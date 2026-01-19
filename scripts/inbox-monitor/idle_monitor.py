#!/usr/bin/env python3
"""
IMAP IDLE Monitor for CCPM Meeting Agent

Uses IMAP IDLE command for push-based email notifications instead of polling.
When new mail arrives, processes it immediately without delay.

Usage:
    # Run the idle monitor
    python idle_monitor.py

    # Or import and use programmatically
    from idle_monitor import IdleMonitor
    monitor = IdleMonitor(email, password, callback=handle_new_mail)
    monitor.run()
"""

import imaplib
import email
import os
import sys
import time
import signal
import threading
from email.utils import parseaddr
from datetime import datetime, timedelta
from typing import Optional, Callable, List
from dataclasses import dataclass

from monitor import MeetingInvite, InboxMonitor


class IdleMonitor:
    """
    IMAP IDLE-based monitor for real-time email notifications.

    Instead of polling every N seconds, this keeps a persistent connection
    and gets notified immediately when new mail arrives.
    """

    def __init__(
        self,
        email_address: str,
        app_password: str,
        on_invite: Optional[Callable[[MeetingInvite], None]] = None,
        idle_timeout: int = 29 * 60,  # Gmail requires re-IDLE every 29 min
        reconnect_delay: int = 5
    ):
        """
        Initialize IDLE monitor.

        Args:
            email_address: Gmail address
            app_password: Gmail App Password
            on_invite: Callback function called for each new meeting invite
            idle_timeout: Seconds before re-issuing IDLE (Gmail max is 29 min)
            reconnect_delay: Seconds to wait before reconnecting after error
        """
        self.email_address = email_address
        self.app_password = app_password
        self.on_invite = on_invite
        self.idle_timeout = idle_timeout
        self.reconnect_delay = reconnect_delay

        self.mail: Optional[imaplib.IMAP4_SSL] = None
        self.running = False
        self.last_seen_uid = None

        # Use InboxMonitor for parsing logic
        self._parser = InboxMonitor(email_address, app_password)

    def connect(self) -> bool:
        """Establish IMAP connection"""
        try:
            self.mail = imaplib.IMAP4_SSL("imap.gmail.com", 993)
            self.mail.login(self.email_address, self.app_password)
            self.mail.select("INBOX")
            print(f"✅ IDLE Monitor connected as {self.email_address}")
            return True
        except imaplib.IMAP4.error as e:
            print(f"❌ IMAP login failed: {e}")
            return False
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False

    def disconnect(self):
        """Close IMAP connection"""
        if self.mail:
            try:
                self.mail.close()
                self.mail.logout()
            except:
                pass
            self.mail = None

    def _get_latest_uid(self) -> Optional[str]:
        """Get the UID of the most recent message"""
        try:
            _, data = self.mail.uid('search', None, 'ALL')
            uids = data[0].split()
            return uids[-1] if uids else None
        except:
            return None

    def _process_new_messages(self, since_uid: Optional[str] = None):
        """Process any new messages since the given UID"""
        try:
            # Search for recent messages
            since_date = (datetime.now() - timedelta(days=1)).strftime("%d-%b-%Y")
            _, data = self.mail.uid('search', None, f'(SINCE {since_date})')
            uids = data[0].split()

            if not uids:
                return

            # If we have a since_uid, only process messages after it
            if since_uid:
                try:
                    since_idx = uids.index(since_uid)
                    uids = uids[since_idx + 1:]
                except ValueError:
                    # since_uid not found, process all recent
                    pass

            for uid in uids:
                self._process_message(uid)
                self.last_seen_uid = uid

        except Exception as e:
            print(f"❌ Error processing messages: {e}")

    def _process_message(self, uid: bytes):
        """Process a single message by UID"""
        try:
            _, data = self.mail.uid('fetch', uid, '(RFC822)')
            if not data or not data[0]:
                return

            raw_email = data[0][1]
            msg = email.message_from_bytes(raw_email)

            # Check for calendar content
            ics_data = None
            for part in msg.walk():
                content_type = part.get_content_type()
                if content_type in ("text/calendar", "application/ics"):
                    ics_data = part.get_payload(decode=True)
                    break
                filename = part.get_filename()
                if filename and filename.endswith(".ics"):
                    ics_data = part.get_payload(decode=True)
                    break

            if not ics_data:
                return  # Not a calendar invite

            # Parse the invite using existing parser
            invite = MeetingInvite()
            invite.message_id = msg.get("Message-ID", "")
            invite.subject = msg.get("Subject", "")
            invite.from_address = parseaddr(msg.get("From", ""))[1]
            invite.to_address = parseaddr(msg.get("To", ""))[1]
            invite.project = self._parser._extract_project_from_address(invite.to_address)

            invite.raw_ics = ics_data.decode("utf-8", errors="ignore")
            parsed = self._parser._parse_ics(ics_data)
            invite.title = parsed["title"] or invite.subject
            invite.start_time = parsed["start_time"]
            invite.end_time = parsed["end_time"]
            invite.location = parsed["location"]
            invite.description = parsed["description"]
            invite.uid = parsed["uid"]
            invite.method = parsed["method"]
            invite.join_url = self._parser._extract_join_url(
                f"{invite.location} {invite.description}"
            )

            # Call the callback
            if self.on_invite:
                print(f"📬 New invite: [{invite.method}] {invite.title}")
                self.on_invite(invite)

        except Exception as e:
            print(f"❌ Error processing message {uid}: {e}")

    def _idle_loop(self):
        """
        Main IDLE loop. Issues IDLE command and waits for notifications.
        """
        while self.running:
            try:
                # Issue IDLE command
                tag = self.mail._new_tag().decode()
                self.mail.send(f'{tag} IDLE\r\n'.encode())

                # Wait for initial continuation response
                response = self.mail.readline()
                if not response.startswith(b'+'):
                    print(f"❌ IDLE not supported: {response}")
                    break

                print(f"👂 Listening for new mail... (timeout: {self.idle_timeout}s)")

                # Wait for data or timeout
                self.mail.sock.settimeout(self.idle_timeout)

                try:
                    while self.running:
                        line = self.mail.readline()
                        if not line:
                            break

                        line_str = line.decode('utf-8', errors='ignore').strip()

                        # Check for EXISTS (new message) notification
                        if 'EXISTS' in line_str:
                            print(f"📨 New mail notification: {line_str}")
                            # Exit IDLE to process
                            break

                        # Check for tagged response (IDLE ended)
                        if line_str.startswith(tag):
                            break

                except TimeoutError:
                    # Normal timeout, re-issue IDLE
                    pass
                except Exception as e:
                    print(f"⚠️  IDLE error: {e}")

                # Send DONE to exit IDLE
                self.mail.send(b'DONE\r\n')

                # Read the tagged response
                while True:
                    line = self.mail.readline()
                    if line.decode('utf-8', errors='ignore').strip().startswith(tag):
                        break

                # Process any new messages
                self._process_new_messages(self.last_seen_uid)

            except Exception as e:
                print(f"❌ IDLE loop error: {e}")
                if self.running:
                    print(f"🔄 Reconnecting in {self.reconnect_delay}s...")
                    time.sleep(self.reconnect_delay)
                    self.disconnect()
                    if not self.connect():
                        continue

    def run(self):
        """
        Start the IDLE monitor. Blocks until stop() is called.
        """
        self.running = True

        # Handle signals for graceful shutdown
        def signal_handler(sig, frame):
            print("\n🛑 Shutting down IDLE monitor...")
            self.stop()

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        print("="*60)
        print("📬 CCPM IDLE Monitor Starting")
        print(f"   Email: {self.email_address}")
        print(f"   IDLE timeout: {self.idle_timeout}s")
        print("   Press Ctrl+C to stop")
        print("="*60)

        while self.running:
            if not self.connect():
                print(f"🔄 Retrying in {self.reconnect_delay}s...")
                time.sleep(self.reconnect_delay)
                continue

            # Get current latest UID to avoid reprocessing old messages
            self.last_seen_uid = self._get_latest_uid()

            # Process any messages that arrived while we were disconnected
            # (only on first connect, subsequent reconnects use last_seen_uid)

            # Enter IDLE loop
            self._idle_loop()

            # If we're still running, we got disconnected - will reconnect
            if self.running:
                print(f"🔄 Connection lost, reconnecting in {self.reconnect_delay}s...")
                self.disconnect()
                time.sleep(self.reconnect_delay)

        self.disconnect()
        print("IDLE Monitor stopped.")

    def stop(self):
        """Stop the IDLE monitor"""
        self.running = False
        # Break out of IDLE by closing socket
        if self.mail:
            try:
                self.mail.sock.shutdown(2)
            except:
                pass


