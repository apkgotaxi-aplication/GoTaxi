import 'package:flutter/material.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  static const _companyName = 'GoTaxi'; // REEMPLAZAR
  static const _version = '1.0.0'; // REEMPLAZAR
  static const _supportEmail = 'soporte@gotaxi.example.com'; // REEMPLAZAR
  static const _supportPhone = '+34 900 000 000'; // REEMPLAZAR
  static const _website = 'www.gotaxi.example.com'; // REEMPLAZAR

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Sobre Nosotros')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 40 + bottomInset),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.15),
                  colorScheme.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _companyName,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Version $_version',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                // const SizedBox(height: 10),
                // Container(
                //   padding: const EdgeInsets.symmetric(
                //     horizontal: 12,
                //     vertical: 6,
                //   ),
                //   decoration: BoxDecoration(
                //     color: Colors.amber.shade100,
                //     borderRadius: BorderRadius.circular(20),
                //   ),
                //   child: const Text(
                //     'Contenido de ejemplo: REEMPLAZAR con datos reales',
                //     textAlign: TextAlign.center,
                //     style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                //   ),
                // ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Nuestra mision',
            child: const Text(
              'Conectar personas y ciudades con soluciones de movilidad seguras, eficientes y accesibles, elevando la experiencia del usuario en cada trayecto.\n\n'
              'Texto de ejemplo: REEMPLAZAR por la propuesta de valor oficial de la empresa.',
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Que hacemos',
            child: const Text(
              'Ofrecemos una plataforma para solicitar viajes urbanos, gestionar pagos y dar soporte en tiempo real para clientes y conductores.\n\n'
              'Texto de ejemplo: REEMPLAZAR por servicios y alcance reales.',
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Valores',
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ValueRow(text: 'Seguridad como prioridad operativa.'),
                SizedBox(height: 8),
                _ValueRow(text: 'Transparencia en tarifas y procesos.'),
                SizedBox(height: 8),
                _ValueRow(
                  text: 'Servicio centrado en la experiencia del usuario.',
                ),
                SizedBox(height: 8),
                _ValueRow(text: 'Mejora continua mediante tecnologia y datos.'),
                SizedBox(height: 12),
                Text(
                  'Lista de ejemplo: REEMPLAZAR por valores corporativos oficiales.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Contacto corporativo',
            child: Column(
              children: [
                _ContactRow(icon: Icons.email_outlined, label: _supportEmail),
                const SizedBox(height: 8),
                _ContactRow(icon: Icons.phone_outlined, label: _supportPhone),
                const SizedBox(height: 8),
                _ContactRow(icon: Icons.language_outlined, label: _website),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Datos de ejemplo: REEMPLAZAR correo, telefono y web.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}
