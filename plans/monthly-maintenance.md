# ZENAFLOW VPS - MONTHLY MAINTENANCE PLAN

> **Last Updated:** 2026-01-14
> **VPS:** core.zenaflow.com
> **Environment:** Production
> **Schedule:** First week of every month

---

## OVERVIEW

This document outlines the complete monthly maintenance routine for the Zenaflow VPS infrastructure. Following this checklist ensures security, stability, and optimal performance of all services.

**Estimated Time:** 1.5-2 hours
**Best Time:** During low-traffic hours (early morning)
**Prerequisites:** SSH access, backup verification

---

## PRE-MAINTENANCE CHECKLIST

- [ ] Schedule maintenance window (notify users if needed)
- [ ] Verify backup storage availability
- [ ] Ensure stable internet connection
- [ ] Have Hetzner console access ready (emergency fallback)
- [ ] Review last month's maintenance notes

---

## 1. DOCKER STACK MAINTENANCE

### 1.1 Database Backups (CRITICAL - Do First!)

```bash
# Create backup directory with timestamp
BACKUP_DATE=$(date +%Y%m%d)
BACKUP_DIR="/opt/zenaflow/backups/${BACKUP_DATE}"
mkdir -p ${BACKUP_DIR}

# Backup n8n database
docker exec postgres pg_dump -U n8n n8n | gzip > ${BACKUP_DIR}/n8n_${BACKUP_DATE}.sql.gz

# Backup zenaflow database
docker exec postgres pg_dump -U n8n zenaflow | gzip > ${BACKUP_DIR}/zenaflow_${BACKUP_DATE}.sql.gz

# Verify backups created
ls -lh ${BACKUP_DIR}/
```

**Verification:**
- [ ] Both backup files exist
- [ ] File sizes are reasonable (not 0 bytes)
- [ ] Test restore on a single table (optional but recommended)

### 1.2 Docker Image Updates

```bash
cd /opt/zenaflow/docker

# Pull latest images for all services
docker compose pull

# Check what will be updated
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep -E "(n8nio|redis|qdrant|postgres|pgadmin)"
```

**Review checklist:**
- [ ] Check n8n release notes: https://github.com/n8n-io/n8n/releases
- [ ] Check PostgreSQL release notes if major update
- [ ] Review any breaking changes

### 1.3 Apply Updates

```bash
# Recreate containers with new images (using core project name)
docker compose -p core up -d

# Wait for services to stabilize (30 seconds)
sleep 30

# Verify all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
```

**Verification:**
- [ ] All containers show "Up" status
- [ ] postgres shows "(healthy)" status
- [ ] n8n is accessible at https://workflow.zenaflow.com

### 1.4 Check Container Logs

```bash
# Check for errors in key services
docker logs n8n --tail 50 | grep -i error
docker logs postgres --tail 50 | grep -i error
docker logs redis --tail 50 | grep -i error
docker logs qdrant --tail 50 | grep -i error
```

**Action:**
- [ ] Investigate any ERROR level messages
- [ ] Document any warnings for follow-up

### 1.5 Container Resource Usage

```bash
# Check container resource usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
```

**Monitor:**
- [ ] CPU usage < 80% for all containers
- [ ] Memory usage not hitting limits
- [ ] No excessive disk I/O

### 1.6 Docker Cleanup

```bash
# Remove old unused images (frees disk space)
docker image prune -a --filter "until=720h" --force

# Remove stopped containers
docker container prune --force

# Remove unused volumes (CAREFUL - verify first!)
docker volume ls
# Only if you know what you're doing:
# docker volume prune --force

# Remove unused networks
docker network prune --force
```

**Expected result:**
- [ ] Disk space reclaimed
- [ ] No active services affected

---

## 2. SYSTEM UPDATES & SECURITY

### 2.1 System Package Updates

```bash
# Update package lists
sudo apt update

# Check what will be upgraded
apt list --upgradable

# Perform upgrade (security + regular updates)
sudo apt upgrade -y

# Clean up old packages
sudo apt autoremove -y
sudo apt autoclean
```

**Review:**
- [ ] Check if kernel update requires reboot
- [ ] Review any held-back packages
- [ ] Note any configuration file changes

### 2.2 Security Updates Check

```bash
# Check for security updates specifically
sudo apt list --upgradable | grep -i security

# Check for unattended upgrades status
sudo systemctl status unattended-upgrades
```

**Action:**
- [ ] Apply all security updates immediately
- [ ] Document any critical CVEs addressed

