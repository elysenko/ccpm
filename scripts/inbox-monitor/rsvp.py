#!/usr/bin/env python3
"""
RSVP Sender for CCPM Meeting Agent

Sends iCalendar REPLY responses (Accept/Decline) to meeting invites via SMTP.
Uses Gmail's SMTP server with App Passwords for authentication.
"""

import smtplib
import os
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
from datetime import datetime
from typing import Optional

from icalendar import Calendar, Event

from monitor import MeetingInvite


class RSVPSender:
    """Send iCalendar RSVP responses via SMTP."""

    def __init__(self, email: str, app_password: str, smtp_host: str = "smtp.gmail.com", smtp_port: int = 587):
        """
        Initialize RSVP sender.

        Args:
            email: Sender email address (the bot's email)
            app_password: Gmail App Password for SMTP authentication
            smtp_host: SMTP server hostname
            smtp_port: SMTP server port
        """
        self.email = email
        self.app_password = app_password
        self.smtp_host = smtp_host
        self.smtp_port = smtp_port

    def send_rsvp(self, invite: MeetingInvite, accepted: bool, reason: str = "") -> bool:
        """
        Send RSVP response to meeting organizer.

        Args:
            invite: The meeting invite to respond to
            accepted: True to accept, False to decline
            reason: Optional reason for declining

        Returns:
            True if sent successfully, False otherwise
        """
        if not invite.uid:
            print(f"⚠️  Cannot send RSVP: No UID in invite for '{invite.title}'")
            return False

        if not invite.from_address:
            print(f"⚠️  Cannot send RSVP: No organizer address for '{invite.title}'")
            return False

        try:
            # Create iCalendar REPLY
            cal = Calendar()
            cal.add('prodid', '-//CCPM Meeting Bot//EN')
            cal.add('version', '2.0')
            cal.add('method', 'REPLY')

            event = Event()
            event.add('uid', invite.uid)  # Must match original invite UID
            event.add('dtstamp', datetime.utcnow())

            if invite.start_time:
                event.add('dtstart', invite.start_time)
            if invite.end_time:
                event.add('dtend', invite.end_time)

            event.add('summary', invite.title)
            event.add('organizer', f'mailto:{invite.from_address}')

            # PARTSTAT: ACCEPTED, DECLINED, or TENTATIVE
            partstat = 'ACCEPTED' if accepted else 'DECLINED'
            event.add('attendee', f'mailto:{invite.to_address}',
                      parameters={'partstat': partstat, 'cn': 'CCPM Meeting Bot'})

            cal.add_component(event)

            # Create email message
            msg = MIMEMultipart('mixed')
            msg['From'] = self.email
            msg['To'] = invite.from_address
            msg['Subject'] = f"{'Accepted' if accepted else 'Declined'}: {invite.title}"

            # Text body
            status_text = 'accepted' if accepted else 'declined'
            body = f"CCPM Meeting Bot has {status_text} this meeting invitation.\n"
            body += f"\nMeeting: {invite.title}\n"
            if invite.start_time:
                body += f"Time: {invite.start_time.strftime('%Y-%m-%d %H:%M %Z')}\n"
            if reason:
                body += f"\nReason: {reason}\n"
            body += "\n---\nThis is an automated response from the CCPM Meeting Bot."

            msg.attach(MIMEText(body, 'plain'))

            # iCalendar attachment with correct content type for REPLY
            ics_content = cal.to_ical()
            ics_part = MIMEBase('text', 'calendar', method='REPLY')
            ics_part.set_payload(ics_content)
            encoders.encode_base64(ics_part)
            ics_part.add_header('Content-Disposition', 'attachment', filename='response.ics')
            msg.attach(ics_part)

            # Send via SMTP
            with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
                server.starttls()
                server.login(self.email, self.app_password)
                server.send_message(msg)

            status_emoji = "✅" if accepted else "❌"
            print(f"{status_emoji} RSVP sent: {status_text.capitalize()} '{invite.title}' to {invite.from_address}")
            return True

        except smtplib.SMTPAuthenticationError as e:
            print(f"❌ SMTP auth failed: {e}")
            print("   Check your Gmail App Password")
            return False
        except smtplib.SMTPException as e:
            print(f"❌ SMTP error sending RSVP: {e}")
            return False
        except Exception as e:
            print(f"❌ Failed to send RSVP: {e}")
            return False

    def accept(self, invite: MeetingInvite) -> bool:
        """Accept a meeting invite."""
        return self.send_rsvp(invite, accepted=True)

    def decline(self, invite: MeetingInvite, reason: str = "") -> bool:
        """Decline a meeting invite with optional reason."""
        return self.send_rsvp(invite, accepted=False, reason=reason)


def main():
    """CLI for testing RSVP functionality."""
    import argparse

    parser = argparse.ArgumentParser(description="CCPM RSVP Sender")
    parser.add_argument("--test", action="store_true", help="Send a test RSVP")
    args = parser.parse_args()

    email = os.environ.get("GMAIL_ADDRESS")
    app_password = os.environ.get("GMAIL_APP_PASSWORD")

    if not email or not app_password:
        print("❌ Missing credentials. Set:")
        print("   export GMAIL_ADDRESS='your-email@gmail.com'")
        print("   export GMAIL_APP_PASSWORD='your-app-password'")
        return

    if args.test:
        # Create a test invite
        invite = MeetingInvite()
        invite.uid = "test-uid-12345@example.com"
        invite.title = "Test Meeting"
        invite.from_address = email  # Send to ourselves for testing
        invite.to_address = email
        invite.start_time = datetime.now()

        rsvp = RSVPSender(email, app_password)
        success = rsvp.accept(invite)
        print(f"Test RSVP {'succeeded' if success else 'failed'}")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
