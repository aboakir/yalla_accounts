-- Yalla Licensing Server
-- SEC.015 - Security / Recovery / Sessions / Audit
-- Canonical engine: PostgreSQL 16+
-- Server-side administrative authentication only. Never execute against yalla_accounts.db.

BEGIN;

CREATE TABLE yalla_admin_security_policy (
    policy_id SMALLINT PRIMARY KEY,
    access_session_minutes SMALLINT NOT NULL DEFAULT 15,
    session_idle_minutes SMALLINT NOT NULL DEFAULT 30,
    session_absolute_hours SMALLINT NOT NULL DEFAULT 12,
    refresh_rotation_required BOOLEAN NOT NULL DEFAULT TRUE,
    super_owner_mfa_required BOOLEAN NOT NULL DEFAULT TRUE,
    break_glass_reauth_minutes SMALLINT NOT NULL DEFAULT 5,
    login_failure_window_minutes SMALLINT NOT NULL DEFAULT 15,
    throttle_after_failures SMALLINT NOT NULL DEFAULT 5,
    lock_after_failures SMALLINT NOT NULL DEFAULT 10,
    lock_minutes SMALLINT NOT NULL DEFAULT 30,
    recovery_challenge_minutes SMALLINT NOT NULL DEFAULT 15,
    recovery_max_attempts SMALLINT NOT NULL DEFAULT 5,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_security_policy_singleton_ck CHECK (policy_id=1),
    CONSTRAINT yalla_admin_security_policy_access_ck CHECK (access_session_minutes BETWEEN 5 AND 60),
    CONSTRAINT yalla_admin_security_policy_idle_ck CHECK (session_idle_minutes BETWEEN 10 AND 240),
    CONSTRAINT yalla_admin_security_policy_absolute_ck CHECK (session_absolute_hours BETWEEN 1 AND 24),
    CONSTRAINT yalla_admin_security_policy_reauth_ck CHECK (break_glass_reauth_minutes BETWEEN 1 AND 15),
    CONSTRAINT yalla_admin_security_policy_failures_ck CHECK (throttle_after_failures >= 3 AND lock_after_failures > throttle_after_failures)
);

INSERT INTO yalla_admin_security_policy(
    policy_id, access_session_minutes, session_idle_minutes, session_absolute_hours,
    refresh_rotation_required, super_owner_mfa_required, break_glass_reauth_minutes,
    login_failure_window_minutes, throttle_after_failures, lock_after_failures,
    lock_minutes, recovery_challenge_minutes, recovery_max_attempts
) VALUES (1,15,30,12,TRUE,TRUE,5,15,5,10,30,15,5);

CREATE TABLE yalla_admin_auth_credentials (
    admin_user_id UUID PRIMARY KEY REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    password_hash TEXT NOT NULL,
    password_algorithm VARCHAR(24) NOT NULL DEFAULT 'ARGON2ID',
    password_version INTEGER NOT NULL DEFAULT 1,
    pepper_version SMALLINT NOT NULL DEFAULT 1,
    password_changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    last_failed_at TIMESTAMPTZ,
    locked_until TIMESTAMPTZ,
    must_rotate BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_credentials_algo_ck CHECK (password_algorithm='ARGON2ID'),
    CONSTRAINT yalla_admin_credentials_hash_ck CHECK (password_hash LIKE '$argon2id$%'),
    CONSTRAINT yalla_admin_credentials_fail_ck CHECK (failed_attempts >= 0)
);

COMMENT ON COLUMN yalla_admin_auth_credentials.password_hash IS 'Argon2id PHC string only; plaintext password and server pepper are never stored in PostgreSQL.';
COMMENT ON COLUMN yalla_admin_auth_credentials.pepper_version IS 'References a server secret-store pepper generation by version only; secret bytes are outside PostgreSQL.';

CREATE TABLE yalla_admin_mfa_factors (
    id UUID PRIMARY KEY,
    admin_user_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    factor_type VARCHAR(24) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    label TEXT,
    secret_reference TEXT,
    webauthn_public_key JSONB,
    verified_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_mfa_type_ck CHECK (factor_type IN ('TOTP','WEBAUTHN')),
    CONSTRAINT yalla_admin_mfa_status_ck CHECK (status IN ('PENDING','ACTIVE','REVOKED')),
    CONSTRAINT yalla_admin_mfa_material_ck CHECK (
        (factor_type='TOTP' AND secret_reference IS NOT NULL AND webauthn_public_key IS NULL) OR
        (factor_type='WEBAUTHN' AND webauthn_public_key IS NOT NULL AND secret_reference IS NULL)
    ),
    CONSTRAINT yalla_admin_mfa_secret_ref_ck CHECK (secret_reference IS NULL OR secret_reference LIKE 'secret://%')
);
CREATE INDEX yalla_admin_mfa_user_ix ON yalla_admin_mfa_factors(admin_user_id,status);

