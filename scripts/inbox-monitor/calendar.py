#!/usr/bin/env python3
"""
Meeting Calendar - Stores and schedules meeting joins

Uses SQLite for persistence. Tracks:
- Parsed meeting invites
- Meeting status (pending, joined, completed, missed)
- Which project each meeting belongs to
"""

import sqlite3
import json
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, List
from dataclasses import dataclass, asdict


@dataclass
class Meeting:
    """A scheduled meeting"""
    id: Optional[int]
    project: str
    title: str
    start_time: datetime
    end_time: Optional[datetime]
    join_url: str
    platform: str  # google_meet, teams, zoom
    from_address: str
    to_address: str
    status: str  # pending, joining, joined, completed, missed, cancelled
    message_id: str  # Email message ID to avoid duplicates
    created_at: datetime
    raw_ics: str = ""

    def to_dict(self) -> dict:
        d = asdict(self)
        d['start_time'] = self.start_time.isoformat() if self.start_time else None
        d['end_time'] = self.end_time.isoformat() if self.end_time else None
        d['created_at'] = self.created_at.isoformat() if self.created_at else None
        return d


class MeetingCalendar:
    """SQLite-based meeting calendar"""

    def __init__(self, db_path: str = "meetings.db"):
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        """Initialize database schema"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS meetings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    project TEXT NOT NULL,
                    title TEXT NOT NULL,
                    start_time TEXT NOT NULL,
                    end_time TEXT,
                    join_url TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    from_address TEXT,
                    to_address TEXT,
                    status TEXT DEFAULT 'pending',
                    message_id TEXT UNIQUE,
                    created_at TEXT NOT NULL,
                    raw_ics TEXT
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_start_time ON meetings(start_time)
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_status ON meetings(status)
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_project ON meetings(project)
            """)
            conn.commit()

    def _detect_platform(self, join_url: str) -> str:
        """Detect meeting platform from URL"""
        if "meet.google.com" in join_url:
            return "google_meet"
        elif "teams.microsoft.com" in join_url:
            return "teams"
        elif "zoom.us" in join_url:
            return "zoom"
        return "unknown"

    def add_meeting(self, meeting: Meeting) -> Optional[int]:
        """Add a meeting to the calendar. Returns meeting ID or None if duplicate."""
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.execute("""
                    INSERT INTO meetings
                    (project, title, start_time, end_time, join_url, platform,
                     from_address, to_address, status, message_id, created_at, raw_ics)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    meeting.project,
                    meeting.title,
                    meeting.start_time.isoformat(),
                    meeting.end_time.isoformat() if meeting.end_time else None,
                    meeting.join_url,
                    meeting.platform or self._detect_platform(meeting.join_url),
                    meeting.from_address,
                    meeting.to_address,
                    meeting.status,
                    meeting.message_id,
                    meeting.created_at.isoformat(),
                    meeting.raw_ics
                ))
                conn.commit()
                return cursor.lastrowid
        except sqlite3.IntegrityError:
            # Duplicate message_id - meeting already exists
            return None

    def get_upcoming(self, minutes_ahead: int = 5) -> List[Meeting]:
        """Get meetings starting within the next N minutes"""
        now = datetime.now().astimezone()
        cutoff = now + timedelta(minutes=minutes_ahead)

        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("""
                SELECT * FROM meetings
                WHERE status = 'pending'
                AND datetime(start_time) <= datetime(?)
                AND datetime(start_time) >= datetime(?)
                ORDER BY start_time ASC
            """, (cutoff.isoformat(), (now - timedelta(minutes=10)).isoformat()))

            return [self._row_to_meeting(row) for row in cursor.fetchall()]

    def get_all_pending(self) -> List[Meeting]:
        """Get all pending meetings"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("""
                SELECT * FROM meetings
                WHERE status = 'pending'
                ORDER BY start_time ASC
            """)
            return [self._row_to_meeting(row) for row in cursor.fetchall()]

    def get_by_project(self, project: str) -> List[Meeting]:
        """Get all meetings for a project"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("""
                SELECT * FROM meetings
                WHERE project = ?
                ORDER BY start_time DESC
            """, (project,))
            return [self._row_to_meeting(row) for row in cursor.fetchall()]

    def update_status(self, meeting_id: int, status: str):
        """Update meeting status"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                UPDATE meetings SET status = ? WHERE id = ?
            """, (status, meeting_id))
            conn.commit()

    def _row_to_meeting(self, row: sqlite3.Row) -> Meeting:
        """Convert database row to Meeting object"""
        return Meeting(
            id=row['id'],
            project=row['project'],
            title=row['title'],
            start_time=datetime.fromisoformat(row['start_time']),
            end_time=datetime.fromisoformat(row['end_time']) if row['end_time'] else None,
            join_url=row['join_url'],
            platform=row['platform'],
            from_address=row['from_address'],
            to_address=row['to_address'],
            status=row['status'],
            message_id=row['message_id'],
            created_at=datetime.fromisoformat(row['created_at']),
            raw_ics=row['raw_ics'] or ""
        )

    def list_all(self, limit: int = 20) -> List[Meeting]:
        """List all meetings"""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.execute("""
                SELECT * FROM meetings
                ORDER BY start_time DESC
                LIMIT ?
            """, (limit,))
            return [self._row_to_meeting(row) for row in cursor.fetchall()]


def main():
    """CLI for testing the calendar"""
    import argparse

    parser = argparse.ArgumentParser(description="Meeting Calendar")
    parser.add_argument("--list", action="store_true", help="List all meetings")
    parser.add_argument("--pending", action="store_true", help="List pending meetings")
    parser.add_argument("--upcoming", type=int, metavar="MINS", help="List meetings in next N minutes")
    parser.add_argument("--db", default="meetings.db", help="Database path")
    args = parser.parse_args()

    calendar = MeetingCalendar(args.db)

    if args.list:
        meetings = calendar.list_all()
        print(f"All meetings ({len(meetings)}):\n")
        for m in meetings:
            print(f"  [{m.status:10}] {m.start_time:%Y-%m-%d %H:%M} | {m.project:15} | {m.title}")

    elif args.pending:
        meetings = calendar.get_all_pending()
        print(f"Pending meetings ({len(meetings)}):\n")
        for m in meetings:
            print(f"  {m.start_time:%Y-%m-%d %H:%M} | {m.project:15} | {m.title}")
            print(f"    → {m.join_url}")

    elif args.upcoming is not None:
        meetings = calendar.get_upcoming(args.upcoming)
        print(f"Meetings in next {args.upcoming} minutes ({len(meetings)}):\n")
        for m in meetings:
            print(f"  {m.start_time:%H:%M} | {m.project} | {m.title}")
            print(f"    → {m.join_url}")

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
