# OpenCode Zen profile model repair

Use this when a Hermes profile should use an OpenCode Zen model such as `grok-build-0.1`, especially after the user tried to change the model and may have left stale provider fields behind.

## Canonical repair sequence

Inside the Hermes container/profile environment:

```bash
H=/opt/hermes/.venv/bin/hermes
$H -p <profile> config set model.provider opencode-zen
$H -p <profile> config set model.default grok-build-0.1
$H -p <profile> config set model.base_url ''
$H -p <profile> config set model.api_key ''
$H -p <profile> config set model.api_mode ''
$H profile show <profile>
```

Clearing `model.base_url`, `model.api_key`, and `model.api_mode` is intentional: it prevents stale config from a previous provider family (OpenAI Codex, Gemini, OpenRouter, etc.) from overriding OpenCode Zen runtime resolution. Keep credentials in the profile-local `.env`, not in `config.yaml`.

## Required env

Verify the profile-local env contains the key without printing it:

```bash
grep '^OPENCODE_ZEN_API_KEY=' /opt/data/profiles/<profile>/.env >/dev/null && echo 'OPENCODE_ZEN_API_KEY is set' || echo 'MISSING OPENCODE_ZEN_API_KEY'
```

If needed, add it:

```bash
printf '\nOPENCODE_ZEN_API_KEY=YOUR_KEY_HERE\n' >> /opt/data/profiles/<profile>/.env
chmod 600 /opt/data/profiles/<profile>/.env
```

If a custom endpoint is required, use `OPENCODE_ZEN_BASE_URL` in the profile `.env`; otherwise let Hermes use the provider default.

## Docker-host command form

When the user is operating Hermes from the host with a container named `hermes`, give commands in host-executable form:

```bash
docker exec -it hermes /opt/hermes/.venv/bin/hermes -p <profile> config set model.provider opencode-zen
docker exec -it hermes /opt/hermes/.venv/bin/hermes -p <profile> config set model.default grok-build-0.1
docker exec -it hermes /opt/hermes/.venv/bin/hermes -p <profile> config set model.base_url ''
docker exec -it hermes /opt/hermes/.venv/bin/hermes -p <profile> config set model.api_key ''
docker exec -it hermes /opt/hermes/.venv/bin/hermes -p <profile> config set model.api_mode ''
```

## Restart gateway after config changes

A running gateway reads config at startup. Stop/restart it after the model change.

If you know the PID from `gateway status`:

```bash
docker exec -it hermes kill <pid>
docker exec -d hermes /opt/hermes/.venv/bin/hermes -p <profile> gateway run
```

Or, from inside the same agent runtime, kill the tracked background process and start a fresh `hermes -p <profile> gateway run`.

## Verification

```bash
/opt/hermes/.venv/bin/hermes profile show <profile>
/opt/hermes/.venv/bin/hermes -p <profile> gateway status
/opt/hermes/.venv/bin/hermes -p <profile> doctor
```

Expected profile line:

```text
Model:   grok-build-0.1 (opencode-zen)
```

Expected doctor signal:

```text
✓ OpenCode Zen
```

For Telegram bots, also check recent gateway logs for `Connected to Telegram` and `Gateway running with 1 platform(s)`.