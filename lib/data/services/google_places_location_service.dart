import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PlacePrediction {
  final String description;
  final String mainText;
  final String? secondaryText;
  final String placeId;

  PlacePrediction({
    required this.description,
    required this.mainText,
    this.secondaryText,
    required this.placeId,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      description: json['description'] as String,
      mainText: json['structured_formatting']?['main_text'] as String? ?? '',
      secondaryText:
          json['structured_formatting']?['secondary_text'] as String?,
      placeId: json['place_id'] as String,
    );
  }
}

class LocationData {
  final int id;
  final String nombre;
  final double? latitud;
  final double? longitud;
  final int? provinciaId;

  LocationData({
    required this.id,
    required this.nombre,
    this.latitud,
    this.longitud,
    this.provinciaId,
  });
}

class GooglePlacesLocationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  static const List<String> _spanishProvinces = [
    'A Coruña',
    'Álava',
    'Albacete',
    'Alicante',
    'Almería',
    'Asturias',
    'Ávila',
    'Badajoz',
    'Barcelona',
    'Burgos',
    'Cáceres',
    'Cádiz',
    'Cantabria',
    'Castellón',
    'Ceuta',
    'Ciudad Real',
    'Córdoba',
    'Cuenca',
    'Girona',
    'Granada',
    'Guadalajara',
    'Gipuzkoa',
    'Huelva',
    'Huesca',
    'Illes Balears',
    'Jaén',
    'La Rioja',
    'Las Palmas',
    'León',
    'Lleida',
    'Lugo',
    'Madrid',
    'Málaga',
    'Melilla',
    'Murcia',
    'Navarra',
    'Ourense',
    'Palencia',
    'Pontevedra',
    'Salamanca',
    'Santa Cruz de Tenerife',
    'Segovia',
    'Sevilla',
    'Soria',
    'Tarragona',
    'Teruel',
    'Toledo',
    'Valencia',
    'Valladolid',
    'Bizkaia',
    'Zamora',
    'Zaragoza',
  ];

  static String _normalizeText(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'Á': 'a',
      'À': 'a',
      'Ä': 'a',
      'Â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'É': 'e',
      'È': 'e',
      'Ë': 'e',
      'Ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'Í': 'i',
      'Ì': 'i',
      'Ï': 'i',
      'Î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'Ó': 'o',
      'Ò': 'o',
      'Ö': 'o',
      'Ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'Ú': 'u',
      'Ù': 'u',
      'Ü': 'u',
      'Û': 'u',
      'ñ': 'n',
      'Ñ': 'n',
      'ç': 'c',
      'Ç': 'c',
    };

    final buffer = StringBuffer();
    for (final char in value.runes) {
      final character = String.fromCharCode(char);
      buffer.write(replacements[character] ?? character.toLowerCase());
    }
    return buffer.toString();
  }

  /// Busca provincias españolas usando Google Places API
  Future<List<PlacePrediction>> searchProvincias(String query) async {
    if (query.isEmpty) return [];

    final normalizedQuery = _normalizeText(query.trim());

    final matches =
        _spanishProvinces
            .where(
              (provincia) =>
                  _normalizeText(provincia).contains(normalizedQuery),
            )
            .toList()
          ..sort();

    return matches
        .map(
          (provincia) => PlacePrediction(
            description: '$provincia, España',
            mainText: provincia,
            secondaryText: 'España',
            placeId: 'provincia-${_normalizeText(provincia)}',
          ),
        )
        .toList();
  }

  /// Busca municipios españoles usando Google Places API
  Future<List<PlacePrediction>> searchMunicipios(
    String provinciaName,
    String query,
  ) async {
    if (query.isEmpty || _apiKey.isEmpty) return [];

    try {
      final sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': '$query, $provinciaName, Spain',
          'key': _apiKey,
          'language': 'es',
          'components': 'country:es',
          'types': 'locality|administrative_area_level_3',
          'session_token': sessionToken,
        },
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final predictions = data['predictions'] as List<dynamic>?;

      if (predictions == null) return [];

      return predictions
          .map((p) => PlacePrediction.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Obtiene detalles de una ubicación (coordenadas)
  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    if (_apiKey.isEmpty) return null;

    try {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
            'place_id': placeId,
            'key': _apiKey,
            'fields': 'geometry,formatted_address,name,address_component',
            'language': 'es',
          });

      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['result'] as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  /// Verifica o crea una provincia, retorna su ID
  Future<int> getOrCreateProvincia(String provinciaName) async {
    try {
      // Intenta obtener la provincia existente
      final response = await _supabase
          .from('provincias')
          .select('id')
          .ilike('nombre', provinciaName)
          .maybeSingle();

      if (response != null) {
        return response['id'] as int;
      }

      // Si no existe, la crea
      final newResponse = await _supabase
          .from('provincias')
          .insert({'nombre': provinciaName})
          .select('id')
          .single();

      return newResponse['id'] as int;
    } catch (e) {
      throw Exception('Error al crear/obtener provincia: $e');
    }
  }

  /// Verifica o crea un municipio, retorna su ID
  Future<int> getOrCreateMunicipio({
    required String municipioName,
    required int provinciaId,
    required double latitud,
    required double longitud,
  }) async {
    try {
      // Intenta obtener el municipio existente
      final response = await _supabase
          .from('municipios')
          .select('id')
          .ilike('nombre', municipioName)
          .eq('provincia_id', provinciaId)
          .maybeSingle();

      if (response != null) {
        return response['id'] as int;
      }

      // Si no existe, lo crea
      final newResponse = await _supabase
          .from('municipios')
          .insert({
            'nombre': municipioName,
            'latitud': latitud,
            'longitud': longitud,
            'provincia_id': provinciaId,
          })
          .select('id')
          .single();

      return newResponse['id'] as int;
    } catch (e) {
      throw Exception('Error al crear/obtener municipio: $e');
    }
  }
}
