# CLIProxyAPI Install Plan

Status: infrastructure installed and verified. CLIProxyAPI v7.1.74 is running under `/opt/core/cliproxyapi`; Codex/OpenAI OAuth and Dify provider setup remain manual follow-up work.

## Goal

Install CLIProxyAPI on the Zenaflow VPS as an internal-only LLM proxy service for other VPS services, especially future Dify provider use.

This plan intentionally does not touch Dify during the CLIProxyAPI installation stage. Dify integration is a later phase after CLIProxyAPI is installed, configured, authenticated with Codex/OpenAI, and verified as an OpenAI-compatible endpoint.

## Architecture

CLIProxyAPI will run as a separate Docker Compose project under `/opt/core/cliproxyapi/`, following the same separate-runtime-project pattern used by Dify and Honcho. It will be reachable only by internal VPS services and local VPS checks, not as a public internet-facing application.

Dify will eventually call CLIProxyAPI over Docker networking with an OpenAI-compatible base URL such as:

```text
http://cliproxyapi:8317/v1
```

The first upstream provider will be Codex/OpenAI OAuth, but upstream OAuth/account authorization is a manual post-install step and is not part of the initial infrastructure deployment.

## Confirmed decisions

### Service purpose and exposure

- CLIProxyAPI is an internal VPS service.
- Primary consumer: Dify, in a later provider-configuration phase.
- Other future internal VPS consumers may use it if appropriate.
- Do not expose CLIProxyAPI publicly during the initial install.
- Do not add a Caddy hostname during the initial install.
- Do not create a Cloudflare Access application during the initial install.
- Do not open firewall ports for CLIProxyAPI.
- If a host port is published for testing/admin access, bind it to localhost only:
  - `127.0.0.1:8317:8317`
- Prefer internal Docker access for service-to-service traffic:
  - `http://cliproxyapi:8317/v1`

### Runtime layout

Use a separate runtime directory:

```text
/opt/core/cliproxyapi/
  docker-compose.yml
  .env                       # optional, runtime-only, not committed
  config.yaml                # runtime config and client-facing API keys; not committed
  auths/                     # persisted OAuth/provider auth files
  logs/                      # persisted app logs if file logging is enabled
```

Repository-side plan path:

```text
/opt/zenaflow/plans/cliproxyapi-install.md
```

Local planning path:

```text
/Users/kris/Projects/zenaflow/plans/cliproxyapi-install.md
```

### Image/version policy

- Use the latest stable CLIProxyAPI image/release available at installation time.
- Prefer a stable/versioned Docker image tag if upstream publishes one clearly.
- If upstream only provides a floating `latest` Docker tag, verify the image version at deployment time and document the exact observed application version in this plan or a follow-up ops note.
- Do not add a CLIProxyAPI-specific update script in this plan.
- Do not add automatic update/watchtower behavior for CLIProxyAPI in this plan.
- Future container update automation is out of scope here and should be handled later by a separate, centralized update service covering multiple Zenaflow containers.

Observed during planning:

- Upstream project: `router-for-me/CLIProxyAPI`
- Upstream GitHub repo: `https://github.com/router-for-me/CLIProxyAPI`
- Latest stable release selected at install time: `v7.1.74`
- Installed image: `eceasy/cli-proxy-api:v7.1.74`
- Official Compose example image observed during planning: `eceasy/cli-proxy-api:latest`
- Default API port: `8317`

Before implementation, re-check the current latest stable release/image rather than relying on this planning-time observation.

### Initial provider scope

- Initial upstream provider: Codex/OpenAI OAuth.
- Do not configure Claude Code, Gemini, Qwen, Grok, or multi-provider routing in the first infrastructure install.
- Do not configure multi-account rotation in the first infrastructure install.
- Add additional providers/accounts only after one Codex/OpenAI path is verified end-to-end.

### OAuth/account authorization

OAuth/provider authorization is post-install manual setup.

Initial install should:

