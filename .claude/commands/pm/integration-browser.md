# Integration Browser

Dynamically research and automate integration setup for any service.

## Usage

```
/pm:integration-browser <service-name>
```

## Arguments

- `service-name`: The service to set up (e.g., gorgias, slack, stripe, hubspot)

## Instructions

### Phase 1: Research (Sub-Agent)

Use the Task tool with `deep-research` agent to find API credentials info. This preserves main context by returning only a condensed summary.

**Task tool invocation:**
```
subagent_type: deep-research
description: Research {service-name} API setup
prompt: |
  Research how to get API keys or access tokens for {service-name}.

  Return a structured summary with ONLY these fields:

  1. HAS_NATIVE_API: yes/no
  2. AUTH_METHOD: API key | OAuth 2.0 | Basic Auth | Bearer token
  3. SETUP_URL: The exact URL to obtain credentials
  4. STEPS: Numbered list of steps to get credentials
  5. ENV_VARS_NEEDED: List of environment variables user must set (e.g., EMAIL, PASSWORD, SUBDOMAIN)
  6. VALIDATION_ENDPOINT: API endpoint to test credentials (if known)
  7. GOTCHAS: Any prerequisites or common issues

  Keep response under 500 words. No preamble.
```

Wait for sub-agent to return before proceeding.

### Phase 2: Analyze Research Results

From the research findings, determine:

**1. Has native API?**
- If yes: Extract API endpoint base URL, auth method, and manual setup steps
- Recommend API-based setup over browser automation when possible

**2. Requires browser automation?**
- If no native API exists, or
- If API key must be created via UI (no programmatic way), or
- If OAuth app must be registered through a web interface
- Extract the step-by-step browser flow from research

**3. Authentication type:**
- **API Key**: Simple token that can be copied
- **OAuth 2.0**: May require app creation, client ID/secret, redirect URIs
- **Basic Auth**: Username/password combination
- **Bearer Token**: Similar to API key, often with expiration

**4. Environment variables needed:**
Determine what credentials the user needs to provide:
- `{SERVICE}_EMAIL` - Login email
- `{SERVICE}_PASSWORD` - Login password
- `{SERVICE}_SUBDOMAIN` - If service uses subdomains (e.g., company.service.com)
- `{SERVICE}_API_KEY` - Final output credential

### Phase 3: Present Findings to User

Display a clear summary:

```
## Research Findings for {service-name}

**Service Type**: {SaaS/Platform/API Service}
**Has Native API**: {Yes/No}
**Authentication Method**: {API Key/OAuth/Basic Auth/Bearer Token}

### Recommended Approach
{Either "API-based setup (manual)" or "Browser automation"}

### Required Credentials
Before proceeding, set these environment variables:
- {SERVICE}_EMAIL: Your login email
- {SERVICE}_PASSWORD: Your login password
{Additional vars as needed}

### Steps to be Performed
{Numbered list of steps that will be taken}
```

**Ask user to confirm:**
1. Have they set the required environment variables?
2. Do they approve the browser automation steps (if applicable)?

Use AskUserQuestion tool to get confirmation before proceeding to automation.

### Phase 4: Execute Based on Approach

#### Path A: API-Based Setup (No Browser Automation)

If service has a straightforward API setup:

```
Instructions for {service-name}:

1. Log into {service-url} manually
2. Navigate to: {exact path from research}
3. {Specific steps to generate/copy key}
4. Set environment variable:
   export {SERVICE}_API_KEY="your_key_here"

After setting the key, I can validate it works.
```

Offer to validate credentials with a test API call if endpoint is known.

#### Path B: Browser Automation (Sub-Agent)

If browser automation is approved, delegate to a sub-agent to preserve main context. The sub-agent handles all Playwright interactions and returns only the extracted credential.

**Task tool invocation:**
```
subagent_type: general-purpose
description: Automate {service-name} credential extraction
prompt: |
  Use Playwright MCP to extract API credentials from {service-name}.

  ## Login Details
  - URL: {setup_url_from_research}
  - Email: Read from environment variable ${SERVICE}_EMAIL
  - Password: Read from environment variable ${SERVICE}_PASSWORD
  - Subdomain (if needed): Read from ${SERVICE}_SUBDOMAIN

  ## Steps to Follow
  {steps_from_research}

  ## Instructions
  1. Use browser_navigate to go to the login/setup URL
  2. Use browser_snapshot to see the page
  3. Use browser_fill_form or browser_type to enter credentials
  4. Use browser_click to submit and navigate
  5. Follow the steps to reach the API key page
  6. Use browser_snapshot and browser_evaluate to extract the API key
  7. Use browser_close when done

  ## Return Format
  Return ONLY this (no other text):

  EXTRACTED_CREDENTIAL: {the_api_key_or_token}
  CREDENTIAL_TYPE: {API key | Bearer token | Client ID/Secret | etc}

  If extraction fails, return:

  ERROR: {what_went_wrong}
  LAST_PAGE: {url_where_it_failed}
```

