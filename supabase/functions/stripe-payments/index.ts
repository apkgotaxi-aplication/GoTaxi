import { createClient } from 'npm:@supabase/supabase-js@2';
import Stripe from 'npm:stripe@16.12.0';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY');
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET');
const ONESIGNAL_API_KEY = Deno.env.get('ONESIGNAL_REST_API_KEY') ?? Deno.env.get('ONESIGNAL_API_KEY');
const ONESIGNAL_APP_ID = Deno.env.get('ONESIGNAL_APP_ID');
const APP_DEEPLINK_BASE = (Deno.env.get('APP_DEEPLINK_BASE') ?? 'gotaxi://stripe').replace(/\/$/, '');

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
const supabaseAuth = createClient(supabaseUrl, supabaseAnonKey);

const stripe = STRIPE_SECRET_KEY
  ? new Stripe(STRIPE_SECRET_KEY, {
      apiVersion: '2024-06-20',
    })
  : null;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
};

function jsonResponse(body: unknown, init?: ResponseInit) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
      ...(init?.headers ?? {}),
    },
  });
}

function buildCheckoutReturnUrl(path: 'success' | 'cancel', params: Record<string, string>) {
  const query = new URLSearchParams(params);
  return `${APP_DEEPLINK_BASE}/${path}?${query.toString()}`;
}

async function getAuthenticatedUser(req: Request) {
  const authHeader = req.headers.get('authorization') ?? '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';

  if (!token) {
    return null;
  }

  const { data, error } = await supabaseAuth.auth.getUser(token);
  if (error || !data.user) {
    return null;
  }

  return {
    id: data.user.id,
    email: data.user.email ?? null,
  };
}

async function getOrCreateStripeCustomer(userId: string, email?: string | null) {
  const { data: cliente, error } = await supabase
    .from('clientes')
    .select('stripe_customer_id')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (cliente?.stripe_customer_id) {
    return cliente.stripe_customer_id as string;
  }

  if (!stripe) {
    throw new Error('Stripe no está configurado');
  }

  const customer = await stripe.customers.create({
    email: email ?? undefined,
    metadata: { user_id: userId },
  });

  await supabase.from('clientes').update({ stripe_customer_id: customer.id }).eq('id', userId);

  return customer.id;
}

async function createSetupSession(userId: string, email?: string | null) {
  if (!stripe) {
    throw new Error('Stripe no está configurado');
  }

  const customerId = await getOrCreateStripeCustomer(userId, email);
  const session = await stripe.checkout.sessions.create({
    mode: 'setup',
    customer: customerId,
    payment_method_types: ['card'],
    metadata: {
      user_id: userId,
      purpose: 'save_payment_method',
    },
    success_url: buildCheckoutReturnUrl('success', {
      flow: 'setup_method',
      session_id: '{CHECKOUT_SESSION_ID}',
    }),
    cancel_url: buildCheckoutReturnUrl('cancel', {
      flow: 'setup_method',
      session_id: '{CHECKOUT_SESSION_ID}',
    }),
  });

  return { checkout_url: session.url, checkout_session_id: session.id };
}

async function createRidePaymentSession(userId: string, rideId: string, email?: string | null) {
  if (!stripe) {
    throw new Error('Stripe no está configurado');
  }

  const { data: ride, error } = await supabase
    .from('viajes')
    .select('id, user_id, estado, precio, pagado')
    .eq('id', rideId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!ride) {
    throw new Error('Viaje no encontrado');
  }

  if (ride.user_id !== userId) {
    throw new Error('No tienes permiso para pagar este viaje');
  }

  if (ride.pagado === true) {
    throw new Error('Este viaje ya está pagado');
  }

  if (ride.estado !== 'en_curso') {
    throw new Error('Solo puedes pagar un viaje en curso');
  }

  const amount = Math.max(0, Math.round(Number(ride.precio ?? 0) * 100));
  if (amount < 1) {
    throw new Error('El importe del viaje no es válido');
  }

  const customerId = await getOrCreateStripeCustomer(userId, email ?? null);
  const session = await stripe.checkout.sessions.create({
    mode: 'payment',
    customer: customerId,
    payment_method_types: ['card'],
    line_items: [
      {
        quantity: 1,
        price_data: {
          currency: 'eur',
          unit_amount: amount,
          product_data: {
            name: 'Viaje GoTaxi',
            description: `Viaje ${rideId}`,
          },
        },
      },
    ],
    metadata: {
      user_id: userId,
      ride_id: rideId,
      purpose: 'ride_payment',
    },
    payment_intent_data: {
      metadata: {
        user_id: userId,
        ride_id: rideId,
      },
    },
    success_url: buildCheckoutReturnUrl('success', {
      flow: 'ride_payment',
      ride_id: rideId,
      session_id: '{CHECKOUT_SESSION_ID}',
    }),
    cancel_url: buildCheckoutReturnUrl('cancel', {
      flow: 'ride_payment',
      ride_id: rideId,
      session_id: '{CHECKOUT_SESSION_ID}',
    }),
  });

  return { checkout_url: session.url, checkout_session_id: session.id };
}

