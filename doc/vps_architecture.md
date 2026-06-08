# ZENAFLOW — CORE VPS ARCHITECTURE DOCUMENTATION

## 1. ACCESS LAYER
### 1.1 SSH (Primary Entry)
Preferred operational login:
```
ssh appdev@zenaflow
```

Legacy/root DNS entry, when needed for recovery work:
```
ssh root@core.zenaflow.com
```

Default noninteractive working directory for `appdev` is `/home/appdev`. Use `/opt/core` for live Docker/runtime operations and `/opt/zenaflow` for architecture docs, plans, and repo-tracked configuration.

### 1.2 SCP (Download Docker Compose)
```
scp root@core.zenaflow.com:/opt/zenaflow/docker/docker-compose.yml ./docker-compose.yml
```

### 1.3 SSH Tunnel (RedisInsight)
```
ssh -L 5555:localhost:5540 root@core.zenaflow.com
```
Browser:
```
http://localhost:5555
```

### 1.4 SSH Tunnel (pgAdmin)
```
ssh -L 8889:localhost:8889 root@core.zenaflow.com
```
Browser:
```
http://localhost:8889
```

### 1.5 Hetzner Console
Always works even if SSH/firewall is broken.

### 1.6 Tailscale + Samba (File Access from macOS Finder)
VPS is on Tailscale as `core-hub-01` (100.75.180.124). Connect in Finder:
```
smb://core-hub-01/share
```
Username: `zenaflow`. Requires Tailscale running on both Mac and VPS.

---

## 2. FILESYSTEM STRUCTURE
```
/opt/zenaflow                    ← git repo (infra config)
   CLAUDE.md
   docker/
      docker-compose.yml         ← symlinked from /opt/core/docker-compose.yml
   caddy/
      Caddyfile                  ← symlinked from /opt/core/Caddyfile
   doc/
   plans/

/opt/core                        ← live runtime data and Docker Compose stack
   docker-compose.yml            ← live Compose file for core services
   Caddyfile                     → symlink → /opt/zenaflow/caddy/Caddyfile
   .env                          ← POSTGRES_PASSWORD, N8N_API_KEY, N8N_MCP_AUTH_TOKEN, and other secrets
   n8n_data/
   postgres_data/
   redis_data/
   qdrant_storage/
   pgadmin_data/
   pgadmin_config/servers.json
   hermes_data/                  ← Hermes agent state (profiles, memories, skills, sessions)
      .env                       ← default Hermes/Argo profile env; API model name is `Argo`
      config.yaml                ← default Hermes/Argo config; includes n8n MCP server config
      profiles/moran/            ← Moran profile; Honcho memory config is profile-local here
      profiles/robot/            ← Sterile Hermes API profile reserved for future Dify/RAGFlow provider use
   open_webui_data/              ← Open WebUI persistent data (users, chats, settings)
   honcho/                       ← self-hosted Honcho memory stack for Hermes profile `moran`
      docker-compose.yml         ← separate Compose project (`honcho`), not part of `/opt/core/docker-compose.yml`
      .env                       ← Honcho LLM provider config/secrets (root-only)
      database/init.sql          ← pgvector init SQL for Honcho Postgres
   dify/                         ← Dify separate Compose project runtime directory
      docker-compose.yaml        ← Dify-specific Compose file based on official 1.14.2 bundle
      .env                       ← sparse Dify-only config/secrets; runtime-only, do not commit

/opt/memento                     ← second-brain Obsidian vault mounted into Hermes as `/memento`
```

### Sparse `.env` file convention

- `/opt/core/.env` is for the existing core Compose stack and shared/core service secrets such as n8n, core Postgres, and n8n MCP.
- Separate Compose projects should keep their own sparse app-local `.env` file beside their Compose file, containing only that app's required config/secrets.
- Current/planned examples:
  - Honcho: `/opt/core/honcho/.env`
  - Dify: `/opt/core/dify/.env` (runtime-only Dify secrets/config; not committed)
- Do not copy unrelated secrets between `.env` files. If a cross-service credential is needed, document the source-of-truth path and variable name instead of duplicating the secret unless deliberately choosing a copied-secret workflow.
- Never paste secret values into docs, chat, git diffs, or logs.

---