### 2.3 Reboot if Required

```bash
# Check if reboot is required
ls -la /var/run/reboot-required 2>/dev/null && cat /var/run/reboot-required.pkgs

# If reboot needed, schedule and execute:
# sudo reboot
```

**If rebooting:**
- [ ] Notify users (if applicable)
- [ ] Verify all Docker services auto-restart after reboot
- [ ] Test SSH access after reboot
- [ ] Verify n8n, Caddy, all services are up

---

## 3. FIREWALL & SECURITY CHECKS

### 3.1 UFW Firewall Status

```bash
# Check firewall status and rules
sudo ufw status verbose

# Verify expected rules
sudo ufw status numbered
```

**Expected rules:**
- [ ] 22/tcp (SSH) - ALLOW
- [ ] 80/tcp (HTTP) - ALLOW
- [ ] 443/tcp (HTTPS) - ALLOW
- [ ] Default incoming - DENY
- [ ] Default outgoing - ALLOW

### 3.2 Fail2Ban Status

```bash
# Check Fail2Ban status
sudo fail2ban-client status

# Check individual jail statistics
sudo fail2ban-client status sshd
sudo fail2ban-client status caddy-login
sudo fail2ban-client status caddy-webhook
sudo fail2ban-client status recidive

# Check recent bans
sudo zgrep 'Ban' /var/log/fail2ban.log* | tail -20
```

**Review:**
- [ ] Check ban counts (high numbers may indicate attack)
- [ ] Review banned IPs for patterns
- [ ] Verify jails are active and working

### 3.3 SSH Security Audit

```bash
# Check SSH configuration
sudo sshd -T | grep -E "(passwordauthentication|pubkeyauthentication|permitrootlogin)"

# Review recent SSH logins
sudo lastlog | head -20

# Check failed login attempts
sudo grep "Failed password" /var/log/auth.log | tail -20
```

**Verify:**
- [ ] PasswordAuthentication = no
- [ ] PubkeyAuthentication = yes
- [ ] PermitRootLogin = without-password or prohibit-password
- [ ] No suspicious failed login patterns

### 3.4 Open Ports Scan

```bash
# Check listening ports
sudo ss -tulpn | grep LISTEN

# Verify only expected ports are open
sudo netstat -tlpn | grep LISTEN
```

**Expected ports:**
- [ ] :22 (SSH)
- [ ] :80 (Caddy HTTP)
- [ ] :443 (Caddy HTTPS)
- [ ] 127.0.0.1:5678 (n8n - local only)
- [ ] 127.0.0.1:5432 (PostgreSQL - local only)
- [ ] 127.0.0.1:5540 (RedisInsight - local only)
- [ ] 127.0.0.1:8889 (pgAdmin - local only)

---

## 4. DATABASE MAINTENANCE

### 4.1 PostgreSQL Health Check

```bash
# Check database sizes
docker exec -it postgres psql -U n8n -c "\l+"

# Check table sizes in n8n database
docker exec -it postgres psql -U n8n -d n8n -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
"

# Check table sizes in zenaflow database
docker exec -it postgres psql -U n8n -d zenaflow -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
"
```

**Review:**
- [ ] Database growth is expected
- [ ] No unexpectedly large tables
- [ ] Total size within disk space limits

### 4.2 PostgreSQL Vacuum & Analyze

```bash
# Run VACUUM ANALYZE on both databases (reclaim space, update statistics)
docker exec -it postgres psql -U n8n -d n8n -c "VACUUM ANALYZE;"
docker exec -it postgres psql -U n8n -d zenaflow -c "VACUUM ANALYZE;"

# Check for bloat in tables (optional deep check)
docker exec -it postgres psql -U n8n -d n8n -c "
SELECT
    schemaname,
    tablename,
    n_dead_tup,
    n_live_tup,
    round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) AS dead_percentage
FROM pg_stat_user_tables
WHERE n_dead_tup > 100
ORDER BY n_dead_tup DESC
LIMIT 10;
"
```

**Action:**
- [ ] VACUUM completed without errors
- [ ] Dead tuple percentage < 10% for active tables

### 4.3 Redis Health Check

```bash
# Check Redis info
docker exec -it redis redis-cli INFO | grep -E "(used_memory_human|connected_clients|total_commands_processed|uptime_in_days)"

# Check Redis persistence
docker exec -it redis redis-cli INFO persistence | grep -E "(aof_enabled|aof_last_write_status|rdb_last_save_time)"

# Check keyspace
docker exec -it redis redis-cli INFO keyspace
```