CREATE TABLE yalla_admin_recovery_codes (
    id UUID PRIMARY KEY,
    admin_user_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    code_digest BYTEA NOT NULL,
    digest_algorithm VARCHAR(32) NOT NULL DEFAULT 'HMAC-SHA256',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    used_at TIMESTAMPTZ,
    CONSTRAINT yalla_admin_recovery_digest_ck CHECK (digest_algorithm='HMAC-SHA256'),
    UNIQUE(admin_user_id, code_digest)
);

CREATE TABLE yalla_admin_auth_challenges (
    id UUID PRIMARY KEY,
    admin_user_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    challenge_type VARCHAR(24) NOT NULL,
    challenge_digest BYTEA,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    source_ip INET,
    source_device TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    CONSTRAINT yalla_admin_challenge_type_ck CHECK (challenge_type IN ('ENROLLMENT','LOGIN_MFA','RECOVERY','REAUTH')),
    CONSTRAINT yalla_admin_challenge_status_ck CHECK (status IN ('PENDING','VERIFIED','CONSUMED','EXPIRED','REVOKED')),
    CONSTRAINT yalla_admin_challenge_attempts_ck CHECK (attempts >= 0 AND max_attempts BETWEEN 1 AND 10),
    CONSTRAINT yalla_admin_challenge_expiry_ck CHECK (expires_at > created_at)
);
CREATE INDEX yalla_admin_auth_challenges_user_ix ON yalla_admin_auth_challenges(admin_user_id,status,expires_at);

CREATE TABLE yalla_admin_sessions (
    id UUID PRIMARY KEY,
    admin_user_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    session_family_id UUID NOT NULL,
    access_token_digest BYTEA NOT NULL UNIQUE,
    authentication_level VARCHAR(16) NOT NULL,
    auth_time TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    access_expires_at TIMESTAMPTZ NOT NULL,
    idle_expires_at TIMESTAMPTZ NOT NULL,
    absolute_expires_at TIMESTAMPTZ NOT NULL,
    source_ip INET,
    source_device TEXT,
    user_agent TEXT,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    revoked_at TIMESTAMPTZ,
    revoked_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    revoke_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_session_auth_level_ck CHECK (authentication_level IN ('PASSWORD','MFA')),
    CONSTRAINT yalla_admin_session_status_ck CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','COMPROMISED')),
    CONSTRAINT yalla_admin_session_windows_ck CHECK (
        access_expires_at > auth_time AND idle_expires_at > auth_time AND absolute_expires_at > auth_time AND
        access_expires_at <= absolute_expires_at AND idle_expires_at <= absolute_expires_at
    ),
    CONSTRAINT yalla_admin_session_revoke_ck CHECK ((status IN ('REVOKED','COMPROMISED') AND revoked_at IS NOT NULL) OR status NOT IN ('REVOKED','COMPROMISED'))
);
CREATE INDEX yalla_admin_sessions_user_ix ON yalla_admin_sessions(admin_user_id,status,last_seen_at DESC);
CREATE INDEX yalla_admin_sessions_family_ix ON yalla_admin_sessions(session_family_id,status);

CREATE TABLE yalla_admin_refresh_tokens (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES yalla_admin_sessions(id) ON DELETE RESTRICT,
    token_digest BYTEA NOT NULL UNIQUE,
    generation INTEGER NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'CURRENT',
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    rotated_at TIMESTAMPTZ,
    replaced_by_id UUID REFERENCES yalla_admin_refresh_tokens(id) ON DELETE RESTRICT,
    reuse_detected_at TIMESTAMPTZ,
    CONSTRAINT yalla_admin_refresh_status_ck CHECK (status IN ('CURRENT','ROTATED','REVOKED','REUSED','EXPIRED')),
    CONSTRAINT yalla_admin_refresh_generation_ck CHECK (generation >= 1),
    CONSTRAINT yalla_admin_refresh_expiry_ck CHECK (expires_at > issued_at),
    CONSTRAINT yalla_admin_refresh_rotation_ck CHECK ((status='ROTATED' AND rotated_at IS NOT NULL AND replaced_by_id IS NOT NULL) OR status <> 'ROTATED')
);
CREATE INDEX yalla_admin_refresh_session_ix ON yalla_admin_refresh_tokens(session_id,generation DESC);

