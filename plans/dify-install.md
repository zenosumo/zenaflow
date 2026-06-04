# Dify Install Plan

Status: planning. Dify is not installed yet.

## Goal

Install Dify on the Zenaflow VPS as a separate, isolated Compose project while keeping the existing n8n/Open WebUI/Hermes stack stable.

Dify will be used as an AI-native workflow/app platform. It will later connect to the sterile Hermes `robot` profile as an OpenAI-compatible model provider, but the provider should be configured after Dify itself is healthy.

## Confirmed decisions

### Exposure and routing

- Public hostname: `dify.zenaflow.com`.
- Cloudflare Zero Trust is already in place for `dify.zenaflow.com`.
- Caddy will reverse proxy `dify.zenaflow.com` to Dify.
- Dify web/proxy entrypoint host binding:
  - `127.0.0.1:8088`
- Do not bind Dify directly to `0.0.0.0`.
- Do not use ports `3002` through `3020`; reserve that range for future chat/WebUI tools.
- Only the Dify web/proxy entrypoint should be host-published. Internal services must not expose host ports.
- Use the existing `/opt/core/Caddyfile` directly for the initial Dify route.
- Validate the current Caddyfile before editing, validate again after editing, and reload Caddy only after validation passes.
- Use a dedicated Dify Caddy access log matching the existing per-service pattern:
  - `/var/log/caddy/dify_access.log`
- If the official Dify bundle includes its own nginx/proxy service, keep it and point Caddy to that single Dify entrypoint.
- Keep Dify's default internal ports from the official bundle; only remap the host-published entrypoint to `127.0.0.1:8088`.

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

Implementation workflow:

- Install only Dify now; leave RAGFlow untouched.
- Inspect Dify's current official Docker Compose bundle/docs live before preparing install files.
- Use `/tmp/dify-prepare` as a temporary staging/inspection directory.
- If `/opt/core/dify` already exists and is non-empty, make a timestamped backup before modifying it.
- Prepare files/config first, summarize the intended changes, and ask for approval before starting containers.
- Do a live VPS resource/headroom check before install/start: CPU/load, memory, disk, Docker status/stats, existing service health, and whether `127.0.0.1:8088` is free.
- Commit after each meaningful docs/config phase. Keep Dify marked planned/prepared in docs until it is actually running and verified.
- Set `COMPOSE_PROJECT_NAME=dify` for predictable Compose naming.
- Prefer bind-mounted persistent directories under `/opt/core/dify/volumes/` where practical; use Docker named volumes only where the official bundle strongly expects them.
- Use `restart: unless-stopped` for Dify services unless the official bundle already uses an equivalent policy.

### Data services and storage

- Use Dify-owned dedicated services from the official bundle:
  - dedicated Dify Postgres
  - dedicated Dify Redis
  - dedicated Dify vector database/container
- If the official bundle offers multiple vector backends, use Dify's official default/recommended dedicated vector backend rather than forcing Zenaflow's existing Qdrant.
- Do not share existing Zenaflow Postgres, Redis, or Qdrant.
- Use local filesystem storage under `/opt/core/dify/` for the initial install.
- Do not configure S3/R2/MinIO/object storage initially.
- Set an initial Dify upload/file-size limit of 100 MB if Dify supports it cleanly; keep the official lower default if it is already lower.

### Networks

- Keep Dify internal services on Dify's own Compose network where possible.
- Attach only the Dify service(s) that need to call model providers to the existing external Docker network `core_core_net` so they can reach Hermes at:
  - `http://hermes:8648/v1`
- Do not attach Dify Postgres/Redis/vector DB to `core_core_net` unless the official service topology requires it.

### Email and accounts

- Leave SMTP/email unconfigured initially unless Dify hard-requires it.
- Disable public self-registration / use admin-only accounts initially.
- The user will create the initial Dify admin account through the UI after the service is reachable. Do not create or handle admin credentials in chat/terminal logs.
- Public self-registration can be enabled later if desired, preferably still behind Cloudflare Zero Trust.

### Dify secrets and .env files

- Use Dify-specific config/secrets in:
  - `/opt/core/dify/.env`
- Do not place Dify's large app-specific secret set in `/opt/core/.env`.
- `/opt/core/.env` remains for the existing core Compose stack and shared/core services.
- Sparse per-app `.env` files are preferred for separate Compose projects.
- Do not reuse existing Zenaflow, n8n, Hermes, or Open WebUI secrets for Dify.
- Generate new Dify-only secrets for Dify's `SECRET_KEY`, DB password, Redis password, sandbox/plugin secrets, and other required secret values.
- Do not paste secrets into docs, chat, git diffs, or logs.
- Keep `/opt/core/dify/.env` runtime-only and out of git; do not copy it into `/opt/zenaflow`.
- Skip creating a local sanitized Dify env example for now; rely on upstream examples plus this plan.

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
5. Confirm Cloudflare Zero Trust protects `dify.zenaflow.com` before treating the app as internet-facing; user says Zero Trust is already in place.
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
6. Review file upload limits and storage location; target initial cap is 100 MB if supported cleanly.
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

## Future RAGFlow note

RAGFlow is explicitly out of scope for this installation. Install only Dify in this stage.

When planning RAGFlow later, reuse the same default deployment preferences from this Dify plan unless RAGFlow has a specific reason to differ:

- separate Compose project under `/opt/core/ragflow/`
- dedicated app-local `.env`, runtime-only and out of git
- generated app-only secrets, no reused n8n/Hermes/Open WebUI secrets
- dedicated app-owned database/cache/vector/search services instead of sharing core Zenaflow services, unless the official RAGFlow bundle requires otherwise
- localhost-only published web entrypoint behind Caddy and Cloudflare Zero Trust
- no direct `0.0.0.0` exposure
- existing `/opt/core/Caddyfile` route with validate-before/after flow
- dedicated Caddy access log
- official stable Docker Compose bundle as base
- pin official stable image tags
- staging directory before writing final runtime files
- backup existing runtime dir if non-empty
- prepare files/config first, summarize diff, ask before starting containers
- live resource/headroom check before start
- commit after each meaningful docs/config phase
- keep future docs marked planned/prepared until verified

For RAGFlow, ask the user only for decisions not already covered by this plan or where RAGFlow's official bundle creates a new tradeoff.

## Open questions before install

Most deployment-shape decisions are resolved. Remaining questions should be limited to items discovered from the live official Dify bundle or VPS resource check, such as:

1. Which exact official Dify stable release/tag is current at preparation time?
2. Which service in that release is the correct single web/proxy entrypoint for `127.0.0.1:8088`?
3. Which Dify service(s) in that release must join `core_core_net` to reach Hermes `robot`?
4. What exact env variable controls signup/self-registration and the 100 MB upload limit in that release?
5. Are VPS resources sufficient, or are service limits/swap/postponement needed before start?

Do not re-ask decisions already recorded above unless the official Dify bundle conflicts with them.