Wait for sub-agent to return the extracted credential or error.

### Phase 5: Store and Verify Credentials

After extraction:

**1. Validate credentials work (if possible):**
- Make a test API call to a simple endpoint (e.g., /me, /account, /ping)
- Report success or failure

**2. Store credentials:**
- Append to `.env` file in project root
- Use format: `{SERVICE}_API_KEY=extracted_value`
- Ensure .env is in .gitignore

**3. Report results:**

```
✅ {service-name} configured successfully!

Credentials stored in .env:
  - {KEY_NAME}: ****{last 4 characters}

Validation: {Passed - able to call /endpoint / Failed - reason / Skipped - no test endpoint known}

Next steps:
  - {Any follow-up actions}
```

## Security Guardrails

1. **Never hardcode credentials** - Always read from environment variables
2. **User approval required** - Always ask before browser automation
3. **Prefer API over browser** - Let research findings decide the approach
4. **Mask credentials in output** - Show only last 4 characters
5. **Local execution only** - Playwright runs on user's machine, not remote
6. **No credential logging** - Never write full credentials to logs or transcripts

## Error Handling

**Research fails:**
```
❌ Could not find API setup instructions for {service}.
This might be a lesser-known service. Try:
1. Check {service}'s official documentation
2. Search for "{service} API documentation"
3. Contact {service} support for API access
```

**Browser automation fails:**
```
❌ Browser automation failed at step: {step}
Error: {error_message}

Options:
1. Retry automation
2. Complete manually using these steps: {steps}
3. Check if page structure has changed
```

**Invalid credentials:**
```
❌ Credential validation failed.
Response: {error_response}

This usually means:
- Credentials were not correctly extracted
- Account lacks API permissions
- API key needs activation
```

## Example Flows

### Example 1: Service with Native API (Stripe)

```
User: /pm:integration-browser stripe

Claude: [Spawns deep-research sub-agent...]

Sub-agent returns:
  HAS_NATIVE_API: yes
  AUTH_METHOD: Bearer token
  SETUP_URL: https://dashboard.stripe.com/apikeys
  STEPS: 1. Login 2. Developers → API Keys 3. Copy Secret Key
  ENV_VARS_NEEDED: none (manual copy)
  VALIDATION_ENDPOINT: GET https://api.stripe.com/v1/balance

Claude: ## Research Findings for Stripe

**Has Native API**: Yes
**Authentication Method**: Bearer Token (API Key)

### Recommended Approach
API-based setup (manual) - Stripe has excellent developer portal

### Instructions

1. Log into https://dashboard.stripe.com
2. Navigate to: Developers → API Keys
3. Copy your Secret Key (starts with sk_live_ or sk_test_)
4. Set environment variable:

   export STRIPE_API_KEY="sk_test_..."

After setting, I can validate with a test API call.

Would you like me to validate your credentials once set?
```

### Example 2: Service Requiring Browser Automation

```
User: /pm:integration-browser legacy-erp

Claude: [Spawns deep-research sub-agent...]

Sub-agent returns:
  HAS_NATIVE_API: no
  AUTH_METHOD: API key
  SETUP_URL: https://{subdomain}.legacy-erp.com/admin/api-settings
  STEPS: 1. Login 2. Settings → API 3. Generate Key
  ENV_VARS_NEEDED: EMAIL, PASSWORD, SUBDOMAIN

Claude: ## Research Findings for legacy-erp

**Has Native API**: No (key must be generated via UI)
**Authentication Method**: API Key

### Required Credentials
Before proceeding, set these environment variables:
  export LEGACY_ERP_EMAIL="your_email"
  export LEGACY_ERP_PASSWORD="your_password"
  export LEGACY_ERP_SUBDOMAIN="yourcompany"

### Steps to be Performed
1. Navigate to https://{subdomain}.legacy-erp.com/admin
2. Log in with provided credentials
3. Go to Settings → Integrations → API
4. Click "Generate New Key"
5. Extract the generated key

Proceed with browser automation? [Confirm required]

User: Yes

Claude: [Spawns general-purpose sub-agent for Playwright automation...]

Sub-agent returns:
  EXTRACTED_CREDENTIAL: sk_live_abc1234567890
  CREDENTIAL_TYPE: API key

Claude: ✅ legacy-erp configured successfully!

Credentials stored in .env:
  - LEGACY_ERP_API_KEY: ****7890

Validation: Passed - GET /api/v1/me returned 200
```

## Dependencies

- **Task tool** - For spawning sub-agents (preserves main context)
- **deep-research agent** - For Phase 1 research
- **general-purpose agent** - For Phase 4 browser automation
- **Playwright MCP** - Browser automation (used by sub-agent)
- **Environment variable access** - For credentials

## Notes

- This skill works with any service by researching on-demand
- No static registry to maintain - always gets fresh instructions
- Research quality depends on available documentation
- Some services may require manual steps that cannot be automated
- **Context preservation**: Sub-agents handle verbose operations (research, browser automation) and return only condensed results to main conversation