## 3. NETWORK & DOCKER ARCHITECTURE
Public ports:
- 22/tcp (SSH)
- 80/tcp (HTTP → redirected to HTTPS by Caddy)
- 443/tcp (HTTPS)
- 41641/udp (Tailscale direct connections)

### Tailscale Network
| Machine     | Tailscale IP    | Role         |
|-------------|-----------------|--------------|
| core-hub-01 | 100.75.180.124  | This VPS     |

### Docker Networks
```
core_core_net    (bridge)  Main application network, subnet 172.18.0.0/16
hermes_honcho    (bridge)  Private Hermes ↔ Honcho API network; no host-published ports
honcho_internal  (bridge)  Honcho API/worker ↔ Honcho Postgres/Redis only
```

Honcho isolation rule:
- `honcho-api` is reachable from `hermes` only via `hermes_honcho` at `http://honcho-api:8000`.
- `honcho-postgres` and `honcho-redis` are only on `honcho_internal`.
- Honcho exposes no host port; `127.0.0.1:8000` should refuse connections from the VPS host.

### Container IP Map
| Service      | IP          | Host Port (bound to 127.0.0.1) |
|--------------|-------------|-------------------------------|
| n8n          | 172.18.0.3  | 5678                          |
| postgres     | 172.18.0.5  | 5432                          |
| redis        | 172.18.0.2  | —                             |
| qdrant       | 172.18.0.7  | —                             |
| redisinsight | 172.18.0.4  | 5540                          |
| pgadmin      | 172.18.0.6  | 8889                          |
| hermes       | 172.18.0.8  | 8642 (Argo API), 8643-8648 (profile APIs), 9119 (dashboard) |
| open-webui   | dynamic     | 3001                          |
| n8n-mcp      | dynamic     | — (Docker-network only, port 3000 in `core_core_net`) |
| honcho-api   | dynamic     | — (Docker-network only)        |
| honcho-postgres | internal | —                              |
| honcho-redis | internal    | —                              |

---

## 4. CADDY REVERSE PROXY

Config: `/opt/zenaflow/caddy/Caddyfile` (source of truth)

```
n8n.zenaflow.com              → 127.0.0.1:5678   (n8n editor; Cloudflare Zero Trust protected)
webhook.n8n.zenaflow.com      → 127.0.0.1:5678   (temporary n8n webhook hostname; DNS-only/unproxied)
n8n-in.zenaflow.com           → 127.0.0.1:5678   (temporary n8n webhook hostname; Cloudflare proxied)
argo.zenaflow.com             → 127.0.0.1:3001   (Open WebUI — Cloudflare Zero Trust protected)
dashboard.zenaflow.com        → 127.0.0.1:9119   (Hermes dashboard)
dify.zenaflow.com             → 127.0.0.1:8088   (Dify — Cloudflare Zero Trust protected)
postgres.zenaflow.com         → 127.0.0.1:8889   (pgAdmin — Cloudflare Zero Trust protected)
redis.zenaflow.com            → 127.0.0.1:5540   (RedisInsight — Cloudflare Zero Trust protected)
```

Retired n8n hostnames:
- `workflow.zenaflow.com` removed from Caddy/DNS after migrating the editor to `n8n.zenaflow.com`.
- `webhook.zenaflow.com` removed from Caddy/DNS after introducing the temporary webhook hostnames above.

n8n webhook hostname policy:
- The canonical `WEBHOOK_URL` in Compose is currently `https://n8n-in.zenaflow.com/`.
- `n8n-in.zenaflow.com` and `webhook.n8n.zenaflow.com` are both kept temporarily for inbound webhooks while deciding which name to retain long-term.
- Both webhook hostnames are path-filtered in Caddy. Only `/webhook/*`, `/webhook-test/*`, `/form/*`, and `/form-waiting/*` pass through to n8n; all other paths return 404 so the editor, login, REST API, and static UI paths are not exposed on webhook ingress domains.

All Caddy domains:
- Cloudflare trusted proxy IPs configured in global block
- JSON access logs with 10MiB rotation, 7 files, 336h retention
- TLS handled by Caddy/Let's Encrypt at the origin; Cloudflare-proxied hostnames terminate public TLS at Cloudflare and connect to Caddy at the origin.

