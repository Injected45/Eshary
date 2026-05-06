import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/auth_repository.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) context.go('/');
    } catch (e, st) {
      AppLogger.error('auth.signIn.submit', e, st);
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await ref.read(authRepositoryProvider).signInWithGoogle();
      if (ok && mounted) context.go('/');
    } catch (e, st) {
      AppLogger.error('auth.signIn.google', e, st);
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.jpeg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: GlassCard(
                padding: const EdgeInsets.all(28),
                child: Column(
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
                            AppColors.accent.withValues(alpha: 0.30),
                            AppColors.positive.withValues(alpha: 0.20),
                          ],
                        ),
                        border: Border.all(color: AppColors.glassBorderStrong),
                      ),
                      child: const FaIcon(
                        FontAwesomeIcons.lock,
                        size: 22,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'مرحباً بعودتك إلى تطبيق إشاري',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textHigh,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'تابع حوالاتك المالية، راجع عملياتك، وأدِر حساباتك من مكان واحد بكل أمان ووضوح.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textLow,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        prefixIcon: Icon(Icons.alternate_email,
                            color: AppColors.textLow),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: Icon(Icons.lock_outline,
                            color: AppColors.textLow),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
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
                    if (_error != null) const SizedBox(height: 12),
                    FilledButton(
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
                          : const Text('دخول'),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: AppColors.glassBorder,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'أو',
                          style: TextStyle(
                            color: AppColors.textLow,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: AppColors.glassBorder,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _googleSignIn,
                      icon: const FaIcon(
                        FontAwesomeIcons.google,
                        size: 16,
                        color: AppColors.textHigh,
                      ),
                      label: const Text('متابعة بـ Google'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textHigh,
                        side: const BorderSide(
                          color: AppColors.glassBorderStrong,
                        ),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => context.go('/sign-up'),
                      child: const Text('إنشاء حساب جديد'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
          ),
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'شركة الرحالة للبرمجيات . جميع الحقوق محفوظة 2026 ©',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
