import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';

/// Shown once after the admin creates a sub_user (or regenerates a code).
/// The plain code lives only in the in-memory state of this dialog; once
/// the dialog is dismissed the only way to view it again is to regenerate.
class CodeDisplayDialog extends StatelessWidget {
  const CodeDisplayDialog({
    super.key,
    required this.employeeName,
    required this.phoneNumber,
    required this.code,
    this.isRegenerated = false,
  });

  final String employeeName;
  final String phoneNumber;
  final String code;
  final bool isRegenerated;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.positive.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.positive,
                      width: 2,
                    ),
                  ),
                  child: const FaIcon(
                    FontAwesomeIcons.circleCheck,
                    color: AppColors.positive,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  isRegenerated
                      ? 'تم توليد كود دخول جديد'
                      : 'تم إنشاء حساب الموظف بنجاح',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _InfoRow(label: 'اسم الموظف', value: employeeName),
              _InfoRow(label: 'رقم الهاتف', value: phoneNumber),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'كود الدخول المؤقت',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMid,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          code,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppColors.accent,
                            letterSpacing: 6,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: code),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ الكود'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                          tooltip: 'نسخ',
                          icon: const FaIcon(
                            FontAwesomeIcons.copy,
                            size: 18,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'يُسلَّم هذا الكود للموظف لاستخدامه في أول تسجيل دخول فقط. '
                  'لن يظهر مرة أخرى — إن نُسي يمكن توليد كود جديد من قائمة الموظفين.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textLow,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('تم'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textLow,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
