# Meeting Bot Browser Automation Research

## Executive Summary

This research covers headless browser automation techniques for joining video meetings (Google Meet, Microsoft Teams, Zoom) from containers. The findings show that **Playwright is the recommended choice** over Puppeteer for meeting bots due to better built-in waiting, permission handling, and multi-browser support. All three platforms can be joined via browser automation, but each has unique challenges and detection mechanisms.

---

## 1. Playwright vs Puppeteer for Meeting Bots

### Comparative Analysis

| Factor | Playwright | Puppeteer |
|--------|-----------|-----------|
| **Waiting mechanisms** | Built-in auto-wait | Manual waits required |
| **Permission handling** | Native support via launch args | Requires more configuration |
| **Multi-browser** | Chromium, Firefox, WebKit | Chrome/Chromium only (Firefox via v23+) |
| **Container support** | Excellent, official Docker images | Good, but more manual setup |
| **Stealth plugins** | playwright-extra (less maintained) | puppeteer-extra-plugin-stealth (more mature) |
| **Meeting bot ecosystem** | More modern projects use Playwright | Older projects use Puppeteer |

### Verdict

**Playwright is recommended** for new meeting bot projects. The recall.ai and screenapp.io open-source bots both use Playwright. However, Puppeteer has a more mature stealth plugin ecosystem.

### Key Launch Arguments for Meeting Bots

```javascript
// Playwright example
const browser = await chromium.launch({
  headless: true,
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--use-fake-ui-for-media-stream',      // Auto-accept media permissions
    '--use-fake-device-for-media-stream',   // Mock camera/mic
    '--disable-blink-features=AutomationControlled'
  ]
});
```

---

## 2. Bot Detection Bypass Techniques

### 2.1 User Agent Management

**Problem**: Headless browsers expose `HeadlessChrome` in User-Agent and set `navigator.webdriver = true`.

**Solutions**:

```javascript
// Set realistic User-Agent
const context = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
});
```

**Critical**: When rotating User-Agent, ensure consistency with:
- `Sec-Ch-Ua` header
- `Sec-Ch-Ua-Platform` header
- Browser capabilities reported by navigator

### 2.2 Stealth Plugin Techniques

**puppeteer-extra-plugin-stealth** provides these evasion modules:

| Module | Purpose |
|--------|---------|
| `navigator.webdriver` | Sets to undefined/false using ES6 Proxies |
| `chrome.runtime` | Mocks chrome object for extension detection |
| `navigator.plugins` | Emulates real browser plugins array |
| `navigator.languages` | Sets realistic language preferences |
| `media.codecs` | Reports standard Chrome codec support |
| `webgl.vendor` | Masks WebGL fingerprinting |
| `iframe.contentWindow` | Fixes HEADCHR_iframe detection |

**Installation**:
```javascript
// Puppeteer
const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());

// Playwright (less maintained)
const { chromium } = require('playwright-extra');
const stealth = require('puppeteer-extra-plugin-stealth')();
chromium.use(stealth);
```

### 2.3 Behavioral Simulation

1. **Random delays**: Add 300-1000ms delays between actions
2. **Mouse movements**: Simulate human-like cursor paths
3. **Scroll patterns**: Natural scrolling before clicking
4. **Typing simulation**: Type characters with random intervals

```javascript
// Human-like typing
async function typeHumanLike(page, selector, text) {
  await page.click(selector);
  for (const char of text) {
    await page.type(selector, char);
    await page.waitForTimeout(50 + Math.random() * 100);
  }
}
```

### 2.4 Xvfb for Headful Mode in Containers

Some anti-bot systems detect headless mode directly. Running headful mode with Xvfb virtual display can bypass this:

```bash
# Docker command
docker run -it --rm --ipc=host mcr.microsoft.com/playwright \
  xvfb-run --auto-servernum --server-args='-screen 0, 1920x1080x24' \
  npx playwright test
```

**Benefits**:
- Real rendering environment
- Consistent canvas/WebGL fingerprints
- Better video playback handling

### 2.5 Detection Limitations

Even with stealth plugins, these can still detect automation:
- **CDP (Chrome DevTools Protocol) detection**: Modern anti-bots detect CDP command usage
- **TLS fingerprinting**: Browser TLS signatures differ from standard Chrome
- **Cloudflare/PerimeterX**: Enterprise anti-bots still detect most evasions

---

## 3. Platform-Specific Join Flows

### 3.1 Google Meet

#### Guest Join (No Authentication)

Google Meet allows unauthenticated guest joins for meetings with specific settings, but functionality is limited.

