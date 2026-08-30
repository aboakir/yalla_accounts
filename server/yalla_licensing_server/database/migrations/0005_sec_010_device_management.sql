-- Yalla Licensing Server
-- SEC.010 - Device Management
-- Canonical engine: PostgreSQL 16+
-- Server-authoritative device lifecycle. Client SQLite is never authoritative.

BEGIN;

ALTER TABLE devices
    ADD COLUMN status_changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN status_reason TEXT,
    ADD COLUMN suspended_until TIMESTAMPTZ,
    ADD COLUMN revoked_at TIMESTAMPTZ,
    ADD COLUMN replaced_at TIMESTAMPTZ;

UPDATE devices
   SET status_reason = COALESCE(status_reason, 'Legacy device state migrated by SEC.010'),
       revoked_at = CASE WHEN status = 'REVOKED' THEN COALESCE(revoked_at, updated_at, CURRENT_TIMESTAMP) ELSE revoked_at END,
       replaced_at = CASE WHEN status = 'REPLACED' THEN COALESCE(replaced_at, updated_at, CURRENT_TIMESTAMP) ELSE replaced_at END,
       status_changed_at = COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
 WHERE status IN ('SUSPENDED','REVOKED','REPLACED');

ALTER TABLE devices
    ADD CONSTRAINT devices_suspension_window_ck CHECK (
        (status = 'SUSPENDED' AND status_reason IS NOT NULL) OR status <> 'SUSPENDED'
    ),
    ADD CONSTRAINT devices_revoked_metadata_ck CHECK (
        (status = 'REVOKED' AND revoked_at IS NOT NULL AND status_reason IS NOT NULL) OR status <> 'REVOKED'
    ),
    ADD CONSTRAINT devices_replaced_metadata_ck CHECK (
        (status = 'REPLACED' AND replaced_at IS NOT NULL AND status_reason IS NOT NULL) OR status <> 'REPLACED'
    ),
    ADD CONSTRAINT devices_suspend_until_ck CHECK (
        suspended_until IS NULL OR suspended_until > created_at
    );

CREATE TABLE device_management_actions (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    action_type VARCHAR(24) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'REQUESTED',
    target_device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    replacement_device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    request_idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    reason TEXT NOT NULL,
    requested_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    decided_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decided_at TIMESTAMPTZ,
    applied_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT device_actions_type_ck CHECK (
        action_type IN ('ADD_DEVICE','REACTIVATE','SUSPEND','RESUME','REVOKE','REPLACE')
    ),
    CONSTRAINT device_actions_status_ck CHECK (
        status IN ('REQUESTED','APPROVED','APPLIED','REJECTED','CANCELLED')
    ),
    CONSTRAINT device_actions_target_ck CHECK (
        (action_type = 'ADD_DEVICE' AND target_device_id IS NULL) OR
        (action_type <> 'ADD_DEVICE' AND target_device_id IS NOT NULL)
    ),
    CONSTRAINT device_actions_replacement_ck CHECK (
        (action_type = 'REPLACE') OR replacement_device_id IS NULL
    ),
    CONSTRAINT device_actions_decision_ck CHECK (
        (status = 'REQUESTED' AND decided_at IS NULL) OR
        (status <> 'REQUESTED' AND decided_at IS NOT NULL)
    ),
    CONSTRAINT device_actions_applied_ck CHECK (
        (status = 'APPLIED' AND applied_at IS NOT NULL) OR status <> 'APPLIED'
    )
);

CREATE INDEX device_management_actions_org_ix
    ON device_management_actions(organization_id, requested_at DESC);
CREATE INDEX device_management_actions_target_ix
    ON device_management_actions(target_device_id, status);

ALTER TABLE activation_grants
    DROP CONSTRAINT activation_grants_kind_ck;
ALTER TABLE activation_grants
    ADD CONSTRAINT activation_grants_kind_ck CHECK (
        activation_kind IN ('FIRST','ADD_DEVICE','REACTIVATION','DEVICE_REPLACEMENT','LICENSE_REFRESH')
    );

