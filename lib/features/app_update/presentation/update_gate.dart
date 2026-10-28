import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import 'app_update_controller.dart';

/// Wraps the whole app. When a newer build was published it covers the app with
/// the update screen: a mandatory update cannot be dismissed (the app behind it
/// is not reachable), an optional one has "لاحقًا".
///
/// It checks when the app opens and each time the app comes back to the screen.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appUpdateProvider.notifier).check(force: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appUpdateProvider.notifier).onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appUpdateProvider);
    final blocked = s.visible && s.mandatory;
    return Stack(
      children: [
        // behind a mandatory update the app cannot be touched or focused
        Positioned.fill(
          child: ExcludeFocus(
            excluding: blocked,
            child: IgnorePointer(ignoring: blocked, child: widget.child),
          ),
        ),
        if (s.visible)
          Positioned.fill(
            child: PopScope(
              canPop: !s.mandatory,
              child: _UpdateScreen(state: s),
            ),
          ),
      ],
    );
  }
}

class _UpdateScreen extends ConsumerWidget {
  const _UpdateScreen({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appUpdateProvider.notifier);
    final release = state.release;
    final mandatory = state.mandatory;
    final notes = (release?.notes ?? '').trim();
    final working = state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.verifying;

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withValues(alpha: 0.18),
            border: Border.all(color: AppColors.glassBorderStrong),
          ),
          child: const FaIcon(
            FontAwesomeIcons.cloudArrowDown,
            size: 26,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          mandatory ? 'تحديث إلزامي' : 'يتوفر تحديث جديد',
          key: const ValueKey('update-title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textHigh,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          mandatory
              ? 'صدر إصدار جديد من إشاري'
                  '${release == null ? '' : ' (${release.versionName})'}'
                  '. يجب تحديث التطبيق للمتابعة.'
              : 'صدر إصدار جديد من إشاري'
                  '${release == null ? '' : ' (${release.versionName})'}.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMid,
            fontSize: 14,
            height: 1.6,
          ),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            key: const ValueKey('update-notes'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.glassFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              notes,
              style: const TextStyle(
                color: AppColors.textHigh,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        ..._actions(controller, working),
      ],
    );

    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: GlassCard(
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(child: body),
      ),
    );

    return Material(
      key: const ValueKey('update-screen'),
      // a mandatory update covers everything; an optional one dims the app
      color: mandatory ? AppColors.bgDeep : Colors.black54,
      child: SafeArea(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(20), child: card),
        ),
      ),
    );
  }

  List<Widget> _actions(AppUpdateController controller, bool working) {
    switch (state.phase) {
      case UpdatePhase.idle:
        return const [];
      case UpdatePhase.offered:
        return [
          FilledButton.icon(
            key: const ValueKey('update-now'),
            onPressed: controller.start,
            icon: const FaIcon(FontAwesomeIcons.download, size: 14),
            label: const Text('تحديث الآن'),
          ),
          if (!state.mandatory) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('update-later'),
              onPressed: controller.dismiss,
              child: const Text('لاحقًا'),
            ),
          ],
        ];
      case UpdatePhase.downloading:
      case UpdatePhase.verifying:
        final verifying = state.phase == UpdatePhase.verifying;
        return [
          LinearProgressIndicator(
            key: const ValueKey('update-progress'),
            value: verifying ? null : state.progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 10),
          Text(
            verifying
                ? 'جارٍ التحقق من الملف…'
                : 'جارٍ تنزيل التحديث… ${(state.progress * 100).round()}%',
            key: const ValueKey('update-status'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMid, fontSize: 13),
          ),
        ];
      case UpdatePhase.needsPermission:
        return [
          const Text(
            'لإكمال التحديث اسمح لإشاري بتثبيت التطبيقات: اضغط «فتح الإعدادات» '
            'ثم فعّل «السماح من هذا المصدر» وارجع إلى التطبيق.',
            key: ValueKey('update-status'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMid,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('update-settings'),
            onPressed: controller.openPermissionSettings,
            icon: const FaIcon(FontAwesomeIcons.gear, size: 14),
            label: const Text('فتح الإعدادات'),
          ),
        ];
      case UpdatePhase.ready:
        return [
          const Text(
            'تم تنزيل التحديث والتحقق منه. اضغط «تثبيت» ثم افتح إشاري من جديد '
            'بعد انتهاء التثبيت.',
            key: ValueKey('update-status'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMid,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('update-install'),
            onPressed: controller.start,
            icon: const FaIcon(FontAwesomeIcons.boxOpen, size: 14),
            label: const Text('تثبيت'),
          ),
        ];
      case UpdatePhase.failed:
        return [
          Text(
            state.error ?? 'تعذّر إكمال التحديث.',
            key: const ValueKey('update-status'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.negative,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('update-retry'),
            onPressed: controller.start,
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            label: const Text('إعادة المحاولة'),
          ),
          if (!state.mandatory) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('update-later'),
              onPressed: controller.dismiss,
              child: const Text('لاحقًا'),
            ),
          ],
        ];
    }
  }
}
