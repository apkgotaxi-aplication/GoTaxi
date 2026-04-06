import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/taxista_service.dart';
import 'package:gotaxi/presentation/screens/home/ride_history_screen.dart';

class DriverDashboardTab extends StatefulWidget {
  const DriverDashboardTab({super.key});

  @override
  State<DriverDashboardTab> createState() => _DriverDashboardTabState();
}

class _DriverDashboardTabState extends State<DriverDashboardTab> {
  final TaxistaService _taxistaService = TaxistaService();

  bool _loading = true;
  bool _updatingStatus = false;
  bool _processingRideAction = false;
  String? _error;
  DriverDashboardData? _dashboardData;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _taxistaService.getDriverDashboardData(limit: 3);
      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        _loading = false;
      });

      if (!data.success && data.message.isNotEmpty) {
        _showMessage(data.message, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el dashboard: $e';
      });
    }
  }

  Future<void> _toggleDisponibilidad() async {
    final data = _dashboardData;
    if (data == null || _updatingStatus || _processingRideAction) return;

    final estadoActual = data.estadoTaxista;
    if (estadoActual == 'ocupado') {
      _showMessage(
        'No puedes cambiar tu disponibilidad mientras tengas un viaje activo.',
        isError: true,
      );
      return;
    }

    final nextEstado = estadoActual == 'disponible'
        ? 'no disponible'
        : 'disponible';

    setState(() => _updatingStatus = true);
    try {
      final result = await _taxistaService.setDriverDisponibilidad(
        estado: nextEstado,
      );
      if (!mounted) return;

      _showMessage(result.message, isError: !result.success);
      if (result.success) {
        await _loadDashboard();
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        'No se pudo actualizar la disponibilidad: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _handleRideAction({
    required String action,
    required String rideId,
  }) async {
    if (_processingRideAction) return;

    setState(() => _processingRideAction = true);
    try {
      late final TaxistaActionResult result;

      if (action == 'confirmar') {
        result = await _taxistaService.confirmRideByDriver(viajeId: rideId);
      } else if (action == 'cancelar') {
        result = await _taxistaService.cancelRideByDriver(viajeId: rideId);
      } else {
        result = await _taxistaService.finishRideByDriver(viajeId: rideId);
      }

      if (!mounted) return;
      _showMessage(result.message, isError: !result.success);
      if (result.success) {
        await _loadDashboard();
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('No se pudo completar la accion: $e', isError: true);
    } finally {
      if (mounted) setState(() => _processingRideAction = false);
    }
  }

  Future<void> _confirmFinishRide(String rideId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar viaje'),
        content: const Text(
          '¿Seguro que quieres finalizar este viaje? Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _handleRideAction(action: 'finalizar', rideId: rideId);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadDashboard,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _dashboardData;
    if (data == null) {
      return const Center(child: Text('No se pudo cargar el dashboard.'));
    }

    final estado = data.estadoTaxista;
    final isDisponible = estado == 'disponible';
    final isOcupado = estado == 'ocupado';
    final estadoColor = isOcupado
        ? Colors.orange
        : (isDisponible ? Colors.green : Colors.red);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: estadoColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Estado: ${estado.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: (isOcupado || _updatingStatus)
                          ? null
                          : _toggleDisponibilidad,
                      child: _updatingStatus
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Cambiar'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (data.viajeActivo != null)
              _buildViajeActivoCard(data.viajeActivo!)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No tienes un viaje activo ahora mismo.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Ultimos 3 viajes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (data.ultimosViajes.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aun no tienes viajes registrados.'),
                ),
              )
            else
              ...data.ultimosViajes.map(_buildViajeResumenCard),
            const SizedBox(height: 16),
            Text(
              'Accesos rapidos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RideHistoryScreen(initialTab: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.local_taxi),
                  label: const Text('Viajes activos'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RideHistoryScreen(initialTab: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('Historial'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _showMessage(
                      'Modulo de ganancias disponible en la siguiente iteracion.',
                      isError: false,
                    );
                  },
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Ganancias'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViajeActivoCard(Map<String, dynamic> ride) {
    final estado = ride['estado']?.toString() ?? '';
    final rideId = ride['id']?.toString() ?? '';
    final cliente =
        '${ride['cliente_nombre'] ?? ''} ${ride['cliente_apellidos'] ?? ''}'
            .trim();

    return Card(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Viaje activo (${estado.toUpperCase()})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Cliente: ${cliente.isEmpty ? 'Sin nombre' : cliente}'),
            const SizedBox(height: 4),
            Text('Origen: ${ride['origen'] ?? '-'}'),
            const SizedBox(height: 4),
            Text('Destino: ${ride['destino'] ?? '-'}'),
            const SizedBox(height: 12),
            Row(
              children: [
                if (estado == 'pendiente')
                  Expanded(
                    child: FilledButton(
                      onPressed: (rideId.isEmpty || _processingRideAction)
                          ? null
                          : () => _handleRideAction(
                              action: 'confirmar',
                              rideId: rideId,
                            ),
                      child: const Text('Confirmar'),
                    ),
                  ),
                if (estado == 'pendiente') const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: (rideId.isEmpty || _processingRideAction)
                        ? null
                        : () => _handleRideAction(
                            action: 'cancelar',
                            rideId: rideId,
                          ),
                    child: const Text('Cancelar'),
                  ),
                ),
                if (estado == 'en_curso') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: (rideId.isEmpty || _processingRideAction)
                          ? null
                          : () => _confirmFinishRide(rideId),
                      child: const Text('Finalizar viaje'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViajeResumenCard(Map<String, dynamic> ride) {
    final estado = ride['estado']?.toString() ?? 'sin estado';
    final origen = ride['origen']?.toString() ?? '-';
    final destino = ride['destino']?.toString() ?? '-';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long),
        title: Text('$origen -> $destino'),
        subtitle: Text('Estado: $estado'),
      ),
    );
  }
}