**Monitor:**
- [ ] Memory usage is reasonable
- [ ] AOF persistence is enabled and healthy
- [ ] No errors in persistence status

### 4.4 Qdrant Health Check

```bash
# Check Qdrant status
docker logs qdrant --tail 20

# Check collections (if any)
curl -s http://localhost:6333/collections | python3 -m json.tool
```

**Verify:**
- [ ] Service is running without errors
- [ ] Collections are healthy (if using)

---

## 5. CADDY & SSL CERTIFICATES

### 5.1 Caddy Configuration Validation

```bash
# Validate Caddyfile syntax
sudo caddy validate --config /etc/caddy/Caddyfile
```

**Result:**
- [ ] Configuration is valid

### 5.2 SSL Certificate Status

```bash
# Check certificate expiry for workflow domain
echo | openssl s_client -servername workflow.zenaflow.com -connect workflow.zenaflow.com:443 2>/dev/null | openssl x509 -noout -dates

# Check certificate expiry for webhook domain
echo | openssl s_client -servername webhook.zenaflow.com -connect webhook.zenaflow.com:443 2>/dev/null | openssl x509 -noout -dates
```

**Verify:**
- [ ] Certificates expire > 30 days from now
- [ ] Auto-renewal is working (Caddy handles this automatically)

### 5.3 Caddy Logs Review

```bash
# Check Caddy access logs for errors
sudo tail -100 /var/log/caddy/workflow_access.log | grep -v " 200 " | tail -20
sudo tail -100 /var/log/caddy/webhook_access.log | grep -v " 200 " | tail -20

# Check for rate limiting or suspicious activity
sudo tail -200 /var/log/caddy/workflow_access.log | awk '{print $1}' | sort | uniq -c | sort -rn | head -10
```

**Review:**
- [ ] No excessive 4xx/5xx errors
- [ ] No single IP dominating requests (potential attack)
- [ ] Response times are normal

### 5.4 Domain DNS Check

```bash
# Verify DNS resolution
dig workflow.zenaflow.com +short
dig webhook.zenaflow.com +short

# Check if Cloudflare proxy is active
dig workflow.zenaflow.com
```

**Verify:**
- [ ] Domains resolve to correct IP
- [ ] Cloudflare proxy is active (if applicable)

---

## 6. DISK SPACE & LOG MANAGEMENT

### 6.1 Disk Usage Check

```bash
# Check overall disk usage
df -h

# Check inode usage
df -i

# Check largest directories
sudo du -h --max-depth=1 /opt/zenaflow | sort -hr | head -10
sudo du -h --max-depth=1 /var/log | sort -hr | head -10
```

**Thresholds:**
- [ ] Root filesystem < 80% full
- [ ] Inodes < 80% used
- [ ] At least 5GB free space available

### 6.2 Docker Volume Sizes

```bash
# Check Docker data usage
docker system df

# Check individual volume sizes
sudo du -sh /opt/zenaflow/docker/postgres_data
sudo du -sh /opt/zenaflow/docker/redis_data
sudo du -sh /opt/zenaflow/docker/n8n_data
sudo du -sh /opt/zenaflow/docker/qdrant_storage
```

**Review:**
- [ ] Growth rate is expected
- [ ] No runaway data growth

### 6.3 Log Rotation & Cleanup

```bash
# Check log rotation configuration
sudo cat /etc/logrotate.d/caddy

# Manually rotate logs if needed
sudo logrotate -f /etc/logrotate.d/caddy

# Clean old system logs (older than 30 days)
sudo journalctl --vacuum-time=30d

# Check systemd journal size
sudo journalctl --disk-usage
```

**Action:**
- [ ] Logs are rotating properly
- [ ] Old logs are being cleaned up
- [ ] Journal size < 500MB

### 6.4 Old Backup Cleanup

```bash
# List old backups (keep last 3 months)
ls -lht /opt/zenaflow/backups/

# Remove backups older than 90 days
find /opt/zenaflow/backups/ -type f -mtime +90 -name "*.sql.gz" -delete

# Verify backup retention
ls -lh /opt/zenaflow/backups/
```

**Verify:**
- [ ] At least last 3 months of backups retained
- [ ] Old backups deleted to save space

---

## 7. N8N WORKFLOW HEALTH

### 7.1 N8N Service Check

