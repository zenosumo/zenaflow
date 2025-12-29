# ZENAFLOW — CORE VPS ARCHITECTURE DOCUMENTATION

## 1. ACCESS LAYER
### 1.1 SSH (Primary Entry)
```
ssh root@core.zenaflow.com
```

### 1.2 SCP (Download Docker Compose)
```
scp root@core.zenaflow.com:/opt/core/docker-compose.yml ./docker-compose.yml
```

### 1.3 SSH Tunnel (RedisInsight)
```
ssh -L 5555:localhost:5540 root@core.zenaflow.com
```
Browser:
```
http://localhost:5555
```

### 1.4 Hetzner Console
Always works even if SSH/firewall is broken.

---

## 2. FILESYSTEM STRUCTURE
```
/opt/core
   docker-compose.yml
   /data/
      postgres/
      redis/
      qdrant/
      n8n/
```

### N8N Workflows
```
/opt/core/data/n8n
```

### Caddy Config
```
/etc/caddy/Caddyfile
```

---

## 3. NETWORK & DOCKER ARCHITECTURE
Public ports:
- 22/tcp (SSH)
- 80/tcp (HTTP)
- 443/tcp (HTTPS)

### Docker Network
```
core_core_net (bridge)
Subnet: 172.18.0.0/16
```

### Container IP Map
| Service | IP | Ports |
|---------|-------------|--------|
| n8n | 172.18.0.2 | 5678 |
| qdrant | 172.18.0.3 | 6333/6334 |
| redis | 172.18.0.4 | 6379 |
| postgres | 172.18.0.5 | 5432 |
| redisinsight | 172.18.0.6 | 5540 |

---

## 4. CADDY REVERSE PROXY
```
workflow.zenaflow.com → 127.0.0.1:5678
webhook.zenaflow.com  → 127.0.0.1:5678
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

### 5.3 Fail2Ban
Active jails:
- sshd  
- caddy-login  
- caddy-webhook  
- recidive  

Logpaths:
- /var/log/auth.log  
- /var/log/caddy/workflow_access.log  
- /var/log/caddy/webhook_access.log  

---

## 6. TOOLING
- Caddy: /etc/caddy  
- Docker: /opt/core  
- N8N: container + /opt/core/data/n8n  
- PostgreSQL: internal  
- Redis: internal  
- Qdrant: internal  

---

## 7. EXPOSURE SURFACE
Only:
- SSH
- HTTP
- HTTPS

Everything else internal.

---

## 8. OPERATIONAL COMMANDS

### Firewall
```
ufw status verbose
ufw allow XX
ufw delete allow XX
```

### Fail2Ban
```
fail2ban-client status
fail2ban-client status sshd
fail2ban-client set sshd unbanip <IP>
```

### Docker
```
docker ps
docker logs n8n
docker-compose -f /opt/core/docker-compose.yml up -d
```

### Editing Files (Micro)
```
micro /etc/ssh/sshd_config
micro /etc/caddy/Caddyfile
micro /opt/core/docker-compose.yml
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
- Docker isolated services  
- Key-only SSH  
- UFW active  
- Fail2Ban active  
- Internal-only DBs  
- Caddy handling HTTPS  
