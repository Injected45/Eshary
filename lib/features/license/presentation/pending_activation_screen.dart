import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/license_status.dart';
import 'license_provider.dart';

class PendingActivationScreen extends ConsumerStatefulWidget {
  const PendingActivationScreen({super.key});

  @override
  ConsumerState<PendingActivationScreen> createState() =>
      _PendingActivationScreenState();
}

class _PendingActivationScreenState
    extends ConsumerState<PendingActivationScreen> {
  Timer? _poll;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    // Auto-refresh while the screen is mounted so admin activation in
    // Supabase Studio is reflected without the user mashing the button.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(licenseStatusProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (e, st) {
      AppLogger.error('license.signOut', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentSessionProvider)?.user.email ?? '';
    final asyncStatus = ref.watch(licenseStatusProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: GlassCard(
                padding: const EdgeInsets.all(28),
                child: asyncStatus.when(
                  data: (s) => _buildContent(context, s, email),
                  loading: () => _buildLoading(),
                  error: (e, _) => _buildError(e),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'تعذّر التحقق من حالة الحساب',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          friendlyError(error),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textLow),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => ref.invalidate(licenseStatusProvider),
          child: const Text('إعادة المحاولة'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _signingOut ? null : _signOut,
          child: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, LicenseStatus s, String email) {
    final badge = _StatusBadge(status: s);
    final headline = _headlineFor(s);
    final body = _bodyFor(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.warning.withValues(alpha: 0.30),
                AppColors.accent.withValues(alpha: 0.20),
              ],
            ),
            border: Border.all(color: AppColors.glassBorderStrong),
          ),
          child: const FaIcon(
            FontAwesomeIcons.hourglassHalf,
            size: 22,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textHigh,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textLow, height: 1.5),
        ),
        const SizedBox(height: 18),
        Align(alignment: Alignment.center, child: badge),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 14),
          GlassPanel(
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.envelope,
                  size: 14,
                  color: AppColors.textLow,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    email,
                    textAlign: TextAlign.start,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textHigh,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (s.status == 'trial' && s.trialEndsAt != null) ...[
          const SizedBox(height: 10),
          GlassPanel(
            child: Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.clock,
                  size: 14,
                  color: AppColors.textLow,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تنتهي الفترة التجريبية: ${_formatDate(s.trialEndsAt!)}',
                    style: const TextStyle(
                      color: AppColors.textHigh,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => ref.invalidate(licenseStatusProvider),
          icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
          label: const Text('تحديث الحالة'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _signingOut ? null : _signOut,
          child: _signingOut
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تسجيل الخروج'),
        ),
      ],
    );
  }

  String _headlineFor(LicenseStatus s) {
    switch (s.status) {
      case 'blocked':
        return 'تم حظر الحساب';
      case 'expired':
        return 'انتهت الفترة التجريبية';
      case 'trial':
        // status='trial' but isValid=false means trial_ends_at <= now()
        return s.isValid ? 'فترة تجريبية' : 'انتهت الفترة التجريبية';
      case 'pending':
      default:
        return 'بانتظار التفعيل';
    }
  }

  String _bodyFor(LicenseStatus s) {
    switch (s.status) {
      case 'blocked':
        return 'تواصل مع الإدارة لإعادة تفعيل الحساب.';
      case 'expired':
        return 'انتهت الفترة التجريبية. تواصل مع الإدارة للترقية.';
      case 'trial':
        if (!s.isValid) {
          return 'انتهت الفترة التجريبية. تواصل مع الإدارة للترقية.';
        }
        return 'حسابك في فترة تجريبية فعّالة.';
      case 'pending':
      default:
        return 'تم استلام تسجيلك بنجاح. الإدارة ستقوم بتفعيل حسابك قريبًا.';
    }
  }

  String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final LicenseStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (String, Color) _styleFor(LicenseStatus s) {
    switch (s.status) {
      case 'blocked':
        return ('محظور', AppColors.negative);
      case 'expired':
        return ('انتهت الفترة التجريبية', AppColors.negative);
      case 'trial':
        return s.isValid
            ? ('فترة تجريبية', AppColors.warning)
            : ('انتهت الفترة التجريبية', AppColors.negative);
      case 'pending':
      default:
        return ('بانتظار التفعيل', AppColors.warning);
    }
  }
}
