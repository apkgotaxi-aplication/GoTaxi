import 'package:supabase_flutter/supabase_flutter.dart';

const _ridesTable = 'viajes'; // REEMPLAZAR si en tu BD tiene otro nombre.
const _accountIdColumn =
    'user_id'; // REEMPLAZAR por la columna real del usuario.
const _orderByColumn = 'created_at'; // REEMPLAZAR por la columna de fecha real.

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
