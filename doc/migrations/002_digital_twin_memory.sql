-- ============================================================================
-- DIGITAL TWIN ACCESS CONTROL HARDENING MIGRATION v1.0
-- ============================================================================
-- Purpose: Strengthen Router authorization for Telegram-driven app workflows
-- Implements:
--   1) Stable Telegram identity via users.telegram_user_id
--   2) Deterministic app-access resolution function (fail-closed decisions)
-- Related plan: plans/deanna-cognitive-brain.md
-- ============================================================================

-- 1) Stable Telegram identity (numeric Telegram user id)
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS telegram_user_id BIGINT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_telegram_user_id
    ON users(telegram_user_id)
    WHERE telegram_user_id IS NOT NULL;

COMMENT ON COLUMN users.telegram_user_id IS
    'Stable Telegram numeric user id (preferred over mutable username handle)';

-- 2) Resolve + authorize user/app access in one deterministic query path
CREATE OR REPLACE FUNCTION resolve_user_app_access(
    p_app_name TEXT,
    p_telegram_user_id BIGINT,
    p_telegram_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    user_id UUID,
    user_app_id UUID,
    app_id UUID,
    decision TEXT,
    user_status TEXT,
    active_after TIMESTAMPTZ
) AS $$
DECLARE
    v_app_id UUID;
    v_user_id UUID;
    v_user_status TEXT;
    v_active_after TIMESTAMPTZ;
    v_user_app_id UUID;
    v_telegram_id TEXT;
BEGIN
    v_telegram_id := NULLIF(trim(p_telegram_id), '');
    IF v_telegram_id IS NOT NULL AND left(v_telegram_id, 1) <> '@' THEN
        v_telegram_id := '@' || v_telegram_id;
    END IF;

    SELECT a.app_id
    INTO v_app_id
    FROM applications a
    WHERE a.app_name = p_app_name
      AND a.is_active = TRUE
    LIMIT 1;

    IF v_app_id IS NULL THEN
        RETURN QUERY
        SELECT
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            'app_inactive'::TEXT,
            NULL::TEXT,
            NULL::TIMESTAMPTZ;
        RETURN;
    END IF;

    SELECT
        u.user_id,
        u.status::TEXT,
        u.active_after
    INTO
        v_user_id,
        v_user_status,
        v_active_after
    FROM users u
    WHERE
        (p_telegram_user_id IS NOT NULL AND u.telegram_user_id = p_telegram_user_id)
        OR
        (v_telegram_id IS NOT NULL AND lower(u.telegram_id) = lower(v_telegram_id))
    ORDER BY
        CASE
            WHEN p_telegram_user_id IS NOT NULL AND u.telegram_user_id = p_telegram_user_id THEN 0
            ELSE 1
        END,
        u.created_at ASC
    LIMIT 1;

    IF v_user_id IS NULL THEN
        RETURN QUERY
        SELECT
            NULL::UUID,
            NULL::UUID,
            v_app_id,
            'unknown_user'::TEXT,
            NULL::TEXT,
            NULL::TIMESTAMPTZ;
        RETURN;
    END IF;

    IF v_user_status = 'blocked' THEN
        RETURN QUERY
        SELECT
            v_user_id,
            NULL::UUID,
            v_app_id,
            'blocked'::TEXT,
            v_user_status,
            v_active_after;
        RETURN;
    END IF;

    IF v_user_status = 'suspended' AND v_active_after > NOW() THEN
        RETURN QUERY
        SELECT
            v_user_id,
            NULL::UUID,
            v_app_id,
            'suspended'::TEXT,
            v_user_status,
            v_active_after;
        RETURN;
    END IF;

    SELECT ua.user_app_id
    INTO v_user_app_id
    FROM user_applications ua
    WHERE ua.user_id = v_user_id
      AND ua.app_id = v_app_id
    LIMIT 1;

    IF v_user_app_id IS NULL THEN
        RETURN QUERY
        SELECT
            v_user_id,
            NULL::UUID,
            v_app_id,
            'no_app_access'::TEXT,
            v_user_status,
            v_active_after;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        v_user_id,
        v_user_app_id,
        v_app_id,
        'authorized'::TEXT,
        v_user_status,
        v_active_after;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION resolve_user_app_access(TEXT, BIGINT, TEXT) IS
    'Resolve Telegram user and app access with fail-closed decision codes: authorized, unknown_user, blocked, suspended, app_inactive, no_app_access';

-- ============================================================================
-- END OF MIGRATION
-- ============================================================================
