import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/google_places_location_service.dart';
import 'package:gotaxi/data/services/taxista_service.dart';
import 'package:gotaxi/domain/validators/dni_validator.dart';

class CrearTaxistaScreen extends StatefulWidget {
  const CrearTaxistaScreen({super.key});

  @override
  State<CrearTaxistaScreen> createState() => _CrearTaxistaScreenState();
}

class _CrearTaxistaScreenState extends State<CrearTaxistaScreen> {
  final _taxistaService = TaxistaService();
  final _googlePlacesService = GooglePlacesLocationService();

  // Paso 1: Datos del taxista
  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _dniController = TextEditingController();

  // Paso 2: Datos del vehículo
  final _licenciaTaxiController = TextEditingController();
  final _matriculaController = TextEditingController();
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _colorController = TextEditingController();
  final _capacidadController = TextEditingController();

  // Estado general
  int _currentStep = 0;
  bool _loading = false;
  bool _isAdmin = false;
  bool _minusvalido = false;

  // Provincias y municipios
  List<PlacePrediction> _provinciasSugerencias = [];
  List<PlacePrediction> _municipiosSugerencias = [];
  PlacePrediction? _selectedProvincia;
  PlacePrediction? _selectedMunicipio;

  // Controllers para búsqueda
  final _provinciaSearchController = TextEditingController();
  final _municipioSearchController = TextEditingController();

  // Estado de dropdowns
  bool _showProvinciaDropdown = false;
  bool _showMunicipioDropdown = false;
  bool _selectingProvincia = false;
  bool _selectingMunicipio = false;

