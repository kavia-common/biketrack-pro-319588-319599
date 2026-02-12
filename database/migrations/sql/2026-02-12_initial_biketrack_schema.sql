-- BikeTrack Pro - Initial schema
-- Notes:
-- - Idempotent: safe to run multiple times.
-- - Uses uuid-ossp extension for UUID generation.
-- - updated_at is maintained by a generic trigger for relevant tables.

BEGIN;

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- updated_at trigger function
CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- users
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email text NOT NULL UNIQUE,
  password_hash text,
  full_name text,
  role text NOT NULL DEFAULT 'user',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_updated_at') THEN
    CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;
END$$;

-- bikes
CREATE TABLE IF NOT EXISTS bikes (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  make text,
  model text,
  color text,
  serial_number text,
  device_identifier text UNIQUE,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bikes_owner_user_id ON bikes(owner_user_id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_bikes_updated_at') THEN
    CREATE TRIGGER trg_bikes_updated_at
    BEFORE UPDATE ON bikes
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;
END$$;

-- device_sessions
CREATE TABLE IF NOT EXISTS device_sessions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  bike_id uuid NOT NULL REFERENCES bikes(id) ON DELETE CASCADE,
  device_identifier text,
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  status text NOT NULL DEFAULT 'active',
  last_heartbeat_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_device_sessions_bike_started
  ON device_sessions(bike_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_device_sessions_status
  ON device_sessions(status);

-- gps_location_points
CREATE TABLE IF NOT EXISTS gps_location_points (
  id bigserial PRIMARY KEY,
  bike_id uuid NOT NULL REFERENCES bikes(id) ON DELETE CASCADE,
  session_id uuid REFERENCES device_sessions(id) ON DELETE SET NULL,
  recorded_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  accuracy_m double precision,
  altitude_m double precision,
  speed_mps double precision,
  heading_deg double precision,
  source text NOT NULL DEFAULT 'device',
  raw jsonb,
  CONSTRAINT chk_gps_latitude_range CHECK (latitude >= -90 AND latitude <= 90),
  CONSTRAINT chk_gps_longitude_range CHECK (longitude >= -180 AND longitude <= 180),
  CONSTRAINT chk_gps_heading_range CHECK (heading_deg IS NULL OR (heading_deg >= 0 AND heading_deg < 360))
);

-- Primary time-series indexes
CREATE INDEX IF NOT EXISTS idx_gps_points_bike_recorded_at_desc
  ON gps_location_points(bike_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_gps_points_session_recorded_at_desc
  ON gps_location_points(session_id, recorded_at DESC);

-- BRIN for time range scans
CREATE INDEX IF NOT EXISTS idx_gps_points_recorded_at_brin
  ON gps_location_points USING brin(recorded_at);

-- geofences
CREATE TABLE IF NOT EXISTS geofences (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  bike_id uuid NOT NULL REFERENCES bikes(id) ON DELETE CASCADE,
  name text NOT NULL,
  geofence_type text NOT NULL DEFAULT 'circle',
  center_latitude double precision,
  center_longitude double precision,
  radius_m double precision,
  polygon jsonb,
  is_active boolean NOT NULL DEFAULT true,
  notify_on_exit boolean NOT NULL DEFAULT true,
  notify_on_enter boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_geofence_circle_required
    CHECK (
      geofence_type <> 'circle'
      OR (center_latitude IS NOT NULL AND center_longitude IS NOT NULL AND radius_m IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_geofences_bike_id ON geofences(bike_id);
CREATE INDEX IF NOT EXISTS idx_geofences_active ON geofences(is_active) WHERE is_active = true;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_geofences_updated_at') THEN
    CREATE TRIGGER trg_geofences_updated_at
    BEFORE UPDATE ON geofences
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;
END$$;

-- alert_events
CREATE TABLE IF NOT EXISTS alert_events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  bike_id uuid NOT NULL REFERENCES bikes(id) ON DELETE CASCADE,
  geofence_id uuid REFERENCES geofences(id) ON DELETE SET NULL,
  session_id uuid REFERENCES device_sessions(id) ON DELETE SET NULL,
  event_type text NOT NULL,
  event_at timestamptz NOT NULL DEFAULT now(),
  severity text NOT NULL DEFAULT 'warning',
  message text,
  location_latitude double precision,
  location_longitude double precision,
  payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_alert_latitude_range CHECK (location_latitude IS NULL OR (location_latitude >= -90 AND location_latitude <= 90)),
  CONSTRAINT chk_alert_longitude_range CHECK (location_longitude IS NULL OR (location_longitude >= -180 AND location_longitude <= 180))
);

CREATE INDEX IF NOT EXISTS idx_alert_events_bike_event_at_desc
  ON alert_events(bike_id, event_at DESC);

CREATE INDEX IF NOT EXISTS idx_alert_events_geofence_event_at_desc
  ON alert_events(geofence_id, event_at DESC);

COMMIT;
