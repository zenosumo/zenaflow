# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Operational Rules

**Sudo Command Authorization:**
- Claude Code must **never** execute `sudo` commands without explicit user permission
- Before running any `sudo` command:
  1. Explain what the command will do and why sudo is required
  2. Show the exact command that will be executed
  3. Ask explicitly: "May I proceed with sudo?"
  4. Wait for user confirmation before executing
- This applies to all system-level operations requiring elevated privileges including:
  - Direct `sudo` commands
  - System file modifications (`/etc/`, `/var/`, `/usr/`, etc.)
  - Firewall rules (UFW, iptables)
  - Service management (systemctl, service commands)
  - Package management (apt, dpkg, npm -g with sudo)

## Environment Detection

**Automatic Detection via SessionStart Hook:**
A Claude Code hook (`.claude/hooks/session_start.py`) runs automatically at session start to detect the environment based on working directory path. The following environment variables are available in all bash commands:

- `$ZENAFLOW_ENV` - Environment type: `VPS_PRODUCTION` or `LOCAL_DEVELOPMENT`
- `$ZENAFLOW_CWD` - Current working directory at session start
- `$ZENAFLOW_PLATFORM` - Platform: `linux`, `darwin`, etc.

**Environment Types:**

**VPS Production** (`ZENAFLOW_ENV=VPS_PRODUCTION`):
- Detected when working directory is `/opt/core/*` or `/opt/zenaflow/*`
- Full system access: UFW, Fail2Ban, systemctl available
- Production domains: workflow.zenaflow.com, webhook.zenaflow.com
- Direct access to all Docker services and docker compose commands
- Requires sudo permission for system operations (see Operational Rules)

**Local Development** (`ZENAFLOW_ENV=LOCAL_DEVELOPMENT`):
- Detected when working directory is NOT `/opt/core/*` or `/opt/zenaflow/*`
- Works on any platform (macOS, Linux, Windows, etc.)
- **NO Docker access** - Docker and docker compose commands are VPS-only
- No system-level tools (UFW, Fail2Ban, systemctl)
- No production domains
- Database access requires SSH tunnels to VPS:
  ```bash
  ssh -L 5432:localhost:5432 root@core.zenaflow.com  # PostgreSQL
  ssh -L 8889:localhost:8889 root@core.zenaflow.com  # pgAdmin
  ssh -L 5555:localhost:5540 root@core.zenaflow.com  # RedisInsight
  ```

**Claude Code Behavior:**
- Check `$ZENAFLOW_ENV` before suggesting system commands
- **NEVER run docker or docker compose commands when `ZENAFLOW_ENV=LOCAL_DEVELOPMENT`**
- Never suggest `ufw`, `fail2ban-client`, or `systemctl` when `ZENAFLOW_ENV=LOCAL_DEVELOPMENT`
- Recommend SSH tunnels for database access on local development
- Remind about sudo permission requirement when `ZENAFLOW_ENV=VPS_PRODUCTION`

## Project Overview

Zenaflow is a VPS-based n8n workflow automation infrastructure that provides a production-ready deployment with:
- n8n workflow engine with PostgreSQL persistence
- Redis for caching and job queuing
- Qdrant vector database for AI/ML workflows
- Caddy as reverse proxy with Cloudflare trusted proxy configuration
- Management tools (RedisInsight, pgAdmin)
- Multi-app Telegram bot platform with centralized user management

**VPS Deployment**: Production instance runs at `core.zenaflow.com` under `/opt/core` with hardened SSH, UFW firewall, and Fail2Ban protection. See `doc/vps_architecture.md` for full infrastructure details.

## Architecture

### Service Stack (docker-compose.yml)

All services run in a Docker Compose stack connected via `core_net` network:

1. **n8n** (workflow.zenaflow.com, webhook.zenaflow.com)
   - Main workflow engine, bound to 127.0.0.1:5678
   - Configured for production with runners enabled and security hardening
   - Uses PostgreSQL backend with connection pooling
   - Data persisted to `./n8n_data`

2. **postgres** (PostgreSQL 16)
   - Hosts two databases: `n8n` (system) and `zenaflow` (application)
   - Two roles: `n8n` (superuser) and `zenaflow_user` (restricted app access)
   - Data in `./postgres_data`

3. **redis** (Redis 7)
   - AOF persistence enabled for durability
   - Used by n8n for caching and job queuing
   - Data in `./redis_data`

4. **qdrant**
   - Vector database for AI/embeddings workflows
   - Storage in `./qdrant_storage`

5. **redisinsight** (127.0.0.1:5540)
   - Web UI for Redis monitoring

