import 'dart:math';

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class RideAssignmentResult {
  const RideAssignmentResult({
    required this.success,
    this.viajeId,
    this.taxistaId,
    this.estado,
    required this.message,
  });

  final bool success;
  final String? viajeId;
  final String? taxistaId;
  final String? estado;
  final String message;

  factory RideAssignmentResult.fromMap(Map<String, dynamic> map) {
    return RideAssignmentResult(
      success: map['success'] as bool? ?? false,
      viajeId: map['viaje_id'] as String?,
      taxistaId: map['taxista_id'] as String?,
      estado: map['estado'] as String?,
      message: (map['message'] as String?) ?? 'Operacion completada',
    );
  }
}

class RideCancellationResult {
  const RideCancellationResult({
    required this.success,
    required this.message,
    this.estado,
  });

  final bool success;
  final String message;
  final String? estado;

  factory RideCancellationResult.fromMap(Map<String, dynamic> map) {
    return RideCancellationResult(
      success: map['success'] as bool? ?? false,
      message: (map['message'] as String?) ?? 'No se pudo cancelar el viaje.',
      estado: map['estado']?.toString(),
    );
  }
}

class RideEtaResult {
  const RideEtaResult({required this.available, this.etaMin, this.updatedAt});

  final bool available;
  final int? etaMin;
  final DateTime? updatedAt;

  factory RideEtaResult.unavailable() {
    return const RideEtaResult(available: false);
  }
}

