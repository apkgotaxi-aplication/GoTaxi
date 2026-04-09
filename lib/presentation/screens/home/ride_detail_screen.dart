import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/ride_service.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';

class RideDetailScreen extends StatefulWidget {
  const RideDetailScreen({
    super.key,
    required this.rideId,
    required this.initialRide,
  });

  final String rideId;
  final Map<String, dynamic> initialRide;

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  final RideService _rideService = RideService();

  late Future<Map<String, dynamic>> _detailFuture;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = fetchCurrentUserRideDetail(rideId: widget.rideId);
  }

  Future<void> _reload() async {
    setState(() {
      _detailFuture = fetchCurrentUserRideDetail(rideId: widget.rideId);
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

    final canCancel = isRideCancelable(detail['estado']);
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

          final phone =
              (detail['driver_telefono']?.toString().trim() ?? '').isEmpty
              ? 'No disponible'
              : detail['driver_telefono'].toString().trim();

          return ListView(
            padding: const EdgeInsets.all(16),
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
                      Text('Solicitado: ${_formatDate(detail['created_at'])}'),
                      Text(
                        'Recogida: ${_formatDate(detail['fecha_recogida'])}',
                      ),
                      Text('Entrega: ${_formatDate(detail['fecha_entrega'])}'),
                      const SizedBox(height: 8),
                      Text('Origen: ${detail['origen'] ?? 'No disponible'}'),
                      Text('Destino: ${detail['destino'] ?? 'No disponible'}'),
                      const SizedBox(height: 8),
                      Text('Precio: ${_formatPrice(detail['precio'])}'),
                      Text(
                        'Pasajeros: ${detail['num_pasajeros'] ?? 'No disponible'}',
                      ),
                    ],
                  ),
                ),
              ),
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
                      const Text(
                        'Taxista',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Nombre: ${_buildDriverName(detail)}'),
                      Text('Telefono: $phone'),
                    ],
                  ),
                ),
              ),
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
                      const Text(
                        'Vehiculo',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Modelo: ${_buildVehicleName(detail)}'),
                      Text(
                        'Matricula: ${detail['vehiculo_matricula'] ?? 'No disponible'}',
                      ),
                      Text(
                        'Licencia: ${detail['vehiculo_licencia_taxi'] ?? 'No disponible'}',
                      ),
                      Text(
                        'Color: ${detail['vehiculo_color'] ?? 'No disponible'}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (isRideCancelable(state))
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
          );
        },
      ),
    );
  }
}
