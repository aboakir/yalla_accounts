-- Yalla Licensing Server
-- SEC.004 - Cryptographic License Authority
-- Canonical engine: PostgreSQL 16+
-- Server-side only. No private signing key bytes are stored in this schema.

BEGIN;

CREATE TABLE license_signing_keys (
    id UUID PRIMARY KEY,
    key_id VARCHAR(64) NOT NULL UNIQUE,
    algorithm VARCHAR(24) NOT NULL DEFAULT 'ED25519',
    public_key_base64url TEXT NOT NULL,
    public_key_sha256 CHAR(64) NOT NULL UNIQUE,
    key_provider VARCHAR(24) NOT NULL,
    key_provider_reference TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'STAGED',
    not_before TIMESTAMPTZ NOT NULL,
    not_after TIMESTAMPTZ,
    activated_at TIMESTAMPTZ,
    retired_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    revocation_reason TEXT,
    created_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT license_signing_keys_key_id_ck CHECK (key_id ~ '^YALLA-LIC-[A-Z0-9][A-Z0-9._-]{5,55}$'),
    CONSTRAINT license_signing_keys_algorithm_ck CHECK (algorithm = 'ED25519'),
    CONSTRAINT license_signing_keys_public_key_ck CHECK (public_key_base64url ~ '^[A-Za-z0-9_-]{43}$'),
    CONSTRAINT license_signing_keys_public_hash_ck CHECK (public_key_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT license_signing_keys_provider_ck CHECK (key_provider IN ('KMS','HSM','SECRET_STORE')),
    CONSTRAINT license_signing_keys_provider_ref_ck CHECK (length(btrim(key_provider_reference)) >= 3),
    CONSTRAINT license_signing_keys_status_ck CHECK (status IN ('STAGED','ACTIVE','RETIRED','REVOKED')),
    CONSTRAINT license_signing_keys_dates_ck CHECK (not_after IS NULL OR not_after > not_before),
    CONSTRAINT license_signing_keys_activation_ck CHECK ((status = 'ACTIVE' AND activated_at IS NOT NULL) OR status <> 'ACTIVE'),
    CONSTRAINT license_signing_keys_retirement_ck CHECK ((status = 'RETIRED' AND retired_at IS NOT NULL) OR status <> 'RETIRED'),
    CONSTRAINT license_signing_keys_revocation_ck CHECK ((status = 'REVOKED' AND revoked_at IS NOT NULL AND revocation_reason IS NOT NULL) OR status <> 'REVOKED')
);

CREATE UNIQUE INDEX license_signing_keys_one_active_signer_uq
    ON license_signing_keys ((1))
    WHERE status = 'ACTIVE';

CREATE INDEX license_signing_keys_status_time_ix
    ON license_signing_keys(status, not_before, not_after);

ALTER TABLE licenses
    ADD COLUMN signing_key_id UUID REFERENCES license_signing_keys(id) ON DELETE RESTRICT,
    ADD COLUMN payload_schema_version SMALLINT,
    ADD COLUMN signed_payload JSONB,
    ADD COLUMN signature_algorithm VARCHAR(24),
    ADD COLUMN signature_base64url TEXT,
    ADD COLUMN signed_at TIMESTAMPTZ;

ALTER TABLE licenses
    ADD CONSTRAINT licenses_payload_schema_ck CHECK (payload_schema_version IS NULL OR payload_schema_version >= 1),
    ADD CONSTRAINT licenses_signature_algorithm_ck CHECK (signature_algorithm IS NULL OR signature_algorithm = 'ED25519'),
    ADD CONSTRAINT licenses_signature_format_ck CHECK (signature_base64url IS NULL OR signature_base64url ~ '^[A-Za-z0-9_-]{86}$'),
    ADD CONSTRAINT licenses_crypto_state_ck CHECK (
        status <> 'ACTIVE' OR (
            signing_key_id IS NOT NULL
            AND payload_schema_version IS NOT NULL
            AND signed_payload IS NOT NULL
            AND signed_payload_hash IS NOT NULL
            AND signature_algorithm = 'ED25519'
            AND signature_base64url IS NOT NULL
            AND signed_at IS NOT NULL
        )
    ) NOT VALID;

CREATE OR REPLACE FUNCTION yalla_protect_signing_key_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status <> 'STAGED' AND (
        NEW.key_id IS DISTINCT FROM OLD.key_id
        OR NEW.algorithm IS DISTINCT FROM OLD.algorithm
        OR NEW.public_key_base64url IS DISTINCT FROM OLD.public_key_base64url
        OR NEW.public_key_sha256 IS DISTINCT FROM OLD.public_key_sha256
        OR NEW.key_provider IS DISTINCT FROM OLD.key_provider
        OR NEW.key_provider_reference IS DISTINCT FROM OLD.key_provider_reference
    ) THEN
        RAISE EXCEPTION 'Activated signing key identity/provider metadata is immutable';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF OLD.status = 'STAGED' AND NEW.status NOT IN ('ACTIVE','REVOKED') THEN
            RAISE EXCEPTION 'Invalid signing key transition: % -> %', OLD.status, NEW.status;
        ELSIF OLD.status = 'ACTIVE' AND NEW.status NOT IN ('RETIRED','REVOKED') THEN
            RAISE EXCEPTION 'Invalid signing key transition: % -> %', OLD.status, NEW.status;
        ELSIF OLD.status = 'RETIRED' AND NEW.status <> 'REVOKED' THEN
            RAISE EXCEPTION 'Invalid signing key transition: % -> %', OLD.status, NEW.status;
        ELSIF OLD.status = 'REVOKED' THEN
            RAISE EXCEPTION 'Revoked signing keys cannot change lifecycle state';
        END IF;
    END IF;

    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER license_signing_keys_lifecycle_trg
BEFORE UPDATE ON license_signing_keys
FOR EACH ROW
EXECUTE FUNCTION yalla_protect_signing_key_lifecycle();

CREATE OR REPLACE FUNCTION yalla_current_license_signing_key(
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS UUID
LANGUAGE SQL
STABLE
AS $$
    SELECT id
      FROM license_signing_keys
     WHERE status = 'ACTIVE'
       AND not_before <= p_at
       AND (not_after IS NULL OR p_at < not_after)
     ORDER BY activated_at DESC, created_at DESC, id DESC
     LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION yalla_assert_active_license_crypto_state()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_key license_signing_keys%ROWTYPE;
BEGIN
    IF NEW.status <> 'ACTIVE' THEN
        RETURN NEW;
    END IF;

    IF NEW.signing_key_id IS NULL
       OR NEW.payload_schema_version IS NULL
       OR NEW.signed_payload IS NULL
       OR NEW.signed_payload_hash IS NULL
       OR NEW.signature_algorithm IS NULL
       OR NEW.signature_base64url IS NULL
       OR NEW.signed_at IS NULL THEN
        RAISE EXCEPTION 'ACTIVE license requires complete cryptographic envelope metadata';
    END IF;

    SELECT * INTO v_key
      FROM license_signing_keys
     WHERE id = NEW.signing_key_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown signing key: %', NEW.signing_key_id;
    END IF;

    IF v_key.algorithm <> 'ED25519' OR NEW.signature_algorithm <> 'ED25519' THEN
        RAISE EXCEPTION 'License/signing-key algorithm mismatch';
    END IF;

    IF v_key.status NOT IN ('ACTIVE','RETIRED') THEN
        RAISE EXCEPTION 'Signing key must be ACTIVE at issuance or RETIRED for historical verification';
    END IF;

    IF NEW.signed_at < v_key.not_before
       OR (v_key.not_after IS NOT NULL AND NEW.signed_at >= v_key.not_after)
       OR (v_key.activated_at IS NOT NULL AND NEW.signed_at < v_key.activated_at)
       OR (v_key.retired_at IS NOT NULL AND NEW.signed_at >= v_key.retired_at)
       OR (v_key.revoked_at IS NOT NULL AND NEW.signed_at >= v_key.revoked_at) THEN
        RAISE EXCEPTION 'License signed outside signing key validity window';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER licenses_crypto_state_trg
BEFORE INSERT OR UPDATE OF status, signing_key_id, payload_schema_version, signed_payload,
    signed_payload_hash, signature_algorithm, signature_base64url, signed_at
ON licenses
FOR EACH ROW
EXECUTE FUNCTION yalla_assert_active_license_crypto_state();

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (3, 'SEC.004', 'Cryptographic license authority and signing-key lifecycle');

COMMIT;
