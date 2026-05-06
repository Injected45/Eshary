import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_provider.dart';
import '../data/license_repository.dart';
import '../domain/license_status.dart';

/// Authoritative license state for the signed-in user. Re-fetches whenever
/// [currentUserIdProvider] changes (sign-in / sign-out). UI can call
/// `ref.invalidate(licenseStatusProvider)` to force a refresh — used by the
/// pending-activation screen's manual button and its 30-second poll.
final licenseStatusProvider = FutureProvider<LicenseStatus>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return LicenseStatus.missing;
  return ref.watch(licenseRepositoryProvider).fetch();
});
