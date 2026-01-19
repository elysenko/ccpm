#!/usr/bin/env python3
"""
Meeting Bot Entry Point

Usage:
    python -m meeting_bot --url "https://meet.google.com/xxx" --project "cattle-erp"
"""

import asyncio
import argparse
import os
import sys

from bot import MeetingBot


async def main():
    parser = argparse.ArgumentParser(description="CCPM Meeting Bot")
    parser.add_argument("--url", help="Meeting URL to join")
    parser.add_argument("--project", default="unknown", help="Project name")
    parser.add_argument("--output", default="/app/output", help="Output directory")
    parser.add_argument("--max-hours", type=float, default=2.0, help="Max meeting duration")
    args = parser.parse_args()

    # Get from args or environment
    url = args.url or os.environ.get("MEETING_URL")
    project = args.project
    if project == "unknown":
        project = os.environ.get("PROJECT", "unknown")
    output_dir = args.output or os.environ.get("OUTPUT_DIR", "/app/output")
    max_hours = args.max_hours

    # Database configuration (from environment)
    meeting_id = os.environ.get("MEETING_ID")
    if meeting_id:
        meeting_id = int(meeting_id)
    database_url = os.environ.get("DATABASE_URL")

    if not url:
        print("Error: Meeting URL required")
        print("  Use --url or set MEETING_URL environment variable")
        sys.exit(1)

    print("="*60)
    print("CCPM Meeting Bot")
    print("="*60)
    print(f"  URL:     {url}")
    print(f"  Project: {project}")
    print(f"  Output:  {output_dir}")
    print(f"  Max:     {max_hours} hours")
    if meeting_id and database_url:
        print(f"  DB:      PostgreSQL (meeting_id: {meeting_id})")
    else:
        print(f"  DB:      None (file output only)")
    print("="*60)

    bot = MeetingBot(url, project, output_dir, meeting_id=meeting_id, database_url=database_url)

    try:
        transcript = await bot.join_and_record(max_hours)

        print("\n" + "="*60)
        print("Meeting Complete!")
        print("="*60)
        print(f"  Project:  {project}")
        print(f"  Duration: {transcript['duration']:.1f} seconds")
        print(f"  Segments: {len(transcript['segments'])}")
        print("="*60)

        # Print summary of transcript
        if transcript['text']:
            preview = transcript['text'][:500]
            if len(transcript['text']) > 500:
                preview += "..."
            print(f"\nTranscript Preview:\n{preview}")

    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
