import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../auth/data/auth_repository.dart';
import '../../license/domain/license_status.dart';
import '../../license/presentation/license_provider.dart';

class ProfileDetailsScreen extends ConsumerWidget {
  const ProfileDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '—';
    final meta = user?.userMetadata ?? const {};

    // Try every known location Supabase might stash the avatar/name in.
    String? avatarUrl;
    String? fullName;
    for (final identity in user?.identities ?? const []) {
      final data = identity.identityData ?? const {};
      avatarUrl ??= (data['avatar_url'] ?? data['picture']) as String?;
      fullName ??=
          (data['full_name'] ?? data['name']) as String?;
    }
    avatarUrl ??= (meta['avatar_url'] ?? meta['picture']) as String?;
    fullName ??= (meta['full_name'] ?? meta['name']) as String?;

    // Temporary diagnostic — will appear in DevTools console / `flutter run`
    // output. Remove after confirming the keys.
    debugPrint('[profile] email=$email');
    debugPrint('[profile] userMetadata=$meta');
    debugPrint('[profile] identities=${user?.identities?.map((i) => {
              'provider': i.provider,
              'data': i.identityData,
            }).toList()}');
    debugPrint('[profile] resolved avatarUrl=$avatarUrl');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.55),
                        AppColors.positive.withValues(alpha: 0.40),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.25),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _initialsAvatar(email, fullName),
                          )
                        : _initialsAvatar(email, fullName),
                  ),
                ),
                if (fullName != null && fullName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    fullName,
                    style: const TextStyle(
                      color: AppColors.textHigh,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'البريد الإلكتروني',
                  style: TextStyle(color: AppColors.textLow, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _PlanCard(),
          const SizedBox(height: 16),
          const GlassCard(
            padding: EdgeInsets.all(18),
            child: _ChangePasswordSection(),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const FaIcon(
              FontAwesomeIcons.rightFromBracket,
              size: 16,
            ),
            label: const Text('تسجيل الخروج'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.negative,
              side: BorderSide(
                color: AppColors.negative.withValues(alpha: 0.6),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(String email, String? fullName) {
    final source = (fullName?.trim().isNotEmpty ?? false)
        ? fullName!.trim()
        : email.trim();
    final initial = source.isEmpty ? '?' : source.characters.first.toUpperCase();
    return Container(
      color: AppColors.bgPanel,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'تأكيد تسجيل الخروج',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'هل أنت متأكد من تسجيل الخروج؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textLow,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(false),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.negative,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(true),
                      child: const Text('خروج'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(authRepositoryProvider).signOut();
    }
  }
}

/// Reads `licenseStatusProvider` and renders the user's current plan badge
/// + secondary trial-cutoff line. Replaces the previous hardcoded
/// "مجاني" label that ignored real license state.
class _PlanCard extends ConsumerWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLicense = ref.watch(licenseStatusProvider);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.crown,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 10),
              const Text(
                'الخطة الحالية',
                style: TextStyle(
                  color: AppColors.textHigh,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              asyncLicense.when(
                loading: () => const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => _badge(label: '...', color: AppColors.textLow),
                data: (s) {
                  final (label, color) = _planStyle(s);
                  return _badge(label: label, color: color);
                },
              ),
            ],
          ),
          // Secondary line: trial cutoff or admin tag.
          asyncLicense.maybeWhen(
            orElse: SizedBox.shrink,
            data: (s) {
              final lines = <String>[];
              if (s.status == 'trial' && s.isValid && s.trialEndsAt != null) {
                lines.add('حتى ${dateOnly.format(s.trialEndsAt!.toLocal())}');
              }
              if (s.isAdmin) lines.add('صلاحيات مشرف');
              if (lines.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  lines.join(' · '),
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _badge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.50)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  (String, Color) _planStyle(LicenseStatus s) {
    switch (s.status) {
      case 'active':
        if (s.licenseType == 'lifetime') {
          return ('خطة دائمة', AppColors.positive);
        }
        return ('خطة مفعّلة', AppColors.positive);
      case 'trial':
        return s.isValid
            ? ('فترة تجريبية (3 أيام)', AppColors.warning)
            : ('انتهت الفترة التجريبية', AppColors.negative);
      case 'expired':
        return ('انتهت الفترة التجريبية', AppColors.negative);
      case 'blocked':
        return ('محظور', AppColors.negative);
      case 'pending':
      default:
        return ('بانتظار التفعيل', AppColors.warning);
    }
  }
}

class _ChangePasswordSection extends ConsumerStatefulWidget {
  const _ChangePasswordSection();

  @override
  ConsumerState<_ChangePasswordSection> createState() =>
      _ChangePasswordSectionState();
}

class _ChangePasswordSectionState
    extends ConsumerState<_ChangePasswordSection> {
  final _newPass = TextEditingController();
  final _confirmPass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newPass.dispose();
    _confirmPass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final p1 = _newPass.text;
    final p2 = _confirmPass.text;
    if (p1.isEmpty || p2.isEmpty) {
      setState(() => _error = 'يرجى تعبئة كلتا الخانتين');
      return;
    }
    if (p1.length < 6) {
      setState(
          () => _error = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(p1);
      if (!mounted) return;
      _newPass.clear();
      _confirmPass.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.positive.withValues(alpha: 0.85),
          content: const Text(
            'تم تحديث كلمة المرور',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
          ),
        ),
      );
    } catch (e, st) {
      AppLogger.error('profile.changePassword', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.negative.withValues(alpha: 0.85),
          content: Text(friendlyError(e),
              style: const TextStyle(color: Colors.white)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.positive],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Expanded(
                child: Text(
                  'تغيير كلمة المرور',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textHigh,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        TextField(
          controller: _newPass,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة المرور الجديدة',
            prefixIcon: Icon(Icons.lock_outline, color: AppColors.textLow),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPass,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'تأكيد كلمة المرور الجديدة',
            prefixIcon: Icon(Icons.lock_outline, color: AppColors.textLow),
          ),
        ),
        if (_error != null) const SizedBox(height: 12),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.negative.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.negative.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.negative),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: const FaIcon(FontAwesomeIcons.key, size: 14),
          label: Text(_busy ? '...' : 'تحديث كلمة المرور'),
        ),
      ],
    );
  }
}
