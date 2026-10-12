import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/cache.dart';
import '../../license/data/license_repository.dart';
import '../../trial/domain/trial_models.dart';
import '../../trial/presentation/phone_input.dart' show CodeField;
import '../data/account_deletion_repository.dart';
import 'privacy_policy_screen.dart' show supportContactText;

/// "حذف حسابي": removes the account and everything it owns, for good. A code
/// sent by WhatsApp to the account's registered phone confirms that the owner
/// (not someone holding an unlocked phone) is asking.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  bool _sent = false;
  bool _busy = false;
  String? _error;
  int? _left;
  int _wait = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startWait(int s) {
    _timer?.cancel();
    setState(() => _wait = s);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _left = null;
    });
    try {
      final wait =
          await ref.read(accountDeletionRepositoryProvider).requestCode();
      if (!mounted) return;
      setState(() {
        _sent = true;
        _code.clear();
      });
      _startWait(wait);
    } on TrialRefused catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
      if (e.wait != null) _startWait(e.wait!);
    } catch (e, st) {
      AppLogger.error('account.deleteRequest', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'أدخل رمز واتساب المكوّن من 6 أرقام.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _left = null;
    });
    try {
      await ref.read(accountDeletionRepositoryProvider).confirm(code);
      // The account no longer exists: clear what this phone kept and leave.
      await ref.read(licenseRepositoryProvider).clearCache();
      await ref.read(jsonCacheProvider).clearUserData();
      try {
        await ref.read(supabaseClientProvider).auth.signOut();
      } catch (_) {
        // the session is already gone with the account
      }
      if (mounted) context.go('/sign-in');
    } on TrialRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _left = e.left;
        if (e.code == 'invalid_code') _code.clear();
      });
    } catch (e, st) {
      AppLogger.error('account.deleteConfirm', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: const Text('حذف حسابي')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: FaIcon(
                      FontAwesomeIcons.triangleExclamation,
                      size: 30,
                      color: AppColors.negative,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'حذف الحساب نهائي',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textHigh,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'سيُحذف حسابك وكل ما يملكه: الشركات والحسابات والعملاء والمستفيدون وكل العمليات '
                    'والموظفون والفروع. لا يمكن التراجع ولا استرجاع البيانات. '
                    'نوصيك بتنزيل تقاريرك قبل الحذف.',
                    style: TextStyle(
                      color: AppColors.textMid,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'للتأكد أنك صاحب الحساب، سيصل رمز على واتساب إلى الرقم المسجّل. '
                    'للمساعدة: ${supportContactText()}',
                    style: const TextStyle(
                      color: AppColors.textLow,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_sent)
                    FilledButton(
                      key: const ValueKey('delete-send-code'),
                      onPressed: _busy ? null : _send,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.negative,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('إرسال رمز التأكيد'),
                    )
                  else ...[
                    CodeField(
                      controller: _code,
                      enabled: !_busy,
                      onComplete: () {
                        if (!_busy) _confirm();
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const ValueKey('delete-confirm'),
                      onPressed: _busy ? null : _confirm,
                      icon: const FaIcon(FontAwesomeIcons.trashCan, size: 14),
                      label: const Text('حذف حسابي نهائياً'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.negative,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: (_busy || _wait > 0) ? null : _send,
                      child: Text(
                        _wait > 0
                            ? 'إعادة الإرسال بعد $_wait ث'
                            : 'إعادة إرسال الرمز',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _left == null ? _error! : '$_error (متبقي $_left محاولة)',
                      style: const TextStyle(color: AppColors.negative),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => context.pop(),
                    child: const Text('تراجع'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
