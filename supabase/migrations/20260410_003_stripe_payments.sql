BEGIN;

CREATE TABLE IF NOT EXISTS public.cliente_metodos_pago (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id UUID NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  stripe_customer_id TEXT NOT NULL,
  stripe_payment_method_id TEXT NOT NULL,
  brand TEXT,
  last4 TEXT,
  exp_month INTEGER,
  exp_year INTEGER,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT cliente_metodos_pago_method_unique UNIQUE (stripe_payment_method_id),
  CONSTRAINT cliente_metodos_pago_cliente_method_unique UNIQUE (cliente_id, stripe_payment_method_id)
);

DROP VIEW IF EXISTS public.cliente_metodos_de_pago;
CREATE VIEW public.cliente_metodos_de_pago AS
SELECT
  id,
  cliente_id,
  stripe_customer_id,
  stripe_payment_method_id,
  brand,
  last4,
  exp_month,
  exp_year,
  is_default,
  created_at,
  updated_at
FROM public.cliente_metodos_pago;

CREATE INDEX IF NOT EXISTS cliente_metodos_pago_cliente_idx
  ON public.cliente_metodos_pago (cliente_id, is_default DESC, created_at DESC);

ALTER TABLE public.clientes
  ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
  ADD COLUMN IF NOT EXISTS stripe_default_payment_method_id TEXT;

ALTER TABLE public.viajes
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS stripe_payment_status TEXT,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

ALTER TABLE public.cliente_metodos_pago ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cliente_metodos_pago_select_own ON public.cliente_metodos_pago;
CREATE POLICY cliente_metodos_pago_select_own
ON public.cliente_metodos_pago
FOR SELECT
TO authenticated
USING (cliente_id = auth.uid());

DROP POLICY IF EXISTS cliente_metodos_pago_insert_own ON public.cliente_metodos_pago;
CREATE POLICY cliente_metodos_pago_insert_own
ON public.cliente_metodos_pago
FOR INSERT
TO authenticated
WITH CHECK (cliente_id = auth.uid());

DROP POLICY IF EXISTS cliente_metodos_pago_update_own ON public.cliente_metodos_pago;
CREATE POLICY cliente_metodos_pago_update_own
ON public.cliente_metodos_pago
FOR UPDATE
TO authenticated
USING (cliente_id = auth.uid())
WITH CHECK (cliente_id = auth.uid());

DROP POLICY IF EXISTS cliente_metodos_pago_delete_own ON public.cliente_metodos_pago;
CREATE POLICY cliente_metodos_pago_delete_own
ON public.cliente_metodos_pago
FOR DELETE
TO authenticated
USING (cliente_id = auth.uid());

CREATE OR REPLACE FUNCTION public.get_my_payment_methods()
RETURNS TABLE(
  id UUID,
  cliente_id UUID,
  stripe_customer_id TEXT,
  stripe_payment_method_id TEXT,
  brand TEXT,
  last4 TEXT,
  exp_month INTEGER,
  exp_year INTEGER,
  is_default BOOLEAN,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT
    m.id,
    m.cliente_id,
    m.stripe_customer_id,
    m.stripe_payment_method_id,
    m.brand,
    m.last4,
    m.exp_month,
    m.exp_year,
    m.is_default,
    m.created_at,
    m.updated_at
  FROM public.cliente_metodos_pago m
  WHERE m.cliente_id = auth.uid()
  ORDER BY m.is_default DESC, m.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.set_default_payment_method(
  p_payment_method_id TEXT
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Sesion no valida';
    RETURN;
  END IF;

  UPDATE public.cliente_metodos_pago
  SET is_default = (stripe_payment_method_id = p_payment_method_id),
      updated_at = CURRENT_TIMESTAMP
  WHERE cliente_id = v_user_id;

  UPDATE public.clientes
  SET stripe_default_payment_method_id = p_payment_method_id
  WHERE id = v_user_id;

  RETURN QUERY SELECT TRUE, 'Metodo de pago actualizado correctamente';
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al actualizar metodo de pago: ' || SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_ride_payment_state(
  p_viaje_id UUID,
  p_cliente_id UUID
)
RETURNS TABLE(
  success BOOLEAN,
  mensaje TEXT,
  estado public.estado_viaje,
  pagado BOOLEAN,
  stripe_payment_status TEXT,
  stripe_payment_intent_id TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT
    TRUE,
    'Estado de pago cargado',
    v.estado,
    v.pagado,
    v.stripe_payment_status,
    v.stripe_payment_intent_id
  FROM public.viajes v
  WHERE v.id = p_viaje_id
    AND v.user_id = p_cliente_id;
$$;

CREATE OR REPLACE FUNCTION public.upsert_ride_payment_state(
  p_viaje_id UUID,
  p_stripe_payment_intent_id TEXT,
  p_stripe_payment_status TEXT,
  p_pagado BOOLEAN,
  p_paid_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE(
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
BEGIN
  UPDATE public.viajes
  SET stripe_payment_intent_id = p_stripe_payment_intent_id,
      stripe_payment_status = p_stripe_payment_status,
      pagado = p_pagado,
      paid_at = CASE WHEN p_pagado THEN COALESCE(paid_at, p_paid_at) ELSE paid_at END,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_viaje_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'Viaje no encontrado';
    RETURN;
  END IF;

  RETURN QUERY SELECT TRUE, 'Estado de pago actualizado correctamente';
EXCEPTION
  WHEN OTHERS THEN
    RETURN QUERY SELECT FALSE, 'Error al actualizar pago: ' || SQLERRM;
END;
$$;

COMMIT;