Log files:
```
/var/log/caddy/n8n_access.log
/var/log/caddy/webhook_n8n_access.log
/var/log/caddy/n8n_in_access.log
/var/log/caddy/argo_access.log
/var/log/caddy/dashboard_access.log
/var/log/caddy/dify_access.log
/var/log/caddy/postgres_access.log
/var/log/caddy/redis_access.log
```

---

## 5. SECURITY

### 5.1 SSH Hardening
- PasswordAuthentication no
- KbdInteractiveAuthentication no
- PubkeyAuthentication yes
- PermitRootLogin without-password
- UsePAM yes

### 5.2 UFW Firewall
Default:
- incoming: deny
- outgoing: allow

Allowed:
- 22/tcp
- 80/tcp
- 443/tcp
- 41641/udp (Tailscale)
- 445/tcp on tailscale0 (Samba — Tailscale only)
- 139/tcp on tailscale0 (Samba — Tailscale only)

Denied (public):
- 445/tcp (Samba blocked from internet)
- 139/tcp (NetBIOS blocked from internet)

### 5.3 Fail2Ban
Active jails:
- sshd
- caddy-login
- caddy-webhook
- recidive

Logpaths:
- /var/log/auth.log
- /var/log/caddy/n8n_access.log
- /var/log/caddy/webhook_n8n_access.log
- /var/log/caddy/n8n_in_access.log

### 5.4 Cloudflare Access (Zero Trust)
Cloudflare Access protects human-facing/admin UIs before unauthenticated requests reach the VPS.

- Team: `zenaflow.cloudflareaccess.com`
- Protected applications include:
  - `n8n.zenaflow.com` (n8n editor)
  - `argo.zenaflow.com` (Open WebUI)
  - `dify.zenaflow.com` (Dify)
  - `postgres.zenaflow.com` (pgAdmin)
  - `redis.zenaflow.com` (RedisInsight)
- Policy pattern: email allowlist with one-time email code (OTP), usually 24-hour sessions.

Webhook ingress hostnames are intentionally not protected by Cloudflare Access because external automation callers must be able to POST to them. They are instead constrained by Caddy path filters plus workflow-level authentication/secrets.

Any unauthenticated browser request to a protected hostname such as `n8n.zenaflow.com` or `argo.zenaflow.com` should be intercepted by Cloudflare and redirected to the Access login page before reaching the VPS.

---

## 6. SERVICES

### n8n
- Editor URL: `n8n.zenaflow.com` (Cloudflare Zero Trust protected)
- Canonical generated webhook URL: `n8n-in.zenaflow.com` (`WEBHOOK_URL=https://n8n-in.zenaflow.com/`)
- Temporary alternate webhook URL: `webhook.n8n.zenaflow.com` (DNS-only/unproxied)
- Retired URLs: `workflow.zenaflow.com` and `webhook.zenaflow.com`
- Webhook exposure: both temporary webhook hostnames are Caddy path-filtered to `/webhook/*`, `/webhook-test/*`, `/form/*`, and `/form-waiting/*`; all other paths return 404.
- Data: /opt/core/n8n_data
- DB: PostgreSQL `n8n` database
- Public API: enabled; API key stored in `/opt/core/.env` as `N8N_API_KEY`
- Current workflow inventory can be queried via n8n REST API or through Argo's n8n MCP tools

### n8n MCP Server
- Purpose: exposes n8n workflow-management tools to Argo via MCP
- Container: `n8n-mcp`
- Image: `ghcr.io/czlonkowski/n8n-mcp:latest`
- Internal URL from Hermes: `http://n8n-mcp:3000/mcp`
- Health endpoint: `http://n8n-mcp:3000/health`
- Transport: HTTP / Streamable HTTP with Bearer auth
- Auth token: `/opt/core/.env` variable `N8N_MCP_AUTH_TOKEN`; passed as `AUTH_TOKEN` and `MCP_AUTH_TOKEN`
- n8n API key: `/opt/core/.env` variable `N8N_API_KEY`
- Network: `core_core_net`; no public or localhost host port is exposed
- Hermes config: `/opt/core/hermes_data/config.yaml` under `mcp_servers.n8n`
- Verified tools: 24 n8n MCP tools, including workflow list/get/create/update/delete, validation, template search, executions, and health check


