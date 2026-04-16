BEGIN;

-- Create ENUM type for rating type
CREATE TYPE public.rating_type AS ENUM ('positiva', 'negativa');

-- Create ENUM type for rating motive
CREATE TYPE public.rating_motive AS ENUM ('imprudente', 'sucio', 'ruta_incorrecta');

-- Create main table
CREATE TABLE IF NOT EXISTS public.valoraciones_taxista (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  viaje_id UUID NOT NULL UNIQUE REFERENCES public.viajes(id) ON DELETE CASCADE,
  taxista_id UUID NOT NULL REFERENCES public.taxistas(id) ON DELETE CASCADE,
  cliente_id UUID NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  tipo_valoracion public.rating_type NOT NULL,
  motivo public.rating_motive,
  comentario TEXT,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS valoraciones_taxista_taxista_idx
  ON public.valoraciones_taxista (taxista_id DESC);

CREATE INDEX IF NOT EXISTS valoraciones_taxista_tipo_idx
  ON public.valoraciones_taxista (tipo_valoracion);

CREATE INDEX IF NOT EXISTS valoraciones_taxista_cliente_idx
  ON public.valoraciones_taxista (cliente_id);

CREATE INDEX IF NOT EXISTS valoraciones_taxista_creado_en_idx
  ON public.valoraciones_taxista (creado_en DESC);

-- Enable RLS
ALTER TABLE public.valoraciones_taxista ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Admin and clients can view ratings
DROP POLICY IF EXISTS valoraciones_select_own_or_admin ON public.valoraciones_taxista;
CREATE POLICY valoraciones_select_own_or_admin
ON public.valoraciones_taxista
FOR SELECT
TO authenticated
USING (
  cliente_id = auth.uid() 
  OR EXISTS (
    SELECT 1 FROM public.usuarios u 
    WHERE u.id = auth.uid() AND u.rol = 'admin'
  )
);

-- Only clients can insert ratings
DROP POLICY IF EXISTS valoraciones_insert_own ON public.valoraciones_taxista;
CREATE POLICY valoraciones_insert_own
ON public.valoraciones_taxista
FOR INSERT
TO authenticated
WITH CHECK (cliente_id = auth.uid());

-- Only the rating author (client) can update
DROP POLICY IF EXISTS valoraciones_update_own ON public.valoraciones_taxista;
CREATE POLICY valoraciones_update_own
ON public.valoraciones_taxista
FOR UPDATE
TO authenticated
USING (cliente_id = auth.uid())
WITH CHECK (cliente_id = auth.uid());

-- Only the rating author (client) can delete
DROP POLICY IF EXISTS valoraciones_delete_own ON public.valoraciones_taxista;
CREATE POLICY valoraciones_delete_own
ON public.valoraciones_taxista
FOR DELETE
TO authenticated
USING (cliente_id = auth.uid());

-- RPC: Check if a ride has been rated
CREATE OR REPLACE FUNCTION public.check_ride_rated(p_ride_id UUID)
RETURNS TABLE(
  is_rated BOOLEAN,
  rating_type TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT
    COALESCE(COUNT(*) > 0, false) as is_rated,
    MAX(CASE WHEN vt.tipo_valoracion = 'positiva' THEN 'positiva' 
             WHEN vt.tipo_valoracion = 'negativa' THEN 'negativa' 
             ELSE NULL END)::TEXT as rating_type
  FROM public.valoraciones_taxista vt
  WHERE vt.viaje_id = p_ride_id;
$$;

-- RPC: Get taxista ratings summary (for admin dashboard)
CREATE OR REPLACE FUNCTION public.get_taxista_ratings_summary(p_taxista_id UUID)
RETURNS TABLE(
  total_ratings BIGINT,
  positive_count BIGINT,
  negative_count BIGINT,
  incident_percentage NUMERIC,
  recent_incidents JSONB
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  WITH rating_stats AS (
    SELECT
      COUNT(*) as total,
      COUNT(CASE WHEN vt.tipo_valoracion = 'positiva' THEN 1 END) as positive,
      COUNT(CASE WHEN vt.tipo_valoracion = 'negativa' THEN 1 END) as negative
    FROM public.valoraciones_taxista vt
    WHERE vt.taxista_id = p_taxista_id
  ),
  recent_incidents_data AS (
    SELECT
      json_agg(
        json_build_object(
          'id', vt.id,
          'motivo', vt.motivo::TEXT,
          'comentario', vt.comentario,
          'creado_en', vt.creado_en
        ) ORDER BY vt.creado_en DESC
      ) as incidents
    FROM public.valoraciones_taxista vt
    WHERE vt.taxista_id = p_taxista_id 
      AND vt.tipo_valoracion = 'negativa'
    LIMIT 10
  )
  SELECT
    rs.total as total_ratings,
    rs.positive as positive_count,
    rs.negative as negative_count,
    ROUND(
      CASE 
        WHEN rs.total > 0 
        THEN (rs.negative::NUMERIC / rs.total * 100) 
        ELSE 0 
      END, 
      2
    ) as incident_percentage,
    COALESCE(rid.incidents, '[]'::JSONB) as recent_incidents
  FROM rating_stats rs, recent_incidents_data rid;
$$;

-- RPC: Submit a rating for a ride
CREATE OR REPLACE FUNCTION public.submit_ride_rating(
  p_viaje_id UUID,
  p_taxista_id UUID,
  p_tipo_valoracion public.rating_type,
  p_motivo public.rating_motive DEFAULT NULL,
  p_comentario TEXT DEFAULT NULL
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  rating_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_rating_id UUID;
  v_cliente_id UUID;
BEGIN
  -- Get the cliente_id from the ride
  SELECT viajes.cliente_id INTO v_cliente_id
  FROM public.viajes
  WHERE viajes.id = p_viaje_id;

  IF v_cliente_id IS NULL THEN
    RETURN QUERY SELECT false, 'Viaje no encontrado'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  -- Verify that the current user is the client who made the ride
  IF v_cliente_id != auth.uid() THEN
    RETURN QUERY SELECT false, 'No tienes permisos para valorar este viaje'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  -- Validate motive is provided for negative ratings
  IF p_tipo_valoracion = 'negativa' AND p_motivo IS NULL THEN
    RETURN QUERY SELECT false, 'El motivo es obligatorio para valoraciones negativas'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  -- Insert the rating
  INSERT INTO public.valoraciones_taxista (
    viaje_id,
    taxista_id,
    cliente_id,
    tipo_valoracion,
    motivo,
    comentario
  )
  VALUES (
    p_viaje_id,
    p_taxista_id,
    v_cliente_id,
    p_tipo_valoracion,
    p_motivo,
    p_comentario
  )
  RETURNING valoraciones_taxista.id INTO v_rating_id;

  RETURN QUERY SELECT true, 'Valoración enviada exitosamente'::TEXT, v_rating_id;

EXCEPTION WHEN unique_violation THEN
  RETURN QUERY SELECT false, 'Este viaje ya ha sido valorado'::TEXT, NULL::UUID;
WHEN OTHERS THEN
  RETURN QUERY SELECT false, SQLERRM, NULL::UUID;
END;
$$;

COMMIT;
