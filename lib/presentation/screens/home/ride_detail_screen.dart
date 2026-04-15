import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gotaxi/data/services/app_links_service.dart';
import 'package:gotaxi/data/services/ride_service.dart';
import 'package:gotaxi/data/services/stripe_payment_service.dart';
import 'package:gotaxi/data/services/rating_service.dart';
import 'package:gotaxi/models/rating_model.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';
import 'package:gotaxi/utils/ratings/rating_utils.dart';

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

class _RideDetailScreenState extends State<RideDetailScreen>
    with WidgetsBindingObserver {
  final RideService _rideService = RideService();
  final StripePaymentService _stripePaymentService = StripePaymentService();
  final RatingService _ratingService = RatingService();

  late Future<Map<String, dynamic>> _detailFuture;
  bool _isCancelling = false;
  bool _isPaying = false;
  bool _waitingStripeReturn = false;
  bool _checkingPaymentStatus = false;
  bool _optimisticPaidUntilSync = false;
  bool _isRated = false;
  bool _ratingInProgress = false;
  StreamSubscription<Uri>? _deepLinkSubscription;
  String? _pendingCheckoutSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detailFuture = _fetchRideDetail();
    unawaited(_tryAutoSyncPendingPayment());
    unawaited(_checkRatingStatus());
    _deepLinkSubscription = AppLinksService.instance.uriStream.listen(
      _handleStripeDeepLink,
    );
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleStripeDeepLink(Uri uri) {
    if (uri.scheme != 'gotaxi' || uri.host != 'stripe') return;

    final isSuccess = uri.path.contains('success');
    final isCancel = uri.path.contains('cancel');
    final sessionId = uri.queryParameters['session_id'];

    if (!isSuccess && !isCancel) return;

    if (isCancel) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pago cancelado en Stripe.')),
      );
      _optimisticPaidUntilSync = false;
      _waitingStripeReturn = false;
      _pendingCheckoutSessionId = null;
      return;
    }

    _optimisticPaidUntilSync = true;
    _pendingCheckoutSessionId = sessionId;
    _waitingStripeReturn = true;
    unawaited(_markRideAsPaidLocally());
    unawaited(_checkPaymentAfterStripeReturn());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingStripeReturn) {
      unawaited(_checkPaymentAfterStripeReturn());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(
        _tryAutoSyncPendingPayment(
          checkoutSessionId: _pendingCheckoutSessionId,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _fetchRideDetail() {
    return widget.isDriverView
        ? fetchCurrentUserDriverRideDetail(rideId: widget.rideId)
        : fetchCurrentUserRideDetail(rideId: widget.rideId);
  }

  bool _isRidePaidFromData(Map<String, dynamic> detail) {
    if (detail['pagado'] == true) return true;
    final stripeStatus = detail['stripe_payment_status']
        ?.toString()
        .toLowerCase()
        .trim();
    return stripeStatus == 'succeeded' ||
        stripeStatus == 'successed' ||
        stripeStatus == 'paid';
  }

  bool _isRidePaid(Map<String, dynamic> detail) {
    return _optimisticPaidUntilSync || _isRidePaidFromData(detail);
  }

  Map<String, dynamic> _withOptimisticPaid(Map<String, dynamic> detail) {
    if (!_optimisticPaidUntilSync || _isRidePaidFromData(detail)) {
      return detail;
    }

    return Map<String, dynamic>.from(detail)
      ..['pagado'] = true
      ..['stripe_payment_status'] = 'succeeded';
  }

  Future<void> _checkPaymentAfterStripeReturn() async {
    if (_checkingPaymentStatus) return;
    _checkingPaymentStatus = true;

    try {
      for (var attempt = 0; attempt < 10; attempt++) {
        if (!mounted) return;

        try {
          await _stripePaymentService.syncRidePaymentStatus(
            rideId: widget.rideId,
            checkoutSessionId: _pendingCheckoutSessionId,
          );
        } catch (_) {
          // Si la sync falla, seguimos reintentando con la BD.
        }

        final latest = await _fetchRideDetail();
        if (!mounted) return;

        final confirmedPaid = _isRidePaidFromData(latest);
        final displayDetail = _withOptimisticPaid(latest);

        setState(() {
          _detailFuture = Future<Map<String, dynamic>>.value(displayDetail);
        });

        if (confirmedPaid) {
          _optimisticPaidUntilSync = false;
          _waitingStripeReturn = false;
          _pendingCheckoutSessionId = null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pago confirmado correctamente.')),
          );
          return;
        }

        if (attempt < 9) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aun no se refleja el pago. Se actualizara automaticamente en breve.',
          ),
        ),
      );
    } catch (_) {
      // Ignora errores transitorios de red al volver desde navegador.
    } finally {
      _checkingPaymentStatus = false;
    }
  }

  Future<void> _tryAutoSyncPendingPayment({String? checkoutSessionId}) async {
    if (widget.isDriverView || _checkingPaymentStatus) return;

    try {
      final current = await _fetchRideDetail();
      if (!mounted) return;

      final rideState = normalizeRideState(current['estado']);
      final isPendingInProgress =
          rideState == 'en_curso' && !_isRidePaidFromData(current);

      if (!isPendingInProgress) {
        setState(() {
          _detailFuture = Future<Map<String, dynamic>>.value(current);
        });
        return;
      }

      try {
        await _stripePaymentService.syncRidePaymentStatus(
          rideId: widget.rideId,
          checkoutSessionId: checkoutSessionId,
        );
      } catch (_) {
        // Ignora errores transitorios y deja la UI con el estado más reciente disponible.
      }

      final refreshed = await _fetchRideDetail();
      if (!mounted) return;

      if (_isRidePaidFromData(refreshed)) {
        _optimisticPaidUntilSync = false;
      }

      setState(() {
        _detailFuture = Future<Map<String, dynamic>>.value(
          _withOptimisticPaid(refreshed),
        );
      });
    } catch (_) {
      // No interrumpe la pantalla si la sync de fondo falla.
    }
  }

  Future<void> _markRideAsPaidLocally() async {
    try {
      final current = await _detailFuture;
      if (!mounted) return;

      _optimisticPaidUntilSync = true;
      final optimistic = _withOptimisticPaid(current);

      setState(() {
        _detailFuture = Future<Map<String, dynamic>>.value(optimistic);
      });
    } catch (_) {
      // Si el detalle actual no está disponible aún, la sync remota actualizará la UI.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _detailFuture = _fetchRideDetail();
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
    final isPaid = _isRidePaid(detail);

    if (isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este viaje ya está pagado.')),
      );
      return;
    }

    if (state != 'en_curso') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solo puedes pagar viajes en curso.')),
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
      _pendingCheckoutSessionId = result.checkoutSessionId;
      _waitingStripeReturn = true;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se abrio Stripe. Al volver, comprobaremos el estado del pago.',
          ),
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

  /// Check if the current ride has been rated already
  Future<void> _checkRatingStatus() async {
    try {
      final result = await _ratingService.checkIfRideRated(widget.rideId);
      if (mounted) {
        setState(() {
          _isRated = result.isRated;
        });
      }
    } catch (e) {
      print('Error checking rating status: $e');
    }
  }

  /// Show the main rating bottom sheet (green/red thumbs)
  void _showRatingBottomSheet(Map<String, dynamic> detail) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '¿Cómo fue tu viaje?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Green thumb button (positive)
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _showPositiveRatingDialog(detail);
                    },
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.thumb_up,
                            size: 48,
                            color: Colors.green.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Excelente',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  // Red thumb button (negative)
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _showNegativeRatingDialog(detail);
                    },
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.thumb_down,
                            size: 48,
                            color: Colors.red.shade600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Malo',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  /// Show dialog for positive rating (with optional comment)
  void _showPositiveRatingDialog(Map<String, dynamic> detail) {
    final controllerCommentario = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Gran viaje'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('¿Quieres agregar un comentario?'),
              const SizedBox(height: 16),
              TextField(
                controller: controllerCommentario,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Tu comentario aquí...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _submitRating(
                  detail: detail,
                  tipo: RatingType.positiva,
                  comentario: controllerCommentario.text.trim().isEmpty
                      ? null
                      : controllerCommentario.text.trim(),
                );
              },
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
  }

  /// Show dialog for negative rating (with mandatory motive selection)
  void _showNegativeRatingDialog(Map<String, dynamic> detail) {
    RatingMotive? selectedMotive;
    final controllerCommentario = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Lo sentimos'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('¿Cuál fue el problema?'),
                  const SizedBox(height: 12),
                  DropdownButton<RatingMotive>(
                    isExpanded: true,
                    value: selectedMotive,
                    hint: const Text('Selecciona un motivo'),
                    items: RatingConstants.negativeMotives.map((motive) {
                      return DropdownMenuItem(
                        value: motive,
                        child: Text(motive.toDisplayString()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedMotive = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedMotive == RatingMotive.otra
                        ? 'Cuéntanos qué pasó (obligatorio):'
                        : 'Cuéntanos más (opcional):',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controllerCommentario,
                    maxLines: 3,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: selectedMotive == RatingMotive.otra
                          ? 'Escribe el motivo...'
                          : 'Tu comentario aquí...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed:
                      selectedMotive == null ||
                          (selectedMotive == RatingMotive.otra &&
                              controllerCommentario.text.trim().isEmpty)
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _submitRating(
                            detail: detail,
                            tipo: RatingType.negativa,
                            motivo: selectedMotive,
                            comentario:
                                controllerCommentario.text.trim().isEmpty
                                ? null
                                : controllerCommentario.text.trim(),
                          );
                        },
                  child: const Text('Enviar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Submit the rating to Supabase
  Future<void> _submitRating({
    required Map<String, dynamic> detail,
    required RatingType tipo,
    RatingMotive? motivo,
    String? comentario,
  }) async {
    if (_ratingInProgress) return;

    final taxistaId = _resolveTaxistaId(detail);

    if (taxistaId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo obtener el ID del taxista'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _ratingInProgress = true);

    try {
      final result = await _ratingService.submitRating(
        viajeId: widget.rideId,
        taxistaId: taxistaId,
        tipo: tipo,
        motivo: motivo,
        comentario: comentario,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _isRated = true;
          _ratingInProgress = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Valoración enviada! Gracias por tu feedback.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _ratingInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _ratingInProgress = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar valoración: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String? _resolveTaxistaId(Map<String, dynamic> detail) {
    final directKeys = [
      detail['taxista_id'],
      detail['driver_id'],
      detail['taxistaId'],
      detail['driverId'],
    ];

    for (final value in directKeys) {
      final id = value?.toString().trim();
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }

    final nestedDriver = detail['driver'];
    if (nestedDriver is Map) {
      final nestedId = nestedDriver['id']?.toString().trim();
      if (nestedId != null && nestedId.isNotEmpty) {
        return nestedId;
      }
    }

    final nestedTaxista = detail['taxista'];
    if (nestedTaxista is Map) {
      final nestedId = nestedTaxista['id']?.toString().trim();
      if (nestedId != null && nestedId.isNotEmpty) {
        return nestedId;
      }
    }

    return null;
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
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
          Icon(icon, size: 18, color: iconColor ?? colorScheme.primary),
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
          final isPaid = _isRidePaid(detail);

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
                          iconColor: isPaid ? Colors.green : null,
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
                          iconColor: isPaid ? Colors.green : null,
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
                  normalizeRideState(detail['estado']) == 'finalizada' &&
                  !_isRated) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _ratingInProgress
                      ? null
                      : () => _showRatingBottomSheet(detail),
                  icon: _ratingInProgress
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.rate_review_outlined),
                  label: Text(
                    _ratingInProgress
                        ? 'Enviando valoración...'
                        : 'Valora tu viaje',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
              if (!widget.isDriverView &&
                  normalizeRideState(detail['estado']) == 'finalizada' &&
                  _isRated) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade600),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Valoración enviada',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
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
              if (!widget.isDriverView && state == 'en_curso' && !isPaid) ...[
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