### Dify

- Application: Dify (`dify.zenaflow.com`)
- Current state: installed and verified; initial admin account still to be created by the user in the Dify UI
- Exposure: Caddy + Cloudflare Zero Trust; Caddy proxies to `127.0.0.1:8088`
- Runtime directory: `/opt/core/dify/`
- Compose file: `/opt/core/dify/docker-compose.yaml` based on official Dify `1.14.2` Docker bundle
- Compose project: `dify`
- Host-published Dify port: only `127.0.0.1:8088 -> nginx:80`
- Dedicated Caddy access log: `/var/log/caddy/dify_access.log`
- Dedicated Dify-owned services: Postgres, Redis, Weaviate vector DB, sandbox, plugin daemon, workers
- Dify internal proxy: keep official Dify `nginx` service; outer VPS Caddy proxies to it
- Persistent/runtime data: bind-mounted under `/opt/core/dify/volumes/` where supported by the official bundle
- Secrets/config: `/opt/core/dify/.env` (runtime-only, mode `0600`, not committed)
- Setup API after install: `/console/api/setup` returned `not_started`, so the first-user setup remains pending in the UI
- Robot provider setup: configure manually in Dify UI after first boot using OpenAI-compatible endpoint `http://hermes:8648/v1`, model `robot`, API key from `/opt/core/hermes_data/profiles/robot/.env` (`API_SERVER_KEY`)
- RAGFlow is not installed as part of the Dify stage.

### Open WebUI
- URL: argo.zenaflow.com (Cloudflare Zero Trust protected)
- Connects to Hermes API at `http://hermes:8642/v1` (OpenAI-compatible)
- Port: 127.0.0.1:3001
- Data: /opt/core/open_webui_data
- Image: ghcr.io/open-webui/open-webui:main

### Hermes Agent / Argo
- Default profile name in Open WebUI/API model list: `Argo`
- Dashboard: dashboard.zenaflow.com
- Gateway API: 127.0.0.1:8642 (internal only, OpenAI-compatible)
- Telegram: connected (bot token in hermes_data/.env)
- Data: /opt/core/hermes_data
- Image: nousresearch/hermes-agent:latest
- Runtime UID/GID inside container: 10000:10000 (`hermes` user)
- Avoid running `docker exec hermes hermes` as root; prefer `docker exec -u 10000:10000 hermes ...` for read-only container operations
- Main vault mount: `/opt/memento` on host → `/memento` inside container
- Named profiles live under `/opt/core/hermes_data/profiles/`
- Secondary API-server ports are assigned per profile to avoid conflicts with Argo on 8642:
  - `clio`: 8643
  - `hermione`: 8644
  - `moran`: 8645
  - `samira`: 8646
  - `nadia`: 8647
  - `robot`: 8648
- Argo has n8n MCP configured at `mcp_servers.n8n` and can manage/query n8n workflows through `n8n-mcp`

#### Hermes profile: robot
- Purpose: sterile OpenAI-compatible model backend reserved for Dify/RAGFlow integration; Dify uses it only after provider setup in the Dify UI.
- Profile path: `/opt/core/hermes_data/profiles/robot`
- Personality file: `/opt/core/hermes_data/profiles/robot/SOUL.md`
- API server: `http://hermes:8648/v1` from containers on `core_core_net`; `http://127.0.0.1:8648/v1` from inside the Hermes container/host context where reachable
- API model name: `robot`
- API key: `/opt/core/hermes_data/profiles/robot/.env` variable `API_SERVER_KEY` (do not paste into docs/chat)
- Memory disabled: `memory.memory_enabled: false`, `memory.user_profile_enabled: false`
- Toolsets and bundled skills disabled for the API profile; `platform_toolsets.api_server: []` keeps the profile model-only for external app calls
- Gateway autostart includes `robot`; verify with `/opt/core/hermes_data/profiles/robot/gateway_state.json` and `/v1/models` before wiring new apps

#### Hermes profile: moran
- Profile path: `/opt/core/hermes_data/profiles/moran`
- Personality file: `/opt/core/hermes_data/profiles/moran/SOUL.md`
- Memory provider: Honcho (`memory.provider: honcho`)
- Honcho profile-local config: `/opt/core/hermes_data/profiles/moran/honcho.json`
- Honcho identity: workspace `hermes-moran`, user peer `kris`, AI peer `moran`
- Honcho API URL from Hermes: `http://honcho-api:8000`

