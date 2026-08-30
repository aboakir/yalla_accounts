-- Yalla Licensing Server
-- SEC.006 - Activation API + First Online Activation
-- Canonical engine: PostgreSQL 16+
-- Plaintext activation codes and signing private keys are NEVER stored here.

BEGIN;

CREATE TABLE activation_grants (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    code_sha256 CHAR(64) NOT NULL UNIQUE,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    activation_kind VARCHAR(24) NOT NULL DEFAULT 'FIRST',
    max_uses INTEGER NOT NULL DEFAULT 1,
    use_count INTEGER NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,
    revocation_reason TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT activation_grants_hash_ck CHECK (code_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT activation_grants_status_ck CHECK (status IN ('ACTIVE','CONSUMED','REVOKED','EXPIRED')),
    CONSTRAINT activation_grants_kind_ck CHECK (activation_kind IN ('FIRST','REACTIVATION','DEVICE_REPLACEMENT','LICENSE_REFRESH')),
    CONSTRAINT activation_grants_usage_ck CHECK (max_uses >= 1 AND use_count >= 0 AND use_count <= max_uses),
    CONSTRAINT activation_grants_expiry_ck CHECK (expires_at > created_at),
    CONSTRAINT activation_grants_consumed_ck CHECK ((status = 'CONSUMED' AND consumed_at IS NOT NULL) OR status <> 'CONSUMED'),
    CONSTRAINT activation_grants_revoked_ck CHECK ((status = 'REVOKED' AND revoked_at IS NOT NULL AND revocation_reason IS NOT NULL) OR status <> 'REVOKED')
);

CREATE INDEX activation_grants_subscription_ix
    ON activation_grants(subscription_id, status, expires_at);

CREATE TABLE activation_challenges (
    id UUID PRIMARY KEY,
    grant_id UUID NOT NULL REFERENCES activation_grants(id) ON DELETE RESTRICT,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    device_id UUID NOT NULL,
    installation_id UUID NOT NULL,
    device_public_key TEXT NOT NULL,
    device_public_key_sha256 CHAR(64) NOT NULL,
    request_idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    proof_bytes_base64url TEXT NOT NULL,
    proof_bytes_sha256 CHAR(64) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ISSUED',
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    rejected_at TIMESTAMPTZ,
    rejection_reason TEXT,
    request_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT activation_challenges_key_hash_ck CHECK (device_public_key_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT activation_challenges_proof_bytes_ck CHECK (proof_bytes_base64url ~ '^[A-Za-z0-9_-]{22,1366}$'),
    CONSTRAINT activation_challenges_proof_hash_ck CHECK (proof_bytes_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT activation_challenges_status_ck CHECK (status IN ('ISSUED','CONSUMED','REJECTED','EXPIRED')),
    CONSTRAINT activation_challenges_expiry_ck CHECK (expires_at > issued_at),
    CONSTRAINT activation_challenges_consumed_ck CHECK ((status = 'CONSUMED' AND consumed_at IS NOT NULL) OR status <> 'CONSUMED'),
    CONSTRAINT activation_challenges_rejected_ck CHECK ((status = 'REJECTED' AND rejected_at IS NOT NULL AND rejection_reason IS NOT NULL) OR status <> 'REJECTED')
);

CREATE INDEX activation_challenges_grant_ix
    ON activation_challenges(grant_id, status, expires_at);
CREATE INDEX activation_challenges_device_ix
    ON activation_challenges(organization_id, device_id, status);

ALTER TABLE activations
    ADD COLUMN grant_id UUID REFERENCES activation_grants(id) ON DELETE RESTRICT,
    ADD COLUMN challenge_id UUID REFERENCES activation_challenges(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX activations_challenge_uq
    ON activations(challenge_id)
    WHERE challenge_id IS NOT NULL;

CREATE OR REPLACE FUNCTION yalla_protect_activation_grant_code_hash()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.code_sha256 IS DISTINCT FROM OLD.code_sha256
       OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
       OR NEW.subscription_id IS DISTINCT FROM OLD.subscription_id
       OR NEW.activation_kind IS DISTINCT FROM OLD.activation_kind THEN
        RAISE EXCEPTION 'Activation grant identity/code hash is immutable';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER activation_grants_immutable_identity_trg
BEFORE UPDATE ON activation_grants
FOR EACH ROW
EXECUTE FUNCTION yalla_protect_activation_grant_code_hash();

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (4, 'SEC.006', 'First-online-activation grants, challenges, proof-of-possession and signed-license delivery contract');

COMMIT;
