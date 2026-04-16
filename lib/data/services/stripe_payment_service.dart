import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class StripePaymentMethodSummary {
  const StripePaymentMethodSummary({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
  });

  final String id;
  final String brand;
  final String last4;
  final int? expMonth;
  final int? expYear;
  final bool isDefault;

  factory StripePaymentMethodSummary.fromMap(Map<String, dynamic> map) {
    return StripePaymentMethodSummary(
      id: map['stripe_payment_method_id']?.toString() ?? '',
      brand: map['brand']?.toString() ?? 'Card',
      last4: map['last4']?.toString() ?? '----',
      expMonth: int.tryParse(map['exp_month']?.toString() ?? ''),
      expYear: int.tryParse(map['exp_year']?.toString() ?? ''),
      isDefault: map['is_default'] == true,
    );
  }

  String get label {
    final parts = <String>[
      brand,
      '•••• $last4',
      if (expMonth != null && expYear != null)
        '${expMonth!.toString().padLeft(2, '0')}/$expYear',
    ];
    return parts.join(' · ');
  }
}

class StripeCheckoutResult {
  const StripeCheckoutResult({
    required this.success,
    required this.message,
    this.checkoutUrl,
    this.checkoutSessionId,
  });

  final bool success;
  final String message;
  final String? checkoutUrl;
  final String? checkoutSessionId;

  factory StripeCheckoutResult.fromMap(Map<String, dynamic> map) {
    return StripeCheckoutResult(
      success: map['success'] == true,
      message: map['message']?.toString() ?? 'Operacion completada',
      checkoutUrl: map['checkout_url']?.toString(),
      checkoutSessionId: map['checkout_session_id']?.toString(),
    );
  }
}

class StripePaymentService {
  StripePaymentService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<StripePaymentMethodSummary>> listMyPaymentMethods() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Debes iniciar sesion para ver tus metodos de pago.');
    }

    final localResponse = await _supabase
        .from('cliente_metodos_pago')
        .select(
          'stripe_payment_method_id, brand, last4, exp_month, exp_year, is_default',
        )
        .eq('cliente_id', user.id)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    final localMethods = List<Map<String, dynamic>>.from(
      localResponse,
    ).map(StripePaymentMethodSummary.fromMap).toList();

    if (localMethods.isNotEmpty) {
      return localMethods;
    }

    final syncedMethods = await syncMyPaymentMethods();
    if (syncedMethods.isNotEmpty) {
      return syncedMethods;
    }

    return localMethods;
  }

  Future<List<StripePaymentMethodSummary>> syncMyPaymentMethods() async {
    final session = await _ensureFreshSession();
    if (session == null) {
      throw StateError('Debes iniciar sesion para continuar.');
    }

    final response = await _invokeStripeFunction({
      'action': 'sync_payment_methods',
    }, accessToken: session.accessToken);

    final methods = response['methods'];
    if (methods is List) {
      return methods
          .whereType<Map>()
          .map(
            (method) => StripePaymentMethodSummary.fromMap(
              Map<String, dynamic>.from(method),
            ),
          )
          .toList();
    }

    return const [];
  }

  Future<StripeCheckoutResult> createPaymentMethodSetupSession() async {
    return _requestCheckoutSession({'action': 'setup_method'});
  }

  Future<StripeCheckoutResult> createRidePaymentSession({
    required String rideId,
  }) async {
    return _requestCheckoutSession({'action': 'pay_ride', 'ride_id': rideId});
  }

  Future<bool> syncRidePaymentStatus({
    required String rideId,
    String? checkoutSessionId,
  }) async {
    final session = await _ensureFreshSession();
    if (session == null) {
      throw StateError('Debes iniciar sesion para continuar.');
    }

    final response = await _invokeStripeFunction({
      'action': 'sync_ride_payment',
      'ride_id': rideId,
      if (checkoutSessionId != null && checkoutSessionId.isNotEmpty)
        'checkout_session_id': checkoutSessionId,
    }, accessToken: session.accessToken);

    return response['paid'] == true ||
        response['synced'] == true &&
            (response['paymentStatus'] == 'succeeded' ||
                response['paymentStatus'] == 'successed' ||
                response['paymentStatus'] == 'paid');
  }

  Future<StripeCheckoutResult> _requestCheckoutSession(
    Map<String, dynamic> body,
  ) async {
    final session = await _ensureFreshSession();
    if (session == null) {
      throw StateError('Debes iniciar sesion para continuar.');
    }

    final response = await _invokeStripeFunction(
      body,
      accessToken: session.accessToken,
    );
    return _decodeCheckoutResponse(response);
  }

  Future<Session?> _ensureFreshSession() async {
    final currentSession = _supabase.auth.currentSession;
    if (currentSession == null) {
      return null;
    }

    return currentSession;
  }

  Future<Map<String, dynamic>> _invokeStripeFunction(
    Map<String, dynamic> body, {
    required String accessToken,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'stripe-payments',
        body: body,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }

      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }

      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }

      return const <String, dynamic>{
        'success': false,
        'message': 'Respuesta inesperada del servidor.',
      };
    } on FunctionException catch (error) {
      final bodyText = error.details?.toString();
      if (bodyText != null && bodyText.isNotEmpty) {
        try {
          final decoded = jsonDecode(bodyText);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          return <String, dynamic>{'success': false, 'message': bodyText};
        }
      }

      return <String, dynamic>{
        'success': false,
        'message': error.toString().isNotEmpty
            ? error.toString()
            : 'No se pudo iniciar la operacion de Stripe.',
      };
    }
  }

  StripeCheckoutResult _decodeCheckoutResponse(Map<String, dynamic> data) {
    final result = StripeCheckoutResult.fromMap(data);

    if (!result.success) {
      return StripeCheckoutResult(
        success: false,
        message: result.message.isNotEmpty
            ? result.message
            : 'No se pudo iniciar el pago.',
      );
    }

    return result;
  }

  Future<void> openCheckoutUrl(String checkoutUrl) async {
    final uri = Uri.parse(checkoutUrl);
    final opened =
        await launchUrl(uri, mode: LaunchMode.externalApplication) ||
        await launchUrl(uri, mode: LaunchMode.platformDefault);

    if (!opened) {
      throw StateError('No se pudo abrir la pagina de pago.');
    }
  }
}
