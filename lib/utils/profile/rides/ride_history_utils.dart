import 'package:supabase_flutter/supabase_flutter.dart';

const Set<String> kCancelableRideStates = {'pendiente', 'confirmada'};

String normalizeRideState(dynamic rawState) {
  return rawState?.toString().trim().toLowerCase() ?? '';
}

bool isRideCancelable(dynamic rawState) {
  return kCancelableRideStates.contains(normalizeRideState(rawState));
}

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

  return List<Map<String, dynamic>>.from(response).map((ride) {
    final state = normalizeRideState(ride['estado']);
    return {...ride, 'estado': state};
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

  final response = await supabase.rpc(
    'get_driver_ride_history',
    params: {'p_driver_id': currentUser.id, 'p_limit': limit},
  );

  return List<Map<String, dynamic>>.from(response).map((ride) {
    final state = normalizeRideState(ride['estado']);
    return {...ride, 'estado': state};
  }).toList();
}

Future<Map<String, dynamic>> fetchCurrentUserRideDetail({
  required String rideId,
}) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    throw StateError('No hay una cuenta iniciada para consultar este viaje.');
  }

  final response = await supabase.rpc(
    'get_ride_detail',
    params: {'p_viaje_id': rideId, 'p_cliente_id': currentUser.id},
  );

  if (response is List && response.isNotEmpty) {
    final detail = Map<String, dynamic>.from(response.first as Map);
    return {...detail, 'estado': normalizeRideState(detail['estado'])};
  }

  throw StateError('No se encontro el detalle del viaje solicitado.');
}

Future<Map<String, dynamic>> fetchCurrentUserDriverRideDetail({
  required String rideId,
}) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    throw StateError('No hay una cuenta iniciada para consultar este viaje.');
  }

  final response = await supabase.rpc(
    'get_driver_ride_detail',
    params: {'p_viaje_id': rideId, 'p_driver_id': currentUser.id},
  );

  if (response is List && response.isNotEmpty) {
    final detail = Map<String, dynamic>.from(response.first as Map);
    return {...detail, 'estado': normalizeRideState(detail['estado'])};
  }

  throw StateError('No se encontro el detalle del viaje solicitado.');
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
