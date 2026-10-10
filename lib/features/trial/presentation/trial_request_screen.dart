import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../../auth/presentation/auth_card.dart';
import '../data/trial_repository.dart';
import 'phone_input.dart';

/// "ابدأ تجربتك": the trial request. No account is created here; the request is
/// recorded and the administrator decides. The phone is NOT verified yet; that
/// happens with the WhatsApp code after approval.
class TrialRequestScreen extends ConsumerStatefulWidget {
  const TrialRequestScreen({super.key});

  @override
  ConsumerState<TrialRequestScreen> createState() => _TrialRequestScreenState();
}

class _TrialRequestScreenState extends ConsumerState<TrialRequestScreen> {
  final _manager = TextEditingController();
  final _business = TextEditingController();
  String _phone = '';
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _manager.dispose();
    _business.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final manager = _manager.text.trim();
    final business = _business.text.trim();
    if (manager.length < 2 || business.length < 2) {
      setState(() => _error = 'اكتب اسم المدير واسم النشاط.');
      return;
    }
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(_phone)) {
      setState(() => _error = 'اكتب رقم الهاتف مع اختيار رمز الدولة.');
      return;
    }
    if (!_consent) {
      setState(() => _error = 'يجب الموافقة على التواصل عبر واتساب.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(trialRepositoryProvider).submit(
            manager: manager,
            business: business,
            phone: _phone,
            consent: _consent,
          );
      if (mounted) context.go('/trial-follow');
    } catch (e, st) {
      AppLogger.error('trial.submit', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(
            child: FaIcon(
              FontAwesomeIcons.rocket,
              size: 28,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ابدأ تجربتك',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'أرسل طلبك وستراجعه الإدارة. لا يُنشأ حساب ولا تبدأ التجربة قبل الموافقة وتأكيد رقمك برمز واتساب.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textLow,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('trial-manager'),
            controller: _manager,
            enabled: !_busy,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'اسم المدير',
              counterText: '',
              prefixIcon: Icon(Icons.person, color: AppColors.textLow),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('trial-business'),
            controller: _business,
            enabled: !_busy,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'اسم الشركة أو النشاط',
              counterText: '',
              prefixIcon: Icon(Icons.business, color: AppColors.textLow),
            ),
          ),
          const SizedBox(height: 12),
          PhoneInput(
            enabled: !_busy,
            onChanged: (v) => _phone = v,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('trial-consent'),
            value: _consent,
            onChanged:
                _busy ? null : (v) => setState(() => _consent = v == true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'أوافق على أن تتواصل معي الإدارة عبر واتساب بخصوص طلبي.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textMid),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            AuthError(_error!),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('trial-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text('إرسال الطلب'),
          ),
          TextButton(
            onPressed: _busy ? null : () => context.go('/sign-in'),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}
