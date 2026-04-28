import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

final currentSessionProvider = Provider<Session?>((ref) {
  final asyncState = ref.watch(authStateChangesProvider);
  return asyncState.maybeWhen(
    data: (s) => s.session,
    orElse: () => ref.watch(supabaseClientProvider).auth.currentSession,
  );
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentSessionProvider)?.user.id;
});
