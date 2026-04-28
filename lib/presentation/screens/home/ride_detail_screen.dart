import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  /// Factory constructor for navigation from notifications when we don't have initialRide
  static Future<void> openFromNotification(BuildContext context, String rideId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideDetailScreenFromNotification(rideId: rideId),
      ),
    );
  }

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class RideDetailScreenFromNotification extends StatefulWidget {
  const RideDetailScreenFromNotification({
    super.key,
    required this.rideId,
  });

  final String rideId;

  @override
  State<RideDetailScreenFromNotification> createState() => _RideDetailScreenFromNotificationState();
}

class _RideDetailScreenFromNotificationState extends State<RideDetailScreenFromNotification> {
  late Future<Map<String, dynamic>> _detailFuture;
  final RideService _rideService = RideService();

  @override
  void initState() {
    super.initState();
    _detailFuture = _rideService.fetchRideDetail(widget.rideId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: const Center(child: Text('No se pudo cargar el viaje')),
          );
        }

        return RideDetailScreen(
          rideId: widget.rideId,
          initialRide: snapshot.data!,
        );
      },
    );
  }
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
  bool _refreshInProgress = false;
  bool _isRated = false;
  bool _ratingInProgress = false;
  int? _etaMinutes;
  DateTime? _etaUpdatedAt;
  DateTime? _etaArrivalAt;
  StreamSubscription<Uri>? _deepLinkSubscription;
  Timer? _refreshTimer;
  Timer? _etaTimer;
  String? _pendingCheckoutSessionId;

  // Map for driver location
  GoogleMapController? _mapController;
  final Set<Marker> _markers = <Marker>{};
  double? _driverLat;
  double? _driverLng;
  double? _originLat;
  double? _originLng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detailFuture = _fetchRideDetail();
    unawaited(_tryAutoSyncPendingPayment());
    unawaited(_checkRatingStatus());
    _startAutoRefresh();
    _deepLinkSubscription = AppLinksService.instance.uriStream.listen(
      _handleStripeDeepLink,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _etaTimer?.cancel();
    _deepLinkSubscription?.cancel();
    _mapController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startAutoRefresh() {
    if (widget.isDriverView) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_refreshDetailAndEta()),
    );
    unawaited(_refreshDetailAndEta());
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
    _pendingCheckoutSessionId = sessionId;
    _waitingStripeReturn = true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Volviendo de Stripe. Verificando el pago...'),
      ),
    );
    unawaited(_checkPaymentAfterStripeReturn());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingStripeReturn) {
      unawaited(_checkPaymentAfterStripeReturn());
      return;
    }
    if (state == AppLifecycleState.resumed)
      unawaited(
        _tryAutoSyncPendingPayment(
          checkoutSessionId: _pendingCheckoutSessionId,
        ),
      );
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

  bool _isRidePaid(Map<String, dynamic> detail) =>
      _optimisticPaidUntilSync || _isRidePaidFromData(detail);

  Map<String, dynamic> _withOptimisticPaid(Map<String, dynamic> detail) {
    if (!_optimisticPaidUntilSync || _isRidePaidFromData(detail)) return detail;
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
        final checkoutSessionId = _pendingCheckoutSessionId;
        if (checkoutSessionId == null || checkoutSessionId.isEmpty) {
          break;
        }
        try {
          await _stripePaymentService.syncRidePaymentStatus(
            rideId: widget.rideId,
            checkoutSessionId: checkoutSessionId,
          );
        } catch (_) {}
        final latest = await _fetchRideDetail();
        if (!mounted) return;
        final confirmedPaid = _isRidePaidFromData(latest);
        setState(
          () => _detailFuture = Future<Map<String, dynamic>>.value(latest),
        );
        if (confirmedPaid) {
          _optimisticPaidUntilSync = false;
          _waitingStripeReturn = false;
          _pendingCheckoutSessionId = null;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pago confirmado correctamente.')),
          );
          return;
        }
        if (attempt < 9) await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aun no se confirma el pago. Reintentaremos la sincronizacion en breve.',
          ),
        ),
      );
    } catch (_) {
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
        setState(
          () => _detailFuture = Future<Map<String, dynamic>>.value(current),
        );
        return;
      }
      try {
        await _stripePaymentService.syncRidePaymentStatus(
          rideId: widget.rideId,
          checkoutSessionId: checkoutSessionId,
        );
      } catch (_) {}
      final refreshed = await _fetchRideDetail();
      if (!mounted) return;
      if (_isRidePaidFromData(refreshed)) {
        _optimisticPaidUntilSync = false;
      }
      setState(
        () => _detailFuture = Future<Map<String, dynamic>>.value(refreshed),
      );
    } catch (_) {}
  }

  Future<void> _reload() async => await _refreshDetailAndEta();

  Future<void> _refreshDetailAndEta() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    try {
      final latest = await _fetchRideDetail();
      if (!mounted) return;
      final mergedDetail = _mergeRideDetail(latest);
      final displayDetail = _withOptimisticPaid(mergedDetail);
      final state = normalizeRideState(displayDetail['estado']);
      setState(
        () => _detailFuture = Future<Map<String, dynamic>>.value(displayDetail),
      );
      if (state == 'confirmada') {
        final localEtaMinutes = _estimateEtaMinutes(displayDetail);
        if (localEtaMinutes != null) {
          setState(() {
            _etaMinutes = localEtaMinutes;
            _etaUpdatedAt = DateTime.now();
            _etaArrivalAt = DateTime.now().add(
              Duration(minutes: localEtaMinutes),
            );
          });
          _startEtaTicker();
        }
        await _refreshEta(displayDetail);
      } else {
        if (!mounted) return;
        setState(() {
          _etaMinutes = null;
          _etaUpdatedAt = null;
          _etaArrivalAt = null;
        });
        _stopEtaTicker();
      }
    } catch (_) {
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<void> _refreshEta(Map<String, dynamic> rideDetail) async {
    try {
      final result = await _rideService.fetchRideEtaFromDetail(rideDetail);
      if (!mounted) return;
      if (!result.available || result.etaMin == null) {
        final fallback = await _rideService.fetchRideEta(rideId: widget.rideId);
        if (!mounted) return;
        if (fallback.available && fallback.etaMin != null) {
          final fallbackUpdatedAt = fallback.updatedAt?.toLocal();
          final fallbackArrivalAt = fallbackUpdatedAt?.add(
            Duration(minutes: fallback.etaMin!),
          );
          setState(() {
            _etaMinutes = fallback.etaMin;
            _etaUpdatedAt = fallbackUpdatedAt;
            _etaArrivalAt = fallbackArrivalAt;
          });
          _startEtaTicker();
          return;
        }

        if (_etaUpdatedAt != null && _etaArrivalAt != null) {
          _startEtaTicker();
          return;
        }
        setState(() {
          _etaMinutes = null;
          _etaUpdatedAt = null;
          _etaArrivalAt = null;
        });
        _stopEtaTicker();
        return;
      }
      final updatedAt = result.updatedAt?.toLocal();
      final arrivalAt = updatedAt?.add(Duration(minutes: result.etaMin!));
      setState(() {
        _etaMinutes = result.etaMin;
        _etaUpdatedAt = updatedAt;
        _etaArrivalAt = arrivalAt;
      });
      _startEtaTicker();
    } catch (_) {
      if (!mounted) return;
      if (_etaUpdatedAt != null && _etaArrivalAt != null) {
        _startEtaTicker();
        return;
      }
      setState(() {
        _etaMinutes = null;
        _etaUpdatedAt = null;
        _etaArrivalAt = null;
      });
      _stopEtaTicker();
    }
  }

  void _startEtaTicker() {
    if (widget.isDriverView) return;
    _etaTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _stopEtaTicker() {
    _etaTimer?.cancel();
    _etaTimer = null;
  }

  Map<String, dynamic> _mergeRideDetail(Map<String, dynamic> detail) {
    return {...widget.initialRide, ...detail};
  }

  int? _estimateEtaMinutes(Map<String, dynamic> detail) {
    final originLat = _parseDouble(detail['origen_lat']);
    final originLng = _parseDouble(detail['origen_lng']);
    final driverLat = _parseDouble(detail['driver_lat']);
    final driverLng = _parseDouble(detail['driver_lng']);

    if (originLat == null ||
        originLng == null ||
        driverLat == null ||
        driverLng == null) {
      return null;
    }

    final distanceKm = _haversineKm(driverLat, driverLng, originLat, originLng);
    return (distanceKm / 0.45).ceil().clamp(1, 9999);
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (pi / 180.0);

  String _formatDuration(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    final hours = safeDuration.inHours;
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    return '${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _buildEtaCountdownText([DateTime? arrivalAt]) {
    final effectiveArrivalAt = arrivalAt ?? _etaArrivalAt;
    if (effectiveArrivalAt == null) return 'No disponible';
    final remaining = effectiveArrivalAt.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero)
      return 'Llegada inminente';
    return _formatDuration(remaining);
  }

  String _formatDate(dynamic rawValue) {
    if (rawValue == null) return 'Sin fecha';
    final parsed = DateTime.tryParse(rawValue.toString());
    if (parsed == null) return rawValue.toString();
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours h';
    return '$hours h $remainingMinutes min';
  }

  String _formatActualDuration(Map<String, dynamic> detail) {
    final start = DateTime.tryParse(detail['fecha_recogida']?.toString() ?? '');
    final end = DateTime.tryParse(detail['fecha_entrega']?.toString() ?? '');
    if (start == null || end == null || end.isBefore(start))
      return 'No disponible';
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
      case 'en_curso':
        return widget.isDriverView ? scheme.outline : Colors.red;
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
      builder: (context) => AlertDialog(
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
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isCancelling = true);
    try {
      final result = await _rideService.cancelRide(viajeId: widget.rideId);
      if (!mounted) return;
      final color = result.success
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message), backgroundColor: color),
      );
      if (result.success)
        Navigator.of(
          context,
        ).pop({...detail, 'estado': result.estado ?? 'cancelada'});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
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

  Future<void> _checkRatingStatus() async {
    try {
      final result = await _ratingService.checkIfRideRated(widget.rideId);
      if (mounted) setState(() => _isRated = result.isRated);
    } catch (e) {
      print('Error checking rating status: $e');
    }
  }

  void _showRatingBottomSheet(Map<String, dynamic> detail) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => Padding(
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
      ),
    );
  }

  void _showPositiveRatingDialog(Map<String, dynamic> detail) {
    final controllerCommentario = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
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
      ),
    );
  }

  void _showNegativeRatingDialog(Map<String, dynamic> detail) {
    RatingMotive? selectedMotive;
    final controllerCommentario = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                items: RatingConstants.negativeMotives
                    .map(
                      (motive) => DropdownMenuItem(
                        value: motive,
                        child: Text(motive.toDisplayString()),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedMotive = value),
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
                        comentario: controllerCommentario.text.trim().isEmpty
                            ? null
                            : controllerCommentario.text.trim(),
                      );
                    },
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRating({
    required Map<String, dynamic> detail,
    required RatingType tipo,
    RatingMotive? motivo,
    String? comentario,
  }) async {
    if (_ratingInProgress) return;
    final taxistaId = _resolveTaxistaId(detail);
    if (taxistaId == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo obtener el ID del taxista'),
            backgroundColor: Colors.red,
          ),
        );
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
      if (id != null && id.isNotEmpty) return id;
    }
    final nestedDriver = detail['driver'];
    if (nestedDriver is Map) {
      final nestedId = nestedDriver['id']?.toString().trim();
      if (nestedId != null && nestedId.isNotEmpty) return nestedId;
    }
    final nestedTaxista = detail['taxista'];
    if (nestedTaxista is Map) {
      final nestedId = nestedTaxista['id']?.toString().trim();
      if (nestedId != null && nestedId.isNotEmpty) return nestedId;
    }
    return null;
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
    double padding = 10,
    double fontSize = 13,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor ?? colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: fontSize - 1,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: fontSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactChip({
    required IconData icon,
    required String value,
    Color? color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? colorScheme.primary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (color ?? colorScheme.primary).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color ?? colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideMap(String state, ColorScheme colorScheme) {
    final detail = _mergeRideDetail(widget.initialRide);
    _driverLat = detail['driver_lat'] as double?;
    _driverLng = detail['driver_lng'] as double?;
    _originLat = detail['origen_lat'] as double?;
    _originLng = detail['origen_lng'] as double?;

    if (_driverLat == null || _driverLng == null) {
      return const SizedBox.shrink();
    }

    // Update markers
    _markers.clear();
    _markers.add(
      Marker(
        markerId: const MarkerId('taxista'),
        position: LatLng(_driverLat!, _driverLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: const InfoWindow(title: 'Taxista'),
      ),
    );

    if (_originLat != null && _originLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('origen'),
          position: LatLng(_originLat!, _originLng!),
          infoWindow: const InfoWindow(title: 'Origen'),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: GoogleMap(
        onMapCreated: (controller) {
          _mapController = controller;
          // Fit map to show both markers
          if (_originLat != null && _originLng != null) {
            controller.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(
                    _driverLat! < _originLat! ? _driverLat! : _originLat!,
                    _driverLng! < _originLng! ? _driverLng! : _originLng!,
                  ),
                  northeast: LatLng(
                    _driverLat! > _originLat! ? _driverLat! : _originLat!,
                    _driverLng! > _originLng! ? _driverLng! : _originLng!,
                  ),
                ),
                50,
              ),
            );
          }
        },
        initialCameraPosition: CameraPosition(
          target: LatLng(_driverLat!, _driverLng!),
          zoom: 14,
        ),
        markers: _markers,
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
      ),
    );
  }

  Widget _buildPersonCard({
    required BuildContext context,
    required String name,
    String? subtitle,
    String? trailing,
    String? avatarUrl,
    IconData? icon,
    Color? bgColor,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: (bgColor ?? colorScheme.primary).withValues(alpha: 0.1),
            backgroundImage:
                (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Icon(icon ?? Icons.person, color: iconColor ?? colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trailing,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
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
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
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
          final detail = _mergeRideDetail(snapshot.data ?? widget.initialRide);
          final state = normalizeRideState(detail['estado']);
          final colorScheme = Theme.of(context).colorScheme;
          final statusColor = _statusColor(state, colorScheme);
          final clientName = _buildClientName(detail);
          final estimatedDuration = _formatMinutes(detail['duracion']);
          final actualDuration = _formatActualDuration(detail);
          final anotaciones = detail['anotaciones']?.toString().trim() ?? '';
          final isPaid = _isRidePaid(detail);
          final isFinalized = state == 'finalizada';
          final displayEtaMinutes = _etaMinutes ?? _estimateEtaMinutes(detail);
          final displayEtaArrivalAt =
              _etaArrivalAt ??
              (displayEtaMinutes != null
                  ? DateTime.now().add(Duration(minutes: displayEtaMinutes))
                  : null);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, size: 20, color: statusColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Viaje #${widget.rideId.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          state.isEmpty ? 'sin estado' : state.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Map showing driver location for active rides
                if (state == 'confirmada' || state == 'en_curso') ...[
                  _buildRideMap(state, colorScheme),
                  const SizedBox(height: 16),
                ],
                Text(
                  widget.isDriverView ? 'CLIENTE' : 'TAXISTA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPersonCard(
                  context: context,
                  name: widget.isDriverView
                      ? clientName
                      : _buildDriverName(detail),
                  subtitle: widget.isDriverView
                      ? detail['cliente_telefono']?.toString()
                      : _buildVehicleName(detail),
                  icon: widget.isDriverView ? Icons.person : Icons.local_taxi,
                  bgColor: colorScheme.primary,
                  iconColor: colorScheme.primary,
                ),
                if (widget.isDriverView && anotaciones.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInfoTile(
                    icon: Icons.notes,
                    label: 'Anotaciones',
                    value: anotaciones,
                    padding: 8,
                    fontSize: 12,
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'DETALLES DEL VIAJE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildCompactChip(
                      icon: Icons.place,
                      value: (detail['origen']?.toString() ?? 'Origen')
                          .split(',')
                          .first,
                    ),
                    _buildCompactChip(
                      icon: Icons.location_on,
                      value: (detail['destino']?.toString() ?? 'Destino')
                          .split(',')
                          .first,
                    ),
                    _buildCompactChip(
                      icon: Icons.schedule,
                      value: _formatDate(detail['created_at']),
                    ),
                  ],
                ),
                if (widget.isDriverView) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildCompactChip(
                        icon: Icons.people,
                        value:
                            '${detail['num_pasajeros']?.toString() ?? '0'} Pax',
                      ),
                      _buildCompactChip(
                        icon: Icons.timer,
                        value: estimatedDuration,
                      ),
                      if (state == 'finalizada')
                        _buildCompactChip(
                          icon: Icons.av_timer,
                          value: actualDuration,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'PAGO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoTile(
                        icon: isPaid
                            ? Icons.check_circle
                            : Icons.hourglass_empty,
                        label: 'Estado',
                        value: isPaid
                            ? 'Pagado'
                            : (isFinalized ? 'Pagado al taxista' : 'Pendiente'),
                        iconColor: isPaid ? Colors.green : Colors.orange,
                        padding: 10,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoTile(
                        icon: Icons.payments,
                        label: 'Total',
                        value: _formatPrice(detail['precio']),
                        padding: 10,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (!widget.isDriverView &&
                    state == 'confirmada' &&
                    displayEtaMinutes != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.directions_car,
                          color: colorScheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Taxista en camino',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                              Text(
                                'Llega en ${_buildEtaCountdownText(displayEtaArrivalAt)}',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!widget.isDriverView &&
                    state == 'confirmada' &&
                    displayEtaMinutes == null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_searching,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Esperando ubicación...',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!widget.isDriverView &&
                    normalizeRideState(detail['estado']) == 'finalizada' &&
                    !_isRated) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _ratingInProgress
                          ? null
                          : () => _showRatingBottomSheet(detail),
                      icon: _ratingInProgress
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.rate_review),
                      label: Text(
                        _ratingInProgress ? 'Enviando...' : 'Valorar viaje',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                if (!widget.isDriverView &&
                    normalizeRideState(detail['estado']) == 'finalizada' &&
                    _isRated) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green.shade600,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Valoración enviada',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!widget.isDriverView &&
                    normalizeRideState(detail['estado']) == 'pendiente') ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isCancelling
                          ? null
                          : () => _confirmAndCancelRide(detail),
                      icon: _isCancelling
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cancel),
                      label: Text(_isCancelling ? 'Cancelando...' : 'Cancelar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        side: BorderSide(color: colorScheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                if (!widget.isDriverView && state == 'en_curso' && !isPaid) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isPaying ? null : () => _payRide(detail),
                      icon: _isPaying
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.payment),
                      label: Text(_isPaying ? 'Procesando...' : 'Pagar ahora'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
