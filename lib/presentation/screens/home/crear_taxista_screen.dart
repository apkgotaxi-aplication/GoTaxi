import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/google_places_location_service.dart';
import 'package:gotaxi/data/services/taxista_service.dart';
import 'package:gotaxi/domain/validators/dni_validator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  final _emailFocusNode = FocusNode();
  final _telefonoFocusNode = FocusNode();
  final _dniFocusNode = FocusNode();
  final _licenciaTaxiFocusNode = FocusNode();
  final _matriculaFocusNode = FocusNode();
  final _provinciaFocusNode = FocusNode();
  final _municipioFocusNode = FocusNode();

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

  String? _backendErrorField;
  String? _backendErrorMessage;

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
      if (_backendErrorField == 'provincia') {
        _backendErrorField = null;
        _backendErrorMessage = null;
      }
    });
    _selectingProvincia = false;
  }

  Future<void> _selectMunicipio(PlacePrediction municipio) async {
    _selectingMunicipio = true;
    setState(() {
      _selectedMunicipio = municipio;
      _municipioSearchController.text = municipio.mainText;
      _showMunicipioDropdown = false;
      if (_backendErrorField == 'municipio') {
        _backendErrorField = null;
        _backendErrorMessage = null;
      }
    });
    _selectingMunicipio = false;
  }

  Future<void> _createTaxista() async {
    _clearBackendError();

    final formStep1Valid = _formKey1.currentState?.validate() ?? true;
    final formStep2Valid = _formKey2.currentState?.validate() ?? false;

    if (!formStep1Valid || !formStep2Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, rellena todos los campos correctamente'),
        ),
      );
      return;
    }

    if (_selectedProvincia == null) {
      _applyBackendFieldError(
        field: 'provincia',
        message: 'Campo Provincia: selecciona una provincia válida.',
      );
      return;
    }

    if (_selectedMunicipio == null) {
      _applyBackendFieldError(
        field: 'municipio',
        message: 'Campo Municipio: selecciona un municipio válido.',
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
    } on AuthException catch (e) {
      if (mounted) {
        final mapped = _mapCreateTaxistaError(e.message);
        _applyBackendFieldError(field: mapped.field, message: mapped.message);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final rawError = [
          e.code,
          e.message,
          e.details,
          e.hint,
        ].whereType<String>().join(' ');
        final mapped = _mapCreateTaxistaError(rawError);
        _applyBackendFieldError(field: mapped.field, message: mapped.message);
      }
    } catch (e) {
      if (mounted) {
        final mapped = _mapCreateTaxistaError(e.toString());
        _applyBackendFieldError(field: mapped.field, message: mapped.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearBackendError() {
    if (_backendErrorField == null && _backendErrorMessage == null) return;
    setState(() {
      _backendErrorField = null;
      _backendErrorMessage = null;
    });
  }

  void _clearBackendErrorIfMatches(String field) {
    if (_backendErrorField != field) return;
    _clearBackendError();
  }

  void _applyBackendFieldError({String? field, required String message}) {
    setState(() {
      _backendErrorField = field;
      _backendErrorMessage = message;
      if (field == 'licenciaTaxi' || field == 'matricula') {
        _currentStep = 1;
      }
      if (field == 'provincia' || field == 'municipio') {
        _currentStep = 0;
      }
    });

    _focusField(field);
    _showCreateTaxistaError(message);
  }

  void _focusField(String? field) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (field) {
        case 'email':
          _emailFocusNode.requestFocus();
          break;
        case 'telefono':
          _telefonoFocusNode.requestFocus();
          break;
        case 'dni':
          _dniFocusNode.requestFocus();
          break;
        case 'licenciaTaxi':
          _licenciaTaxiFocusNode.requestFocus();
          break;
        case 'matricula':
          _matriculaFocusNode.requestFocus();
          break;
        case 'provincia':
          _provinciaFocusNode.requestFocus();
          break;
        case 'municipio':
          _municipioFocusNode.requestFocus();
          break;
      }
    });
  }

  void _showCreateTaxistaError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  ({String? field, String message}) _mapCreateTaxistaError(String rawError) {
    final error = rawError.toLowerCase();

    if (error.contains('user already registered') ||
        error.contains('already registered')) {
      return (
        field: 'email',
        message:
            'Campo Email: este correo ya existe en autenticación. Se intentará reutilizar para crear el taxista.',
      );
    }

    if (error.contains('usuarios_id_fkey') ||
        error.contains('usuario no encontrado')) {
      return (
        field: 'email',
        message:
            'Campo Email: existe en autenticación pero faltaba su perfil. Reintenta crear el taxista.',
      );
    }

    if (error.contains('unexpected failure') ||
        error.contains('please check server logs') ||
        error.contains('sqlstate 42501') ||
        error.contains('permission denied for table usuarios')) {
      return (
        field: null,
        message:
            'Error de permisos en el alta de usuario (Auth/BD). Ya está corregido en servidor; vuelve a intentarlo.',
      );
    }

    if (error.contains('email') &&
        (error.contains('already') ||
            error.contains('exists') ||
            error.contains('duplicate') ||
            error.contains('registered'))) {
      return (
        field: 'email',
        message: 'Campo Email: ya existe un usuario con ese correo.',
      );
    }

    if (error.contains('usuarios_email_key')) {
      return (
        field: 'email',
        message: 'Campo Email: ya existe un usuario con ese correo.',
      );
    }

    if (error.contains('dni') &&
        (error.contains('duplicate') || error.contains('unique'))) {
      return (field: 'dni', message: 'Campo DNI/NIE: ya está registrado.');
    }

    if (error.contains('usuarios_dni_key')) {
      return (field: 'dni', message: 'Campo DNI/NIE: ya está registrado.');
    }

    if (error.contains('telefono') &&
        (error.contains('duplicate') || error.contains('unique'))) {
      return (
        field: 'telefono',
        message: 'Campo Teléfono: ya está registrado.',
      );
    }

    if (error.contains('usuarios_telefono_key')) {
      return (
        field: 'telefono',
        message: 'Campo Teléfono: ya está registrado.',
      );
    }

    if (error.contains('matricula') &&
        (error.contains('duplicate') || error.contains('unique'))) {
      return (
        field: 'matricula',
        message: 'Campo Matrícula: ya está registrada.',
      );
    }

    if (error.contains('vehiculos_matricula_key')) {
      return (
        field: 'matricula',
        message: 'Campo Matrícula: ya está registrada.',
      );
    }

    if (error.contains('licencia_taxi') || error.contains('licencia')) {
      if (error.contains('duplicate') || error.contains('unique')) {
        return (
          field: 'licenciaTaxi',
          message: 'Campo Licencia de Taxi: ya está registrada.',
        );
      }
    }

    if (error.contains('vehiculos_licencia_taxi_key')) {
      return (
        field: 'licenciaTaxi',
        message: 'Campo Licencia de Taxi: ya está registrada.',
      );
    }

    if (error.contains('municipio_id') || error.contains('municipio')) {
      return (
        field: 'municipio',
        message: 'Campo Municipio: selecciona un municipio válido.',
      );
    }

    if (error.contains('rangeerror')) {
      return (
        field: null,
        message:
            'Error interno al generar credenciales del taxista. Inténtalo de nuevo.',
      );
    }

    return (
      field: null,
      message:
          'No se pudo crear el taxista. Error técnico: ${rawError.length > 120 ? '${rawError.substring(0, 120)}...' : rawError}',
    );
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
    _emailFocusNode.dispose();
    _telefonoFocusNode.dispose();
    _dniFocusNode.dispose();
    _licenciaTaxiFocusNode.dispose();
    _matriculaFocusNode.dispose();
    _provinciaFocusNode.dispose();
    _municipioFocusNode.dispose();
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
            fieldKey: 'email',
            focusNode: _emailFocusNode,
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
            fieldKey: 'telefono',
            focusNode: _telefonoFocusNode,
            keyboardType: TextInputType.phone,
            validator: (v) =>
                v?.isEmpty ?? true ? 'El teléfono es obligatorio' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _dniController,
            label: 'DNI/NIE',
            icon: Icons.card_giftcard_outlined,
            fieldKey: 'dni',
            focusNode: _dniFocusNode,
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
            fieldKey: 'provincia',
            focusNode: _provinciaFocusNode,
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
            fieldKey: 'municipio',
            focusNode: _municipioFocusNode,
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
            fieldKey: 'licenciaTaxi',
            focusNode: _licenciaTaxiFocusNode,
            validator: (v) =>
                v?.isEmpty ?? true ? 'La licencia es obligatoria' : null,
          ),
          const SizedBox(height: 16),
          _buildTextFormField(
            controller: _matriculaController,
            label: 'Matrícula',
            icon: Icons.confirmation_number,
            fieldKey: 'matricula',
            focusNode: _matriculaFocusNode,
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
    String? fieldKey,
    FocusNode? focusNode,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final backendErrorText = fieldKey != null && _backendErrorField == fieldKey
        ? _backendErrorMessage
        : null;

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: (_) {
        if (fieldKey != null) {
          _clearBackendErrorIfMatches(fieldKey);
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        errorText: backendErrorText,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
    );
  }

  Widget _buildLocationField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String? selectedValue,
    String? fieldKey,
    FocusNode? focusNode,
    required bool showDropdown,
    required List<PlacePrediction> suggestions,
    required Function(String)? onChanged,
    required Function(PlacePrediction) onItemSelected,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final backendErrorText = fieldKey != null && _backendErrorField == fieldKey
        ? _backendErrorMessage
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          onChanged: (value) {
            if (fieldKey != null) {
              _clearBackendErrorIfMatches(fieldKey);
            }
            onChanged?.call(value);
          },
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            errorText: backendErrorText,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.error, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
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
