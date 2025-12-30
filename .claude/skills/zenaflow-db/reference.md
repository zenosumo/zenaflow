# Zenaflow Database Query Reference

This document provides common query patterns for the Zenaflow database. Always refer to [doc/schema.sql](../../doc/schema.sql) for the authoritative schema definition.

## User Management Queries

### Find User by Identifier

**By Telegram ID**:
```sql
SELECT * FROM users WHERE telegram_id = '@pocmior';
```

**By Phone Number**:
```sql
SELECT * FROM users WHERE phone_number = '393247766945';
```

**By Email**:
```sql
SELECT * FROM users WHERE email = 'user@example.com';
```

### Check User Existence

```sql
-- Returns true/false
SELECT EXISTS(SELECT 1 FROM users WHERE telegram_id = '@pocmior');
```

### Check User Access Status

**Check if user can access system** (not blocked, not suspended, or suspension expired):
```sql
SELECT user_id, status, active_after
FROM users
WHERE telegram_id = '@pocmior'
  AND (status = 'active' OR (status = 'suspended' AND active_after <= NOW()));
```

### Check Admin Status

```sql
SELECT is_admin FROM users WHERE telegram_id = '@admin_username';
```

### List All Users

**Active users only**:
```sql
SELECT user_id, telegram_id, phone_number, display_name, created_at
FROM users
WHERE status = 'active'
ORDER BY created_at DESC;
```

**All users with status**:
```sql
SELECT user_id, telegram_id, phone_number, display_name, status, active_after, created_at
FROM users
ORDER BY created_at DESC;
```

### Get User with Applications

```sql
SELECT
    u.user_id,
    u.telegram_id,
    u.display_name,
    u.status,
    array_agg(a.app_name ORDER BY a.app_name) as applications
FROM users u
LEFT JOIN user_applications ua ON u.user_id = ua.user_id
LEFT JOIN applications a ON ua.app_id = a.app_id
WHERE u.telegram_id = '@pocmior'
GROUP BY u.user_id;
```

### User Status Management

**Suspend user for specific duration**:
```sql
UPDATE users
SET status = 'suspended', active_after = NOW() + INTERVAL '7 days'
WHERE telegram_id = '@pocmior';
```

**Block user permanently**:
```sql
UPDATE users
SET status = 'blocked', active_after = NULL
WHERE telegram_id = '@pocmior';
```

**Reactivate user**:
```sql
UPDATE users
SET status = 'active', active_after = NULL
WHERE telegram_id = '@pocmior';
```

### List Users by Status

**Blocked users**:
```sql
SELECT user_id, telegram_id, phone_number, display_name, updated_at
FROM users
WHERE status = 'blocked'
ORDER BY updated_at DESC;
```

**Currently suspended users** (with time remaining):
```sql
SELECT
    user_id,
    telegram_id,
    phone_number,
    display_name,
    active_after,
    EXTRACT(EPOCH FROM (active_after - NOW())) / 3600 as hours_remaining
FROM users
WHERE status = 'suspended' AND active_after > NOW()
ORDER BY active_after ASC;
```

**Expired suspensions** (candidates for auto-reactivation):
```sql
SELECT user_id, telegram_id, phone_number, display_name
FROM users
WHERE status = 'suspended' AND active_after <= NOW();
```

## Application Management Queries

### List All Applications

**Active applications only**:
```sql
SELECT app_id, app_name, description, bot_username
FROM applications
WHERE is_active = true
ORDER BY app_name;
```

**All applications**:
```sql
SELECT app_id, app_name, description, bot_username, is_active, created_at
FROM applications
ORDER BY app_name;
```

### Get Users for Specific Application

```sql
SELECT
    u.telegram_id,
    u.phone_number,
    u.email,
    u.display_name,
    ua.created_at as access_granted_at
FROM users u
JOIN user_applications ua ON u.user_id = ua.user_id
JOIN applications a ON ua.app_id = a.app_id
WHERE a.app_name = 'deanna' AND u.is_admin = false
ORDER BY ua.created_at DESC;
```

### Get User's Accessible Applications

