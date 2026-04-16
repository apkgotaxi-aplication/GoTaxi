import 'package:uuid/uuid.dart';

/// Enum para el tipo de valoración
enum RatingType { positiva, negativa }

/// Enum para los motivos de valoración negativa
enum RatingMotive {
  imprudente, // Conductor imprudente
  sucio, // Vehículo sucio
  ruta_incorrecta, // Ruta incorrecta
  otra, // Otro motivo
}

/// Extensión para convertir enum a string y viceversa
extension RatingTypeExtension on RatingType {
  String toStringValue() {
    return name.toLowerCase();
  }

  static RatingType fromString(String value) {
    return RatingType.values.firstWhere(
      (type) => type.toStringValue() == value.toLowerCase(),
      orElse: () => RatingType.positiva,
    );
  }
}

/// Extensión para convertir RatingMotive a string y viceversa
extension RatingMotiveExtension on RatingMotive {
  String toStringValue() {
    return name.toLowerCase();
  }

  String toDisplayString() {
    switch (this) {
      case RatingMotive.imprudente:
        return 'Conductor imprudente';
      case RatingMotive.sucio:
        return 'Vehículo sucio';
      case RatingMotive.ruta_incorrecta:
        return 'Ruta incorrecta';
      case RatingMotive.otra:
        return 'Otra';
    }
  }

  static RatingMotive fromString(String value) {
    return RatingMotive.values.firstWhere(
      (motive) => motive.toStringValue() == value.toLowerCase(),
      orElse: () => RatingMotive.imprudente,
    );
  }
}

/// Modelo principal para una valoración de taxista
class TaxistaRating {
  final String id;
  final String viajeId;
  final String taxistaId;
  final String clienteId;
  final RatingType tipo;
  final RatingMotive? motivo;
  final String? comentario;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  const TaxistaRating({
    required this.id,
    required this.viajeId,
    required this.taxistaId,
    required this.clienteId,
    required this.tipo,
    this.motivo,
    this.comentario,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  /// Factory constructor para crear desde un Map (ej: response de Supabase)
  factory TaxistaRating.fromMap(Map<String, dynamic> map) {
    return TaxistaRating(
      id: map['id'] as String? ?? const Uuid().v4(),
      viajeId: map['viaje_id'] as String? ?? '',
      taxistaId: map['taxista_id'] as String? ?? '',
      clienteId: map['cliente_id'] as String? ?? '',
      tipo: RatingTypeExtension.fromString(
        map['tipo_valoracion'] as String? ?? 'positiva',
      ),
      motivo: map['motivo'] != null
          ? RatingMotiveExtension.fromString(map['motivo'] as String)
          : null,
      comentario: map['comentario'] as String?,
      creadoEn: map['creado_en'] != null
          ? DateTime.parse(map['creado_en'] as String)
          : DateTime.now(),
      actualizadoEn: map['actualizado_en'] != null
          ? DateTime.parse(map['actualizado_en'] as String)
          : DateTime.now(),
    );
  }

  /// Convertir a Map para enviar a Supabase
  Map<String, dynamic> toMap() {
    return {
      'viaje_id': viajeId,
      'taxista_id': taxistaId,
      'cliente_id': clienteId,
      'tipo_valoracion': tipo.toStringValue(),
      'motivo': motivo?.toStringValue(),
      'comentario': comentario,
    };
  }

  /// Copiar con nuevos valores
  TaxistaRating copyWith({
    String? id,
    String? viajeId,
    String? taxistaId,
    String? clienteId,
    RatingType? tipo,
    RatingMotive? motivo,
    String? comentario,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) {
    return TaxistaRating(
      id: id ?? this.id,
      viajeId: viajeId ?? this.viajeId,
      taxistaId: taxistaId ?? this.taxistaId,
      clienteId: clienteId ?? this.clienteId,
      tipo: tipo ?? this.tipo,
      motivo: motivo ?? this.motivo,
      comentario: comentario ?? this.comentario,
      creadoEn: creadoEn ?? this.creadoEn,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }
}

/// Resultado cuando se envía una valoración
class SubmitRatingResult {
  final bool success;
  final String message;
  final String? ratingId;

  const SubmitRatingResult({
    required this.success,
    required this.message,
    this.ratingId,
  });

  factory SubmitRatingResult.fromMap(Map<String, dynamic> map) {
    return SubmitRatingResult(
      success: map['success'] as bool? ?? false,
      message: (map['message'] as String?) ?? 'Error desconocido',
      ratingId: map['rating_id'] as String?,
    );
  }
}

/// Modelo para el resumen de valoraciones de un taxista
class TaxistaRatingsSummary {
  final int totalRatings;
  final int positiveCount;
  final int negativeCount;
  final double incidentPercentage;
  final List<RatingIncident> recentIncidents;

  const TaxistaRatingsSummary({
    required this.totalRatings,
    required this.positiveCount,
    required this.negativeCount,
    required this.incidentPercentage,
    required this.recentIncidents,
  });

  /// Factory constructor para crear desde un Map
  factory TaxistaRatingsSummary.fromMap(Map<String, dynamic> map) {
    List<RatingIncident> incidents = [];
    if (map['recent_incidents'] != null) {
      final List<dynamic> incidentsData =
          map['recent_incidents'] as List<dynamic>;
      incidents = incidentsData
          .map(
            (incident) =>
                RatingIncident.fromMap(incident as Map<String, dynamic>),
          )
          .toList();
    }

    return TaxistaRatingsSummary(
      totalRatings: (map['total_ratings'] as num?)?.toInt() ?? 0,
      positiveCount: (map['positive_count'] as num?)?.toInt() ?? 0,
      negativeCount: (map['negative_count'] as num?)?.toInt() ?? 0,
      incidentPercentage:
          (map['incident_percentage'] as num?)?.toDouble() ?? 0.0,
      recentIncidents: incidents,
    );
  }
}

/// Modelo para una incidencia reciente
class RatingIncident {
  final String id;
  final String? motivo;
  final String? comentario;
  final DateTime creadoEn;

  const RatingIncident({
    required this.id,
    this.motivo,
    this.comentario,
    required this.creadoEn,
  });

  factory RatingIncident.fromMap(Map<String, dynamic> map) {
    return RatingIncident(
      id: map['id'] as String? ?? '',
      motivo: map['motivo'] as String?,
      comentario: map['comentario'] as String?,
      creadoEn: map['creado_en'] != null
          ? DateTime.parse(map['creado_en'] as String)
          : DateTime.now(),
    );
  }
}

/// Resultado de checking if a ride was rated
class RideRatingCheckResult {
  final bool isRated;
  final RatingType? ratingType;

  const RideRatingCheckResult({required this.isRated, this.ratingType});

  factory RideRatingCheckResult.fromMap(Map<String, dynamic> map) {
    return RideRatingCheckResult(
      isRated: map['is_rated'] as bool? ?? false,
      ratingType: map['rating_type'] != null
          ? RatingTypeExtension.fromString(map['rating_type'] as String)
          : null,
    );
  }
}
