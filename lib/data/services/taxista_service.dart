import 'package:supabase_flutter/supabase_flutter.dart';

class TaxistaService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> createTaxista({
    required String nombre,
    required String apellidos,
    required String email,
    required String telefono,
    required String dni,
    required String contrasena,
    required int municipioId,
    required int capacidad,
    required bool isAdmin,
    required String licenciaTaxi,
    required String matricula,
    required String marca,
    required String modelo,
    required String color,
    required bool minusvalido,
  }) async {
    await _validateCreateTaxistaData(
      email: email,
      dni: dni,
      telefono: telefono,
      licenciaTaxi: licenciaTaxi,
      matricula: matricula,
      municipioId: municipioId,
    );

    String? userId;
    final normalizedEmail = email.trim().toLowerCase();

    try {
      // 1. Crear usuario en Auth
      final authResponse = await _supabase.auth.signUp(
        email: normalizedEmail,
        password: contrasena,
        data: {
          'nombre': nombre.trim(),
          'apellidos': apellidos.trim(),
          'telefono': telefono.trim(),
          'dni': dni.trim().toUpperCase(),
        },
      );

      if (authResponse.user == null) {
        throw Exception('No se pudo crear el usuario de autenticación');
      }

      userId = authResponse.user!.id;

      // 2. Convertir usuario creado a taxista en una única transacción SQL
      await _supabase.rpc(
        'create_taxista_profile',
        params: {
          'p_user_id': userId,
          'p_nombre': nombre,
          'p_apellidos': apellidos,
          'p_email': email,
          'p_telefono': telefono,
          'p_dni': dni,
          'p_municipio_id': municipioId,
          'p_licencia_taxi': licenciaTaxi,
          'p_matricula': matricula,
          'p_marca': marca,
          'p_modelo': modelo,
          'p_color': color,
          'p_capacidad': capacidad.toString(),
          'p_minusvalido': minusvalido,
          'p_is_admin': isAdmin,
        },
      );
    } on AuthException catch (e) {
      final error = e.message.toLowerCase();

      if (error.contains('already registered') ||
          error.contains('user already registered')) {
        await _supabase.rpc(
          'create_taxista_profile_by_email',
          params: {
            'p_email': normalizedEmail,
            'p_nombre': nombre,
            'p_apellidos': apellidos,
            'p_telefono': telefono,
            'p_dni': dni,
            'p_municipio_id': municipioId,
            'p_licencia_taxi': licenciaTaxi,
            'p_matricula': matricula,
            'p_marca': marca,
            'p_modelo': modelo,
            'p_color': color,
            'p_capacidad': capacidad.toString(),
            'p_minusvalido': minusvalido,
            'p_is_admin': isAdmin,
          },
        );
        return;
      }

      rethrow;
    } catch (e) {
      await _rollbackCreateTaxista(userId: userId);

      rethrow;
    }
  }

  Future<void> _validateCreateTaxistaData({
    required String email,
    required String dni,
    required String telefono,
    required String licenciaTaxi,
    required String matricula,
    required int municipioId,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedDni = dni.trim().toUpperCase();
    final normalizedTelefono = telefono.trim();
    final normalizedLicencia = licenciaTaxi.trim().toUpperCase();
    final normalizedMatricula = matricula.trim().toUpperCase();

    final existingByEmail = await _supabase
        .from('usuarios')
        .select('id')
        .ilike('email', normalizedEmail)
        .maybeSingle();
    if (existingByEmail != null) {
      throw Exception('usuarios_email_key: email duplicado');
    }

    final existingByDni = await _supabase
        .from('usuarios')
        .select('id')
        .eq('dni', normalizedDni)
        .maybeSingle();
    if (existingByDni != null) {
      throw Exception('usuarios_dni_key: dni duplicado');
    }

    if (normalizedTelefono.isNotEmpty) {
      final existingByTelefono = await _supabase
          .from('usuarios')
          .select('id')
          .eq('telefono', normalizedTelefono)
          .maybeSingle();
      if (existingByTelefono != null) {
        throw Exception('usuarios_telefono_key: telefono duplicado');
      }
    }

    final existingByLicencia = await _supabase
        .from('vehiculos')
        .select('id')
        .eq('licencia_taxi', normalizedLicencia)
        .maybeSingle();
    if (existingByLicencia != null) {
      throw Exception('vehiculos_licencia_taxi_key: licencia duplicada');
    }

    final existingByMatricula = await _supabase
        .from('vehiculos')
        .select('id')
        .eq('matricula', normalizedMatricula)
        .maybeSingle();
    if (existingByMatricula != null) {
      throw Exception('vehiculos_matricula_key: matricula duplicada');
    }

    final municipioExists = await _supabase
        .from('municipios')
        .select('id')
        .eq('id', municipioId)
        .maybeSingle();
    if (municipioExists == null) {
      throw Exception('taxistas_municipio_id_fkey: municipio inválido');
    }
  }

  Future<void> _rollbackCreateTaxista({required String? userId}) async {
    if (userId != null) {
      try {
        await _supabase.auth.admin.deleteUser(userId);
      } catch (_) {}
    }
  }

  Future<bool> isUserAdmin() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final response = await _supabase
          .from('taxistas')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();

      return response != null && response['is_admin'] == true;
    } catch (e) {
      return false;
    }
  }
}
