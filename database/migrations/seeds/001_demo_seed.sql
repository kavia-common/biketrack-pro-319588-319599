-- Demo seed data (idempotent)
-- Intended only for development/preview.

-- Demo user
INSERT INTO users (email, password_hash, full_name, role, is_active)
VALUES ('demo@biketrack.pro', 'demo', 'Demo User', 'user', true)
ON CONFLICT (email) DO UPDATE
SET full_name = EXCLUDED.full_name,
    is_active = EXCLUDED.is_active;

-- Demo bike (owned by demo user)
WITH u AS (
  SELECT id FROM users WHERE email = 'demo@biketrack.pro'
)
INSERT INTO bikes (owner_user_id, name, device_identifier, description, make, model, color, is_active)
SELECT u.id, 'Demo Bike', 'demo-device-001', 'Seeded demo bike for preview', 'DemoMake', 'DemoModel', 'Blue', true
FROM u
ON CONFLICT (device_identifier) DO UPDATE
SET name = EXCLUDED.name,
    description = EXCLUDED.description,
    is_active = EXCLUDED.is_active;

-- Demo geofence ("Home") around SF (37.7749, -122.4194), radius 250m
WITH b AS (
  SELECT id FROM bikes WHERE device_identifier = 'demo-device-001'
)
INSERT INTO geofences (
  bike_id,
  name,
  geofence_type,
  center_latitude,
  center_longitude,
  radius_m,
  is_active,
  notify_on_exit,
  notify_on_enter
)
SELECT
  b.id,
  'Home',
  'circle',
  37.7749,
  -122.4194,
  250,
  true,
  true,
  false
FROM b
WHERE NOT EXISTS (
  SELECT 1 FROM geofences g
  WHERE g.bike_id = b.id AND g.name = 'Home'
);
