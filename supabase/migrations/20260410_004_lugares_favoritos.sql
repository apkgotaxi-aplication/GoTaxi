BEGIN;

CREATE TABLE IF NOT EXISTS public.lugares_favoritos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id UUID NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  descripcion TEXT,
  latitud DOUBLE PRECISION NOT NULL,
  longitud DOUBLE PRECISION NOT NULL,
  direccion TEXT NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'otro', -- 'casa', 'trabajo', 'otro'
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT lugares_favoritos_cliente_nombre_unique UNIQUE (cliente_id, nombre)
);

CREATE INDEX IF NOT EXISTS lugares_favoritos_cliente_idx
  ON public.lugares_favoritos (cliente_id, created_at DESC);

ALTER TABLE public.lugares_favoritos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS lugares_favoritos_select_own ON public.lugares_favoritos;
CREATE POLICY lugares_favoritos_select_own
ON public.lugares_favoritos
FOR SELECT
TO authenticated
USING (cliente_id = auth.uid());

DROP POLICY IF EXISTS lugares_favoritos_insert_own ON public.lugares_favoritos;
CREATE POLICY lugares_favoritos_insert_own
ON public.lugares_favoritos
FOR INSERT
TO authenticated
WITH CHECK (cliente_id = auth.uid());

DROP POLICY IF EXISTS lugares_favoritos_update_own ON public.lugares_favoritos;
CREATE POLICY lugares_favoritos_update_own
ON public.lugares_favoritos
FOR UPDATE
TO authenticated
USING (cliente_id = auth.uid())
WITH CHECK (cliente_id = auth.uid());

DROP POLICY IF EXISTS lugares_favoritos_delete_own ON public.lugares_favoritos;
CREATE POLICY lugares_favoritos_delete_own
ON public.lugares_favoritos
FOR DELETE
TO authenticated
USING (cliente_id = auth.uid());

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
    lf.created_at,
    lf.updated_at
  FROM public.lugares_favoritos lf
  WHERE lf.cliente_id = auth.uid()
  ORDER BY lf.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.add_favorite_location(
  p_nombre TEXT,
  p_latitud DOUBLE PRECISION,
  p_longitud DOUBLE PRECISION,
  p_direccion TEXT,
  p_tipo TEXT DEFAULT 'otro',
  p_descripcion TEXT DEFAULT NULL
)
RETURNS TABLE(
  id UUID,
  message TEXT,
  success BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.lugares_favoritos (
    cliente_id,
    nombre,
    descripcion,
    latitud,
    longitud,
    direccion,
    tipo
  )
  VALUES (
    auth.uid(),
    p_nombre,
    p_descripcion,
    p_latitud,
    p_longitud,
    p_direccion,
    p_tipo
  )
  RETURNING lugares_favoritos.id INTO v_id;

  RETURN QUERY SELECT v_id, 'Ubicación favorita agregada exitosamente'::TEXT, true;
EXCEPTION WHEN unique_violation THEN
  RETURN QUERY SELECT NULL::UUID, 'Ya existe un favorito con ese nombre'::TEXT, false;
WHEN OTHERS THEN
  RETURN QUERY SELECT NULL::UUID, SQLERRM, false;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_favorite_location(p_favorite_id UUID)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
  DELETE FROM public.lugares_favoritos
  WHERE id = p_favorite_id AND cliente_id = auth.uid();

  IF FOUND THEN
    RETURN QUERY SELECT true, 'Ubicación eliminada exitosamente'::TEXT;
  ELSE
    RETURN QUERY SELECT false, 'No se encontró la ubicación o no tienes permisos'::TEXT;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false, SQLERRM;
END;
$$;

COMMIT;
