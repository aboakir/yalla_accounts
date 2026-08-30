BEGIN;

-- SEC.011 - explicit license lifecycle challenge/refresh protocol.
CREATE TABLE license_lifecycle_challenges (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    license_id UUID NOT NULL REFERENCES licenses(id) ON DELETE RESTRICT,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    action VARCHAR(16) NOT NULL,
    challenge_hash CHAR(64) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ISSUED',
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    lifecycle_event_id UUID,
    rejection_reason TEXT,
    CONSTRAINT lifecycle_challenges_action_ck
      CHECK (action IN ('VALIDATE','RENEW')),
    CONSTRAINT lifecycle_challenges_hash_ck
      CHECK (challenge_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT lifecycle_challenges_status_ck
      CHECK (status IN ('ISSUED','CONSUMED','REJECTED','EXPIRED')),
    CONSTRAINT lifecycle_challenges_expiry_ck
      CHECK (expires_at > issued_at),
    CONSTRAINT lifecycle_challenges_consumed_ck
      CHECK ((status = 'CONSUMED' AND consumed_at IS NOT NULL)
             OR status <> 'CONSUMED')
);

CREATE INDEX license_lifecycle_challenges_device_ix
    ON license_lifecycle_challenges(organization_id, device_id, status, expires_at);

ALTER TABLE renewals
    ADD COLUMN requested_by_device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    ADD COLUMN lifecycle_event_id UUID,
    ADD COLUMN applied_entitlement_revision INTEGER;

ALTER TABLE renewals
    ADD CONSTRAINT renewals_applied_revision_ck
    CHECK (applied_entitlement_revision IS NULL OR applied_entitlement_revision >= 1);

-- Server-authoritative operational state used when minting the next signed
-- license envelope. The client never self-declares ACTIVE/SUSPENDED/EXPIRED.
CREATE OR REPLACE FUNCTION yalla_effective_license_operational_state(
    p_subscription_id UUID,
    p_license_id UUID,
    p_device_id UUID,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_sub subscriptions%ROWTYPE;
    v_license licenses%ROWTYPE;
    v_device devices%ROWTYPE;
BEGIN
    SELECT * INTO v_sub FROM subscriptions WHERE id = p_subscription_id;
    IF NOT FOUND THEN RETURN 'REVOKED'; END IF;

    SELECT * INTO v_license FROM licenses
     WHERE id = p_license_id AND subscription_id = p_subscription_id;
    IF NOT FOUND THEN RETURN 'REVOKED'; END IF;

    SELECT * INTO v_device FROM devices
     WHERE id = p_device_id AND organization_id = v_sub.organization_id;
    IF NOT FOUND THEN RETURN 'REVOKED'; END IF;

    IF v_sub.status IN ('CANCELLED','SUSPENDED') THEN
        RETURN CASE WHEN v_sub.status = 'SUSPENDED' THEN 'SUSPENDED' ELSE 'CANCELLED' END;
    END IF;

    IF v_license.status IN ('REVOKED','REPLACED') OR
       v_device.status IN ('REVOKED','REPLACED') THEN
        RETURN 'REVOKED';
    END IF;

    IF v_device.status = 'SUSPENDED' THEN
        RETURN 'SUSPENDED';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM suspensions s
         WHERE s.organization_id = v_sub.organization_id
           AND s.status = 'ACTIVE'
           AND s.starts_at <= p_at
           AND (s.ends_at IS NULL OR s.ends_at > p_at)
           AND (
             s.scope = 'ORGANIZATION'
             OR (s.scope = 'SUBSCRIPTION' AND s.subscription_id = p_subscription_id)
             OR (s.scope = 'LICENSE' AND s.license_id = p_license_id)
             OR (s.scope = 'DEVICE' AND s.device_id = p_device_id)
           )
    ) THEN
        RETURN 'SUSPENDED';
    END IF;

    IF p_at >= v_sub.expires_at THEN
        IF v_sub.status = 'GRACE' AND v_sub.grace_until IS NOT NULL
           AND p_at < v_sub.grace_until THEN
            RETURN 'GRACE';
        END IF;
        RETURN 'EXPIRED';
    END IF;

    IF p_at >= v_license.expires_at OR v_license.status = 'EXPIRED' THEN
        RETURN 'EXPIRED';
    END IF;

    IF v_sub.status = 'GRACE' THEN
        IF v_sub.grace_until IS NOT NULL AND p_at < v_sub.grace_until THEN
            RETURN 'GRACE';
        END IF;
        RETURN 'EXPIRED';
    END IF;

    RETURN 'ACTIVE';
END;
$$;

-- Renewal mutates the subscription authorization source, never an already
-- signed payload. A fresh signed license must be minted after this function.
CREATE OR REPLACE FUNCTION yalla_apply_renewal(
    p_renewal_id UUID,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_renewal renewals%ROWTYPE;
    v_revision INTEGER;
BEGIN
    SELECT * INTO v_renewal
      FROM renewals
     WHERE id = p_renewal_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown renewal';
    END IF;
    IF v_renewal.status <> 'APPROVED' THEN
        RAISE EXCEPTION 'Renewal must be APPROVED before apply';
    END IF;

    UPDATE subscriptions
       SET expires_at = v_renewal.new_expires_at,
           status = 'ACTIVE',
           grace_until = NULL,
           entitlement_revision = entitlement_revision + 1,
           updated_at = p_at
     WHERE id = v_renewal.subscription_id
     RETURNING entitlement_revision INTO v_revision;

    UPDATE renewals
       SET status = 'APPLIED',
           applied_at = p_at,
           applied_entitlement_revision = v_revision
     WHERE id = p_renewal_id;

    RETURN v_revision;
END;
$$;

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (
    6,
    'SEC.011',
    'Expiry/read-only lifecycle, renewal application, suspension-aware signed-license refresh'
);

COMMIT;