ALTER TABLE activation_grants
    ADD COLUMN device_management_action_id UUID REFERENCES device_management_actions(id) ON DELETE RESTRICT,
    ADD COLUMN target_device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    ADD COLUMN replacement_for_device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    ADD COLUMN management_protocol_version SMALLINT NOT NULL DEFAULT 1;

ALTER TABLE activation_grants
    ADD CONSTRAINT activation_grants_management_protocol_ck CHECK (management_protocol_version IN (1,2));

ALTER TABLE activation_grants
    ADD CONSTRAINT activation_grants_management_binding_ck CHECK (
        management_protocol_version = 1 OR (
            management_protocol_version = 2 AND (
                (activation_kind = 'FIRST' AND device_management_action_id IS NULL AND target_device_id IS NULL AND replacement_for_device_id IS NULL) OR
                (activation_kind = 'ADD_DEVICE' AND device_management_action_id IS NOT NULL AND target_device_id IS NULL AND replacement_for_device_id IS NULL) OR
                (activation_kind = 'REACTIVATION' AND device_management_action_id IS NOT NULL AND target_device_id IS NOT NULL AND replacement_for_device_id IS NULL) OR
                (activation_kind = 'DEVICE_REPLACEMENT' AND device_management_action_id IS NOT NULL AND target_device_id IS NULL AND replacement_for_device_id IS NOT NULL) OR
                (activation_kind = 'LICENSE_REFRESH')
            )
        )
    );

CREATE OR REPLACE FUNCTION yalla_device_slots_used(p_organization_id UUID)
RETURNS INTEGER
LANGUAGE SQL
STABLE
AS $$
    SELECT COUNT(*)::INTEGER
      FROM devices d
     WHERE d.organization_id = p_organization_id
       AND d.status IN ('ACTIVE','SUSPENDED');
$$;

