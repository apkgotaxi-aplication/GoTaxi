import { createClient } from 'npm:@supabase/supabase-js@2';

type RideEtaPayload = {
  ride_id?: string;
};

const GOOGLE_MAPS_API_KEY = Deno.env.get('GOOGLE_MAPS_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const adminSupabase =
  SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
    ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    : null;

const defaultHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

const MAX_CACHE_AGE_SECONDS = 60;
const MIN_MOVEMENT_FOR_REFRESH_METERS = 150;

function toNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const toRad = (value: number) => (value * Math.PI) / 180;
  const earthRadiusMeters = 6371000;
  const deltaLat = toRad(lat2 - lat1);
  const deltaLng = toRad(lng2 - lng1);
  const a =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(deltaLng / 2) ** 2;
  return 2 * earthRadiusMeters * Math.asin(Math.min(1, Math.sqrt(a)));
}

function parseTimestamp(value: unknown): Date | null {
  if (value === null || value === undefined) return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: defaultHeaders,
  });
}

async function fetchGoogleEtaMinutes(params: {
  driverLat: number;
  driverLng: number;
  originLat: number;
  originLng: number;
}): Promise<{ etaMin: number; providerUpdatedAt: Date }> {
  if (!GOOGLE_MAPS_API_KEY) {
    const distanceKm = haversineMeters(
      params.driverLat,
      params.driverLng,
      params.originLat,
      params.originLng,
    ) / 1000;
    return {
      etaMin: Math.max(1, Math.ceil(distanceKm / 0.45)),
      providerUpdatedAt: new Date(),
    };
  }

  const url = new URL('https://maps.googleapis.com/maps/api/distancematrix/json');
  url.searchParams.set('origins', `${params.driverLat},${params.driverLng}`);
  url.searchParams.set('destinations', `${params.originLat},${params.originLng}`);
  url.searchParams.set('mode', 'driving');
  url.searchParams.set('language', 'es');
  url.searchParams.set('departure_time', 'now');
  url.searchParams.set('traffic_model', 'best_guess');
  url.searchParams.set('key', GOOGLE_MAPS_API_KEY);

  try {
    const response = await fetch(url.toString());
    if (!response.ok) {
      throw new Error(`Google Maps devolvió ${response.status}`);
    }

    const data = await response.json();
    if (data.status !== 'OK') {
      const errorMessage = data.error_message ?? 'No se pudo calcular la ruta';
      throw new Error(String(errorMessage));
    }

    const row = data.rows?.[0]?.elements?.[0];
    if (!row || row.status !== 'OK') {
      throw new Error('No se pudo calcular el tiempo hasta el punto de origen');
    }

    const durationSeconds = toNumber(row.duration_in_traffic?.value) ?? toNumber(row.duration?.value);
    if (durationSeconds === null) {
      throw new Error('Google Maps no devolvió duración válida');
    }

    return {
      etaMin: Math.max(1, Math.ceil(durationSeconds / 60)),
      providerUpdatedAt: new Date(),
    };
  } catch (_) {
    const distanceKm = haversineMeters(
      params.driverLat,
      params.driverLng,
      params.originLat,
      params.originLng,
    ) / 1000;

    return {
      etaMin: Math.max(1, Math.ceil(distanceKm / 0.45)),
      providerUpdatedAt: new Date(),
    };
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: defaultHeaders });
  }

  try {
    if (!adminSupabase || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return jsonResponse({ available: false, message: 'Supabase no esta configurado correctamente' }, 500);
    }

    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.replace('Bearer ', '').trim()
      : null;

    if (!token) {
      return jsonResponse({ available: false, message: 'Authorization Bearer token requerido' }, 401);
    }

    const {
      data: { user },
      error: authError,
    } = await adminSupabase.auth.getUser(token);

    if (authError || !user) {
      return jsonResponse({ available: false, message: 'JWT invalido' }, 401);
    }

    const payload = (await req.json()) as RideEtaPayload;
    const rideId = payload.ride_id?.trim();

    if (!rideId) {
      return jsonResponse({ available: false, message: 'ride_id es requerido' }, 400);
    }

    const { data: ride, error: rideError } = await adminSupabase
      .from('viajes')
      .select(
        'id, estado, user_id, driver_id, origen_lat, origen_lng, eta_pickup_min, eta_pickup_updated_at, eta_pickup_driver_lat, eta_pickup_driver_lng',
      )
      .eq('id', rideId)
      .maybeSingle();

    if (rideError) {
      return jsonResponse({ available: false, message: rideError.message }, 500);
    }

    if (!ride) {
      return jsonResponse({ available: false, message: 'Viaje no encontrado' }, 404);
    }

    if (user.id !== ride.user_id && user.id !== ride.driver_id) {
      return jsonResponse({ available: false, message: 'No autorizado' }, 403);
    }

    if (String(ride.estado).toLowerCase().trim() !== 'confirmada') {
      return jsonResponse({ available: false, message: 'ETA disponible solo en confirmada' });
    }

    const originLat = toNumber(ride.origen_lat);
    const originLng = toNumber(ride.origen_lng);

    if (originLat === null || originLng === null) {
      return jsonResponse({ available: false, message: 'Origen sin coordenadas' });
    }

    const { data: driver, error: driverError } = await adminSupabase
      .from('taxistas')
      .select('lat, lng, ultima_actualizacion_ubicacion')
      .eq('id', ride.driver_id)
      .maybeSingle();

    if (driverError) {
      return jsonResponse({ available: false, message: driverError.message }, 500);
    }

    const driverLat = toNumber(driver?.lat);
    const driverLng = toNumber(driver?.lng);

    if (driverLat === null || driverLng === null) {
      return jsonResponse({ available: false, message: 'Ubicacion del taxista no disponible' });
    }

    const cacheUpdatedAt = parseTimestamp(ride.eta_pickup_updated_at);
    const cachedDriverLat = toNumber(ride.eta_pickup_driver_lat);
    const cachedDriverLng = toNumber(ride.eta_pickup_driver_lng);
    const cacheAgeSeconds = cacheUpdatedAt
      ? (Date.now() - cacheUpdatedAt.getTime()) / 1000
      : Number.POSITIVE_INFINITY;
    const movementMeters =
      cachedDriverLat !== null && cachedDriverLng !== null
        ? haversineMeters(cachedDriverLat, cachedDriverLng, driverLat, driverLng)
        : Number.POSITIVE_INFINITY;

    if (
      ride.eta_pickup_min !== null &&
      cacheAgeSeconds <= MAX_CACHE_AGE_SECONDS &&
      movementMeters <= MIN_MOVEMENT_FOR_REFRESH_METERS
    ) {
      return jsonResponse({
        available: true,
        eta_min: Number(ride.eta_pickup_min),
        ubicacion_actualizada_en: cacheUpdatedAt?.toISOString() ?? new Date().toISOString(),
        cached: true,
      });
    }

    const { etaMin, providerUpdatedAt } = await fetchGoogleEtaMinutes({
      driverLat,
      driverLng,
      originLat,
      originLng,
    });

    const { error: updateError } = await adminSupabase
      .from('viajes')
      .update({
        eta_pickup_min: etaMin,
        eta_pickup_updated_at: providerUpdatedAt.toISOString(),
        eta_pickup_driver_lat: driverLat,
        eta_pickup_driver_lng: driverLng,
      })
      .eq('id', rideId);

    if (updateError) {
      return jsonResponse({ available: false, message: updateError.message }, 500);
    }

    return jsonResponse({
      available: true,
      eta_min: etaMin,
      ubicacion_actualizada_en: providerUpdatedAt.toISOString(),
      cached: false,
    });
  } catch (error) {
    return jsonResponse(
      {
        available: false,
        message: error instanceof Error ? error.message : 'Error inesperado',
      },
      500,
    );
  }
});