```javascript
async function joinGoogleMeetAsGuest(page, meetingUrl, displayName) {
  await page.goto(meetingUrl, { waitUntil: 'domcontentloaded' });

  // Enter display name
  await page.fill('input[aria-label="Your name"]', displayName);

  // Disable camera/mic
  await page.click('[aria-label*="Turn off camera"]');
  await page.click('[aria-label*="Turn off microphone"]');

  // Click join button
  await page.click('button:has-text("Ask to join")');

  // Wait for admission
  await Promise.race([
    page.waitForSelector('button[aria-label*="Leave call"]'),
    page.waitForSelector('text=You\'ve been admitted'),
    page.waitForSelector('text=You\'re the only one here')
  ]);
}
```

#### Authenticated Join (Recommended)

For full functionality and to avoid CAPTCHA, use authenticated sessions:

**Step 1: Generate auth.json**
```javascript
// generate-auth.js - Run once locally
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto('https://accounts.google.com');
  // Manually complete login + 2FA
  await page.pause();  // Wait for manual login

  await context.storageState({ path: 'auth.json' });
  await browser.close();
})();
```

**Step 2: Use stored session**
```javascript
const context = await browser.newContext({
  storageState: 'auth.json'
});
const page = await context.newPage();
await page.goto(meetingUrl);
// Now authenticated - can join directly
```

**Critical Requirements**:
- Real Google account required (service accounts don't work)
- Refresh `auth.json` periodically (sessions expire)
- Rotate bot accounts to avoid rate limiting
- Use residential proxies to reduce CAPTCHA triggers

#### Google Meet Join Flow Sequence

1. Navigate to meeting URL
2. Dismiss "Got it" prompts
3. Disable camera/microphone via aria-label selectors
4. Click join button (with fallback for UI variations)
5. Handle preview collapse if needed
6. Wait for admission confirmation
7. Enable captions via `Shift+C` hotkey or button

#### Caption Scraping

```javascript
// DOM observer for captions
await page.evaluate(() => {
  const captionContainer = document.querySelector('[jscontroller="TEjq6e"]');
  const observer = new MutationObserver((mutations) => {
    mutations.forEach(m => {
      m.addedNodes.forEach(node => {
        if (node instanceof HTMLElement) {
          const text = node.textContent;
          const speaker = node.querySelector('.NWpY1d')?.textContent;
          window.postMessage({ type: 'caption', speaker, text });
        }
      });
    });
  });
  observer.observe(captionContainer, { childList: true, subtree: true });
});
```

---

### 3.2 Microsoft Teams

#### Guest Join (No Authentication Required)

Teams allows unauthenticated guest joins without tenant installation. This is the **recommended approach** for meeting bots.

**URL Modification for Direct Join**:
```javascript
function getTeamsDirectJoinUrl(meetingUrl) {
  const url = new URL(meetingUrl);
  url.searchParams.set('msLaunch', 'false');
  url.searchParams.set('type', 'meetup-join');
  url.searchParams.set('directDl', 'true');
  url.searchParams.set('suppressPrompt', 'true');
  return url.toString();
}
```

#### Join Flow Implementation

```javascript
async function joinTeamsMeeting(page, meetingUrl, displayName) {
  const directUrl = getTeamsDirectJoinUrl(meetingUrl);

  // Fixed user agent is CRITICAL - Teams serves different DOM based on UA
  await page.setExtraHTTPHeaders({
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
  });

  await page.goto(directUrl, { waitUntil: 'networkidle' });

  // Enter display name
  await page.fill('[data-tid="prejoin-display-name-input"]', displayName);

  // Disable audio/video
  await page.click('[data-tid="toggle-mute"]');
  await page.click('[data-tid="toggle-video"]');

  // Click join
  await page.click('[data-tid="prejoin-join-button"]');

  // Wait for lobby or admission
  await page.waitForSelector('text=Someone will let you in shortly', {
    timeout: 60000
  }).catch(() => {});

  // Enable captions
  await page.click('[aria-label="Turn on live captions"]');
}
```

#### Critical Teams Considerations

1. **Fixed User-Agent Required**: Teams serves different DOM structures based on browser detection
2. **No Authentication Needed**: Bot joins as guest participant
3. **Lobby Handling**: Must wait for host to admit from lobby
4. **Caption Finalization**: Teams renders partial captions before finalizing - check for ending punctuation (`.`, `!`, `?`) to filter incomplete text

---

### 3.3 Zoom

#### Web Client Approach

Zoom's web client can be forced by modifying the URL:

```javascript
function getZoomWebClientUrl(meetingUrl) {
  // Convert /j/MEETINGID to /wc/join/MEETINGID
  const meetingId = meetingUrl.match(/\/j\/(\d+)/)?.[1];
  const password = new URL(meetingUrl).searchParams.get('pwd');
  return `https://app.zoom.us/wc/join/${meetingId}?pwd=${password}`;
}
```

#### Join Flow

```javascript
async function joinZoomMeeting(page, meetingUrl, displayName) {
  const webUrl = getZoomWebClientUrl(meetingUrl);

  await page.goto(webUrl, { waitUntil: 'networkidle' });

  // Enter name
  await page.fill('#inputname', displayName);

  // Click join
  await page.click('button:has-text("Join")');

  // Handle two scenarios
  const admitted = await Promise.race([
    page.waitForSelector('[aria-label="mute my microphone"]')  // In meeting
      .then(() => true),
    page.waitForSelector('text=Please wait, the meeting host')  // Waiting room
      .then(() => false)
  ]);

  if (!admitted) {
    // Wait for host admission with timeout
    await page.waitForSelector('[aria-label="mute my microphone"]', {
      timeout: 120000
    });
  }
}
```

#### Zoom Limitations

| Limitation | Impact |
|------------|--------|
| **Web client feature parity** | Reduced video/audio quality, fewer features |
| **Host approval required** | Cannot record without explicit permission |
| **Caption sliding window** | Text updates incrementally, old words disappear |
| **Organization restrictions** | Some accounts disable web client or captions |
| **Meeting SDK approval** | 4-6 week process for external meeting access |

#### Caption Scraping Challenge

Zoom captions use a sliding window that requires deduplication:

```javascript
let lastCaption = '';

