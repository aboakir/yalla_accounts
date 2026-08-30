BEGIN;

-- SEC.012 - server-authoritative periodic validation policy.
ALTER TABLE subscriptions
    ADD COLUMN validation_interval_days INTEGER NOT NULL DEFAULT 30,
    ADD COLUMN validation_grace_days INTEGER NOT NULL DEFAULT 7;

ALTER TABLE subscriptions
    ADD CONSTRAINT subscriptions_validation_interval_ck
      CHECK (validation_interval_days BETWEEN 1 AND 365),
    ADD CONSTRAINT subscriptions_validation_grace_ck
      CHECK (validation_grace_days BETWEEN 0 AND 30);

ALTER TABLE devices
    ADD COLUMN last_validated_at TIMESTAMPTZ;

ALTER TABLE licenses
    ADD COLUMN last_validated_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION yalla_license_validation_window(
    p_subscription_id UUID,
    p_server_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS TABLE(validation_required_at TIMESTAMPTZ, validation_grace_until TIMESTAMPTZ)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_interval INTEGER;
    v_grace INTEGER;
BEGIN
    SELECT validation_interval_days, validation_grace_days
      INTO v_interval, v_grace
      FROM subscriptions
     WHERE id = p_subscription_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown subscription';
    END IF;

    validation_required_at := p_server_time + make_interval(days => v_interval);
    validation_grace_until := validation_required_at + make_interval(days => v_grace);
    RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION yalla_record_periodic_validation(
    p_license_id UUID,
    p_device_id UUID,
    p_server_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE licenses
       SET last_validated_at = p_server_time,
           updated_at = p_server_time
     WHERE id = p_license_id
       AND device_id = p_device_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown license/device binding';
    END IF;

    UPDATE devices
       SET last_validated_at = p_server_time,
           last_seen_at = p_server_time,
           updated_at = p_server_time
     WHERE id = p_device_id;
END;
$$;

INSERT INTO yalla_schema_migrations(version, stage, description)
VALUES (
    7,
    'SEC.012',
    'Periodic online validation policy, signed validation windows and offline grace tracking'
);

COMMIT;