```sql
SELECT
    a.app_name,
    a.description,
    a.bot_username,
    ua.created_at as access_granted_at
FROM user_applications ua
JOIN applications a ON ua.app_id = a.app_id
JOIN users u ON ua.user_id = u.user_id
WHERE u.telegram_id = '@pocmior'
ORDER BY a.app_name;
```

## User-Application Junction Queries

### Grant User Access to Application

```sql
-- First, get the user_id and app_id
-- Then insert the relationship
INSERT INTO user_applications (user_id, app_id)
VALUES (
    (SELECT user_id FROM users WHERE telegram_id = '@pocmior'),
    (SELECT app_id FROM applications WHERE app_name = 'deanna')
);
```

### Revoke User Access to Application

```sql
DELETE FROM user_applications
WHERE user_app_id IN (
    SELECT ua.user_app_id
    FROM user_applications ua
    JOIN users u ON ua.user_id = u.user_id
    JOIN applications a ON ua.app_id = a.app_id
    WHERE u.telegram_id = '@pocmior' AND a.app_name = 'deanna'
);
```

### Get user_app_id for Message Operations

```sql
SELECT ua.user_app_id
FROM user_applications ua
JOIN users u ON ua.user_id = u.user_id
JOIN applications a ON ua.app_id = a.app_id
WHERE u.telegram_id = '@pocmior' AND a.app_name = 'deanna';
```

## Chat Message Queries

### Get User's Chat History with Application

```sql
SELECT
    cm.message_id,
    cm.request_text,
    cm.response_text,
    cm.alt_response_text,
    cm.source_payload->>'platform' as platform,
    cm.status,
    cm.requested_at,
    cm.responded_at,
    u.display_name,
    a.app_name
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
JOIN users u ON ua.user_id = u.user_id
JOIN applications a ON ua.app_id = a.app_id
WHERE u.telegram_id = '@pocmior' AND a.app_name = 'deanna'
ORDER BY cm.requested_at DESC
LIMIT 50;
```

### Check for Duplicate Message (Deduplication)

```sql
SELECT EXISTS(
    SELECT 1 FROM chat_messages
    WHERE source_payload->>'platform' = 'telegram'
      AND source_payload->>'message_id' = '12345'
);
```

### List Pending Messages

```sql
SELECT
    cm.message_id,
    cm.request_text,
    cm.requested_at,
    u.telegram_id,
    a.app_name
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
JOIN users u ON ua.user_id = u.user_id
JOIN applications a ON ua.app_id = a.app_id
WHERE cm.status = 'pending'
ORDER BY cm.requested_at ASC;
```

### Get Messages by Platform

```sql
SELECT
    cm.message_id,
    cm.request_text,
    cm.response_text,
    cm.source_payload->>'platform' as platform,
    cm.requested_at,
    u.telegram_id
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
JOIN users u ON ua.user_id = u.user_id
WHERE cm.source_payload->>'platform' = 'telegram'
ORDER BY cm.requested_at DESC
LIMIT 100;
```

### Get Messages with Alternative Responses

```sql
SELECT * FROM chat_messages
WHERE alt_response_text IS NOT NULL
ORDER BY requested_at DESC;
```

### Complex JSONB Query (Find Messages from Specific Telegram User)

```sql
SELECT * FROM chat_messages
WHERE source_payload @> '{"from": {"username": "pocmior"}}'::jsonb
ORDER BY requested_at DESC;
```

### Insert New Message (Pending Status)

```sql
INSERT INTO chat_messages (
    user_app_id,
    request_text,
    source_payload,
    status
)
VALUES (
    'user-app-uuid-here',
    'User message text here',
    '{"platform": "telegram", "message_id": "12345", "chat_id": "67890"}'::jsonb,
    'pending'
)
RETURNING message_id, requested_at;
```

### Update Message with Response (Complete Status)

```sql
UPDATE chat_messages
SET
    response_text = 'Bot response text here',
    status = 'completed',
    responded_at = NOW()
WHERE message_id = 'message-uuid-here';
```

### Mark Message as Failed

