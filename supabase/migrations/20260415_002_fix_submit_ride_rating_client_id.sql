BEGIN;

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
  SELECT v.user_id INTO v_cliente_id
  FROM public.viajes v
  WHERE v.id = p_viaje_id;

  IF v_cliente_id IS NULL THEN
    RETURN QUERY SELECT false, 'Viaje no encontrado'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF v_cliente_id != auth.uid() THEN
    RETURN QUERY SELECT false, 'No tienes permisos para valorar este viaje'::TEXT, NULL::UUID;
    RETURN;
  END IF;

  IF p_tipo_valoracion = 'negativa' AND p_motivo IS NULL THEN
    RETURN QUERY SELECT false, 'El motivo es obligatorio para valoraciones negativas'::TEXT, NULL::UUID;
    RETURN;
  END IF;

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