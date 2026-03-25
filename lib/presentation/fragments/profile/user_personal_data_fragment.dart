import 'package:flutter/material.dart';
import '../../../utils/profile/user_personal_data_utils.dart';

class UserPersonalDataFragment extends StatelessWidget {
  final TextEditingController nombreController;
  final TextEditingController apellidosController;
  final TextEditingController emailController;
  final TextEditingController telefonoController;
  final GlobalKey<FormState> formKey;
  final bool isCliente;
  final bool editMode;
  final bool saving;
  final String userRole;
  final VoidCallback onEditPressed;
  final VoidCallback onSavePressed;
  final VoidCallback onCancelPressed;

  const UserPersonalDataFragment({
    super.key,
    required this.nombreController,
    required this.apellidosController,
    required this.emailController,
    required this.telefonoController,
    required this.formKey,
    required this.isCliente,
    required this.editMode,
    required this.saving,
    required this.userRole,
    required this.onEditPressed,
    required this.onSavePressed,
    required this.onCancelPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return isCliente
        ? _buildClienteProfile(context, colorScheme)
        : _buildNonClienteView(context, colorScheme);
  }

  // ──────────────────────────────────────────────
  // Vista cliente: formulario editable
  // ──────────────────────────────────────────────
  Widget _buildClienteProfile(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Información personal',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (!editMode)
                IconButton(
                  onPressed: onEditPressed,
                  icon: Icon(Icons.edit, color: colorScheme.primary),
                  tooltip: 'Editar perfil',
                ),
            ],
          ),
          const SizedBox(height: 16),

          _buildProfileField(
            context: context,
            controller: nombreController,
            label: 'Nombre',
            icon: Icons.person_outline,
            enabled: editMode,
            validator: (v) =>
                UserPersonalDataUtils.validateRequired(v, 'El nombre'),
          ),
          const SizedBox(height: 16),

          _buildProfileField(
            context: context,
            controller: apellidosController,
            label: 'Apellidos',
            icon: Icons.people_outline,
            enabled: editMode,
            validator: (v) =>
                UserPersonalDataUtils.validateRequired(v, 'Los apellidos'),
          ),
          const SizedBox(height: 16),

          _buildProfileField(
            context: context,
            controller: emailController,
            label: 'Correo electrónico',
            icon: Icons.email_outlined,
            enabled: editMode,
            keyboardType: TextInputType.emailAddress,
            validator: UserPersonalDataUtils.validateEmail,
          ),
          const SizedBox(height: 16),

          _buildProfileField(
            context: context,
            controller: telefonoController,
            label: 'Teléfono',
            icon: Icons.phone_outlined,
            enabled: editMode,
            keyboardType: TextInputType.phone,
            validator: UserPersonalDataUtils.validateTelefono,
          ),

          if (editMode) ...[
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : onCancelPressed,
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
                    onPressed: saving ? null : onSavePressed,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Guardar cambios',
                            style:
                                TextStyle(fontWeight: FontWeight.bold),
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

  // ──────────────────────────────────────────────
  // Vista no-cliente: solo lectura
  // ──────────────────────────────────────────────
  Widget _buildNonClienteView(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.info_outline,
                    size: 48, color: colorScheme.primary),
                const SizedBox(height: 12),
                const Text(
                  'Perfil no editable',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'La edición de perfil solo está disponible para usuarios con rol de cliente.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Colors.grey.shade400, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildReadOnlyInfo(
            context, 'Email', emailController.text, Icons.email_outlined),
        _buildReadOnlyInfo(
            context, 'Nombre', nombreController.text, Icons.person_outline),
        _buildReadOnlyInfo(context, 'Apellidos', apellidosController.text,
            Icons.people_outline),
        _buildReadOnlyInfo(
            context, 'Teléfono', telefonoController.text, Icons.phone_outlined),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // Widgets auxiliares
  // ──────────────────────────────────────────────
  Widget _buildReadOnlyInfo(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading:
              Icon(icon, color: Theme.of(context).colorScheme.primary),
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
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool enabled,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
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
            ? colorScheme.surface
            : colorScheme.surface.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: colorScheme.primary, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
      ),
    );
  }
}