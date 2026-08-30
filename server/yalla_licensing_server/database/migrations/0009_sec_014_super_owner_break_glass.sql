-- Yalla Licensing Server
-- SEC.014 - YALLA_SUPER_OWNER + Break Glass Overrides
-- Canonical engine: PostgreSQL 16+
-- Server-side authorization only. Never execute against yalla_accounts.db.

BEGIN;

CREATE TABLE yalla_admin_roles (
    role_code VARCHAR(64) PRIMARY KEY,
    display_name TEXT NOT NULL,
    is_system BOOLEAN NOT NULL DEFAULT TRUE,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_roles_code_ck CHECK (role_code ~ '^YALLA_[A-Z0-9_]+$'),
    CONSTRAINT yalla_admin_roles_status_ck CHECK (status IN ('ACTIVE','DISABLED'))
);

CREATE TABLE yalla_admin_permissions (
    permission_code VARCHAR(96) PRIMARY KEY,
    description TEXT NOT NULL,
    requires_break_glass BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_admin_permissions_code_ck CHECK (permission_code ~ '^[A-Z][A-Z0-9_.]+$'),
    CONSTRAINT yalla_admin_permissions_status_ck CHECK (status IN ('ACTIVE','DISABLED'))
);

CREATE TABLE yalla_admin_role_permissions (
    role_code VARCHAR(64) NOT NULL REFERENCES yalla_admin_roles(role_code) ON DELETE RESTRICT,
    permission_code VARCHAR(96) NOT NULL REFERENCES yalla_admin_permissions(permission_code) ON DELETE RESTRICT,
    PRIMARY KEY(role_code, permission_code)
);

CREATE TABLE yalla_admin_user_roles (
    admin_user_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    role_code VARCHAR(64) NOT NULL REFERENCES yalla_admin_roles(role_code) ON DELETE RESTRICT,
    granted_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    PRIMARY KEY(admin_user_id, role_code, granted_at),
    CONSTRAINT yalla_admin_user_roles_status_ck CHECK (status IN ('ACTIVE','REVOKED')),
    CONSTRAINT yalla_admin_user_roles_reason_ck CHECK (length(btrim(reason)) >= 8),
    CONSTRAINT yalla_admin_user_roles_revoked_ck CHECK ((status='REVOKED' AND revoked_at IS NOT NULL) OR status <> 'REVOKED')
);

CREATE TABLE yalla_break_glass_grants (
    id UUID PRIMARY KEY,
    admin_user_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    reason TEXT NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    source_ip INET,
    source_device TEXT,
    reauth_context_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT yalla_break_glass_status_ck CHECK (status IN ('ACTIVE','EXPIRED','REVOKED')),
    CONSTRAINT yalla_break_glass_reason_ck CHECK (length(btrim(reason)) >= 15),
    CONSTRAINT yalla_break_glass_window_ck CHECK (
        expires_at >= starts_at + INTERVAL '5 minutes' AND
        expires_at <= starts_at + INTERVAL '60 minutes'
    ),
    CONSTRAINT yalla_break_glass_revoked_ck CHECK ((status='REVOKED' AND revoked_at IS NOT NULL) OR status <> 'REVOKED')
);

CREATE UNIQUE INDEX yalla_admin_user_roles_active_ix
    ON yalla_admin_user_roles(admin_user_id, role_code) WHERE status='ACTIVE';
CREATE INDEX yalla_break_glass_actor_ix
    ON yalla_break_glass_grants(admin_user_id, organization_id, status, expires_at);

CREATE TABLE yalla_privileged_action_catalog (
    action_code VARCHAR(96) PRIMARY KEY,
    permission_code VARCHAR(96) NOT NULL REFERENCES yalla_admin_permissions(permission_code) ON DELETE RESTRICT,
    target_scope VARCHAR(24) NOT NULL,
    requires_break_glass BOOLEAN NOT NULL DEFAULT FALSE,
    requires_reason BOOLEAN NOT NULL DEFAULT TRUE,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT yalla_priv_action_scope_ck CHECK (target_scope IN ('ADMIN','ORGANIZATION','SUBSCRIPTION','LICENSE','DEVICE')),
    CONSTRAINT yalla_priv_action_status_ck CHECK (status IN ('ACTIVE','DISABLED'))
);

