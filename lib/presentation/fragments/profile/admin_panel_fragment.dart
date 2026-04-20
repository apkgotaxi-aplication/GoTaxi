import 'package:flutter/material.dart';
import '../../screens/home/crear_taxista_screen.dart';
import '../../screens/home/gestionar_clientes_screen.dart';
import '../../screens/home/gestionar_tarifas_screen.dart';
import '../../screens/home/gestionar_taxistas_screen.dart';
import '../../screens/home/push_debug_screen.dart';

class AdminPanelFragment extends StatelessWidget {
  const AdminPanelFragment({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Administrador',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _AdminSectionItem(
                icon: Icons.person_add_alt_1_outlined,
                color: colorScheme.primary,
                title: 'Crear taxista',
                subtitle:
                    'Registrar un nuevo taxista con sus datos y vehiculo.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CrearTaxistaScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
              _AdminSectionItem(
                icon: Icons.badge_outlined,
                color: Colors.blue,
                title: 'Ver clientes',
                subtitle:
                    'Ver todos los clientes registrados con foto y nombre.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GestionarClientesScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
              _AdminSectionItem(
                icon: Icons.people_outline,
                color: colorScheme.error,
                title: 'Gestionar taxistas',
                subtitle:
                    'Ver taxistas registrados y eliminar los que ya no hagan falta.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GestionarTaxistasScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
              _AdminSectionItem(
                icon: Icons.price_change_outlined,
                color: colorScheme.tertiary,
                title: 'Gestionar tarifas',
                subtitle: 'Consultar y editar tarifas por municipio.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GestionarTarifasScreen(),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
              _AdminSectionItem(
                icon: Icons.notifications_active_outlined,
                color: colorScheme.secondary,
                title: 'Push debug',
                subtitle: 'Ver subscription ID y lanzar una push de prueba.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PushDebugScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminSectionItem extends StatelessWidget {
  const _AdminSectionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }
}
