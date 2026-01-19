#!/usr/bin/env python3
"""
Meeting Scheduler - Monitors inbox, stores in calendar, triggers joins

This is the main service that:
1. Polls inbox for new meeting invites
2. Stores them in the calendar database
3. Checks for meetings about to start
4. Triggers the meeting bot to join
"""

import os
import sys
import time
import signal
import argparse
from datetime import datetime, timedelta
from pathlib import Path

from monitor import InboxMonitor, MeetingInvite
from calendar import MeetingCalendar, Meeting


class MeetingScheduler:
    """Main scheduler service"""

    def __init__(
        self,
        email_address: str,
        app_password: str,
        db_path: str = "meetings.db",
        poll_interval: int = 60,
        join_before_minutes: int = 1
    ):
        self.inbox = InboxMonitor(email_address, app_password)
        self.calendar = MeetingCalendar(db_path)
        self.poll_interval = poll_interval
        self.join_before_minutes = join_before_minutes
        self.running = False

    def sync_inbox(self) -> int:
        """Sync new invites from inbox to calendar. Returns count of new meetings."""
        if not self.inbox.connect():
            print("❌ Failed to connect to inbox")
            return 0

        new_count = 0
        try:
            for invite in self.inbox.fetch_invites(unread_only=False, days_back=14):
                # Skip if no join URL
                if not invite.join_url:
                    continue

                # Skip if no start time
                if not invite.start_time:
                    continue

                # Create meeting from invite
                meeting = Meeting(
                    id=None,
                    project=invite.project,
                    title=invite.title,
                    start_time=invite.start_time,
                    end_time=invite.end_time,
                    join_url=invite.join_url,
                    platform="",  # Will be auto-detected
                    from_address=invite.from_address,
                    to_address=invite.to_address,
                    status="pending",
                    message_id=invite.message_id,
                    created_at=datetime.now().astimezone(),
                    raw_ics=invite.raw_ics
                )

                # Try to add (will return None if duplicate)
                meeting_id = self.calendar.add_meeting(meeting)
                if meeting_id:
                    new_count += 1
                    print(f"📅 Added: {meeting.title} ({meeting.project}) @ {meeting.start_time:%Y-%m-%d %H:%M}")

        finally:
            self.inbox.disconnect()

        return new_count

    def check_upcoming(self) -> list[Meeting]:
        """Check for meetings about to start"""
        upcoming = self.calendar.get_upcoming(minutes_ahead=self.join_before_minutes + 1)
        return upcoming

    def trigger_join(self, meeting: Meeting):
        """Trigger the bot to join a meeting"""
        print(f"\n{'='*60}")
        print(f"🚀 TIME TO JOIN MEETING!")
        print(f"   Project:  {meeting.project}")
        print(f"   Title:    {meeting.title}")
        print(f"   Platform: {meeting.platform}")
        print(f"   URL:      {meeting.join_url}")
        print(f"{'='*60}\n")

        # Update status to joining
        self.calendar.update_status(meeting.id, "joining")

        # TODO: Actually launch the meeting bot here
        # For now, just print what we would do
        #
        # In the future, this will:
        # 1. Launch Playwright bot to join the meeting URL
        # 2. Start recording audio
        # 3. When meeting ends, trigger transcription
        # 4. Extract action items
        # 5. Send email for verification

        # For now, mark as joined (simulated)
        self.calendar.update_status(meeting.id, "joined")

    def run_once(self):
        """Run one cycle: sync inbox + check upcoming"""
        print(f"\n[{datetime.now():%H:%M:%S}] Checking...")

        # Sync inbox
        new_meetings = self.sync_inbox()
        if new_meetings:
            print(f"   ✅ Added {new_meetings} new meeting(s)")

        # Check for meetings to join
        upcoming = self.check_upcoming()
        for meeting in upcoming:
            self.trigger_join(meeting)

        # Show next pending meeting
        pending = self.calendar.get_all_pending()
        if pending:
            next_meeting = pending[0]
            time_until = next_meeting.start_time - datetime.now().astimezone()
            mins = int(time_until.total_seconds() / 60)
            if mins > 0:
                print(f"   ⏰ Next meeting in {mins} min: {next_meeting.title}")
            else:
                print(f"   ⏰ Meeting starting now: {next_meeting.title}")

    def run(self):
        """Run continuous scheduler loop"""
        self.running = True

        def signal_handler(sig, frame):
            print("\n\n🛑 Shutting down scheduler...")
            self.running = False

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        print("="*60)
        print("🗓️  CCPM Meeting Scheduler Started")
        print(f"   Polling every {self.poll_interval} seconds")
        print(f"   Will join meetings {self.join_before_minutes} min before start")
        print("   Press Ctrl+C to stop")
        print("="*60)

        while self.running:
            try:
                self.run_once()
            except Exception as e:
                print(f"❌ Error: {e}")

            # Wait for next cycle
            for _ in range(self.poll_interval):
                if not self.running:
                    break
                time.sleep(1)

        print("Scheduler stopped.")


def main():
    parser = argparse.ArgumentParser(description="CCPM Meeting Scheduler")
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    parser.add_argument("--sync", action="store_true", help="Just sync inbox to calendar")
    parser.add_argument("--poll", type=int, default=60, help="Poll interval in seconds")
    parser.add_argument("--db", default="meetings.db", help="Database path")
    args = parser.parse_args()

    # Get credentials
    email_address = os.environ.get("GMAIL_ADDRESS")
    app_password = os.environ.get("GMAIL_APP_PASSWORD")

    if not email_address or not app_password:
        print("❌ Missing credentials. Set:")
        print("   export GMAIL_ADDRESS='your-email@gmail.com'")
        print("   export GMAIL_APP_PASSWORD='your-app-password'")
        sys.exit(1)

    scheduler = MeetingScheduler(
        email_address=email_address,
        app_password=app_password,
        db_path=args.db,
        poll_interval=args.poll
    )

    if args.sync:
        count = scheduler.sync_inbox()
        print(f"\n✅ Synced {count} new meeting(s)")
    elif args.once:
        scheduler.run_once()
    else:
        scheduler.run()


if __name__ == "__main__":
    main()
