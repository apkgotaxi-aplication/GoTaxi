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
  SupabaseAuthService({
    GoTrueClient? authClient,
    SupabaseClient? supabaseClient,
  }) : _authClient = authClient ?? Supabase.instance.client.auth,
       _supabase = supabaseClient ?? Supabase.instance.client;

  final GoTrueClient _authClient;
  final SupabaseClient _supabase;

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _authClient.signInWithPassword(email: email, password: password);
    final user = _authClient.currentUser;
    if (user != null) {
      // Validar que taxistas desactivados no puedan iniciar sesión (soft delete)
      final taxista = await _supabase
          .from('taxistas')
          .select('activo')
          .eq('id', user.id)
          .maybeSingle();

      if (taxista != null && taxista['activo'] == false) {
        // Desconectar usuario si está desactivado
        await _authClient.signOut();
        throw Exception(
          'Tu cuenta ha sido desactivada. Contacta al administrador para más información.',
        );
      }

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
