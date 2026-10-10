import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../auth/presentation/auth_card.dart';

/// A short tour of what the app does, with invented data only. It reads and
/// writes nothing: no account, no server call, no real figure.
class DemoTourScreen extends StatefulWidget {
  const DemoTourScreen({super.key});

  @override
  State<DemoTourScreen> createState() => _DemoTourScreenState();
}

class _DemoTourScreenState extends State<DemoTourScreen> {
  static const _pages = <(IconData, String, String, List<(String, String)>)>[
    (
      FontAwesomeIcons.paperPlane,
      'تحويل صادر',
      'تسجّل التحويل برقم مرجعي تلقائي ورسالة جاهزة للمستلم، ويُخصم الرصيد لحظة الحفظ.',
      [
        ('المرسل', 'عميل تجريبي'),
        ('المبلغ', '1,000.00 USD'),
        ('الرصيد بعد العملية', '24,000.00 USD'),
      ],
    ),
    (
      FontAwesomeIcons.dollarSign,
      'شراء دولار',
      'تسجّل شراء الدولار من العميل بسعر الصرف، ويُضاف إلى الرصيد فوراً.',
      [
        ('المبلغ', '2,500.00 USD'),
        ('سعر الصرف', '5.2000'),
        ('المقابل', '13,000.00 د.ل'),
      ],
    ),
    (
      FontAwesomeIcons.folderOpen,
      'العمليات والتقارير',
      'سجل دائم لكل العمليات، وكشف حساب وتقارير حركة وتصدير PDF.',
      [
        ('عمليات اليوم', '12'),
        ('الإجمالي', '31,500.00 USD'),
        ('الملغاة', '1 (بسبب موثّق)'),
      ],
    ),
  ];

  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final (icon, title, text, rows) = _pages[_i];
    final last = _i == _pages.length - 1;
    return AuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            alignment: Alignment.center,
            child: const Text(
              'بيانات تجريبية للعرض فقط',
              style: TextStyle(color: AppColors.warning, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: FaIcon(icon, size: 30, color: AppColors.accent)),
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
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textLow,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      k,
                      style: const TextStyle(color: AppColors.textLow),
                    ),
                  ),
                  Text(
                    v,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: AppColors.textHigh,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var n = 0; n < _pages.length; n++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: n == _i ? AppColors.accent : AppColors.textDim,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('demo-next'),
            onPressed: () =>
                last ? context.go('/sign-in') : setState(() => _i++),
            child: Text(last ? 'إنهاء' : 'التالي'),
          ),
          if (!last)
            TextButton(
              onPressed: () => context.go('/sign-in'),
              child: const Text('تخطّي'),
            ),
        ],
      ),
    );
  }
}
