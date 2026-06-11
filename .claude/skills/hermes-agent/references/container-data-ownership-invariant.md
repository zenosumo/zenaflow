# Container ownership invariant for Hermes data root

Use this when running Hermes in Docker/Podman containers and you see root-owned files in `/opt/data` (or whatever `HERMES_HOME` resolves to inside the container).

## The invariant

Inside a Hermes Docker/Podman container:

- The container's `entrypoint.sh` (`/opt/hermes/docker/entrypoint.sh`) starts as root, optionally remaps the `hermes` UID/GID, fixes ownership of `HERMES_HOME` with `chown -R hermes:hermes`, then drops privileges via `gosu hermes` before exec'ing the main `hermes` command.
- **Every Hermes process inside the container is expected to run as the `hermes` user (uid 10000)** — gateway, CLI, dashboard, all of them.
- Files under `HERMES_HOME` (default `/opt/data`) MUST be owned by `hermes:hermes`. The gateway writes session state, cron jobs, processes.json, MEMORY.md, logs, and config there. If those files become root-owned with mode `0600`, the gateway loses write access and surfaces warnings like:

  ```text
  WARNING gateway.config: Failed to process config.yaml — falling back to .env / gateway.json values.
    Error: [Errno 13] Permission denied: '/opt/data/profiles/<name>/config.yaml'
  ```

## What breaks the invariant

`docker exec` into the container without `--user hermes` (or attaching to a root shell that bypasses the entrypoint) spawns Hermes as root. Then every file the agent writes — session JSONs, cron edits, .env modifications, skill files, MEMORY.md, dashboard state — is created with `root:root` ownership inside the `hermes:hermes`-owned data tree.

## External Volume Mount Ownership (e.g. /memento)

When external repositories or data directories are mounted into the Hermes container as volumes (such as `/memento`), they are frequently owned by `root:root` with permissions like `755` (`drwxr-xr-x`) inside the container.

This introduces a severe permissions mismatch:
1. **Cron workers run as `hermes`:** The scheduled cron daemon and its sub-processes run as the unprivileged `hermes` user (UID 10000), which cannot write to `root`-owned directories. Any attempt by the cron-ingest job to create files, move files, modify `log.md`, or run `git fetch/commit` will fail with `Permission denied` (e.g., `error: cannot open '.git/FETCH_HEAD': Permission denied`).
2. **Interactive CLI might run as `root`:** If the user or developer executes manual test commands from a shell attached as `root` (e.g., via `docker exec -it <container> bash`), the interactive agent runs with root privileges and successfully writes to the volume.

This mismatch creates a highly confusing discrepancy: **the manual smoke test succeeds perfectly, but the scheduled cron ticks persistently fail with permission errors.**

### Diagnosis

To verify if an external volume (e.g., `/memento`) is writable by the running cron worker (`hermes` user) quickly and without traversing a massive hierarchy or generating write garbage:

```bash
# Check ownership of the mount and its contents
ls -ld /memento
ls -la /memento

# Check if the hermes user has ANY write permissions in the volume (depth-limited for speed)
find /memento -maxdepth 2 -writable
```

If `find /memento -writable` returns empty, the `hermes` user is completely blocked from writing.

### Resolution

The host-side administrator must change the ownership of the mounted directory and its files/subdirectories to `hermes:hermes` (UID 10000:GID 10000) so that both the unprivileged cron worker and the interactive agent have full write access:

```bash
# Run on the host machine (or inside the container as root)
chown -R 10000:10000 /memento
```

Alternatively, if using a Docker Compose mount, ensure the host-side permissions of the directory mapped to `/memento` match UID 10000.

### Cron Worker Strategy under Active Block

If an unprivileged background cron worker (e.g., `memento-ingest`) runs while the volume is write-blocked:
1. **Detect quickly:** Use the non-destructive check `find <volume> -maxdepth 1 -writable` in pre-flight. If it returns empty, the volume is write-blocked.
2. **Handle gracefully (Silent Suppression):** Because the worker lacks permissions to write logs, update stats, or modify `followups.md`, continuing will only cause a cascade of transient failures and spam the user with redundant alerts.
3. **Exit with `[SILENT]`:** The worker should immediately abort and return exactly `[SILENT]` (with no other text) as its final response. This instructs the Hermes cron gateway to suppress delivery of the tick output, preventing UI spam while the system remains blocked. It should repeat this silent-suppression behavior on subsequent ticks until the host-side ownership is fixed.

Symptoms once enough drift accumulates:

