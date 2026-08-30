-- Yalla Licensing Server
-- SEC.002 - Core licensing server data model
-- Canonical engine: PostgreSQL 16+
-- This migration is server-side only. It must never be executed against yalla_accounts.db.

BEGIN;

CREATE TABLE yalla_schema_migrations (
    version INTEGER PRIMARY KEY,
    stage VARCHAR(32) NOT NULL,
    description TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE organizations (
    id UUID PRIMARY KEY,
    organization_code VARCHAR(32) NOT NULL UNIQUE,
    display_name TEXT,
    legal_name TEXT,
    country_code CHAR(2),
    country_pack_code VARCHAR(32),
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    identity_origin VARCHAR(24) NOT NULL DEFAULT 'CLIENT_BOOTSTRAP',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT organizations_code_ck CHECK (organization_code ~ '^ORG-[A-Z0-9]{6,24}$'),
    CONSTRAINT organizations_country_ck CHECK (country_code IS NULL OR country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT organizations_status_ck CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','CANCELLED','ARCHIVED')),
    CONSTRAINT organizations_origin_ck CHECK (identity_origin IN ('CLIENT_BOOTSTRAP','SERVER_CREATED','MIGRATED'))
);

CREATE TABLE yalla_admin_users (
    id UUID PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'INVITED',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_users_status_ck CHECK (status IN ('INVITED','ACTIVE','DISABLED'))
);

CREATE TABLE plans (
    id UUID PRIMARY KEY,
    code VARCHAR(48) NOT NULL UNIQUE,
    name TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
    billing_period_days INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT plans_status_ck CHECK (status IN ('DRAFT','ACTIVE','RETIRED')),
    CONSTRAINT plans_billing_period_ck CHECK (billing_period_days > 0)
);

CREATE TABLE subscriptions (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    starts_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    grace_until TIMESTAMPTZ,
    auto_renew BOOLEAN NOT NULL DEFAULT FALSE,
    external_reference TEXT,
    supersedes_subscription_id UUID REFERENCES subscriptions(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT subscriptions_status_ck CHECK (status IN ('TRIAL','PENDING','ACTIVE','GRACE','SUSPENDED','EXPIRED','CANCELLED')),
    CONSTRAINT subscriptions_dates_ck CHECK (expires_at > starts_at),
    CONSTRAINT subscriptions_grace_ck CHECK (grace_until IS NULL OR grace_until >= expires_at),
    CONSTRAINT subscriptions_supersedes_ck CHECK (supersedes_subscription_id IS NULL OR supersedes_subscription_id <> id)
);

CREATE TABLE devices (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    installation_id UUID NOT NULL UNIQUE,
    public_key TEXT NOT NULL UNIQUE,
    public_key_algorithm VARCHAR(24) NOT NULL DEFAULT 'ED25519',
    fingerprint_hash CHAR(64),
    display_name TEXT,
    platform VARCHAR(32),
    platform_version VARCHAR(64),
    app_version VARCHAR(64),
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    activated_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ,
    replaced_by_device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT devices_key_algorithm_ck CHECK (public_key_algorithm IN ('ED25519','ECDSA_P256','RSA_PSS_SHA256')),
    CONSTRAINT devices_fingerprint_ck CHECK (fingerprint_hash IS NULL OR fingerprint_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT devices_status_ck CHECK (status IN ('ACTIVE','REVOKED','REPLACED','SUSPENDED')),
    CONSTRAINT devices_replacement_ck CHECK (replaced_by_device_id IS NULL OR replaced_by_device_id <> id)
);

CREATE TABLE licenses (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    license_number VARCHAR(64) NOT NULL UNIQUE,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    issued_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    replaced_by_license_id UUID REFERENCES licenses(id) ON DELETE RESTRICT,
    entitlement_revision BIGINT NOT NULL DEFAULT 0,
    signed_payload_hash CHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT licenses_status_ck CHECK (status IN ('PENDING','ACTIVE','REVOKED','REPLACED','EXPIRED')),
    CONSTRAINT licenses_entitlement_revision_ck CHECK (entitlement_revision >= 0),
    CONSTRAINT licenses_payload_hash_ck CHECK (signed_payload_hash IS NULL OR signed_payload_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT licenses_replacement_ck CHECK (replaced_by_license_id IS NULL OR replaced_by_license_id <> id)
);

CREATE UNIQUE INDEX licenses_one_active_per_subscription_device_uq
    ON licenses(subscription_id, device_id)
    WHERE status = 'ACTIVE';

CREATE TABLE activations (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    license_id UUID REFERENCES licenses(id) ON DELETE RESTRICT,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    activation_kind VARCHAR(24) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'REQUESTED',
    request_idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decided_at TIMESTAMPTZ,
    decision_reason TEXT,
    client_app_version VARCHAR(64),
    client_ip INET,
    request_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT activations_kind_ck CHECK (activation_kind IN ('FIRST','REACTIVATION','DEVICE_REPLACEMENT','LICENSE_REFRESH')),
    CONSTRAINT activations_status_ck CHECK (status IN ('REQUESTED','APPROVED','REJECTED')),
    CONSTRAINT activations_decision_ck CHECK ((status = 'REQUESTED' AND decided_at IS NULL) OR (status IN ('APPROVED','REJECTED') AND decided_at IS NOT NULL))
);

CREATE TABLE renewals (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    previous_expires_at TIMESTAMPTZ NOT NULL,
    new_expires_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'REQUESTED',
    external_reference TEXT,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    applied_at TIMESTAMPTZ,
    created_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT renewals_status_ck CHECK (status IN ('REQUESTED','APPROVED','APPLIED','REJECTED','CANCELLED')),
    CONSTRAINT renewals_dates_ck CHECK (new_expires_at > previous_expires_at),
    CONSTRAINT renewals_applied_ck CHECK ((status = 'APPLIED' AND applied_at IS NOT NULL) OR status <> 'APPLIED')
);

CREATE TABLE suspensions (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE RESTRICT,
    license_id UUID REFERENCES licenses(id) ON DELETE RESTRICT,
    device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    scope VARCHAR(20) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    reason TEXT NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ends_at TIMESTAMPTZ,
    lifted_at TIMESTAMPTZ,
    created_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT suspensions_scope_ck CHECK (scope IN ('ORGANIZATION','SUBSCRIPTION','LICENSE','DEVICE')),
    CONSTRAINT suspensions_status_ck CHECK (status IN ('ACTIVE','LIFTED','EXPIRED')),
    CONSTRAINT suspensions_dates_ck CHECK (ends_at IS NULL OR ends_at > starts_at),
    CONSTRAINT suspensions_target_ck CHECK (
        (scope = 'ORGANIZATION' AND subscription_id IS NULL AND license_id IS NULL AND device_id IS NULL) OR
        (scope = 'SUBSCRIPTION' AND subscription_id IS NOT NULL AND license_id IS NULL AND device_id IS NULL) OR
        (scope = 'LICENSE' AND license_id IS NOT NULL AND device_id IS NULL) OR
        (scope = 'DEVICE' AND device_id IS NOT NULL AND license_id IS NULL)
    )
);

CREATE TABLE overrides (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE RESTRICT,
    license_id UUID REFERENCES licenses(id) ON DELETE RESTRICT,
    device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    override_type VARCHAR(40) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    before_state JSONB NOT NULL,
    after_state JSONB NOT NULL,
    reason TEXT NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ,
    created_by_actor_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT overrides_type_ck CHECK (override_type IN ('EXPIRY','PLAN','SEATS','DEVICES','FEATURE','GRACE','ACTIVATION','REACTIVATION','DEVICE_REPLACEMENT','SUBSCRIPTION_RESTORE')),
    CONSTRAINT overrides_status_ck CHECK (status IN ('ACTIVE','EXPIRED','REVOKED')),
    CONSTRAINT overrides_dates_ck CHECK (expires_at IS NULL OR expires_at > starts_at)
);

CREATE TABLE audit_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id UUID REFERENCES organizations(id) ON DELETE RESTRICT,
    actor_type VARCHAR(24) NOT NULL,
    actor_id UUID,
    action VARCHAR(96) NOT NULL,
    entity_type VARCHAR(64) NOT NULL,
    entity_id UUID,
    before_state JSONB,
    after_state JSONB,
    reason TEXT,
    ip_address INET,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT audit_logs_actor_type_ck CHECK (actor_type IN ('SYSTEM','YALLA_ADMIN','CLIENT_OWNER','SERVICE'))
);

CREATE TABLE security_events (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id UUID REFERENCES organizations(id) ON DELETE RESTRICT,
    device_id UUID REFERENCES devices(id) ON DELETE RESTRICT,
    event_type VARCHAR(96) NOT NULL,
    severity VARCHAR(16) NOT NULL,
    event_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ,
    resolved_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    CONSTRAINT security_events_severity_ck CHECK (severity IN ('INFO','WARNING','HIGH','CRITICAL'))
);

CREATE INDEX subscriptions_org_status_ix ON subscriptions(organization_id, status);
CREATE INDEX subscriptions_expiry_ix ON subscriptions(expires_at);
CREATE INDEX devices_org_status_ix ON devices(organization_id, status);
CREATE INDEX devices_last_seen_ix ON devices(last_seen_at);
CREATE INDEX licenses_org_status_ix ON licenses(organization_id, status);
CREATE INDEX licenses_expiry_ix ON licenses(expires_at);
CREATE INDEX activations_org_requested_ix ON activations(organization_id, requested_at DESC);
CREATE INDEX renewals_subscription_ix ON renewals(subscription_id, requested_at DESC);
CREATE INDEX suspensions_org_status_ix ON suspensions(organization_id, status);
CREATE INDEX overrides_org_status_ix ON overrides(organization_id, status);
CREATE INDEX audit_logs_org_time_ix ON audit_logs(organization_id, occurred_at DESC);
CREATE INDEX security_events_org_time_ix ON security_events(organization_id, detected_at DESC);

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (1, 'SEC.002', 'Core licensing server data model');

COMMIT;
