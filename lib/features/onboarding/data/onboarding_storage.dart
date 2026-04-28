import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/cache.dart';

const _kOnboardingDoneKey = 'onboarding_completed_v1';

class OnboardingStorage {
  OnboardingStorage(this._prefs);
  final SharedPreferences _prefs;

  bool isCompleted() => _prefs.getBool(_kOnboardingDoneKey) ?? false;

  Future<void> markCompleted() async {
    await _prefs.setBool(_kOnboardingDoneKey, true);
  }
}

final onboardingStorageProvider = Provider<OnboardingStorage>((ref) {
  return OnboardingStorage(ref.watch(sharedPreferencesProvider));
});
