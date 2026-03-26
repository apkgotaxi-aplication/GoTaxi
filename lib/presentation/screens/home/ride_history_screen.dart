import 'package:flutter/material.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

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
    _loadRole();
    _ridesFuture = fetchCurrentUserRideHistory();
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
                if (_isTaxista)
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
            padding: const EdgeInsets.all(16),
            itemCount: rides.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ride = rides[index];
              // final rideId = ride['id']?.toString() ?? 'Sin ID';
              // final userName = ride['user_nombre']?.toString() ?? 'Sin nombre';
              // final userApellidos =
              //     ride['user_apellidos']?.toString() ?? 'Sin apellidos';
              final driverName =
                  ride['driver_nombre']?.toString() ?? 'Sin nombre';
              final driverApellidos =
                  ride['driver_apellidos']?.toString() ?? 'Sin apellidos';
              final createdAt = _formatDate(ride['created_at']);

              return Card(
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
                      // const SizedBox(height: 10),
                      // Text('ID viaje: $rideId'),
                      // const SizedBox(height: 4),
                      // Text('Usuario: $userName $userApellidos'),
                      const SizedBox(height: 4),
                      Text('Taxista: $driverName $driverApellidos'),
                    ],
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