def main():
    """CLI for testing IDLE monitor"""
    import argparse

    parser = argparse.ArgumentParser(description="CCPM IDLE Monitor")
    parser.add_argument("--test", action="store_true", help="Test connection and process recent")
    args = parser.parse_args()

    email_address = os.environ.get("GMAIL_ADDRESS")
    app_password = os.environ.get("GMAIL_APP_PASSWORD")

    if not email_address or not app_password:
        print("❌ Missing credentials. Set:")
        print("   export GMAIL_ADDRESS='your-email@gmail.com'")
        print("   export GMAIL_APP_PASSWORD='your-app-password'")
        sys.exit(1)

    def handle_invite(invite: MeetingInvite):
        """Example callback - just print the invite"""
        print(f"\n{'─'*50}")
        print(f"Method:   {invite.method}")
        print(f"Title:    {invite.title}")
        print(f"Project:  {invite.project}")
        print(f"From:     {invite.from_address}")
        print(f"Start:    {invite.start_time}")
        print(f"Join URL: {invite.join_url or '(none)'}")
        print(f"UID:      {invite.uid[:30]}..." if invite.uid else "UID: (none)")
        print(f"{'─'*50}\n")

    monitor = IdleMonitor(
        email_address=email_address,
        app_password=app_password,
        on_invite=handle_invite
    )

    if args.test:
        # Just connect, process recent, and exit
        if monitor.connect():
            print("Processing recent messages...")
            monitor._process_new_messages()
            monitor.disconnect()
            print("Done.")
    else:
        # Run the IDLE monitor
        monitor.run()


if __name__ == "__main__":
    main()