class RideService {
  RideService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<void> _sendPushNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _supabase.functions.invoke(
        'send-notification',
        body: {'user_id': userId, 'title': title, 'body': body, 'data': data},
      );
    } catch (_) {}
  }

  Future<void> _notifyRideAssignment({
    required String clienteId,
    required String? taxistaId,
    required String? viajeId,
    required String origen,
    required String destino,
  }) async {
    if (taxistaId != null && viajeId != null) {
      await _sendPushNotification(
        userId: taxistaId,
        title: 'Nuevo taxi solicitado',
        body: 'Cliente esperando viaje de $origen a $destino',
        data: {'viaje_id': viajeId, 'tipo': 'solicitud_taxi'},
      );

      await _sendPushNotification(
        userId: clienteId,
        title: 'Taxista asignado',
        body: 'Ya tienes un taxista asignado para tu viaje',
        data: {'viaje_id': viajeId, 'tipo': 'taxista_asignado'},
      );
    }
  }

  Future<void> _notifyRideCancellation({
    required String clienteId,
    required String? taxistaId,
    required String viajeId,
    required bool cancelledByCliente,
  }) async {
    final clienteBody = cancelledByCliente
        ? 'Tu viaje ha sido cancelado correctamente'
        : 'El taxista ha cancelado tu viaje';
    final taxistaBody = cancelledByCliente
        ? 'El cliente ha cancelado el viaje'
        : 'Has cancelado el viaje correctamente';

    await _sendPushNotification(
      userId: clienteId,
      title: 'Viaje cancelado',
      body: clienteBody,
      data: {'viaje_id': viajeId, 'tipo': 'viaje_cancelado'},
    );

    if (taxistaId != null) {
      await _sendPushNotification(
        userId: taxistaId,
        title: 'Viaje cancelado',
        body: taxistaBody,
        data: {'viaje_id': viajeId, 'tipo': 'viaje_cancelado'},
      );
    }
  }

  Future<RideCancellationResult> cancelRide({required String viajeId}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Debes iniciar sesion para cancelar un viaje.');
    }

    final viaje = await _supabase
        .from('viajes')
        .select('driver_id')
        .eq('id', viajeId)
        .maybeSingle();

    final raw = await _supabase.rpc(
      'cancel_ride',
      params: {'p_viaje_id': viajeId, 'p_cliente_id': user.id},
    );

    if (raw is List && raw.isNotEmpty) {
      final result = RideCancellationResult.fromMap(
        Map<String, dynamic>.from(raw.first as Map),
      );
      if (result.success) {
        await _notifyRideCancellation(
          clienteId: user.id,
          taxistaId: viaje?['driver_id'] as String?,
          viajeId: viajeId,
          cancelledByCliente: true,
        );
      }
      return result;
    }

    if (raw is Map) {
      final result = RideCancellationResult.fromMap(
        Map<String, dynamic>.from(raw),
      );
      if (result.success) {
        await _notifyRideCancellation(
          clienteId: user.id,
          taxistaId: viaje?['driver_id'] as String?,
          viajeId: viajeId,
          cancelledByCliente: true,
        );
      }
      return result;
    }

    return const RideCancellationResult(
      success: false,
      message:
          'No se pudo interpretar la respuesta del servidor. Inténtelo de nuevo más tarde.',
    );
  }

  Future<RideAssignmentResult> createRideAssignment({
    required String origen,
    required String destino,
    required int numPasajeros,
    required String anotaciones,
    required double distanciaKm,
    required double precio,
    required int duracionMin,
    required bool minusvalido,
    required String ciudadOrigen,
    double? origenLat,
    double? origenLng,
    double? destinoLat,
    double? destinoLng,
    DateTime? fechaRecogida,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Debes iniciar sesion para pedir un viaje.');
    }

    final paramsWithCoordinates = {
      'p_cliente_id': user.id,
      'p_origen': origen,
      'p_destino': destino,
      'p_num_pasajeros': numPasajeros,
      'p_anotaciones': anotaciones,
      'p_distancia': distanciaKm,
      'p_precio': precio,
      'p_duracion': duracionMin,
      'p_minusvalido': minusvalido,
      'p_ciudad_origen': ciudadOrigen,
      'p_origen_lat': origenLat,
      'p_origen_lng': origenLng,
      'p_destino_lat': destinoLat,
      'p_destino_lng': destinoLng,
      'p_fecha_recogida': (fechaRecogida ?? DateTime.now()).toIso8601String(),
    };

    final paramsLegacy = {
      'p_cliente_id': user.id,
      'p_origen': origen,
      'p_destino': destino,
      'p_num_pasajeros': numPasajeros,
      'p_anotaciones': anotaciones,
      'p_distancia': distanciaKm,
      'p_precio': precio,
      'p_duracion': duracionMin,
      'p_minusvalido': minusvalido,
      'p_ciudad_origen': ciudadOrigen,
      'p_fecha_recogida': (fechaRecogida ?? DateTime.now()).toIso8601String(),
    };

    dynamic raw;
    try {
      raw = await _supabase.rpc(
        'assign_taxi_to_ride',
        params: paramsWithCoordinates,
      );
    } on PostgrestException catch (error) {
      if (!_isLegacyAssignRideSignatureError(error)) {
        rethrow;
      }

      raw = await _supabase.rpc('assign_taxi_to_ride', params: paramsLegacy);
    }

    if (raw is List && raw.isNotEmpty) {
      final result = RideAssignmentResult.fromMap(
        Map<String, dynamic>.from(raw.first as Map),
      );
      final mappedResult = _mapErrorMessage(result, numPasajeros);
      if (mappedResult.success) {
        _notifyRideAssignment(
          clienteId: user.id,
          taxistaId: mappedResult.taxistaId,
          viajeId: mappedResult.viajeId,
          origen: origen,
          destino: destino,
        );
      }
      return mappedResult;
    }

    if (raw is Map) {
      final result = RideAssignmentResult.fromMap(
        Map<String, dynamic>.from(raw),
      );
      final mappedResult = _mapErrorMessage(result, numPasajeros);
      if (mappedResult.success) {
        _notifyRideAssignment(
          clienteId: user.id,
          taxistaId: mappedResult.taxistaId,
          viajeId: mappedResult.viajeId,
          origen: origen,
          destino: destino,
        );
      }
      return mappedResult;
    }

    return const RideAssignmentResult(
      success: false,
      message:
          'No se pudo interpretar la respuesta del servidor. Inténtelo de nuevo más tarde.',
    );
  }

  bool _isLegacyAssignRideSignatureError(PostgrestException error) {
    final message = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint?.toString() ?? '').toLowerCase();
    final combined = '$message $details $hint';

    return combined.contains('assign_taxi_to_ride') &&
        (combined.contains('p_origen_lat') ||
            combined.contains('p_origen_lng') ||
            combined.contains('p_destino_lat') ||
            combined.contains('p_destino_lng') ||
            combined.contains('function') ||
            combined.contains('does not exist') ||
            combined.contains('no existe'));
  }

  RideAssignmentResult _mapErrorMessage(
    RideAssignmentResult result,
    int numPasajeros,
  ) {
    if (result.success) {
      final normalizedState = result.estado?.toLowerCase().trim();
      if (normalizedState == 'pendiente') {
        return RideAssignmentResult(
          success: true,
          viajeId: result.viajeId,
          taxistaId: result.taxistaId,
          estado: result.estado,
          message:
              'Solicitud enviada. El taxista debe confirmar tu viaje para empezarlo.',
        );
      }
      return result;
    }

    final message = result.message.toLowerCase();

    if (message.contains('cliente obligatorio')) {
      return RideAssignmentResult(
        success: false,
        message:
            'Error: información de cliente inválida. Inténtelo de nuevo más tarde.',
      );
    }

    if (message.contains('debes especificar tu ciudad de origen')) {
      return RideAssignmentResult(
        success: false,
        message:
            '📍 No pudimos detectar tu ubicación. Asegúrate de habilitar la geolocalización.',
      );
    }

    if (message.contains('no operamos en')) {
      return RideAssignmentResult(
        success: false,
        message: '🚫 Lo sentimos, actualmente no operamos en esa zona.',
      );
    }

    if (message.contains('origen') || message.contains('destino')) {
      return RideAssignmentResult(
        success: false,
        message: 'Por favor, completa origen y destino antes de reservar.',
      );
    }

    if (message.contains('pasajeros')) {
      return RideAssignmentResult(
        success: false,
        message: 'El número de pasajeros debe estar entre 1 y 8 personas.',
      );
    }

    if (message.contains('precio minimo') || message.contains('2 euros')) {
      return RideAssignmentResult(
        success: false,
        message: 'El precio mínimo para un viaje es de 2 euros.',
      );
    }

    if (message.contains('duracion') && message.contains('18 horas')) {
      return RideAssignmentResult(
        success: false,
        message: 'La duración del viaje no puede ser mayor a 18 horas.',
      );
    }

    if (message.contains('ya tienes una reserva activa')) {
      return RideAssignmentResult(
        success: false,
        message:
            '⏳ Ya tienes un viaje activo. Cancélalo antes de solicitar otro.',
      );
    }

    if (message.contains('movilidad reducida')) {
      return RideAssignmentResult(
        success: false,
        message: 'No hay taxis de movilidad reducida en estos momentos.',
      );
    }

    if (message.contains('capacidad')) {
      return RideAssignmentResult(
        success: false,
        message: 'No hay taxis con esa capacidad.',
      );
    }

    if (message.contains('no hay taxistas disponibles') ||
        message.contains('todos los taxistas')) {
      return RideAssignmentResult(
        success: false,
        message:
            '❌ Todos los taxistas están ocupados en este momento. Inténtelo de nuevo más tarde.',
      );
    }

    if (message.contains('no se encuentran taxistas') ||
        message.contains('ningun taxista')) {
      return RideAssignmentResult(
        success: false,
        message:
            '❌ No se encuentran taxistas disponibles para tu zona. Inténtelo de nuevo más tarde.',
      );
    }

    if (message.contains('error al crear')) {
      return RideAssignmentResult(
        success: false,
        message: 'Error al procesar tu reserva. Inténtelo de nuevo más tarde.',
      );
    }

    return result;
  }

  Future<RideEtaResult> fetchRideEta({required String rideId}) async {
    final accessToken = _supabase.auth.currentSession?.accessToken;

    try {
      final response = await _supabase.functions.invoke(
        'ride-eta',
        body: {'ride_id': rideId},
        headers: accessToken == null || accessToken.isEmpty
            ? null
            : {'Authorization': 'Bearer $accessToken'},
      );

      final edgeResult = _parseRideEtaFromRaw(response.data, strict: true);
      if (edgeResult.available) {
        return edgeResult;
      }
    } catch (_) {
      // Ignore and fallback to RPC to avoid leaving the client without ETA.
    }

    try {
      final raw = await _supabase.rpc(
        'get_ride_eta',
        params: {'p_viaje_id': rideId},
      );
      return _parseRideEtaFromRaw(raw, strict: false);
    } catch (_) {
      return RideEtaResult.unavailable();
    }
  }

  Future<RideEtaResult> fetchRideEtaFromDetail(
    Map<String, dynamic> rideDetail,
  ) async {
    final originLat = _parseDouble(rideDetail['origen_lat']);
    final originLng = _parseDouble(rideDetail['origen_lng']);
    final driverLat = _parseDouble(rideDetail['driver_lat']);
    final driverLng = _parseDouble(rideDetail['driver_lng']);

    if (originLat == null ||
        originLng == null ||
        driverLat == null ||
        driverLng == null) {
      return RideEtaResult.unavailable();
    }

    final googleMapsApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

    if (googleMapsApiKey.isNotEmpty) {
      try {
        final uri =
            Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
              'origin': '$driverLat,$driverLng',
              'destination': '$originLat,$originLng',
              'mode': 'driving',
              'language': 'es',
              'key': googleMapsApiKey,
            });

        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if ((data['status'] as String?) == 'OK') {
            final routes = data['routes'] as List<dynamic>?;
            final route = routes != null && routes.isNotEmpty
                ? routes.first as Map<String, dynamic>
                : null;
            final legs = route?['legs'] as List<dynamic>?;
            final leg = legs != null && legs.isNotEmpty
                ? legs.first as Map<String, dynamic>
                : null;
            final duration = leg?['duration'] as Map<String, dynamic>?;
            final durationSeconds = double.tryParse(
              duration?['value']?.toString() ?? '',
            );

            if (durationSeconds != null && durationSeconds > 0) {
              return RideEtaResult(
                available: true,
                etaMin: (durationSeconds / 60).ceil(),
                updatedAt: DateTime.now(),
              );
            }
          }
        }
      } catch (_) {}
    }

    final distanceKm = _haversineKm(driverLat, driverLng, originLat, originLng);
    return RideEtaResult(
      available: true,
      etaMin: (distanceKm / 0.45).ceil().clamp(1, 9999),
      updatedAt: DateTime.now(),
    );
  }

  RideEtaResult _parseRideEtaFromRaw(dynamic raw, {required bool strict}) {
    Map<String, dynamic>? data;

    if (raw is List && raw.isNotEmpty) {
      data = Map<String, dynamic>.from(raw.first as Map);
    } else if (raw is Map) {
      data = Map<String, dynamic>.from(raw);
    }

    if (data == null) return RideEtaResult.unavailable();

    final etaMin = int.tryParse(data['eta_min']?.toString() ?? '');
    final updatedAtRaw = data['ubicacion_actualizada_en']?.toString();

    if (etaMin == null) return RideEtaResult.unavailable();

    if (strict && data['available'] != true) {
      return RideEtaResult.unavailable();
    }

    return RideEtaResult(
      available: true,
      etaMin: etaMin,
      updatedAt: _parseBackendTimestamp(updatedAtRaw),
    );
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (3.1415926535897932 / 180.0);

  DateTime? _parseBackendTimestamp(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) return null;

    final normalized = rawValue.trim();
    final hasTimezone = RegExp(
      r'(z|[+-]\d\d:?\d\d)$',
      caseSensitive: false,
    ).hasMatch(normalized);

    final parsed = DateTime.tryParse(
      hasTimezone ? normalized : '${normalized}Z',
    );

    return parsed?.toLocal();
  }
}
