BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_taxista') THEN
    CREATE TYPE public.estado_taxista AS ENUM ('disponible', 'no disponible', 'ocupado');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.provincias (
  id BIGSERIAL PRIMARY KEY,
  nombre VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS public.municipios (
  id BIGSERIAL PRIMARY KEY,
  provincia_id BIGINT NOT NULL REFERENCES public.provincias(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  nombre VARCHAR(255) NOT NULL,
  latitud NUMERIC(10,7) NOT NULL,
  longitud NUMERIC(10,7) NOT NULL,
  CONSTRAINT municipios_provincia_nombre_unique UNIQUE (provincia_id, nombre)
);

CREATE TABLE IF NOT EXISTS public.vehiculos (
  id BIGSERIAL NOT NULL,
  licencia_taxi VARCHAR(255) NOT NULL,
  matricula VARCHAR(255) NOT NULL,
  marca VARCHAR(255) NOT NULL,
  modelo VARCHAR(255) NOT NULL,
  disponible BOOLEAN DEFAULT TRUE NOT NULL,
  color VARCHAR(255) NOT NULL,
  minusvalido BOOLEAN NOT NULL,
  capacidad VARCHAR(255) NOT NULL,
  created_at TIMESTAMP(0),
  updated_at TIMESTAMP(0),
  deleted_at TIMESTAMP(0),
  CONSTRAINT vehiculos_pkey PRIMARY KEY (id),
  CONSTRAINT vehiculos_licencia_taxi_unique UNIQUE (licencia_taxi),
  CONSTRAINT vehiculos_matricula_unique UNIQUE (matricula)
);

ALTER TABLE public.clientes
  ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
DECLARE
  taxistas_count BIGINT;
  taxistas_id_is_uuid BOOLEAN;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'taxistas'
  ) THEN
    SELECT COUNT(*) INTO taxistas_count FROM public.taxistas;

    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'taxistas'
        AND column_name = 'id'
        AND data_type = 'uuid'
    ) INTO taxistas_id_is_uuid;

    IF NOT taxistas_id_is_uuid THEN
      IF taxistas_count > 0 THEN
        RAISE EXCEPTION 'No se puede migrar taxistas.id de bigint a uuid porque hay % filas. Vacía/migra la tabla primero.', taxistas_count;
      END IF;

      DROP TABLE public.taxistas;
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'taxistas'
  ) THEN
    CREATE TABLE public.taxistas (
      id UUID NOT NULL,
      estado public.estado_taxista NOT NULL DEFAULT 'no disponible',
      created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
      vehiculo_id BIGINT NOT NULL,
      ultimo_viaje TIMESTAMP WITHOUT TIME ZONE,
      municipio_id BIGINT,
      lat NUMERIC,
      lng NUMERIC,
      ultima_actualizacion_ubicacion TIMESTAMP WITHOUT TIME ZONE,
      updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
      is_admin BOOLEAN NOT NULL DEFAULT FALSE,
      CONSTRAINT taxistas_pkey PRIMARY KEY (id),
      CONSTRAINT taxistas_id_fkey FOREIGN KEY (id) REFERENCES public.usuarios(id) ON UPDATE CASCADE ON DELETE CASCADE,
      CONSTRAINT taxistas_vehiculo_id_fkey FOREIGN KEY (vehiculo_id) REFERENCES public.vehiculos(id) ON UPDATE CASCADE ON DELETE RESTRICT,
      CONSTRAINT taxistas_municipio_id_fkey FOREIGN KEY (municipio_id) REFERENCES public.municipios(id) ON UPDATE CASCADE ON DELETE RESTRICT
    );
  ELSE
    ALTER TABLE public.taxistas
      ADD COLUMN IF NOT EXISTS vehiculo_id BIGINT,
      ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS municipio_id BIGINT;

    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.table_constraints
      WHERE table_schema = 'public' AND table_name = 'taxistas' AND constraint_name = 'taxistas_id_fkey'
    ) THEN
      ALTER TABLE public.taxistas
        ADD CONSTRAINT taxistas_id_fkey
          FOREIGN KEY (id) REFERENCES public.usuarios(id) ON UPDATE CASCADE ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.table_constraints
      WHERE table_schema = 'public' AND table_name = 'taxistas' AND constraint_name = 'taxistas_vehiculo_id_fkey'
    ) THEN
      ALTER TABLE public.taxistas
        ADD CONSTRAINT taxistas_vehiculo_id_fkey
          FOREIGN KEY (vehiculo_id) REFERENCES public.vehiculos(id) ON UPDATE CASCADE ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.table_constraints
      WHERE table_schema = 'public' AND table_name = 'taxistas' AND constraint_name = 'taxistas_municipio_id_fkey'
    ) THEN
      ALTER TABLE public.taxistas
        ADD CONSTRAINT taxistas_municipio_id_fkey
          FOREIGN KEY (municipio_id) REFERENCES public.municipios(id) ON UPDATE CASCADE ON DELETE RESTRICT;
    END IF;

    SELECT COUNT(*) INTO taxistas_count FROM public.taxistas WHERE vehiculo_id IS NULL;
    IF taxistas_count = 0 THEN
      ALTER TABLE public.taxistas ALTER COLUMN vehiculo_id SET NOT NULL;
    END IF;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.enforce_usuario_perfil_xor(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  perfiles_count INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.usuarios WHERE id = p_user_id) THEN
    RETURN;
  END IF;

  SELECT
    (CASE WHEN EXISTS (SELECT 1 FROM public.clientes c WHERE c.id = p_user_id) THEN 1 ELSE 0 END)
    +
    (CASE WHEN EXISTS (SELECT 1 FROM public.taxistas t WHERE t.id = p_user_id) THEN 1 ELSE 0 END)
  INTO perfiles_count;

  IF perfiles_count <> 1 THEN
    RAISE EXCEPTION 'El usuario % debe pertenecer exactamente a un perfil (clientes XOR taxistas).', p_user_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_check_usuario_perfil_xor()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  target_user_id UUID;
