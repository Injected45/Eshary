import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/app_lock.dart';
import '../../../shared/audio_feedback.dart';
import '../../../shared/cache.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../admin/presentation/admin_screen.dart';
import '../../admin/presentation/backup_screen.dart';
import '../../archive/presentation/archive_providers.dart';
import '../../branches/presentation/branches_screen.dart';
import '../../clients/presentation/clients_screen.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../companies/presentation/companies_screen.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../employee_alerts/presentation/employee_alerts_providers.dart';
import '../../employee_alerts/presentation/employee_alerts_screen.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart';
import '../../license/presentation/license_provider.dart';
import '../../logs/presentation/logs_screen.dart';
import '../../profile/presentation/profile_details_screen.dart';
import '../../sub_users/presentation/sub_users_screen.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../data/wipe_repository.dart';
import '../../../shared/top_message.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref.watch(licenseStatusProvider).valueOrNull?.isAdmin ?? false;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, contentTopPadding(context), 16, contentBottomPadding(context)),
        children: [
          _SettingsRow(
            icon: FontAwesomeIcons.user,
            title: 'الملف الشخصي',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()),
            ),
          ),
          if (!isAdmin &&
              Supabase.instance.client.auth.currentUser?.isAnonymous != true) ...[
            const SizedBox(height: 12),
            _SettingsRow(
              icon: FontAwesomeIcons.crown,
              title: 'اشتراكي',
              onTap: () => context.push('/subscription'),
            ),
          ],
          const SizedBox(height: 12),
          const _AppLockRow(),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            _SettingsRow(
              icon: FontAwesomeIcons.userShield,
              title: 'إدارة الحسابات',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _SettingsRow(
              icon: FontAwesomeIcons.database,
              title: 'النسخ الاحتياطي',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupScreen()),
              ),
            ),
            const SizedBox(height: 12),
            // What the app logged when something failed ("تم تسجيل الحدث").
            _SettingsRow(
              icon: FontAwesomeIcons.fileLines,
              title: 'سجل الأخطاء',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LogsScreen()),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.buildingColumns,
            title: 'شركات الصرافة',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const ExchangeCompaniesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.building,
            title: 'حساباتي',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CompaniesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.users,
            title: 'العملاء',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ClientsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.codeBranch,
            title: 'الفروع',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BranchesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.userTie,
            title: 'إدارة الموظفين',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubUsersScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsRow(
            icon: FontAwesomeIcons.bell,
            title: 'إشعارات الموظفين',
            badge: ref.watch(unreadAlertsCountProvider),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EmployeeAlertsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _DestructiveSettingsRow(
            icon: FontAwesomeIcons.eraser,
            title: 'حذف المدخلات',
            subtitle:
                'يحذف العمليات المسجلة (الحوالات والمشتريات) فقط — لا يحذف الشركات وشركات الصرافة والعملاء',
            onTap: () => _confirmAndWipeEntries(context, ref),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'شركة الرحالة للبرمجيات . جميع الحقوق محفوظة 2026 ©',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool?> _showWipeConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  final controller = TextEditingController();
  return showGlassDialog<bool>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final typed = controller.text.trim();
              final canDelete = typed == 'احذف';
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHigh,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textLow,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'للتأكيد اكتب: احذف',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMid,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      hintText: 'احذف',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
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
                        onPressed: canDelete
                            ? () => Navigator.of(dialogContext).pop(true)
                            : null,
                        child: const Text('حذف'),
                      ),
                    ),
                  ]),
                ],
              );
            },
          ),
        ),
      ),
    ),
  ).whenComplete(controller.dispose);
}

Future<void> _confirmAndWipeEntries(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await _showWipeConfirmDialog(
    context,
    title: 'حذف المدخلات؟',
    body:
        'ستُحذف كل العمليات المالية: عمليات الخروج والدخول وما يتصل بها من إلغاءات '
        'وإشعارات، وتُصفَّر أرصدة الحسابات. تبقى الشركات وشركات الصرافة والعملاء '
        'كما هي. تُحفظ نسخة احتياطية قبل الحذف يمكنك استعادتها من شاشة النسخ الاحتياطي.',
  );
  if (confirmed != true) return;

  final uid = ref.read(currentUserIdProvider);
  if (uid == null) {
    if (!context.mounted) return;
    showTopSnackBar(
      context,
      const SnackBar(content: Text('لم يتم تسجيل الدخول')),
    );
    return;
  }

  // One database transaction: a safety backup first, then every exit, entry,
  // cancellation and alert about them goes, and the balances return to 0.
  WipeResult? result;
  Object? failure;
  try {
    result = await ref.read(wipeRepositoryProvider).wipeOperations();
  } catch (e, st) {
    AppLogger.error('settings.wipeOperations', e, st);
    failure = e;
  }

  await ref.read(jsonCacheProvider).clear();

  ref.invalidate(allExchangesProvider);
  ref.invalidate(dailyTransfersProvider);
  ref.invalidate(todayTransfersProvider);
  ref.invalidate(todayBuysProvider);
  ref.invalidate(archivedTransfersProvider);
  ref.invalidate(dailyBuysProvider);
  ref.invalidate(pendingBuysProvider);
  ref.invalidate(archivedBuysProvider);
  ref.invalidate(archivedSoldTotalProvider);
  ref.invalidate(archivedBoughtTotalProvider);

  if (failure == null) playAlert();

  if (!context.mounted) return;
  showTopSnackBar(
    context,
    SnackBar(
      content: Text(
        failure != null
            ? friendlyError(failure)
            : 'تم حذف كل العمليات المالية: '
                '${result!.transfers} خروج و${result.currencyBuys} دخول. '
                'حُفظت نسخة احتياطية قبل الحذف.',
      ),
    ),
  );
}

/// "القفل بالبصمة": asks for the fingerprint / face / screen lock when the app
/// opens and after a minute in the background. Off by default.
class _AppLockRow extends ConsumerWidget {
  const _AppLockRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appLockEnabledProvider);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SwitchListTile(
        key: const ValueKey('app-lock-switch'),
        contentPadding: EdgeInsets.zero,
        secondary: const FaIcon(
          FontAwesomeIcons.fingerprint,
          size: 18,
          color: AppColors.accent,
        ),
        title: const Text('القفل بالبصمة'),
        subtitle: const Text(
          'يُطلب عند فتح التطبيق وبعد دقيقة في الخلفية',
          style: TextStyle(fontSize: 11.5, color: AppColors.textLow),
        ),
        value: on,
        onChanged: (v) async {
          final auth = ref.read(deviceAuthProvider);
          if (v) {
            if (!await auth.isAvailable()) {
              if (context.mounted) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('فعّل بصمة أو قفل شاشة في إعدادات الهاتف أولاً.'),
                  ),
                );
              }
              return;
            }
            // Proves it works before turning it on, so nobody is locked out.
            if (!await auth.authenticate('أكّد لتفعيل القفل')) return;
          }
          await ref.read(appLockEnabledProvider.notifier).set(v);
        },
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// Unread count shown as a red pill before the chevron; hidden at 0.
  final int badge;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: FaIcon(icon, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (badge > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.negative,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 14,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestructiveSettingsRow extends StatelessWidget {
  const _DestructiveSettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.negative.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppColors.negative.withValues(alpha: 0.4),
                  ),
                ),
                child: FaIcon(icon, size: 16, color: AppColors.negative),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.negative,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textLow,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 14,
                color: AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