CREATE TABLE yalla_privileged_action_requests (
    id UUID PRIMARY KEY,
    idempotency_key VARCHAR(128) NOT NULL UNIQUE,
    actor_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    action_code VARCHAR(96) NOT NULL REFERENCES yalla_privileged_action_catalog(action_code) ON DELETE RESTRICT,
    organization_id UUID REFERENCES organizations(id) ON DELETE RESTRICT,
    target_entity_type VARCHAR(64),
    target_entity_id UUID,
    status VARCHAR(16) NOT NULL DEFAULT 'REQUESTED',
    before_state JSONB,
    requested_state JSONB NOT NULL DEFAULT '{}'::jsonb,
    applied_state JSONB,
    reason TEXT NOT NULL,
    expires_at TIMESTAMPTZ,
    break_glass_grant_id UUID REFERENCES yalla_break_glass_grants(id) ON DELETE RESTRICT,
    source_ip INET,
    source_device TEXT,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    applied_at TIMESTAMPTZ,
    failure_reason TEXT,
    CONSTRAINT yalla_priv_action_request_status_ck CHECK (status IN ('REQUESTED','APPLIED','REJECTED','FAILED','CANCELLED')),
    CONSTRAINT yalla_priv_action_request_reason_ck CHECK (length(btrim(reason)) >= 8),
    CONSTRAINT yalla_priv_action_request_applied_ck CHECK ((status='APPLIED' AND applied_at IS NOT NULL) OR status <> 'APPLIED')
);

CREATE INDEX yalla_privileged_action_requests_actor_ix
    ON yalla_privileged_action_requests(actor_id, requested_at DESC);
CREATE INDEX yalla_privileged_action_requests_org_ix
    ON yalla_privileged_action_requests(organization_id, requested_at DESC);

CREATE TABLE yalla_license_issuance_requests (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    previous_license_id UUID REFERENCES licenses(id) ON DELETE RESTRICT,
    request_kind VARCHAR(24) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'REQUESTED',
    reason TEXT NOT NULL,
    requested_by_actor_id UUID NOT NULL REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    privileged_action_request_id UUID NOT NULL REFERENCES yalla_privileged_action_requests(id) ON DELETE RESTRICT,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    signed_at TIMESTAMPTZ,
    issued_license_id UUID REFERENCES licenses(id) ON DELETE RESTRICT,
    failure_reason TEXT,
    CONSTRAINT yalla_license_issuance_kind_ck CHECK (request_kind IN ('NEW','REFRESH','REPLACEMENT')),
    CONSTRAINT yalla_license_issuance_status_ck CHECK (status IN ('REQUESTED','AUTHORIZED','SIGNED','FAILED','CANCELLED')),
    CONSTRAINT yalla_license_issuance_signed_ck CHECK ((status='SIGNED' AND signed_at IS NOT NULL AND issued_license_id IS NOT NULL) OR status <> 'SIGNED')
);

ALTER TABLE overrides
    ADD COLUMN break_glass_grant_id UUID REFERENCES yalla_break_glass_grants(id) ON DELETE RESTRICT,
    ADD COLUMN source_ip INET,
    ADD COLUMN source_device TEXT;

INSERT INTO yalla_admin_roles(role_code, display_name, is_system)
VALUES
    ('YALLA_SUPER_OWNER','Yalla Super Owner',TRUE),
    ('YALLA_BREAK_GLASS','Yalla Break Glass Operator',TRUE);