```bash
# Check n8n version
docker exec n8n n8n --version

# Check n8n logs for errors
docker logs n8n --tail 100 | grep -i error | tail -20

# Check active executions
docker exec -it postgres psql -U n8n -d n8n -c "
SELECT
    status,
    COUNT(*) as count
FROM execution_entity
WHERE \"startedAt\" > NOW() - INTERVAL '7 days'
GROUP BY status;
"
```

**Review:**
- [ ] n8n version is current
- [ ] No critical errors in logs
- [ ] Execution success rate is healthy

### 7.2 Workflow Execution Performance

```bash
# Check execution times
docker exec -it postgres psql -U n8n -d n8n -c "
SELECT
    \"workflowId\",
    status,
    AVG(EXTRACT(EPOCH FROM (\"stoppedAt\" - \"startedAt\"))) as avg_duration_seconds,
    COUNT(*) as execution_count
FROM execution_entity
WHERE \"startedAt\" > NOW() - INTERVAL '7 days'
GROUP BY \"workflowId\", status
ORDER BY avg_duration_seconds DESC
LIMIT 10;
"
```

**Review:**
- [ ] No workflows taking excessively long
- [ ] Identify slow workflows for optimization

### 7.3 N8N Database Size

```bash
# Check n8n execution table size
docker exec -it postgres psql -U n8n -d n8n -c "
SELECT
    pg_size_pretty(pg_total_relation_size('execution_entity')) as execution_size,
    COUNT(*) as total_executions
FROM execution_entity;
"
```

**Action if too large:**
- [ ] Consider pruning old executions (if > 1GB)
- [ ] Review n8n execution retention settings

---

## 8. SYSTEM PERFORMANCE MONITORING

### 8.1 CPU & Memory Usage

```bash
# Check system load
uptime

# Check memory usage
free -h

# Check swap usage
swapon --show

# Top processes
top -b -n 1 | head -20
```

**Thresholds:**
- [ ] Load average < number of CPU cores
- [ ] Memory usage < 90%
- [ ] Swap usage < 50%

### 8.2 Network Statistics

```bash
# Check network traffic
ifstat -t 1 5

# Check connection states
ss -s

# Check active connections
netstat -ant | awk '{print $6}' | sort | uniq -c | sort -rn
```

**Monitor:**
- [ ] No unusual network spikes
- [ ] Connection states are normal
- [ ] No excessive TIME_WAIT connections

### 8.3 System Service Status

```bash
# Check critical services
sudo systemctl status sshd
sudo systemctl status caddy
sudo systemctl status fail2ban
sudo systemctl status ufw

# Check for failed services
sudo systemctl --failed
```

**Verify:**
- [ ] All critical services are active
- [ ] No failed systemd services

---

## 9. BACKUP VERIFICATION

### 9.1 Test Backup Integrity

```bash
# Test restore of latest backup (to a test database)
LATEST_BACKUP=$(ls -t /opt/zenaflow/backups/*/zenaflow_*.sql.gz | head -1)

# Create test database
docker exec -it postgres psql -U n8n -c "DROP DATABASE IF EXISTS zenaflow_test;"
docker exec -it postgres psql -U n8n -c "CREATE DATABASE zenaflow_test;"

# Restore to test database
gunzip -c ${LATEST_BACKUP} | docker exec -i postgres psql -U n8n -d zenaflow_test

# Verify restore
docker exec -it postgres psql -U n8n -d zenaflow_test -c "\dt"

# Cleanup test database
docker exec -it postgres psql -U n8n -c "DROP DATABASE zenaflow_test;"
```

**Verify:**
- [ ] Backup file is not corrupted
- [ ] Restore completes without errors
- [ ] Tables are present in restored database

### 9.2 Offsite Backup Check

```bash
# Verify backups are copied to offsite location
# (Implement based on your backup strategy - S3, rsync, etc.)

# Example with rsync to remote server:
# rsync -avz /opt/zenaflow/backups/ user@backup-server:/backups/zenaflow/
```

**Verify:**
- [ ] Offsite backups are up to date
- [ ] Offsite backup retention policy is followed

---

## 10. MONITORING & ALERTING

### 10.1 Check Uptime & Availability

```bash
# Check system uptime
uptime

# Check service uptime
systemctl status caddy | grep Active
systemctl status fail2ban | grep Active

# Check Docker uptime
docker ps --format "table {{.Names}}\t{{.Status}}"
```

**Document:**
- [ ] System uptime (reboot history)
- [ ] Service restart history

### 10.2 Review Recent Errors

```bash
# Check systemd errors from last month
sudo journalctl -p err -S "1 month ago" --no-pager | tail -50

# Check Docker container restarts
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | grep -i restart
```