function processZoomCaption(newText) {
  // Find new content by comparing with last caption
  if (newText.startsWith(lastCaption)) {
    const newContent = newText.slice(lastCaption.length).trim();
    lastCaption = newText;
    return newContent;
  }
  // Caption reset - return full text
  lastCaption = newText;
  return newText;
}
```

---

## 4. Authentication Handling in Containers

### 4.1 Cookie/Session Persistence

**Playwright storageState approach**:
```javascript
// Save session after login
await context.storageState({ path: '/data/auth.json' });

// Load session in container
const context = await browser.newContext({
  storageState: '/data/auth.json'
});
```

**Docker volume mount**:
```dockerfile
# Dockerfile
COPY auth.json ./auth.json

# Or mount at runtime
docker run -v /host/path/auth.json:/app/auth.json meeting-bot
```

### 4.2 OAuth Token Handling

For services requiring OAuth (Microsoft Graph API, Google APIs):

1. **Separate token generation service**: Run locally to complete OAuth flow
2. **Store refresh tokens**: Persist to database or secrets manager
3. **Token refresh in container**: Refresh before expiry

```javascript
// Token refresh pattern
async function getValidToken(storedTokens) {
  if (isExpired(storedTokens.accessToken)) {
    const newTokens = await refreshOAuthToken(storedTokens.refreshToken);
    await saveTokens(newTokens);
    return newTokens.accessToken;
  }
  return storedTokens.accessToken;
}
```

### 4.3 Multi-Account Rotation

To avoid rate limiting and detection:

```javascript
// Account pool management
class BotAccountPool {
  constructor(accounts) {
    this.accounts = accounts;
    this.lastUsed = new Map();
  }

  getNextAccount() {
    // Find account not used in last 10 minutes
    const available = this.accounts.filter(acc => {
      const last = this.lastUsed.get(acc.email);
      return !last || Date.now() - last > 600000;
    });

    const account = available[0] || this.accounts[0];
    this.lastUsed.set(account.email, Date.now());
    return account;
  }
}
```

---

## 5. Container/Docker Configuration

### 5.1 Dockerfile Example

```dockerfile
FROM mcr.microsoft.com/playwright:v1.40.0-jammy

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy application
COPY . .

# Copy auth state (or mount at runtime)
COPY auth.json ./auth.json

# Chrome flags for container environment
ENV PLAYWRIGHT_CHROMIUM_ARGS="--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage"

CMD ["node", "bot.js"]
```

### 5.2 Docker Compose for Multi-Service

```yaml
version: '3.8'
services:
  bot:
    build:
      context: .
      dockerfile: Dockerfile.bot
    environment:
      - MEETING_URL=${MEETING_URL}
      - BOT_NAME=${BOT_NAME}
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    shm_size: '2gb'  # Prevent Chrome crashes

  redis:
    image: redis:alpine

  api:
    build:
      context: .
      dockerfile: Dockerfile.api
    ports:
      - "3000:3000"
