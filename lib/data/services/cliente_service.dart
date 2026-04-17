import 'package:supabase_flutter/supabase_flutter.dart';

class ClienteService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<bool> isUserAdmin() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final clienteResponse = await _supabase
          .from('clientes')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();

      if (clienteResponse != null && clienteResponse['is_admin'] == true) {
        return true;
      }

      final taxistaResponse = await _supabase
          .from('taxistas')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();

      return taxistaResponse != null && taxistaResponse['is_admin'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listClientes({
    int limit = 100,
    int offset = 0,
  }) async {
    final isAdmin = await isUserAdmin();
    if (!isAdmin) {
      throw Exception('No tienes permisos de administrador');
    }

    final response = await _supabase
        .from('usuarios')
        .select('id, nombre, apellidos')
        .eq('rol', 'cliente')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> getClienteById(String clienteId) async {
    final isAdmin = await isUserAdmin();
    if (!isAdmin) {
      throw Exception('No tienes permisos de administrador');
    }

    final response = await _supabase
        .from('usuarios')
        .select('id, nombre, apellidos, email, telefono, dni, created_at')
        .eq('id', clienteId)
        .eq('rol', 'cliente')
        .maybeSingle();

    return response;
  }

  Future<List<Map<String, dynamic>>> getClienteViajes(
    String clienteId, {
    int limit = 10,
    int offset = 0,
  }) async {
    final response = await _supabase
        .from('viajes')
        .select('id, created_at, estado, origen, destino, precio, distancia')
        .eq('user_id', clienteId)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> deleteCliente(String clienteId) async {
    final isAdmin = await isUserAdmin();
    if (!isAdmin) {
      throw Exception('No tienes permisos de administrador');
    }

    await _supabase.rpc('delete_cliente', params: {'p_cliente_id': clienteId});
  }
}