INSERT INTO yalla_admin_permissions(permission_code, description, requires_break_glass)
VALUES
    ('ORGANIZATION.CREATE','Create a customer organization',FALSE),
    ('ORGANIZATION.UPDATE','Update organization identity and commercial metadata',FALSE),
    ('ORGANIZATION.ACTIVATE','Activate an organization',FALSE),
    ('ORGANIZATION.SUSPEND','Suspend an organization',FALSE),
    ('ORGANIZATION.RESUME','Resume a suspended organization',FALSE),
    ('ORGANIZATION.COUNTRY_PACK_SET','Change organization country pack',FALSE),
    ('SUBSCRIPTION.CANCEL','Cancel a subscription',FALSE),
    ('SUBSCRIPTION.RESTORE','Restore a subscription through normal policy',FALSE),
    ('SUBSCRIPTION.RENEW','Renew a subscription through normal policy',FALSE),
    ('SUBSCRIPTION.CHANGE_START_DATE','Change subscription start date',FALSE),
    ('SUBSCRIPTION.CHANGE_EXPIRY_DATE','Change subscription expiry date',FALSE),
    ('SUBSCRIPTION.CHANGE_PLAN','Change subscription plan',FALSE),
    ('SUBSCRIPTION.TRIAL_CREATE','Create a trial subscription',FALSE),
    ('SUBSCRIPTION.TRIAL_CONVERT_TO_PAID','Convert trial to paid subscription',FALSE),
    ('SUBSCRIPTION.GRACE_EXTEND','Extend a commercial grace period',FALSE),
    ('ENTITLEMENT.MAX_USERS_SET','Set licensed user seat limit',FALSE),
    ('ENTITLEMENT.MAX_DEVICES_SET','Set licensed device limit',FALSE),
    ('ENTITLEMENT.FEATURE_ENABLE','Enable a feature entitlement',FALSE),
    ('ENTITLEMENT.FEATURE_DISABLE','Disable a feature entitlement',FALSE),
    ('ACTIVATION.FORCE','Force activation in an emergency context',TRUE),
    ('REACTIVATION.FORCE','Force reactivation in an emergency context',TRUE),
    ('RENEWAL.FORCE','Force renewal in an emergency context',TRUE),
    ('DEVICE.REPLACE_FORCE','Force device replacement',TRUE),
    ('DEVICE.REVOKE_FORCE','Force device revocation',TRUE),
    ('SEAT.OVERRIDE_FORCE','Temporarily override licensed user seats',TRUE),
    ('FEATURE.OVERRIDE_FORCE','Temporarily override a feature',TRUE),
    ('EXPIRY.OVERRIDE_FORCE','Temporarily override expiry',TRUE),
    ('SUBSCRIPTION.RESTORE_FORCE','Force subscription restore',TRUE),
    ('LICENSE.REFRESH_FORCE','Force a fresh signed-license refresh',TRUE),
    ('LICENSE.ISSUE','Request issuance of a new signed license',TRUE),
    ('LICENSE.REVOKE','Revoke a license',TRUE),
    ('DEVICES.READ_ALL','Read all customer devices',FALSE),
    ('DEVICE.LAST_SEEN_READ','Read device last-seen information',FALSE),
    ('DEVICE.APP_VERSION_READ','Read device application version',FALSE),
    ('ACTIVATION.HISTORY_READ','Read activation history',FALSE),
    ('SECURITY.EVENTS_READ','Read security events',FALSE),
    ('ADMIN.USERS_MANAGE','Manage Yalla administrative users and role assignments',FALSE),
    ('BREAK_GLASS.OPEN','Open a short-lived break-glass context',FALSE),
    ('BREAK_GLASS.REVOKE','Revoke an active break-glass context',FALSE);

INSERT INTO yalla_admin_role_permissions(role_code, permission_code)
SELECT 'YALLA_SUPER_OWNER', permission_code FROM yalla_admin_permissions;

INSERT INTO yalla_admin_role_permissions(role_code, permission_code)
SELECT 'YALLA_BREAK_GLASS', permission_code
  FROM yalla_admin_permissions
 WHERE permission_code IN ('BREAK_GLASS.OPEN','BREAK_GLASS.REVOKE');

