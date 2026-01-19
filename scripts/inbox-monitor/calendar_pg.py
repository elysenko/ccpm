#!/usr/bin/env python3
"""
Meeting Calendar - PostgreSQL Version

Uses PostgreSQL for persistence in Kubernetes.
Falls back to SQLite for local development.
"""

import os
import json
import sqlite3
from datetime import datetime, timedelta
from typing import Optional, List
from dataclasses import dataclass, asdict

# Try PostgreSQL first, fall back to SQLite
try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    HAS_POSTGRES = True
except ImportError:
    HAS_POSTGRES = False


@dataclass
class Meeting:
    """A scheduled meeting"""
    id: Optional[int]
    project: str
    title: str
    start_time: datetime
    end_time: Optional[datetime]
    join_url: str
    platform: str
    from_address: str
    to_address: str
    status: str
    message_id: str
    created_at: datetime
    raw_ics: str = ""
    uid: str = ""  # iCalendar UID for matching updates/cancellations

    def to_dict(self) -> dict:
        d = asdict(self)
        d['start_time'] = self.start_time.isoformat() if self.start_time else None
        d['end_time'] = self.end_time.isoformat() if self.end_time else None
        d['created_at'] = self.created_at.isoformat() if self.created_at else None
        return d


class MeetingCalendar:
    """PostgreSQL-based meeting calendar with SQLite fallback"""

    def __init__(self, connection_string: Optional[str] = None):
        """
        Initialize calendar.

        Args:
            connection_string: PostgreSQL connection string or None for SQLite
                Format: postgresql://user:pass@host:port/dbname
        """
        self.connection_string = connection_string or os.environ.get("DATABASE_URL")
        self.use_postgres = bool(self.connection_string and HAS_POSTGRES)

        if self.use_postgres:
            print(f"📦 Using PostgreSQL")
        else:
            print(f"📦 Using SQLite (meetings.db)")
            self.db_path = "meetings.db"

        self._init_db()

    def _get_pg_connection(self):
        """Get PostgreSQL connection"""
        return psycopg2.connect(self.connection_string)

    def _init_db(self):
        """Initialize database schema"""
        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        CREATE TABLE IF NOT EXISTS meetings (
                            id SERIAL PRIMARY KEY,
                            project TEXT NOT NULL,
                            title TEXT NOT NULL,
                            start_time TIMESTAMPTZ NOT NULL,
                            end_time TIMESTAMPTZ,
                            join_url TEXT NOT NULL,
                            platform TEXT NOT NULL,
                            from_address TEXT,
                            to_address TEXT,
                            status TEXT DEFAULT 'pending',
                            message_id TEXT UNIQUE,
                            created_at TIMESTAMPTZ NOT NULL,
                            raw_ics TEXT,
                            uid TEXT
                        )
                    """)
                    # Add uid column if it doesn't exist (migration)
                    cur.execute("""
                        DO $$
                        BEGIN
                            ALTER TABLE meetings ADD COLUMN IF NOT EXISTS uid TEXT;
                        EXCEPTION WHEN duplicate_column THEN
                            -- Column already exists, ignore
                        END $$;
                    """)
                    cur.execute("""
                        CREATE INDEX IF NOT EXISTS idx_meetings_start_time ON meetings(start_time)
                    """)
                    cur.execute("""
                        CREATE INDEX IF NOT EXISTS idx_meetings_status ON meetings(status)
                    """)
                    cur.execute("""
                        CREATE INDEX IF NOT EXISTS idx_meetings_project ON meetings(project)
                    """)
                    cur.execute("""
                        CREATE INDEX IF NOT EXISTS idx_meetings_uid ON meetings(uid)
                    """)
                conn.commit()
        else:
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
                        raw_ics TEXT,
                        uid TEXT
                    )
                """)
                # Add uid column if it doesn't exist (migration for existing DBs)
                try:
                    conn.execute("ALTER TABLE meetings ADD COLUMN uid TEXT")
                except sqlite3.OperationalError:
                    pass  # Column already exists
                # Create index on uid
                conn.execute("CREATE INDEX IF NOT EXISTS idx_meetings_uid ON meetings(uid)")
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
        platform = meeting.platform or self._detect_platform(meeting.join_url)

        try:
            if self.use_postgres:
                with self._get_pg_connection() as conn:
                    with conn.cursor() as cur:
                        cur.execute("""
                            INSERT INTO meetings
                            (project, title, start_time, end_time, join_url, platform,
                             from_address, to_address, status, message_id, created_at, raw_ics, uid)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                            RETURNING id
                        """, (
                            meeting.project,
                            meeting.title,
                            meeting.start_time,
                            meeting.end_time,
                            meeting.join_url,
                            platform,
                            meeting.from_address,
                            meeting.to_address,
                            meeting.status,
                            meeting.message_id,
                            meeting.created_at,
                            meeting.raw_ics,
                            meeting.uid
                        ))
                        result = cur.fetchone()
                        conn.commit()
                        return result[0] if result else None
            else:
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.execute("""
                        INSERT INTO meetings
                        (project, title, start_time, end_time, join_url, platform,
                         from_address, to_address, status, message_id, created_at, raw_ics, uid)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        meeting.project,
                        meeting.title,
                        meeting.start_time.isoformat(),
                        meeting.end_time.isoformat() if meeting.end_time else None,
                        meeting.join_url,
                        platform,
                        meeting.from_address,
                        meeting.to_address,
                        meeting.status,
                        meeting.message_id,
                        meeting.created_at.isoformat(),
                        meeting.raw_ics,
                        meeting.uid
                    ))
                    conn.commit()
                    return cursor.lastrowid
        except (psycopg2.IntegrityError if HAS_POSTGRES else sqlite3.IntegrityError):
            return None

    def get_upcoming(self, minutes_ahead: int = 5) -> List[Meeting]:
        """Get meetings starting within the next N minutes OR already started but still ongoing.

        This allows the bot to join meetings that have already started (e.g., when an
        invite arrives after the meeting begins).
        """
        now = datetime.now().astimezone()
        cutoff = now + timedelta(minutes=minutes_ahead)
        past_cutoff = now - timedelta(minutes=10)

        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    cur.execute("""
                        SELECT * FROM meetings
                        WHERE status = 'pending'
                        AND (
                            -- Case 1: Meeting starts soon (within minutes_ahead)
                            (start_time <= %s AND start_time >= %s)
                            OR
                            -- Case 2: Meeting already started but still ongoing
                            (start_time < %s AND (end_time IS NULL OR end_time > %s))
                        )
                        ORDER BY start_time ASC
                    """, (cutoff, past_cutoff, now, now))
                    return [self._row_to_meeting(row) for row in cur.fetchall()]
        else:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute("""
                    SELECT * FROM meetings
                    WHERE status = 'pending'
                    AND (
                        -- Case 1: Meeting starts soon (within minutes_ahead)
                        (datetime(start_time) <= datetime(?) AND datetime(start_time) >= datetime(?))
                        OR
                        -- Case 2: Meeting already started but still ongoing
                        (datetime(start_time) < datetime(?) AND (end_time IS NULL OR datetime(end_time) > datetime(?)))
                    )
                    ORDER BY start_time ASC
                """, (cutoff.isoformat(), past_cutoff.isoformat(), now.isoformat(), now.isoformat()))
                return [self._row_to_meeting_sqlite(row) for row in cursor.fetchall()]

    def get_all_pending(self) -> List[Meeting]:
        """Get all pending meetings"""
        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    cur.execute("""
                        SELECT * FROM meetings
                        WHERE status = 'pending'
                        ORDER BY start_time ASC
                    """)
                    return [self._row_to_meeting(row) for row in cur.fetchall()]
        else:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute("""
                    SELECT * FROM meetings
                    WHERE status = 'pending'
                    ORDER BY start_time ASC
                """)
                return [self._row_to_meeting_sqlite(row) for row in cursor.fetchall()]

    def get_by_project(self, project: str) -> List[Meeting]:
        """Get all meetings for a project"""
        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    cur.execute("""
                        SELECT * FROM meetings
                        WHERE project = %s
                        ORDER BY start_time DESC
                    """, (project,))
                    return [self._row_to_meeting(row) for row in cur.fetchall()]
        else:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute("""
                    SELECT * FROM meetings
                    WHERE project = ?
                    ORDER BY start_time DESC
                """, (project,))
                return [self._row_to_meeting_sqlite(row) for row in cursor.fetchall()]

    def get_by_uid(self, uid: str) -> Optional[Meeting]:
        """Get a meeting by its iCalendar UID.

        Used to find existing meetings when processing updates or cancellations.
        """
        if not uid:
            return None

        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    cur.execute("""
                        SELECT * FROM meetings
                        WHERE uid = %s
                        ORDER BY created_at DESC
                        LIMIT 1
                    """, (uid,))
                    row = cur.fetchone()
                    return self._row_to_meeting(row) if row else None
        else:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute("""
                    SELECT * FROM meetings
                    WHERE uid = ?
                    ORDER BY created_at DESC
                    LIMIT 1
                """, (uid,))
                row = cursor.fetchone()
                return self._row_to_meeting_sqlite(row) if row else None

    def check_conflicts(self, start_time: datetime, end_time: Optional[datetime], exclude_id: Optional[int] = None) -> List[Meeting]:
        """Check for meetings that overlap with the given time range.

        Args:
            start_time: Start time of the new meeting
            end_time: End time of the new meeting (if None, assumes 1 hour duration)
            exclude_id: Meeting ID to exclude from conflict check (for updates)

        Returns:
            List of conflicting meetings
        """
        # Default to 1 hour duration if no end time
        if end_time is None:
            end_time = start_time + timedelta(hours=1)

        # Two meetings overlap if: new_start < existing_end AND new_end > existing_start
        # We exclude completed, cancelled, missed, and declined meetings from conflict checks
        excluded_statuses = ('completed', 'cancelled', 'missed', 'declined')

        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    query = """
                        SELECT * FROM meetings
                        WHERE status NOT IN %s
                        AND start_time < %s
                        AND (end_time > %s OR (end_time IS NULL AND start_time + interval '1 hour' > %s))
                    """
                    params = [excluded_statuses, end_time, start_time, start_time]

                    if exclude_id is not None:
                        query += " AND id != %s"
                        params.append(exclude_id)

                    query += " ORDER BY start_time ASC"
                    cur.execute(query, params)
                    return [self._row_to_meeting(row) for row in cur.fetchall()]
        else:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                # SQLite doesn't support tuples directly, use IN with multiple placeholders
                status_placeholders = ','.join('?' * len(excluded_statuses))
                query = f"""
                    SELECT * FROM meetings
                    WHERE status NOT IN ({status_placeholders})
                    AND datetime(start_time) < datetime(?)
                    AND (
                        datetime(end_time) > datetime(?)
                        OR (end_time IS NULL AND datetime(start_time, '+1 hour') > datetime(?))
                    )
                """
                params = list(excluded_statuses) + [end_time.isoformat(), start_time.isoformat(), start_time.isoformat()]

                if exclude_id is not None:
                    query += " AND id != ?"
                    params.append(exclude_id)

                query += " ORDER BY start_time ASC"
                cursor = conn.execute(query, params)
                return [self._row_to_meeting_sqlite(row) for row in cursor.fetchall()]

    def update_status(self, meeting_id: int, status: str):
        """Update meeting status"""
        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        UPDATE meetings SET status = %s WHERE id = %s
                    """, (status, meeting_id))
                conn.commit()
        else:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("""
                    UPDATE meetings SET status = ? WHERE id = ?
                """, (status, meeting_id))
                conn.commit()

    def list_all(self, limit: int = 20) -> List[Meeting]:
        """List all meetings"""
        if self.use_postgres:
            with self._get_pg_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cur:
                    cur.execute("""
                        SELECT * FROM meetings
                        ORDER BY start_time DESC
                        LIMIT %s
                    """, (limit,))
                    return [self._row_to_meeting(row) for row in cur.fetchall()]
        else:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.execute("""
                    SELECT * FROM meetings
                    ORDER BY start_time DESC
                    LIMIT ?
                """, (limit,))
                return [self._row_to_meeting_sqlite(row) for row in cursor.fetchall()]

    def _row_to_meeting(self, row: dict) -> Meeting:
        """Convert PostgreSQL row to Meeting object"""
        return Meeting(
            id=row['id'],
            project=row['project'],
            title=row['title'],
            start_time=row['start_time'],
            end_time=row['end_time'],
            join_url=row['join_url'],
            platform=row['platform'],
            from_address=row['from_address'],
            to_address=row['to_address'],
            status=row['status'],
            message_id=row['message_id'],
            created_at=row['created_at'],
            raw_ics=row['raw_ics'] or "",
            uid=row.get('uid') or ""
        )

    def _row_to_meeting_sqlite(self, row: sqlite3.Row) -> Meeting:
        """Convert SQLite row to Meeting object"""
        # Handle uid column which may not exist in older databases
        try:
            uid = row['uid'] or ""
        except (IndexError, KeyError):
            uid = ""

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
            raw_ics=row['raw_ics'] or "",
            uid=uid
        )


def main():
    """CLI for testing the calendar"""
    import argparse

    parser = argparse.ArgumentParser(description="Meeting Calendar")
    parser.add_argument("--list", action="store_true", help="List all meetings")
    parser.add_argument("--pending", action="store_true", help="List pending meetings")
    parser.add_argument("--upcoming", type=int, metavar="MINS", help="List meetings in next N minutes")
    parser.add_argument("--db", help="Database URL (postgresql://...) or SQLite path")
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
