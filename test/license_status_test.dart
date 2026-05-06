import 'package:eshary/features/license/domain/license_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseStatus.fromJson', () {
    test('pending', () {
      final s = LicenseStatus.fromJson({
        'status': 'pending',
        'license_type': null,
        'trial_ends_at': null,
        'is_valid': false,
        'is_admin': false,
      });
      expect(s.status, 'pending');
      expect(s.licenseType, isNull);
      expect(s.trialEndsAt, isNull);
      expect(s.isValid, isFalse);
      expect(s.isPending, isTrue);
      expect(s.isBlocked, isFalse);
      expect(s.isAdmin, isFalse);
    });

    test('admin flag round-trips', () {
      final s = LicenseStatus.fromJson({
        'status': 'active',
        'license_type': 'lifetime',
        'trial_ends_at': null,
        'is_valid': true,
        'is_admin': true,
      });
      expect(s.isAdmin, isTrue);
      expect(s.toJson()['is_admin'], isTrue);
    });

    test('missing is_admin defaults to false', () {
      final s = LicenseStatus.fromJson({
        'status': 'active',
        'license_type': 'lifetime',
        'trial_ends_at': null,
        'is_valid': true,
      });
      expect(s.isAdmin, isFalse);
    });

    test('trial — not yet expired', () {
      final ends = DateTime.now().toUtc().add(const Duration(days: 2));
      final s = LicenseStatus.fromJson({
        'status': 'trial',
        'license_type': 'trial',
        'trial_ends_at': ends.toIso8601String(),
        'is_valid': true,
      });
      expect(s.status, 'trial');
      expect(s.licenseType, 'trial');
      expect(s.trialEndsAt!.isAfter(DateTime.now().toUtc()), isTrue);
      expect(s.isValid, isTrue);
      expect(s.isExpiredTrial, isFalse);
    });

    test('trial — server reports expired (is_valid=false)', () {
      final s = LicenseStatus.fromJson({
        'status': 'trial',
        'license_type': 'trial',
        'trial_ends_at':
            DateTime.now().toUtc().subtract(const Duration(hours: 1))
                .toIso8601String(),
        'is_valid': false,
      });
      expect(s.isValid, isFalse);
      expect(s.isExpiredTrial, isTrue);
    });

    test('active / lifetime', () {
      final s = LicenseStatus.fromJson({
        'status': 'active',
        'license_type': 'lifetime',
        'trial_ends_at': null,
        'is_valid': true,
      });
      expect(s.status, 'active');
      expect(s.licenseType, 'lifetime');
      expect(s.trialEndsAt, isNull);
      expect(s.isValid, isTrue);
    });

    test('expired', () {
      final s = LicenseStatus.fromJson({
        'status': 'expired',
        'license_type': 'trial',
        'trial_ends_at':
            DateTime.now().toUtc().subtract(const Duration(days: 1))
                .toIso8601String(),
        'is_valid': false,
      });
      expect(s.status, 'expired');
      expect(s.isValid, isFalse);
      expect(s.isExpiredTrial, isTrue);
    });

    test('blocked', () {
      final s = LicenseStatus.fromJson({
        'status': 'blocked',
        'license_type': null,
        'trial_ends_at': null,
        'is_valid': false,
      });
      expect(s.isValid, isFalse);
      expect(s.isBlocked, isTrue);
    });

    test('missing is_valid defaults to false', () {
      final s = LicenseStatus.fromJson({
        'status': 'pending',
        'license_type': null,
        'trial_ends_at': null,
      });
      expect(s.isValid, isFalse);
    });
  });

  group('LicenseStatus.missing', () {
    test('treats user as gated', () {
      const s = LicenseStatus.missing;
      expect(s.status, 'pending');
      expect(s.isValid, isFalse);
      expect(s.isPending, isTrue);
    });
  });
}
