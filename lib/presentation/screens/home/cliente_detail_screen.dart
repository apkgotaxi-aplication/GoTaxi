import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/cliente_service.dart';

class ClienteDetailScreen extends StatefulWidget {
  const ClienteDetailScreen({super.key, required this.cliente});

  final Map<String, dynamic> cliente;

  @override
  State<ClienteDetailScreen> createState() => _ClienteDetailScreenState();
}

class _ClienteDetailScreenState extends State<ClienteDetailScreen> {
  final _clienteService = ClienteService();

  Map<String, dynamic>? _cliente;
  List<Map<String, dynamic>> _viajes = [];
  bool _loadingCliente = true;
  bool _loadingViajes = true;
  bool _hasMore = false;
  bool _hasPrevious = false;
  int _currentPage = 1;
  String? _error;
  static const int _limit = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loadingCliente = true;
      _error = null;
    });

    try {
      final clienteId = widget.cliente['id'] as String;
      final cliente = await _clienteService.getClienteById(clienteId);

      if (!mounted) return;

      setState(() {
        _cliente = cliente;
        _loadingCliente = false;
      });

      _loadViajes(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar los datos';
        _loadingCliente = false;
      });
    }
  }

  Future<void> _loadViajes({required int page}) async {
    setState(() => _loadingViajes = true);

    try {
      final clienteId = widget.cliente['id'] as String;
      final offset = (page - 1) * _limit;

      final viajes = await _clienteService.getClienteViajes(
        clienteId,
        limit: _limit,
        offset: offset,
      );

      if (!mounted) return;

      setState(() {
        _viajes = viajes;
        _currentPage = page;
        _hasMore = viajes.length == _limit;
        _hasPrevious = page > 1;
        _loadingViajes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingViajes = false);
    }
  }

  void _nextPage() {
    if (_hasMore) {
      _loadViajes(page: _currentPage + 1);
    }
  }

  void _previousPage() {
    if (_hasPrevious) {
      _loadViajes(page: _currentPage - 1);
    }
  }

  Future<void> _refresh() async {
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del cliente'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loadingCliente
            ? const Center(child: CircularProgressIndicator())
            : _error != null || _cliente == null
            ? _buildErrorState(colorScheme)
            : _buildContent(colorScheme),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Cliente no encontrado',
              style: TextStyle(fontSize: 16, color: colorScheme.error),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    final nombre = _cliente!['nombre'] as String? ?? '';
    final apellidos = _cliente!['apellidos'] as String? ?? '';
    final email = _cliente!['email'] as String? ?? '';
    final telefono = _cliente!['telefono'] as String? ?? '';
    final dni = _cliente!['dni'] as String? ?? '';
    final createdAt = _cliente!['created_at'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    _buildInitials(nombre, apellidos),
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$nombre $apellidos'.trim().isEmpty
                      ? 'Sin nombre'
                      : '$nombre $apellidos'.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Cliente',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _DetailSection(
          title: 'Información personal',
          children: [
            _DetailRow(
              icon: Icons.badge_outlined,
              label: 'DNI',
              value: dni.isEmpty ? 'No disponible' : dni,
            ),
            _DetailRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: email.isEmpty ? 'No disponible' : email,
            ),
            _DetailRow(
              icon: Icons.phone_outlined,
              label: 'Teléfono',
              value: telefono.isEmpty ? 'No disponible' : telefono,
            ),
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Fecha de registro',
              value: _formatDate(createdAt),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildViajesSection(colorScheme),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _deleting ? null : _deleteCliente,
          icon: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline, color: Colors.red),
          label: Text(
            _deleting ? 'Eliminando...' : 'Eliminar cliente',
            style: const TextStyle(color: Colors.red),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.red.shade300),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
      ],
    );
  }

  bool _deleting = false;

  Future<void> _deleteCliente() async {
    final nombre = _cliente!['nombre'] as String? ?? '';
    final apellidos = _cliente!['apellidos'] as String? ?? '';
    final fullName = '$nombre $apellidos'.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          '¿Estás seguro de que deseas eliminar a ${fullName.isEmpty ? 'este cliente' : fullName}?\n\n'
          'Esta acción eliminará al cliente y sus datos de forma permanente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);

    try {
      final clienteId = _cliente!['id'] as String;
      await _clienteService.deleteCliente(clienteId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${fullName.isEmpty ? 'Cliente' : fullName} eliminado correctamente',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Widget _buildViajesSection(ColorScheme colorScheme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Viajes realizados',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (!_loadingViajes && _viajes.isNotEmpty)
                  Text(
                    'Página $_currentPage',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingViajes)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_viajes.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        size: 48,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Este cliente aún no tiene viajes',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  ..._viajes.map((viaje) => _ViajeCard(viaje: viaje)),
                  const SizedBox(height: 16),
                  _buildPaginationControls(colorScheme),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationControls(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _hasPrevious ? _previousPage : null,
          icon: const Icon(Icons.chevron_left),
          style: IconButton.styleFrom(
            backgroundColor: _hasPrevious
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(width: 16),
        Text(
          '$_currentPage',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          onPressed: _hasMore ? _nextPage : null,
          icon: const Icon(Icons.chevron_right),
          style: IconButton.styleFrom(
            backgroundColor: _hasMore
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic rawValue) {
    if (rawValue == null) return 'No disponible';
    final parsed = DateTime.tryParse(rawValue.toString());
    if (parsed == null) return rawValue.toString();
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _buildInitials(String nombre, String apellidos) {
    final firstName = nombre.trim();
    final lastName = apellidos.trim();
    final firstInitial = firstName.isNotEmpty ? firstName[0] : '';
    final lastInitial = lastName.isNotEmpty ? lastName[0] : '';
    final initials = '$firstInitial$lastInitial'.trim();
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViajeCard extends StatelessWidget {
  const _ViajeCard({required this.viaje});

  final Map<String, dynamic> viaje;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estado = (viaje['estado']?.toString() ?? 'sin estado').toLowerCase();
    final statusColor = switch (estado) {
      'pendiente' => Colors.orange,
      'confirmada' => colorScheme.primary,
      'cancelada' => colorScheme.error,
      'finalizada' => Colors.green,
      'en_curso' => Colors.blue,
      _ => colorScheme.outline,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${viaje['origen'] ?? 'Origen no disponible'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  estado,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Destino: ${viaje['destino'] ?? 'No disponible'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              Text(
                'Precio: ${_formatPrice(viaje['precio'])}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'Fecha: ${_formatDate(viaje['created_at'])}',
                style: TextStyle(color: colorScheme.outline, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(dynamic rawValue) {
    if (rawValue == null) return 'No disponible';
    final price = double.tryParse(rawValue.toString());
    if (price == null) return rawValue.toString();
    return '${price.toStringAsFixed(2)} €';
  }

  String _formatDate(dynamic rawValue) {
    if (rawValue == null) return 'Sin fecha';
    final parsed = DateTime.tryParse(rawValue.toString());
    if (parsed == null) return rawValue.toString();
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  }
}
