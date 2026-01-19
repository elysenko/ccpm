#!/usr/bin/env python3
"""
Meeting Scheduler - Kubernetes/PostgreSQL Version

This is the main service that:
1. Polls inbox for new meeting invites
2. Stores them in PostgreSQL
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
from calendar_pg import MeetingCalendar, Meeting
from rsvp import RSVPSender
from idle_monitor import IdleMonitor


class MeetingScheduler:
    """Main scheduler service"""

    def __init__(
        self,
        email_address: str,
        app_password: str,
        database_url: str = None,
        poll_interval: int = 60,
        join_before_minutes: int = 1,
        send_rsvp: bool = True
    ):
        self.inbox = InboxMonitor(email_address, app_password)
        self.calendar = MeetingCalendar(database_url)
        self.rsvp = RSVPSender(email_address, app_password) if send_rsvp else None
        self.poll_interval = poll_interval
        self.join_before_minutes = join_before_minutes
        self.send_rsvp = send_rsvp
        self.running = False

    def sync_inbox(self) -> int:
        """Sync new invites from inbox to calendar. Returns count of new meetings."""
        if not self.inbox.connect():
            print("❌ Failed to connect to inbox")
            return 0

        new_count = 0
        cancelled_count = 0
        try:
            for invite in self.inbox.fetch_invites(unread_only=False, days_back=14):
                # Handle cancellations first
                if invite.method == "CANCEL":
                    self._handle_cancellation(invite)
                    cancelled_count += 1
                    continue

                # Skip if no join URL (for new invites)
                if not invite.join_url:
                    continue

                # Skip if no start time
                if not invite.start_time:
                    continue

                # Check if meeting has already ended
                now = datetime.now().astimezone()
                if invite.end_time and invite.end_time < now:
                    # Meeting already ended - record it as missed, don't RSVP
                    meeting = Meeting(
                        id=None,
                        project=invite.project,
                        title=invite.title,
                        start_time=invite.start_time,
                        end_time=invite.end_time,
                        join_url=invite.join_url,
                        platform="",
                        from_address=invite.from_address,
                        to_address=invite.to_address,
                        status="missed",
                        message_id=invite.message_id,
                        created_at=datetime.now().astimezone(),
                        raw_ics=invite.raw_ics,
                        uid=invite.uid
                    )
                    meeting_id = self.calendar.add_meeting(meeting)
                    if meeting_id:
                        print(f"⏰ Meeting already ended, marking as missed: {invite.title}")
                    continue

                # Check for conflicts with existing meetings
                conflicts = self.calendar.check_conflicts(
                    invite.start_time,
                    invite.end_time
                )

                if conflicts:
                    # Decline with reason listing conflicting meetings
                    conflict_titles = ", ".join(m.title for m in conflicts[:3])
                    if len(conflicts) > 3:
                        conflict_titles += f" (+{len(conflicts) - 3} more)"
                    reason = f"Scheduling conflict with: {conflict_titles}"

                    # Create meeting record with declined status
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
                        status="declined",
                        message_id=invite.message_id,
                        created_at=datetime.now().astimezone(),
                        raw_ics=invite.raw_ics,
                        uid=invite.uid
                    )

                    meeting_id = self.calendar.add_meeting(meeting)
                    if meeting_id:
                        print(f"⚠️  Declined: {meeting.title} (conflict with {len(conflicts)} meeting(s))")
                        # Send decline RSVP
                        if self.rsvp:
                            self.rsvp.decline(invite, reason=reason)
                else:
                    # No conflicts - accept the meeting
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
                        raw_ics=invite.raw_ics,
                        uid=invite.uid
                    )

                    meeting_id = self.calendar.add_meeting(meeting)
                    if meeting_id:
                        new_count += 1
                        print(f"📅 Accepted: {meeting.title} ({meeting.project}) @ {meeting.start_time:%Y-%m-%d %H:%M}")
                        # Send accept RSVP
                        if self.rsvp:
                            self.rsvp.accept(invite)

        finally:
            self.inbox.disconnect()

        if cancelled_count > 0:
            print(f"   🗑️  Processed {cancelled_count} cancellation(s)")

        return new_count

    def _handle_cancellation(self, invite: MeetingInvite):
        """Handle a meeting cancellation by updating the existing meeting status."""
        if not invite.uid:
            print(f"⚠️  Cancellation without UID: {invite.title}")
            return

        # Find the existing meeting by UID
        existing = self.calendar.get_by_uid(invite.uid)
        if existing:
            if existing.status not in ('cancelled', 'completed'):
                self.calendar.update_status(existing.id, "cancelled")
                print(f"🗑️  Cancelled: {existing.title} ({existing.project})")
            else:
                # Already cancelled or completed, skip
                pass
        else:
            # No matching meeting found - might be for a meeting we declined or never saw
            print(f"⚠️  Cancellation for unknown meeting: {invite.title} (UID: {invite.uid[:20]}...)")

    def check_upcoming(self) -> list[Meeting]:
        """Check for meetings about to start"""
        upcoming = self.calendar.get_upcoming(minutes_ahead=self.join_before_minutes + 1)
        return upcoming

    def trigger_join(self, meeting: Meeting):
        """Trigger the bot to join a meeting by creating a K8s Job"""
        print(f"\n{'='*60}")
        print(f"🚀 TIME TO JOIN MEETING!")
        print(f"   Project:  {meeting.project}")
        print(f"   Title:    {meeting.title}")
        print(f"   Platform: {meeting.platform}")
        print(f"   URL:      {meeting.join_url}")
        print(f"{'='*60}\n")

        # Update status to joining
        self.calendar.update_status(meeting.id, "joining")

        # Spawn meeting-bot K8s Job
        try:
            from kubernetes import client, config

            # Load in-cluster config (running inside K8s)
            try:
                config.load_incluster_config()
            except:
                # Fallback for local testing
                config.load_kube_config()

            batch_v1 = client.BatchV1Api()

            job_name = f"meeting-bot-{meeting.id}"
            namespace = "robert"

            job = client.V1Job(
                api_version="batch/v1",
                kind="Job",
                metadata=client.V1ObjectMeta(
                    name=job_name,
                    namespace=namespace,
                    labels={
                        "app": "meeting-bot",
                        "project": meeting.project,
                        "meeting-id": str(meeting.id),
                    }
                ),
                spec=client.V1JobSpec(
                    ttl_seconds_after_finished=3600,  # Clean up after 1 hour
                    backoff_limit=0,  # Don't retry
                    template=client.V1PodTemplateSpec(
                        metadata=client.V1ObjectMeta(
                            labels={"app": "meeting-bot"}
                        ),
                        spec=client.V1PodSpec(
                            restart_policy="Never",
                            containers=[
                                client.V1Container(
                                    name="bot",
                                    image="ubuntu.desmana-truck.ts.net:30500/meeting-bot:v3-postgres",
                                    image_pull_policy="Always",
                                    env=[
                                        client.V1EnvVar(name="MEETING_URL", value=meeting.join_url),
                                        client.V1EnvVar(name="PROJECT", value=meeting.project),
                                        client.V1EnvVar(name="OUTPUT_DIR", value="/app/output"),
                                        client.V1EnvVar(name="MEETING_ID", value=str(meeting.id)),
                                        client.V1EnvVar(name="DATABASE_URL", value=os.environ.get("DATABASE_URL", "")),
                                    ],
                                    resources=client.V1ResourceRequirements(
                                        requests={"memory": "1Gi", "cpu": "1"},
                                        limits={"memory": "2Gi", "cpu": "2"}
                                    ),
                                    security_context=client.V1SecurityContext(
                                        capabilities=client.V1Capabilities(add=["SYS_ADMIN"])
                                    ),
                                    volume_mounts=[
                                        client.V1VolumeMount(name="dshm", mount_path="/dev/shm")
                                    ]
                                )
                            ],
                            volumes=[
                                client.V1Volume(
                                    name="dshm",
                                    empty_dir=client.V1EmptyDirVolumeSource(
                                        medium="Memory",
                                        size_limit="1Gi"
                                    )
                                )
                            ]
                        )
                    )
                )
            )

            batch_v1.create_namespaced_job(namespace=namespace, body=job)
            print(f"✅ Created K8s Job: {job_name}")
            self.calendar.update_status(meeting.id, "bot_spawned")

        except Exception as e:
            print(f"❌ Failed to create K8s Job: {e}")
            import traceback
            traceback.print_exc()
            self.calendar.update_status(meeting.id, "spawn_failed")

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
        else:
            print(f"   📭 No pending meetings")

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
        print(f"   Database: {'PostgreSQL' if self.calendar.use_postgres else 'SQLite'}")
        print(f"   Polling every {self.poll_interval} seconds")
        print(f"   Will join meetings {self.join_before_minutes} min before start")
        print(f"   Auto RSVP: {'Enabled' if self.send_rsvp else 'Disabled'}")
        print("   Press Ctrl+C to stop")
        print("="*60)

        while self.running:
            try:
                self.run_once()
            except Exception as e:
                print(f"❌ Error: {e}")
                import traceback
                traceback.print_exc()

            # Wait for next cycle
            for _ in range(self.poll_interval):
                if not self.running:
                    break
                time.sleep(1)

        print("Scheduler stopped.")

    def process_invite(self, invite: MeetingInvite):
        """
        Process a single invite (callback for IDLE monitor).
        This is the push-based equivalent of sync_inbox().
        """
        # Handle cancellations
        if invite.method == "CANCEL":
            self._handle_cancellation(invite)
            return

        # Skip if no join URL
        if not invite.join_url:
            print(f"⚠️  Skipping invite without join URL: {invite.title}")
            return

        # Skip if no start time
        if not invite.start_time:
            print(f"⚠️  Skipping invite without start time: {invite.title}")
            return

        # Check if meeting has already ended
        now = datetime.now().astimezone()
        if invite.end_time and invite.end_time < now:
            # Meeting already ended - record it as missed, don't RSVP
            meeting = Meeting(
                id=None,
                project=invite.project,
                title=invite.title,
                start_time=invite.start_time,
                end_time=invite.end_time,
                join_url=invite.join_url,
                platform="",
                from_address=invite.from_address,
                to_address=invite.to_address,
                status="missed",
                message_id=invite.message_id,
                created_at=datetime.now().astimezone(),
                raw_ics=invite.raw_ics,
                uid=invite.uid
            )
            meeting_id = self.calendar.add_meeting(meeting)
            if meeting_id:
                print(f"⏰ Meeting already ended, marking as missed: {invite.title}")
            return

        # Check for conflicts
        conflicts = self.calendar.check_conflicts(
            invite.start_time,
            invite.end_time
        )

        if conflicts:
            conflict_titles = ", ".join(m.title for m in conflicts[:3])
            if len(conflicts) > 3:
                conflict_titles += f" (+{len(conflicts) - 3} more)"
            reason = f"Scheduling conflict with: {conflict_titles}"

            meeting = Meeting(
                id=None,
                project=invite.project,
                title=invite.title,
                start_time=invite.start_time,
                end_time=invite.end_time,
                join_url=invite.join_url,
                platform="",
                from_address=invite.from_address,
                to_address=invite.to_address,
                status="declined",
                message_id=invite.message_id,
                created_at=datetime.now().astimezone(),
                raw_ics=invite.raw_ics,
                uid=invite.uid
            )

            meeting_id = self.calendar.add_meeting(meeting)
            if meeting_id:
                print(f"⚠️  Declined: {meeting.title} (conflict with {len(conflicts)} meeting(s))")
                if self.rsvp:
                    self.rsvp.decline(invite, reason=reason)
        else:
            meeting = Meeting(
                id=None,
                project=invite.project,
                title=invite.title,
                start_time=invite.start_time,
                end_time=invite.end_time,
                join_url=invite.join_url,
                platform="",
                from_address=invite.from_address,
                to_address=invite.to_address,
                status="pending",
                message_id=invite.message_id,
                created_at=datetime.now().astimezone(),
                raw_ics=invite.raw_ics,
                uid=invite.uid
            )

            meeting_id = self.calendar.add_meeting(meeting)
            if meeting_id:
                print(f"📅 Accepted: {meeting.title} ({meeting.project}) @ {meeting.start_time:%Y-%m-%d %H:%M}")
                if self.rsvp:
                    self.rsvp.accept(invite)

                # Check if we should join immediately
                now = datetime.now().astimezone()
                time_until = meeting.start_time - now

                # Case 1: Meeting starts soon
                if time_until.total_seconds() < (self.join_before_minutes + 1) * 60 and time_until.total_seconds() >= 0:
                    print(f"⚡ Meeting starting soon, checking if we should join...")
                    self._check_and_join_upcoming()
                # Case 2: Meeting already started but still ongoing
                elif time_until.total_seconds() < 0:
                    meeting_end = meeting.end_time
                    if meeting_end is None or meeting_end > now:
                        print(f"📍 Meeting already in progress, joining immediately: {meeting.title}")
                        self._check_and_join_upcoming()
                    else:
                        print(f"⏰ Meeting already ended: {meeting.title}")

    def _check_and_join_upcoming(self):
        """Check for and join any upcoming meetings"""
        upcoming = self.check_upcoming()
        for meeting in upcoming:
            self.trigger_join(meeting)

    def run_idle(self):
        """
        Run scheduler with IMAP IDLE (push-based) instead of polling.
        New invites are processed immediately when they arrive.
        """
        self.running = True

        def signal_handler(sig, frame):
            print("\n\n🛑 Shutting down scheduler...")
            self.running = False
            if hasattr(self, '_idle_monitor'):
                self._idle_monitor.stop()

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        print("="*60)
        print("🗓️  CCPM Meeting Scheduler Started (IDLE Mode)")
        print(f"   Database: {'PostgreSQL' if self.calendar.use_postgres else 'SQLite'}")
        print(f"   Mode: Push-based (IMAP IDLE)")
        print(f"   Will join meetings {self.join_before_minutes} min before start")
        print(f"   Auto RSVP: {'Enabled' if self.send_rsvp else 'Disabled'}")
        print("   Press Ctrl+C to stop")
        print("="*60)

        # Initial inbox sync to catch emails that arrived before we started
        print("\n📥 Initial inbox sync...")
        try:
            count = self.sync_inbox()
            print(f"   Processed {count} new invite(s)")
        except Exception as e:
            print(f"   Warning: Initial sync failed: {e}")

        # Create IDLE monitor with our callback
        self._idle_monitor = IdleMonitor(
            email_address=self.inbox.email_address,
            app_password=self.inbox.app_password,
            on_invite=self.process_invite
        )

        # Start a background thread to check for upcoming meetings periodically
        # (in case a meeting was scheduled before we started)
        import threading

        def check_upcoming_loop():
            while self.running:
                try:
                    self._check_and_join_upcoming()
                except Exception as e:
                    print(f"❌ Error checking upcoming: {e}")
                # Check every 30 seconds
                for _ in range(30):
                    if not self.running:
                        break
                    time.sleep(1)

        upcoming_thread = threading.Thread(target=check_upcoming_loop, daemon=True)
        upcoming_thread.start()

        # Run the IDLE monitor (this blocks)
        self._idle_monitor.run()

        print("Scheduler stopped.")


def main():
    parser = argparse.ArgumentParser(description="CCPM Meeting Scheduler")
    parser.add_argument("--once", action="store_true", help="Run once and exit")
    parser.add_argument("--sync", action="store_true", help="Just sync inbox to calendar")
    parser.add_argument("--idle", action="store_true", help="Use IMAP IDLE (push-based) instead of polling")
    parser.add_argument("--poll", type=int, default=60, help="Poll interval in seconds (ignored with --idle)")
    parser.add_argument("--no-rsvp", action="store_true", help="Disable automatic RSVP responses")
    args = parser.parse_args()

    # Get credentials from environment
    email_address = os.environ.get("GMAIL_ADDRESS")
    app_password = os.environ.get("GMAIL_APP_PASSWORD")
    database_url = os.environ.get("DATABASE_URL")

    if not email_address or not app_password:
        print("❌ Missing credentials. Set:")
        print("   export GMAIL_ADDRESS='your-email@gmail.com'")
        print("   export GMAIL_APP_PASSWORD='your-app-password'")
        sys.exit(1)

    scheduler = MeetingScheduler(
        email_address=email_address,
        app_password=app_password,
        database_url=database_url,
        poll_interval=args.poll,
        send_rsvp=not args.no_rsvp
    )

    if args.sync:
        count = scheduler.sync_inbox()
        print(f"\n✅ Synced {count} new meeting(s)")
    elif args.once:
        scheduler.run_once()
    elif args.idle:
        scheduler.run_idle()
    else:
        scheduler.run()


if __name__ == "__main__":
    main()