**Action:**
- [ ] Investigate any repeated errors
- [ ] Document known issues and fixes

---

## 11. DOCUMENTATION & REPORTING

### 11.1 Update Maintenance Log

Create an entry in `/opt/zenaflow/maintenance-logs/YYYY-MM.md`:

```markdown
# Maintenance Log - YYYY-MM-DD

## Summary
- All systems healthy
- Docker images updated
- Security patches applied
- Backups verified

## Issues Found
- [List any issues and resolutions]

## Actions Taken
- [List major changes or updates]

## Next Month's Focus
- [Note any follow-up items]
```

### 11.2 Review and Update Documentation

```bash
# Check if documentation needs updates
ls -lh /opt/zenaflow/doc/
ls -lh /opt/zenaflow/CLAUDE.md
```

**Update if needed:**
- [ ] Infrastructure changes
- [ ] New procedures
- [ ] Configuration changes
- [ ] Version updates

---

## 12. POST-MAINTENANCE VERIFICATION

### 12.1 End-to-End Service Check

```bash
# Test n8n web UI
curl -I https://workflow.zenaflow.com | head -1

# Test webhook endpoint
curl -I https://webhook.zenaflow.com | head -1

# Test SSH access
ssh -T root@core.zenaflow.com "echo 'SSH OK'"

# Test PostgreSQL connection
docker exec -it postgres psql -U n8n -d n8n -c "SELECT version();"
```

**Verify:**
- [ ] All web services return 200 OK
- [ ] SSH access works
- [ ] Database responds

### 12.2 Final Checklist

- [ ] All Docker containers running
- [ ] n8n accessible and functional
- [ ] Backups created and verified
- [ ] Security updates applied
- [ ] Logs reviewed for errors
- [ ] Disk space adequate
- [ ] Documentation updated
- [ ] Maintenance log completed

---

## EMERGENCY CONTACTS & PROCEDURES

### If Something Goes Wrong

**SSH Access Issues:**
```bash
# Use Hetzner console to access server
# Reset SSH: sudo systemctl restart sshd
```

**Firewall Lockout:**
```bash
# Use Hetzner console
# Disable UFW: sudo ufw disable
# Fix rules, then re-enable: sudo ufw enable
```

**Database Corruption:**
```bash
# Restore from latest backup
cd /opt/zenaflow/backups
# Find latest backup and restore per section 9.1
```

**Docker Issues:**
```bash
# Restart Docker daemon
sudo systemctl restart docker

# Restart all services
cd /opt/zenaflow/docker
docker compose -p core down
docker compose -p core up -d
```

---

## APPENDIX: QUICK REFERENCE

### Critical Commands

```bash
# Backup databases
docker exec postgres pg_dump -U n8n n8n > /tmp/n8n_backup.sql
docker exec postgres pg_dump -U n8n zenaflow > /tmp/zenaflow_backup.sql

# Update Docker images
cd /opt/zenaflow/docker && docker compose pull && docker compose -p core up -d

# System updates
sudo apt update && sudo apt upgrade -y

# Check all services
docker ps && sudo systemctl status caddy fail2ban ufw

# Check security
sudo ufw status && sudo fail2ban-client status

# Check disk space
df -h && docker system df
```

### Important Paths

- Docker Compose: `/opt/zenaflow/docker/docker-compose.yml`
- Caddy Config: `/etc/caddy/Caddyfile`
- Caddy Logs: `/var/log/caddy/`
- Backups: `/opt/zenaflow/backups/`
- Documentation: `/opt/zenaflow/doc/`
- Maintenance Plans: `/opt/zenaflow/plans/`

### Service URLs

- n8n Editor: https://workflow.zenaflow.com
- n8n Webhooks: https://webhook.zenaflow.com
- pgAdmin: http://localhost:8889 (via SSH tunnel)
- RedisInsight: http://localhost:5540 (via SSH tunnel)

---

## MAINTENANCE SCHEDULE

| Task | Frequency | Estimated Time |
|------|-----------|----------------|
| Full Monthly Maintenance | Monthly (1st week) | 1.5-2 hours |
| Database Backups | Daily (automated) | N/A |
| Security Updates | Weekly check | 15 minutes |
| Log Review | Weekly | 10 minutes |
| Disk Space Check | Weekly | 5 minutes |
| Service Health Check | Daily (automated monitoring recommended) | N/A |

---

**End of Monthly Maintenance Plan**

*Keep this document updated as infrastructure evolves.*