### Honcho Memory Stack (Moran)
- Purpose: self-hosted Honcho memory backend for Hermes profile `moran`
- Compose project: `honcho`
- Compose file: `/opt/core/honcho/docker-compose.yml`
- Services: `honcho-api`, `honcho-deriver`, `honcho-postgres`, `honcho-redis`
- LLM backend: OpenAI-compatible opencode-zen endpoint (`claude-sonnet-4-6`) via `/opt/core/honcho/.env`
- Message embeddings: disabled (`EMBED_MESSAGES=false`) until a dedicated embeddings provider is configured
- API exposure: no published host port; accessible only from `hermes` over Docker network `hermes_honcho`
- Database: dedicated Honcho Postgres with pgvector, volume `honcho_pgdata`
- Cache: dedicated Honcho Redis, volume `honcho_redis-data`

### PostgreSQL
- Two databases: `n8n` (system) and `zenaflow` (application)
- Two roles: `n8n` (superuser) and `zenaflow_user` (restricted)
- Data: /opt/core/postgres_data

### Redis
- AOF persistence enabled
- Data: /opt/core/redis_data

### Qdrant
- Vector DB for AI/embeddings
- Storage: /opt/core/qdrant_storage

### pgAdmin
- Access: 127.0.0.1:8889 (SSH tunnel required from local)
- Data: /opt/core/pgadmin_data

### RedisInsight
- Access: 127.0.0.1:5540 (SSH tunnel required from local)

### Tailscale
- Machine name: `core-hub-01`
- Tailscale IP: `100.75.180.124`
- Tailnet: zenosumo@
- Auto-starts via systemd (`tailscaled.service`)

### Samba
- Share: `share` → `/opt` (covers both `/opt/zenaflow` and `/opt/core`)
- Access: Tailscale only (`hosts allow = 100.64.0.0/10`)
- User: `zenaflow` (system user, no shell login)
- File operations run as: `root` (force user)
- Config: `/etc/samba/smb.conf`
- Service: `smbd` (nmbd disabled — not needed for macOS)

---

## 7. EXPOSURE SURFACE
Public:
- SSH (key-only)
- HTTP (redirects to HTTPS)
- HTTPS

Internal only (never exposed):
- PostgreSQL (5432)
- Redis (6379)
- Qdrant (6333/6334)
- Hermes/Argo API (8642)
- Secondary Hermes profile APIs (8643-8648)
- Hermes dashboard direct (9119) — proxied via Caddy at dashboard.zenaflow.com
- Open WebUI (3001) — proxied via Caddy + Cloudflare Zero Trust at argo.zenaflow.com
- n8n-mcp (3000) — Docker-network only on `core_core_net`, no host port
- Honcho API (8000) — Docker-network only, not bound to host localhost
- Honcho Postgres (5432) — `honcho_internal` Docker network only
- Honcho Redis (6379) — `honcho_internal` Docker network only
- pgAdmin (8889)
- RedisInsight (5540)

Tailscale-only (not reachable from public internet):
- Samba (445/139) — file share at `smb://core-hub-01/share`

---

## 8. OPERATIONAL COMMANDS

### Docker Stack
```bash
# IMPORTANT: core stack: always run from /opt/core
cd /opt/core && docker compose up -d
cd /opt/core && docker compose ps
cd /opt/core && docker compose logs -f [service]
cd /opt/core && docker compose restart [service]
cd /opt/core && docker compose down

# Honcho memory stack for moran: separate Compose project
cd /opt/core/honcho && docker compose up -d
cd /opt/core/honcho && docker compose ps
cd /opt/core/honcho && docker compose logs -f api deriver
cd /opt/core/honcho && docker compose restart api deriver
```

### Hermes / Argo / n8n MCP
```bash
# Check Argo API model name; should include id/root `Argo`
# Use the live API key from /opt/core/.env; do not paste secrets into logs.
cd /opt/core && curl -sS http://127.0.0.1:8642/v1/models  # add Authorization: Bearer <API_SERVER_KEY> from .env

# Check n8n MCP container health from Hermes/core network
docker exec hermes curl -sS --max-time 5 http://n8n-mcp:3000/health

# Check Hermes native MCP registration; n8n should show 24 tools
docker exec -u 10000:10000 hermes /opt/hermes/.venv/bin/hermes mcp list
docker exec -u 10000:10000 hermes /opt/hermes/.venv/bin/hermes mcp test n8n
```

