# Postgres & pgAdmin Configuration Guide  
Zenaflow Infrastructure • Core Hub

This document describes the complete configuration of **PostgreSQL**, **pgAdmin**, and the **Zenaflow application database** running inside the Core Hub (`docker-compose` stack under `/opt/core`).  
It is intended for developers and operators who need database access through SSH tunnels or pgAdmin.

---

## 1. Overview

The system runs the following key services:

- **PostgreSQL 16** (Docker service: `postgres`)
- **pgAdmin 4** (Docker service: `pgadmin`)
- **Zenaflow application database** (`zenaflow`)
- **Zenaflow DB user** (`zenaflow_user`)
- **n8n system database** (`n8n`)
- Access restricted to **local ports only**, exposed via SSH tunnel

---

## 2. PostgreSQL Configuration

### Service definition (from docker-compose)

```yaml
postgres:
  image: postgres:16
  container_name: postgres
  restart: unless-stopped
  environment:
    - POSTGRES_DB=n8n
    - POSTGRES_USER=n8n
  volumes:
    - ./postgres_data:/var/lib/postgresql/data
  networks:
    - core_net
```

### Key points

- **Primary admin role**: `n8n` (superuser)
- **Postgres default role (`postgres`) does not exist**
- **External access** only through:
  - SSH port-forwarding  
  - Internal Docker network (other containers)

### Container hostname inside Docker
```
postgres
```

---

## 3. Databases

The cluster contains two databases:

### `n8n` (system)
Internal workflow engine DB for n8n.  
Contains workflow definitions, credentials, OAuth tokens, installed nodes, and internal tables.

### `zenaflow` (application)
Custom application database for messaging, user relationships, and integrations.

Created with:

```sql
CREATE DATABASE zenaflow OWNER n8n;
```

---

## 4. Zenaflow Database User

A dedicated restricted user was created for application-level queries:

```sql
CREATE ROLE zenaflow_user LOGIN PASSWORD '${POSTGRES_PASSWORD}';
```

### Granted privileges

Inside `zenaflow`:

```sql
GRANT ALL PRIVILEGES ON DATABASE zenaflow TO zenaflow_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO zenaflow_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO zenaflow_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO zenaflow_user;
```

### Restrictions

The user is **explicitly blocked** from accessing n8n’s internal DB:

```sql
REVOKE CONNECT ON DATABASE n8n FROM zenaflow_user;
```

---

## 5. pgAdmin Configuration

### Service definition

```yaml
pgadmin:
  image: dpage/pgadmin4:latest
  container_name: pgadmin
  restart: unless-stopped
  ports:
    - "127.0.0.1:8889:80"
  environment:
    PGADMIN_DEFAULT_EMAIL: "kris@zenaflow.com"
    PGADMIN_DEFAULT_PASSWORD: xxx
    PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION: "False"
    PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: "False"
  volumes:
    - ./pgadmin_data:/var/lib/pgadmin
    - ./pgadmin_config/servers.json:/pgadmin4/servers.json
```

### Web UI Credentials

| Field | Value |
|-------|--------|
| Email | `kris@zenaflow.com` |
| Password | `xxx` |

### Local port binding
`127.0.0.1:8889 → pgAdmin`

pgAdmin is **NOT exposed publicly**.

---

## 6. SSH Tunnel Access

Because pgAdmin and Postgres ports are bound to `127.0.0.1`, they are only reachable via SSH port forwarding.

### Tunnel for pgAdmin UI (web)
```
ssh -L 8889:localhost:8889 root@your-server-ip
```

Then open:

```
http://localhost:8889
```

### Tunnel for direct Postgres client access (psql, IDE, Prisma Studio, etc.)
```
ssh -L 5432:localhost:5432 root@your-server-ip
```

Then connect locally with:

- Host: `localhost`
- Port: `5432`
- Database: `zenaflow`
- User: `zenaflow_user`
- Password: `${POSTGRES_PASSWORD}`

---

## 7. pgAdmin → Postgres Server Registration

The system auto-loads a server definition from:

```
/opt/core/pgadmin_config/servers.json
```

Example:

```json
{
  "Servers": {
    "1": {
      "Name": "Core Postgres",
      "Group": "Servers",
      "Host": "postgres",
      "Port": 5432,
      "Username": "n8n",
      "MaintenanceDB": "n8n",
      "SSLMode": "prefer"
    }
  }
}
```

You may manually add the Zenaflow DB in pgAdmin:

- Database: `zenaflow`
- User: `zenaflow_user`
- Password: `${POSTGRES_PASSWORD}`

---

## 8. Accessing the Zenaflow Database from Applications

### Inside Docker (other services)
Use the container hostname:

```
postgres:5432
```

Connection string example:

```
postgresql://zenaflow_user:${POSTGRES_PASSWORD}@postgres:5432/zenaflow
```

### Outside Docker (via SSH tunnel)
Use:

```
localhost:5432
```

---

## 9. Security Summary

- Postgres and pgAdmin are **not exposed to the internet**
- Access is only possible via:
  - Internal docker services (network `core_net`)
  - SSH tunnels
- A dedicated least-privilege role (`zenaflow_user`) prevents accidental modification of n8n internal tables
- pgAdmin requires authentication
- Passwords stored only in `.env`

---

## 10. Backup Commands

### Export n8n DB
```
docker exec postgres pg_dump -U n8n n8n > /tmp/n8n_backup.sql
```

### Export zenaflow DB
```
docker exec postgres pg_dump -U n8n zenaflow > /tmp/zenaflow_backup.sql
```

---

## 11. Restore Example

```bash
cat zenaflow_backup.sql | docker exec -i postgres psql -U n8n -d zenaflow
```

---

## 12. Quick Reference

### pgAdmin URL
```
http://localhost:8889
```

### Databases
- `n8n`
- `zenaflow`

### Service hostnames (inside Docker)
- `postgres`
- `pgadmin`

### Credentials

| Description | User | Password |
|------------|-------|----------|
| Postgres superuser | `n8n` | `xxx` |
| Zenaflow app user | `zenaflow_user` | `${POSTGRES_PASSWORD}` |
| pgAdmin login | `kris@zenaflow.com` | `xxx` |

---

## 13. Notes

This setup provides:

- Separation between system and application DBs  
- Secure role-based access  
- SSH-only access to sensitive services  
- Reliable Docker deployment  
- Reproducibility for onboarding and audits