CREATE TABLE yalla_admin_reauth_contexts (
    id UUID PRIMARY KEY,
    admin_user_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    session_id UUID NOT NULL REFERENCES yalla_admin_sessions(id) ON DELETE RESTRICT,
    purpose VARCHAR(32) NOT NULL,
    authentication_level VARCHAR(16) NOT NULL DEFAULT 'MFA',
    verified_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    source_ip INET,
    source_device TEXT,
    CONSTRAINT yalla_admin_reauth_purpose_ck CHECK (purpose IN ('BREAK_GLASS','SECURITY_CHANGE','RECOVERY_CHANGE')),
    CONSTRAINT yalla_admin_reauth_level_ck CHECK (authentication_level='MFA'),
    CONSTRAINT yalla_admin_reauth_window_ck CHECK (expires_at > verified_at AND expires_at <= verified_at + INTERVAL '15 minutes')
);
CREATE INDEX yalla_admin_reauth_user_ix ON yalla_admin_reauth_contexts(admin_user_id,session_id,expires_at DESC);

ALTER TABLE yalla_break_glass_grants
    ADD CONSTRAINT yalla_break_glass_reauth_fk
    FOREIGN KEY (reauth_context_id) REFERENCES yalla_admin_reauth_contexts(id) ON DELETE RESTRICT;

CREATE TABLE yalla_admin_login_attempts (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_user_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    normalized_identifier_digest BYTEA NOT NULL,
    outcome VARCHAR(24) NOT NULL,
    failure_code VARCHAR(48),
    source_ip INET,
    source_device TEXT,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_login_outcome_ck CHECK (outcome IN ('SUCCESS','FAILURE','THROTTLED','LOCKED','MFA_REQUIRED'))
);
CREATE INDEX yalla_admin_login_attempts_user_ix ON yalla_admin_login_attempts(admin_user_id,occurred_at DESC);
CREATE INDEX yalla_admin_login_attempts_ip_ix ON yalla_admin_login_attempts(source_ip,occurred_at DESC);

CREATE TABLE yalla_admin_security_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_user_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    session_id UUID REFERENCES yalla_admin_sessions(id) ON DELETE RESTRICT,
    event_type VARCHAR(96) NOT NULL,
    severity VARCHAR(16) NOT NULL,
    event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    source_ip INET,
    source_device TEXT,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_security_event_severity_ck CHECK (severity IN ('INFO','WARNING','HIGH','CRITICAL'))
);
CREATE INDEX yalla_admin_security_events_user_ix ON yalla_admin_security_events(admin_user_id,detected_at DESC);

CREATE TABLE yalla_audit_chain_heads (
    chain_name VARCHAR(48) PRIMARY KEY,
    last_sequence BIGINT NOT NULL DEFAULT 0,
    last_event_hash CHAR(64),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_audit_chain_head_hash_ck CHECK (last_event_hash IS NULL OR last_event_hash ~ '^[0-9A-Fa-f]{64}$')
);
INSERT INTO yalla_audit_chain_heads(chain_name,last_sequence,last_event_hash) VALUES ('CONTROL_CENTER_ADMIN',0,NULL);

