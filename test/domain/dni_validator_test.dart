import 'package:flutter_test/flutter_test.dart';
import 'package:gotaxi/domain/validators/dni_validator.dart';

void main() {
  group('validarDniNie', () {
    test('valida DNI correcto', () {
      expect(validarDniNie('12345678Z'), isTrue);
    });

    test('rechaza DNI con letra incorrecta', () {
      expect(validarDniNie('12345678A'), isFalse);
    });

    test('valida NIE correcto', () {
      expect(validarDniNie('X1234567L'), isTrue);
    });

    test('rechaza formato invalido', () {
      expect(validarDniNie('ABC123'), isFalse);
    });
  });
}
