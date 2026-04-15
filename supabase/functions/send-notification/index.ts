import { createClient } from 'npm:@supabase/supabase-js@2';

const ONESIGNAL_API_KEY =
  Deno.env.get('ONESIGNAL_REST_API_KEY') ?? Deno.env.get('ONESIGNAL_API_KEY');
const ONESIGNAL_APP_ID = Deno.env.get('ONESIGNAL_APP_ID');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const adminSupabase =
  SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
    ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    : null;

const defaultHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: defaultHeaders,
    });
  }

  try {
    console.log('Function send-notification called');
    console.log('SUPABASE_URL configured:', Boolean(SUPABASE_URL));
    console.log('SUPABASE_SERVICE_ROLE_KEY configured:', Boolean(SUPABASE_SERVICE_ROLE_KEY));
    console.log('ONESIGNAL_APP_ID configured:', Boolean(ONESIGNAL_APP_ID));
    console.log('ONESIGNAL_API_KEY configured:', Boolean(ONESIGNAL_API_KEY));

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !adminSupabase) {
      return new Response(
        JSON.stringify({ error: 'Supabase no esta configurado correctamente en la funcion' }),
        { status: 500, headers: defaultHeaders }
      );
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    console.log('Authorization header prefix:', authHeader.slice(0, 30));
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.replace('Bearer ', '').trim()
      : null;

    if (!token) {
      return new Response(
        JSON.stringify({ error: 'Authorization Bearer token requerido' }),
        { status: 401, headers: defaultHeaders }
      );
    }

    const {
      data: { user },
      error: authError,
    } = await adminSupabase.auth.getUser(token);

    if (authError || !user) {
      console.error('JWT validation error:', authError);
      return new Response(
        JSON.stringify({ error: 'JWT invalido' }),
        { status: 401, headers: defaultHeaders }
      );
    }

    const payload = await req.json();
    console.log('Incoming request payload:', JSON.stringify(payload));

    const { user_id, title, body, data } = payload;

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: 'user_id es requerido' }),
        { status: 400, headers: defaultHeaders }
      );
    }

    if (user.id !== user_id) {
      return new Response(
        JSON.stringify({ error: 'No autorizado para enviar push a otro usuario' }),
        { status: 403, headers: defaultHeaders }
      );
    }

    const { data: players, error: playerError } = await adminSupabase
      .from('user_onesignal_players')
      .select('onesignal_player_id')
      .eq('user_id', user_id)
      .maybeSingle();

    if (playerError) {
      console.error('Error fetching player:', playerError);
    }

    console.log('DB player row:', JSON.stringify(players));

    if (!ONESIGNAL_API_KEY || !ONESIGNAL_APP_ID) {
      console.error('OneSignal API key or App ID not configured');
      return new Response(
        JSON.stringify({
          error: 'OneSignal no esta configurado. Revisa ONESIGNAL_APP_ID y ONESIGNAL_REST_API_KEY',
        }),
        { status: 500, headers: defaultHeaders }
      );
    }

    const notificationPayload = {
      app_id: ONESIGNAL_APP_ID,
      data: data || {},
      headings: { en: title || 'GoTaxi' },
      contents: { en: body || '' },
    };

    const audience = players?.onesignal_player_id
      ? { include_subscription_ids: [players.onesignal_player_id] }
      : {
          include_aliases: { external_id: [user_id] },
          target_channel: 'push',
        };

    const requestBody = {
      ...notificationPayload,
      ...audience,
    };

    console.log('OneSignal target user:', user_id);
    console.log('OneSignal subscription_id:', players?.onesignal_player_id ?? null);
    console.log('OneSignal payload:', JSON.stringify(requestBody));

    const response = await fetch('https://api.onesignal.com/notifications?c=push', {
      method: 'POST',
      headers: {
        'Authorization': `key ${ONESIGNAL_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    });

    const rawResponse = await response.text();
    console.log('OneSignal response status:', response.status);
    console.log('OneSignal response body:', rawResponse);

    const result = rawResponse ? JSON.parse(rawResponse) : {};

    if (result.errors) {
      console.error('OneSignal error:', result.errors);
      return new Response(
        JSON.stringify({ success: false, error: result.errors }),
        { status: 500, headers: defaultHeaders }
      );
    }

    return new Response(
      JSON.stringify({ success: true, notification_id: result.id }),
      { headers: defaultHeaders }
    );

  } catch (error) {
    console.error('Error general:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: defaultHeaders }
    );
  }
});
