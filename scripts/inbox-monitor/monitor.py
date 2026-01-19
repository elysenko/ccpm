#!/usr/bin/env python3
"""
Inbox Monitor for CCPM Meeting Agent

Monitors a Gmail inbox for meeting invites (ICS attachments),
parses them, and routes to the correct project based on To: address.

Usage:
    # Test connection
    python monitor.py --test

    # List recent invites
    python monitor.py --list

    # Run continuous monitor
    python monitor.py --watch
"""

import imaplib
import email
import os
import sys
import json
import argparse
from email.utils import parseaddr
from datetime import datetime
from pathlib import Path
from typing import Optional, Generator

# Optional: icalendar for parsing ICS
try:
    from icalendar import Calendar
    HAS_ICALENDAR = True
except ImportError:
    HAS_ICALENDAR = False
    print("Warning: icalendar not installed. Run: pip install icalendar")


class MeetingInvite:
    """Parsed meeting invite data"""
    def __init__(self):
        self.project: str = ""
        self.to_address: str = ""
        self.from_address: str = ""
        self.subject: str = ""
        self.title: str = ""
        self.start_time: Optional[datetime] = None
        self.end_time: Optional[datetime] = None
        self.location: str = ""
        self.join_url: str = ""
        self.description: str = ""
        self.raw_ics: str = ""
        self.message_id: str = ""
        self.uid: str = ""  # iCalendar UID for RSVP responses
        self.method: str = "REQUEST"  # ICS method: REQUEST, CANCEL, REPLY

    def to_dict(self) -> dict:
        return {
            "project": self.project,
            "to_address": self.to_address,
            "from_address": self.from_address,
            "subject": self.subject,
            "title": self.title,
            "start_time": self.start_time.isoformat() if self.start_time else None,
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "location": self.location,
            "join_url": self.join_url,
            "description": self.description[:500] if self.description else "",
            "message_id": self.message_id,
            "uid": self.uid,
            "method": self.method,
        }

    def __str__(self):
        return (
            f"MeetingInvite(\n"
            f"  project={self.project}\n"
            f"  title={self.title}\n"
            f"  start={self.start_time}\n"
            f"  join_url={self.join_url}\n"
            f")"
        )