```sql
UPDATE chat_messages
SET
    status = 'failed',
    error_message = 'Error description here'
WHERE message_id = 'message-uuid-here';
```

## Analytics Queries

### Calculate Average Response Time per Application

```sql
SELECT
    a.app_name,
    AVG(EXTRACT(EPOCH FROM (cm.responded_at - cm.requested_at))) as avg_response_seconds,
    COUNT(*) as total_messages,
    COUNT(CASE WHEN cm.status = 'completed' THEN 1 END) as completed_messages,
    COUNT(CASE WHEN cm.status = 'failed' THEN 1 END) as failed_messages
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
JOIN applications a ON ua.app_id = a.app_id
WHERE cm.status = 'completed'
GROUP BY a.app_name
ORDER BY avg_response_seconds DESC;
```

### User Activity Statistics

```sql
SELECT
    u.telegram_id,
    u.display_name,
    COUNT(DISTINCT a.app_id) as apps_count,
    COUNT(cm.message_id) as total_messages,
    COUNT(CASE WHEN cm.status = 'completed' THEN 1 END) as completed_messages,
    MAX(cm.requested_at) as last_activity
FROM users u
LEFT JOIN user_applications ua ON u.user_id = ua.user_id
LEFT JOIN applications a ON ua.app_id = a.app_id
LEFT JOIN chat_messages cm ON ua.user_app_id = cm.user_app_id
WHERE u.is_admin = false
GROUP BY u.user_id
ORDER BY last_activity DESC NULLS LAST;
```

### Application Usage Statistics

```sql
SELECT
    a.app_name,
    COUNT(DISTINCT ua.user_id) as total_users,
    COUNT(cm.message_id) as total_messages,
    COUNT(CASE WHEN cm.status = 'pending' THEN 1 END) as pending_messages,
    MAX(cm.requested_at) as last_message_at
FROM applications a
LEFT JOIN user_applications ua ON a.app_id = ua.app_id
LEFT JOIN chat_messages cm ON ua.user_app_id = cm.user_app_id
WHERE a.is_active = true
GROUP BY a.app_id
ORDER BY total_messages DESC;
```

### Recent Activity Timeline

```sql
SELECT
    cm.requested_at,
    u.telegram_id,
    a.app_name,
    cm.request_text,
    cm.status,
    CASE
        WHEN cm.responded_at IS NOT NULL
        THEN EXTRACT(EPOCH FROM (cm.responded_at - cm.requested_at))
        ELSE NULL
    END as response_time_seconds
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
JOIN users u ON ua.user_id = u.user_id
JOIN applications a ON ua.app_id = a.app_id
ORDER BY cm.requested_at DESC
LIMIT 50;
```

## Dependency Checking (Before DELETE)

### Check User Dependencies

```sql
SELECT
    'user_applications' as table_name,
    COUNT(*) as dependent_records
FROM user_applications
WHERE user_id = 'user-uuid-here'
UNION ALL
SELECT
    'chat_messages (via user_applications)',
    COUNT(*)
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
WHERE ua.user_id = 'user-uuid-here';
```

### Check Application Dependencies

```sql
SELECT
    'user_applications' as table_name,
    COUNT(*) as dependent_records
FROM user_applications
WHERE app_id = 'app-uuid-here'
UNION ALL
SELECT
    'chat_messages (via user_applications)',
    COUNT(*)
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
WHERE ua.app_id = 'app-uuid-here';
```

### Check User-Application Dependencies

```sql
SELECT COUNT(*) as dependent_chat_messages
FROM chat_messages
WHERE user_app_id = 'user-app-uuid-here';
```

## Notes

- All queries should be adapted based on the current schema from [doc/schema.sql](../../doc/schema.sql)
- UUIDs shown as 'uuid-here' should be replaced with actual UUIDs from database lookups
- Timestamps use TIMESTAMPTZ (timezone-aware)
- JSONB queries use PostgreSQL JSONB operators (`->`, `->>`, `@>`, `?`)
- CASCADE deletes are automatic based on foreign key constraints
- Always verify schema with `list_tables` MCP tool before complex operations
