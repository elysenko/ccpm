#!/usr/bin/env python3
"""
Google Meet Join Logic

Handles joining a Google Meet meeting via Playwright.
"""

from playwright.async_api import Page


async def join(page: Page, url: str, bot_name: str = "CCPM Meeting Bot"):
    """
    Join a Google Meet meeting.

    Args:
        page: Playwright page instance
        url: Google Meet URL (e.g., https://meet.google.com/xxx-yyyy-zzz)
        bot_name: Name to display in the meeting
    """
    print(f"Joining Google Meet: {url}")

    await page.goto(url)

    # Dismiss "Got it" or other popups
    try:
        await page.click('button:has-text("Got it")', timeout=3000)
    except:
        pass

    try:
        await page.click('button:has-text("Dismiss")', timeout=2000)
    except:
        pass

    # Wait for pre-join screen to load
    await page.wait_for_load_state("networkidle", timeout=15000)

    # Turn off camera (multiple possible selectors)
    camera_selectors = [
        '[aria-label*="camera" i][aria-pressed="true"]',
        '[aria-label*="Turn off camera" i]',
        '[data-tooltip*="camera" i]',
    ]
    for selector in camera_selectors:
        try:
            await page.click(selector, timeout=2000)
            print("  Camera turned off")
            break
        except:
            continue

    # Turn off microphone
    mic_selectors = [
        '[aria-label*="microphone" i][aria-pressed="true"]',
        '[aria-label*="Turn off microphone" i]',
        '[data-tooltip*="microphone" i]',
    ]
    for selector in mic_selectors:
        try:
            await page.click(selector, timeout=2000)
            print("  Microphone turned off")
            break
        except:
            continue

    # Enter name if prompted (guest join)
    try:
        name_input = page.locator('input[aria-label="Your name"]')
        if await name_input.is_visible(timeout=3000):
            await name_input.fill(bot_name)
            print(f"  Set name: {bot_name}")
    except:
        pass

    # Click "Ask to join" or "Join now"
    join_selectors = [
        'button:has-text("Ask to join")',
        'button:has-text("Join now")',
        'button:has-text("Join")',
    ]
    for selector in join_selectors:
        try:
            await page.click(selector, timeout=5000)
            print("  Clicked join button")
            break
        except:
            continue

    # Wait for meeting to load (look for meeting controls)
    try:
        await page.wait_for_selector('[aria-label*="Leave call" i]', timeout=60000)
        print("Successfully joined meeting!")
    except:
        print("Warning: Could not confirm meeting join")

    # Enable captions if available
    try:
        await page.click('[aria-label*="caption" i]', timeout=5000)
        print("  Captions enabled")
    except:
        print("  Captions not available or already enabled")


async def leave(page: Page):
    """Leave the Google Meet meeting."""
    try:
        await page.click('[aria-label*="Leave call" i]', timeout=5000)
        print("Left the meeting")
    except:
        print("Could not find leave button")


async def is_meeting_ended(page: Page) -> bool:
    """Check if the meeting has ended."""
    end_indicators = [
        'text="You left the meeting"',
        'text="The meeting has ended"',
        'text="Return to home screen"',
    ]
    for selector in end_indicators:
        try:
            if await page.locator(selector).is_visible(timeout=1000):
                return True
        except:
            continue
    return False