  final _formKey1 = GlobalKey<FormState>();
  final _formKey2 = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _provinciaSearchController.addListener(() {
      _searchProvincias(_provinciaSearchController.text);
    });
    _municipioSearchController.addListener(() {
      _searchMunicipios(_municipioSearchController.text);
    });
  }

  Future<void> _searchProvincias(String query) async {
    if (_selectingProvincia) return;
    if (query.isEmpty) {
      setState(() {
        _provinciasSugerencias = [];
        _showProvinciaDropdown = false;
      });
      return;
    }

    try {
      final suggestions = await _googlePlacesService.searchProvincias(query);
      if (!mounted) return;
      setState(() {
        _provinciasSugerencias = suggestions;
        _showProvinciaDropdown = suggestions.isNotEmpty;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al buscar provincias: $e')),
        );
      }
    }
  }

  Future<void> _searchMunicipios(String query) async {
    if (_selectingMunicipio) return;
    if (_selectedProvincia == null) return;

    if (query.isEmpty) {
      setState(() {
        _municipiosSugerencias = [];
        _showMunicipioDropdown = false;
      });
      return;
    }

    try {
      final suggestions = await _googlePlacesService.searchMunicipios(
        _selectedProvincia!.mainText,
        query,
      );
      if (!mounted) return;
      setState(() {
        _municipiosSugerencias = suggestions;
        _showMunicipioDropdown = suggestions.isNotEmpty;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al buscar municipios: $e')),
        );
      }
    }
  }

  Future<void> _selectProvincia(PlacePrediction provincia) async {
    _selectingProvincia = true;
    setState(() {
      _selectedProvincia = provincia;
      _provinciaSearchController.text = provincia.mainText;
      _showProvinciaDropdown = false;
      _selectedMunicipio = null;
      _municipioSearchController.clear();
      _municipiosSugerencias = [];
    });
    _selectingProvincia = false;
  }

  Future<void> _selectMunicipio(PlacePrediction municipio) async {
    _selectingMunicipio = true;
    setState(() {
      _selectedMunicipio = municipio;
      _municipioSearchController.text = municipio.mainText;
      _showMunicipioDropdown = false;
    });
    _selectingMunicipio = false;
  }

  Future<void> _createTaxista() async {
    if (!_formKey1.currentState!.validate() ||
        !_formKey2.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, rellena todos los campos correctamente'),
        ),
      );
      return;
    }

    if (_selectedProvincia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona una provincia')),
      );
      return;
    }

    if (_selectedMunicipio == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona un municipio')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Obtener detalles del municipio para coordenadas
      final municipioDetails = await _googlePlacesService.getPlaceDetails(
        _selectedMunicipio!.placeId,
      );

      double latitud = 40.4168; // Madrid por defecto
      double longitud = -3.7038;

      if (municipioDetails != null) {
        final geometry = municipioDetails['geometry'] as Map<String, dynamic>?;
        if (geometry != null) {
          final location = geometry['location'] as Map<String, dynamic>?;
          if (location != null) {
            latitud = (location['lat'] as num).toDouble();
            longitud = (location['lng'] as num).toDouble();
          }
        }
      }

      // Crear o obtener provincia
      final provinciaId = await _googlePlacesService.getOrCreateProvincia(
        _selectedProvincia!.mainText,
      );

      // Crear o obtener municipio
      final municipioId = await _googlePlacesService.getOrCreateMunicipio(
        municipioName: _selectedMunicipio!.mainText,
        provinciaId: provinciaId,
        latitud: latitud,
        longitud: longitud,
      );

      final capacidad = int.tryParse(_capacidadController.text) ?? 4;

      await _taxistaService.createTaxista(
        nombre: _nombreController.text.trim(),
        apellidos: _apellidosController.text.trim(),
        email: _emailController.text.trim(),
        telefono: _telefonoController.text.trim(),
        dni: _dniController.text.trim(),
        municipioId: municipioId,
        capacidad: capacidad,
        isAdmin: _isAdmin,
        licenciaTaxi: _licenciaTaxiController.text.trim(),
        matricula: _matriculaController.text.trim(),
        marca: _marcaController.text.trim(),
        modelo: _modeloController.text.trim(),
        color: _colorController.text.trim(),
        minusvalido: _minusvalido,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Taxista creado correctamente'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al crear taxista: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidosController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _dniController.dispose();
    _licenciaTaxiController.dispose();
    _matriculaController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _colorController.dispose();
    _capacidadController.dispose();
    _provinciaSearchController.dispose();
    _municipioSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear Taxista'), centerTitle: true),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            children: [
              // Stepper
              Row(
                children: [
                  _buildStepIndicator(
                    number: 1,
                    label: 'Datos del Taxista',
                    isActive: _currentStep >= 0,
                    isCompleted: _currentStep > 0,
                    colorScheme: colorScheme,
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: _currentStep > 0
                          ? colorScheme.primary
                          : colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  _buildStepIndicator(
                    number: 2,
                    label: 'Vehículo',
                    isActive: _currentStep >= 1,
                    isCompleted: _currentStep > 1,
                    colorScheme: colorScheme,
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Contenido del paso actual
              if (_currentStep == 0)
                _buildStep1(colorScheme)
              else
                _buildStep2(colorScheme),

              const SizedBox(height: 32),

              // Botones de navegación
              Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() => _currentStep = 0),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Atrás'),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () {
                              if (_currentStep == 0) {
                                if (_formKey1.currentState!.validate() &&
                                    _selectedProvincia != null &&
                                    _selectedMunicipio != null) {
                                  setState(() => _currentStep = 1);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Por favor, rellena todos los campos',
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                _createTaxista();
                              }
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _currentStep == 0 ? 'Siguiente' : 'Crear Taxista',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator({
    required int number,
    required String label,
    required bool isActive,
    required bool isCompleted,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? Colors.green
                : isActive
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, color: Colors.white, size: 24)
                : Text(
                    '$number',
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? colorScheme.primary : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1(ColorScheme colorScheme) {
    return Form(
      key: _formKey1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información Personal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _nombreController,
            label: 'Nombre',
            icon: Icons.person_outline,
            validator: (v) =>
                v?.isEmpty ?? true ? 'El nombre es obligatorio' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _apellidosController,
            label: 'Apellidos',
            icon: Icons.people_outline,
            validator: (v) =>
                v?.isEmpty ?? true ? 'Los apellidos son obligatorios' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _emailController,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v?.isEmpty ?? true) return 'El email es obligatorio';
              if (!v!.contains('@')) return 'Email inválido';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _telefonoController,
            label: 'Teléfono',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (v) =>
                v?.isEmpty ?? true ? 'El teléfono es obligatorio' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _dniController,
            label: 'DNI/NIE',
            icon: Icons.card_giftcard_outlined,
            validator: (v) {
              if (v?.isEmpty ?? true) return 'El DNI es obligatorio';
              if (!validarDniNie(v!)) return 'DNI/NIE inválido';
              return null;
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Ubicación de Trabajo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          // Provincia
          _buildLocationField(
            label: 'Provincia',
            icon: Icons.location_on_outlined,
            controller: _provinciaSearchController,
            selectedValue: _selectedProvincia?.mainText,
            showDropdown: _showProvinciaDropdown,
            suggestions: _provinciasSugerencias,
            onChanged: _searchProvincias,
            onItemSelected: _selectProvincia,
          ),
          const SizedBox(height: 16),
          // Municipio
          _buildLocationField(
            label: 'Municipio',
            icon: Icons.location_city_outlined,
            controller: _municipioSearchController,
            selectedValue: _selectedMunicipio?.mainText,
            showDropdown: _showMunicipioDropdown && _selectedProvincia != null,
            suggestions: _municipiosSugerencias,
            onChanged: _selectedProvincia == null ? null : _searchMunicipios,
            onItemSelected: _selectMunicipio,
            enabled: _selectedProvincia != null,
          ),
          const SizedBox(height: 24),
          const Text(
            'Permisos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            title: const Text('Es administrador'),
            subtitle: const Text(
              'Los administradores podrán gestionar tarifa del municipio y diversas configuraciones del sistema.',
            ),
            value: _isAdmin,
            onChanged: (value) => setState(() => _isAdmin = value ?? false),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(ColorScheme colorScheme) {
    return Form(
      key: _formKey2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información del Vehículo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _buildTextFormField(
            controller: _licenciaTaxiController,
            label: 'Licencia de Taxi',
            icon: Icons.card_travel_outlined,
            validator: (v) =>
                v?.isEmpty ?? true ? 'La licencia es obligatoria' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _matriculaController,
            label: 'Matrícula',
            icon: Icons.confirmation_number,
            validator: (v) =>
                v?.isEmpty ?? true ? 'La matrícula es obligatoria' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _marcaController,
            label: 'Marca',
            icon: Icons.directions_car,
            validator: (v) =>
                v?.isEmpty ?? true ? 'La marca es obligatoria' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _modeloController,
            label: 'Modelo',
            icon: Icons.directions_car_outlined,
            validator: (v) =>
                v?.isEmpty ?? true ? 'El modelo es obligatorio' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _colorController,
            label: 'Color',
            icon: Icons.palette_outlined,
            validator: (v) =>
                v?.isEmpty ?? true ? 'El color es obligatorio' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _capacidadController,
            label: 'Capacidad (personas)',
            icon: Icons.group_outlined,
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v?.isEmpty ?? true) return 'La capacidad es obligatoria';
              if (int.tryParse(v!) == null) return 'Debe ser un número';
              return null;
            },
          ),
          const SizedBox(height: 24),
          CheckboxListTile(
            title: const Text('Vehículo para minusválidos'),
            value: _minusvalido,
            onChanged: (value) => setState(() => _minusvalido = value ?? false),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildLocationField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String? selectedValue,
    required bool showDropdown,
    required List<PlacePrediction> suggestions,
    required Function(String)? onChanged,
    required Function(PlacePrediction) onItemSelected,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        TextFormField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          onChanged: onChanged,
        ),
        if (showDropdown) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border.all(color: colorScheme.outline),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final item = suggestions[index];
                return ListTile(
                  title: Text(item.mainText),
                  subtitle: item.secondaryText != null
                      ? Text(
                          item.secondaryText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => onItemSelected(item),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
