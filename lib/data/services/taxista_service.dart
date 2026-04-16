import 'package:supabase_flutter/supabase_flutter.dart';

class TaxistaActionResult {
  const TaxistaActionResult({
    required this.success,
    required this.message,
    this.estado,
  });

  final bool success;
  final String message;
  final String? estado;

  factory TaxistaActionResult.fromMap(Map<String, dynamic> map) {
    return TaxistaActionResult(
      success: map['success'] == true,
      message: (map['message']?.toString() ?? 'Operacion completada').trim(),
      estado: map['estado']?.toString(),
    );
  }
}

class DriverDashboardData {
  const DriverDashboardData({
    required this.success,
    required this.message,
    required this.estadoTaxista,
    required this.ultimosViajes,
    this.viajeActivo,
  });

  final bool success;
  final String message;
  final String estadoTaxista;
  final Map<String, dynamic>? viajeActivo;
  final List<Map<String, dynamic>> ultimosViajes;

  factory DriverDashboardData.fromMap(Map<String, dynamic> map) {
    final viajeActivoRaw = map['viaje_activo'];
    final ultimosViajesRaw = map['ultimos_viajes'];

    return DriverDashboardData(
      success: map['success'] == true,
      message: (map['message']?.toString() ?? 'Dashboard cargado').trim(),
      estadoTaxista: (map['estado_taxista']?.toString() ?? 'no disponible')
          .trim(),
      viajeActivo: viajeActivoRaw is Map<String, dynamic>
          ? viajeActivoRaw
          : (viajeActivoRaw is Map
                ? Map<String, dynamic>.from(viajeActivoRaw)
                : null),
      ultimosViajes: ultimosViajesRaw is List
          ? ultimosViajesRaw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : const [],
    );
  }
}

class TaxistaService {
  final SupabaseClient _supabase = Supabase.instance.client;

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

  Future<void> _notifyClienteViaje({
    required String viajeId,
    required String title,
    required String body,
    String? tipo,
  }) async {
    try {
      final viaje = await _supabase
          .from('viajes')
          .select('user_id')
          .eq('id', viajeId)
          .maybeSingle();

      if (viaje != null) {
        await _sendPushNotification(
          userId: viaje['user_id'] as String,
          title: title,
          body: body,
          data: {'viaje_id': viajeId, 'tipo': tipo},
        );
      }
    } catch (_) {}
  }

  Future<void> _notifyDriverViaje({
    required String title,
    required String body,
    required String viajeId,
    String? tipo,
  }) async {
    final driverId = _supabase.auth.currentUser?.id;
    if (driverId == null) return;

    try {
      await _sendPushNotification(
        userId: driverId,
        title: title,
        body: body,
        data: {'viaje_id': viajeId, 'tipo': tipo},
      );
    } catch (_) {}
  }

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

