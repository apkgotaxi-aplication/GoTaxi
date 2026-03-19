import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotaxi/data/services/auth_service.dart';
import 'package:gotaxi/presentation/screens/auth/auth_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService authService;

  setUp(() {
    authService = MockAuthService();
  });

  Widget buildScreen() {
    return MaterialApp(
      home: AuthScreen(
        authService: authService,
        homeBuilder: (_) => const Scaffold(body: Text('Home fake')),
      ),
    );
  }

  testWidgets('muestra error si login va vacio', (tester) async {
    await tester.pumpWidget(buildScreen());

    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Por favor, rellena todos los campos'), findsOneWidget);
  });

  testWidgets('login correcto llama signIn y navega', (tester) async {
    when(
      () => authService.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());

    await tester.enterText(find.byType(TextField).at(0), 'test@mail.com');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(
      () => authService.signIn(email: 'test@mail.com', password: '123456'),
    ).called(1);

    expect(find.text('Home fake'), findsOneWidget);
  });

  testWidgets('registro con DNI invalido muestra error', (tester) async {
    await tester.pumpWidget(buildScreen());

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Ana');
    await tester.enterText(find.byType(TextField).at(1), 'Lopez');
    await tester.enterText(find.byType(TextField).at(2), '600123123');
    await tester.enterText(find.byType(TextField).at(3), '00000000A');
    await tester.enterText(find.byType(TextField).at(4), 'ana@mail.com');
    await tester.enterText(find.byType(TextField).at(5), '123456');

    await tester.tap(find.text('Registrarse'));
    await tester.pump();

    expect(find.text('El DNI introducido no es correcto'), findsOneWidget);
    verifyNever(
      () => authService.signUp(
        email: any(named: 'email'),
        password: any(named: 'password'),
        data: any(named: 'data'),
      ),
    );
  });

  testWidgets('registro correcto llama signUp y vuelve a login', (tester) async {
    when(
      () => authService.signUp(
        email: any(named: 'email'),
        password: any(named: 'password'),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(buildScreen());

    await tester.tap(find.text('¿No tienes cuenta? Regístrate'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Ana');
    await tester.enterText(find.byType(TextField).at(1), 'Lopez');
    await tester.enterText(find.byType(TextField).at(2), '600123123');
    await tester.enterText(find.byType(TextField).at(3), '12345678Z');
    await tester.enterText(find.byType(TextField).at(4), 'ana@mail.com');
    await tester.enterText(find.byType(TextField).at(5), '123456');

    await tester.tap(find.text('Registrarse'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(
      () => authService.signUp(
        email: 'ana@mail.com',
        password: '123456',
        data: {
          'nombre': 'Ana',
          'apellidos': 'Lopez',
          'telefono': '600123123',
          'dni': '12345678Z',
        },
      ),
    ).called(1);

    expect(find.text('Registro correcto. Ahora inicia sesión.'), findsOneWidget);
    expect(find.text('Iniciar Sesión'), findsOneWidget);
  });
}
