import 'package:supabase_flutter/supabase_flutter.dart';

class LocationModel {
  final int id;
  final String nombre;

  LocationModel({required this.id, required this.nombre});

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
    );
  }
}

class MunicipioModel extends LocationModel {
  final double latitud;
  final double longitud;
  final int? provinciaId;

  MunicipioModel({
    required super.id,
    required super.nombre,
    required this.latitud,
    required this.longitud,
    this.provinciaId,
  });

  factory MunicipioModel.fromJson(Map<String, dynamic> json) {
    return MunicipioModel(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      provinciaId: json['provincia_id'] as int?,
    );
  }
}

class LocationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<LocationModel>> getProvincias() async {
    try {
      final response = await _supabase
          .from('provincias')
          .select('id, nombre')
          .order('nombre');

      return (response as List)
          .map((p) => LocationModel.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<LocationModel>> searchProvincias(String query) async {
    if (query.isEmpty) {
      return getProvincias();
    }

    try {
      final response = await _supabase
          .from('provincias')
          .select('id, nombre')
          .ilike('nombre', '%$query%')
          .order('nombre');

      return (response as List)
          .map((p) => LocationModel.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<MunicipioModel>> getMunicipios(int provinciaId) async {
    try {
      final response = await _supabase
          .from('municipios')
          .select('id, nombre, latitud, longitud, provincia_id')
          .eq('provincia_id', provinciaId)
          .order('nombre');

      return (response as List)
          .map((m) => MunicipioModel.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<MunicipioModel>> searchMunicipios(
    int provinciaId,
    String query,
  ) async {
    if (query.isEmpty) {
      return getMunicipios(provinciaId);
    }

    try {
      final response = await _supabase
          .from('municipios')
          .select('id, nombre, latitud, longitud, provincia_id')
          .eq('provincia_id', provinciaId)
          .ilike('nombre', '%$query%')
          .order('nombre');

      return (response as List)
          .map((m) => MunicipioModel.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<LocationModel?> getProvinciaById(int id) async {
    try {
      final response = await _supabase
          .from('provincias')
          .select('id, nombre')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return LocationModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  Future<MunicipioModel?> getMunicipioById(int id) async {
    try {
      final response = await _supabase
          .from('municipios')
          .select('id, nombre, latitud, longitud, provincia_id')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return MunicipioModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }
}