6. **pgadmin** (127.0.0.1:8889)
   - PostgreSQL management interface
   - Pre-configured with servers.json

### Reverse Proxy (Caddy)

Caddy handles SSL termination and proxying for two domains:
- `workflow.zenaflow.com` → n8n editor UI
- `webhook.zenaflow.com` → n8n webhook endpoints

Both route to 127.0.0.1:5678 with:
- JSON logging with ISO8601 timestamps
- Log rotation (10MB, 7 files, 336h retention)
- Cloudflare trusted proxy IP ranges configured

### Session Management (scripts/session.sh)

Custom Claude Code session wrapper that:
- Maintains persistent sessions with 12-hour TTL
- Supports `/reset` to clear session
- Supports `/task <prompt>` to start fresh task-specific session
- Auto-recovery from invalid server sessions
- Session state stored in `/run/user/$(id -u)/zenaflow/claude.session`
- Working directory: `/opt/zenaflow`

Environment loading (scripts/env.sh) sets up fnm (Fast Node Manager) path.

## Common Commands

### Docker Stack Management (VPS Production Only)

**IMPORTANT: Docker commands are only available in VPS Production environment (`ZENAFLOW_ENV=VPS_PRODUCTION`). Do not run these in local development.**

```bash
# Start all services
cd docker && docker compose up -d

# View logs
docker compose logs -f [service_name]

# Stop all services
docker compose down

# Restart specific service
docker compose restart [service_name]

# View service status
docker compose ps
```

### Database Access

**VPS Production (Docker)**:
```bash
# PostgreSQL - n8n database (system operations)
docker exec -it postgres psql -U n8n -d n8n

# Redis CLI
docker exec -it redis redis-cli
```

**Management Tools**:
- **pgAdmin** (VPS: 127.0.0.1:8889, Local: SSH tunnel on port 8889)
- **RedisInsight** (VPS: 127.0.0.1:5540, Local: SSH tunnel on port 5555)

**Local Development (SSH Tunnels)**:
```bash
# pgAdmin web UI
ssh -L 8889:localhost:8889 root@core.zenaflow.com

# RedisInsight web UI
ssh -L 5555:localhost:5540 root@core.zenaflow.com
```

### Caddy Management
```bash
# Validate Caddyfile
caddy validate --config caddy/Caddyfile

# Reload Caddy config
caddy reload --config caddy/Caddyfile

# View Caddy logs
tail -f /var/log/caddy/workflow_access.log
tail -f /var/log/caddy/webhook_access.log
```

### Claude Session Wrapper
```bash
# Run with persistent session (12h TTL)
scripts/session.sh "your prompt here"

# Start fresh task session
scripts/session.sh "/task implement new workflow"

# Clear session state
scripts/session.sh "/reset"
```

### VPS Operations

**Firewall (UFW)**:
```bash
# Check firewall status
ufw status verbose

# Allow/deny ports
ufw allow 22/tcp
ufw delete allow 80/tcp
```

**Fail2Ban**:
```bash
# Check jail status
fail2ban-client status
fail2ban-client status sshd

# Unban IP address
fail2ban-client set sshd unbanip <IP>
fail2ban-client unban --all
```

**Backup/Restore**:
```bash
# Backup n8n database
docker exec postgres pg_dump -U n8n n8n > /tmp/n8n_backup.sql

# Backup zenaflow database
docker exec postgres pg_dump -U n8n zenaflow > /tmp/zenaflow_backup.sql

# Restore database
cat backup.sql | docker exec -i postgres psql -U n8n -d zenaflow
```

**File Editing**:
```bash
# Preferred editor: micro
micro /etc/caddy/Caddyfile
micro /opt/core/docker-compose.yml
```

## Data Persistence

All data is persisted in subdirectories under `docker/`:
- `n8n_data/` - n8n workflows, credentials, settings
- `postgres_data/` - PostgreSQL database files
- `redis_data/` - Redis AOF and RDB files
- `qdrant_storage/` - Vector database collections
- `pgadmin_data/` - pgAdmin configuration
- `pgadmin_config/servers.json` - Pre-configured database connections

These directories are gitignored and should be backed up separately.

## Documentation References

- **`doc/vps_architecture.md`** - Complete VPS infrastructure guide including network topology, Docker container IPs, firewall rules, Fail2Ban configuration, and operational commands
- **`doc/postgres_pgadmin_setup.md`** - Detailed PostgreSQL and pgAdmin configuration with user roles, privileges, SSH tunnel setup, and database access patterns
- **`doc/schema.sql`** - Complete application database schema with table definitions, constraints, indexes, and example queries for common operations
