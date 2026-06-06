# Dify Install Plan

Status: installed and verified. Dify 1.14.2 is running under `/opt/core/dify` behind Caddy at `dify.zenaflow.com`.

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


## Installation verification

Verified after start:

- Caddy route installed live in `/etc/caddy/Caddyfile` and reloaded successfully.
- Dedicated Dify Caddy log exists at `/var/log/caddy/dify_access.log` owned by `caddy:caddy` with mode `0600`.
- Dify Compose project `dify` is running from `/opt/core/dify`.
- Host-published Dify port is only `127.0.0.1:8088 -> nginx:80`.
- `plugin_daemon` has no host-published debug/public port.
- `db_postgres`, `redis`, `sandbox`, and `api` health checks reached healthy state.
- Local web check succeeded: `http://127.0.0.1:8088/` returns the Dify web app after redirect.
- Setup API check succeeded: `http://127.0.0.1:8088/console/api/setup` returned `{"step":"not_started","setup_at":null}`.
- From inside the Dify `api` container, `http://hermes:8648/v1/models` reached Hermes `robot` and returned model `robot` when using the robot API key.
- Public `https://dify.zenaflow.com` is behind Cloudflare Access / Zero Trust.

Install notes:

- Initial image pull failed once because `/` reached about 95% usage and Docker reported `no space left on device`.
- Reclaimed space with `docker image prune -af` and `docker builder prune -af`; no Docker volumes were pruned.
- Disk improved to about `35G/75G` used (`49%`) before the successful second start.
- The VPS load average spiked during image extraction/startup; after startup, Dify containers were running but memory remained tight. Keep an eye on memory/load during first UI use.

Remaining manual setup:

1. Visit `https://dify.zenaflow.com` through Cloudflare Zero Trust.
2. Create the initial Dify admin account yourself in the UI.
3. Configure the OpenAI-compatible model provider for Hermes `robot` in the Dify UI:
   - Base URL: `http://hermes:8648/v1`
   - Model: `robot`
   - API key source: `/opt/core/hermes_data/profiles/robot/.env`, variable `API_SERVER_KEY`
4. Do not paste the robot API key into docs/chat.

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


---

## Incident note — 2026-06-05

### What happened

After Dify was installed and started, the VPS became critically overloaded:

- Load average reached 190+ (4 vCPU machine)
- RAM: 7.6 GB total, ~7.2 GB used, no swap configured
- SSH banner exchange was timing out; the machine was effectively unreachable

Root causes identified:

1. No swap — with all 26 containers running and no swap buffer, any memory spike caused
   the OOM killer to fire, creating a load spiral.
2. Runaway Cloudflare MCP node processes — 10+ stray node processes each consuming
   1-2% CPU and 1-2% RAM continuously (~300 MB total).
3. Dify adds ~1.5 GB RAM across its 12 containers on top of an already tight stack.

### What was done

1. Hard shutdown via Hetzner console (SSH was unresponsive).
2. After reboot: stopped all 26 containers with docker stop + docker rm.
3. Installed linux-modules-extra and zram-tools.
4. Configured 4 GB zram device with lz4 compression, priority 100.
   - Effective swap capacity: ~10 GB (at ~2.5:1 compression ratio)
   - Zero disk I/O overhead
   - Persistent via zramswap.service (enabled, starts on boot)
5. Tuned kernel: vm.swappiness=100, vm.vfs_cache_pressure=500 (persisted in /etc/sysctl.conf).
6. Set all container restart policies to no to prevent auto-restart until deliberately brought up.

### Current state (2026-06-05)

- All containers: Exited, restart=no (will not auto-start on next reboot)
- zram: /dev/zram0 4 GB lz4 active, 0 used — NO reboot needed, already live
- RAM available (no containers): ~6.9 GB free
- Load: 0.39

### Remaining work before bringing containers back up