- create the runtime directory structure;
- create/persist `config.yaml`;
- create/persist `auths/`;
- start the container;
- verify the service is reachable locally/internally;
- verify client-facing API authentication behavior where possible.

Initial install should not:

- perform Codex/OpenAI OAuth login automatically;
- handle browser/device-code credentials in chat logs;
- paste provider tokens into docs, terminal output, or git;
- touch Dify provider settings.

Post-install manual provider setup will add Codex/OpenAI OAuth credentials into `/opt/core/cliproxyapi/auths/` through the CLIProxyAPI-supported login/management workflow.

### Client-facing API key

Generate a dedicated internal client API key for Dify during CLIProxyAPI install.

- Store the key only in runtime config:
  - `/opt/core/cliproxyapi/config.yaml`
- Do not commit the key.
- Do not paste the key into docs, chat, git diffs, or logs.
- Document only the key location and purpose:
  - purpose: Dify client key for CLIProxyAPI
  - location: `/opt/core/cliproxyapi/config.yaml` under `api-keys`

Future Dify provider setup should use:

```text
Base URL: http://cliproxyapi:8317/v1
API key: read from /opt/core/cliproxyapi/config.yaml under api-keys
Model: chosen after Codex/OpenAI OAuth and model listing are verified
```

### Management UI/API

- Keep management local/internal only for the first phase.
- Do not expose `/management.html` through Caddy in the first phase.
- Configure a strong management secret if the Management API/UI is enabled.
- If possible, disable remote management or restrict it to localhost/internal access.
- If browser-based management is needed, use an SSH tunnel or VPS-local workflow rather than a public hostname.

### Networking

Target network shape:

- Attach CLIProxyAPI to the existing external Docker network:
  - `core_core_net`
- Use a stable Docker DNS name for internal consumers:
  - `cliproxyapi`
- Publish at most one localhost-only port for host-local checks:
  - `127.0.0.1:8317:8317`
- Do not publish the extra ports shown in upstream's generic Compose example unless implementation-time inspection proves they are required.

Known existing relevant ports from planning:

- Dify: `127.0.0.1:8088`
- Open WebUI: `127.0.0.1:3001`
- Hermes/Argo API: `127.0.0.1:8642`
- Hermes dashboard: `127.0.0.1:9119`
- CLIProxyAPI default port `8317` appeared unused during the planning check.

Before implementation, verify port availability again on the live VPS.

### Storage and persistence

Persist these paths under `/opt/core/cliproxyapi/`:

- `config.yaml`
  - service config;
  - client-facing API keys;
  - management secret/config;
  - provider/channel declarations as needed.
- `auths/`
  - OAuth/provider credentials created during manual post-install authorization.
- `logs/`
  - app logs if file logging is enabled.

Do not use Zenaflow's existing Postgres, Redis, or Qdrant for initial CLIProxyAPI deployment.

Optional remote token stores from upstream, such as Postgres, git-backed config, or object storage, are out of scope for the first install unless live upstream inspection shows they are required.

### Dify relationship

Dify is already installed under:

```text
/opt/core/dify/
```

Dify's current Hermes robot provider path remains unchanged by this plan:

```text
http://hermes:8648/v1
model: robot
```

Do not change Dify during CLIProxyAPI installation.

Later, after CLIProxyAPI is healthy and Codex/OpenAI OAuth is configured, a separate Dify provider task can add CLIProxyAPI as another OpenAI-compatible provider.

That later task must verify that the Dify container that performs provider validation can resolve and reach `cliproxyapi` over Docker networking. The earlier Dify install showed that provider validation may happen through `plugin_daemon`, not only the `api` container, so network reachability must be checked from the relevant Dify container(s) before assuming UI validation will work.

## Current VPS context observed during planning

Read-only planning checks observed:

