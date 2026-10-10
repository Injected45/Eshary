import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../data/member_auth_repository.dart';
import 'auth_card.dart';
import 'phone_code_step.dart';

/// "دخول برقم الهاتف": a member whose phone is already linked (they came in with
/// an invitation) signs in with that phone number and the code WhatsApp sends.
class PhoneLoginScreen extends ConsumerWidget {
  const PhoneLoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(memberAuthRepositoryProvider);
    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(
            child: FaIcon(
              FontAwesomeIcons.whatsapp,
              size: 30,
              color: AppColors.positive,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'دخول برقم الهاتف',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'اكتب رقمك المسجّل، فيصلك رمز التحقق على واتساب.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textLow,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          PhoneCodeStep(
            request: repo.phoneLoginRequest,
            confirm: repo.phoneLogin,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/sign-in'),
            child: const Text('رجوع'),
          ),
        ],
      ),
    );
  }
}