INSERT INTO yalla_privileged_action_catalog(action_code, permission_code, target_scope, requires_break_glass)
VALUES
    ('ORGANIZATION.CREATE','ORGANIZATION.CREATE','ORGANIZATION',FALSE),
    ('ORGANIZATION.UPDATE','ORGANIZATION.UPDATE','ORGANIZATION',FALSE),
    ('ORGANIZATION.ACTIVATE','ORGANIZATION.ACTIVATE','ORGANIZATION',FALSE),
    ('ORGANIZATION.SUSPEND','ORGANIZATION.SUSPEND','ORGANIZATION',FALSE),
    ('ORGANIZATION.RESUME','ORGANIZATION.RESUME','ORGANIZATION',FALSE),
    ('ORGANIZATION.COUNTRY_PACK_SET','ORGANIZATION.COUNTRY_PACK_SET','ORGANIZATION',FALSE),
    ('SUBSCRIPTION.CANCEL','SUBSCRIPTION.CANCEL','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.RESTORE','SUBSCRIPTION.RESTORE','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.RENEW','SUBSCRIPTION.RENEW','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.CHANGE_START_DATE','SUBSCRIPTION.CHANGE_START_DATE','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.CHANGE_EXPIRY_DATE','SUBSCRIPTION.CHANGE_EXPIRY_DATE','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.CHANGE_PLAN','SUBSCRIPTION.CHANGE_PLAN','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.TRIAL_CREATE','SUBSCRIPTION.TRIAL_CREATE','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.TRIAL_CONVERT_TO_PAID','SUBSCRIPTION.TRIAL_CONVERT_TO_PAID','SUBSCRIPTION',FALSE),
    ('SUBSCRIPTION.GRACE_EXTEND','SUBSCRIPTION.GRACE_EXTEND','SUBSCRIPTION',FALSE),
    ('ENTITLEMENT.MAX_USERS_SET','ENTITLEMENT.MAX_USERS_SET','SUBSCRIPTION',FALSE),
    ('ENTITLEMENT.MAX_DEVICES_SET','ENTITLEMENT.MAX_DEVICES_SET','SUBSCRIPTION',FALSE),
    ('ENTITLEMENT.FEATURE_ENABLE','ENTITLEMENT.FEATURE_ENABLE','SUBSCRIPTION',FALSE),
    ('ENTITLEMENT.FEATURE_DISABLE','ENTITLEMENT.FEATURE_DISABLE','SUBSCRIPTION',FALSE),
    ('ACTIVATION.FORCE','ACTIVATION.FORCE','ORGANIZATION',TRUE),
    ('REACTIVATION.FORCE','REACTIVATION.FORCE','ORGANIZATION',TRUE),
    ('RENEWAL.FORCE','RENEWAL.FORCE','SUBSCRIPTION',TRUE),
    ('DEVICE.REPLACE_FORCE','DEVICE.REPLACE_FORCE','DEVICE',TRUE),
    ('DEVICE.REVOKE_FORCE','DEVICE.REVOKE_FORCE','DEVICE',TRUE),
    ('SEAT.OVERRIDE_FORCE','SEAT.OVERRIDE_FORCE','SUBSCRIPTION',TRUE),
    ('FEATURE.OVERRIDE_FORCE','FEATURE.OVERRIDE_FORCE','SUBSCRIPTION',TRUE),
    ('EXPIRY.OVERRIDE_FORCE','EXPIRY.OVERRIDE_FORCE','SUBSCRIPTION',TRUE),
    ('SUBSCRIPTION.RESTORE_FORCE','SUBSCRIPTION.RESTORE_FORCE','SUBSCRIPTION',TRUE),
    ('LICENSE.REFRESH_FORCE','LICENSE.REFRESH_FORCE','LICENSE',TRUE),
    ('LICENSE.ISSUE','LICENSE.ISSUE','LICENSE',TRUE),
    ('LICENSE.REVOKE','LICENSE.REVOKE','LICENSE',TRUE),
    ('BREAK_GLASS.TEMP_SUBSCRIPTION_OPEN','EXPIRY.OVERRIDE_FORCE','SUBSCRIPTION',TRUE),
    ('BREAK_GLASS.FREE_DAYS','EXPIRY.OVERRIDE_FORCE','SUBSCRIPTION',TRUE),
    ('BREAK_GLASS.TEMP_DEVICE_LIMIT','ENTITLEMENT.MAX_DEVICES_SET','SUBSCRIPTION',TRUE),
    ('BREAK_GLASS.TEMP_USER_LIMIT','SEAT.OVERRIDE_FORCE','SUBSCRIPTION',TRUE),
    ('BREAK_GLASS.CLIENT_REACTIVATE','REACTIVATION.FORCE','ORGANIZATION',TRUE),
    ('BREAK_GLASS.TEMP_FEATURE','FEATURE.OVERRIDE_FORCE','SUBSCRIPTION',TRUE),
    ('ADMIN.USERS_MANAGE','ADMIN.USERS_MANAGE','ADMIN',FALSE);

