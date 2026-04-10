import 'package:supabase_flutter/supabase_flutter.dart';

class FavoriteLocation {
  final String id;
  final String clienteId;
  final String nombre;
  final String? descripcion;
  final double latitud;
  final double longitud;
  final String direccion;
  final String tipo; // 'casa', 'trabajo', 'otro'
  final DateTime createdAt;
  final DateTime updatedAt;

  FavoriteLocation({
    required this.id,
    required this.clienteId,
    required this.nombre,
    this.descripcion,
    required this.latitud,
    required this.longitud,
    required this.direccion,
    required this.tipo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FavoriteLocation.fromJson(Map<String, dynamic> json) {
    return FavoriteLocation(
      id: json['id'] as String,
      clienteId: json['cliente_id'] as String,
      nombre: json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      direccion: json['direccion'] as String,
      tipo: json['tipo'] as String? ?? 'otro',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'cliente_id': clienteId,
    'nombre': nombre,
    'descripcion': descripcion,
    'latitud': latitud,
    'longitud': longitud,
    'direccion': direccion,
    'tipo': tipo,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

class FavoritesService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todos los lugares favoritos del usuario actual
  Future<List<FavoriteLocation>> getMyFavorites() async {
    try {
      final response = await _supabase
          .from('lugares_favoritos')
          .select()
          .order('created_at', ascending: false);

      return (response as List)
          .map(
            (json) => FavoriteLocation.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Agrega un nuevo lugar favorito
  Future<bool> addFavorite({
    required String nombre,
    required double latitud,
    required double longitud,
    required String direccion,
    String tipo = 'otro',
    String? descripcion,
  }) async {
    try {
      final response =
          await _supabase.rpc(
                'add_favorite_location',
                params: {
                  'p_nombre': nombre,
                  'p_latitud': latitud,
                  'p_longitud': longitud,
                  'p_direccion': direccion,
                  'p_tipo': tipo,
                  'p_descripcion': descripcion,
                },
              )
              as List<dynamic>;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        return result['success'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }

  /// Elimina un lugar favorito
  Future<bool> deleteFavorite(String favoriteId) async {
    try {
      final response =
          await _supabase.rpc(
                'delete_favorite_location',
                params: {'p_favorite_id': favoriteId},
              )
              as List<dynamic>;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        return result['success'] as bool? ?? false;
      }
      return false;
    } catch (e) {
      rethrow;
    }
  }

  /// Actualiza un lugar favorito (nombre, descripción, tipo)
  Future<bool> updateFavorite({
    required String favoriteId,
    String? nombre,
    String? descripcion,
    String? tipo,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (nombre != null) updates['nombre'] = nombre;
      if (descripcion != null) updates['descripcion'] = descripcion;
      if (tipo != null) updates['tipo'] = tipo;

      await _supabase
          .from('lugares_favoritos')
          .update(updates)
          .eq('id', favoriteId)
          .eq('cliente_id', _supabase.auth.currentUser!.id);

      return true;
    } catch (e) {
      rethrow;
    }
  }
}
