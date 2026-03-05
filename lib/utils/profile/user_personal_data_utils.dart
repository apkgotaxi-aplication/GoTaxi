import 'package:flutter/material.dart';

class UserPersonalDataUtils {
  /// Obtiene las iniciales del usuario a partir de nombre y apellidos.
  static String getInitials(String nombre, String apellidos) {
    String initials = '';
    if (nombre.isNotEmpty) initials += nombre[0].toUpperCase();
    if (apellidos.isNotEmpty) initials += apellidos[0].toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  /// Capitaliza la primera letra de un rol.
  static String formatRole(String role) {
    if (role.isEmpty) return 'Sin rol';
    return role[0].toUpperCase() + role.substring(1);
  }

  /// Determina si el rol es cliente.
  static bool isCliente(String role) => role == 'cliente';

  /// Devuelve el color del badge según el rol.
  static Color getRoleBadgeColor(bool isCliente) =>
      isCliente ? Colors.green : Colors.orange;

  /// Validador para campos de texto obligatorios.
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName es obligatorio';
    }
    return null;
  }

  /// Validador para el campo email.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El email es obligatorio';
    }
    if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$')
        .hasMatch(value.trim())) {
      return 'Introduce un email válido';
    }
    return null;
  }

  /// Validador para el campo teléfono (opcional).
  static String? validateTelefono(String? value) {
    if (value != null && value.trim().isNotEmpty) {
      if (!RegExp(r'^\+?[0-9]{6,15}$').hasMatch(value.trim())) {
        return 'Introduce un teléfono válido';
      }
    }
    return null;
  }
}