```

### 5.3 Resource Requirements

| Component | Memory | CPU | Notes |
|-----------|--------|-----|-------|
| Chromium instance | 500MB-1GB | 0.5-1 core | Per meeting |
| Node.js runtime | 100-200MB | 0.1-0.2 core | Base overhead |
| Xvfb (if headful) | 50-100MB | 0.1 core | Virtual display |

**Scaling warning**: "Chromium was not built to run hundreds of instances simultaneously on a single machine."

---

## 6. Open Source Reference Projects

### 6.1 screenappai/meeting-bot
- **URL**: https://github.com/screenappai/meeting-bot
- **Tech**: TypeScript, Node.js, Playwright
- **Platforms**: Google Meet, Teams, Zoom
- **Features**: REST API, Redis queue, stealth mode, Prometheus metrics

### 6.2 recallai/google-meet-meeting-bot
- **URL**: https://github.com/recallai/google-meet-meeting-bot
- **Tech**: Node.js, Playwright, PostgreSQL, OpenAI
- **Focus**: Caption scraping, summarization
- **Architecture**: Docker Compose, separate bot/backend services

### 6.3 Ritika-Das/Google-Meet-Bot
- **URL**: https://github.com/Ritika-Das/Google-Meet-Bot
- **Tech**: Node.js, Puppeteer with stealth
- **Features**: Auto-login, caption toggle, chat greeting

### 6.4 shayant98/teamsBot
- **URL**: https://github.com/shayant98/teamsBot
- **Tech**: Node.js, Puppeteer
- **Focus**: Auto-join Teams meetings

---

## 7. Key Recommendations

### Do's

1. **Use Playwright** for new projects - better async handling
2. **Store auth state** via storageState for Google authentication
3. **Use fixed User-Agent** for Teams (critical for DOM consistency)
4. **Force web client** for Zoom via URL modification
5. **Implement retry logic** with exponential backoff
6. **Use residential proxies** to reduce CAPTCHA/blocking
7. **Rotate bot accounts** to avoid rate limits
8. **Set adequate shm_size** in Docker (2GB+) to prevent crashes
9. **Handle lobby/waiting room** with appropriate timeouts
10. **Use MutationObserver** for caption scraping

### Don'ts

1. **Don't use service accounts** for Google Meet (they don't work)
2. **Don't expect 100% stealth** - enterprise anti-bots will still detect
3. **Don't run hundreds of Chromium instances** on single machine
4. **Don't rely on Meeting SDK** for Zoom (4-6 week approval)
5. **Don't hardcode selectors** - UI changes frequently
6. **Don't skip delay simulation** - instant actions trigger detection
7. **Don't store credentials in code** - use environment variables

---

## 8. Detection Risk Matrix

| Platform | Guest Join Risk | Auth Join Risk | Mitigation |
|----------|----------------|----------------|------------|
| **Google Meet** | HIGH (CAPTCHA) | MEDIUM | Rotate accounts, residential IP |
| **MS Teams** | LOW | N/A (not needed) | Fixed UA, proper URL params |
| **Zoom** | MEDIUM | MEDIUM | Web client URL, handle waiting room |

---

## Sources

- [How to Build a Google Meet Bot from Scratch - Recall.ai](https://www.recall.ai/blog/how-i-built-an-in-house-google-meet-bot)
- [How to Build a Microsoft Teams Bot - Recall.ai](https://www.recall.ai/blog/how-to-build-a-microsoft-teams-bot)
- [How to Build a Zoom Bot - Recall.ai](https://www.recall.ai/blog/how-to-build-a-zoom-bot)
- [screenappai/meeting-bot - GitHub](https://github.com/screenappai/meeting-bot)
- [recallai/google-meet-meeting-bot - GitHub](https://github.com/recallai/google-meet-meeting-bot)
- [puppeteer-extra-plugin-stealth - npm](https://www.npmjs.com/package/puppeteer-extra-plugin-stealth)
- [Avoid Bot Detection with Playwright Stealth - Scrapeless](https://www.scrapeless.com/en/blog/avoid-bot-detection-with-playwright-stealth)
- [Bypass Bot Detection 2026 - ZenRows](https://www.zenrows.com/blog/bypass-bot-detection)
- [Playwright xvfb - Restack](https://www.restack.io/p/playwright-answer-xvfb-browser-testing)
- [Google Authentication with Playwright - Medium](https://adequatica.medium.com/google-authentication-with-playwright-8233b207b71a)
- [Zoom Web Client Support - Zoom](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0082184)
- [Teams Bots Overview - Microsoft Learn](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/overview)
