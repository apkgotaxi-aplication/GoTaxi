import 'package:supabase_flutter/supabase_flutter.dart';

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
    DateTime? fechaRecogida,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Debes iniciar sesion para pedir un viaje.');
    }

    final raw = await _supabase.rpc(
      'assign_taxi_to_ride',
      params: {
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
      },
    );

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

    if (message.contains('minusvalido')) {
      return RideAssignmentResult(
        success: false,
        message:
            '❌ No se encuentran taxis disponibles para personas con movilidad reducida en tu zona.',
      );
    }

    if (message.contains('capacidad')) {
      return RideAssignmentResult(
        success: false,
        message:
            '❌ No se encuentran taxis disponibles con capacidad para $numPasajeros pasajeros.',
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
}
