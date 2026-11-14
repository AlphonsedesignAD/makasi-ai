import 'package:supabase_flutter/supabase_flutter.dart';

/// Authentification et mémoire cloud, via le même projet Supabase que le site.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  String get displayName {
    final user = currentUser;
    if (user == null) return '';
    final meta = user.userMetadata;
    final name = (meta?['display_name'] ?? meta?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final email = user.email ?? '';
    return email.contains('@') ? email.split('@').first : email;
  }

  String get email => currentUser?.email ?? '';

  Future<AuthOutcome> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': name.trim()},
    );
    return AuthOutcome(
      user: response.user,
      needsConfirmation: response.session == null,
    );
  }

  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return AuthOutcome(user: response.user, needsConfirmation: false);
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // La session locale est nettoyée même hors ligne.
    }
  }

  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());

  Future<void> updateDisplayName(String name) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({'display_name': name.trim()}).eq('id', user.id);
    await _client.auth.updateUser(
      UserAttributes(data: {'display_name': name.trim()}),
    );
  }
}

class AuthOutcome {
  AuthOutcome({required this.user, required this.needsConfirmation});

  final User? user;
  final bool needsConfirmation;
}
