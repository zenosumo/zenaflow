---
name: zenaflow-db
description: Manage the Zenaflow PostgreSQL database (users, applications, user_applications, chat_messages). Use when querying, creating, updating, or deleting data in the zenaflow database. Handles full CRUD operations with mandatory user confirmation for destructive operations.
allowed-tools: mcp__postgres__*, Read, AskUserQuestion
---

# Zenaflow Database Management Skill

This skill provides comprehensive database management for the Zenaflow multi-app platform using the PostgreSQL MCP server.

## Critical Safety Rules

### Mandatory Confirmation Protocol

**ALWAYS follow this protocol for UPDATE, DELETE, and INSERT operations:**

1. **Read the schema first**: Before ANY database operation, read [doc/schema.sql](../../doc/schema.sql) to understand:
   - Current table structure
   - Business rules and constraints
   - Foreign key relationships
   - Triggers and defaults

2. **Verify current state**: Use `list_tables` MCP tool to verify the actual database structure matches the schema

3. **Show exact SQL query**: Display the complete SQL query you plan to execute

4. **Request confirmation**: Use the `AskUserQuestion` tool to ask the user to confirm the operation with the exact SQL shown

5. **Execute only after approval**: Only run the query after explicit user confirmation

### Operation-Specific Rules

#### SELECT Operations
- Auto-execute without confirmation
- Prefer JOINs over multiple queries when fetching related data
- Use proper column selection instead of `SELECT *` when possible

#### INSERT Operations
- ALWAYS show the exact INSERT statement
- ALWAYS request user confirmation before executing
- Validate against schema constraints before proposing the query

#### UPDATE Operations
- ALWAYS show the exact UPDATE statement with WHERE clause
- ALWAYS request user confirmation before executing
- **Single record**: Show which record will be affected
- **Multiple records**: Show COUNT of affected records before asking confirmation
- Warn if no WHERE clause (affects all records)

#### DELETE Operations
- ALWAYS show the exact DELETE statement with WHERE clause
- ALWAYS request user confirmation before executing
- **Check dependencies first**: Query for dependent records (foreign key relationships)
- **Ask about cascading deletes**: If dependent records exist, ask user:
  - "This record has X dependent records in [table_name]. The CASCADE constraint will automatically delete them. Do you want to proceed?"
- **Single record**: Show which record will be deleted
- **Multiple records**: Show COUNT of records to be deleted before asking confirmation
- **NEVER allow**: `DELETE FROM table` without WHERE clause without explicit double-confirmation

#### FORBIDDEN Operations (Always Refuse)
- `DROP TABLE`
- `DROP DATABASE`
- `TRUNCATE TABLE`
- `ALTER TABLE` (schema changes require manual review)
- Multiple DELETE/UPDATE operations in a single query without WHERE clause

## Workflow

### Standard Database Operation Workflow

```
1. User requests database operation
   ↓
2. Read doc/schema.sql to understand schema and business rules
   ↓
3. Use list_tables MCP tool to verify current database state
   ↓
4. If discrepancy detected between schema file and actual database:
   - Alert user about the difference
   - Ask which source to trust
   ↓
5. For SELECT: Execute query, return results
   ↓
6. For INSERT/UPDATE/DELETE:
   a. Construct SQL query following best practices
   b. For DELETE: Check for dependent records first
   c. Show exact SQL to user
   d. Use AskUserQuestion to request confirmation
   e. Execute only after approval
   f. Report success/failure with row count affected
```

### Query Best Practices

**Use JOINs for Related Data**

Good example (user requests "show all apps available to user @pocmior"):
```sql
SELECT
    u.display_name,
    u.telegram_id,
    a.app_name,
    a.description,
    a.bot_username,
    ua.created_at as access_granted_at
FROM users u
JOIN user_applications ua ON u.user_id = ua.user_id
JOIN applications a ON ua.app_id = a.app_id
WHERE u.telegram_id = '@pocmior'
ORDER BY a.app_name;
```

