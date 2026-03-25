import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotaxi/data/services/auth_service.dart';
import 'package:gotaxi/presentation/screens/auth/auth_screen.dart';

class _NoopAuthService implements AuthService {
  @override
  Future<void> signIn({required String email, required String password}) async {}

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) async {}
}

void main() {
  testWidgets('AuthScreen renderiza en modo login', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(authService: _NoopAuthService())),
    );

    expect(find.text('Iniciar Sesión'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
