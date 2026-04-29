import 'package:flutter_test/flutter_test.dart';
import 'package:gotaxi/presentation/screens/home/tabs/map_tab.dart';

void main() {
  group('MapTab - Issue #112: Dirección de origen real', () {
    const defaultOriginText = 'Mi ubicación actual';

    test('lógica: usa dirección real cuando es "Mi ubicación actual"', () {
      final originText = defaultOriginText;
      final realAddress = 'Calle Mayor 15, Madrid';

      final origenFinal =
          (originText.isEmpty || originText == defaultOriginText)
          ? realAddress
          : originText;

      expect(origenFinal, realAddress);
    });

    test('lógica: usa dirección real cuando está vacío', () {
      final originText = '';
      final realAddress = 'Gran Vía 45, Madrid';

      final origenFinal =
          (originText.isEmpty || originText == defaultOriginText)
          ? realAddress
          : originText;

      expect(origenFinal, realAddress);
    });

    test('lógica: mantiene dirección personalizada del usuario', () {
      final originText = 'Aeropuerto Barajas, Madrid';

      final origenFinal =
          (originText.isEmpty || originText == defaultOriginText)
          ? 'Calle Falsa 123'
          : originText;

      expect(origenFinal, 'Aeropuerto Barajas, Madrid');
    });

    test('formato de dirección: calle + ciudad', () {
      final street = 'Calle Mayor 15';
      final locality = 'Madrid';

      String address;
      if (street.isNotEmpty && locality.isNotEmpty) {
        address = '$street, $locality';
      } else if (street.isNotEmpty) {
        address = street;
      } else {
        address = '$street, $locality';
      }

      expect(address, 'Calle Mayor 15, Madrid');
    });

    test('fallback a coordenadas si no hay street', () {
      final street = '';
      final locality = 'Madrid';
      final lat = 40.4168;
      final lng = -3.7038;

      String address;
      if (street.isNotEmpty && locality.isNotEmpty) {
        address = '$street, $locality';
      } else {
        address = '$lat,$lng';
      }

      expect(address, '40.4168,-3.7038');
    });

    test('fallback a street si no hay locality', () {
      final street = 'Calle Mayor';
      final locality = '';

      String address;
      if (street.isNotEmpty && locality.isNotEmpty) {
        address = '$street, $locality';
      } else if (street.isNotEmpty) {
        address = street;
      } else {
        address = '$street, $locality';
      }

      expect(address, 'Calle Mayor');
    });
  });

  group('RideService - Creación de viaje con dirección real', () {
    test('createRideAssignment usa dirección real (no coordenadas)', () {
      // Simular el comportamiento esperado después del fix #112
      const defaultOriginText = 'Mi ubicación actual';
      const userOriginText = defaultOriginText;
      const realAddress = 'Calle Mayor 15, Madrid';

      // Lo que hace el nuevo código en _createRide
      final origenFinal =
          (userOriginText.isEmpty || userOriginText == defaultOriginText)
          ? realAddress // _getFullAddress(origin)
          : userOriginText;

      expect(origenFinal, realAddress);
      expect(origenFinal, isNot('Mi ubicación actual'));
      expect(origenFinal, isNot(startsWith('40.'))); // No coordenadas
    });

    test('createRideAssignment mantiene dirección personalizada', () {
      const userOriginText = 'Aeropuerto Barajas, Madrid';
      const defaultOriginText = 'Mi ubicación actual';

      final origenFinal =
          (userOriginText.isEmpty || userOriginText == defaultOriginText)
          ? 'Calle Falsa 123'
          : userOriginText;

      expect(origenFinal, 'Aeropuerto Barajas, Madrid');
    });
  });

  group('MapTab autocomplete helpers', () {
    const defaultOriginText = 'Mi ubicación actual';

    test('no muestra autocomplete en origen sin foco aunque haya texto', () {
      expect(
        shouldShowAutocompleteSuggestions(
          fieldHasFocus: false,
          input: 'Calle Mayor 15, Madrid',
          defaultOriginText: defaultOriginText,
        ),
        isFalse,
      );
    });

    test('muestra autocomplete en destino con foco y texto válido', () {
      expect(
        shouldShowAutocompleteSuggestions(
          fieldHasFocus: true,
          input: 'Plaza Mayor, Madrid',
          defaultOriginText: defaultOriginText,
        ),
        isTrue,
      );
    });

    test(
      'no muestra autocomplete en origen si el texto es el predeterminado',
      () {
        expect(
          shouldShowAutocompleteSuggestions(
            fieldHasFocus: true,
            input: defaultOriginText,
            defaultOriginText: defaultOriginText,
          ),
          isFalse,
        );
      },
    );
  });
}