- Dashboard process shows stale data because its background polling has permission issues.
- `hermes -p <worker> gateway run` logs "Permission denied" on `config.yaml` and silently falls back to `.env`-only defaults.
- `cronjob` tool writes to `cron/jobs.json` as root; later the hermes-running scheduler can read it (root mode 0600 is still readable by root reading itself), but a subsequent restart by the hermes-owned gateway cannot rewrite the file → cron job updates appear to silently fail.

## Detection

Quick audit:

```bash
find /opt/data -not -user hermes 2>/dev/null | wc -l       # should be 0
find /opt/data -not -group hermes 2>/dev/null | wc -l      # should be 0
```

If non-zero, list the offenders to identify which subsystem is writing as root:

```bash
find /opt/data -not -user hermes -printf '%u:%g %m %p\n' | head -50
```

Common categories:

- `sessions/session_*.json` → the interactive CLI is running as root
- `profiles/<name>/sessions/...` → manual `hermes -p <profile> chat` was invoked from root
- `cron/jobs.json` → cron edits made as root
- `skills/*/SKILL.md` → skill install/edit made as root
- `MEMORY.md`, `processes.json`, `auth.json` → background-process tracker or memory subsystem touched while root
- `.DS_Store`, `._*` → macOS metadata leaked in via a bind mount (delete these; they're not Hermes files)

## Fix

Once-off remediation (must run as root):

```bash
# Clean cosmetic cruft
find /opt/data -name '.DS_Store' -delete
find /opt/data -name '._*' -delete

# Normalize ownership
chown -R hermes:hermes /opt/data
```

Verify count goes to 0:

```bash
find /opt/data -not -user hermes | wc -l
```

## Prevention (single-source-of-truth approach)

The clean fix is to never run Hermes as root inside the container. If you must spawn additional Hermes processes (worker gateways, dashboard restart, smoke tests), use `setpriv` to drop to the `hermes` user with the right env:

```bash
setpriv --reuid hermes --regid hermes --init-groups \
    env HERMES_HOME=/opt/data HOME=/opt/data/home \
    /opt/hermes/.venv/bin/hermes -p <worker> gateway run
```

This is the equivalent of `su - hermes -c '...'` but `setpriv` does NOT strip the env, so `HERMES_HOME` survives the privilege drop. The `su -` pattern (which loads the login shell) drops env vars and breaks `HERMES_HOME` resolution to `/opt/data`.

From `terminal(background=True)` inside the agent:

```python
terminal(
    command='setpriv --reuid hermes --regid hermes --init-groups '
            'env HERMES_HOME=/opt/data HOME=/opt/data/home '
            '/opt/hermes/.venv/bin/hermes -p memento-ingest gateway run',
    background=True,
    watch_patterns=['Gateway running', 'Cron ticker started', 'ERROR']
)
```

## Safety-net script

For environments where the agent CLI cannot avoid running as root (e.g., the user's main shell is rooted), install a chown-sweep script that can be re-run after any session:

```bash
cat > /opt/data/bin/fix-hermes-ownership.sh <<'EOF'
#!/bin/bash
set -e
HERMES_HOME="${HERMES_HOME:-/opt/data}"
[ "$(id -u)" = "0" ] || { echo "must run as root"; exit 1; }
before=$(find "$HERMES_HOME" -not -user hermes 2>/dev/null | wc -l)
chown -R hermes:hermes "$HERMES_HOME"
after=$(find "$HERMES_HOME" -not -user hermes 2>/dev/null | wc -l)
echo "fixed $((before - after)) files; remaining non-hermes: $after"
EOF
chmod +x /opt/data/bin/fix-hermes-ownership.sh
```

Wire it into the agent's tooling habit: after any large multi-file operation that touched `/opt/data` while running as root, run the script. It is idempotent and cheap.

## What the dashboard actually shows

The Hermes dashboard process reads from `<HERMES_HOME>/cron/jobs.json` — the **default profile's** cron file. It does NOT enumerate per-profile cron jobs in the current implementation. So even with perfect ownership:

- A cron job created under a non-default profile (via `hermes -p <worker> cron create ...`) lives at `/opt/data/profiles/<worker>/cron/jobs.json`.
- The dashboard's `/api/cron/jobs` endpoint will return `[]` for that, because the dashboard is bound to the default profile's `JOBS_FILE`.
- The CLI sees it correctly with `hermes -p <worker> cron list --all`.

If the user expects the dashboard to display the job, either:

1. Create the cron job in the default profile and pass `--workdir /memento` so it runs in the right repo (sacrifices the per-profile SOUL.md/model identity), OR
2. Accept that the dashboard is a default-profile-only view and use the CLI for per-profile cron management.

This is a Hermes dashboard limitation, not an ownership bug. Tell the user explicitly so they don't keep refreshing the dashboard waiting for the job to appear.
