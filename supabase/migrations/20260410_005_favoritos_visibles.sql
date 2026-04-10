BEGIN;

ALTER TABLE public.lugares_favoritos
  ADD COLUMN IF NOT EXISTS visible_en_mapa BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS lugares_favoritos_visible_idx
  ON public.lugares_favoritos (cliente_id, visible_en_mapa, created_at DESC);

DROP FUNCTION IF EXISTS public.get_my_favorites();

CREATE OR REPLACE FUNCTION public.get_my_favorites()
RETURNS TABLE(
  id UUID,
  cliente_id UUID,
  nombre TEXT,
  descripcion TEXT,
  latitud DOUBLE PRECISION,
  longitud DOUBLE PRECISION,
  direccion TEXT,
  tipo TEXT,
  visible_en_mapa BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT
    lf.id,
    lf.cliente_id,
    lf.nombre,
    lf.descripcion,
    lf.latitud,
    lf.longitud,
    lf.direccion,
    lf.tipo,
    lf.visible_en_mapa,
    lf.created_at,
    lf.updated_at
  FROM public.lugares_favoritos lf
  WHERE lf.cliente_id = auth.uid()
  ORDER BY lf.created_at DESC;
$$;

COMMIT;
