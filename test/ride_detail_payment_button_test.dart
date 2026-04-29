import 'package:flutter_test/flutter_test.dart';
import 'package:gotaxi/presentation/screens/home/ride_detail_screen.dart';
import 'package:gotaxi/utils/profile/rides/ride_history_utils.dart';

void main() {
  group('RideDetailScreen payment button logic', () {
    test('deshabilita el botón cuando el pago ya está en curso', () {
      final enabled = shouldEnableRidePaymentButton(
        isDriverView: false,
        isPaying: true,
        waitingStripeReturn: false,
        isPaid: false,
        rideState: 'en_curso',
      );

      expect(enabled, isFalse);
    });

    test('deshabilita el botón cuando se espera el retorno de Stripe', () {
      final enabled = shouldEnableRidePaymentButton(
        isDriverView: false,
        isPaying: false,
        waitingStripeReturn: true,
        isPaid: false,
        rideState: 'en_curso',
      );

      expect(enabled, isFalse);
    });

    test(
      'habilita el botón solo para un viaje en curso no pagado y no driver view',
      () {
        final enabled = shouldEnableRidePaymentButton(
          isDriverView: false,
          isPaying: false,
          waitingStripeReturn: false,
          isPaid: false,
          rideState: 'en_curso',
        );

        expect(enabled, isTrue);
      },
    );

    test(
      'deshabilita el botón en modo driver incluso si el viaje está en curso',
      () {
        final enabled = shouldEnableRidePaymentButton(
          isDriverView: true,
          isPaying: false,
          waitingStripeReturn: false,
          isPaid: false,
          rideState: 'en_curso',
        );

        expect(enabled, isFalse);
      },
    );

    test('no muestra el mapa cuando el estado es en_curso', () {
      expect(shouldShowRideMap('en_curso'), isFalse);
    });

    test('muestra el mapa solo cuando el estado es confirmada', () {
      expect(shouldShowRideMap('confirmada'), isTrue);
    });

    test(
      'polling se activa solo en viaje en curso cuando espera retorno Stripe',
      () {
        expect(
          shouldPollStripePayment(
            rideState: 'en_curso',
            waitingStripeReturn: true,
          ),
          isTrue,
        );
      },
    );

    test('polling no se activa si no hay retorno Stripe pendiente', () {
      expect(
        shouldPollStripePayment(
          rideState: 'en_curso',
          waitingStripeReturn: false,
        ),
        isFalse,
      );
    });

    test('polling no se activa en estados distintos de en_curso', () {
      expect(
        shouldPollStripePayment(
          rideState: 'confirmada',
          waitingStripeReturn: true,
        ),
        isFalse,
      );
    });
  });

  group('normalizeRidePaymentStatus', () {
    test('interpreta true en String como pago', () {
      expect(normalizeRidePaymentStatus('true'), isTrue);
    });

    test('interpreta valor booleano true como pago', () {
      expect(normalizeRidePaymentStatus(true), isTrue);
    });

    test('interpreta otros valores como no pago', () {
      expect(normalizeRidePaymentStatus('false'), isFalse);
      expect(normalizeRidePaymentStatus(null), isFalse);
    });
  });
}
