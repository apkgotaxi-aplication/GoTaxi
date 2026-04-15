import 'package:flutter/material.dart';
import 'package:gotaxi/presentation/screens/home/ride_detail_screen.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _ridesFuture;
  bool _isTaxista = false;
  bool _loadingRole = true;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _loadRole();
    _ridesFuture = _selectedTab == 1
        ? fetchCurrentUserDriverRideHistory()
        : fetchCurrentUserRideHistory();
  }

  Future<void> _loadRole() async {
    final isTaxista = await isCurrentUserTaxista();
    if (mounted) {
      setState(() {
        _isTaxista = isTaxista;
        _loadingRole = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _ridesFuture = _selectedTab == 0
          ? fetchCurrentUserRideHistory()
          : fetchCurrentUserDriverRideHistory();
    });
    await _ridesFuture;
  }

  void _onTabChanged(int index) {
    setState(() {
      _selectedTab = index;
      _ridesFuture = index == 0
          ? fetchCurrentUserRideHistory()
          : fetchCurrentUserDriverRideHistory();
    });
  }

  Future<void> _openRideDetail({
    required int index,
    required Map<String, dynamic> ride,
  }) async {
    final rideId = ride['id']?.toString();
    if (rideId == null || rideId.isEmpty) return;

    final updatedRide = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => RideDetailScreen(
          rideId: rideId,
          initialRide: ride,
          isDriverView: _selectedTab == 1,
        ),
      ),
    );

    if (updatedRide == null) return;

    final currentRides = List<Map<String, dynamic>>.from(await _ridesFuture);
    if (index < 0 || index >= currentRides.length) return;

    final oldRideId = currentRides[index]['id']?.toString();
    if (oldRideId != rideId) {
      final fixedIndex = currentRides.indexWhere(
        (item) => item['id']?.toString() == rideId,
      );
      if (fixedIndex == -1) return;
      currentRides[fixedIndex] = {...currentRides[fixedIndex], ...updatedRide};
    } else {
      currentRides[index] = {...currentRides[index], ...updatedRide};
    }

    if (!mounted) return;
    setState(() {
      _ridesFuture = Future.value(currentRides);
    });
  }

  String _formatDate(dynamic rawValue) {
    if (rawValue == null) return 'Sin fecha';
    final parsed = DateTime.tryParse(rawValue.toString());
    if (parsed == null) return rawValue.toString();

    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de viajes')),
      body: _loadingRole
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_isTaxista && _selectedTab == 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTabButton(
                              label: 'Pasajero',
                              icon: Icons.person,
                              isSelected: _selectedTab == 0,
                              onTap: () => _onTabChanged(0),
                            ),
                          ),
                          Expanded(
                            child: _buildTabButton(
                              label: 'Conductor',
                              icon: Icons.drive_eta,
                              isSelected: _selectedTab == 1,
                              onTap: () => _onTabChanged(1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: _buildRidesList()),
              ],
            ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRidesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _ridesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 52,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No se pudo cargar el historial de viajes.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }

        final rides = snapshot.data ?? const [];
        if (rides.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              children: const [
                SizedBox(height: 140),
                Icon(
                  Icons.directions_car_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 12),
                Center(
                  child: Text(
                    'No tienes viajes registrados todavia',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).padding.bottom + 32,
            ),
            itemCount: rides.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ride = rides[index];
              final driverName =
                  ride['driver_nombre']?.toString() ?? 'Sin nombre';
              final driverApellidos =
                  ride['driver_apellidos']?.toString() ?? 'Sin apellidos';
              final clientName =
                  ride['cliente_nombre']?.toString() ??
                  ride['user_nombre']?.toString() ??
                  'Sin nombre';
              final clientApellidos =
                  ride['cliente_apellidos']?.toString() ??
                  ride['user_apellidos']?.toString() ??
                  'Sin apellidos';
              final state = normalizeRideState(ride['estado']);
              final isActiveRide = _selectedTab == 0 && isRideCancelable(state);
              final createdAt = _formatDate(ride['created_at']);
              final origin = ride['origen']?.toString() ?? 'No disponible';
              final destination =
                  ride['destino']?.toString() ?? 'No disponible';
              final isRated = ride['valorado'] == true;
              final paymentLabel = ride['pagado'] == true
                  ? 'Pagado en GoTaxi'
                  : 'Pagado al taxista';
              final isPaidInGoTaxi = paymentLabel == 'Pagado en GoTaxi';
              final statusColor = switch (state) {
                'pendiente' => Colors.orange,
                'confirmada' => Theme.of(context).colorScheme.primary,
                'cancelada' => Theme.of(context).colorScheme.error,
                'finalizada' => Colors.green,
                _ => Theme.of(context).colorScheme.outline,
              };

              if (_selectedTab == 0) {
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openRideDetail(index: index, ride: ride),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.receipt_long, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Viaje ${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                createdAt,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Origen: $origin'),
                          const SizedBox(height: 2),
                          Text('Destino: $destination'),
                          const SizedBox(height: 2),
                          Text('Taxista: $driverName $driverApellidos'),
                          if (_selectedTab == 0) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isRated ? Colors.green : Colors.orange)
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: isRated
                                          ? Colors.green.withValues(alpha: 0.45)
                                          : Colors.orange.withValues(
                                              alpha: 0.45,
                                            ),
                                    ),
                                  ),
                                  child: Text(
                                    isRated
                                        ? 'Valorado'
                                        : 'Pendiente de valoración',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isRated
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isPaidInGoTaxi
                                                ? Colors.green
                                                : Colors.blue)
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color:
                                          (isPaidInGoTaxi
                                                  ? Colors.green
                                                  : Colors.blue)
                                              .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    paymentLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isPaidInGoTaxi
                                          ? Colors.green.shade700
                                          : Colors.blue.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Pulsa para ver más información',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openRideDetail(index: index, ride: ride),
                child: Card(
                  color: isActiveRide
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.08)
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: isActiveRide
                        ? BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.4,
                          )
                        : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isActiveRide
                                  ? Icons.local_taxi
                                  : Icons.receipt_long,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Viaje ${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              createdAt,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Origen: $origin'),
                        const SizedBox(height: 2),
                        Text('Destino: $destination'),
                        const SizedBox(height: 2),
                        Text(
                          _selectedTab == 0
                              ? 'Taxista: $driverName $driverApellidos'
                              : 'Cliente: $clientName $clientApellidos',
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                state.isEmpty ? 'sin estado' : state,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ),
                            if (isActiveRide)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Activo',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Pulsa para ver detalle',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