class InboxMonitor:
    """Monitor Gmail inbox for meeting invites"""

    def __init__(self, email_address: str, app_password: str, domain: str = "athenconsult.com"):
        self.email_address = email_address
        self.app_password = app_password
        self.domain = domain
        self.mail: Optional[imaplib.IMAP4_SSL] = None

    def connect(self) -> bool:
        """Connect to Gmail IMAP"""
        try:
            self.mail = imaplib.IMAP4_SSL("imap.gmail.com", 993)
            self.mail.login(self.email_address, self.app_password)
            print(f"✅ Connected to Gmail as {self.email_address}")
            return True
        except imaplib.IMAP4.error as e:
            print(f"❌ IMAP login failed: {e}")
            print("   Make sure you're using an App Password, not your regular password")
            print("   Get one at: https://myaccount.google.com/apppasswords")
            return False
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False

    def disconnect(self):
        """Close IMAP connection"""
        if self.mail:
            try:
                self.mail.logout()
            except:
                pass

    def _extract_project_from_address(self, to_address: str) -> str:
        """Extract project name from To: address

        e.g., 'cattle-erp@athenconsult.com' -> 'cattle-erp'
        """
        if "@" in to_address:
            local_part = to_address.split("@")[0]
            return local_part
        return "unknown"

    def _extract_join_url(self, text: str) -> str:
        """Extract meeting join URL from text"""
        import re

        # Google Meet
        match = re.search(r'https://meet\.google\.com/[a-z-]+', text)
        if match:
            return match.group(0)

        # Zoom
        match = re.search(r'https://[a-z0-9]+\.zoom\.us/j/\d+', text)
        if match:
            return match.group(0)

        # Microsoft Teams
        match = re.search(r'https://teams\.microsoft\.com/l/meetup-join/[^\s"<>]+', text)
        if match:
            return match.group(0)

        return ""

    def _parse_ics(self, ics_data: bytes) -> dict:
        """Parse ICS calendar data"""
        result = {
            "title": "",
            "start_time": None,
            "end_time": None,
            "location": "",
            "description": "",
            "uid": "",
            "method": "REQUEST",  # Default to REQUEST
        }

        if not HAS_ICALENDAR:
            # Fallback: basic regex parsing
            ics_text = ics_data.decode("utf-8", errors="ignore")
            import re

            summary = re.search(r'SUMMARY[^:]*:(.+)', ics_text)
            if summary:
                result["title"] = summary.group(1).strip()

            location = re.search(r'LOCATION[^:]*:(.+)', ics_text)
            if location:
                result["location"] = location.group(1).strip()

            description = re.search(r'DESCRIPTION[^:]*:(.+?)(?=\r?\n[A-Z])', ics_text, re.DOTALL)
            if description:
                result["description"] = description.group(1).strip()

            uid = re.search(r'UID[^:]*:(.+)', ics_text)
            if uid:
                result["uid"] = uid.group(1).strip()

            method = re.search(r'METHOD[^:]*:(.+)', ics_text)
            if method:
                result["method"] = method.group(1).strip().upper()

            return result

        # Parse with icalendar library
        try:
            cal = Calendar.from_ical(ics_data)

            # Get METHOD from calendar (not event)
            method = cal.get("METHOD")
            if method:
                result["method"] = str(method).upper()

            for component in cal.walk():
                if component.name == "VEVENT":
                    result["title"] = str(component.get("SUMMARY", ""))
                    result["location"] = str(component.get("LOCATION", ""))
                    result["description"] = str(component.get("DESCRIPTION", ""))
                    result["uid"] = str(component.get("UID", ""))

                    dtstart = component.get("DTSTART")
                    if dtstart:
                        dt = dtstart.dt
                        if hasattr(dt, 'date'):
                            result["start_time"] = dt
                        else:
                            result["start_time"] = datetime.combine(dt, datetime.min.time())

                    dtend = component.get("DTEND")
                    if dtend:
                        dt = dtend.dt
                        if hasattr(dt, 'date'):
                            result["end_time"] = dt
                        else:
                            result["end_time"] = datetime.combine(dt, datetime.min.time())

                    break
        except Exception as e:
            print(f"Warning: ICS parse error: {e}")

        return result

    def fetch_invites(self, folder: str = "INBOX", unread_only: bool = False, days_back: int = 7) -> Generator[MeetingInvite, None, None]:
        """Fetch meeting invites from inbox"""
        if not self.mail:
            raise RuntimeError("Not connected. Call connect() first.")

        self.mail.select(folder)

        # Search for recent emails (much faster than scanning all)
        from datetime import timedelta
        since_date = (datetime.now() - timedelta(days=days_back)).strftime("%d-%b-%Y")

        if unread_only:
            search_criteria = f'(UNSEEN SINCE {since_date})'
        else:
            search_criteria = f'(SINCE {since_date})'

        _, message_numbers = self.mail.search(None, search_criteria)

        for num in message_numbers[0].split():
            _, data = self.mail.fetch(num, "(RFC822)")
            raw_email = data[0][1]
            msg = email.message_from_bytes(raw_email)

            # Check if this email has an ICS attachment or is a calendar invite
            has_ics = False
            ics_data = None

            for part in msg.walk():
                content_type = part.get_content_type()

                # Look for ICS content
                if content_type == "text/calendar" or content_type == "application/ics":
                    has_ics = True
                    ics_data = part.get_payload(decode=True)
                    break

                # Sometimes ICS is an attachment
                filename = part.get_filename()
                if filename and filename.endswith(".ics"):
                    has_ics = True
                    ics_data = part.get_payload(decode=True)
                    break

            if not has_ics:
                continue

            # Parse the invite
            invite = MeetingInvite()
            invite.message_id = msg.get("Message-ID", "")
            invite.subject = msg.get("Subject", "")
            invite.from_address = parseaddr(msg.get("From", ""))[1]
            invite.to_address = parseaddr(msg.get("To", ""))[1]
            invite.project = self._extract_project_from_address(invite.to_address)

            if ics_data:
                invite.raw_ics = ics_data.decode("utf-8", errors="ignore")
                parsed = self._parse_ics(ics_data)
                invite.title = parsed["title"] or invite.subject
                invite.start_time = parsed["start_time"]
                invite.end_time = parsed["end_time"]
                invite.location = parsed["location"]
                invite.description = parsed["description"]
                invite.uid = parsed["uid"]
                invite.method = parsed["method"]

                # Extract join URL from location or description
                invite.join_url = self._extract_join_url(
                    f"{invite.location} {invite.description}"
                )

            yield invite

    def list_invites(self, limit: int = 10) -> list[MeetingInvite]:
        """List recent meeting invites"""
        invites = []
        for invite in self.fetch_invites():
            invites.append(invite)
            if len(invites) >= limit:
                break
        return invites


def main():
    parser = argparse.ArgumentParser(description="CCPM Inbox Monitor")
    parser.add_argument("--test", action="store_true", help="Test IMAP connection")
    parser.add_argument("--list", action="store_true", help="List recent invites")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--limit", type=int, default=10, help="Max invites to list")
    args = parser.parse_args()

    # Get credentials from environment
    email_address = os.environ.get("GMAIL_ADDRESS")
    app_password = os.environ.get("GMAIL_APP_PASSWORD")

    if not email_address or not app_password:
        print("❌ Missing credentials. Set environment variables:")
        print("   export GMAIL_ADDRESS='your-email@gmail.com'")
        print("   export GMAIL_APP_PASSWORD='your-app-password'")
        sys.exit(1)

    monitor = InboxMonitor(email_address, app_password)

    if args.test:
        success = monitor.connect()
        monitor.disconnect()
        sys.exit(0 if success else 1)

    if args.list:
        if not monitor.connect():
            sys.exit(1)

        invites = monitor.list_invites(limit=args.limit)

        if args.json:
            print(json.dumps([inv.to_dict() for inv in invites], indent=2, default=str))
        else:
            print(f"\nFound {len(invites)} meeting invite(s):\n")
            for inv in invites:
                print(f"{'─' * 50}")
                print(f"Project:  {inv.project}")
                print(f"Title:    {inv.title}")
                print(f"From:     {inv.from_address}")
                print(f"To:       {inv.to_address}")
                print(f"Start:    {inv.start_time}")
                print(f"Join URL: {inv.join_url or '(not found)'}")

        monitor.disconnect()
        sys.exit(0)

    # Default: show help
    parser.print_help()


if __name__ == "__main__":
    main()