Bad example (multiple separate queries):
```sql
-- Don't do this
SELECT user_id FROM users WHERE telegram_id = '@pocmior';
-- Then query user_applications
-- Then query applications
```

**Handle Dependencies for DELETE**

Before deleting a user, check dependencies:
```sql
-- First, check what will be cascade-deleted
SELECT
    'user_applications' as table_name,
    COUNT(*) as dependent_records
FROM user_applications
WHERE user_id = 'uuid-here'
UNION ALL
SELECT
    'chat_messages (via user_applications)',
    COUNT(*)
FROM chat_messages cm
JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
WHERE ua.user_id = 'uuid-here';
```

Then show results to user and ask for confirmation before deleting.

## Database Schema Overview

The Zenaflow database powers a multi-app Telegram bot platform with centralized user management.

**Core Tables** (always refer to [doc/schema.sql](../../doc/schema.sql) for current structure):

- **users**: User accounts with telegram_id, phone_number, display_name, admin status, and status management (active/blocked/suspended)
- **applications**: Available apps (e.g., deanna, b4, anaketa) with bot usernames
- **user_applications**: Junction table linking users to their accessible apps
- **chat_messages**: Request/response pairs with status tracking (pending/completed/failed/timeout)

**Key Relationships**:
- Users ↔ Applications: Many-to-many via user_applications
- Messages belong to user-application pairings (via user_app_id), not users or apps independently

**Important Constraints** (see schema for full details):
- Users must have telegram_id OR phone_number (at least one)
- telegram_id format: WITH @ prefix (e.g., '@pocmior')
- phone_number format: digits only (e.g., '393247766945')
- User status: 'active', 'blocked', 'suspended'
- Suspended users require active_after timestamp
- Message status lifecycle: pending → completed/failed/timeout
- Message deduplication via (platform, message_id) unique constraint

## Common Operations Reference

See [reference.md](reference.md) for detailed query examples.

## MCP Tools Available

From the postgres MCP server (`/opt/zenaflow/mcp-toolbox/start.sh`):

**Schema Discovery**:
- `list_tables` - List all tables and their structure
- `list_table_stats` - Get table statistics (row counts, indexes, etc.)
- `list_indexes` - Show indexes for performance analysis
- `get_column_cardinality` - Analyze data distribution in columns

**Query Execution**:
- `execute_sql` - Execute any SQL query (SELECT, INSERT, UPDATE, DELETE)

**Database Health**:
- `database_overview` - Check database connection and health
- `list_active_queries` - Monitor running queries
- `list_locks` - Check for blocking queries

## Error Handling

**When errors occur**:
1. Show the error message to the user
2. Explain what likely caused it (constraint violation, foreign key, etc.)
3. Suggest corrective action based on schema rules
4. Do NOT retry automatically - ask user how to proceed

**Common Errors**:
- Foreign key violation: Parent record doesn't exist or child records prevent deletion
- Unique constraint violation: telegram_id, phone_number, or email already exists
- Check constraint violation: Invalid status value, missing required fields
- Not-null violation: Required field is missing

## Example Interaction

**User Request**: "Delete user @testuser"

**Skill Response**:
```
I'll help you delete the user. Let me first check the current schema and dependencies.

[Reads doc/schema.sql]
[Runs list_tables to verify structure]

Found user: @testuser (user_id: abc-123-def)

Checking dependencies...

This user has:
- 2 application access records in user_applications (deanna, b4)
- 15 chat messages across both applications

Due to CASCADE constraints, deleting this user will automatically delete:
- 2 user_applications records
- 15 chat_messages records

SQL to execute:
DELETE FROM users WHERE telegram_id = '@testuser';

[Uses AskUserQuestion]:
This operation will delete 1 user record and CASCADE delete 17 dependent records (2 user_applications, 15 chat_messages).

Do you want to proceed?
- Yes, delete the user and all dependent data
- No, cancel the operation
```

**After user confirms**: Execute the DELETE and report results.

## Progressive Disclosure

This SKILL.md contains essential instructions. For detailed query examples and patterns, see:
- [reference.md](reference.md) - Common query patterns organized by use case
