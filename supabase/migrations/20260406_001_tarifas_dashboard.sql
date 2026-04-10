BEGIN;

CREATE TABLE IF NOT EXISTS public.tarifas (
  id BIGSERIAL NOT NULL,
  provincia_id BIGINT NOT NULL,
  municipio_id BIGINT NOT NULL,
  precio_km NUMERIC(8,2) DEFAULT 1.5 NOT NULL,
  precio_hora NUMERIC(8,2) DEFAULT 0.2 NOT NULL,
  created_at TIMESTAMP(0) DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at TIMESTAMP(0) DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT tarifas_pkey PRIMARY KEY (id),
  CONSTRAINT tarifas_provincia_id_foreign
    FOREIGN KEY (provincia_id) REFERENCES public.provincias(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT tarifas_municipio_id_foreign
    FOREIGN KEY (municipio_id) REFERENCES public.municipios(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT tarifas_municipio_id_unique UNIQUE (municipio_id),
  CONSTRAINT tarifas_precio_km_positive CHECK (precio_km > 0),
  CONSTRAINT tarifas_precio_hora_non_negative CHECK (precio_hora >= 0)
);

CREATE INDEX IF NOT EXISTS tarifas_provincia_idx ON public.tarifas (provincia_id);

CREATE OR REPLACE FUNCTION public.set_updated_at_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO public
AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tarifas_set_updated_at ON public.tarifas;
CREATE TRIGGER tarifas_set_updated_at
BEFORE UPDATE ON public.tarifas
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at_timestamp();

CREATE OR REPLACE FUNCTION public.trg_sync_tarifa_provincia_from_municipio()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO public
AS $$
DECLARE
  v_provincia_id BIGINT;
BEGIN
  SELECT m.provincia_id
  INTO v_provincia_id
  FROM public.municipios m
  WHERE m.id = NEW.municipio_id;

  IF v_provincia_id IS NULL THEN
    RAISE EXCEPTION 'Municipio % no existe o no tiene provincia asociada.', NEW.municipio_id;
  END IF;

  NEW.provincia_id := v_provincia_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tarifas_sync_provincia_from_municipio ON public.tarifas;
CREATE TRIGGER tarifas_sync_provincia_from_municipio
BEFORE INSERT OR UPDATE OF municipio_id ON public.tarifas
FOR EACH ROW
EXECUTE FUNCTION public.trg_sync_tarifa_provincia_from_municipio();

CREATE OR REPLACE FUNCTION public.is_cliente_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clientes c
    WHERE c.id = COALESCE(p_user_id, auth.uid())
      AND c.is_admin = TRUE
  );
$$;

CREATE OR REPLACE FUNCTION public.is_taxista_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.taxistas t
    WHERE t.id = COALESCE(p_user_id, auth.uid())
      AND t.is_admin = TRUE
  );
$$;

