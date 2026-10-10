import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../license/data/license_repository.dart';

class AuthRepository {
  AuthRepository(this._client, this._licenseRepo);

  final SupabaseClient _client;
  final LicenseRepository _licenseRepo;

  Future<void> signIn({required String email, required String password}) async {
    // Wipe any cached license from a previous user/session before signing
    // in — guards against a stale 'blocked' cached row triggering the
    // force-logout listener as the new session lights up.
    await _licenseRepo.clearCache();
    await _client.auth.signInWithPassword(email: email, password: password);
    await ensureProfile();
  }

  Future<void> signUp({required String email, required String password}) async {
    await _licenseRepo.clearCache();
    await _client.auth.signUp(email: email, password: password);
    await ensureProfile();
  }

  Future<void> signOut() async {
    await _licenseRepo.clearCache();
    await _client.auth.signOut();
  }

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
  return AuthRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(licenseRepositoryProvider),
  );
});
