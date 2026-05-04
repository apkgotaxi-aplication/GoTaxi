BEGIN;

DROP FUNCTION IF EXISTS public.get_ride_detail(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_driver_ride_detail(uuid, uuid);

CREATE FUNCTION public.get_ride_detail(
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
  pagado boolean,
  stripe_payment_status text,
  stripe_payment_intent_id text,
  driver_id uuid,
  driver_nombre text,
  driver_apellidos text,
  driver_telefono text,
  origen_lat numeric,
  origen_lng numeric,
  driver_lat numeric,
  driver_lng numeric,
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
    v.pagado,
    v.stripe_payment_status,
    v.stripe_payment_intent_id,
    v.driver_id,
    u_driver.nombre AS driver_nombre,
    u_driver.apellidos AS driver_apellidos,
    u_driver.telefono AS driver_telefono,
    v.origen_lat,
    v.origen_lng,
    t.lat AS driver_lat,
    t.lng AS driver_lng,
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

CREATE FUNCTION public.get_driver_ride_detail(
  p_viaje_id uuid,
  p_driver_id uuid
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
  pagado boolean,
  stripe_payment_status text,
  stripe_payment_intent_id text,
  cliente_id uuid,
  cliente_nombre text,
  cliente_apellidos text,
  cliente_telefono text,
  driver_id uuid,
  driver_nombre text,
  driver_apellidos text,
  driver_telefono text,
  origen_lat numeric,
  origen_lng numeric,
  driver_lat numeric,
  driver_lng numeric,
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
SECURITY DEFINER
SET search_path TO 'public'
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
    v.pagado,
    v.stripe_payment_status,
    v.stripe_payment_intent_id,
    v.user_id AS cliente_id,
    u_cliente.nombre AS cliente_nombre,
    u_cliente.apellidos AS cliente_apellidos,
    u_cliente.telefono AS cliente_telefono,
    v.driver_id,
    u_driver.nombre AS driver_nombre,
    u_driver.apellidos AS driver_apellidos,
    u_driver.telefono AS driver_telefono,
    v.origen_lat,
    v.origen_lng,
    t.lat AS driver_lat,
    t.lng AS driver_lng,
    veh.marca AS vehiculo_marca,
    veh.modelo AS vehiculo_modelo,
    veh.color AS vehiculo_color,
    veh.matricula AS vehiculo_matricula,
    veh.licencia_taxi AS vehiculo_licencia_taxi,
    veh.capacidad AS vehiculo_capacidad,
    veh.minusvalido AS vehiculo_minusvalido
  FROM public.viajes v
  LEFT JOIN public.usuarios u_cliente ON u_cliente.id = v.user_id
  LEFT JOIN public.usuarios u_driver ON u_driver.id = v.driver_id
  LEFT JOIN public.taxistas t ON t.id = v.driver_id
  LEFT JOIN public.vehiculos veh ON veh.id = t.vehiculo_id
  WHERE v.id = p_viaje_id
    AND v.driver_id = p_driver_id
    AND p_driver_id = auth.uid()
  LIMIT 1;
$function$;

COMMIT;