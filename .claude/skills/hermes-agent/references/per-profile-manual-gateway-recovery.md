# Per-profile manual gateway recovery

Use this when a Telegram/other messaging bot tied to a non-default Hermes profile stops replying, especially in Docker or container setups where each profile gateway is run manually rather than as a systemd service.

## Symptom pattern

- `hermes profile list` shows the target profile's Gateway as `stopped` while the default profile is still `running`.
- `hermes -p <profile> gateway status` says `Gateway is not running` or shows stale health such as `Gateway draining for shutdown`.
- Profile-local `logs/gateway.log` ends with a planned `SIGTERM`, `planned gateway stop`, or shutdown notification.
- A user may have asked the bot itself to restart the gateway; if that profile has no durable supervisor, the stop side can succeed while the restart side does not persist.

## Recovery sequence

1. Verify the specific profile, not just global/default status:
   ```bash
   hermes profile show <profile>
   hermes -p <profile> gateway status
   ps -eo pid,ppid,etime,cmd | grep -E 'hermes.*-p <profile> gateway run|PID' | grep -v grep
   ```

2. Inspect profile-local logs:
   ```bash
   tail -n 80 ~/.hermes/profiles/<profile>/logs/gateway.log
   ```

   In container layouts, the profile directory may be under `/opt/data/profiles/<profile>/logs/gateway.log`.

3. If it is stopped, start the profile gateway explicitly:
   ```bash
   hermes -p <profile> gateway run
   ```

   In an agent/tool session, prefer a tracked background process rather than shell-level `nohup`/`&`, so lifecycle and output remain visible.

4. Verify readiness:
   ```bash
   hermes -p <profile> gateway status
   tail -n 50 ~/.hermes/profiles/<profile>/logs/gateway.log
   ```

   Look for:
   - `Connected to Telegram (polling mode)`
   - `✓ telegram connected`
   - `Gateway running with 1 platform(s)`

5. Ask the user to send a fresh Telegram message. Avoid relying on old pending updates; manual API polling can consume them before the gateway sees them.

## Durable fix

If the gateway should survive restarts, container restarts, SSH logout, or slash-command restarts, run it under a real supervisor:

- systemd user/system service where available: `hermes -p <profile> gateway install` or system-level install as appropriate.
- Docker/container supervisor/restart policy where systemd is not used.
- A long-lived process manager for profile-specific gateways.

Do not declare the bot healthy merely because the default Hermes gateway is running. Profiles own separate gateway state, logs, credentials, and sessions.