- VPS host: `core-hub-01`
- SSH user: `appdev`
- Runtime directory convention: `/opt/core`
- Repo/docs/plans directory: `/opt/zenaflow`
- Core Docker network: `core_core_net`
- VPS headroom at planning time:
  - RAM: `7.6Gi` total, about `3.7Gi` available
  - zram/swap: `4.0Gi` total, about `2.3Gi` free
  - root disk: `75G` total, about `24G` available, `68%` used
  - load average: low
- Core services running at planning time included:
  - `hermes`
  - `n8n`
  - `n8n-mcp`
  - `open-webui`
  - `postgres`
  - `redis`
  - `qdrant`
  - `pgadmin`
  - `redisinsight`
- Dify services were also running from `/opt/core/dify`.

These observations are not a substitute for implementation-time checks. Re-check live state before making changes.

## Implementation tasks

### Task 1: Re-check live VPS state

Objective: confirm the live VPS still matches the assumptions in this plan.

Commands:

```bash
ssh appdev@zenaflow 'hostname && whoami && pwd'
ssh appdev@zenaflow 'uptime; free -h; df -h /; swapon --show'
ssh appdev@zenaflow 'cd /opt/core && docker compose ps --format "table {{.Name}}\t{{.Service}}\t{{.State}}\t{{.Status}}\t{{.Ports}}"'
ssh appdev@zenaflow 'cd /opt/core/dify && docker compose ps --format "table {{.Name}}\t{{.Service}}\t{{.State}}\t{{.Status}}\t{{.Ports}}"'
ssh appdev@zenaflow 'ss -tln | grep -E ":(8317|8088|3001|8642|9119)" || true'
```

Expected:

- SSH works as `appdev`.
- Load, memory, swap, and disk headroom are acceptable.
- Existing core and Dify services are stable.
- Port `8317` is free or only occupied by an expected existing CLIProxyAPI instance.

Stop and ask before proceeding if live state conflicts with this plan.

### Task 2: Inspect current upstream release/image details

Objective: select the current latest stable CLIProxyAPI image/release at install time.

Checklist:

1. Check the latest upstream stable release:
   - `https://github.com/router-for-me/CLIProxyAPI/releases/latest`
2. Check whether the official Docker image has versioned tags corresponding to that release.
3. Prefer the latest stable versioned image tag if available.
4. If only `latest` is available, document the observed CLIProxyAPI application version immediately after first start.
5. Do not implement automatic updates.

Expected output for the implementation record:

```text
Selected image: <image>:<tag>
Observed CLIProxyAPI version: <version>
Reason: latest stable available at install time
```

### Task 3: Prepare runtime directory and files

Objective: create `/opt/core/cliproxyapi/` with runtime-only config and persistent directories.

Target paths:

```text
/opt/core/cliproxyapi/
  docker-compose.yml
  config.yaml
  auths/
  logs/
```

Security requirements:

- Keep `config.yaml` out of git.
- Keep generated API keys and management secrets out of chat/logs.
- Use restrictive file permissions where practical.
- If sudo is needed to create directories or set ownership under `/opt/core`, explain the exact command and ask for approval before running it.

### Task 4: Generate local secrets

Objective: generate CLIProxyAPI-local secrets without exposing values.

Generate:

- one management secret if Management API/UI is enabled;
- one dedicated Dify client API key under `api-keys`.

Store only in:

```text
/opt/core/cliproxyapi/config.yaml
```

Do not print the generated values. Verify only by checking that non-empty entries exist, redacted.

### Task 5: Create minimal Zenaflow-specific config

Objective: create a conservative `config.yaml` suitable for internal-only first boot.

Minimum intended settings:

```yaml
host: "0.0.0.0"
port: 8317
auth-dir: "/root/.cli-proxy-api"
api-keys:
  - "<generated-dify-client-key>"
remote-management:
  allow-remote: false
  secret-key: "<generated-management-secret-or-disabled>"
  disable-control-panel: false
logging-to-file: true
logs-max-total-size-mb: 100
error-logs-max-files: 10
```

Notes:

