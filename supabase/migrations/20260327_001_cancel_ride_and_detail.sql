-- RPC para cancelar viajes activos del cliente y liberar taxista/vehiculo.
CREATE OR REPLACE FUNCTION public.cancel_ride(
  p_viaje_id uuid,
  p_cliente_id uuid
)
RETURNS TABLE(success boolean, message text, estado estado_viaje)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_estado public.estado_viaje;
  v_driver_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida para cancelar viaje', NULL::public.estado_viaje;
    RETURN;
  END IF;

  IF p_cliente_id IS DISTINCT FROM auth.uid() THEN
    RETURN QUERY SELECT FALSE, 'No tienes permiso para cancelar este viaje', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado, v.driver_id
  INTO v_estado, v_driver_id
  FROM public.viajes v
  WHERE v.id = p_viaje_id
    AND v.user_id = p_cliente_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'No se encontro el viaje para este cliente', NULL::public.estado_viaje;
    RETURN;
  END IF;

  IF v_estado NOT IN ('pendiente', 'confirmada') THEN
    RETURN QUERY SELECT FALSE, 'Solo puedes cancelar viajes pendientes o confirmados', v_estado;
    RETURN;
  END IF;

  UPDATE public.viajes
  SET estado = 'cancelada',
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_viaje_id;

  IF v_driver_id IS NOT NULL THEN
    UPDATE public.taxistas
    SET estado = 'disponible',
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_driver_id;

    UPDATE public.vehiculos
    SET disponible = TRUE,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = (SELECT vehiculo_id FROM public.taxistas WHERE id = v_driver_id);
  END IF;

  RETURN QUERY SELECT TRUE, 'Viaje cancelado correctamente', 'cancelada'::public.estado_viaje;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al cancelar viaje: ' || SQLERRM, NULL::public.estado_viaje;
END;
$function$;

-- RPC para cargar detalle de viaje de cliente con taxista y vehiculo.
CREATE OR REPLACE FUNCTION public.get_ride_detail(
  p_viaje_id uuid,
  p_cliente_id uuid
)
RETURNS TABLE(
  id uuid,
  created_at timestamptz,
  estado estado_viaje,
  origen varchar,
  destino varchar,
  precio numeric,
  distancia double precision,
  duracion integer,
  num_pasajeros integer,
  anotaciones varchar,
  fecha_recogida timestamp,
  fecha_entrega timestamp,
  driver_id uuid,
  driver_nombre text,
  driver_apellidos text,
  driver_telefono text,
  vehiculo_marca varchar,
  vehiculo_modelo varchar,
  vehiculo_color varchar,
  vehiculo_matricula varchar,
  vehiculo_licencia_taxi varchar,
  vehiculo_capacidad varchar,
  vehiculo_minusvalido boolean
)
LANGUAGE sql
STABLE
AS $function$
  SELECT
    v.id,
    v.created_at,
    v.estado,
    v.origen,
    v.destino,
    v.precio,
    v.distancia,
    v.duracion,
    v.num_pasajeros,
    v.anotaciones,
    v.fecha_recogida,
    v.fecha_entrega,
    v.driver_id,
    u_driver.nombre AS driver_nombre,
    u_driver.apellidos AS driver_apellidos,
    u_driver.telefono AS driver_telefono,
    veh.marca AS vehiculo_marca,
    veh.modelo AS vehiculo_modelo,
    veh.color AS vehiculo_color,
    veh.matricula AS vehiculo_matricula,
    veh.licencia_taxi AS vehiculo_licencia_taxi,
    veh.capacidad AS vehiculo_capacidad,
    veh.minusvalido AS vehiculo_minusvalido
  FROM public.viajes v
  LEFT JOIN public.usuarios u_driver ON u_driver.id = v.driver_id
  LEFT JOIN public.taxistas t ON t.id = v.driver_id
  LEFT JOIN public.vehiculos veh ON veh.id = t.vehiculo_id
  WHERE v.id = p_viaje_id
    AND v.user_id = p_cliente_id
  LIMIT 1;
$function$;
