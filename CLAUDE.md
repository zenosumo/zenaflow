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
   - `n8n` database: Workflow definitions, credentials, execution history
   - `zenaflow` database: Multi-app platform with users, applications, and chat messages
   - Two roles: `n8n` (superuser) and `zenaflow_user` (restricted app access)
   - Health checks configured, data in `./postgres_data`
   - See `doc/postgres_pgadmin_setup.md` for complete database configuration
   - See `doc/schema.sql` for application database schema

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

## Application Database Architecture

The `zenaflow` PostgreSQL database powers a multi-app Telegram bot platform with centralized user management:

**Core Tables**:
- `users` - User accounts with telegram_id, phone_number, display_name, and admin status
- `applications` - Available apps (e.g., deanna, b4, anaketa) with bot usernames
- `user_applications` - Junction table linking users to their accessible apps
- `chat_messages` - Request/response pairs with status tracking (pending/completed/failed)

**Key Design Patterns**:
- Messages belong to user-application pairings (via `user_app_id`), not users or apps independently
- Telegram message IDs used for deduplication (prevents duplicate webhook processing)
- Status lifecycle: `pending` → `completed`/`failed` with automatic timestamp tracking
- Role-based access: `zenaflow_user` cannot access `n8n` database

**Common Workflows**:
- Admins use Vader bot to pre-register users and assign app access
- Users interact with app-specific bots (Deanna, B4, etc.)
- Each message creates a row (status='pending'), later updated with response

Full schema with constraints, indexes, and example queries in `doc/schema.sql`.

## Common Commands

### Docker Stack Management
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

**Local (Docker)**:
```bash
# PostgreSQL - n8n database
docker exec -it postgres psql -U n8n -d n8n

# PostgreSQL - zenaflow database
docker exec -it postgres psql -U zenaflow_user -d zenaflow

# Redis CLI
docker exec -it redis redis-cli
```

**Remote (via SSH Tunnel)**:
```bash
# Tunnel for pgAdmin web UI
ssh -L 8889:localhost:8889 root@core.zenaflow.com
# Then open: http://localhost:8889

# Tunnel for RedisInsight web UI
ssh -L 5555:localhost:5540 root@core.zenaflow.com
# Then open: http://localhost:5555

# Tunnel for direct PostgreSQL access (psql, IDEs, Prisma Studio)
ssh -L 5432:localhost:5432 root@core.zenaflow.com
# Connection string: postgresql://zenaflow_user:${ZENAFLOW_DB_PASSWORD}@localhost:5432/zenaflow
```

**Database Credentials**:
- n8n superuser: `n8n` / `${POSTGRES_PASSWORD}`
- Application user: `zenaflow_user` / `${ZENAFLOW_DB_PASSWORD}`
- pgAdmin login: `kris@zenaflow.com` / `${POSTGRES_PASSWORD}`

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

## Environment Configuration

Required environment variables (typically in `.env` file, gitignored):
- `POSTGRES_PASSWORD` - PostgreSQL password for n8n user
- `ZENAFLOW_DB_PASSWORD` - Password for zenaflow_user database role (default: `${ZENAFLOW_DB_PASSWORD}`)
- `CLOUDFLARE_API_TOKEN` - Cloudflare API token for MCP server (if using Cloudflare MCP)
- `CLOUDFLARE_ACCOUNT_ID` - Cloudflare account ID for MCP server (if using Cloudflare MCP)

The n8n service environment is extensively configured in docker-compose.yml including:
- Multi-domain setup (workflow/webhook)
- Security hardening (block env access, enforce file permissions)
- PostgreSQL connection details
- Timezone and protocol settings

## Data Persistence

All data is persisted in subdirectories under `docker/`:
- `n8n_data/` - n8n workflows, credentials, settings
- `postgres_data/` - PostgreSQL database files
- `redis_data/` - Redis AOF and RDB files
- `qdrant_storage/` - Vector database collections
- `pgadmin_data/` - pgAdmin configuration
- `pgadmin_config/servers.json` - Pre-configured database connections

These directories are gitignored and should be backed up separately.

## Security Considerations

**Application-level**:
- n8n runners enabled for isolated workflow execution
- Environment variable access blocked in nodes (`N8N_BLOCK_ENV_ACCESS_IN_NODE`)
- Git bare repos disabled for security
- File permissions enforcement enabled
- All services bound to localhost except via Caddy
- Cloudflare proxy IP ranges trusted for real IP detection

**VPS-level** (see `doc/vps_architecture.md`):
- SSH key-only authentication (PasswordAuthentication disabled)
- UFW firewall: deny all incoming except 22, 80, 443
- Fail2Ban active jails: sshd, caddy-login, caddy-webhook, recidive
- Database access only via SSH tunnels or internal Docker network
- Dedicated `zenaflow_user` role cannot access n8n system database

**Recovery**:
- Hetzner console access available if SSH/firewall breaks
- Database backups via pg_dump to `/tmp`

## Documentation References

- **`doc/vps_architecture.md`** - Complete VPS infrastructure guide including network topology, Docker container IPs, firewall rules, Fail2Ban configuration, and operational commands
- **`doc/postgres_pgadmin_setup.md`** - Detailed PostgreSQL and pgAdmin configuration with user roles, privileges, SSH tunnel setup, and database access patterns
- **`doc/schema.sql`** - Complete application database schema with table definitions, constraints, indexes, and example queries for common operations