async function upsertSavedPaymentMethod(customerId: string, userId: string, paymentMethodId: string) {
  if (!stripe) {
    throw new Error('Stripe no está configurado');
  }

  const paymentMethod = await stripe.paymentMethods.retrieve(paymentMethodId);
  const card = paymentMethod.card;
  const now = new Date().toISOString();

  await supabase
    .from('cliente_metodos_pago')
    .update({ is_default: false, updated_at: now })
    .eq('cliente_id', userId);

  await supabase
    .from('cliente_metodos_pago')
    .upsert(
      {
        cliente_id: userId,
        stripe_customer_id: customerId,
        stripe_payment_method_id: paymentMethod.id,
        brand: card?.brand ?? null,
        last4: card?.last4 ?? null,
        exp_month: card?.exp_month ?? null,
        exp_year: card?.exp_year ?? null,
        is_default: true,
        updated_at: now,
      },
      { onConflict: 'stripe_payment_method_id' },
    );

  await supabase
    .from('clientes')
    .update({
      stripe_customer_id: customerId,
      stripe_default_payment_method_id: paymentMethod.id,
    })
    .eq('id', userId);
}

async function syncSavedPaymentMethodsFromStripe(userId: string) {
  if (!stripe) {
    throw new Error('Stripe no está configurado');
  }

  const { data: cliente, error } = await supabase
    .from('clientes')
    .select('stripe_customer_id, stripe_default_payment_method_id')
    .eq('id', userId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  const customerId = cliente?.stripe_customer_id?.toString().trim();
  if (!customerId) {
    return { synced: false, count: 0 };
  }

  const customer = await stripe.customers.retrieve(customerId);
  if ('deleted' in customer && customer.deleted) {
    return { synced: false, count: 0 };
  }

  const defaultPaymentMethodId = typeof customer.invoice_settings?.default_payment_method === 'string'
    ? customer.invoice_settings.default_payment_method
    : customer.invoice_settings?.default_payment_method?.id ?? cliente?.stripe_default_payment_method_id ?? null;

  const paymentMethods = await stripe.paymentMethods.list({
    customer: customerId,
    type: 'card',
    limit: 100,
  });

  const now = new Date().toISOString();

  await supabase
    .from('cliente_metodos_pago')
    .update({ is_default: false, updated_at: now })
    .eq('cliente_id', userId);

  for (const paymentMethod of paymentMethods.data) {
    const card = paymentMethod.card;
    await supabase
      .from('cliente_metodos_pago')
      .upsert(
        {
          cliente_id: userId,
          stripe_customer_id: customerId,
          stripe_payment_method_id: paymentMethod.id,
          brand: card?.brand ?? null,
          last4: card?.last4 ?? null,
          exp_month: card?.exp_month ?? null,
          exp_year: card?.exp_year ?? null,
          is_default: paymentMethod.id === defaultPaymentMethodId,
          updated_at: now,
        },
        { onConflict: 'stripe_payment_method_id' },
      );
  }

  if (defaultPaymentMethodId) {
    await supabase
      .from('clientes')
      .update({ stripe_default_payment_method_id: defaultPaymentMethodId })
      .eq('id', userId);
  }

  return {
    synced: true,
    count: paymentMethods.data.length,
    methods: paymentMethods.data.map((paymentMethod) => {
      const card = paymentMethod.card;
      return {
        stripe_payment_method_id: paymentMethod.id,
        brand: card?.brand ?? null,
        last4: card?.last4 ?? null,
        exp_month: card?.exp_month ?? null,
        exp_year: card?.exp_year ?? null,
        is_default: paymentMethod.id === defaultPaymentMethodId,
      };
    }),
  };
}

async function markRidePaid(rideId: string, paymentIntentId: string, paymentStatus: string) {
  const { data: ride, error } = await supabase
    .from('viajes')
    .select('estado')
    .eq('id', rideId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!ride) {
    throw new Error('Viaje no encontrado');
  }

  await supabase.rpc('upsert_ride_payment_state', {
    p_viaje_id: rideId,
    p_stripe_payment_intent_id: paymentIntentId,
    p_stripe_payment_status: paymentStatus,
    p_pagado: true,
    p_paid_at: new Date().toISOString(),
  });

  // Send notification for successful payment
  await sendRidePaymentNotification(rideId, true);
}

async function syncRidePaymentFromStripe(userId: string, rideId: string) {
  if (!stripe) {
    throw new Error('Stripe no está configurado');
  }

  const { data: ride, error } = await supabase
    .from('viajes')
    .select('id, user_id, stripe_payment_intent_id, pagado, stripe_payment_status, precio')
    .eq('id', rideId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!ride) {
    throw new Error('Viaje no encontrado');
  }

  if (ride.user_id !== userId) {
    throw new Error('No tienes permiso para consultar este viaje');
  }

  const paymentIntentId = ride.stripe_payment_intent_id?.toString().trim();
  if (paymentIntentId) {
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    const paymentStatus = paymentIntent.status;

    const shouldMarkPaid = paymentStatus === 'succeeded';

    if (shouldMarkPaid && ride.pagado !== true) {
      await markRidePaid(rideId, paymentIntent.id, paymentStatus);
      return { synced: true, paid: true, paymentStatus };
    }

    if (ride.stripe_payment_status !== paymentStatus) {
      await supabase
        .from('viajes')
        .update({
          stripe_payment_status: paymentStatus,
        })
        .eq('id', rideId);
    }

    // Send failed payment notification if payment failed
    if (!shouldMarkPaid && paymentStatus === 'canceled') {
      await sendRidePaymentNotification(rideId, false);
    }

    return { synced: true, paid: ride.pagado === true || shouldMarkPaid, paymentStatus };
  }

  const { data: cliente, error: customerError } = await supabase
    .from('clientes')
    .select('stripe_customer_id')
    .eq('id', userId)
    .maybeSingle();

  if (customerError) {
    throw customerError;
  }

  const customerId = cliente?.stripe_customer_id?.toString().trim();
  if (!customerId) {
    return { synced: false, paid: ride.pagado === true };
  }

  const paymentIntents = await stripe.paymentIntents.list({
    customer: customerId,
    limit: 10,
  });

  const matchingIntent = paymentIntents.data.find((intent) => {
    const intentRideId = intent.metadata?.ride_id ?? '';
    const intentUserId = intent.metadata?.user_id ?? '';
    return (
      intentRideId === rideId &&
      intentUserId === userId &&
      intent.status === 'succeeded'
    );
  });

  if (!matchingIntent) {
    return { synced: false, paid: ride.pagado === true };
  }

  const paymentStatus = matchingIntent.status;

  const shouldMarkPaid = paymentStatus === 'succeeded';

  if (shouldMarkPaid && ride.pagado !== true) {
    await markRidePaid(rideId, matchingIntent.id, paymentStatus);
    return { synced: true, paid: true, paymentStatus };
  }

  if (ride.stripe_payment_status !== paymentStatus) {
    await supabase
      .from('viajes')
      .update({
        stripe_payment_status: paymentStatus,
      })
      .eq('id', rideId);
  }

  return { synced: true, paid: ride.pagado === true || shouldMarkPaid, paymentStatus };
}

async function syncRidePaymentFromCheckoutSession(
  userId: string,
  rideId: string,
  checkoutSessionId: string,
) {
  if (!stripe) {
    throw new Error('Stripe no está configurado');
  }

  const session = await stripe.checkout.sessions.retrieve(checkoutSessionId, {
    expand: ['payment_intent'],
  });

  const sessionRideId = session.metadata?.ride_id ?? '';
  const sessionUserId = session.metadata?.user_id ?? '';

  if (sessionUserId && sessionUserId !== userId) {
    throw new Error('No tienes permiso para consultar esta sesión');
  }

  if (sessionRideId && sessionRideId !== rideId) {
    throw new Error('La sesión no corresponde a este viaje');
  }

  const paymentIntentId = typeof session.payment_intent === 'string'
    ? session.payment_intent
    : session.payment_intent?.id;

  const paymentStatus = session.payment_status ?? '';

  if (paymentStatus === 'paid' && paymentIntentId) {
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    if (paymentIntent.status === 'succeeded') {
      await markRidePaid(rideId, paymentIntent.id, paymentIntent.status);
      return { synced: true, paid: true, paymentStatus: paymentIntent.status };
    }

    await supabase
      .from('viajes')
      .update({ stripe_payment_status: paymentIntent.status })
      .eq('id', rideId);

    return { synced: true, paid: false, paymentStatus: paymentIntent.status };
  }

  if (paymentIntentId) {
    const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    if (paymentIntent.status === 'succeeded') {
      await markRidePaid(rideId, paymentIntent.id, paymentIntent.status);
      return { synced: true, paid: true, paymentStatus: paymentIntent.status };
    }

    await supabase
      .from('viajes')
      .update({ stripe_payment_status: paymentIntent.status })
      .eq('id', rideId);

    return { synced: true, paid: false, paymentStatus: paymentIntent.status };
  }

  return { synced: true, paid: false, paymentStatus };
}

async function sendRidePaymentNotification(rideId: string, paid: boolean) {
  if (!ONESIGNAL_API_KEY || !ONESIGNAL_APP_ID) {
    console.log('OneSignal not configured, skipping push notification');
    return;
  }

  try {
    const { data: ride, error } = await supabase
      .from('viajes')
      .select('user_id, driver_id, precio')
      .eq('id', rideId)
      .maybeSingle();

    if (error || !ride) {
      console.error('Error fetching ride for notification:', error);
      return;
    }

    const onesignalPayload = (userId: string, title: string, body: string, tipo: string) => ({
      app_id: ONESIGNAL_APP_ID,
      headings: { en: title },
      contents: { en: body },
      data: { viaje_id: rideId, tipo },
      ...(ride.user_id === userId
        ? { include_aliases: { external_id: [userId] }, target_channel: 'push' }
        : { include_aliases: { external_id: [userId] }, target_channel: 'push' }),
    });

    const notifications = [];

    if (paid) {
      // Notify client - payment successful
      notifications.push({
        ...onesignalPayload(ride.user_id, 'Pago confirmado', 'Gracias por tu pago. El taxista ha sido notificado.', 'pago_exitoso'),
      });

      // Notify driver - payment received
      if (ride.driver_id) {
        notifications.push({
          ...onesignalPayload(ride.driver_id, 'Viaje pagado', `El cliente ha pagado ${(ride.precio ?? 0).toFixed(2)}€ del viaje.`, 'pago_recibido'),
        });
      }
    } else {
      // Notify client - payment failed
      notifications.push({
        ...onesignalPayload(ride.user_id, 'Pago fallido', 'Hubo un problema con tu pago. Por favor, inténtalo de nuevo.', 'pago_fallido'),
      });
    }

    for (const notification of notifications) {
      try {
        const response = await fetch('https://api.onesignal.com/notifications?c=push', {
          method: 'POST',
          headers: {
            'Authorization': `key ${ONESIGNAL_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(notification),
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error('OneSignal notification error:', errorText);
        }
      } catch (err) {
        console.error('Error sending OneSignal notification:', err);
      }
    }
  } catch (err) {
    console.error('Error in sendRidePaymentNotification:', err);
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (!stripe) {
    return jsonResponse({ success: false, message: 'Stripe no está configurado' }, { status: 500 });
  }

  if (req.method === 'POST' && req.headers.get('stripe-signature')) {
    const body = await req.text();
    const signature = req.headers.get('stripe-signature');

    if (!STRIPE_WEBHOOK_SECRET || !signature) {
      return jsonResponse({ success: false, message: 'Webhook no configurado' }, { status: 500 });
    }

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(body, signature, STRIPE_WEBHOOK_SECRET);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Firma invalida';
      return jsonResponse({ success: false, message }, { status: 400 });
    }

    try {
      if (event.type === 'checkout.session.completed') {
        const session = event.data.object as Stripe.Checkout.Session;
        const userId = session.metadata?.user_id ?? '';
        const purpose = session.metadata?.purpose ?? '';
        const customerId = typeof session.customer === 'string' ? session.customer : session.customer?.id;

        if (!userId || !customerId) {
          return jsonResponse({ success: false, message: 'Sesion incompleta' }, { status: 400 });
        }

        if (purpose === 'save_payment_method') {
          const setupIntentId = typeof session.setup_intent === 'string'
            ? session.setup_intent
            : session.setup_intent?.id;

          if (!setupIntentId) {
            return jsonResponse({ success: false, message: 'Setup intent no encontrado' }, { status: 400 });
          }

          const setupIntent = await stripe.setupIntents.retrieve(setupIntentId, {
            expand: ['payment_method'],
          });

          const paymentMethodId = typeof setupIntent.payment_method === 'string'
            ? setupIntent.payment_method
            : setupIntent.payment_method?.id;

          if (!paymentMethodId) {
            return jsonResponse({ success: false, message: 'Metodo de pago no encontrado' }, { status: 400 });
          }

          await upsertSavedPaymentMethod(customerId, userId, paymentMethodId);
        }

        if (purpose === 'ride_payment') {
          const rideId = session.metadata?.ride_id ?? '';
          const paymentIntentId = typeof session.payment_intent === 'string'
            ? session.payment_intent
            : session.payment_intent?.id;

          if (rideId && paymentIntentId) {
            const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
            await markRidePaid(rideId, paymentIntent.id, paymentIntent.status);
          }
        }
      }

      return jsonResponse({ success: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Error inesperado en webhook';
      return jsonResponse({ success: false, message }, { status: 500 });
    }
  }

  if (req.method !== 'POST') {
    return jsonResponse({ success: false, message: 'Metodo no permitido' }, { status: 405 });
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) {
      return jsonResponse({ success: false, message: 'Sesion no valida' }, { status: 401 });
    }

    const payload = await req.json();
    const action = (payload.action ?? '').toString();

    if (action === 'setup_method') {
      const result = await createSetupSession(user.id, user.email ?? null);
      return jsonResponse({ success: true, ...result });
    }

    if (action === 'sync_payment_methods') {
      const result = await syncSavedPaymentMethodsFromStripe(user.id);
      return jsonResponse({ success: true, ...result });
    }

    if (action === 'pay_ride') {
      const rideId = (payload.ride_id ?? '').toString();
      if (!rideId) {
        return jsonResponse({ success: false, message: 'ride_id es requerido' }, { status: 400 });
      }

      const result = await createRidePaymentSession(user.id, rideId, user.email ?? null);
      return jsonResponse({ success: true, ...result });
    }

    if (action === 'sync_ride_payment') {
      const rideId = (payload.ride_id ?? '').toString();
      if (!rideId) {
        return jsonResponse({ success: false, message: 'ride_id es requerido' }, { status: 400 });
      }

      const checkoutSessionId = (payload.checkout_session_id ?? '').toString().trim();

      if (checkoutSessionId) {
        const result = await syncRidePaymentFromCheckoutSession(user.id, rideId, checkoutSessionId);
        return jsonResponse({ success: true, ...result });
      }

      const result = await syncRidePaymentFromStripe(user.id, rideId);
      return jsonResponse({ success: true, ...result });
    }

    return jsonResponse({ success: false, message: 'Accion no soportada' }, { status: 400 });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Error inesperado';
    return jsonResponse({ success: false, message }, { status: 500 });
  }
});