import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

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
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return new Response(
        JSON.stringify({ error: 'Supabase no está configurado correctamente en la función' }),
        { status: 500, headers: defaultHeaders }
      );
    }

    const adminSupabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.replace('Bearer ', '').trim()
      : null;

    if (!token) {
      return new Response(
        JSON.stringify({ error: 'Token de autorización requerido' }),
        { status: 401, headers: defaultHeaders }
      );
    }

    const {
      data: { user },
      error: authError,
    } = await adminSupabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Token inválido' }),
        { status: 401, headers: defaultHeaders }
      );
    }

    const {
      data: isAdminCheck,
      error: adminCheckError,
    } = await adminSupabase
      .from('clientes')
      .select('is_admin')
      .eq('id', user.id)
      .maybeSingle();

    const taxistaAdminCheck = await adminSupabase
      .from('taxistas')
      .select('is_admin')
      .eq('id', user.id)
      .maybeSingle();

    const isUserAdmin =
      isAdminCheck?.is_admin === true || taxistaAdminCheck.data?.is_admin === true;

    if (!isUserAdmin) {
      return new Response(
        JSON.stringify({ error: 'Solo los administradores pueden crear taxistas' }),
        { status: 403, headers: defaultHeaders }
      );
    }

    const payload = await req.json();

    const {
      nombre,
      apellidos,
      email,
      telefono,
      dni,
      contrasena,
      municipio_id,
      licencia_taxi,
      matricula,
      marca,
      modelo,
      color,
      capacidad,
      minusvalido,
      is_admin,
    } = payload;

    const requiredFields = {
      nombre,
      apellidos,
      email,
      telefono,
      dni,
      contrasena,
      municipio_id,
      licencia_taxi,
      matricula,
      marca,
      modelo,
      color,
      capacidad,
    };

    for (const [field, value] of Object.entries(requiredFields)) {
      if (value === undefined || value === null || String(value).trim() === '') {
        return new Response(
          JSON.stringify({ error: `Campo ${field} es requerido` }),
          { status: 400, headers: defaultHeaders }
        );
      }
    }

    const normalizedEmail = String(email).trim().toLowerCase();
    const normalizedDni = String(dni).trim().toUpperCase();
    const normalizedTelefono = String(telefono).trim();
    const normalizedLicencia = String(licencia_taxi).trim().toUpperCase();
    const normalizedMatricula = String(matricula).trim().toUpperCase();

    const existingByEmail = await adminSupabase
      .from('usuarios')
      .select('id')
      .ilike('email', normalizedEmail)
      .maybeSingle();

    if (existingByEmail.data) {
      return new Response(
        JSON.stringify({ error: 'usuarios_email_key: email duplicado' }),
        { status: 409, headers: defaultHeaders }
      );
    }

    const existingByDni = await adminSupabase
      .from('usuarios')
      .select('id')
      .eq('dni', normalizedDni)
      .maybeSingle();

    if (existingByDni.data) {
      return new Response(
        JSON.stringify({ error: 'usuarios_dni_key: dni duplicado' }),
        { status: 409, headers: defaultHeaders }
      );
    }

    if (normalizedTelefono.length > 0) {
      const existingByTelefono = await adminSupabase
        .from('usuarios')
        .select('id')
        .eq('telefono', normalizedTelefono)
        .maybeSingle();

      if (existingByTelefono.data) {
        return new Response(
          JSON.stringify({ error: 'usuarios_telefono_key: telefono duplicado' }),
          { status: 409, headers: defaultHeaders }
        );
      }
    }

    const existingByLicencia = await adminSupabase
      .from('vehiculos')
      .select('id')
      .eq('licencia_taxi', normalizedLicencia)
      .maybeSingle();

    if (existingByLicencia.data) {
      return new Response(
        JSON.stringify({ error: 'vehiculos_licencia_taxi_key: licencia duplicada' }),
        { status: 409, headers: defaultHeaders }
      );
    }

    const existingByMatricula = await adminSupabase
      .from('vehiculos')
      .select('id')
      .eq('matricula', normalizedMatricula)
      .maybeSingle();

    if (existingByMatricula.data) {
      return new Response(
        JSON.stringify({ error: 'vehiculos_matricula_key: matricula duplicada' }),
        { status: 409, headers: defaultHeaders }
      );
    }

    const municipioExists = await adminSupabase
      .from('municipios')
      .select('id')
      .eq('id', municipio_id)
      .maybeSingle();

    if (!municipioExists.data) {
      return new Response(
        JSON.stringify({ error: 'taxistas_municipio_id_fkey: municipio inválido' }),
        { status: 400, headers: defaultHeaders }
      );
    }

    const { data: userData, error: userError } = await adminSupabase.auth.admin.createUser({
      email: normalizedEmail,
      password: contrasena,
      email_confirm: true,
      user_metadata: {
        nombre: String(nombre).trim(),
        apellidos: String(apellidos).trim(),
        telefono: normalizedTelefono,
        dni: normalizedDni,
      },
    });

    if (userError) {
      const lowerMsg = userError.message.toLowerCase();
      if (lowerMsg.includes('already registered') || lowerMsg.includes('user already')) {
        return new Response(
          JSON.stringify({ error: 'user_already_registered: este correo ya está registrado' }),
          { status: 409, headers: defaultHeaders }
        );
      }
      return new Response(
        JSON.stringify({ error: userError.message }),
        { status: 400, headers: defaultHeaders }
      );
    }

    const userId = userData.user.id;

    const { error: profileError } = await adminSupabase.rpc('create_taxista_profile', {
      p_user_id: userId,
      p_nombre: String(nombre).trim(),
      p_apellidos: String(apellidos).trim(),
      p_email: normalizedEmail,
      p_telefono: normalizedTelefono,
      p_dni: normalizedDni,
      p_municipio_id: municipio_id,
      p_licencia_taxi: normalizedLicencia,
      p_matricula: normalizedMatricula,
      p_marca: String(marca).trim(),
      p_modelo: String(modelo).trim(),
      p_color: String(color).trim(),
      p_capacidad: String(capacidad),
      p_minusvalido: minusvalido ?? false,
      p_is_admin: is_admin ?? false,
    });

    if (profileError) {
      await adminSupabase.auth.admin.deleteUser(userId);

      const lowerMsg = profileError.message.toLowerCase();
      if (
        lowerMsg.includes('duplicate') ||
        lowerMsg.includes('unique') ||
        lowerMsg.includes('key')
      ) {
        if (lowerMsg.includes('dni') || lowerMsg.includes('dni_key')) {
          return new Response(
            JSON.stringify({ error: 'usuarios_dni_key: dni duplicado' }),
            { status: 409, headers: defaultHeaders }
          );
        }
        if (lowerMsg.includes('telefono')) {
          return new Response(
            JSON.stringify({ error: 'usuarios_telefono_key: telefono duplicado' }),
            { status: 409, headers: defaultHeaders }
          );
        }
        if (lowerMsg.includes('licencia')) {
          return new Response(
            JSON.stringify({ error: 'vehiculos_licencia_taxi_key: licencia duplicada' }),
            { status: 409, headers: defaultHeaders }
          );
        }
        if (lowerMsg.includes('matricula')) {
          return new Response(
            JSON.stringify({ error: 'vehiculos_matricula_key: matricula duplicada' }),
            { status: 409, headers: defaultHeaders }
          );
        }
      }

      return new Response(
        JSON.stringify({ error: profileError.message }),
        { status: 400, headers: defaultHeaders }
      );
    }

    return new Response(
      JSON.stringify({ success: true, user_id: userId }),
      { status: 200, headers: defaultHeaders }
    );
  } catch (error) {
    console.error('Error en create-taxista:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: defaultHeaders }
    );
  }
});