CREATE OR REPLACE FUNCTION public.is_app_admin(p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT public.is_cliente_admin(p_user_id) OR public.is_taxista_admin(p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.taxista_municipio_id(p_user_id UUID DEFAULT auth.uid())
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT t.municipio_id
  FROM public.taxistas t
  WHERE t.id = COALESCE(p_user_id, auth.uid())
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.can_manage_tarifa_municipio(
  p_user_id UUID,
  p_municipio_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT (
    public.is_cliente_admin(p_user_id)
    OR (
      public.is_taxista_admin(p_user_id)
      AND public.taxista_municipio_id(p_user_id) = p_municipio_id
    )
  );
$$;

ALTER TABLE public.tarifas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provincias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.municipios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tarifas_select_admin ON public.tarifas;
CREATE POLICY tarifas_select_admin
ON public.tarifas
FOR SELECT
TO authenticated
USING (public.is_app_admin(auth.uid()));

DROP POLICY IF EXISTS tarifas_insert_admin ON public.tarifas;
CREATE POLICY tarifas_insert_admin
ON public.tarifas
FOR INSERT
TO authenticated
WITH CHECK (public.can_manage_tarifa_municipio(auth.uid(), municipio_id));

DROP POLICY IF EXISTS tarifas_update_admin ON public.tarifas;
CREATE POLICY tarifas_update_admin
ON public.tarifas
FOR UPDATE
TO authenticated
USING (public.can_manage_tarifa_municipio(auth.uid(), municipio_id))
WITH CHECK (public.can_manage_tarifa_municipio(auth.uid(), municipio_id));

DROP POLICY IF EXISTS provincias_select_authenticated ON public.provincias;
CREATE POLICY provincias_select_authenticated
ON public.provincias
FOR SELECT
TO authenticated
USING (TRUE);

DROP POLICY IF EXISTS provincias_insert_admin ON public.provincias;
CREATE POLICY provincias_insert_admin
ON public.provincias
FOR INSERT
TO authenticated
WITH CHECK (public.is_app_admin(auth.uid()));

DROP POLICY IF EXISTS provincias_update_admin ON public.provincias;
CREATE POLICY provincias_update_admin
ON public.provincias
FOR UPDATE
TO authenticated
USING (public.is_app_admin(auth.uid()))
WITH CHECK (public.is_app_admin(auth.uid()));

DROP POLICY IF EXISTS municipios_select_authenticated ON public.municipios;
CREATE POLICY municipios_select_authenticated
ON public.municipios
FOR SELECT
TO authenticated
USING (TRUE);

DROP POLICY IF EXISTS municipios_insert_admin ON public.municipios;
CREATE POLICY municipios_insert_admin
ON public.municipios
FOR INSERT
TO authenticated
WITH CHECK (public.is_app_admin(auth.uid()));

DROP POLICY IF EXISTS municipios_update_admin ON public.municipios;
CREATE POLICY municipios_update_admin
ON public.municipios
FOR UPDATE
TO authenticated
USING (public.is_app_admin(auth.uid()))
WITH CHECK (public.is_app_admin(auth.uid()));

CREATE OR REPLACE FUNCTION public.get_tarifas_by_provincia(
  p_provincia_id BIGINT
)
RETURNS TABLE(
  id BIGINT,
  provincia_id BIGINT,
  municipio_id BIGINT,
  municipio_nombre VARCHAR,
  precio_km NUMERIC,
  precio_hora NUMERIC,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT
    t.id,
    t.provincia_id,
    t.municipio_id,
    m.nombre AS municipio_nombre,
    t.precio_km,
    t.precio_hora,
    t.created_at,
    t.updated_at
  FROM public.tarifas t
  JOIN public.municipios m ON m.id = t.municipio_id
  WHERE t.provincia_id = p_provincia_id
  ORDER BY m.nombre ASC;
$$;

CREATE OR REPLACE FUNCTION public.get_tarifa_by_city_or_default(
  p_ciudad_origen TEXT
)
RETURNS TABLE(
  municipio_id BIGINT,
  provincia_id BIGINT,
  precio_km NUMERIC,
  precio_hora NUMERIC,
  is_default BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_municipio_id BIGINT;
  v_provincia_id BIGINT;
  v_precio_km NUMERIC(8,2);
  v_precio_hora NUMERIC(8,2);
BEGIN
  SELECT m.id, m.provincia_id
  INTO v_municipio_id, v_provincia_id
  FROM public.municipios m
  WHERE lower(m.nombre) = lower(trim(COALESCE(p_ciudad_origen, '')))
  LIMIT 1;

  IF v_municipio_id IS NULL THEN
    RETURN QUERY SELECT NULL::BIGINT, NULL::BIGINT, 1.5::NUMERIC, 0.2::NUMERIC, TRUE;
    RETURN;
  END IF;

  SELECT t.precio_km, t.precio_hora
  INTO v_precio_km, v_precio_hora
  FROM public.tarifas t
  WHERE t.municipio_id = v_municipio_id
  LIMIT 1;

  IF v_precio_km IS NULL OR v_precio_hora IS NULL THEN
    RETURN QUERY SELECT v_municipio_id, v_provincia_id, 1.5::NUMERIC, 0.2::NUMERIC, TRUE;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_municipio_id, v_provincia_id, v_precio_km, v_precio_hora, FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_tarifa_municipio(
  p_municipio_id BIGINT,
  p_precio_km NUMERIC(8,2),
  p_precio_hora NUMERIC(8,2)
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  tarifa_id BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_provincia_id BIGINT;
  v_tarifa_id BIGINT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::BIGINT;
    RETURN;
  END IF;

  IF p_precio_km <= 0 THEN
    RETURN QUERY SELECT FALSE, 'precio_km debe ser mayor que cero', NULL::BIGINT;
    RETURN;
  END IF;

  IF p_precio_hora < 0 THEN
    RETURN QUERY SELECT FALSE, 'precio_hora no puede ser negativo', NULL::BIGINT;
    RETURN;
  END IF;

  IF NOT public.can_manage_tarifa_municipio(v_user_id, p_municipio_id) THEN
    RETURN QUERY SELECT FALSE, 'No tienes permisos para editar esta tarifa', NULL::BIGINT;
    RETURN;
  END IF;

  SELECT m.provincia_id INTO v_provincia_id
  FROM public.municipios m
  WHERE m.id = p_municipio_id;

  IF v_provincia_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Municipio no encontrado', NULL::BIGINT;
    RETURN;
  END IF;

  INSERT INTO public.tarifas (provincia_id, municipio_id, precio_km, precio_hora)
  VALUES (v_provincia_id, p_municipio_id, p_precio_km, p_precio_hora)
  ON CONFLICT (municipio_id)
  DO UPDATE SET
    precio_km = EXCLUDED.precio_km,
    precio_hora = EXCLUDED.precio_hora,
    updated_at = CURRENT_TIMESTAMP
  RETURNING id INTO v_tarifa_id;

  RETURN QUERY SELECT TRUE, 'Tarifa guardada correctamente', v_tarifa_id;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al guardar tarifa: ' || SQLERRM, NULL::BIGINT;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_driver_disponibilidad(
  p_estado public.estado_taxista
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT,
  estado public.estado_taxista
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado_actual public.estado_taxista;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_taxista;
    RETURN;
  END IF;

  SELECT t.estado INTO v_estado_actual
  FROM public.taxistas t
  WHERE t.id = v_user_id
  FOR UPDATE;

  IF v_estado_actual IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Solo los taxistas pueden cambiar disponibilidad', NULL::public.estado_taxista;
    RETURN;
  END IF;

  IF v_estado_actual = 'ocupado' THEN
    RETURN QUERY SELECT FALSE, 'No puedes cambiar tu estado mientras tienes un viaje activo', v_estado_actual;
    RETURN;
  END IF;

  IF p_estado NOT IN ('disponible'::public.estado_taxista, 'no disponible'::public.estado_taxista) THEN
    RETURN QUERY SELECT FALSE, 'Estado no permitido. Usa disponible o no disponible', v_estado_actual;
    RETURN;
  END IF;

  UPDATE public.taxistas
  SET estado = p_estado,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = v_user_id;

  IF p_estado = 'disponible' THEN
    UPDATE public.vehiculos
    SET disponible = TRUE,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = (SELECT vehiculo_id FROM public.taxistas WHERE id = v_user_id);
  ELSE
    UPDATE public.vehiculos
    SET disponible = FALSE,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = (SELECT vehiculo_id FROM public.taxistas WHERE id = v_user_id);
  END IF;

  RETURN QUERY SELECT TRUE, 'Estado actualizado correctamente', p_estado;
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al actualizar estado: ' || SQLERRM, NULL::public.estado_taxista;
END;
$$;

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
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_viaje;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado INTO v_estado
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
$$;

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
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_viaje;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado INTO v_estado
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
      ultimo_viaje = CURRENT_TIMESTAMP,
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
$$;

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
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_viaje;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida', NULL::public.estado_viaje;
    RETURN;
  END IF;

  SELECT v.estado INTO v_estado
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
$$;

CREATE OR REPLACE FUNCTION public.get_driver_dashboard_data(
  p_limit INTEGER DEFAULT 3
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_estado public.estado_taxista;
  v_viaje_activo JSONB;
  v_ultimos_viajes JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Sesion no valida',
      'estado_taxista', NULL,
      'viaje_activo', NULL,
      'ultimos_viajes', '[]'::jsonb
    );
  END IF;

  SELECT t.estado INTO v_estado
  FROM public.taxistas t
  WHERE t.id = v_user_id;

  IF v_estado IS NULL THEN
    RETURN jsonb_build_object(
      'success', FALSE,
      'message', 'Solo los taxistas tienen dashboard',
      'estado_taxista', NULL,
      'viaje_activo', NULL,
      'ultimos_viajes', '[]'::jsonb
    );
  END IF;

  SELECT to_jsonb(x)
  INTO v_viaje_activo
  FROM (
    SELECT
      v.id,
      v.estado,
      v.origen,
      v.destino,
      v.precio,
      v.pagado,
      v.distancia,
      v.duracion,
      v.created_at,
      v.fecha_recogida,
      v.fecha_entrega,
      u.nombre AS cliente_nombre,
      u.apellidos AS cliente_apellidos
    FROM public.viajes v
    LEFT JOIN public.usuarios u ON u.id = v.user_id
    WHERE v.driver_id = v_user_id
      AND v.estado IN ('pendiente', 'confirmada', 'en_curso')
    ORDER BY v.created_at DESC
    LIMIT 1
  ) x;

  SELECT COALESCE(jsonb_agg(to_jsonb(y)), '[]'::jsonb)
  INTO v_ultimos_viajes
  FROM (
    SELECT
      v.id,
      v.estado,
      v.origen,
      v.destino,
      v.precio,
      v.pagado,
      v.distancia,
      v.duracion,
      v.created_at,
      v.fecha_recogida,
      v.fecha_entrega,
      u.nombre AS cliente_nombre,
      u.apellidos AS cliente_apellidos
    FROM public.viajes v
    LEFT JOIN public.usuarios u ON u.id = v.user_id
    WHERE v.driver_id = v_user_id
    ORDER BY v.created_at DESC
    LIMIT GREATEST(COALESCE(p_limit, 3), 1)
  ) y;

  RETURN jsonb_build_object(
    'success', TRUE,
    'message', 'Dashboard cargado',
    'estado_taxista', v_estado,
    'viaje_activo', v_viaje_activo,
    'ultimos_viajes', v_ultimos_viajes
  );
END;
$$;

COMMIT;