- `host: "0.0.0.0"` is acceptable inside the container because host publishing is localhost-only and Docker-network access is intentional.
- `auth-dir` should match the mounted persistent auth directory inside the container.
- Confirm exact supported config fields against the current upstream config example before writing the final file.
- If management should be fully disabled instead of local/internal, use upstream-supported settings to disable it cleanly.

### Task 6: Create Docker Compose file

Objective: create a minimal Compose file rather than using upstream's broad generic port exposure.

Intended shape:

```yaml
services:
  cliproxyapi:
    image: <selected-stable-image>
    container_name: cliproxyapi
    restart: unless-stopped
    ports:
      - "127.0.0.1:8317:8317"
    volumes:
      - ./config.yaml:/CLIProxyAPI/config.yaml:ro
      - ./auths:/root/.cli-proxy-api
      - ./logs:/CLIProxyAPI/logs
    networks:
      - core_core_net

networks:
  core_core_net:
    external: true
```

Implementation-time checks:

- Confirm the image expects config at `/CLIProxyAPI/config.yaml`.
- Confirm the image expects auth persistence at `/root/.cli-proxy-api` or adjust mount path to match upstream docs.
- Confirm the image writes logs to `/CLIProxyAPI/logs` when file logging is enabled.
- Confirm whether a healthcheck endpoint exists and add one if supported.
- Do not publish upstream example ports `8085`, `1455`, `54545`, `51121`, or `11451` unless a required use case is discovered and approved.

### Task 7: Start CLIProxyAPI only after review/approval

Objective: start only the new CLIProxyAPI container after showing the prepared files/config summary.

Before starting:

- summarize the selected image/version;
- summarize generated-secret locations without values;
- summarize network and port exposure;
- confirm no Dify/Caddy/Cloudflare changes are included;
- ask for approval to start the container.

Start command:

```bash
cd /opt/core/cliproxyapi && docker compose up -d
```

If sudo is required on the VPS, follow the repo sudo-approval rule before running the command.

### Task 8: Verify first boot

Objective: prove the service is running without exposing it publicly.

Checks:

```bash
cd /opt/core/cliproxyapi && docker compose ps
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8317/v1/models
curl -sS -H "Authorization: Bearer <redacted-dify-client-key>" http://127.0.0.1:8317/v1/models
```

Expected:

- Container is running.
- Unauthenticated request is rejected if auth is enforced.
- Authenticated request reaches the service.
- Before Codex/OpenAI OAuth is configured, model listing may be empty or limited; record exact behavior.

Also verify Docker-network DNS from a temporary container or an existing relevant container without changing Dify config:

```bash
# Example shape only; choose a safe implementation-time method.
docker run --rm --network core_core_net curlimages/curl:latest \
  curl -sS -H AUTHORIZATION_HEADER_REDACTED http://cliproxyapi:8317/v1/models
```

Do not paste the real key into logs or docs.

### Task 9: Manual post-install Codex/OpenAI OAuth setup

Objective: add the first upstream provider credential manually after infrastructure is healthy.

This is not part of the automated install.

Post-install operator steps should be based on the current upstream docs, but the intended shape is:

1. Enter the CLIProxyAPI container or use its management workflow.
2. Run the upstream-supported Codex/OpenAI OAuth login flow.
3. Complete browser/device-code authorization manually.
4. Persist the resulting auth files under `/opt/core/cliproxyapi/auths/`.
5. Restart/reload CLIProxyAPI only if upstream requires it.
6. Verify `/v1/models` returns the expected Codex/OpenAI-backed models.
7. Verify one minimal chat completion using the Dify client key.

Do not paste OAuth tokens or account credentials into chat, docs, git diffs, or logs.

### Task 10: Future Dify provider setup

Objective: configure Dify to use CLIProxyAPI after CLIProxyAPI itself is proven.

This is a later task, not part of the initial install.

Future Dify provider values:

```text
Provider type: OpenAI-compatible
Base URL: http://cliproxyapi:8317/v1
API key: read from /opt/core/cliproxyapi/config.yaml under api-keys
Model: selected verified Codex/OpenAI model or alias
```

