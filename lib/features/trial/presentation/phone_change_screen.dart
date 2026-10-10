import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/trial_repository.dart';
import '../domain/trial_models.dart';
import 'phone_input.dart';
import 'subscription_screen.dart' show formatTripoli;

final phoneChangeStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(trialRepositoryProvider).phoneChangeStatus();
});

/// "تغيير رقم واتساب": the subscriber types the new number, a code goes to
/// THAT number, and then an administrator approves. One change per 30 days;
/// the old number is warned. Changing numbers never earns another trial.
class PhoneChangeScreen extends ConsumerStatefulWidget {
  const PhoneChangeScreen({super.key});

  @override
  ConsumerState<PhoneChangeScreen> createState() => _PhoneChangeScreenState();
}

class _PhoneChangeScreenState extends ConsumerState<PhoneChangeScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  String _phone = '';
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

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
      _left = null;
    });
    try {
      await job();
      ref.invalidate(phoneChangeStatusProvider);
    } on TrialRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _left = e.left;
      });
      if (e.wait != null) _startWait(e.wait!);
    } catch (e, st) {
      AppLogger.error('phoneChange', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(phoneChangeStatusProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: const Text('تغيير رقم واتساب')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: async.when(
                skipLoadingOnReload: true,
                skipError: true,
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (e, _) => Text(friendlyError(e)),
                data: _body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> st) {
    final status = st['status'] as String?;
    final next = st['nextChangeAfter'] == null
        ? null
        : DateTime.parse(st['nextChangeAfter'] as String);
    final repo = ref.read(trialRepositoryProvider);
    final children = <Widget>[
      Text(
        'الرقم الحالي: ${st['phone'] ?? ''}',
        textDirection: TextDirection.rtl,
        style: const TextStyle(color: AppColors.textHigh),
      ),
      const SizedBox(height: 12),
    ];

    if (status == 'pending_verify') {
      children.addAll([
        Text(
          'أُرسل رمز إلى الرقم الجديد ${st['newPhone'] ?? ''}. أدخله لتأكيد أنه رقمك.',
          style: const TextStyle(color: AppColors.textMid, height: 1.6),
        ),
        const SizedBox(height: 12),
        CodeField(
          controller: _code,
          enabled: !_busy,
          onComplete: () => _run(() async {
            await repo.phoneChangeVerify(_code.text.trim());
          }),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const ValueKey('change-verify'),
          onPressed: _busy
              ? null
              : () => _run(() => repo.phoneChangeVerify(_code.text.trim())),
          child: const Text('تأكيد الرقم الجديد'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: (_busy || _wait > 0)
              ? null
              : () => _run(() async {
                    _startWait(await repo.phoneChangeResend());
                  }),
          child: Text(
            _wait > 0 ? 'إعادة الإرسال بعد $_wait ث' : 'إعادة إرسال الرمز',
          ),
        ),
        TextButton(
          onPressed: _busy ? null : () => _run(repo.phoneChangeCancel),
          child: const Text('إلغاء الطلب'),
        ),
      ]);
    } else if (status == 'pending_admin') {
      children.addAll([
        Text(
          'تم تأكيد الرقم الجديد ${st['newPhone'] ?? ''}. بانتظار موافقة الإدارة؛ يبقى رقمك الحالي ساري المفعول حتى ذلك الحين.',
          style: const TextStyle(color: AppColors.textMid, height: 1.6),
        ),
        TextButton(
          onPressed: _busy ? null : () => _run(repo.phoneChangeCancel),
          child: const Text('إلغاء الطلب'),
        ),
      ]);
    } else {
      if (status == 'rejected') {
        children.add(
          Text(
            'رُفض الطلب السابق${(st['note'] as String?)?.isNotEmpty == true ? ': ${st['note']}' : ''}',
            style: const TextStyle(color: AppColors.negative),
          ),
        );
        children.add(const SizedBox(height: 8));
      }
      if (next != null) {
        children.add(
          Text(
            'التغيير التالي متاح بعد ${formatTripoli(next)}',
            style: const TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
        );
        children.add(const SizedBox(height: 8));
      }
      children.addAll([
        const Text(
          'اكتب الرقم الجديد. سيصله رمز على واتساب، ثم تراجع الإدارة الطلب. يُسمح بتغيير واحد كل 30 يوماً، ويصل تنبيه إلى رقمك القديم.',
          style: TextStyle(color: AppColors.textMid, height: 1.6, fontSize: 13),
        ),
        const SizedBox(height: 12),
        PhoneInput(enabled: !_busy, onChanged: (v) => _phone = v),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('change-start'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    _startWait(await repo.phoneChangeStart(_phone));
                  }),
          child: const Text('إرسال رمز إلى الرقم الجديد'),
        ),
      ]);
    }

    if (_error != null) {
      children.add(const SizedBox(height: 12));
      children.add(
        Text(
          _left == null ? _error! : '$_error (متبقي $_left محاولة)',
          style: const TextStyle(color: AppColors.negative),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
