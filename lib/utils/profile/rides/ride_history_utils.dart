import 'package:supabase_flutter/supabase_flutter.dart';

const _ridesTable = 'viajes';
const _accountIdColumn = 'user_id';
const _driverIdColumn = 'driver_id';
const _orderByColumn = 'created_at';

Future<List<Map<String, dynamic>>> fetchCurrentUserRideHistory({
  int limit = 50,
}) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    throw StateError('No hay una cuenta iniciada para consultar viajes.');
  }

  final response = await supabase
      .from(_ridesTable)
      .select(
        'id, created_at, '
        'usuario:user_id(nombre, apellidos), '
        'taxista:driver_id(nombre, apellidos)',
      )
      .eq(_accountIdColumn, currentUser.id)
      .order(_orderByColumn, ascending: false)
      .limit(limit);

  return List<Map<String, dynamic>>.from(response).map((ride) {
    final userData = ride['usuario'] as Map<String, dynamic>?;
    final driverData = ride['taxista'] as Map<String, dynamic>?;

    return {
      'id': ride['id'],
      'created_at': ride['created_at'],
      'user_nombre': userData?['nombre'],
      'user_apellidos': userData?['apellidos'],
      'driver_nombre': driverData?['nombre'],
      'driver_apellidos': driverData?['apellidos'],
    };
  }).toList();
}

Future<List<Map<String, dynamic>>> fetchCurrentUserDriverRideHistory({
  int limit = 50,
}) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    throw StateError('No hay una cuenta iniciada para consultar viajes.');
  }

  final response = await supabase
      .from(_ridesTable)
      .select(
        'id, created_at, '
        'usuario:user_id(nombre, apellidos), '
        'taxista:driver_id(nombre, apellidos)',
      )
      .eq(_driverIdColumn, currentUser.id)
      .order(_orderByColumn, ascending: false)
      .limit(limit);

  return List<Map<String, dynamic>>.from(response).map((ride) {
    final userData = ride['usuario'] as Map<String, dynamic>?;
    final driverData = ride['taxista'] as Map<String, dynamic>?;

    return {
      'id': ride['id'],
      'created_at': ride['created_at'],
      'user_nombre': userData?['nombre'],
      'user_apellidos': userData?['apellidos'],
      'driver_nombre': driverData?['nombre'],
      'driver_apellidos': driverData?['apellidos'],
    };
  }).toList();
}

Future<bool> isCurrentUserTaxista() async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) return false;

  final response = await supabase
      .from('usuarios')
      .select('rol')
      .eq('id', currentUser.id)
      .maybeSingle();

  return response != null && response['rol'] == 'taxista';
}
