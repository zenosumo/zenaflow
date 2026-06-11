# Cron worker profile credential and gateway isolation

Use this when a cloned/durable Hermes worker profile runs cron jobs and the user changes its model/provider or starts its gateway only to drive cron.

## Key lessons

- Profile model changes are not enough; verify the provider credential from the worker profile's own Hermes home.
- Put provider secrets in the profile-local `.env`; keep `model.api_key` empty in `config.yaml` so secrets do not land in config.
- For Gemini API-key usage, Hermes' native provider is `gemini`, with base URL `https://generativelanguage.googleapis.com/v1beta`. `GOOGLE_API_KEY` and `GEMINI_API_KEY` are both recognized.
- A cron-only worker gateway does not need Telegram/Discord/API-server platforms. It can start with no messaging platforms enabled and still run the cron ticker.
- If a cloned worker inherits platform credentials or a project/global `.env` supplies them, the worker gateway may contend with the main gateway for the same Telegram bot token or API server port. Disable/blank those in the worker profile `.env`.

## Verification pattern

1. Show profile and config:

```bash
hermes profile show <worker>
hermes -p <worker> config path
hermes -p <worker> config env-path
```

2. Set Gemini native API model without embedding the key in config:

```bash
hermes -p <worker> config set model.provider gemini
hermes -p <worker> config set model.default gemini-3.5-flash
hermes -p <worker> config set model.base_url https://generativelanguage.googleapis.com/v1beta
hermes -p <worker> config set model.api_mode chat_completions
hermes -p <worker> config set model.api_key ''
```

3. Ensure the profile-local `.env` contains exactly the needed provider key, e.g. `GOOGLE_API_KEY=...` or `GEMINI_API_KEY=...`. Do not print the value.

4. Smoke test the model:

```bash
hermes -p <worker> chat -q 'Provider smoke test. Reply with exactly: OK' --quiet --toolsets safe
```

5. Start/verify the cron-only gateway:

```bash
hermes -p <worker> gateway run
hermes -p <worker> gateway status
hermes -p <worker> cron list --all
```

Healthy cron-only logs may include:

```text
No messaging platforms enabled.
Gateway will continue running for cron job execution.
Cron ticker started (interval=60s)
```

## Env vars to blank/disable for cron-only workers

Only do this for worker profiles that should not own a messaging identity or API server:

```dotenv
TELEGRAM_BOT_TOKEN=
DISCORD_BOT_TOKEN=
SLACK_BOT_TOKEN=
WHATSAPP_ACCESS_TOKEN=
WHATSAPP_TOKEN=
SIGNAL_PHONE_NUMBER=
MATRIX_ACCESS_TOKEN=
MATRIX_PASSWORD=
MATTERMOST_TOKEN=
HASS_TOKEN=
API_SERVER_ENABLED=false
API_SERVER_KEY=
WEBHOOK_ENABLED=false
WEBHOOK_SECRET=
```

This avoids conflicts like "Telegram bot token already in use" or API-server port contention while preserving cron execution.
