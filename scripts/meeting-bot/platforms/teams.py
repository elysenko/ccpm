#!/usr/bin/env python3
"""
Microsoft Teams Join Logic

Handles joining a Teams meeting via Playwright.
"""

from playwright.async_api import Page


async def join(page: Page, url: str, bot_name: str = "CCPM Meeting Bot"):
    """
    Join a Microsoft Teams meeting.

    Args:
        page: Playwright page instance
        url: Teams meeting URL
        bot_name: Name to display in the meeting
    """
    print(f"Joining Microsoft Teams: {url}")

    # Add URL params to force web client
    if "?" in url:
        url += "&msLaunch=false&directDl=false&suppressPrompt=true"
    else:
        url += "?msLaunch=false&directDl=false&suppressPrompt=true"

    await page.goto(url)

    # Click "Continue on this browser" if prompted
    try:
        await page.click('button:has-text("Continue on this browser")', timeout=10000)
        print("  Selected browser client")
    except:
        pass

    # Wait for pre-join screen
    await page.wait_for_load_state("networkidle", timeout=15000)

    # Turn off camera
    try:
        await page.click('[aria-label*="camera" i]', timeout=3000)
        print("  Camera toggled")
    except:
        pass

    # Turn off microphone
    try:
        await page.click('[aria-label*="microphone" i]', timeout=3000)
        print("  Microphone toggled")
    except:
        pass

    # Enter name
    try:
        name_input = page.locator('input[placeholder*="name" i]')
        if await name_input.is_visible(timeout=3000):
            await name_input.fill(bot_name)
            print(f"  Set name: {bot_name}")
    except:
        pass

    # Click join button
    try:
        await page.click('button:has-text("Join now")', timeout=10000)
        print("  Clicked join")
    except:
        pass

    # Wait for meeting to load
    try:
        await page.wait_for_selector('[aria-label*="Leave" i]', timeout=60000)
        print("Successfully joined Teams meeting!")
    except:
        print("Warning: Could not confirm meeting join")


async def leave(page: Page):
    """Leave the Teams meeting."""
    try:
        await page.click('[aria-label*="Leave" i]', timeout=5000)
        print("Left the meeting")
    except:
        print("Could not find leave button")


async def is_meeting_ended(page: Page) -> bool:
    """Check if the meeting has ended."""
    try:
        if await page.locator('text="You left the meeting"').is_visible(timeout=1000):
            return True
    except:
        pass
    return False
