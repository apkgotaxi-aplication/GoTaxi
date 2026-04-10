BEGIN;

CREATE OR REPLACE FUNCTION public.get_user_ride_history(
  p_user_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  id uuid,
  created_at timestamp with time zone,
  estado estado_viaje,
  origen varchar,
  destino varchar,
  precio numeric,
  fecha_recogida timestamp without time zone,
  fecha_entrega timestamp without time zone,
  user_nombre text,
  user_apellidos text,
  driver_nombre text,
  driver_apellidos text
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
    v.fecha_recogida,
    v.fecha_entrega,
    u_client.nombre AS user_nombre,
    u_client.apellidos AS user_apellidos,
    u_driver.nombre AS driver_nombre,
    u_driver.apellidos AS driver_apellidos
  FROM public.viajes v
  LEFT JOIN public.usuarios u_client ON v.user_id = u_client.id
  LEFT JOIN public.usuarios u_driver ON v.driver_id = u_driver.id
  WHERE v.user_id = p_user_id
  ORDER BY v.created_at DESC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.get_driver_ride_history(
  p_driver_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  id uuid,
  created_at timestamp with time zone,
  estado estado_viaje,
  origen varchar,
  destino varchar,
  precio numeric,
  fecha_recogida timestamp without time zone,
  fecha_entrega timestamp without time zone,
  user_nombre text,
  user_apellidos text,
  driver_nombre text,
  driver_apellidos text
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
    v.fecha_recogida,
    v.fecha_entrega,
    u_client.nombre AS user_nombre,
    u_client.apellidos AS user_apellidos,
    u_driver.nombre AS driver_nombre,
    u_driver.apellidos AS driver_apellidos
  FROM public.viajes v
  LEFT JOIN public.usuarios u_client ON v.user_id = u_client.id
  LEFT JOIN public.usuarios u_driver ON v.driver_id = u_driver.id
  WHERE v.driver_id = p_driver_id
  ORDER BY v.created_at DESC
  LIMIT p_limit;
$function$;

COMMIT;