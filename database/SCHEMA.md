# BikeTrack Pro — Database Schema (PostgreSQL)

This container runs **PostgreSQL** (see `startup.sh`) and the connection string is saved in `db_connection.txt`.

## Connection

```bash
cat db_connection.txt
# psql postgresql://appuser:dbuser123@localhost:5000/myapp
```

## Notes / Design choices

- IDs: Most entity tables use `uuid` primary keys (`uuid-ossp` extension).
- GPS points use `bigserial` primary key for write performance and ordered ingestion.
- PostGIS is **not installed** in this environment, so geo indexing is done with standard btree + BRIN (time) indexes.
- `updated_at` is maintained using a trigger function for tables that have it.
- Polygon geofences are stored as `jsonb` (application interprets).

## Tables

### `users`
- `id uuid PK`
- `email text UNIQUE NOT NULL`
- `password_hash text` (backend auth decides hashing)
- `full_name text`
- `role text NOT NULL DEFAULT 'user'`
- `is_active boolean NOT NULL DEFAULT true`
- `created_at`, `updated_at`

Trigger:
- `trg_users_updated_at` sets `updated_at` on update.

### `bikes`
- `id uuid PK`
- `owner_user_id uuid NOT NULL` → `users(id)` (CASCADE on delete)
- `name text NOT NULL`
- optional metadata: `description`, `make`, `model`, `color`, `serial_number`
- `device_identifier text UNIQUE` (tracker device id / external id)
- `is_active boolean NOT NULL DEFAULT true`
- `created_at`, `updated_at`

Indexes:
- `idx_bikes_owner_user_id (owner_user_id)`

Trigger:
- `trg_bikes_updated_at`

### `device_sessions`
Represents a device reporting session for a bike.
- `id uuid PK`
- `bike_id uuid NOT NULL` → `bikes(id)` (CASCADE)
- `device_identifier text` (optional snapshot)
- `started_at timestamptz NOT NULL DEFAULT now()`
- `ended_at timestamptz`
- `status text NOT NULL DEFAULT 'active'` (`active`, `ended`, etc.)
- `last_heartbeat_at timestamptz`
- `created_at timestamptz NOT NULL DEFAULT now()`

Indexes:
- `idx_device_sessions_bike_started (bike_id, started_at DESC)`
- `idx_device_sessions_status (status)`

### `gps_location_points`
Time series GPS history.
- `id bigserial PK`
- `bike_id uuid NOT NULL` → `bikes(id)` (CASCADE)
- `session_id uuid` → `device_sessions(id)` (SET NULL)
- `recorded_at timestamptz NOT NULL` (when device recorded)
- `received_at timestamptz NOT NULL DEFAULT now()` (when server ingested)
- `latitude`, `longitude` (double precision, with range constraints)
- optional telemetry: `accuracy_m`, `altitude_m`, `speed_mps`, `heading_deg`
- `source text NOT NULL DEFAULT 'device'`
- `raw jsonb` (optional raw payload)

Indexes (GPS history performance):
- `idx_gps_points_bike_recorded_at_desc (bike_id, recorded_at DESC)` — main history query
- `idx_gps_points_session_recorded_at_desc (session_id, recorded_at DESC)` — playback by session
- `idx_gps_points_recorded_at_brin USING brin(recorded_at)` — large time range scans

### `geofences`
- `id uuid PK`
- `bike_id uuid NOT NULL` → `bikes(id)` (CASCADE)
- `name text NOT NULL`
- `geofence_type text NOT NULL DEFAULT 'circle'` (e.g. `circle`, `polygon`)
- Circle fields: `center_latitude`, `center_longitude`, `radius_m`
- Polygon field: `polygon jsonb` (application-defined structure)
- `is_active boolean NOT NULL DEFAULT true`
- `notify_on_exit boolean NOT NULL DEFAULT true`
- `notify_on_enter boolean NOT NULL DEFAULT false`
- `created_at`, `updated_at`
- Constraint: if `geofence_type = 'circle'`, requires center + radius

Indexes:
- `idx_geofences_bike_id (bike_id)`
- `idx_geofences_active (is_active) WHERE is_active = true`

Trigger:
- `trg_geofences_updated_at`

### `alert_events`
Events such as geofence enter/exit, device offline, etc.
- `id uuid PK`
- `bike_id uuid NOT NULL` → `bikes(id)` (CASCADE)
- `geofence_id uuid` → `geofences(id)` (SET NULL)
- `session_id uuid` → `device_sessions(id)` (SET NULL)
- `event_type text NOT NULL` (e.g. `geofence_exit`, `geofence_enter`, ...)
- `event_at timestamptz NOT NULL DEFAULT now()`
- `severity text NOT NULL DEFAULT 'warning'`
- `message text`
- `location_latitude`, `location_longitude` (optional snapshot)
- `payload jsonb` (optional structured data)
- `created_at timestamptz NOT NULL DEFAULT now()`

Indexes:
- `idx_alert_events_bike_event_at_desc (bike_id, event_at DESC)`
- `idx_alert_events_geofence_event_at_desc (geofence_id, event_at DESC)`

### `schema_migrations`
Lightweight ledger table to track applied schema versions.
- `version text PK`
- `applied_at timestamptz NOT NULL DEFAULT now()`

Current version:
- `2026-02-12_initial_biketrack_schema`

## Seed data

Inserted (idempotent):
- User: `demo@biketrack.pro` (password_hash = `demo` placeholder for development)
- Bike: `Demo Bike` with `device_identifier = demo-device-001`
- Geofence: `Home` circle around (37.7749, -122.4194), radius 250m
