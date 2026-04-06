import 'package:supabase_flutter/supabase_flutter.dart';

class TarifaMunicipioView {
  const TarifaMunicipioView({
    required this.municipioId,
    required this.municipioNombre,
    required this.provinciaId,
    required this.precioKm,
    required this.precioHora,
    required this.isDefault,
    this.tarifaId,
  });

  final int municipioId;
  final String municipioNombre;
  final int provinciaId;
  final double precioKm;
  final double precioHora;
  final bool isDefault;
  final int? tarifaId;
}

class TarifaSaveResult {
  const TarifaSaveResult({
    required this.success,
    required this.message,
    this.tarifaId,
  });

  final bool success;
  final String message;
  final int? tarifaId;

  factory TarifaSaveResult.fromMap(Map<String, dynamic> map) {
    final rawTarifaId = map['tarifa_id'];
    final tarifaId = rawTarifaId is int
        ? rawTarifaId
        : int.tryParse(rawTarifaId?.toString() ?? '');

    return TarifaSaveResult(
      success: map['success'] == true,
      message: (map['message']?.toString() ?? 'Operacion completada').trim(),
      tarifaId: tarifaId,
    );
  }
}

class TarifaService {
  TarifaService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const double defaultPrecioKm = 1.5;
  static const double defaultPrecioHora = 0.2;

  Future<int> getProvinciaIdByNombre(String provinciaNombre) async {
    final response = await _supabase
        .from('provincias')
        .select('id')
        .ilike('nombre', provinciaNombre.trim())
        .maybeSingle();

    if (response == null) {
      throw StateError(
        'No existe la provincia seleccionada en la base de datos.',
      );
    }

    return response['id'] as int;
  }

  Future<List<TarifaMunicipioView>> getMunicipiosConTarifaByProvincia({
    required int provinciaId,
  }) async {
    final municipiosRaw = await _supabase
        .from('municipios')
        .select('id, nombre, provincia_id')
        .eq('provincia_id', provinciaId)
        .order('nombre', ascending: true);

    final tarifasRaw = await _supabase.rpc(
      'get_tarifas_by_provincia',
      params: {'p_provincia_id': provinciaId},
    );

    final tarifasPorMunicipio = <int, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(tarifasRaw as List)) {
      final municipioId = row['municipio_id'] as int;
      tarifasPorMunicipio[municipioId] = row;
    }

    final result = <TarifaMunicipioView>[];
    for (final row in List<Map<String, dynamic>>.from(municipiosRaw)) {
      final municipioId = row['id'] as int;
      final tarifa = tarifasPorMunicipio[municipioId];

      result.add(
        TarifaMunicipioView(
          municipioId: municipioId,
          municipioNombre: row['nombre']?.toString() ?? 'Sin nombre',
          provinciaId: row['provincia_id'] as int,
          precioKm:
              (tarifa?['precio_km'] as num?)?.toDouble() ?? defaultPrecioKm,
          precioHora:
              (tarifa?['precio_hora'] as num?)?.toDouble() ?? defaultPrecioHora,
          isDefault: tarifa == null,
          tarifaId: tarifa?['id'] as int?,
        ),
      );
    }

    return result;
  }

  Future<TarifaSaveResult> upsertTarifaMunicipio({
    required int municipioId,
    required double precioKm,
    required double precioHora,
  }) async {
    final raw = await _supabase.rpc(
      'upsert_tarifa_municipio',
      params: {
        'p_municipio_id': municipioId,
        'p_precio_km': precioKm,
        'p_precio_hora': precioHora,
      },
    );

    if (raw is List && raw.isNotEmpty) {
      return TarifaSaveResult.fromMap(Map<String, dynamic>.from(raw.first));
    }

    if (raw is Map) {
      return TarifaSaveResult.fromMap(Map<String, dynamic>.from(raw));
    }

    return const TarifaSaveResult(
      success: false,
      message: 'No se pudo interpretar la respuesta del servidor.',
    );
  }

  Future<double> calculateEstimatedFareForCity({
    required String ciudadOrigen,
    required double kilometers,
    required double minutes,
  }) async {
    final response = await _supabase.rpc(
      'get_tarifa_by_city_or_default',
      params: {'p_ciudad_origen': ciudadOrigen},
    );

    double precioKm = defaultPrecioKm;
    double precioHora = defaultPrecioHora;

    if (response is List && response.isNotEmpty) {
      final row = Map<String, dynamic>.from(response.first as Map);
      precioKm = (row['precio_km'] as num?)?.toDouble() ?? defaultPrecioKm;
      precioHora =
          (row['precio_hora'] as num?)?.toDouble() ?? defaultPrecioHora;
    }

    final total = (kilometers * precioKm) + (minutes * precioHora);
    return double.parse(total.toStringAsFixed(2));
  }
}
