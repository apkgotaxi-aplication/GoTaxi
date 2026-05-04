-- Agregar columna 'activo' a la tabla taxistas para soft delete
-- Esto permite desactivar taxistas sin perder datos históricos

ALTER TABLE IF EXISTS public.taxistas
ADD COLUMN IF NOT EXISTS activo BOOLEAN NOT NULL DEFAULT TRUE;

-- Crear RPC para desactivar un taxista de forma segura
CREATE OR REPLACE FUNCTION public.deactivate_taxista(p_taxista_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Actualizar el estado del taxista a no disponible y marcarlo como inactivo
  UPDATE public.taxistas
  SET 
    activo = FALSE,
    estado = 'no disponible'::estado_taxista,
    updated_at = CURRENT_TIMESTAMP
  WHERE id = p_taxista_id;

  -- Opcionalmente, desactivar la cuenta de usuario
  UPDATE public.usuarios
  SET raw_user_meta_data = jsonb_set(
    COALESCE(raw_user_meta_data, '{}'::jsonb),
    '{activo}',
    'false'::jsonb
  )
  WHERE id = p_taxista_id;
END;
$$;

-- Comentario para documentación
COMMENT ON COLUMN public.taxistas.activo IS 'Indica si el taxista está activo (true) o desactivado (false). Soft delete para mantener referencia histórica de viajes.';
COMMENT ON FUNCTION public.deactivate_taxista(UUID) IS 'Desactiva un taxista sin eliminar datos históricos. Permite mantener referencias a viajes pasados.';
