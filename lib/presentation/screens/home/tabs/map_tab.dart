import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:gotaxi/utils/pricing_constants.dart';
import 'package:gotaxi/utils/places_autocomplete_service.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  static const String _defaultOriginText = 'Mi ubicación actual';

  String get _googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  late PlacesAutocompleteService _placesService;

  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  final TextEditingController _originController = TextEditingController(
    text: _defaultOriginText,
  );
  final TextEditingController _destinationController = TextEditingController();
  final Set<Marker> _markers = <Marker>{};
  final Set<Polyline> _polylines = <Polyline>{};

  bool _loading = true;
  bool _loadingRoute = false;
  String? _error;
  String? _routeError;
  String? _distanceText;
  String? _durationText;
  // ignore: unused_field
  double? _distanceMeters;
  // ignore: unused_field
  double? _durationSeconds;
  double? _estimatedFareEur;

  // Autocomplete state
  List<PlacePrediction> _originSuggestions = [];
  List<PlacePrediction> _destinationSuggestions = [];
  bool _showOriginSuggestions = false;
  bool _showDestinationSuggestions = false;
  Timer? _originDebounce;
  Timer? _destinationDebounce;

  // ubicación por defecto
  static const LatLng _defaultPosition = LatLng(40.4168, -3.7038);

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _mapController?.dispose();
    _originDebounce?.cancel();
    _destinationDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _placesService = PlacesAutocompleteService(apiKey: _googleMapsApiKey);
    _originController.addListener(_onOriginChanged);
    _destinationController.addListener(_onDestinationChanged);
    _determinePosition();
  }

  void _onOriginChanged() {
    _originDebounce?.cancel();
    _originDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchOriginSuggestions(_originController.text);
    });
  }

  void _onDestinationChanged() {
    _destinationDebounce?.cancel();
    _destinationDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchDestinationSuggestions(_destinationController.text);
    });
  }

  Future<void> _fetchOriginSuggestions(String input) async {
    if (input == _defaultOriginText || input.isEmpty) {
      if (!mounted) return;
      setState(() {
        _originSuggestions = [];
        _showOriginSuggestions = false;
      });
      return;
    }

    final suggestions = await _placesService.getPredictions(input);
    if (!mounted) return;
    setState(() {
      _originSuggestions = suggestions;
      _showOriginSuggestions = suggestions.isNotEmpty;
    });
  }

  Future<void> _fetchDestinationSuggestions(String input) async {
    if (input.isEmpty) {
      if (!mounted) return;
      setState(() {
        _destinationSuggestions = [];
        _showDestinationSuggestions = false;
      });
      return;
    }

    final suggestions = await _placesService.getPredictions(input);
    if (!mounted) return;
    setState(() {
      _destinationSuggestions = suggestions;
      _showDestinationSuggestions = suggestions.isNotEmpty;
    });
  }

  void _selectOriginSuggestion(PlacePrediction prediction) {
    _originController.text = prediction.description;
    setState(() {
      _showOriginSuggestions = false;
      _originSuggestions = [];
    });
  }

  void _selectDestinationSuggestion(PlacePrediction prediction) {
    _destinationController.text = prediction.description;
    setState(() {
      _showDestinationSuggestions = false;
      _destinationSuggestions = [];
    });
  }

  Future<void> _determinePosition() async {
    try {
      // Comprobar si el servicio de ubicación está habilitado
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _error = 'El servicio de ubicación está desactivado';
          _loading = false;
        });
        return;
      }

      // Comprobar permisos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() {
            _error = 'Permisos de ubicación denegados';
            _loading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _error = 'Permisos de ubicación denegados permanentemente';
          _loading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _markers
          ..clear()
          ..add(
            Marker(
              markerId: const MarkerId('origin'),
              position: _currentPosition!,
              infoWindow: const InfoWindow(title: 'Origen'),
            ),
          );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al obtener la ubicación';
        _loading = false;
      });
    }
  }

  Future<LatLng> _resolvePointFromText(
    String input, {
    required bool isOrigin,
  }) async {
    final normalized = input.trim();
    final shouldUseCurrentLocation =
        isOrigin &&
        (normalized.isEmpty ||
            normalized.toLowerCase() == _defaultOriginText.toLowerCase());

    if (shouldUseCurrentLocation) {
      final current = _currentPosition;
      if (current == null) {
        throw Exception('No se pudo obtener tu ubicación actual');
      }
      return current;
    }

    if (normalized.isEmpty) {
      throw Exception(
        isOrigin ? 'Introduce un origen válido' : 'Introduce un destino válido',
      );
    }

    final locations = await locationFromAddress(normalized);
    if (locations.isEmpty) {
      throw Exception(
        isOrigin ? 'No se encontró el origen' : 'No se encontró el destino',
      );
    }

    final first = locations.first;
    return LatLng(first.latitude, first.longitude);
  }

  Future<void> _searchRoute() async {
    if (_loadingRoute) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    try {
      final origin = await _resolvePointFromText(
        _originController.text,
        isOrigin: true,
      );
      final destination = await _resolvePointFromText(
        _destinationController.text,
        isOrigin: false,
      );

      if (_googleMapsApiKey.isEmpty) {
        throw Exception('Falta GOOGLE_MAPS_API_KEY en el archivo .env');
      }

      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
            'origin': '${origin.latitude},${origin.longitude}',
            'destination': '${destination.latitude},${destination.longitude}',
            'mode': 'driving',
            'language': 'es',
            'key': _googleMapsApiKey,
          });

      final response = await http.get(uri);
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final status = (data['status'] as String?) ?? 'UNKNOWN_ERROR';

      if (status != 'OK') {
        final apiError =
            (data['error_message'] as String?) ?? 'No se pudo calcular la ruta';
        throw Exception(apiError);
      }

      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw Exception('No se encontraron rutas para este trayecto');
      }

      final route = routes.first as Map<String, dynamic>;
      final legs = route['legs'] as List<dynamic>;
      if (legs.isEmpty) {
        throw Exception('No hay información de distancia y tiempo');
      }

      final leg = legs.first as Map<String, dynamic>;
      final distance = leg['distance'] as Map<String, dynamic>?;
      final duration = leg['duration'] as Map<String, dynamic>?;
      final overviewPolyline =
          route['overview_polyline'] as Map<String, dynamic>?;
      final encodedPolyline = overviewPolyline?['points'] as String?;

      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        throw Exception('No se pudo dibujar la ruta');
      }

      final routePoints = _decodePolyline(encodedPolyline);

      // Extract numeric values for fare calculation
      final distanceMeters = (distance?['value'] as num?)?.toDouble() ?? 0.0;
      final durationSeconds = (duration?['value'] as num?)?.toDouble() ?? 0.0;
      final kilometers = distanceMeters / 1000;
      final minutes = durationSeconds / 60;
      final estimatedFare = PricingConstants.calculateEstimatedFare(
        kilometers: kilometers,
        minutes: minutes,
      );

      if (!mounted) return;
      setState(() {
        _distanceText = (distance?['text'] as String?) ?? '-';
        _durationText = (duration?['text'] as String?) ?? '-';
        _distanceMeters = distanceMeters;
        _durationSeconds = durationSeconds;
        _estimatedFareEur = estimatedFare;
        _markers
          ..clear()
          ..add(
            Marker(
              markerId: const MarkerId('origin'),
              position: origin,
              infoWindow: const InfoWindow(title: 'Origen'),
            ),
          )
          ..add(
            Marker(
              markerId: const MarkerId('destination'),
              position: destination,
              infoWindow: const InfoWindow(title: 'Destino'),
            ),
          );
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('route_driving'),
              points: routePoints,
              width: 5,
              color: Theme.of(context).colorScheme.primary,
            ),
          );
      });

      await _fitMapToRoute(routePoints);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routeError = e.toString().replaceFirst('Exception: ', '');
        _distanceMeters = null;
        _durationSeconds = null;
        _estimatedFareEur = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
        });
      }
    }
  }

  Future<void> _fitMapToRoute(List<LatLng> points) async {
    if (_mapController == null || points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 90),
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += deltaLat;

      shift = 0;
      result = 0;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += deltaLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final LatLng target = _currentPosition ?? _defaultPosition;

    final theme = Theme.of(context);
    final panelColor =
        theme.navigationBarTheme.backgroundColor ?? theme.colorScheme.surface;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: target, zoom: 15),
          onMapCreated: (controller) {
            _mapController = controller;
          },
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 14,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.gps_fixed_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _originController,
                            textInputAction: TextInputAction.next,
                            onTap: () {
                              if (_originController.text ==
                                  _defaultOriginText) {
                                _originController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: _originController.text.length,
                                );
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Origen',
                              filled: true,
                              fillColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showOriginSuggestions) ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            left: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            right: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _originSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _originSuggestions[index];
                            return InkWell(
                              onTap: () => _selectOriginSuggestion(suggestion),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      suggestion.mainText.isNotEmpty
                                          ? suggestion.mainText
                                          : suggestion.description,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                    ),
                                    if (suggestion.secondaryText != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        suggestion.secondaryText!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.location_pin,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _destinationController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _searchRoute(),
                            decoration: InputDecoration(
                              hintText: 'Destino',
                              filled: true,
                              fillColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showDestinationSuggestions) ...[
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            left: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            right: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _destinationSuggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _destinationSuggestions[index];
                            return InkWell(
                              onTap: () =>
                                  _selectDestinationSuggestion(suggestion),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      suggestion.mainText.isNotEmpty
                                          ? suggestion.mainText
                                          : suggestion.description,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                    ),
                                    if (suggestion.secondaryText != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        suggestion.secondaryText!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                if (_loadingRoute) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
                if (_routeError != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _routeError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
                if (_distanceText != null && _durationText != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.route_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text('$_distanceText'),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text('$_durationText'),
                    ],
                  ),
                  if (_estimatedFareEur != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.local_taxi_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Precio aprox.: ${_estimatedFareEur!.toStringAsFixed(2)} ${PricingConstants.currencySymbol}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {},
                        child: const Text('Pedir ahora'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {},
                        child: const Text('Reservar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
