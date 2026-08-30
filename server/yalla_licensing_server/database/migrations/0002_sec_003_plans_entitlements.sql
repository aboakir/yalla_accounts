-- Yalla Licensing Server
-- SEC.003 - Plans and entitlements
-- Canonical engine: PostgreSQL 16+
-- Server-side only. Never execute against yalla_accounts.db.

BEGIN;

ALTER TABLE plans
    ADD COLUMN entitlement_revision BIGINT NOT NULL DEFAULT 1;

ALTER TABLE plans
    ADD CONSTRAINT plans_entitlement_revision_ck CHECK (entitlement_revision >= 1);

ALTER TABLE subscriptions
    ADD COLUMN entitlement_revision BIGINT NOT NULL DEFAULT 1;

ALTER TABLE subscriptions
    ADD CONSTRAINT subscriptions_entitlement_revision_ck CHECK (entitlement_revision >= 1);

CREATE TABLE features (
    id UUID PRIMARY KEY,
    code VARCHAR(64) NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    value_type VARCHAR(16) NOT NULL,
    min_numeric NUMERIC,
    max_numeric NUMERIC,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT features_code_ck CHECK (code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
    CONSTRAINT features_value_type_ck CHECK (value_type IN ('BOOLEAN','INTEGER','DECIMAL','TEXT','JSON')),
    CONSTRAINT features_status_ck CHECK (status IN ('ACTIVE','RETIRED')),
    CONSTRAINT features_numeric_bounds_ck CHECK (
        (min_numeric IS NULL OR max_numeric IS NULL OR min_numeric <= max_numeric)
        AND ((value_type IN ('INTEGER','DECIMAL')) OR (min_numeric IS NULL AND max_numeric IS NULL))
    )
);

CREATE TABLE plan_entitlements (
    id UUID PRIMARY KEY,
    plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
    feature_id UUID NOT NULL REFERENCES features(id) ON DELETE RESTRICT,
    entitlement_value JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT plan_entitlements_plan_feature_uq UNIQUE (plan_id, feature_id)
);

CREATE TABLE subscription_entitlement_overrides (
    id UUID PRIMARY KEY,
    subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE RESTRICT,
    feature_id UUID NOT NULL REFERENCES features(id) ON DELETE RESTRICT,
    entitlement_value JSONB NOT NULL,
    priority SMALLINT NOT NULL DEFAULT 100,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    reason TEXT NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ,
    created_by_actor_id UUID REFERENCES yalla_admin_users(id) ON DELETE RESTRICT,
    supersedes_override_id UUID REFERENCES subscription_entitlement_overrides(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,
    CONSTRAINT subscription_entitlement_overrides_priority_ck CHECK (priority BETWEEN 0 AND 1000),
    CONSTRAINT subscription_entitlement_overrides_status_ck CHECK (status IN ('ACTIVE','REVOKED','EXPIRED')),
    CONSTRAINT subscription_entitlement_overrides_dates_ck CHECK (expires_at IS NULL OR expires_at > starts_at),
    CONSTRAINT subscription_entitlement_overrides_supersedes_ck CHECK (supersedes_override_id IS NULL OR supersedes_override_id <> id),
    CONSTRAINT subscription_entitlement_overrides_revoked_ck CHECK ((status = 'REVOKED' AND revoked_at IS NOT NULL) OR status <> 'REVOKED')
);

CREATE INDEX plan_entitlements_plan_ix
    ON plan_entitlements(plan_id, feature_id);

CREATE INDEX subscription_entitlement_overrides_lookup_ix
    ON subscription_entitlement_overrides(subscription_id, feature_id, status, priority DESC, starts_at DESC);

CREATE INDEX subscription_entitlement_overrides_expiry_ix
    ON subscription_entitlement_overrides(expires_at)
    WHERE status = 'ACTIVE' AND expires_at IS NOT NULL;

CREATE OR REPLACE FUNCTION yalla_entitlement_value_is_valid(
    p_value_type VARCHAR,
    p_value JSONB
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE p_value_type
        WHEN 'BOOLEAN' THEN jsonb_typeof(p_value) = 'boolean'
        WHEN 'INTEGER' THEN jsonb_typeof(p_value) = 'number' AND (p_value #>> '{}') ~ '^-?[0-9]+$'
        WHEN 'DECIMAL' THEN jsonb_typeof(p_value) = 'number'
        WHEN 'TEXT' THEN jsonb_typeof(p_value) = 'string'
        WHEN 'JSON' THEN jsonb_typeof(p_value) IN ('object','array')
        ELSE FALSE
    END;
$$;

CREATE OR REPLACE FUNCTION yalla_assert_entitlement_value_matches_feature()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_value_type VARCHAR(16);
    v_min NUMERIC;
    v_max NUMERIC;
    v_numeric NUMERIC;
BEGIN
    SELECT value_type, min_numeric, max_numeric
      INTO v_value_type, v_min, v_max
      FROM features
     WHERE id = NEW.feature_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown feature_id: %', NEW.feature_id;
    END IF;

    IF NOT yalla_entitlement_value_is_valid(v_value_type, NEW.entitlement_value) THEN
        RAISE EXCEPTION 'Entitlement value does not match feature type % for feature %', v_value_type, NEW.feature_id;
    END IF;

    IF v_value_type IN ('INTEGER','DECIMAL') THEN
        v_numeric := (NEW.entitlement_value #>> '{}')::NUMERIC;
        IF v_min IS NOT NULL AND v_numeric < v_min THEN
            RAISE EXCEPTION 'Entitlement value % is below minimum % for feature %', v_numeric, v_min, NEW.feature_id;
        END IF;
        IF v_max IS NOT NULL AND v_numeric > v_max THEN
            RAISE EXCEPTION 'Entitlement value % is above maximum % for feature %', v_numeric, v_max, NEW.feature_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER plan_entitlements_validate_value_trg
BEFORE INSERT OR UPDATE ON plan_entitlements
FOR EACH ROW
EXECUTE FUNCTION yalla_assert_entitlement_value_matches_feature();

CREATE TRIGGER subscription_entitlement_overrides_validate_value_trg
BEFORE INSERT OR UPDATE ON subscription_entitlement_overrides
FOR EACH ROW
EXECUTE FUNCTION yalla_assert_entitlement_value_matches_feature();

CREATE OR REPLACE FUNCTION yalla_bump_plan_entitlement_revision()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_plan_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_plan_id := OLD.plan_id;
    ELSE
        v_plan_id := NEW.plan_id;
    END IF;

    UPDATE plans
       SET entitlement_revision = entitlement_revision + 1,
           updated_at = CURRENT_TIMESTAMP
     WHERE id = v_plan_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER plan_entitlements_revision_trg
AFTER INSERT OR UPDATE OR DELETE ON plan_entitlements
FOR EACH ROW
EXECUTE FUNCTION yalla_bump_plan_entitlement_revision();

CREATE OR REPLACE FUNCTION yalla_bump_subscription_entitlement_revision()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_subscription_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_subscription_id := OLD.subscription_id;
    ELSE
        v_subscription_id := NEW.subscription_id;
    END IF;

    UPDATE subscriptions
       SET entitlement_revision = entitlement_revision + 1,
           updated_at = CURRENT_TIMESTAMP
     WHERE id = v_subscription_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER subscription_entitlement_overrides_revision_trg
AFTER INSERT OR UPDATE OR DELETE ON subscription_entitlement_overrides
FOR EACH ROW
EXECUTE FUNCTION yalla_bump_subscription_entitlement_revision();

CREATE OR REPLACE FUNCTION yalla_bump_entitlement_revisions_for_feature_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.value_type IS DISTINCT FROM OLD.value_type
       OR NEW.min_numeric IS DISTINCT FROM OLD.min_numeric
       OR NEW.max_numeric IS DISTINCT FROM OLD.max_numeric
       OR NEW.status IS DISTINCT FROM OLD.status THEN

        UPDATE plans p
           SET entitlement_revision = entitlement_revision + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE EXISTS (
             SELECT 1
               FROM plan_entitlements pe
              WHERE pe.plan_id = p.id
                AND pe.feature_id = NEW.id
         );

        UPDATE subscriptions s
           SET entitlement_revision = entitlement_revision + 1,
               updated_at = CURRENT_TIMESTAMP
         WHERE EXISTS (
             SELECT 1
               FROM subscription_entitlement_overrides seo
              WHERE seo.subscription_id = s.id
                AND seo.feature_id = NEW.id
         );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER features_revision_propagation_trg
AFTER UPDATE ON features
FOR EACH ROW
EXECUTE FUNCTION yalla_bump_entitlement_revisions_for_feature_change();

CREATE OR REPLACE FUNCTION yalla_effective_entitlements(
    p_subscription_id UUID,
    p_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (
    feature_id UUID,
    feature_code VARCHAR(64),
    value_type VARCHAR(16),
    entitlement_value JSONB,
    entitlement_source VARCHAR(32),
    source_id UUID,
    plan_revision BIGINT,
    subscription_revision BIGINT
)
LANGUAGE SQL
STABLE
AS $$
    WITH subscription_context AS (
        SELECT s.id AS subscription_id,
               s.plan_id,
               s.entitlement_revision AS subscription_revision,
               p.entitlement_revision AS plan_revision
          FROM subscriptions s
          JOIN plans p ON p.id = s.plan_id
         WHERE s.id = p_subscription_id
    ),
    candidate_features AS (
        SELECT pe.feature_id
          FROM plan_entitlements pe
          JOIN subscription_context sc ON sc.plan_id = pe.plan_id
        UNION
        SELECT seo.feature_id
          FROM subscription_entitlement_overrides seo
         WHERE seo.subscription_id = p_subscription_id
           AND seo.status = 'ACTIVE'
           AND seo.starts_at <= p_at
           AND (seo.expires_at IS NULL OR seo.expires_at > p_at)
    )
    SELECT f.id,
           f.code,
           f.value_type,
           COALESCE(active_override.entitlement_value, pe.entitlement_value) AS entitlement_value,
           CASE
               WHEN active_override.id IS NOT NULL THEN 'SUBSCRIPTION_OVERRIDE'::VARCHAR(32)
               ELSE 'PLAN'::VARCHAR(32)
           END AS entitlement_source,
           COALESCE(active_override.id, pe.id) AS source_id,
           sc.plan_revision,
           sc.subscription_revision
      FROM subscription_context sc
      JOIN candidate_features cf ON TRUE
      JOIN features f ON f.id = cf.feature_id
      LEFT JOIN plan_entitlements pe
        ON pe.plan_id = sc.plan_id
       AND pe.feature_id = f.id
      LEFT JOIN LATERAL (
          SELECT seo.id, seo.entitlement_value
            FROM subscription_entitlement_overrides seo
           WHERE seo.subscription_id = sc.subscription_id
             AND seo.feature_id = f.id
             AND seo.status = 'ACTIVE'
             AND seo.starts_at <= p_at
             AND (seo.expires_at IS NULL OR seo.expires_at > p_at)
           ORDER BY seo.priority DESC,
                    seo.starts_at DESC,
                    seo.created_at DESC,
                    seo.id DESC
           LIMIT 1
      ) active_override ON TRUE
     WHERE f.status = 'ACTIVE'
       AND (active_override.id IS NOT NULL OR pe.id IS NOT NULL)
     ORDER BY f.code;
$$;

-- Stable system feature identifiers. These are capability definitions only;
-- SEC.003 deliberately creates no commercial plan names, prices, or plan rows.
INSERT INTO features(id, code, name, description, value_type, min_numeric, max_numeric, is_system, status)
VALUES
    ('00000000-0000-4000-8000-000000000101', 'MAX_USERS', 'Maximum users', 'Maximum licensed users for the organization.', 'INTEGER', 1, NULL, TRUE, 'ACTIVE'),
    ('00000000-0000-4000-8000-000000000102', 'MAX_DEVICES', 'Maximum devices', 'Maximum activated devices for the organization.', 'INTEGER', 1, NULL, TRUE, 'ACTIVE'),
    ('00000000-0000-4000-8000-000000000103', 'ACCOUNTING_CORE', 'Accounting core', 'Core accounting operations.', 'BOOLEAN', NULL, NULL, TRUE, 'ACTIVE'),
    ('00000000-0000-4000-8000-000000000104', 'WORKSHOP_REPAIRS', 'Workshop repairs', 'Repair-order and workshop workflow capability.', 'BOOLEAN', NULL, NULL, TRUE, 'ACTIVE'),
    ('00000000-0000-4000-8000-000000000105', 'INVENTORY', 'Inventory', 'Inventory and stock capability.', 'BOOLEAN', NULL, NULL, TRUE, 'ACTIVE'),
    ('00000000-0000-4000-8000-000000000106', 'INSURANCE', 'Insurance', 'Insurance workflow capability.', 'BOOLEAN', NULL, NULL, TRUE, 'ACTIVE'),
    ('00000000-0000-4000-8000-000000000107', 'REPORT_EXPORT', 'Report export', 'Export reports and data.', 'BOOLEAN', NULL, NULL, TRUE, 'ACTIVE'),
    ('00000000-0000-4000-8000-000000000108', 'BACKUP_RESTORE', 'Backup and restore', 'Create and restore application backups.', 'BOOLEAN', NULL, NULL, TRUE, 'ACTIVE');

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (2, 'SEC.003', 'Plans, feature catalog, typed entitlements, subscription overrides and evaluation rules');

COMMIT;
