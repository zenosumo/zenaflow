# Per-profile Telegram bot setup checklist

Use when connecting a separate Hermes profile to its own Telegram bot identity.

## Checklist

1. Verify/create the profile, and check for near-miss typos before creating a duplicate:
   ```bash
   hermes profile list
   hermes profile show <profile>
   # if the requested profile is missing but a near-miss exists, rename it early:
   hermes profile rename <typo-name> <profile>
   # if no suitable profile exists:
   hermes profile create <profile> --clone
   ```
   Profile name typos are common when users create profiles manually. Prefer renaming the accidental profile early (before cron jobs, aliases, or gateway processes accumulate) rather than creating a second nearly-identical profile.

2. Ensure the profile has its own config and env file:
   ```bash
   hermes -p <profile> config path
   hermes -p <profile> config env-path
   ```

3. Put the new bot token only in the profile-local `.env`:
   ```bash
   printf '\nTELEGRAM_BOT_TOKEN=<token>\n' >> /opt/data/profiles/<profile>/.env
   chmod 600 /opt/data/profiles/<profile>/.env
   ```

4. Do **not** copy another profile's `TELEGRAM_BOT_TOKEN`. Two gateways polling the same bot token will fight each other.

5. If cloning from a profile that has an allowlist, copy authorization separately from the token when the same user should be allowed:
   ```bash
   # copy TELEGRAM_ALLOWED_USERS (or the relevant allowlist), not the token
   ```
   Without an allowlist or `GATEWAY_ALLOW_ALL_USERS=true`, the gateway can connect but deny all users.

6. If the cloned env contains API-server credentials, remove or change them unless this profile intentionally owns a separate API server port:
   ```bash
   # remove API_SERVER_KEY from profile-local .env, or configure platforms.api_server.port uniquely
   ```
   Otherwise the profile can repeatedly try to bind the default API server port already used by another gateway. Telegram can still work, but logs will show avoidable API server failures.

7. Validate the token before starting the gateway, without printing the token:
   ```bash
   curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"
   ```
   `{"ok":true,...}` proves the token is valid; `Unauthorized` means it is invalid/revoked/copied incorrectly.

8. Start/restart and verify the profile gateway:
   ```bash
   # After changing the profile's Telegram env or default model/provider,
   # restart any already-running profile gateway so the new config is loaded.
   hermes -p <profile> gateway stop || true
   hermes -p <profile> gateway run
   hermes -p <profile> gateway status
   tail -80 /opt/data/profiles/<profile>/logs/gateway.log
   ```

9. If setting the profile to the same GPT-5.5 OpenAI Codex default as the main profile, use profile-scoped config and clear stale provider-specific overrides:
   ```bash
   hermes -p <profile> config set model.provider openai-codex
   hermes -p <profile> config set model.default gpt-5.5
   hermes -p <profile> config set model.base_url https://chatgpt.com/backend-api/codex
   hermes -p <profile> config set model.api_key ''
   hermes -p <profile> config set model.api_mode ''
   hermes profile show <profile>
   ```
   Then restart the profile gateway as above.

## Verification signals

Healthy Telegram-only startup logs look like:

```text
Active profile: <profile>
Connecting to telegram...
[Telegram] Connected to Telegram (polling mode)
✓ telegram connected
Gateway running with 1 platform(s)
```

If the log warns `No user allowlists configured. All unauthorized users will be denied`, add the intended Telegram allowlist or explicitly set `GATEWAY_ALLOW_ALL_USERS=true` for an open bot.
