import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gotaxi/data/services/taxista_service.dart';
import 'package:gotaxi/presentation/screens/home/ride_history_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverDashboardTab extends StatefulWidget {
  const DriverDashboardTab({super.key});

  @override
  State<DriverDashboardTab> createState() => _DriverDashboardTabState();
}

class _DriverDashboardTabState extends State<DriverDashboardTab>
    with WidgetsBindingObserver {
  final TaxistaService _taxistaService = TaxistaService();

  bool _loading = true;
  bool _updatingStatus = false;
  bool _processingRideAction = false;
  bool _updatingLocation = false;
  bool _sharingLocationInProgress = false;
  bool _locationSharingEnabled = false;
  String? _error;
  DriverDashboardData? _dashboardData;
  Timer? _locationUpdateTimer;
  Timer? _dashboardRefreshDebounce;
  Timer? _dashboardPollingTimer;
  RealtimeChannel? _dashboardRealtimeChannel;
  bool _dashboardLoadInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboard();
    _startDashboardRealtimeSync();
    _startDashboardPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationUpdateTimer?.cancel();
    _dashboardRefreshDebounce?.cancel();
    _dashboardPollingTimer?.cancel();
    if (_dashboardRealtimeChannel != null) {
      Supabase.instance.client.removeChannel(_dashboardRealtimeChannel!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_loadDashboard(showLoader: false));
    }
  }

  String _formatDuration(dynamic rawMinutes) {
    final minutes = int.tryParse(rawMinutes?.toString() ?? '');
    if (minutes == null || minutes <= 0) return 'No disponible';

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '$hours h';
    }

    return '$hours h $remainingMinutes min';
  }

  bool _isRidePaid(Map<String, dynamic> ride) {
    if (ride['pagado'] == true) return true;
    final stripeStatus = ride['stripe_payment_status']
        ?.toString()
        .toLowerCase()
        .trim();
    return stripeStatus == 'succeeded' ||
        stripeStatus == 'successed' ||
        stripeStatus == 'paid';
  }

  String _buildPaymentLabel(Map<String, dynamic> ride) {
    return _isRidePaid(ride) ? 'Pagado' : 'Pendiente';
  }

  void _startDashboardRealtimeSync() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _dashboardRealtimeChannel = Supabase.instance.client
        .channel('driver-dashboard-${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'viajes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: user.id,
          ),
          callback: (_) => _scheduleDashboardRefresh(),
        )
        .subscribe();
  }

  void _scheduleDashboardRefresh() {
    _dashboardRefreshDebounce?.cancel();
    _dashboardRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_loadDashboard(showLoader: false));
    });
  }

  void _startDashboardPolling() {
    _dashboardPollingTimer?.cancel();
    _dashboardPollingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      unawaited(_loadDashboard(showLoader: false));
    });
  }

  Future<void> _loadDashboard({bool showLoader = true}) async {
    if (_dashboardLoadInFlight) return;
    _dashboardLoadInFlight = true;

    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _taxistaService.getDriverDashboardData(limit: 6);

      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        if (showLoader) {
          _loading = false;
        }
        if (!showLoader) {
          _error = null;
        }
      });

      if (data.viajeActivo == null) {
        _locationSharingEnabled = false;
      }
      _syncLocationTracking(data.viajeActivo);

      if (!data.success && data.message.isNotEmpty) {
        _showMessage(data.message, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      if (showLoader) {
        setState(() {
          _loading = false;
          _error = 'No se pudo cargar el dashboard: $e';
        });
      }
      _syncLocationTracking(null);
    } finally {
      _dashboardLoadInFlight = false;
    }
  }

  bool _shouldTrackLocation(Map<String, dynamic>? activeRide) {
    final state = activeRide?['estado']?.toString().trim().toLowerCase();
    return _locationSharingEnabled &&
        (state == 'confirmada' || state == 'en_curso');
  }

  void _syncLocationTracking(Map<String, dynamic>? activeRide) {
    if (_shouldTrackLocation(activeRide)) {
      _locationUpdateTimer ??= Timer.periodic(const Duration(seconds: 15), (
        _,
      ) async {
        final published = await _pushCurrentLocation();
        if (!published && mounted && _locationSharingEnabled) {
          setState(() {
            _locationSharingEnabled = false;
          });
          _locationUpdateTimer?.cancel();
          _locationUpdateTimer = null;
          _showMessage(
            'Se perdió la sincronización de ubicación. Pulsa "Compartir ubicación" para retomarla.',
            isError: true,
          );
        }
      });
      return;
    }

    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
  }

  Future<bool> _pushCurrentLocation({bool notifyOnError = false}) async {
    if (_updatingLocation) return false;
    _updatingLocation = true;

    try {
      final canUseLocation = await _ensureLocationPermission(
        showSettingsOnDeniedForever: false,
      );
      if (!canUseLocation) {
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );

      final result = await _taxistaService.updateDriverLocation(
        lat: position.latitude,
        lng: position.longitude,
      );

      if (!result.success) {
        if (notifyOnError) {
          _showMessage(
            result.message.isNotEmpty
                ? result.message
                : 'No se pudo compartir la ubicación.',
            isError: true,
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (notifyOnError) {
        final raw = e.toString();
        final message = raw.contains('update_driver_location')
            ? 'No se pudo guardar tu ubicación en el servidor. Verifica migraciones y vuelve a intentar.'
            : 'No se pudo compartir tu ubicación: $raw';
        _showMessage(message, isError: true);
      }
      return false;
    } finally {
      _updatingLocation = false;
    }
  }

  Future<void> _shareLocationForRide(String rideId) async {
    final ride = _dashboardData?.viajeActivo;
    final state = ride?['estado']?.toString().trim().toLowerCase();

    if (ride == null || rideId.isEmpty || state != 'confirmada') {
      _showMessage(
        'Solo puedes compartir ubicación cuando el viaje está confirmado.',
        isError: true,
      );
      return;
    }

    if (_sharingLocationInProgress) return;

    if (!mounted) return;
    setState(() {
      _sharingLocationInProgress = true;
    });

    _showLocationSharingDialog();

    try {
      final canUseLocation = await _ensureLocationPermission(
        showSettingsOnDeniedForever: true,
      );
      if (!canUseLocation) {
        return;
      }

      final published = await _pushCurrentLocation(notifyOnError: true);
      if (!published) {
        return;
      }

      if (!mounted) return;
      setState(() {
        _locationSharingEnabled = true;
      });

      _syncLocationTracking(ride);

      if (!mounted) return;
      _showMessage(
        'Ubicación compartida activada. El cliente ya puede ver su ubicación.',
        isError: false,
      );
    } finally {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        _sharingLocationInProgress = false;
      });
    }
  }

  void _showLocationSharingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: SizedBox(
            width: 240,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Compartiendo ubicación...')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _ensureLocationPermission({
    required bool showSettingsOnDeniedForever,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showMessage('Activa el GPS para compartir tu ubicación.', isError: true);
      return false;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return true;
    }

    if (permission == LocationPermission.deniedForever) {
      _showMessage(
        'Tienes el permiso de ubicación bloqueado. Ábrelo desde Ajustes para continuar.',
        isError: true,
      );
      if (showSettingsOnDeniedForever) {
        await Geolocator.openAppSettings();
      }
      return false;
    }

    final requestedPermission = await Geolocator.requestPermission();
    if (requestedPermission == LocationPermission.always ||
        requestedPermission == LocationPermission.whileInUse) {
      return true;
    }

    if (requestedPermission == LocationPermission.deniedForever) {
      _showMessage(
        'Tienes el permiso de ubicación bloqueado. Ábrelo desde Ajustes para continuar.',
        isError: true,
      );
      if (showSettingsOnDeniedForever) {
        await Geolocator.openAppSettings();
      }
      return false;
    }

    _showMessage(
      'Necesitamos permiso de ubicación para que el cliente vea el ETA.',
      isError: true,
    );
    return false;
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
      } else if (action == 'comenzar') {
        result = await _taxistaService.startRideByDriver(viajeId: rideId);
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

  Future<void> _confirmCancelRide(String rideId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar viaje'),
        content: const Text(
          '¿Seguro que quieres cancelar este viaje? Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancelar viaje'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _handleRideAction(action: 'cancelar', rideId: rideId);
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
    final isBusy = _sharingLocationInProgress || _updatingLocation;
    final estadoColor = isOcupado
        ? Colors.orange
        : (isDisponible ? Colors.green : Colors.red);
    final activeRideId = data.viajeActivo?['id']?.toString();
    final ultimosViajesSinActivo = data.ultimosViajes
        .where((ride) {
          final rideId = ride['id']?.toString();
          return activeRideId == null || rideId != activeRideId;
        })
        .take(3)
        .toList();

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
                      onPressed: (isOcupado || _updatingStatus || isBusy)
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
                  label: const Text('Historial de viajes'),
                ),              ],
            ),
            const SizedBox(height: 12),
            if (data.viajeActivo != null)
              _buildViajeActivoCard(data.viajeActivo!, isBusy: isBusy)
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
            if (ultimosViajesSinActivo.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aun no tienes viajes registrados.'),
                ),
              )
            else
              ...ultimosViajesSinActivo.map(_buildViajeResumenCard),
          ],
        ),
      ),
    );
  }

  Widget _buildViajeActivoCard(
    Map<String, dynamic> ride, {
    required bool isBusy,
  }) {
    final estado = ride['estado']?.toString() ?? '';
    final rideId = ride['id']?.toString() ?? '';
    final cliente =
        '${ride['cliente_nombre'] ?? ''} ${ride['cliente_apellidos'] ?? ''}'
            .trim();
    final anotaciones = ride['anotaciones']?.toString().trim() ?? '';
    final duracion = _formatDuration(ride['duracion']);
    final isPaid = _isRidePaid(ride);

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
            const SizedBox(height: 4),
            Text('Duracion del trayecto: $duracion'),
            const SizedBox(height: 4),
            Text(
              'Anotaciones: ${anotaciones.isEmpty ? 'Sin anotaciones' : anotaciones}',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isPaid
                      ? Icons.verified_outlined
                      : Icons.hourglass_empty_outlined,
                  size: 18,
                  color: isPaid ? Colors.green : null,
                ),
                const SizedBox(width: 6),
                Text('Pago: ${_buildPaymentLabel(ride)}'),
              ],
            ),
            if (estado == 'confirmada') ...[const SizedBox(height: 4)],
            const SizedBox(height: 12),
            Row(
              children: [
                if (estado == 'pendiente')
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (rideId.isEmpty || _processingRideAction || isBusy)
                          ? null
                          : () => _handleRideAction(
                              action: 'confirmar',
                              rideId: rideId,
                            ),
                      child: const Text('Confirmar'),
                    ),
                  ),
                if (estado == 'pendiente') const SizedBox(width: 8),
                if (estado == 'confirmada')
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (rideId.isEmpty || _processingRideAction || isBusy)
                          ? null
                          : () => _handleRideAction(
                              action: 'comenzar',
                              rideId: rideId,
                            ),
                      child: const Text('Comenzar viaje'),
                    ),
                  ),
                if (estado == 'confirmada') const SizedBox(width: 8),
                if (estado == 'confirmada' && !_locationSharingEnabled)
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          (rideId.isEmpty || _processingRideAction || isBusy)
                          ? null
                          : () => _shareLocationForRide(rideId),
                      child: const Text('Compartir ubicación'),
                    ),
                  ),
                if (estado == 'confirmada' && !_locationSharingEnabled)
                  const SizedBox(width: 8),
                if (estado == 'pendiente')
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          (rideId.isEmpty || _processingRideAction || isBusy)
                          ? null
                          : () => _confirmCancelRide(rideId),
                      child: const Text('Cancelar'),
                    ),
                  ),
                if (estado == 'en_curso') const SizedBox(width: 8),
                if (estado == 'en_curso')
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (rideId.isEmpty || _processingRideAction || isBusy)
                          ? null
                          : () => _confirmFinishRide(rideId),
                      child: const Text('Finalizar viaje'),
                    ),
                  ),
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
    final isPaid = _isRidePaid(ride);

    return Card(
      child: ListTile(
        leading: Icon(
          isPaid ? Icons.receipt_long : Icons.receipt_long_outlined,
          color: isPaid ? Colors.green : null,
        ),
        title: Text('$origen -> $destino'),
        subtitle: Text('Estado: $estado · Pago: ${_buildPaymentLabel(ride)}'),
      ),
    );
  }
}
