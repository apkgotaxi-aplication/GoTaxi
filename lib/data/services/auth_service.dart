import 'package:supabase_flutter/supabase_flutter.dart';

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
  Future<void> signIn({required String email, required String password}) {
    return _authClient.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> data,
  }) {
    return _authClient.signUp(email: email, password: password, data: data);
  }

  @override
  Future<void> resetPassword({required String email}) {
    return _authClient.resetPasswordForEmail(email);
  }
}
