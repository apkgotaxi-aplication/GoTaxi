import 'package:supabase_flutter/supabase_flutter.dart';

class TaxistaService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> createTaxista({
    required String nombre,
    required String apellidos,
    required String email,
    required String telefono,
    required String dni,
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
    try {
      // 1. Crear usuario en Auth
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: _generateSecurePassword(),
      );

      if (authResponse.user == null) {
        throw Exception('No se pudo crear el usuario de autenticación');
      }

      final userId = authResponse.user!.id;

      // 2. Crear registro en tabla usuarios
      await _supabase.from('usuarios').insert({
        'id': userId,
        'nombre': nombre,
        'apellidos': apellidos,
        'email': email,
        'telefono': telefono,
        'dni': dni.toUpperCase(),
        'rol': 'taxista',
      });

      // 3. Crear vehículo
      final vehiculoResponse = await _supabase
          .from('vehiculos')
          .insert({
            'licencia_taxi': licenciaTaxi,
            'matricula': matricula.toUpperCase(),
            'marca': marca,
            'modelo': modelo,
            'color': color,
            'disponible': true,
            'minusvalido': minusvalido,
            'capacidad': capacidad.toString(),
          })
          .select()
          .single();

      final vehiculoId = vehiculoResponse['id'];

      // 4. Crear taxista
      await _supabase.from('taxistas').insert({
        'id': userId,
        'vehiculo_id': vehiculoId,
        'municipio_id': municipioId,
        'estado': 'disponible',
        'is_admin': isAdmin,
      });
    } catch (e) {
      rethrow;
    }
  }

  String _generateSecurePassword() {
    const chars =
        'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz0123456789!@#\$%^&*';
    final random = DateTime.now().millisecondsSinceEpoch;
    final password = String.fromCharCodes(
      List.generate(
        16,
        (index) => chars.codeUnitAt(random + index) % chars.length,
      ),
    );
    return password;
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