CREATE OR REPLACE VIEW yalla_cc_admin_effective_permissions AS
SELECT DISTINCT
    au.id AS admin_user_id,
    au.email,
    aur.role_code,
    arp.permission_code,
    ap.requires_break_glass
FROM yalla_admin_users au
JOIN yalla_admin_user_roles aur ON aur.admin_user_id=au.id AND aur.status='ACTIVE'
JOIN yalla_admin_roles ar ON ar.role_code=aur.role_code AND ar.status='ACTIVE'
JOIN yalla_admin_role_permissions arp ON arp.role_code=ar.role_code
JOIN yalla_admin_permissions ap ON ap.permission_code=arp.permission_code AND ap.status='ACTIVE'
WHERE au.status='ACTIVE';

CREATE OR REPLACE FUNCTION yalla_admin_has_permission(
    p_actor_id UUID,
    p_permission_code VARCHAR
) RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM yalla_cc_admin_effective_permissions ep
         WHERE ep.admin_user_id=p_actor_id
           AND ep.permission_code=p_permission_code
    );
$$;

CREATE OR REPLACE FUNCTION yalla_authorize_admin_action(
    p_actor_id UUID,
    p_action_code VARCHAR,
    p_organization_id UUID,
    p_reason TEXT,
    p_break_glass_grant_id UUID DEFAULT NULL,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS VOID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_permission VARCHAR(96);
    v_requires_break_glass BOOLEAN;
    v_user_status VARCHAR(16);
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) < 8 THEN
        RAISE EXCEPTION 'Privileged action requires a meaningful reason';
    END IF;

    SELECT status INTO v_user_status FROM yalla_admin_users WHERE id=p_actor_id;
    IF v_user_status IS DISTINCT FROM 'ACTIVE' THEN
        RAISE EXCEPTION 'Yalla admin actor is not ACTIVE';
    END IF;

    SELECT permission_code, requires_break_glass
      INTO v_permission, v_requires_break_glass
      FROM yalla_privileged_action_catalog
     WHERE action_code=p_action_code AND status='ACTIVE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown or disabled privileged action %', p_action_code;
    END IF;

    IF NOT yalla_admin_has_permission(p_actor_id, v_permission) THEN
        RAISE EXCEPTION 'Permission denied: %', v_permission;
    END IF;

    IF v_requires_break_glass THEN
        IF p_organization_id IS NULL OR p_break_glass_grant_id IS NULL THEN
            RAISE EXCEPTION 'Break-glass action requires organization and active grant';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM yalla_break_glass_grants bg
             WHERE bg.id=p_break_glass_grant_id
               AND bg.admin_user_id=p_actor_id
               AND bg.organization_id=p_organization_id
               AND bg.status='ACTIVE'
               AND bg.starts_at <= p_at
               AND bg.expires_at > p_at
        ) THEN
            RAISE EXCEPTION 'Break-glass grant is missing, expired, revoked or out of scope';
        END IF;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_open_break_glass(
    p_grant_id UUID,
    p_actor_id UUID,
    p_organization_id UUID,
    p_reason TEXT,
    p_expires_at TIMESTAMPTZ,
    p_source_ip INET DEFAULT NULL,
    p_source_device TEXT DEFAULT NULL,
    p_reauth_context_id UUID DEFAULT NULL,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS UUID
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT yalla_admin_has_permission(p_actor_id, 'BREAK_GLASS.OPEN') THEN
        RAISE EXCEPTION 'Permission denied: BREAK_GLASS.OPEN';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 15 THEN
        RAISE EXCEPTION 'Break-glass reason must contain at least 15 characters';
    END IF;
    IF p_expires_at < p_at + INTERVAL '5 minutes' OR p_expires_at > p_at + INTERVAL '60 minutes' THEN
        RAISE EXCEPTION 'Break-glass lifetime must be between 5 and 60 minutes';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM organizations WHERE id=p_organization_id) THEN
        RAISE EXCEPTION 'Unknown organization';
    END IF;

    INSERT INTO yalla_break_glass_grants(
        id, admin_user_id, organization_id, reason, starts_at, expires_at,
        source_ip, source_device, reauth_context_id
    ) VALUES (
        p_grant_id, p_actor_id, p_organization_id, p_reason, p_at, p_expires_at,
        p_source_ip, p_source_device, p_reauth_context_id
    );

    INSERT INTO audit_logs(
        organization_id, actor_type, actor_id, action, entity_type, entity_id,
        after_state, reason, ip_address, metadata, occurred_at
    ) VALUES (
        p_organization_id, 'YALLA_ADMIN', p_actor_id, 'BREAK_GLASS.OPEN',
        'YALLA_BREAK_GLASS_GRANT', p_grant_id,
        jsonb_build_object('expires_at',p_expires_at,'source_device',p_source_device),
        p_reason, p_source_ip,
        jsonb_build_object('reauth_context_id',p_reauth_context_id), p_at
    );

    RETURN p_grant_id;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_revoke_break_glass(
    p_grant_id UUID,
    p_actor_id UUID,
    p_reason TEXT,
    p_source_ip INET DEFAULT NULL,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_org UUID;
BEGIN
    IF NOT yalla_admin_has_permission(p_actor_id, 'BREAK_GLASS.REVOKE') THEN
        RAISE EXCEPTION 'Permission denied: BREAK_GLASS.REVOKE';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 8 THEN
        RAISE EXCEPTION 'Revocation requires a reason';
    END IF;

    UPDATE yalla_break_glass_grants
       SET status='REVOKED', revoked_at=p_at
     WHERE id=p_grant_id AND status='ACTIVE'
     RETURNING organization_id INTO v_org;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active break-glass grant not found';
    END IF;

    INSERT INTO audit_logs(
        organization_id, actor_type, actor_id, action, entity_type, entity_id,
        after_state, reason, ip_address, occurred_at
    ) VALUES (
        v_org, 'YALLA_ADMIN', p_actor_id, 'BREAK_GLASS.REVOKE',
        'YALLA_BREAK_GLASS_GRANT', p_grant_id,
        jsonb_build_object('status','REVOKED'), p_reason, p_source_ip, p_at
    );
END;
$$;

-- One-time ownership binding. It never creates credentials and never embeds a
-- universal password. The target admin identity must already exist and be ACTIVE.
CREATE OR REPLACE FUNCTION yalla_bootstrap_super_owner(
    p_actor_id UUID,
    p_reason TEXT,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) < 15 THEN
        RAISE EXCEPTION 'Super-owner bootstrap requires a meaningful reason';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM yalla_admin_users WHERE id=p_actor_id AND status='ACTIVE') THEN
        RAISE EXCEPTION 'Super-owner target must be an ACTIVE Yalla admin identity';
    END IF;
    IF EXISTS (
        SELECT 1 FROM yalla_admin_user_roles
         WHERE role_code='YALLA_SUPER_OWNER' AND status='ACTIVE'
    ) THEN
        RAISE EXCEPTION 'YALLA_SUPER_OWNER has already been bootstrapped';
    END IF;

    INSERT INTO yalla_admin_user_roles(
        admin_user_id, role_code, granted_by_actor_id, reason, granted_at, status
    ) VALUES (
        p_actor_id, 'YALLA_SUPER_OWNER', NULL, p_reason, p_at, 'ACTIVE'
    );

    INSERT INTO audit_logs(
        actor_type, actor_id, action, entity_type, entity_id, after_state, reason, occurred_at
    ) VALUES (
        'SYSTEM', p_actor_id, 'YALLA_SUPER_OWNER.BOOTSTRAP', 'YALLA_ADMIN_USER', p_actor_id,
        jsonb_build_object('role','YALLA_SUPER_OWNER'), p_reason, p_at
    );
