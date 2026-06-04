# Dify Install Plan

Status: planning. Dify is not installed yet.

## Goal

Install Dify on the Zenaflow VPS as a separate, isolated Compose project while keeping the existing n8n/Open WebUI/Hermes stack stable.

Dify will be used as an AI-native workflow/app platform. It will later connect to the sterile Hermes `robot` profile as an OpenAI-compatible model provider, but the provider should be configured after Dify itself is healthy.

## Confirmed decisions

### Exposure and routing

- Public hostname: `dify.zenaflow.com`.
- User will configure Cloudflare Zero Trust for `dify.zenaflow.com` in parallel with the install.
- Caddy will reverse proxy `dify.zenaflow.com` to Dify.
- Dify web/proxy entrypoint host binding:
  - `127.0.0.1:8088`
- Do not bind Dify directly to `0.0.0.0`.
- Do not use ports `3002` through `3020`; reserve that range for future chat/WebUI tools.
- Only the Dify web/proxy entrypoint should be host-published. Internal services must not expose host ports.

### Compose/project layout

- Use a separate Compose project under:
  - `/opt/core/dify/`
- Use Dify's official Docker Compose bundle as the base.
- Apply minimal Zenaflow-specific changes rather than hand-writing a minimal custom Compose.
- Keep Dify separate from `/opt/core/docker-compose.yml`.
- Use Dify's current official stable image tag from the bundle and pin images to that stable tag/version. Avoid floating `latest`/`main` unless explicitly reviewed.

Suggested layout:

```text
/opt/core/dify/
  docker-compose.yml
  .env
  volumes/
    ...
```

### Data services and storage

- Use Dify-owned dedicated services from the official bundle:
  - dedicated Dify Postgres
  - dedicated Dify Redis
  - dedicated Dify vector database/container
- Do not share existing Zenaflow Postgres, Redis, or Qdrant.
- Use local filesystem storage under `/opt/core/dify/` for the initial install.
- Do not configure S3/R2/MinIO/object storage initially.

### Networks

- Keep Dify internal services on Dify's own Compose network where possible.
- Attach only the Dify service(s) that need to call model providers to the existing external Docker network `core_core_net` so they can reach Hermes at:
  - `http://hermes:8648/v1`
- Do not attach Dify Postgres/Redis/vector DB to `core_core_net` unless the official service topology requires it.

### Email and accounts

- Leave SMTP/email unconfigured initially unless Dify hard-requires it.
- Disable public self-registration / use admin-only accounts initially.
- This can be enabled later if desired, preferably still behind Cloudflare Zero Trust.

### Dify secrets and .env files

- Use Dify-specific config/secrets in:
  - `/opt/core/dify/.env`
- Do not place Dify's large app-specific secret set in `/opt/core/.env`.
- `/opt/core/.env` remains for the existing core Compose stack and shared/core services.
- Sparse per-app `.env` files are preferred for separate Compose projects.
- Do not reuse existing Zenaflow, n8n, Hermes, or Open WebUI secrets for Dify.
- Generate new Dify-only secrets for Dify's `SECRET_KEY`, DB password, Redis password, sandbox/plugin secrets, and other required secret values.
- Do not paste secrets into docs, chat, git diffs, or logs.

Robot provider reference in `/opt/core/dify/.env`:

- Include non-secret/provider-reference placeholders for later UI setup.
- Do not copy the actual robot API key initially.
- Use comments pointing to the source of truth:
  - `/opt/core/hermes_data/profiles/robot/.env`
  - variable: `API_SERVER_KEY`

Suggested placeholder shape:

```dotenv
# Robot Hermes provider reference for later Dify UI configuration.
# Do not duplicate the real API key here unless deliberately choosing convenience
# over single-source secret storage. Source of truth:
# /opt/core/hermes_data/profiles/robot/.env, variable API_SERVER_KEY
ROBOT_OPENAI_BASE_URL=http://hermes:8648/v1
ROBOT_OPENAI_MODEL=robot
ROBOT_OPENAI_KEY_LOCATION=see-robot-profile-env
```

### Worker/sandbox/plugin services

- Keep Dify sandbox, plugin, worker, and related official services enabled with official defaults for the first install.
- Do not expose their internal ports publicly.
- Revisit hardening/resource limits after first successful boot.

## Post-install settings and checks

These items should be completed after containers are up and before considering the install finished.

### Infrastructure checks

1. Confirm Dify Compose services are healthy.
2. Confirm only the intended host port is published:
   - `127.0.0.1:8088`
3. Confirm Dify internal services are not host-published:
   - Postgres
   - Redis
   - vector database
   - sandbox
   - worker
   - plugin daemon
4. Confirm Caddy proxies:
   - `dify.zenaflow.com` -> `127.0.0.1:8088`
5. Confirm Cloudflare Zero Trust protects `dify.zenaflow.com` before treating the app as internet-facing.
6. Confirm Dify data persists under `/opt/core/dify/` after restart.
7. Confirm Dify services can reach Hermes `robot` over Docker networking where needed:
   - `http://hermes:8648/v1`
8. Confirm Dify Postgres/Redis/vector services are isolated from the existing Zenaflow core data services.

### Dify app/admin settings

1. Create the initial admin account.
2. Disable public self-registration/admin-only accounts if the setting is not already enforced by environment config.
3. Leave SMTP/email disabled/unconfigured unless Dify requires it for the chosen account flow.
4. Review workspace/app visibility defaults.
5. Review any telemetry/analytics settings exposed by Dify and disable if desired.
6. Review file upload limits and storage location.
7. Review sandbox/plugin settings and make sure no public ports are exposed.

### Model provider setup after Dify is healthy

Configure the Hermes `robot` profile through the Dify UI after first boot.

Provider type:
- OpenAI-compatible

Base URL:
- `http://hermes:8648/v1`

Model:
- `robot`

API key:
- Read from `/opt/core/hermes_data/profiles/robot/.env`
- Variable: `API_SERVER_KEY`
- Do not paste the key into docs/chat.

Validation:
1. Use Dify's provider validation/test-generation UI.
2. Confirm the request reaches `robot`, not Argo or another Hermes profile.
3. Confirm Dify can generate a simple response through `robot`.
4. If provider validation fails, test from the relevant Dify container to `http://hermes:8648/v1/models` using the robot API key.

### Documentation updates after successful install

After Dify is actually installed and verified, update:

- `/opt/zenaflow/doc/vps_architecture.md`
  - add Dify to service inventory
  - document hostname and Caddy route
  - document localhost port `127.0.0.1:8088`
  - document separate Compose project under `/opt/core/dify/`
  - document dedicated Dify Postgres/Redis/vector DB
  - document sparse per-app `.env` usage
  - document post-install robot provider wiring if completed

Optionally update or create operational notes for backup/restore and upgrade procedure.

## Open questions before install

The remaining planning questions should be resolved before installation starts.
