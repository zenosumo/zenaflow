# Telegram bot profile setup notes

Use this when creating or repairing a Hermes profile that should own its own Telegram bot identity.

## Pattern

1. Verify the profile exists and inspect it:
   ```bash
   hermes profile list
   hermes profile show <profile>
   hermes -p <profile> config path
   hermes -p <profile> config env-path
   hermes -p <profile> gateway status
   ```

2. A profile can appear in `hermes profile list` even if its `config.yaml` or `.env` is missing. If `profile show` reports no model or `.env: not configured`, repair the profile before starting the gateway.

3. For a chat bot profile, copy or set the model config deliberately, then create a profile-local `.env`.
   - Copying the default config is acceptable when the bot should use the same model/provider.
   - Do not copy another profile's `TELEGRAM_BOT_TOKEN`, `TELEGRAM_HOME_CHANNEL`, or Telegram allowlist values unless the user explicitly wants the same bot/chat identity.
   - Keep shared non-Telegram provider keys/settings if the profile needs the same model/web/tool credentials.

4. Put the new bot token in the profile-local env file:
   ```bash
   printf '\nTELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN_HERE\n' >> /opt/data/profiles/<profile>/.env
   chmod 600 /opt/data/profiles/<profile>/.env
   ```

5. Start and verify the profile's gateway:
   ```bash
   hermes -p <profile> gateway run
   hermes -p <profile> gateway status
   ```

   In containers without systemd, use a tracked/background process or `nohup` if the user wants it to survive the current shell:
   ```bash
   nohup hermes -p <profile> gateway run > /opt/data/profiles/<profile>/logs/gateway.out 2>&1 &
   ```

6. Test by sending a fresh message to the bot after the gateway starts. Avoid relying on old pending updates; manual Telegram API checks can consume updates before the gateway sees them.

## Pitfalls

- Never let two running Hermes gateways poll the same Telegram bot token unless that is explicitly intended; they will compete for updates.
- A profile-local `.env` should normally own the Telegram credential for that bot identity.
- If the user wants to add the token themselves, give exact commands and do not ask them to paste secrets into chat.
