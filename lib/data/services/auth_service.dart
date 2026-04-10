import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

abstract class AuthService {
  Future<void> signIn({required String email, required String password});

  Future<void> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  });

  Future<void> resetPassword({required String email});
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({GoTrueClient? authClient})
    : _authClient = authClient ?? Supabase.instance.client.auth;

  final GoTrueClient _authClient;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _authClient.signInWithPassword(email: email, password: password);
    final user = _authClient.currentUser;
    if (user != null) {
      await NotificationService().login(user.id);
    }
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) async {
    await _authClient.signUp(email: email, password: password, data: data);
    final user = _authClient.currentUser;
    if (user != null) {
      await NotificationService().login(user.id);
    }
  }

  @override
  Future<void> resetPassword({required String email}) {
    return _authClient.resetPasswordForEmail(email);
  }
}
