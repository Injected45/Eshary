import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../../auth/presentation/auth_card.dart';
import '../data/trial_repository.dart';
import '../domain/trial_models.dart';
import 'phone_input.dart';

/// Follows the request with the secret token kept on this device (a phone
/// number alone shows nothing). While the request is pending it only waits;
/// once approved it asks for the WhatsApp code, and the trial starts the first
/// time the right code is entered.
class TrialFollowScreen extends ConsumerStatefulWidget {
  const TrialFollowScreen({super.key});

  @override
  ConsumerState<TrialFollowScreen> createState() => _TrialFollowScreenState();
}

class _TrialFollowScreenState extends ConsumerState<TrialFollowScreen> {
  final _code = TextEditingController();
  Timer? _poll;
  Timer? _tick;
  TrialFollow? _data;
  String? _token;
  String? _error;
  bool _busy = false;
  bool _loadFailed = false;
  int _wait = 0;
  int? _left;

  @override
  void initState() {
    super.initState();
    _token = ref.read(trialRepositoryProvider).savedToken;
    if (_token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/sign-in');
      });
      return;
    }
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _wait > 0) setState(() => _wait--);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final token = _token;
    if (token == null || _busy) return;
    try {
      final d = await ref.read(trialRepositoryProvider).follow(token);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loadFailed = false;
        if (d.resendWait > _wait) _wait = d.resendWait;
      });
    } on TrialRefused catch (e) {
      if (!mounted) return;
      if (e.code == 'not_found') {
        await ref.read(trialRepositoryProvider).forgetToken();
        if (mounted) context.go('/sign-in');
      } else {
        setState(() => _loadFailed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _requestCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wait = await ref.read(trialRepositoryProvider).requestCode(_token!);
      _code.clear();
      if (mounted) setState(() => _wait = wait);
    } on TrialRefused catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          if (e.wait != null) _wait = e.wait!;
        });
      }
    } catch (e, st) {
      AppLogger.error('trial.requestCode', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  Future<void> _activate() async {
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
      await ref.read(trialRepositoryProvider).activate(_token!, code);
      // The session that follows moves the router into the app.
    } on TrialRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _left = e.left;
        if (e.code == 'invalid_code') _code.clear();
      });
    } catch (e, st) {
      AppLogger.error('trial.activate', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fixPhone() async {
    var phone = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تصحيح رقم الهاتف'),
          content: PhoneInput(onChanged: (v) => phone = v),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(trialRepositoryProvider).updatePhone(_token!, phone);
      await _refresh();
    } catch (e, st) {
      AppLogger.error('trial.fixPhone', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return AuthCard(
      child: d == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadFailed)
                  const AuthError('تعذّر الاتصال بالخادم. تحقق من الإنترنت.')
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                TextButton(
                  onPressed: _refresh,
                  child: const Text('إعادة المحاولة'),
                ),
                TextButton(
                  onPressed: () => context.go('/sign-in'),
                  child: const Text('رجوع'),
                ),
              ],
            )
          : _content(d),
    );
  }

  Widget _content(TrialFollow d) {
    final (icon, color, title, body) = switch (d.status) {
      'pending_review' => (
          FontAwesomeIcons.hourglassHalf,
          AppColors.warning,
          'طلبك قيد المراجعة',
          'سنُعلمك فور اتخاذ القرار. يمكنك إغلاق التطبيق والعودة لاحقاً؛ يبقى طلبك محفوظاً.',
        ),
      'needs_info' => (
          FontAwesomeIcons.circleQuestion,
          AppColors.warning,
          'نحتاج معلومات إضافية',
          d.reviewNote ?? '',
        ),
      'approved' => (
          FontAwesomeIcons.circleCheck,
          AppColors.positive,
          'تمت الموافقة على طلبك',
          'مدة التجربة ${d.trialHours == 168 ? 'أسبوع' : '3 أيام'}، وتبدأ لحظة إدخال رمز واتساب لأول مرة.',
        ),
      'approval_expired' => (
          FontAwesomeIcons.clockRotateLeft,
          AppColors.negative,
          'انتهت صلاحية الموافقة',
          'مرّت 7 أيام على الموافقة دون تفعيل. تواصل مع الإدارة لتجديدها.',
        ),
      'rejected' => (
          FontAwesomeIcons.circleXmark,
          AppColors.negative,
          'لم تتم الموافقة على طلبك',
          d.reviewNote ?? '',
        ),
      _ => (
          FontAwesomeIcons.userCheck,
          AppColors.positive,
          'تم تفعيل حسابك',
          'ادخل بالرقم المسجّل ورمز واتساب.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(child: FaIcon(icon, size: 30, color: color)),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: AppColors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        if (body.isNotEmpty)
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textLow,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        const SizedBox(height: 10),
        Text(
          '${d.businessName} — ${d.managerName}\n${d.phoneMasked}',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(color: AppColors.textMid, fontSize: 12),
        ),
        if (d.status == 'pending_review' || d.status == 'needs_info') ...[
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              key: const ValueKey('trial-fix-phone'),
              onPressed: _fixPhone,
              child: const Text('تصحيح رقم الهاتف'),
            ),
          ),
        ],
        if (d.status == 'approved') ..._codeSection(d),
        if (d.status == 'activated') ...[
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => context.go('/phone-login'),
            child: const Text('دخول حسابي'),
          ),
        ],
        if (d.status == 'rejected') ...[
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () async {
              await ref.read(trialRepositoryProvider).forgetToken();
              if (mounted) context.go('/sign-in');
            },
            child: const Text('إغلاق'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          AuthError(
            _left == null ? _error! : '$_error (متبقي $_left محاولة)',
          ),
        ],
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => context.go('/demo'),
          child: const Text('شاهد جولة تعريفية بالتطبيق'),
        ),
        TextButton(
          onPressed: () => context.go('/sign-in'),
          child: const Text('رجوع'),
        ),
      ],
    );
  }

  List<Widget> _codeSection(TrialFollow d) {
    return [
      const SizedBox(height: 16),
      if (d.messageStatus == 'failed')
        const AuthError(
          'تعذّر إرسال كود واتساب، حاول مجددًا أو تواصل مع الدعم',
        )
      else if (d.messageStatus != null)
        const Text(
          'أُرسل رمز التحقق إلى واتساب. صلاحيته 5 دقائق ويُستخدم مرة واحدة.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textLow, fontSize: 12),
        ),
      const SizedBox(height: 12),
      CodeField(
        controller: _code,
        enabled: !_busy,
        onComplete: () {
          if (!_busy) _activate();
        },
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('trial-activate'),
        onPressed: _busy ? null : _activate,
        child: _busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Text('تفعيل التجربة'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const ValueKey('trial-resend'),
        onPressed: (_busy || _wait > 0) ? null : _requestCode,
        child: Text(
          _wait > 0
              ? 'إعادة الإرسال بعد $_wait ث'
              : (d.messageStatus == null ? 'إرسال الرمز' : 'إعادة إرسال الرمز'),
        ),
      ),
    ];
  }
}
