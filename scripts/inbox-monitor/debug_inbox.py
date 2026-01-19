#!/usr/bin/env python3
"""Debug script to see what's in the inbox"""

import imaplib
import email
import os
from datetime import datetime, timedelta

email_address = os.environ.get("GMAIL_ADDRESS")
app_password = os.environ.get("GMAIL_APP_PASSWORD")

mail = imaplib.IMAP4_SSL("imap.gmail.com", 993)
mail.login(email_address, app_password)
mail.select("INBOX")

# Search last 7 days
since_date = (datetime.now() - timedelta(days=7)).strftime("%d-%b-%Y")
_, message_numbers = mail.search(None, f'(SINCE {since_date})')

nums = message_numbers[0].split()
print(f"Found {len(nums)} emails in last 7 days\n")

for num in nums[-10:]:  # Last 10 emails
    _, data = mail.fetch(num, "(RFC822)")
    msg = email.message_from_bytes(data[0][1])

    print(f"{'─' * 60}")
    print(f"Subject: {msg.get('Subject', '(no subject)')}")
    print(f"From:    {msg.get('From', '(no from)')}")
    print(f"To:      {msg.get('To', '(no to)')}")
    print(f"Date:    {msg.get('Date', '(no date)')}")

    # Show content types
    content_types = []
    for part in msg.walk():
        ct = part.get_content_type()
        fn = part.get_filename()
        if fn:
            content_types.append(f"{ct} [{fn}]")
        else:
            content_types.append(ct)
    print(f"Parts:   {', '.join(set(content_types))}")
    print()

mail.logout()