CREATE TABLE yalla_audit_chain_seals (
    audit_log_id BIGINT PRIMARY KEY REFERENCES audit_logs(id) ON DELETE RESTRICT,
    chain_name VARCHAR(48) NOT NULL REFERENCES yalla_audit_chain_heads(chain_name) ON DELETE RESTRICT,
    chain_sequence BIGINT NOT NULL,
    previous_event_hash CHAR(64),
    event_hash CHAR(64) NOT NULL,
    canonicalization VARCHAR(32) NOT NULL DEFAULT 'RFC8785-JCS',
    hash_algorithm VARCHAR(16) NOT NULL DEFAULT 'SHA-256',
    sealed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_audit_chain_sequence_ck CHECK (chain_sequence > 0),
    CONSTRAINT yalla_audit_chain_prev_hash_ck CHECK (previous_event_hash IS NULL OR previous_event_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT yalla_audit_chain_event_hash_ck CHECK (event_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT yalla_audit_chain_algo_ck CHECK (canonicalization='RFC8785-JCS' AND hash_algorithm='SHA-256'),
    UNIQUE(chain_name,chain_sequence)
);

CREATE OR REPLACE FUNCTION yalla_protect_audit_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Audit records and chain seals are immutable';
END;
$$;

DROP TRIGGER IF EXISTS yalla_audit_logs_no_delete_trg ON audit_logs;
CREATE TRIGGER yalla_audit_logs_immutable_trg
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION yalla_protect_audit_immutable();

CREATE TRIGGER yalla_audit_chain_seals_immutable_trg
BEFORE UPDATE OR DELETE ON yalla_audit_chain_seals
FOR EACH ROW EXECUTE FUNCTION yalla_protect_audit_immutable();

CREATE OR REPLACE FUNCTION yalla_append_audit_chain_seal(
    p_audit_log_id BIGINT,
    p_event_hash CHAR(64)
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_sequence BIGINT;
    v_previous CHAR(64);
BEGIN
    IF p_event_hash IS NULL OR p_event_hash !~ '^[0-9A-Fa-f]{64}$' THEN
        RAISE EXCEPTION 'SEC.015 requires a canonical SHA-256 event hash';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM audit_logs WHERE id=p_audit_log_id) THEN
        RAISE EXCEPTION 'Audit log event does not exist';
    END IF;

    SELECT last_sequence,last_event_hash INTO v_sequence,v_previous
      FROM yalla_audit_chain_heads
     WHERE chain_name='CONTROL_CENTER_ADMIN'
     FOR UPDATE;
    v_sequence := v_sequence + 1;

    INSERT INTO yalla_audit_chain_seals(
        audit_log_id,chain_name,chain_sequence,previous_event_hash,event_hash
    ) VALUES (
        p_audit_log_id,'CONTROL_CENTER_ADMIN',v_sequence,v_previous,upper(p_event_hash)
    );

    UPDATE yalla_audit_chain_heads
       SET last_sequence=v_sequence,last_event_hash=upper(p_event_hash),updated_at=CURRENT_TIMESTAMP
     WHERE chain_name='CONTROL_CENTER_ADMIN';
    RETURN v_sequence;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_revoke_admin_session(
    p_session_id UUID,
    p_actor_id UUID,
    p_reason TEXT
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) < 8 THEN
        RAISE EXCEPTION 'Session revocation requires a meaningful reason';
    END IF;
    UPDATE yalla_admin_sessions
       SET status='REVOKED',revoked_at=CURRENT_TIMESTAMP,revoked_by_actor_id=p_actor_id,revoke_reason=p_reason
     WHERE id=p_session_id AND status='ACTIVE';
    UPDATE yalla_admin_refresh_tokens SET status='REVOKED'
     WHERE session_id=p_session_id AND status='CURRENT';
END;
$$;

CREATE OR REPLACE FUNCTION yalla_revoke_all_admin_sessions(
    p_admin_user_id UUID,
    p_actor_id UUID,
    p_reason TEXT
) RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE v_count INTEGER;
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) < 8 THEN
        RAISE EXCEPTION 'Session revocation requires a meaningful reason';
    END IF;
    UPDATE yalla_admin_sessions
       SET status='REVOKED',revoked_at=CURRENT_TIMESTAMP,revoked_by_actor_id=p_actor_id,revoke_reason=p_reason
     WHERE admin_user_id=p_admin_user_id AND status='ACTIVE';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    UPDATE yalla_admin_refresh_tokens rt SET status='REVOKED'
     WHERE status='CURRENT' AND EXISTS (
         SELECT 1 FROM yalla_admin_sessions s WHERE s.id=rt.session_id AND s.admin_user_id=p_admin_user_id AND s.status='REVOKED'
     );
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_assert_fresh_break_glass_reauth(
    p_admin_user_id UUID,
    p_session_id UUID,
    p_reauth_context_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
          FROM yalla_admin_reauth_contexts rc
          JOIN yalla_admin_security_policy sp ON sp.policy_id=1
         WHERE rc.id=p_reauth_context_id
           AND rc.admin_user_id=p_admin_user_id
           AND rc.session_id=p_session_id
           AND rc.purpose='BREAK_GLASS'
           AND rc.authentication_level='MFA'
           AND rc.consumed_at IS NULL
           AND rc.expires_at > CURRENT_TIMESTAMP
           AND rc.verified_at >= CURRENT_TIMESTAMP - make_interval(mins => sp.break_glass_reauth_minutes)
    );
END;
$$;

CREATE OR REPLACE VIEW yalla_cc_admin_sessions AS
SELECT
    s.id,s.admin_user_id,au.email,au.display_name,s.authentication_level,
    s.auth_time,s.last_seen_at,s.access_expires_at,s.idle_expires_at,s.absolute_expires_at,
    s.source_ip,s.source_device,s.status,s.revoked_at,s.revoke_reason
FROM yalla_admin_sessions s
JOIN yalla_admin_users au ON au.id=s.admin_user_id;

CREATE OR REPLACE VIEW yalla_cc_admin_security_events AS
SELECT
    se.id,se.admin_user_id,au.email,se.session_id,se.event_type,se.severity,
    se.event_data,se.source_ip,se.source_device,se.detected_at
FROM yalla_admin_security_events se
LEFT JOIN yalla_admin_users au ON au.id=se.admin_user_id;

INSERT INTO yalla_schema_migrations(version,stage,description)
VALUES (10,'SEC.015','Admin authentication, MFA/recovery, secure sessions, reauthentication, and tamper-evident audit hardening');

COMMIT;