BEGIN
  IF TG_TABLE_NAME = 'usuarios' THEN
    target_user_id := NEW.id;
  ELSIF TG_OP = 'DELETE' THEN
    target_user_id := OLD.id;
  ELSE
    target_user_id := NEW.id;
  END IF;

  PERFORM public.enforce_usuario_perfil_xor(target_user_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS usuarios_profile_xor_check ON public.usuarios;
CREATE CONSTRAINT TRIGGER usuarios_profile_xor_check
AFTER INSERT OR UPDATE OF id ON public.usuarios
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_usuario_perfil_xor();

DROP TRIGGER IF EXISTS clientes_profile_xor_check ON public.clientes;
CREATE CONSTRAINT TRIGGER clientes_profile_xor_check
AFTER INSERT OR UPDATE OR DELETE ON public.clientes
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_usuario_perfil_xor();

DROP TRIGGER IF EXISTS taxistas_profile_xor_check ON public.taxistas;
CREATE CONSTRAINT TRIGGER taxistas_profile_xor_check
AFTER INSERT OR UPDATE OR DELETE ON public.taxistas
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.trg_check_usuario_perfil_xor();

CREATE OR REPLACE FUNCTION public.trg_sync_rol_desde_perfil()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_TABLE_NAME = 'clientes' THEN
    UPDATE public.usuarios SET rol = 'cliente' WHERE id = NEW.id;
  ELSIF TG_TABLE_NAME = 'taxistas' THEN
    UPDATE public.usuarios SET rol = 'taxista' WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS clientes_sync_rol ON public.clientes;
CREATE TRIGGER clientes_sync_rol
AFTER INSERT ON public.clientes
FOR EACH ROW
EXECUTE FUNCTION public.trg_sync_rol_desde_perfil();

DROP TRIGGER IF EXISTS taxistas_sync_rol ON public.taxistas;
CREATE TRIGGER taxistas_sync_rol
AFTER INSERT ON public.taxistas
FOR EACH ROW
EXECUTE FUNCTION public.trg_sync_rol_desde_perfil();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.usuarios (id, nombre, apellidos, email, telefono, dni, rol)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nombre', 'Sin nombre'),
    COALESCE(NEW.raw_user_meta_data->>'apellidos', 'Sin apellidos'),
    NEW.email,
    NULLIF(NEW.raw_user_meta_data->>'telefono', ''),
    NULLIF(UPPER(TRIM(NEW.raw_user_meta_data->>'dni')), ''),
    'cliente'
  );

  INSERT INTO public.clientes (id, is_admin)
  VALUES (NEW.id, FALSE)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'Error en registro de usuario: %', SQLERRM;
END;
$function$;

COMMIT;