Future Dify verification must include:

- network reachability from the Dify container that validates provider credentials;
- model listing or provider validation in Dify;
- one simple generation through Dify;
- confirmation that existing Hermes robot provider remains unaffected.

## Installation verification

Verified after infrastructure start:

- Runtime directory exists at `/opt/core/cliproxyapi/`.
- Compose file exists at `/opt/core/cliproxyapi/docker-compose.yml`.
- Runtime config exists at `/opt/core/cliproxyapi/config.yaml` with mode `0600`; secrets are not committed.
- Container `cliproxyapi` is running from image `eceasy/cli-proxy-api:v7.1.74`.
- Container restart policy is `unless-stopped`.
- Container is attached to `core_core_net`.
- Host-published port is localhost-only: `127.0.0.1:8317 -> 8317`.
- Unauthenticated `/v1/models` returns `401` with `Missing API key`.
- Authenticated `/v1/models` returns `200` and an empty model list before provider OAuth is configured.
- Docker-network check from `core_core_net` reaches `http://cliproxyapi:8317/v1/models` with the internal API key.
- Resource snapshot after start showed about `16 MiB` memory use for `cliproxyapi`.

Remaining manual follow-up:

1. Run the upstream-supported Codex/OpenAI OAuth login workflow.
2. Confirm `/v1/models` lists expected Codex/OpenAI-backed models.
3. Run one minimal chat completion directly against CLIProxyAPI.
4. Configure Dify later as a separate task, using `http://cliproxyapi:8317/v1` and the internal Dify client key from `/opt/core/cliproxyapi/config.yaml`.

## Documentation updates after successful install

After CLIProxyAPI is actually installed and verified, update:

- `/opt/zenaflow/doc/vps_architecture.md`
  - add CLIProxyAPI to filesystem layout under `/opt/core/cliproxyapi/`;
  - add CLIProxyAPI to service inventory;
  - document internal API URL `http://cliproxyapi:8317/v1`;
  - document host-local check URL `http://127.0.0.1:8317/v1` if localhost binding is kept;
  - document that there is no Caddy/public hostname;
  - document that CLIProxyAPI is intended for internal Dify/future service use;
  - document where runtime config/auths/logs live without secrets.

Do not mark the service installed in architecture docs until it is actually running and verified.

## Rollback plan

If the initial install fails before OAuth setup:

1. Stop only the CLIProxyAPI Compose project:

   ```bash
   cd /opt/core/cliproxyapi && docker compose down
   ```

2. Preserve `/opt/core/cliproxyapi/config.yaml` and `auths/` for inspection unless secrets need immediate removal.
3. Do not modify Dify, Caddy, Cloudflare, or core stack services.
4. If the container caused unexpected load, verify:

   ```bash
   uptime
   free -h
   docker stats --no-stream
   ```

5. Remove or archive `/opt/core/cliproxyapi/` only after confirming no needed credentials or logs remain.

## Out of scope

- No Dify provider changes during initial CLIProxyAPI install.
- No Caddy route.
- No Cloudflare Access app.
- No public DNS.
- No firewall changes.
- No multi-provider setup.
- No multi-account rotation.
- No per-app update script.
- No centralized container update service.
- No migration of existing Hermes robot provider.
- No use of existing Zenaflow Postgres/Redis/Qdrant for CLIProxyAPI storage.

## Open items for implementation time

These are not user preference questions; resolve them by inspecting current upstream docs/images during implementation:

- exact latest stable image tag available at install time;
- exact CLIProxyAPI version command or endpoint;
- exact healthcheck endpoint, if any;
- exact Codex/OpenAI OAuth login command/workflow;
- exact config field names supported by the selected release;
- whether Management API can be fully disabled or should stay local/internal with a secret;
- whether the official image runs as root or a non-root user and whether file ownership adjustments are needed for mounted dirs.
