import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gotaxi/presentation/screens/auth/auth_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _supabase = Supabase.instance.client;

  final _nombreController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _isCliente = false;
  bool _editMode = false;
  String? _error;
  String _userRole = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() => _error = 'No se encontró el usuario');
        return;
      }

      // Cargar datos del usuario desde user_metadata
      final metadata = user.userMetadata ?? {};
      _nombreController.text = metadata['nombre'] ?? '';
      _apellidosController.text = metadata['apellidos'] ?? '';
      _emailController.text = user.email ?? '';
      _telefonoController.text = metadata['telefono'] ?? '';

      // Verificar rol del usuario en la tabla 'usuarios'
      final response = await _supabase
          .from('usuarios')
          .select('rol')
          .eq('id', user.id)
          .maybeSingle();

      if (response != null && response['rol'] != null) {
        _userRole = response['rol'].toString();
        _isCliente = _userRole == 'cliente';
      } else {
        _isCliente = false;
        _userRole = 'desconocido';
      }
    } catch (e) {
      _error = 'Error al cargar el perfil: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Actualizar user_metadata en Supabase Auth
      await _supabase.auth.updateUser(
        UserAttributes(
          email: _emailController.text.trim(),
          data: {
            'nombre': _nombreController.text.trim(),
            'apellidos': _apellidosController.text.trim(),
            'telefono': _telefonoController.text.trim(),
          },
        ),
      );

      // Actualizar en la tabla 'usuarios'
      await _supabase
          .from('usuarios')
          .update({
            'nombre': _nombreController.text.trim(),
            'apellidos': _apellidosController.text.trim(),
            'email': _emailController.text.trim(),
            'telefono': _telefonoController.text.trim(),
          })
          .eq('id', user.id);

      if (mounted) {
        setState(() => _editMode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Perfil actualizado correctamente'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  String _getInitials() {
    final nombre = _nombreController.text.trim();
    final apellidos = _apellidosController.text.trim();
    String initials = '';
    if (nombre.isNotEmpty) initials += nombre[0].toUpperCase();
    if (apellidos.isNotEmpty) initials += apellidos[0].toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loadProfile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header con avatar y nombre
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.3),
                    colorScheme.surface,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [colorScheme.primary, colorScheme.tertiary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _getInitials(),
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Nombre completo
                      Text(
                        '${_nombreController.text} ${_apellidosController.text}'
                            .trim(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Rol badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _isCliente
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isCliente
                                ? Colors.green.withValues(alpha: 0.5)
                                : Colors.orange.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _userRole.isNotEmpty
                              ? _userRole[0].toUpperCase() +
                                    _userRole.substring(1)
                              : 'Sin rol',
                          style: TextStyle(
                            color: _isCliente
                                ? Colors.green.shade300
                                : Colors.orange.shade300,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Contenido del perfil
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _isCliente
                  ? _buildClienteProfile(colorScheme)
                  : _buildNonClienteView(colorScheme),
            ),
          ),

          // Botón cerrar sesión
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Cerrar sesión',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteProfile(ColorScheme colorScheme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sección header con botón editar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Información personal',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (!_editMode)
                IconButton(
                  onPressed: () => setState(() => _editMode = true),
                  icon: Icon(Icons.edit, color: colorScheme.primary),
                  tooltip: 'Editar perfil',
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Campo Nombre
          _buildProfileField(
            controller: _nombreController,
            label: 'Nombre',
            icon: Icons.person_outline,
            enabled: _editMode,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El nombre es obligatorio';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Campo Apellidos
          _buildProfileField(
            controller: _apellidosController,
            label: 'Apellidos',
            icon: Icons.people_outline,
            enabled: _editMode,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Los apellidos son obligatorios';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Campo Email
          _buildProfileField(
            controller: _emailController,
            label: 'Correo electrónico',
            icon: Icons.email_outlined,
            enabled: _editMode,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El email es obligatorio';
              }
              if (!RegExp(
                r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$',
              ).hasMatch(value.trim())) {
                return 'Introduce un email válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Campo Teléfono
          _buildProfileField(
            controller: _telefonoController,
            label: 'Teléfono',
            icon: Icons.phone_outlined,
            enabled: _editMode,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value != null && value.trim().isNotEmpty) {
                if (!RegExp(r'^\+?[0-9]{6,15}$').hasMatch(value.trim())) {
                  return 'Introduce un teléfono válido';
                }
              }
              return null;
            },
          ),

          // Botones de acción en modo edición
          if (_editMode) ...[
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _editMode = false);
                            _loadProfile();
                          },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _saveProfile,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Guardar cambios',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNonClienteView(ColorScheme colorScheme) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.info_outline, size: 48, color: colorScheme.primary),
                const SizedBox(height: 12),
                const Text(
                  'Perfil no editable',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'La edición de perfil solo está disponible para usuarios con rol de cliente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildReadOnlyInfo(
          'Email',
          _emailController.text,
          Icons.email_outlined,
        ),
        _buildReadOnlyInfo(
          'Nombre',
          _nombreController.text,
          Icons.person_outline,
        ),
        _buildReadOnlyInfo(
          'Apellidos',
          _apellidosController.text,
          Icons.people_outline,
        ),
        _buildReadOnlyInfo(
          'Teléfono',
          _telefonoController.text,
          Icons.phone_outlined,
        ),
      ],
    );
  }

  Widget _buildReadOnlyInfo(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          subtitle: Text(
            value.isNotEmpty ? value : 'No especificado',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool enabled,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: enabled ? null : Colors.grey.shade400),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: enabled
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidosController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }
}
