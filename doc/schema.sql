-- ============================================================================
-- VADER BOT DATABASE SCHEMA v2.2
-- ============================================================================
-- Purpose: Account management system for multi-app platform
-- Architecture:
--   - Admins use Vader bot to pre-register users
--   - Users initiate conversations with app-specific bots (Deanna, B4, etc.)
--   - Platform-agnostic design supports Telegram, WhatsApp, and future sources
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- USERS TABLE
-- ============================================================================
-- Stores user and admin account information
-- Business rules:
--   - At least one of telegram_id OR phone_number must be populated
--   - telegram_id, phone_number, and email must be unique when not null
--   - display_name is always required
--   - Admins can access Vader bot to manage users
--   - telegram_id stored WITH @ prefix (e.g., '@pocmior')
--   - phone_number stored as digits only (e.g., '393247766945')
--   - email is optional but must be unique when provided
--   - status can be: active, blocked, suspended (default: active)
--   - active_after is required when status = 'suspended', defines when user can access again
--   - blocked users are permanently denied access
--   - suspended users are temporarily denied until active_after timestamp
-- ============================================================================

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    telegram_id VARCHAR(33) UNIQUE,
    phone_number TEXT UNIQUE,
    email VARCHAR(255) UNIQUE,
    display_name VARCHAR(255) NOT NULL,
    is_admin BOOLEAN NOT NULL DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    active_after TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_users_contact_method_required CHECK (
        telegram_id IS NOT NULL OR phone_number IS NOT NULL
    ),

    CONSTRAINT chk_users_status_valid CHECK (
        status IN ('active', 'blocked', 'suspended')
    ),

    CONSTRAINT chk_users_suspended_active_after CHECK (
        (status = 'suspended' AND active_after IS NOT NULL) OR
        (status != 'suspended')
    )
);

-- Indexes for common queries
CREATE INDEX idx_users_telegram_id ON users(telegram_id) WHERE telegram_id IS NOT NULL;
CREATE INDEX idx_users_phone_number ON users(phone_number) WHERE phone_number IS NOT NULL;
CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_users_is_admin ON users(is_admin);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_active_after ON users(active_after) WHERE active_after IS NOT NULL;
CREATE INDEX idx_users_created_at ON users(created_at);

-- Trigger function for updated_at
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to users table
CREATE TRIGGER trg_users_set_updated_at_before_update
    BEFORE UPDATE ON users
    FOR EACH ROW
    WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION trg_set_updated_at();

-- ============================================================================
-- APPLICATIONS TABLE
-- ============================================================================
-- Stores available applications in the platform
-- Each application has its own Telegram bot that users interact with
-- Initial apps: deanna, b4, anaketa
-- ============================================================================

