BEGIN;

ALTER TABLE public.viajes
  ADD COLUMN IF NOT EXISTS eta_pickup_min integer,
  ADD COLUMN IF NOT EXISTS eta_pickup_updated_at timestamp without time zone,
  ADD COLUMN IF NOT EXISTS eta_pickup_driver_lat numeric(10,7),
  ADD COLUMN IF NOT EXISTS eta_pickup_driver_lng numeric(10,7);

COMMIT;