END;
$$;

CREATE OR REPLACE FUNCTION yalla_protect_last_super_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_removing_active_owner BOOLEAN := FALSE;
BEGIN
    IF OLD.role_code='YALLA_SUPER_OWNER' AND OLD.status='ACTIVE' THEN
        IF TG_OP='DELETE' THEN
            v_removing_active_owner := TRUE;
        ELSIF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM 'ACTIVE' THEN
            v_removing_active_owner := TRUE;
        END IF;
    END IF;

    IF v_removing_active_owner AND
       (SELECT COUNT(*) FROM yalla_admin_user_roles
         WHERE role_code='YALLA_SUPER_OWNER' AND status='ACTIVE') <= 1 THEN
        RAISE EXCEPTION 'Cannot remove or revoke the last active YALLA_SUPER_OWNER';
    END IF;

    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER yalla_admin_user_roles_last_owner_trg
BEFORE UPDATE OR DELETE ON yalla_admin_user_roles
FOR EACH ROW EXECUTE FUNCTION yalla_protect_last_super_owner();

CREATE OR REPLACE FUNCTION yalla_protect_privileged_audit_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Audit events are append-only and cannot be deleted';
END;
$$;

CREATE TRIGGER yalla_audit_logs_no_delete_trg
BEFORE DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION yalla_protect_privileged_audit_delete();

