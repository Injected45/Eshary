import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import 'glass.dart';
import 'pending_dispatch.dart';
import 'share.dart';

/// Persistent dispatch screen shown after a transaction has been saved
/// to Supabase. The user shares each generated message via the native
/// share sheet (WhatsApp, Telegram, ...). State is restored from
/// SharedPreferences if Android killed the activity while the share
/// target was in the foreground, so returning here always lands the
/// user on the same screen with the same data and the same ✓ marks.
class MessagesDispatchScreen extends ConsumerStatefulWidget {
  const MessagesDispatchScreen({super.key});

  @override
  ConsumerState<MessagesDispatchScreen> createState() =>
      _MessagesDispatchScreenState();
}

class _MessagesDispatchScreenState
    extends ConsumerState<MessagesDispatchScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No-op: the StateNotifier already mirrors to SharedPreferences on
    // every change, and is re-instantiated with the persisted value
    // when Riverpod rebuilds after activity recreation. This observer
    // is registered so AppLifecycle events are delivered, which is what
    // forces Flutter to settle pending state restoration on resume.
  }

  Future<void> _onShare(int index, PendingDispatch dispatch) async {
    await ref.read(pendingDispatchProvider.notifier).markOpened(index);
    if (!mounted) return;
    await shareText(context, dispatch.messages[index]);
  }

  Future<void> _onFinish() async {
    await ref.read(pendingDispatchProvider.notifier).finish();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dispatch = ref.watch(pendingDispatchProvider);

    if (dispatch == null) {
      // Defensive: nothing pending — fall back home on next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      });
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox.shrink(),
      );
    }

    final allOpened = dispatch.openedIndices.length >= dispatch.messages.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'إرسال الرسائل',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textHigh,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 120),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                FaIcon(
                  allOpened
                      ? FontAwesomeIcons.circleCheck
                      : FontAwesomeIcons.circleInfo,
                  color: allOpened ? AppColors.positive : AppColors.accent,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    allOpened
                        ? 'تم فتح كل الرسائل. اضغط "تم" لإنهاء العملية.'
                        : 'تم حفظ المعاملة. أرسل الرسائل أدناه ثم اضغط "تم".',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMid,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < dispatch.messages.length; i++)
            GlassCard(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          i < dispatch.cardTitles.length
                              ? dispatch.cardTitles[i]
                              : 'الرسالة ${i + 1}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (dispatch.openedIndices.contains(i))
                        const FaIcon(
                          FontAwesomeIcons.circleCheck,
                          color: AppColors.positive,
                          size: 16,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    dispatch.messages[i],
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textHigh,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _onShare(i, dispatch),
                    icon: const FaIcon(
                      FontAwesomeIcons.shareNodes,
                      size: 14,
                    ),
                    label: Text(
                      dispatch.openedIndices.contains(i)
                          ? 'إعادة الإرسال'
                          : 'إرسال',
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _onFinish,
            icon: const FaIcon(FontAwesomeIcons.check, size: 16),
            label: const Text('تم'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  allOpened ? AppColors.positive : AppColors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
