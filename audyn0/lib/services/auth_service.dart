import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _client = Supabase.instance.client;

  /// Returns a stream of `Session?` –  `null` means signed‑out.
  Stream<Session?> get onAuthState => _client.auth.onAuthStateChange
      .map((event) => event.session);

  bool get isSignedIn => _client.auth.currentUser != null;

  User? get user => _client.auth.currentUser;

  Future<void> signInWithEmail(String email) async {
    await _client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: 'io.supabase.flutter://callback',
    );
  }

  Future<void> signOut() async => _client.auth.signOut();
}

final authService = AuthService();
