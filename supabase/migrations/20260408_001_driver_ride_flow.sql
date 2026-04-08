BEGIN;

CREATE OR REPLACE FUNCTION public.assign_taxi_to_ride(
  p_cliente_id uuid,
  p_origen text,
  p_destino text,
  p_num_pasajeros integer,
  p_anotaciones text,
  p_distancia double precision,
  p_precio numeric,
  p_duracion integer,
  p_minusvalido boolean,
  p_ciudad_origen text,
  p_fecha_recogida timestamp without time zone DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE(
  success boolean,
  viaje_id uuid,
  taxista_id uuid,
  estado estado_viaje,
  message text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_has_active_ride BOOLEAN;
  v_taxista_id UUID;
  v_viaje_id UUID;
  v_municipio_id INTEGER;
BEGIN
  IF p_cliente_id IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Cliente obligatorio';
    RETURN;
  END IF;

  IF p_origen IS NULL OR btrim(p_origen) = '' OR p_destino IS NULL OR btrim(p_destino) = '' THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Origen y destino son obligatorios';
    RETURN;
  END IF;

  IF p_num_pasajeros < 1 OR p_num_pasajeros > 8 THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'El numero de pasajeros debe estar entre 1 y 8';
    RETURN;
  END IF;

  IF p_precio < 2 THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'El precio minimo para un viaje es de 2 euros';
    RETURN;
  END IF;

  IF p_duracion >= 1080 THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'La duracion del viaje no puede ser mayor a 18 horas';
    RETURN;
  END IF;

  IF p_ciudad_origen IS NULL OR btrim(p_ciudad_origen) = '' THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Debes especificar tu ciudad de origen';
    RETURN;
  END IF;

  SELECT id INTO v_municipio_id
  FROM public.municipios
  WHERE lower(nombre) = lower(btrim(p_ciudad_origen))
  LIMIT 1;

  IF v_municipio_id IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'No operamos en ' || btrim(p_ciudad_origen) || '. Municipios disponibles: Jerez, Jerez de la Frontera';
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.viajes v
    WHERE v.user_id = p_cliente_id
      AND v.estado IN ('pendiente'::public.estado_viaje, 'confirmada'::public.estado_viaje, 'en_curso'::public.estado_viaje)
  ) INTO v_has_active_ride;

  IF v_has_active_ride THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Ya tienes una reserva activa';
    RETURN;
  END IF;

  SELECT t.id
  INTO v_taxista_id
  FROM public.taxistas t
  JOIN public.vehiculos veh ON veh.id = t.vehiculo_id
  WHERE t.estado = 'disponible'::public.estado_taxista
    AND veh.disponible = TRUE
    AND t.municipio_id = v_municipio_id
    AND CASE
      WHEN veh.capacidad ~ '^[0-9]+$' THEN veh.capacidad::INT
      ELSE 0
    END >= p_num_pasajeros
    AND (p_minusvalido = FALSE OR veh.minusvalido = TRUE)
  ORDER BY t.ultimo_viaje ASC NULLS FIRST, t.created_at ASC
  LIMIT 1
  FOR UPDATE OF t SKIP LOCKED;

  IF v_taxista_id IS NULL THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'No hay taxistas disponibles en tu zona en este momento';
    RETURN;
  END IF;

  INSERT INTO public.viajes (
    user_id,
    driver_id,
    fecha_reserva,
    fecha_recogida,
    estado,
    origen,
    destino,
    num_pasajeros,
    anotaciones,
    distancia,
    precio,
    pagado,
    duracion,
    minusvalido,
    ciudad_origen,
    updated_at
  ) VALUES (
    p_cliente_id,
    v_taxista_id,
    CURRENT_TIMESTAMP,
    COALESCE(p_fecha_recogida, CURRENT_TIMESTAMP),
    'pendiente'::public.estado_viaje,
    p_origen,
    p_destino,
    p_num_pasajeros,
    NULLIF(btrim(p_anotaciones), ''),
    p_distancia,
    p_precio,
    FALSE,
    p_duracion,
    p_minusvalido,
    NULLIF(btrim(p_ciudad_origen), ''),
    CURRENT_TIMESTAMP
  )
  RETURNING id INTO v_viaje_id;

  UPDATE public.taxistas
  SET estado = 'ocupado'::public.estado_taxista,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = v_taxista_id;

  UPDATE public.vehiculos
  SET disponible = FALSE,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = (SELECT vehiculo_id FROM public.taxistas WHERE id = v_taxista_id);

  RETURN QUERY SELECT TRUE, v_viaje_id, v_taxista_id, 'pendiente'::public.estado_viaje, 'Solicitud enviada al taxista y pendiente de confirmacion';
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Error al crear solicitud: ' || SQLERRM;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_ride_by_driver(
  p_viaje_id UUID
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  estado public.estado_viaje
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_viaje;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado
  INTO v_estado
  FROM public.viajes v
  WHERE v.id = p_viaje_id
    AND v.driver_id = v_user_id
  FOR UPDATE;

  IF v_estado IS NULL THEN
    RETURN QUERY SELECT FALSE, 'No se encontro el viaje para este taxista', NULL::public.estado_viaje;
    RETURN;
  END IF;

  IF v_estado <> 'confirmada' THEN
    RETURN QUERY SELECT FALSE, 'Solo puedes comenzar viajes confirmados', v_estado;
    RETURN;
  END IF;

  UPDATE public.viajes
  SET estado = 'en_curso',
      fecha_recogida = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_viaje_id;

  RETURN QUERY SELECT TRUE, 'Viaje en curso', 'en_curso'::public.estado_viaje;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al comenzar viaje: ' || SQLERRM, NULL::public.estado_viaje;
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_ride_by_driver(
  p_viaje_id UUID
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  estado public.estado_viaje
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_viaje;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado
  INTO v_estado
  FROM public.viajes v
  WHERE v.id = p_viaje_id
    AND v.driver_id = v_user_id
  FOR UPDATE;

  IF v_estado IS NULL THEN
    RETURN QUERY SELECT FALSE, 'No se encontro el viaje para este taxista', NULL::public.estado_viaje;
    RETURN;
  END IF;

  IF v_estado <> 'pendiente' THEN
    RETURN QUERY SELECT FALSE, 'Solo puedes confirmar viajes pendientes', v_estado;
    RETURN;
  END IF;

  UPDATE public.viajes
  SET estado = 'confirmada',
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_viaje_id;

  UPDATE public.taxistas
  SET estado = 'ocupado',
      updated_at = CURRENT_TIMESTAMP
  WHERE id = v_user_id;

  UPDATE public.vehiculos
  SET disponible = FALSE,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = (SELECT vehiculo_id FROM public.taxistas WHERE id = v_user_id);

  RETURN QUERY SELECT TRUE, 'Viaje confirmado', 'confirmada'::public.estado_viaje;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al confirmar viaje: ' || SQLERRM, NULL::public.estado_viaje;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_ride_by_driver(
  p_viaje_id UUID
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  estado public.estado_viaje
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_viaje;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado
  INTO v_estado
  FROM public.viajes v
  WHERE v.id = p_viaje_id
    AND v.driver_id = v_user_id
  FOR UPDATE;

  IF v_estado IS NULL THEN
    RETURN QUERY SELECT FALSE, 'No se encontro el viaje para este taxista', NULL::public.estado_viaje;
    RETURN;
  END IF;

  IF v_estado NOT IN ('pendiente', 'confirmada', 'en_curso') THEN
    RETURN QUERY SELECT FALSE, 'Solo puedes cancelar viajes activos', v_estado;
    RETURN;
  END IF;

  UPDATE public.viajes
  SET estado = 'cancelada',
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_viaje_id;

  UPDATE public.taxistas
  SET estado = 'disponible',
      updated_at = CURRENT_TIMESTAMP
  WHERE id = v_user_id;

  UPDATE public.vehiculos
  SET disponible = TRUE,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = (SELECT vehiculo_id FROM public.taxistas WHERE id = v_user_id);

  RETURN QUERY SELECT TRUE, 'Viaje cancelado', 'cancelada'::public.estado_viaje;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al cancelar viaje: ' || SQLERRM, NULL::public.estado_viaje;
END;
$function$;

CREATE OR REPLACE FUNCTION public.finish_ride_by_driver(
  p_viaje_id UUID
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  estado public.estado_viaje
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_viaje;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado
  INTO v_estado
  FROM public.viajes v
  WHERE v.id = p_viaje_id
    AND v.driver_id = v_user_id
  FOR UPDATE;

  IF v_estado IS NULL THEN
    RETURN QUERY SELECT FALSE, 'No se encontro el viaje para este taxista', NULL::public.estado_viaje;
    RETURN;
  END IF;

  IF v_estado <> 'en_curso' THEN
    RETURN QUERY SELECT FALSE, 'Solo puedes finalizar viajes en curso', v_estado;
    RETURN;
  END IF;

  UPDATE public.viajes
  SET estado = 'finalizada',
      fecha_entrega = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_viaje_id;

  UPDATE public.taxistas
  SET estado = 'disponible',
      ultimo_viaje = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = v_user_id;

  UPDATE public.vehiculos
  SET disponible = TRUE,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = (SELECT vehiculo_id FROM public.taxistas WHERE id = v_user_id);

  RETURN QUERY SELECT TRUE, 'Viaje finalizado', 'finalizada'::public.estado_viaje;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al finalizar viaje: ' || SQLERRM, NULL::public.estado_viaje;
END;
$function$;

COMMIT;