1. Fix Caddy TLS block for dify.zenaflow.com:
   - Current block attempts public ACME (Let's Encrypt http-01/tls-alpn-01)
   - Both challenges fail because Cloudflare Access intercepts the domain
   - Fix: use same TLS strategy as other working sites (likely Cloudflare Origin cert or tls internal)
2. Decide which containers to bring up and in what order.
3. Consider whether pgadmin and redisinsight need to run 24/7 (saves ~350 MB RAM).
4. Consider upgrading Hetzner plan for more RAM if zram proves insufficient under full load.


### Robot model provider — plugin_daemon network fix (2026-06-05)

Dify model-credential validation runs through the `plugin_daemon` container, not `api`.
Symptom: validation failed with `Failed to resolve 'hermes'`.

Root cause: `plugin_daemon` was only attached to `ssrf_proxy_network` + `default`, so it
could not reach the `hermes` service on `core_core_net` (only `api` was on that network).

Fix (made permanent): added `core_core_net` to the `plugin_daemon` service `networks:` list
in /opt/core/dify/docker-compose.yaml, then `docker compose up -d plugin_daemon`.
Backup saved at /opt/core/dify/docker-compose.yaml.bak.

Verified after recreation:
- plugin_daemon networks: core_core_net, dify_default, dify_ssrf_proxy_network
- DNS: `getent hosts hermes` -> 172.18.0.5 hermes (persists across recreation)
- Auth: GET http://hermes:8648/v1/models with robot API_SERVER_KEY -> lists model "robot"
- E2E: POST /v1/chat/completions (model=robot) -> assistant replied "DIFY_TEST_OK"

Robot provider settings used in Dify (OpenAI-API-compatible):
- Base URL: http://hermes:8648/v1
- API key: API_SERVER_KEY from /opt/core/hermes_data/profiles/robot/.env (64-char hex)
- Model name: robot ; context 128000 ; max tokens 16384 ; Chat mode
- Vision/structured-output/document/stream-function-calling: off ; stream auth: on

Remaining: final credential-validation click-through in the Dify console (behind
Cloudflare Zero Trust email login — must be done interactively in a browser).

### Robot model VERIFIED working end-to-end via UI (2026-06-06)

Confirmed live: created a Chatflow app in Dify Studio, set the LLM node model to
`robot` (OpenAI-API-compatible), sent "Reply with exactly: ROBOT_OK" in the preview
chat — assistant replied "ROBOT_OK". Full chain proven: Dify UI -> api -> plugin_daemon
-> core_core_net -> hermes robot profile -> response.

DB confirms provider saved + valid:
- provider_models: langgenius/openai_api_compatible, model "robot", type llm, is_valid=t
- provider_model_credentials row present (created 2026-06-04)

#### Two follow-on bugs found and fixed while testing

1) Redis name collision (was causing "dancing dots" / request hang)
   Symptom: dify-api log spammed `redis.exceptions.AuthenticationError: AUTH <password>
   called without any password configured for the default user`. Chat requests hung
   forever and never reached the LLM.
   Root cause: after adding Dify's api/worker/worker_beat/api_websocket to core_core_net
   (needed to reach hermes), the generic name `redis` became ambiguous — it resolved to
   the CORE shared redis (172.18.0.7, NO password) instead of Dify's own dify-redis-1
   (172.23.0.3, password-protected). Dify sent its password to the passwordless core
   redis -> AUTH error.
   Also found: CELERY_BROKER_URL used stale password `difyai123456` which fails auth
   against dify-redis-1 (real pw = REDIS_PASSWORD value).
   Fix (in /opt/core/dify/.env, backup .env.bak_20260606T212325Z):
     - REDIS_HOST=redis            -> REDIS_HOST=dify-redis-1
     - CELERY_BROKER_URL: difyai123456@redis -> <REDIS_PASSWORD>@dify-redis-1
   Then: docker compose up -d api api_websocket worker worker_beat
   Note: db_postgres was NOT affected — Dify references it by the unambiguous name
   `db_postgres`, so only `redis` needed disambiguating. If more core services are ever
   joined to core_core_net, watch for the same generic-name collision (redis, postgres).

2) nginx 502 / "This page couldn't load" after recreating api
   Symptom: console showed "This page couldn't load"; nginx logged
   `connect() failed (111: Connection refused) ... upstream http://172.23.0.10:5001`.
   Root cause: most Dify nginx routes use static `proxy_pass http://api:5001;` — nginx
   resolves the name ONCE at startup and caches the IP. Recreating the api container
   gave it a new IP (172.23.0.11), so nginx kept hitting the dead old IP.
   Fix: `docker exec dify-nginx-1 nginx -s reload` (re-resolves, zero downtime). Console
   went 502 -> 200 immediately.

#### Operational rule — recreating Dify containers

- A full reboot is SAFE: all containers restart together, nginx resolves fresh IPs.
- `docker restart dify-api-1` is SAFE: restart keeps the same IP (no recreation).
- HAZARD: recreating api/web/plugin_daemon (docker compose up -d <svc>, image update,
  rm+recreate) while nginx keeps running -> nginx caches the stale IP -> 502s.
  REMEDY: after recreating any of those, run `docker exec dify-nginx-1 nginx -s reload`
  (or include nginx in the up: `docker compose up -d api nginx`).
- Only the websocket route uses `resolver 127.0.0.11 valid=30s` and self-heals in 30s;
  the console/api static routes do not. Do NOT hand-edit the nginx template (breaks on
  Dify upgrades) — just reload nginx after recreations.
