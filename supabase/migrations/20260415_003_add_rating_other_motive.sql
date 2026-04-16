BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'rating_motive'
      AND e.enumlabel = 'otra'
  ) THEN
    ALTER TYPE public.rating_motive ADD VALUE 'otra';
  END IF;
END $$;

COMMIT;