CREATE TABLE applications (
    app_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    app_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    bot_username VARCHAR(33),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for active app queries
CREATE INDEX idx_applications_is_active_partial ON applications(is_active) WHERE is_active = true;
CREATE INDEX idx_applications_app_name ON applications(app_name);
CREATE INDEX idx_applications_bot_username_partial ON applications(bot_username) WHERE bot_username IS NOT NULL;

COMMENT ON COLUMN applications.bot_username IS 'Telegram bot username (e.g., @deanna_bot, @b4_bot)';

-- ============================================================================
-- USER_APPLICATIONS JUNCTION TABLE
-- ============================================================================
-- Many-to-many relationship between users and applications
-- Tracks which users have access to which applications
-- This is the entity that chat_messages are bound to (not users/apps directly)
-- ============================================================================

CREATE TABLE user_applications (
    user_app_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    app_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_user_applications_user_id
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    CONSTRAINT fk_user_applications_app_id
        FOREIGN KEY (app_id) REFERENCES applications(app_id) ON DELETE CASCADE,

    CONSTRAINT uq_user_applications_user_id_app_id UNIQUE (user_id, app_id)
);

-- Indexes for junction queries (composite covers individual lookups via leftmost prefix)
CREATE INDEX idx_user_applications_user_id_app_id ON user_applications(user_id, app_id);
CREATE INDEX idx_user_applications_app_id_user_id ON user_applications(app_id, user_id);

-- ============================================================================
-- CHAT_MESSAGES TABLE
-- ============================================================================
-- Stores all chat message exchanges (request/response pairs)
-- Messages belong to a user-application pairing (not users/apps independently)
-- Lifecycle:
--   1. Row inserted when user sends message (request_text filled, status='pending')
--   2. Row updated when app responds (response_text filled, status='completed')
-- Platform-agnostic design:
--   - source_payload stores raw message data from any platform (Telegram, WhatsApp, etc.)
--   - Deduplication via UNIQUE constraint on (platform, message_id)
-- ============================================================================

CREATE TABLE chat_messages (
    message_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_app_id UUID NOT NULL,
    request_text TEXT NOT NULL,
    response_text TEXT,
    alt_response_text TEXT,
    source_payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    error_message TEXT,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,

    CONSTRAINT fk_chat_messages_user_app_id
        FOREIGN KEY (user_app_id) REFERENCES user_applications(user_app_id) ON DELETE CASCADE,

    CONSTRAINT chk_chat_messages_status_valid
        CHECK (status IN ('pending', 'completed', 'failed', 'timeout')),

    CONSTRAINT chk_chat_messages_completed_integrity CHECK (
        (status = 'completed' AND response_text IS NOT NULL AND responded_at IS NOT NULL) OR
        (status != 'completed')
    ),

    CONSTRAINT chk_chat_messages_failed_integrity CHECK (
        (status = 'failed' AND error_message IS NOT NULL) OR
        (status != 'failed')
    ),

    CONSTRAINT chk_chat_messages_source_payload_structure CHECK (
        source_payload ? 'platform' AND
        source_payload ? 'message_id'
    )
);

-- Indexes for common queries
CREATE INDEX idx_chat_messages_user_app_id ON chat_messages(user_app_id);
CREATE INDEX idx_chat_messages_status ON chat_messages(status);
CREATE INDEX idx_chat_messages_requested_at_desc ON chat_messages(requested_at DESC);
CREATE INDEX idx_chat_messages_user_app_id_requested_at_desc ON chat_messages(user_app_id, requested_at DESC);

-- JSONB indexes for source_payload
CREATE INDEX idx_chat_messages_source_payload_gin ON chat_messages USING GIN (source_payload);
CREATE INDEX idx_chat_messages_source_platform ON chat_messages((source_payload->>'platform'));

-- Deduplication index (prevents duplicate webhook processing)
CREATE UNIQUE INDEX uq_chat_messages_source_platform_message_id
    ON chat_messages((source_payload->>'platform'), (source_payload->>'message_id'));

-- Specialized indexes for performance
CREATE INDEX idx_chat_messages_status_requested_at_pending
    ON chat_messages(status, requested_at)
    WHERE status = 'pending';

CREATE INDEX idx_chat_messages_user_app_id_responded_at_desc_completed
    ON chat_messages(user_app_id, responded_at DESC)
    WHERE status = 'completed';

-- Comments
COMMENT ON COLUMN chat_messages.alt_response_text IS
    'Alternative response text (A/B testing, fallback, sanitized version)';

COMMENT ON COLUMN chat_messages.source_payload IS
    'Platform-agnostic raw message data. Required fields: platform, message_id. Example: {"platform":"telegram","message_id":"12345","chat_id":"67890"}';

-- ============================================================================
-- USEFUL QUERIES FOR VADER BOT
-- ============================================================================

-- Check if user exists by telegram_id
-- SELECT EXISTS(SELECT 1 FROM users WHERE telegram_id = '@pocmior');

-- Check if user exists by phone_number
-- SELECT EXISTS(SELECT 1 FROM users WHERE phone_number = '393247766945');

-- Check if user exists by email
-- SELECT EXISTS(SELECT 1 FROM users WHERE email = 'user@example.com');

-- Check if user is accessible (not blocked, not suspended, or suspension expired)
-- SELECT user_id, status, active_after
-- FROM users
-- WHERE telegram_id = '@pocmior'
--   AND (status = 'active' OR (status = 'suspended' AND active_after <= NOW()));

-- Check if admin (for Vader access control)
-- SELECT is_admin FROM users WHERE telegram_id = '@admin_username';

-- Get user with their applications
-- SELECT u.*, array_agg(a.app_name) as applications
-- FROM users u
-- JOIN user_applications ua ON u.user_id = ua.user_id
-- JOIN applications a ON ua.app_id = a.app_id
-- WHERE u.telegram_id = '@pocmior'
-- GROUP BY u.user_id;

-- Get all active applications (for /newaccount app selection)
-- SELECT app_id, app_name, description FROM applications
-- WHERE is_active = true
-- ORDER BY app_name;

-- Get user_app_id for inserting messages (used by app workflows)
-- SELECT user_app_id FROM user_applications ua
-- JOIN users u ON ua.user_id = u.user_id
-- WHERE u.telegram_id = '@pocmior' AND ua.app_id = 'app-uuid';

-- Get user's chat history with specific app
-- SELECT
--     cm.message_id,
--     cm.request_text,
--     cm.response_text,
--     cm.alt_response_text,
--     cm.source_payload->>'platform' as platform,
--     cm.requested_at,
--     cm.responded_at,
--     u.display_name,
--     a.app_name
-- FROM chat_messages cm
-- JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
-- JOIN users u ON ua.user_id = u.user_id
-- JOIN applications a ON ua.app_id = a.app_id
-- WHERE u.telegram_id = '@pocmior' AND a.app_name = 'deanna'
-- ORDER BY cm.requested_at DESC
-- LIMIT 50;

-- Check for duplicate message (deduplication in workflows)
-- SELECT EXISTS(
--     SELECT 1 FROM chat_messages
--     WHERE source_payload->>'platform' = 'telegram'
--       AND source_payload->>'message_id' = '12345'
-- );

-- Calculate average response time per app
-- SELECT
--     a.app_name,
--     AVG(EXTRACT(EPOCH FROM (cm.responded_at - cm.requested_at))) as avg_response_seconds,
--     COUNT(*) as total_messages
-- FROM chat_messages cm
-- JOIN user_applications ua ON cm.user_app_id = ua.user_app_id
-- JOIN applications a ON ua.app_id = a.app_id
-- WHERE cm.status = 'completed'
-- GROUP BY a.app_name;

-- Get all users for a specific application
-- SELECT u.telegram_id, u.phone_number, u.email, u.display_name
-- FROM users u
-- JOIN user_applications ua ON u.user_id = ua.user_id
-- JOIN applications a ON ua.app_id = a.app_id
-- WHERE a.app_name = 'deanna' AND u.is_admin = false;

-- Get all blocked users
-- SELECT user_id, telegram_id, phone_number, display_name, updated_at
-- FROM users
-- WHERE status = 'blocked'
-- ORDER BY updated_at DESC;

-- Get all suspended users with expiry time
-- SELECT user_id, telegram_id, phone_number, display_name, active_after,
--        EXTRACT(EPOCH FROM (active_after - NOW())) / 3600 as hours_remaining
-- FROM users
-- WHERE status = 'suspended' AND active_after > NOW()
-- ORDER BY active_after ASC;

-- Get users whose suspension has expired (candidates for auto-reactivation)
-- SELECT user_id, telegram_id, phone_number, display_name
-- FROM users
-- WHERE status = 'suspended' AND active_after <= NOW();

-- Suspend user for specific duration (e.g., 7 days)
-- UPDATE users
-- SET status = 'suspended', active_after = NOW() + INTERVAL '7 days'
-- WHERE telegram_id = '@pocmior';

-- Block user permanently
-- UPDATE users
-- SET status = 'blocked', active_after = NULL
-- WHERE telegram_id = '@pocmior';

-- Reactivate user
-- UPDATE users
-- SET status = 'active', active_after = NULL
-- WHERE telegram_id = '@pocmior';

-- Get messages by platform
-- SELECT * FROM chat_messages
-- WHERE source_payload->>'platform' = 'telegram';

-- Get messages with alternative responses
-- SELECT * FROM chat_messages
-- WHERE alt_response_text IS NOT NULL;

-- Complex JSONB query example (find messages from specific Telegram user)
-- SELECT * FROM chat_messages
-- WHERE source_payload @> '{"from": {"username": "pocmior"}}'::jsonb;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