### Hermes / Moran / Honcho
```bash
# Check Moran Honcho config and memory status
sudo docker exec -u 10000:10000 -e HERMES_HOME=/opt/data/profiles/moran hermes /opt/hermes/.venv/bin/hermes memory status
sudo docker exec -u 10000:10000 -e HERMES_HOME=/opt/data/profiles/moran hermes /opt/hermes/.venv/bin/hermes honcho status

# Verify Honcho is not host-exposed; this should fail from the VPS host
curl --max-time 2 http://127.0.0.1:8000/health

# Verify Hermes can reach Honcho over the private Docker network; this should return {"status":"ok"}
sudo docker exec -u 10000:10000 hermes curl -sS --max-time 5 http://honcho-api:8000/health

# Restart the Moran gateway inside the Hermes container after config/SOUL changes
sudo docker exec hermes pkill -f "hermes -p moran gateway run" || true
sudo docker exec -u hermes -d hermes /opt/hermes/.venv/bin/hermes -p moran gateway run
```

### Caddy
```bash
caddy validate --config /opt/zenaflow/caddy/Caddyfile
sudo caddy reload --config /opt/zenaflow/caddy/Caddyfile
tail -f /var/log/caddy/n8n_access.log
```

### Firewall
```bash
ufw status verbose
ufw allow XX
ufw delete allow XX
```

### Tailscale
```bash
# Status and peer list
tailscale status

# Check Tailscale IP
tailscale ip -4

# Restart if needed
sudo systemctl restart tailscaled
```

### Samba
```bash
# Check service
sudo systemctl status smbd

# Verify listening on Tailscale range
sudo ss -tlnp | grep -E ':(445|139)'

# Reload config after changes
sudo systemctl restart smbd

# Reset Samba password
sudo smbpasswd zenaflow
```

### Fail2Ban
```bash
fail2ban-client status
fail2ban-client status sshd
fail2ban-client set sshd unbanip <IP>
fail2ban-client unban --all
```

### Database
```bash
# PostgreSQL shell
docker exec -it postgres psql -U n8n -d n8n

# Redis CLI
docker exec -it redis redis-cli

# Backup n8n DB
docker exec postgres pg_dump -U n8n n8n > /tmp/n8n_backup.sql

# Backup zenaflow DB
docker exec postgres pg_dump -U n8n zenaflow > /tmp/zenaflow_backup.sql
```

---

## 9. BACKUP & RECOVERY

### If SSH breaks
Use Hetzner console:
```
systemctl restart sshd
```

### If firewall breaks
```
ufw disable
```

### If Fail2Ban bans you
```
fail2ban-client unban --all
systemctl stop fail2ban
```

---

## 10. SUMMARY
- Secure, minimal, production-ready stack
- Main Docker services isolated on core_core_net (172.18.0.0/16)
- Honcho memory stack isolated in its own Compose project and private Docker networks
- Key-only SSH, UFW active, Fail2Ban active
- Caddy handles HTTPS with Cloudflare trusted proxy
- Internal-only DBs and services
- Hermes Agent default profile runs as Argo with Telegram + dashboard (dashboard.zenaflow.com)
- Open WebUI chat interface at argo.zenaflow.com, backed by Argo's Hermes OpenAI-compatible API
- Secondary Hermes profiles use dedicated API ports 8643-8648 to avoid conflicts with Argo on 8642; `robot` uses 8648 as a sterile future Dify/RAGFlow provider
- Argo has n8n MCP integration through internal `n8n-mcp` container and can query/manage n8n workflows
- Moran Hermes profile uses self-hosted Honcho memory: workspace `hermes-moran`, peer `kris`, AI peer `moran`
- argo.zenaflow.com protected by Cloudflare Zero Trust Access
- Tailscale mesh VPN for secure private access
- Samba file share (`smb://core-hub-01/share`) — Tailscale-only, macOS Finder compatible
