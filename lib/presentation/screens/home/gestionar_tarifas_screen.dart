import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/google_places_location_service.dart';
import 'package:gotaxi/data/services/tarifa_service.dart';

class GestionarTarifasScreen extends StatefulWidget {
  const GestionarTarifasScreen({super.key});

  @override
  State<GestionarTarifasScreen> createState() => _GestionarTarifasScreenState();
}

class _GestionarTarifasScreenState extends State<GestionarTarifasScreen> {
  final GooglePlacesLocationService _placesService =
      GooglePlacesLocationService();
  final TarifaService _tarifaService = TarifaService();

  final TextEditingController _provinciaController = TextEditingController();
  final TextEditingController _municipioController = TextEditingController();

  List<PlacePrediction> _provincias = [];
  List<PlacePrediction> _municipios = [];

  PlacePrediction? _selectedProvincia;
  int? _selectedProvinciaId;

  List<TarifaMunicipioView> _tarifas = [];

  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _provinciaController.addListener(_onProvinciaChanged);
    _municipioController.addListener(_onMunicipioChanged);
  }

  @override
  void dispose() {
    _provinciaController.dispose();
    _municipioController.dispose();
    super.dispose();
  }

  Future<void> _onProvinciaChanged() async {
    final query = _provinciaController.text.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _provincias = [];
      });
      return;
    }

    final list = await _placesService.searchProvincias(query);
    if (!mounted) return;
    setState(() {
      _provincias = list;
    });
  }

  Future<void> _onMunicipioChanged() async {
    final query = _municipioController.text.trim();
    if (query.isEmpty || _selectedProvincia == null) {
      if (!mounted) return;
      setState(() {
        _municipios = [];
      });
      return;
    }

    final list = await _placesService.searchMunicipios(
      _selectedProvincia!.mainText,
      query,
    );
    if (!mounted) return;
    setState(() {
      _municipios = list;
    });
  }

  Future<void> _selectProvincia(PlacePrediction provincia) async {
    setState(() {
      _selectedProvincia = provincia;
      _selectedProvinciaId = null;
      _provinciaController.text = provincia.mainText;
      _provincias = [];
      _tarifas = [];
      _error = null;
    });

    await _loadTarifasForCurrentProvincia();
  }

  Future<void> _loadTarifasForCurrentProvincia() async {
    final provincia = _selectedProvincia;
    if (provincia == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final provinciaId = await _placesService.getOrCreateProvincia(
        provincia.mainText,
      );

      final tarifas = await _tarifaService.getMunicipiosConTarifaByProvincia(
        provinciaId: provinciaId,
      );

      if (!mounted) return;
      setState(() {
        _selectedProvinciaId = provinciaId;
        _tarifas = tarifas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las tarifas: $e';
        _loading = false;
      });
    }
  }

  Future<void> _addMunicipioFromGoogle(PlacePrediction municipio) async {
    final provinciaId = _selectedProvinciaId;
    if (provinciaId == null) return;

    setState(() => _saving = true);
    try {
      final details = await _placesService.getPlaceDetails(municipio.placeId);
      final geometry = details?['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();

      if (lat == null || lng == null) {
        throw StateError(
          'No se encontraron coordenadas validas para el municipio.',
        );
      }

      await _placesService.getOrCreateMunicipio(
        municipioName: municipio.mainText,
        provinciaId: provinciaId,
        latitud: lat,
        longitud: lng,
      );

      if (!mounted) return;
      _municipioController.clear();
      setState(() {
        _municipios = [];
      });
      await _loadTarifasForCurrentProvincia();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Municipio creado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el municipio: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editTarifa(TarifaMunicipioView tarifa) async {
    final precioKmController = TextEditingController(
      text: tarifa.precioKm.toStringAsFixed(2),
    );
    final precioHoraController = TextEditingController(
      text: tarifa.precioHora.toStringAsFixed(2),
    );

    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Tarifa de ${tarifa.municipioNombre}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: precioKmController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Precio por km'),
                  validator: (value) {
                    final parsed = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    if (parsed == null || parsed <= 0) {
                      return 'Introduce un valor mayor que 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: precioHoraController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Precio por hora (base por minuto en app)',
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    if (parsed == null || parsed < 0) {
                      return 'Introduce un valor valido';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (saved != true) return;

    setState(() => _saving = true);
    try {
      final precioKm = double.parse(
        precioKmController.text.replaceAll(',', '.'),
      );
      final precioHora = double.parse(
        precioHoraController.text.replaceAll(',', '.'),
      );

      final result = await _tarifaService.upsertTarifaMunicipio(
        municipioId: tarifa.municipioId,
        precioKm: precioKm,
        precioHora: precioHora,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success
              ? Colors.green.shade700
              : Colors.red.shade700,
        ),
      );

      if (result.success) {
        await _loadTarifasForCurrentProvincia();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la tarifa: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar tarifas')),
      body: RefreshIndicator(
        onRefresh: _loadTarifasForCurrentProvincia,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _provinciaController,
              decoration: const InputDecoration(
                labelText: 'Buscar provincia',
                prefixIcon: Icon(Icons.map_outlined),
              ),
            ),
            if (_provincias.isNotEmpty)
              Card(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _provincias.length,
                  itemBuilder: (context, index) {
                    final provincia = _provincias[index];
                    return ListTile(
                      title: Text(provincia.mainText),
                      subtitle: Text(provincia.secondaryText ?? 'España'),
                      onTap: () => _selectProvincia(provincia),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            if (_selectedProvincia != null) ...[
              Text(
                'Municipios de ${_selectedProvincia!.mainText}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _municipioController,
                decoration: const InputDecoration(
                  labelText: 'Agregar municipio con Google Places',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              if (_municipios.isNotEmpty)
                Card(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _municipios.length,
                    itemBuilder: (context, index) {
                      final municipio = _municipios[index];
                      return ListTile(
                        title: Text(municipio.mainText),
                        subtitle: Text(municipio.secondaryText ?? ''),
                        trailing: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        onTap: _saving
                            ? null
                            : () => _addMunicipioFromGoogle(municipio),
                      );
                    },
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red.shade700))
            else if (_selectedProvincia == null)
              const Text('Selecciona una provincia para ver y editar tarifas.')
            else if (_tarifas.isEmpty)
              const Text('No hay municipios disponibles para esta provincia.')
            else
              ..._tarifas.map(
                (tarifa) => Card(
                  child: ListTile(
                    title: Text(tarifa.municipioNombre),
                    subtitle: Text(
                      'Km: ${tarifa.precioKm.toStringAsFixed(2)} | Hora: ${tarifa.precioHora.toStringAsFixed(2)}'
                      '${tarifa.isDefault ? ' (default)' : ''}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _saving ? null : () => _editTarifa(tarifa),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
