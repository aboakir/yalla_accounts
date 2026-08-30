-- Yalla Licensing Server
-- SEC.013 - Yalla Control Center
-- Canonical engine: PostgreSQL 16+
-- Server-side read/control-plane projection only.
-- This migration MUST NOT be executed against yalla_accounts.db.

BEGIN;

CREATE OR REPLACE VIEW yalla_cc_dashboard AS
SELECT
    (SELECT COUNT(*)::BIGINT FROM organizations) AS organizations_total,
    (SELECT COUNT(*)::BIGINT FROM organizations WHERE status = 'ACTIVE') AS organizations_active,
    (SELECT COUNT(*)::BIGINT FROM subscriptions WHERE status IN ('ACTIVE','TRIAL','GRACE')) AS subscriptions_live,
    (SELECT COUNT(*)::BIGINT FROM subscriptions WHERE status = 'SUSPENDED') AS subscriptions_suspended,
    (SELECT COUNT(*)::BIGINT FROM subscriptions WHERE status = 'EXPIRED') AS subscriptions_expired,
    (SELECT COUNT(*)::BIGINT FROM licenses WHERE status = 'ACTIVE') AS licenses_active,
    (SELECT COUNT(*)::BIGINT FROM devices WHERE status = 'ACTIVE') AS devices_active,
    (SELECT COUNT(*)::BIGINT FROM activations WHERE status = 'REQUESTED') AS activations_pending,
    (SELECT COUNT(*)::BIGINT FROM renewals WHERE status IN ('REQUESTED','APPROVED')) AS renewals_pending,
    (SELECT COUNT(*)::BIGINT FROM security_events WHERE resolved_at IS NULL AND severity IN ('HIGH','CRITICAL')) AS security_open_high,
    CURRENT_TIMESTAMP AS generated_at;

CREATE OR REPLACE VIEW yalla_cc_organizations AS
SELECT
    o.id,
    o.organization_code,
    o.display_name,
    o.legal_name,
    o.country_code,
    o.country_pack_code,
    o.status,
    o.identity_origin,
    o.created_at,
    o.updated_at,
    (SELECT COUNT(*)::INTEGER FROM devices d WHERE d.organization_id = o.id AND d.status IN ('ACTIVE','SUSPENDED')) AS device_slots_used,
    (SELECT MAX(s.expires_at) FROM subscriptions s WHERE s.organization_id = o.id AND s.status IN ('ACTIVE','TRIAL','GRACE','SUSPENDED')) AS current_expires_at
FROM organizations o;

CREATE OR REPLACE VIEW yalla_cc_subscriptions AS
SELECT
    s.id,
    s.organization_id,
    o.organization_code,
    COALESCE(o.display_name, o.legal_name, o.organization_code) AS organization_name,
    s.plan_id,
    p.code AS plan_code,
    p.name AS plan_name,
    s.status,
    s.starts_at,
    s.expires_at,
    s.grace_until,
    s.auto_renew,
    s.entitlement_revision,
    s.external_reference,
    s.created_at,
    s.updated_at
FROM subscriptions s
JOIN organizations o ON o.id = s.organization_id
JOIN plans p ON p.id = s.plan_id;

CREATE OR REPLACE VIEW yalla_cc_licenses AS
SELECT
    l.id,
    l.organization_id,
    o.organization_code,
    l.subscription_id,
    l.device_id,
    d.display_name AS device_name,
    l.license_number,
    l.status,
    l.issued_at,
    l.expires_at,
    l.revoked_at,
    l.entitlement_revision,
    l.signed_payload_hash,
    l.created_at,
    l.updated_at
FROM licenses l
JOIN organizations o ON o.id = l.organization_id
JOIN devices d ON d.id = l.device_id;

CREATE OR REPLACE VIEW yalla_cc_devices AS
SELECT
    d.id,
    d.organization_id,
    o.organization_code,
    d.installation_id,
    d.display_name,
    d.platform,
    d.platform_version,
    d.app_version,
    d.status,
    d.activated_at,
    d.last_seen_at,
    d.status_changed_at,
    d.status_reason,
    d.suspended_until,
    d.revoked_at,
    d.replaced_at,
    d.replaced_by_device_id,
    d.created_at,
    d.updated_at
FROM devices d
JOIN organizations o ON o.id = d.organization_id;

CREATE OR REPLACE VIEW yalla_cc_plans AS
SELECT
    p.id,
    p.code,
    p.name,
    p.status,
    p.billing_period_days,
    p.entitlement_revision,
    p.created_at,
    p.updated_at,
    (SELECT COUNT(*)::INTEGER FROM plan_entitlements pe WHERE pe.plan_id = p.id) AS entitlement_count,
    (SELECT COUNT(*)::INTEGER FROM subscriptions s WHERE s.plan_id = p.id AND s.status IN ('ACTIVE','TRIAL','GRACE','SUSPENDED')) AS live_subscription_count
