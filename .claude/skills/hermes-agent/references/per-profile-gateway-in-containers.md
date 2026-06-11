# Running per-profile gateways in containerized environments

When a worker profile (cron ingest, lint, sync, etc.) needs its own gateway running — because per-profile cron jobs only fire when *that profile's* gateway is up — you hit a different set of pitfalls than when running the default profile's gateway. Captured here so future sessions don't rediscover them.

## Why each profile needs its own gateway for cron

Hermes's cron scheduler lives inside the gateway process. The default profile's gateway only ticks the default profile's cron jobs. A cron job created with `hermes -p memento-ingest cron create ...` will *not* fire from the default gateway — you need `hermes -p memento-ingest gateway run` running for that profile's scheduler to tick.

Symptom you'll see:

```
$ hermes -p memento-ingest cron status
✗ Gateway is not running — cron jobs will NOT fire

  1 active job(s)
  Next run: 2026-05-20T00:00:00+00:00
```

The job is registered, the schedule is set, but no scheduler ticks it.

## Platform bind conflicts when cloning a profile

`hermes profile create <name> --clone` copies the default profile's `.env` verbatim. If the default profile has a Telegram bot token, API server key, or any other platform credential set in `.env`, the cloned profile inherits it. When you then start the cloned profile's gateway, it tries to bind to the same Telegram polling connection (or same API server port) as the default profile's gateway and fails:

```
ERROR gateway.platforms.base: [Telegram] Telegram bot token already in use (PID 7). Stop the other gateway first.
WARNING gateway.run: ✗ telegram failed to connect
ERROR gateway.platforms.api_server: [Api_Server] Port 8642 already in use. Set a different port in config.yaml: platforms.api_server.port
WARNING gateway.run: ✗ api_server failed to connect
ERROR gateway.run: Gateway hit a non-retryable startup conflict
```

For a non-chat worker profile (cron ingest, lint, etc.), you almost never want it owning a bot identity. The fix is to disable platform binds in the cloned profile's `.env` so the gateway starts with cron only, no platforms:

```bash
# In <profile-home>/.env, comment out:
# TELEGRAM_BOT_TOKEN=...
# TELEGRAM_ALLOWED_USERS=...
# TELEGRAM_HOME_CHANNEL=...
# API_SERVER_KEY=...
```

After that, the gateway starts with no platform adapters but still ticks cron jobs:

```
✓ Gateway is running — cron jobs will fire automatically
  PID: 1509

  1 active job(s)
  Next run: ...
```

`hermes gateway list` will show both gateways live:

```
Gateways:
  ✓ default (current)        — PID 7
  ✓ memento-ingest           — PID 1509
```

## HERMES_HOME must be set explicitly when invoking as a different user

In containerized Hermes deployments, the data root often lives at `/opt/data` rather than the user's home directory. The default profile process is started with `HERMES_HOME=/opt/data` baked in, so running `hermes` as root just works. But if you `su - hermes -c 'hermes ...'` to drop to a worker user, the env var is dropped:

```bash
$ su - hermes -c 'hermes profile list'
Error: Profile 'memento-ingest' does not exist. Create it with: hermes profile create memento-ingest
```

The profile is there — it just resolves `HERMES_HOME` to `~/.hermes` (which is empty for the hermes user), not `/opt/data/profiles/`. Fix: pass `HERMES_HOME` explicitly:

```bash
su - hermes -c 'HERMES_HOME=/opt/data hermes profile list'
# → lists profiles correctly
```

This applies to every CLI invocation as a non-default user. When starting a worker gateway:

```bash
su - hermes -c 'HERMES_HOME=/opt/data exec hermes -p memento-ingest gateway run'
```

## Starting a worker gateway from root in a container (no su needed)

If the main Hermes agent already runs as root with `HERMES_HOME=/opt/data`, you do NOT need `su - hermes` to start a worker profile's gateway. Just use `terminal(background=true)` directly:

```python
terminal(
    command='HERMES_HOME=/opt/data /opt/hermes/.venv/bin/hermes -p memento-ingest gateway run',
    background=True,
    watch_patterns=['No messaging platforms enabled', 'Gateway running', 'cron ticker started', 'ERROR']
)
```

The `su - hermes -c '...'` pattern drops `HERMES_HOME` (su resets the environment) and produces an empty process log if stdout is not captured. Running as root with the env var set is simpler and works correctly.

**If "Gateway already running" appears** — the first background attempt worked even if the process log was empty. Check with `hermes -p <profile> gateway status` before trying to restart.

## Dashboard does not reflect new profiles or cron jobs until restarted

After creating a new profile or cron job, the dashboard (port 9119) does not hot-reload. It will show stale state — missing profiles, missing jobs, outdated session counts — until the dashboard process is restarted.

Restart procedure:

```bash
hermes dashboard --stop
# then start in background:
terminal(
    command='HERMES_HOME=/opt/data /opt/hermes/.venv/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open --insecure --skip-build',
    background=True
)
```

Tell the user to hard-refresh the browser after restart. This is the fix for "dashboard seems broken / doesn't show updated information".

`hermes gateway install` registers a systemd / launchd service. In a typical Hermes-in-Docker container, PID 1 is `tini` or `dumb-init` and there's no systemd. The install command will either no-op or fail. Use `hermes gateway run` as a background process instead.

The pattern for a worker that should outlive the parent shell:

```bash
# From a hermes-aware shell (root, with HERMES_HOME set)
nohup su - hermes -c 'HERMES_HOME=/opt/data exec hermes -p memento-ingest gateway run' \
      > /var/log/memento-ingest-gateway.log 2>&1 &
disown
```

Or from the Hermes agent itself, use `terminal(background=true)` with a long-lived watch on a startup signature like `Gateway running` (then drop watch_patterns once it's up — the gateway is a long-running process and you don't want a notification flood).

To survive container restarts, wire the same command into your container's existing init script (Docker `CMD` / `ENTRYPOINT`, supervisord conf, etc.). The "right" answer depends on whoever owns the container image — there isn't a one-size-fits-all here.

## Quick verification checklist after wiring this up

```bash
# 1. The profile loads with the right HERMES_HOME
HERMES_HOME=/opt/data hermes profile show <worker-name>

# 2. The cron job is registered
HERMES_HOME=/opt/data hermes -p <worker-name> cron list

# 3. The gateway is actually running (not just registered)
hermes gateway list           # should show ✓ for both default and the worker

# 4. The cron status agrees
HERMES_HOME=/opt/data hermes -p <worker-name> cron status
# should say "Gateway is running — cron jobs will fire automatically"

# 5. Force a tick for end-to-end validation before waiting for the natural fire time
HERMES_HOME=/opt/data hermes -p <worker-name> cron run <job-id>
# or
HERMES_HOME=/opt/data hermes -p <worker-name> cron tick
```

## Memory cost note

Each running gateway is a long-lived Python process — roughly 80-150 MB resident when idle. A box running default + 2 worker profile gateways uses ~250-450 MB just for the gateways. If you have many low-frequency workers, consider the alternative pattern: a single external scheduler (host cron, supervisord timer, etc.) invokes `hermes -p <name> cron tick` on each profile's schedule. `cron tick` runs due jobs once and exits — no persistent gateway needed, no memory cost between ticks. Trade-off: you give up the canonical Hermes-managed scheduler in exchange for not paying idle gateway memory.
