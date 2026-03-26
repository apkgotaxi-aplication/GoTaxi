import 'package:supabase_flutter/supabase_flutter.dart';

Future<List<Map<String, dynamic>>> fetchCurrentUserRideHistory({
  int limit = 50,
}) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    throw StateError('No hay una cuenta iniciada para consultar viajes.');
  }

  final response = await supabase.rpc(
    'get_user_ride_history',
    params: {'p_user_id': currentUser.id, 'p_limit': limit},
  );

  return List<Map<String, dynamic>>.from(response);
}

Future<List<Map<String, dynamic>>> fetchCurrentUserDriverRideHistory({
  int limit = 50,
}) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    throw StateError('No hay una cuenta iniciada para consultar viajes.');
  }

  final response = await supabase.rpc(
    'get_driver_ride_history',
    params: {'p_driver_id': currentUser.id, 'p_limit': limit},
  );

  return List<Map<String, dynamic>>.from(response);
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
