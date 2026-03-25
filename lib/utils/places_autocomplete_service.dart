import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacesAutocompleteService {
  final String apiKey;
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const int _minCharacters = 4;
  static const String _componentRestriction = 'es'; // Spain only

  PlacesAutocompleteService({required this.apiKey});

  /// Get autocomplete suggestions for a given input text.
  /// Returns a list of place predictions or empty list if input is too short.
  Future<List<PlacePrediction>> getPredictions(String input) async {
    if (input.isEmpty || input.length < _minCharacters) {
      return [];
    }

    try {
      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: {
          'input': input,
          'key': apiKey,
          'language': 'es', // Spanish language
          'components': 'country:$_componentRestriction',
          'types': 'geocode', // Any type related to location/address
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final status = json['status'] as String?;

      if (status != 'OK' && status != 'ZERO_RESULTS') {
        return [];
      }

      final predictions = json['predictions'] as List<dynamic>? ?? [];
      return predictions
          .cast<Map<String, dynamic>>()
          .map((p) => PlacePrediction.fromJson(p))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String? secondaryText;

  PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structuredFormatting =
        json['structured_formatting'] as Map<String, dynamic>?;
    final mainText =
        (structuredFormatting?['main_text'] as String?) ??
        (json['description'] as String?) ??
        '';
    final secondaryText = structuredFormatting?['secondary_text'] as String?;

    return PlacePrediction(
      placeId: json['place_id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      mainText: mainText,
      secondaryText: secondaryText,
    );
  }
}
