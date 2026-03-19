import 'package:flutter/material.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _ridesFuture;

  @override
  void initState() {
    super.initState();
    _ridesFuture = fetchCurrentUserRideHistory();
  }

  Future<void> _reload() async {
    setState(() {
      _ridesFuture = fetchCurrentUserRideHistory();
    });
    await _ridesFuture;
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
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
                final rideId = ride['id']?.toString() ?? 'Sin ID';
                final userName = ride['user_nombre']?.toString() ?? 'Sin nombre';
                final userApellidos = ride['user_apellidos']?.toString() ?? 'Sin apellidos';
                final driverName = ride['driver_nombre']?.toString() ?? 'Sin nombre';
                final driverApellidos = ride['driver_apellidos']?.toString() ?? 'Sin apellidos';
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
                        const SizedBox(height: 10),
                        Text('ID viaje: $rideId'),
                        const SizedBox(height: 4),
                        Text('Usuario: $userName $userApellidos'),
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
      ),
    );
  }
}
