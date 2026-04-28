import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Web client ID from Google Cloud Console — required by google_sign_in
  /// as `serverClientId` so the ID token's audience matches what Supabase
  /// validates against. The Android client ID configured in GCC stays
  /// in the dashboard; the SDK doesn't take it as a parameter.
  static const _googleWebClientId =
      '711418304779-tt2dh9equsbqu6ckrnlgv8m95s6ca0q6.apps.googleusercontent.com';

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    await ensureProfile();
  }

  Future<void> signUp({required String email, required String password}) async {
    await _client.auth.signUp(email: email, password: password);
    await ensureProfile();
  }

  /// Returns true if a session was established. Returns false if the user
  /// cancelled the Google account picker — the caller should treat that as
  /// a non-error and stop showing the busy spinner.
  Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
      await _client.auth.signInWithOAuth(OAuthProvider.google);
      // Web uses redirect flow — control returns to the app via URL hash;
      // the auth state listener picks up the new session and the router
      // redirects automatically. Treat as success here.
      return true;
    }

    final googleSignIn = GoogleSignIn(serverClientId: _googleWebClientId);
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return false; // user cancelled the picker

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;
    if (idToken == null) {
      throw const AuthException('لم يتم استلام رمز Google');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    await ensureProfile();
    return true;
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Belt-and-suspenders insert into `profiles` for the current user. The
  /// `0005_auth_triggers.sql` trigger handles this server-side, but this
  /// keeps the app working even if the migration hasn't been applied yet
  /// or for users created before the trigger existed.
  Future<void> ensureProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('profiles').upsert(
        {'id': user.id},
        onConflict: 'id',
      );
    } catch (_) {
      // Swallow: if the table doesn't exist yet, the FK will tell us soon.
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
