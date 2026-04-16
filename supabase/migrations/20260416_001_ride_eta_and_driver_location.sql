BEGIN;

ALTER TABLE public.viajes
  ADD COLUMN IF NOT EXISTS origen_lat numeric(10,7),
  ADD COLUMN IF NOT EXISTS origen_lng numeric(10,7),
  ADD COLUMN IF NOT EXISTS destino_lat numeric(10,7),
  ADD COLUMN IF NOT EXISTS destino_lng numeric(10,7);

DROP FUNCTION IF EXISTS public.assign_taxi_to_ride(
  uuid,
  text,
  text,
  integer,
  text,
  double precision,
  numeric,
  integer,
  boolean,
  text,
  timestamp without time zone
);

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
  p_origen_lat numeric DEFAULT NULL,
  p_origen_lng numeric DEFAULT NULL,
  p_destino_lat numeric DEFAULT NULL,
  p_destino_lng numeric DEFAULT NULL,
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

  IF p_origen_lat IS NOT NULL AND (p_origen_lat < -90 OR p_origen_lat > 90) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Latitud de origen invalida';
    RETURN;
  END IF;

  IF p_origen_lng IS NOT NULL AND (p_origen_lng < -180 OR p_origen_lng > 180) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Longitud de origen invalida';
    RETURN;
  END IF;

  IF p_destino_lat IS NOT NULL AND (p_destino_lat < -90 OR p_destino_lat > 90) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Latitud de destino invalida';
    RETURN;
  END IF;

  IF p_destino_lng IS NOT NULL AND (p_destino_lng < -180 OR p_destino_lng > 180) THEN
    RETURN QUERY SELECT FALSE, NULL::UUID, NULL::UUID, NULL::public.estado_viaje, 'Longitud de destino invalida';
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
    origen_lat,
    origen_lng,
    destino_lat,
    destino_lng,
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
    p_origen_lat,
    p_origen_lng,
    p_destino_lat,
    p_destino_lng,
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

CREATE OR REPLACE FUNCTION public.update_driver_location(
  p_lat numeric,
  p_lng numeric
)
RETURNS TABLE(
  success boolean,
  message text,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::timestamptz;
    RETURN;
  END IF;

  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Ubicacion incompleta', NULL::timestamptz;
    RETURN;
  END IF;

  IF p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
    RETURN QUERY SELECT FALSE, 'Coordenadas invalidas', NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.taxistas
  SET lat = p_lat,
      lng = p_lng,
      ultima_actualizacion_ubicacion = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = v_user_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'Solo los taxistas pueden actualizar ubicacion', NULL::timestamptz;
    RETURN;
  END IF;

  RETURN QUERY SELECT TRUE, 'Ubicacion actualizada', now();
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_ride_eta(
  p_viaje_id uuid
)
RETURNS TABLE(
  eta_min integer,
  distancia_km numeric,
  taxista_lat numeric,
  taxista_lng numeric,
  ubicacion_actualizada_en timestamp
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_estado public.estado_viaje;
  v_cliente_id uuid;
  v_driver_id uuid;
  v_origen_lat numeric;
  v_origen_lng numeric;
  v_driver_lat numeric;
  v_driver_lng numeric;
  v_updated timestamp;
  v_distance_km numeric;
  v_eta integer;
BEGIN
  IF v_user_id IS NULL OR p_viaje_id IS NULL THEN
    RETURN;
  END IF;

  SELECT
    v.estado,
    v.user_id,
    v.driver_id,
    v.origen_lat,
    v.origen_lng,
    t.lat,
    t.lng,
    t.ultima_actualizacion_ubicacion
  INTO
    v_estado,
    v_cliente_id,
    v_driver_id,
    v_origen_lat,
    v_origen_lng,
    v_driver_lat,
    v_driver_lng,
    v_updated
  FROM public.viajes v
  LEFT JOIN public.taxistas t ON t.id = v.driver_id
  WHERE v.id = p_viaje_id;

  IF v_cliente_id IS NULL THEN
    RETURN;
  END IF;

  IF v_user_id <> v_cliente_id AND v_user_id <> v_driver_id THEN
    RETURN;
  END IF;

  IF v_estado <> 'confirmada'::public.estado_viaje THEN
    RETURN;
  END IF;

  IF v_origen_lat IS NULL OR v_origen_lng IS NULL OR v_driver_lat IS NULL OR v_driver_lng IS NULL THEN
    RETURN;
  END IF;

  v_distance_km := 6371 * acos(
    LEAST(
      1,
      GREATEST(
        -1,
        cos(radians(v_driver_lat::double precision))
        * cos(radians(v_origen_lat::double precision))
        * cos(radians((v_origen_lng - v_driver_lng)::double precision))
        + sin(radians(v_driver_lat::double precision))
        * sin(radians(v_origen_lat::double precision))
      )
    )
  );

  v_eta := GREATEST(1, CEIL(COALESCE(v_distance_km, 0) / 0.45)::integer);

  RETURN QUERY SELECT
    v_eta,
    round(v_distance_km::numeric, 2),
    v_driver_lat,
    v_driver_lng,
    v_updated;
END;
$function$;

COMMIT;