FROM plans p;

CREATE OR REPLACE VIEW yalla_cc_features AS
SELECT
    f.id,
    f.code,
    f.name,
    f.description,
    f.value_type,
    f.min_numeric,
    f.max_numeric,
    f.is_system,
    f.status,
    f.created_at,
    f.updated_at
FROM features f;

CREATE OR REPLACE VIEW yalla_cc_entitlements AS
SELECT
    'PLAN'::TEXT AS scope,
    pe.id,
    pe.plan_id AS scope_id,
    p.code AS scope_code,
    pe.feature_id,
    f.code AS feature_code,
    f.name AS feature_name,
    pe.entitlement_value,
    'ACTIVE'::TEXT AS status,
    NULL::TEXT AS reason,
    pe.created_at,
    pe.updated_at
FROM plan_entitlements pe
JOIN plans p ON p.id = pe.plan_id
JOIN features f ON f.id = pe.feature_id
UNION ALL
SELECT
    'SUBSCRIPTION_OVERRIDE'::TEXT AS scope,
    seo.id,
    seo.subscription_id AS scope_id,
    s.id::TEXT AS scope_code,
    seo.feature_id,
    f.code AS feature_code,
    f.name AS feature_name,
    seo.entitlement_value,
    seo.status::TEXT AS status,
    seo.reason,
    seo.created_at,
    COALESCE(seo.revoked_at, seo.created_at) AS updated_at
FROM subscription_entitlement_overrides seo
JOIN subscriptions s ON s.id = seo.subscription_id
JOIN features f ON f.id = seo.feature_id;

CREATE OR REPLACE VIEW yalla_cc_activations AS
SELECT
    a.id,
    a.organization_id,
    o.organization_code,
    a.subscription_id,
    a.license_id,
    a.device_id,
    a.activation_kind,
    a.status,
    a.requested_at,
    a.decided_at,
    a.decision_reason,
    a.client_app_version,
    a.client_ip
FROM activations a
JOIN organizations o ON o.id = a.organization_id;

CREATE OR REPLACE VIEW yalla_cc_renewals AS
SELECT
    r.id,
    r.organization_id,
    o.organization_code,
    r.subscription_id,
    r.previous_expires_at,
    r.new_expires_at,
    r.status,
    r.external_reference,
    r.requested_at,
    r.applied_at,
    r.created_by_actor_id,
    r.requested_by_device_id,
    r.applied_entitlement_revision
FROM renewals r
JOIN organizations o ON o.id = r.organization_id;

CREATE OR REPLACE VIEW yalla_cc_overrides AS
SELECT
    ov.id,
    ov.organization_id,
    o.organization_code,
    ov.subscription_id,
    ov.license_id,
    ov.device_id,
    ov.override_type,
    ov.status,
    ov.before_state,
    ov.after_state,
    ov.reason,
    ov.starts_at,
    ov.expires_at,
    ov.created_by_actor_id,
    ov.created_at,
    ov.revoked_at
FROM overrides ov
JOIN organizations o ON o.id = ov.organization_id;

CREATE OR REPLACE VIEW yalla_cc_security_events AS
SELECT
    se.id,
    se.organization_id,
    o.organization_code,
    se.device_id,
    se.event_type,
    se.severity,
    se.event_data,
    se.detected_at,
    se.resolved_at,
    se.resolved_by_actor_id
FROM security_events se
LEFT JOIN organizations o ON o.id = se.organization_id;

CREATE OR REPLACE VIEW yalla_cc_audit_logs AS
SELECT
    al.id,
    al.organization_id,
    o.organization_code,
    al.actor_type,
    al.actor_id,
    al.action,
    al.entity_type,
    al.entity_id,
    al.before_state,
    al.after_state,
    al.reason,
    al.ip_address,
    al.metadata,
    al.occurred_at
FROM audit_logs al
LEFT JOIN organizations o ON o.id = al.organization_id;

CREATE OR REPLACE VIEW yalla_cc_admin_users AS
SELECT
    au.id,
    au.email,
    au.display_name,
    au.status,
    au.created_at,
    au.updated_at
FROM yalla_admin_users au;

COMMENT ON VIEW yalla_cc_admin_users IS
'SEC.013 safe admin projection. No password, secret, session token or recovery secret is exposed.';

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (8, 'SEC.013', 'Yalla Control Center canonical read models and independent admin-console surface');

COMMIT;