  Future<List<Map<String, dynamic>>> listTaxistas() async {
    final response = await _supabase
        .from('taxistas')
        .select(
          'id, estado, is_admin, vehiculo_id, municipio_id, '
          'usuarios!inner(nombre, apellidos, email, telefono, dni), '
          'vehiculos!inner(licencia_taxi, matricula, marca, modelo, color, capacidad, minusvalido)',
        )
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getTaxistaRideHistory({
    required String taxistaId,
    int limit = 100,
  }) async {
    final response = await _supabase
        .from('viajes')
        .select(
          'id, created_at, estado, origen, destino, precio, distancia, '
          'duracion, fecha_recogida, fecha_entrega, ciudad_origen',
        )
        .eq('driver_id', taxistaId)
        .order('created_at', ascending: false)
        .limit(limit);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> deleteTaxista({required String taxistaId}) async {
    final isAdmin = await isUserAdmin();
    if (!isAdmin) {
      throw Exception('No tienes permisos de administrador');
    }

    final taxista = await _supabase
        .from('taxistas')
        .select('vehiculo_id')
        .eq('id', taxistaId)
        .maybeSingle();

    if (taxista == null) {
      throw Exception('Taxista no encontrado');
    }

    final vehiculoId = taxista['vehiculo_id'] as int;

    // Eliminar registro de taxistas
    await _supabase.from('taxistas').delete().eq('id', taxistaId);

    // Eliminar vehículo
    await _supabase.from('vehiculos').delete().eq('id', vehiculoId);

    // Eliminar usuario
    await _supabase.from('usuarios').delete().eq('id', taxistaId);
  }

  Future<DriverDashboardData> getDriverDashboardData({int limit = 3}) async {
    final raw = await _supabase.rpc(
      'get_driver_dashboard_data',
      params: {'p_limit': limit},
    );

    if (raw is Map<String, dynamic>) {
      return _enrichDriverDashboardData(DriverDashboardData.fromMap(raw));
    }

    if (raw is Map) {
      return _enrichDriverDashboardData(
        DriverDashboardData.fromMap(Map<String, dynamic>.from(raw)),
      );
    }

    return const DriverDashboardData(
      success: false,
      message: 'No se pudo obtener el dashboard del taxista.',
      estadoTaxista: 'no disponible',
      ultimosViajes: [],
    );
  }

  Future<DriverDashboardData> _enrichDriverDashboardData(
    DriverDashboardData data,
  ) async {
    final viajeActivo = data.viajeActivo;
    final rideId = viajeActivo?['id']?.toString();

    if (viajeActivo == null || rideId == null || rideId.isEmpty) {
      return data;
    }

    if (viajeActivo['anotaciones'] != null && viajeActivo['duracion'] != null) {
      return data;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      return data;
    }

    try {
      final rawDetail = await _supabase.rpc(
        'get_driver_ride_detail',
        params: {'p_viaje_id': rideId, 'p_driver_id': user.id},
      );

      if (rawDetail is List && rawDetail.isNotEmpty) {
        final detail = Map<String, dynamic>.from(rawDetail.first as Map);
        final enriched = {
          ...viajeActivo,
          'anotaciones': detail['anotaciones'],
          'duracion': detail['duracion'] ?? viajeActivo['duracion'],
        };

        return DriverDashboardData(
          success: data.success,
          message: data.message,
          estadoTaxista: data.estadoTaxista,
          viajeActivo: enriched,
          ultimosViajes: data.ultimosViajes,
        );
      }
    } catch (_) {
      // Keep dashboard data usable even if extra enrichment fails.
    }

    return data;
  }

  Future<TaxistaActionResult> setDriverDisponibilidad({
    required String estado,
  }) async {
    final raw = await _supabase.rpc(
      'set_driver_disponibilidad',
      params: {'p_estado': estado},
    );

    if (raw is List && raw.isNotEmpty) {
      return TaxistaActionResult.fromMap(Map<String, dynamic>.from(raw.first));
    }

    if (raw is Map) {
      return TaxistaActionResult.fromMap(Map<String, dynamic>.from(raw));
    }

    return const TaxistaActionResult(
      success: false,
      message: 'No se pudo cambiar la disponibilidad.',
    );
  }

  Future<TaxistaActionResult> updateDriverLocation({
    required double lat,
    required double lng,
  }) async {
    final raw = await _supabase.rpc(
      'update_driver_location',
      params: {'p_lat': lat, 'p_lng': lng},
    );

    if (raw is List && raw.isNotEmpty) {
      return TaxistaActionResult.fromMap(Map<String, dynamic>.from(raw.first));
    }

    if (raw is Map) {
      return TaxistaActionResult.fromMap(Map<String, dynamic>.from(raw));
    }

    return const TaxistaActionResult(
      success: false,
      message: 'No se pudo actualizar la ubicacion.',
    );
  }

  Future<TaxistaActionResult> confirmRideByDriver({required String viajeId}) {
    return _runDriverRideAction(
      'confirm_ride_by_driver',
      viajeId,
      onSuccess: () async {
        await _notifyClienteViaje(
          viajeId: viajeId,
          title: 'Taxista en camino',
          body: 'El taxista ha confirmado tu viaje y está en camino',
          tipo: 'taxista_confirmado',
        );
      },
    );
  }

  Future<TaxistaActionResult> cancelRideByDriver({required String viajeId}) {
    return _runDriverRideAction(
      'cancel_ride_by_driver',
      viajeId,
      onSuccess: () async {
        await Future.wait([
          _notifyClienteViaje(
            viajeId: viajeId,
            title: 'Viaje cancelado',
            body: 'El taxista ha cancelado el viaje',
            tipo: 'viaje_cancelado',
          ),
          _notifyDriverViaje(
            viajeId: viajeId,
            title: 'Viaje cancelado',
            body: 'Has cancelado el viaje correctamente',
            tipo: 'viaje_cancelado',
          ),
        ]);
      },
    );
  }

  Future<TaxistaActionResult> startRideByDriver({required String viajeId}) {
    return _runDriverRideAction(
      'start_ride_by_driver',
      viajeId,
      onSuccess: () async {
        await _notifyClienteViaje(
          viajeId: viajeId,
          title: 'Viaje iniciado',
          body: 'El taxista ha iniciado el viaje',
          tipo: 'viaje_iniciado',
        );
      },
    );
  }

  Future<TaxistaActionResult> finishRideByDriver({required String viajeId}) {
    return _runDriverRideAction(
      'finish_ride_by_driver',
      viajeId,
      onSuccess: () async {
        await _notifyClienteViaje(
          viajeId: viajeId,
          title: 'Viaje finalizado',
          body: 'El viaje ha finalizado correctamente',
          tipo: 'viaje_finalizado',
        );
      },
    );
  }

  Future<TaxistaActionResult> _runDriverRideAction(
    String rpcName,
    String viajeId, {
    Future<void> Function()? onSuccess,
  }) async {
    final raw = await _supabase.rpc(rpcName, params: {'p_viaje_id': viajeId});

    TaxistaActionResult? result;

    if (raw is List && raw.isNotEmpty) {
      result = TaxistaActionResult.fromMap(
        Map<String, dynamic>.from(raw.first),
      );
    } else if (raw is Map) {
      result = TaxistaActionResult.fromMap(Map<String, dynamic>.from(raw));
    }

    if (result?.success == true && onSuccess != null) {
      await onSuccess();
    }

    return result ??
        const TaxistaActionResult(
          success: false,
          message: 'No se pudo completar la accion solicitada.',
        );
  }
}