CREATE OR REPLACE VIEW yalla_cc_break_glass AS
SELECT
    bg.id,
    bg.admin_user_id,
    au.email AS admin_email,
    bg.organization_id,
    o.organization_code,
    bg.status,
    bg.reason,
    bg.starts_at,
    bg.expires_at,
    bg.revoked_at,
    bg.source_ip,
    bg.source_device,
    bg.created_at
FROM yalla_break_glass_grants bg
JOIN yalla_admin_users au ON au.id=bg.admin_user_id
JOIN organizations o ON o.id=bg.organization_id;

CREATE OR REPLACE VIEW yalla_cc_privileged_actions AS
SELECT
    par.id,
    par.actor_id,
    au.email AS actor_email,
    par.action_code,
    par.organization_id,
    o.organization_code,
    par.target_entity_type,
    par.target_entity_id,
    par.status,
    par.before_state,
    par.requested_state,
    par.applied_state,
    par.reason,
    par.expires_at,
    par.break_glass_grant_id,
    par.source_ip,
    par.source_device,
    par.requested_at,
    par.applied_at,
    par.failure_reason
FROM yalla_privileged_action_requests par
JOIN yalla_admin_users au ON au.id=par.actor_id
LEFT JOIN organizations o ON o.id=par.organization_id;

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (
    9,
    'SEC.014',
    'YALLA_SUPER_OWNER RBAC, scoped break-glass authorization and privileged action control plane'
);

COMMIT;
