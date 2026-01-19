#!/usr/bin/env python3
"""
Zoom Join Logic

Handles joining a Zoom meeting via web client.
Note: Host must enable "Join from browser" for this to work.
"""

from playwright.async_api import Page


async def join(page: Page, url: str, bot_name: str = "CCPM Meeting Bot"):
    """
    Join a Zoom meeting via web client.

    Args:
        page: Playwright page instance
        url: Zoom meeting URL
        bot_name: Name to display in the meeting
    """
    print(f"Joining Zoom: {url}")

    await page.goto(url)

    # Look for "Join from Your Browser" link
    try:
        await page.click('a:has-text("Join from Your Browser")', timeout=10000)
        print("  Selected browser client")
    except:
        # May already be on web client page
        pass

    # Wait for pre-join screen
    await page.wait_for_load_state("networkidle", timeout=15000)

    # Enter name
    try:
        name_input = page.locator('#inputname, input[placeholder*="name" i]')
        if await name_input.is_visible(timeout=3000):
            await name_input.fill(bot_name)
            print(f"  Set name: {bot_name}")
    except:
        pass

    # Click join button
    try:
        await page.click('button:has-text("Join")', timeout=10000)
        print("  Clicked join")
    except:
        pass

    # Handle "Join Audio" prompt
    try:
        await page.click('button:has-text("Join Audio by Computer")', timeout=10000)
        print("  Joined audio")
    except:
        pass

    # Wait for meeting to load
    try:
        await page.wait_for_selector('[aria-label*="Leave" i]', timeout=60000)
        print("Successfully joined Zoom meeting!")
    except:
        print("Warning: Could not confirm meeting join")


async def leave(page: Page):
    """Leave the Zoom meeting."""
    try:
        await page.click('[aria-label*="Leave" i]', timeout=5000)
        await page.click('button:has-text("Leave Meeting")', timeout=3000)
        print("Left the meeting")
    except:
        print("Could not find leave button")


async def is_meeting_ended(page: Page) -> bool:
    """Check if the meeting has ended."""
    try:
        if await page.locator('text="This meeting has been ended"').is_visible(timeout=1000):
            return True
    except:
        pass
    return False