CREATE OR REPLACE FUNCTION yalla_max_devices(p_subscription_id UUID, p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_value JSONB;
    v_limit INTEGER;
BEGIN
    SELECT entitlement_value
      INTO v_value
      FROM yalla_effective_entitlements(p_subscription_id, p_at)
     WHERE feature_code = 'MAX_DEVICES'
     LIMIT 1;

    IF v_value IS NULL OR jsonb_typeof(v_value) <> 'number' THEN
        RAISE EXCEPTION 'MAX_DEVICES entitlement is missing or invalid';
    END IF;
    v_limit := (v_value #>> '{}')::INTEGER;
    IF v_limit < 1 THEN
        RAISE EXCEPTION 'MAX_DEVICES entitlement must be >= 1';
    END IF;
    RETURN v_limit;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_assert_device_capacity(
    p_subscription_id UUID,
    p_slots_to_add INTEGER DEFAULT 1,
    p_exclude_device_id UUID DEFAULT NULL,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS VOID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_org UUID;
    v_used INTEGER;
    v_limit INTEGER;
BEGIN
    IF p_slots_to_add < 0 THEN
        RAISE EXCEPTION 'p_slots_to_add cannot be negative';
    END IF;
    SELECT organization_id INTO v_org FROM subscriptions WHERE id = p_subscription_id;
    IF v_org IS NULL THEN
        RAISE EXCEPTION 'Unknown subscription';
    END IF;
    v_limit := yalla_max_devices(p_subscription_id, p_at);
    SELECT COUNT(*)::INTEGER
      INTO v_used
      FROM devices d
     WHERE d.organization_id = v_org
       AND d.status IN ('ACTIVE','SUSPENDED')
       AND (p_exclude_device_id IS NULL OR d.id <> p_exclude_device_id);
    IF v_used + p_slots_to_add > v_limit THEN
        RAISE EXCEPTION 'MAX_DEVICES exceeded: used %, requested %, limit %', v_used, p_slots_to_add, v_limit;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_transition_device(
    p_device_id UUID,
    p_action VARCHAR,
    p_reason TEXT,
    p_replacement_device_id UUID DEFAULT NULL,
    p_suspend_until TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_device devices%ROWTYPE;
    v_replacement devices%ROWTYPE;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'Device status transition requires a reason';
    END IF;
    SELECT * INTO v_device FROM devices WHERE id = p_device_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown device'; END IF;

    IF v_device.status IN ('REVOKED','REPLACED') THEN
        RAISE EXCEPTION 'Terminal device status % cannot be reactivated', v_device.status;
    END IF;

    IF p_action = 'SUSPEND' THEN
        IF v_device.status <> 'ACTIVE' THEN RAISE EXCEPTION 'Only ACTIVE device can be suspended'; END IF;
        UPDATE devices SET status='SUSPENDED', status_reason=p_reason,
            suspended_until=p_suspend_until, status_changed_at=CURRENT_TIMESTAMP,
            updated_at=CURRENT_TIMESTAMP WHERE id=p_device_id;
    ELSIF p_action IN ('RESUME','REACTIVATE') THEN
        IF v_device.status <> 'SUSPENDED' THEN RAISE EXCEPTION 'Only SUSPENDED device can be resumed/reactivated'; END IF;
        UPDATE devices SET status='ACTIVE', status_reason=p_reason,
            suspended_until=NULL, status_changed_at=CURRENT_TIMESTAMP,
            updated_at=CURRENT_TIMESTAMP WHERE id=p_device_id;
    ELSIF p_action = 'REVOKE' THEN
        UPDATE devices SET status='REVOKED', status_reason=p_reason,
            revoked_at=CURRENT_TIMESTAMP, suspended_until=NULL,
            status_changed_at=CURRENT_TIMESTAMP, updated_at=CURRENT_TIMESTAMP
         WHERE id=p_device_id;
        UPDATE licenses SET status='REVOKED', revoked_at=CURRENT_TIMESTAMP,
            updated_at=CURRENT_TIMESTAMP
         WHERE device_id=p_device_id AND status='ACTIVE';
    ELSIF p_action = 'REPLACE' THEN
        IF p_replacement_device_id IS NULL OR p_replacement_device_id = p_device_id THEN
            RAISE EXCEPTION 'Replacement device is required';
        END IF;
        SELECT * INTO v_replacement FROM devices WHERE id=p_replacement_device_id FOR UPDATE;
        IF NOT FOUND OR v_replacement.organization_id <> v_device.organization_id OR v_replacement.status <> 'ACTIVE' THEN
            RAISE EXCEPTION 'Replacement device must be ACTIVE in the same organization';
        END IF;
        UPDATE devices SET status='REPLACED', status_reason=p_reason,
            replaced_at=CURRENT_TIMESTAMP, replaced_by_device_id=p_replacement_device_id,
            suspended_until=NULL, status_changed_at=CURRENT_TIMESTAMP,
            updated_at=CURRENT_TIMESTAMP WHERE id=p_device_id;
        UPDATE licenses SET status='REVOKED', revoked_at=CURRENT_TIMESTAMP,
            updated_at=CURRENT_TIMESTAMP
         WHERE device_id=p_device_id AND status='ACTIVE';
    ELSE
        RAISE EXCEPTION 'Unsupported device transition action %', p_action;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_protect_terminal_device_state()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status IN ('REVOKED','REPLACED') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'Terminal device status % is immutable', OLD.status;
    END IF;
    IF NEW.replaced_by_device_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM devices d
             WHERE d.id = NEW.replaced_by_device_id
               AND d.organization_id = NEW.organization_id
        ) THEN
            RAISE EXCEPTION 'Replacement device must belong to the same organization';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER devices_terminal_state_guard_trg
BEFORE UPDATE ON devices
FOR EACH ROW
EXECUTE FUNCTION yalla_protect_terminal_device_state();

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (5, 'SEC.010', 'Server-authoritative device lifecycle, MAX_DEVICES capacity, add/reactivate/revoke/replace management contracts');

COMMIT;
