import { createClient } from 'npm:@supabase/supabase-js@2';

const ONESIGNAL_API_KEY = Deno.env.get('ONESIGNAL_API_KEY');
const ONESIGNAL_APP_ID = Deno.env.get('ONESIGNAL_APP_ID');

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  try {
    const { user_id, title, body, data, tipo } = await req.json();

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: 'user_id es requerido' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const { data: players, error: playerError } = await supabase
      .from('user_onesignal_players')
      .select('onesignal_player_id')
      .eq('user_id', user_id)
      .maybeSingle();

    if (playerError) {
      console.error('Error fetching player:', playerError);
    }

    if (!players?.onesignal_player_id) {
      return new Response(
        JSON.stringify({ success: false, message: 'No se encontró player_id para el usuario' }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }

    if (!ONESIGNAL_API_KEY || !ONESIGNAL_APP_ID) {
      console.error('OneSignal API key or App ID not configured');
      return new Response(
        JSON.stringify({ error: 'OneSignal no está configurado' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const notificationPayload = {
      app_id: ONESIGNAL_APP_ID,
      include_player_ids: [players.onesignal_player_id],
      headings: { en: title || 'GoTaxi' },
      contents: { en: body || '' },
      data: data || {},
      small_icon: 'ic_notification_icon',
    };

    const response = await fetch('https://onesignal.com/api/v1/notifications', {
      method: 'POST',
      headers: {
        'Authorization': `Key ${ONESIGNAL_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(notificationPayload),
    });

    const result = await response.json();

    if (result.errors) {
      console.error('OneSignal error:', result.errors);
      return new Response(
        JSON.stringify({ success: false, error: result.errors }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, notification_id: result.id }),
      { headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error general:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
