import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/ride_service.dart';
import 'package:gotaxi/data/services/stripe_payment_service.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';

class RideDetailScreen extends StatefulWidget {
  const RideDetailScreen({
    super.key,
    required this.rideId,
    required this.initialRide,
    this.isDriverView = false,
  });

  final String rideId;
  final Map<String, dynamic> initialRide;
  final bool isDriverView;

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  final RideService _rideService = RideService();
  final StripePaymentService _stripePaymentService = StripePaymentService();

  late Future<Map<String, dynamic>> _detailFuture;
  bool _isCancelling = false;
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.isDriverView
        ? fetchCurrentUserDriverRideDetail(rideId: widget.rideId)
        : fetchCurrentUserRideDetail(rideId: widget.rideId);
  }

  Future<void> _reload() async {
    setState(() {
      _detailFuture = widget.isDriverView
          ? fetchCurrentUserDriverRideDetail(rideId: widget.rideId)
          : fetchCurrentUserRideDetail(rideId: widget.rideId);
    });
    await _detailFuture;
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

  String _formatPrice(dynamic rawValue) {
    if (rawValue == null) return 'No disponible';
    final price = double.tryParse(rawValue.toString());
    if (price == null) return rawValue.toString();
    return '${price.toStringAsFixed(2)} €';
  }

  String _formatMinutes(dynamic rawValue) {
    if (rawValue == null) return 'No disponible';
    final minutes = int.tryParse(rawValue.toString());
    if (minutes == null) return rawValue.toString();
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

  String _formatActualDuration(Map<String, dynamic> detail) {
    final start = DateTime.tryParse(detail['fecha_recogida']?.toString() ?? '');
    final end = DateTime.tryParse(detail['fecha_entrega']?.toString() ?? '');

    if (start == null || end == null || end.isBefore(start)) {
      return 'No disponible';
    }

    return _formatMinutes(end.difference(start).inMinutes);
  }

  String _buildDriverName(Map<String, dynamic> detail) {
    final nombre = detail['driver_nombre']?.toString().trim() ?? '';
    final apellidos = detail['driver_apellidos']?.toString().trim() ?? '';
    final fullName = '$nombre $apellidos'.trim();
    return fullName.isEmpty ? 'Sin taxista asignado' : fullName;
  }

  String _buildVehicleName(Map<String, dynamic> detail) {
    final marca = detail['vehiculo_marca']?.toString().trim() ?? '';
    final modelo = detail['vehiculo_modelo']?.toString().trim() ?? '';
    final composed = '$marca $modelo'.trim();
    return composed.isEmpty ? 'Vehiculo no disponible' : composed;
  }

  String _buildClientName(Map<String, dynamic> detail) {
    final nombre = detail['cliente_nombre']?.toString().trim() ?? '';
    final apellidos = detail['cliente_apellidos']?.toString().trim() ?? '';
    final fullName = '$nombre $apellidos'.trim();
    return fullName.isEmpty ? 'Sin cliente asignado' : fullName;
  }

  String _buildDriverLabel(Map<String, dynamic> detail) {
    final nombre = detail['driver_nombre']?.toString().trim() ?? '';
    final apellidos = detail['driver_apellidos']?.toString().trim() ?? '';
    final fullName = '$nombre $apellidos'.trim();
    return fullName.isEmpty ? 'Sin taxista asignado' : fullName;
  }

  Color _statusColor(String state, ColorScheme scheme) {
    switch (state) {
      case 'pendiente':
        return Colors.orange;
      case 'confirmada':
        return scheme.primary;
      case 'cancelada':
        return scheme.error;
      case 'finalizada':
        return Colors.green;
      default:
        return scheme.outline;
    }
  }

  Future<void> _confirmAndCancelRide(Map<String, dynamic> detail) async {
    if (_isCancelling) return;

    final canCancel = normalizeRideState(detail['estado']) == 'pendiente';
    if (!canCancel) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar viaje'),
          content: const Text(
            'Esta accion cancelara el viaje y liberara al taxista. ¿Deseas continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Si, cancelar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isCancelling = true;
    });

    try {
      final result = await _rideService.cancelRide(viajeId: widget.rideId);
      if (!mounted) return;

      final color = result.success
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: color),
      );

      if (result.success) {
        Navigator.of(
          context,
        ).pop({...detail, 'estado': result.estado ?? 'cancelada'});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  Future<void> _payRide(Map<String, dynamic> detail) async {
    if (_isPaying) return;

    final state = normalizeRideState(detail['estado']);
    final isPaid = detail['pagado'] == true;

    if (isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este viaje ya está pagado.')),
      );
      return;
    }

    if (state != 'confirmada' && state != 'en_curso') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo puedes pagar viajes confirmados o en curso.'),
        ),
      );
      return;
    }

    setState(() => _isPaying = true);
    try {
      final result = await _stripePaymentService.createRidePaymentSession(
        rideId: widget.rideId,
      );

      if (!mounted) return;

      if (!result.success || result.checkoutUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      await _stripePaymentService.openCheckoutUrl(result.checkoutUrl!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se ha abierto el pago seguro de Stripe.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('StateError: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del viaje')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailFuture,
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
                      'No se pudo cargar el detalle del viaje.',
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

          final detail = snapshot.data ?? widget.initialRide;
          final state = normalizeRideState(detail['estado']);
          final colorScheme = Theme.of(context).colorScheme;
          final statusColor = _statusColor(state, colorScheme);

          final clientName = _buildClientName(detail);
          final driverName = _buildDriverLabel(detail);
          final estimatedDuration = _formatMinutes(detail['duracion']);
          final actualDuration = _formatActualDuration(detail);
          final anotaciones = detail['anotaciones']?.toString().trim() ?? '';
          final isPaid = detail['pagado'] == true;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).padding.bottom + 32,
            ),
            children: [
              Card(
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
                              'Viaje ${widget.rideId.substring(0, 8).toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              state.isEmpty ? 'sin estado' : state,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (widget.isDriverView) ...[
                        _buildInfoTile(
                          icon: Icons.schedule_outlined,
                          label: 'Solicitado',
                          value: _formatDate(detail['created_at']),
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.flight_takeoff_outlined,
                          label: 'Recogida',
                          value: _formatDate(detail['fecha_recogida']),
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.flag_outlined,
                          label: 'Entrega',
                          value: _formatDate(detail['fecha_entrega']),
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.people_outline,
                          label: 'Pasajeros',
                          value:
                              detail['num_pasajeros']?.toString() ??
                              'No disponible',
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.timer_outlined,
                          label: 'Tiempo aproximado',
                          value: estimatedDuration,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.av_timer_outlined,
                          label: 'Tiempo final calculado',
                          value: actualDuration,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.place_outlined,
                          label: 'Origen',
                          value:
                              detail['origen']?.toString() ?? 'No disponible',
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.location_on_outlined,
                          label: 'Destino',
                          value:
                              detail['destino']?.toString() ?? 'No disponible',
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.payments_outlined,
                          label: 'Precio',
                          value: _formatPrice(detail['precio']),
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: isPaid
                              ? Icons.verified_outlined
                              : Icons.hourglass_empty_outlined,
                          label: 'Pago',
                          value: isPaid ? 'Pagado' : 'Pendiente de pago',
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.person_outline,
                          label: 'Cliente',
                          value: clientName,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.notes_outlined,
                          label: 'Anotaciones del cliente',
                          value: anotaciones.isEmpty
                              ? 'Sin anotaciones'
                              : anotaciones,
                        ),
                      ] else ...[
                        _buildInfoTile(
                          icon: Icons.place_outlined,
                          label: 'Origen',
                          value:
                              detail['origen']?.toString() ?? 'No disponible',
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.location_on_outlined,
                          label: 'Destino',
                          value:
                              detail['destino']?.toString() ?? 'No disponible',
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.payments_outlined,
                          label: 'Precio',
                          value: _formatPrice(detail['precio']),
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: isPaid
                              ? Icons.verified_outlined
                              : Icons.hourglass_empty_outlined,
                          label: 'Pago',
                          value: isPaid ? 'Pagado' : 'Pendiente de pago',
                        ),
                        const SizedBox(height: 10),
                        _buildInfoTile(
                          icon: Icons.local_taxi_outlined,
                          label: 'Taxista',
                          value: driverName,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!widget.isDriverView) ...[
                const SizedBox(height: 10),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Taxista',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('Nombre: ${_buildDriverName(detail)}'),
                        Text('Vehiculo: ${_buildVehicleName(detail)}'),
                      ],
                    ),
                  ),
                ),
              ],
              if (!widget.isDriverView &&
                  normalizeRideState(detail['estado']) == 'pendiente') ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isCancelling
                      ? null
                      : () => _confirmAndCancelRide(detail),
                  icon: _isCancelling
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cancel_outlined),
                  label: Text(
                    _isCancelling ? 'Cancelando...' : 'Cancelar viaje',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
              if (!widget.isDriverView &&
                  (state == 'confirmada' || state == 'en_curso') &&
                  !isPaid) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isPaying ? null : () => _payRide(detail),
                  icon: _isPaying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payments_outlined),
                  label: Text(_isPaying ? 'Procesando...' : 'Pagar viaje'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
              if (widget.isDriverView) ...[
                const SizedBox(height: 10),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cliente',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('Nombre: $clientName'),
                        Text(
                          'Telefono: ${detail['cliente_telefono']?.toString() ?? 'No disponible'}',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
