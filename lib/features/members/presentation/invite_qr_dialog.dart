import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../domain/member_invite.dart';

/// The text the administrator sends with the invitation (WhatsApp, SMS…).
/// It carries the whole secret, so [inviteTokenFromText] reads it back.
String inviteShareText({
  required String name,
  required InviteLicense license,
  required DateTime expiresAt,
  required String payload,
}) {
  final until = DateFormat('yyyy/MM/dd HH:mm').format(expiresAt.toLocal());
  return 'دعوة للانضمام إلى تطبيق إشاري\n'
      'الاسم: $name\n'
      'الصلاحية: ${license.label}\n\n'
      '1) ثبّت التطبيق وافتحه ثم اختر «لدي دعوة».\n'
      '2) امسح الـ QR المرفق، أو الصق هذا الرمز كاملاً:\n'
      '$payload\n'
      '3) اكتب رقم هاتفك، فيصلك رمز تحقق على واتساب.\n\n'
      'صالحة لمرة واحدة حتى $until. لا تشاركها مع أحد.';
}

/// Shown right after creating an invitation: the one moment the secret exists.
/// The administrator shows the QR on screen, or sends it as an image / as
/// text (e.g. by WhatsApp). It cannot be shown again later (only its hash is
/// stored); to resend, revoke and create a new one.
class InviteQrDialog extends StatefulWidget {
  const InviteQrDialog({
    super.key,
    required this.name,
    required this.phone,
    required this.license,
    required this.invite,
  });

  final String name;
  final String phone;
  final InviteLicense license;
  final CreatedInvite invite;

  @override
  State<InviteQrDialog> createState() => _InviteQrDialogState();
}

class _InviteQrDialogState extends State<InviteQrDialog> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  String get _text => inviteShareText(
        name: widget.name,
        license: widget.license,
        expiresAt: widget.invite.expiresAt,
        payload: widget.invite.payload,
      );

  Future<void> _shareImage() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('boundary not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('png encode failed');
      await Share.shareXFiles(
        [
          XFile.fromData(
            data.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'eshary-invite.png',
          ),
        ],
        text: _text,
      );
    } catch (e, st) {
      AppLogger.error('invites.shareImage', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareText() async {
    setState(() => _busy = true);
    try {
      await Share.share(_text);
    } catch (e, st) {
      AppLogger.error('invites.shareText', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text));
    if (mounted) {
      showTopSnackBar(context, const SnackBar(content: Text('تم نسخ نص الدعوة')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrSize = math.min(
      220.0,
      math.min(400.0, MediaQuery.sizeOf(context).width - 48) - 44 - 24,
    );
    final until =
        DateFormat('yyyy/MM/dd HH:mm').format(widget.invite.expiresAt.toLocal());
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: GlassCard(
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'دعوة جاهزة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.name} · ${widget.phone}',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: AppColors.textLow, fontSize: 13),
                ),
                Text(
                  'الصلاحية: ${widget.license.label}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      // Fixed colours, never theme colours: a camera needs dark
                      // modules on a light quiet zone, even in dark mode.
                      child: QrImageView(
                        key: const ValueKey('invite-qr'),
                        data: widget.invite.payload,
                        size: qrSize,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF0B1220),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF0B1220),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'صالحة حتى $until · لمرة واحدة',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'يمسح المشترك الـ QR ثم يكتب رقم هاتفه، فيصله رمز على واتساب '
                  'على الرقم المسجّل أعلاه. من يملك الـ QR وحده لا يدخل. '
                  'لا يمكن عرض هذه الدعوة مرة أخرى؛ إن أضعتها فألغها وأنشئ غيرها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('invite-share-image'),
                  onPressed: _busy ? null : _shareImage,
                  icon: const FaIcon(FontAwesomeIcons.image, size: 15),
                  label: const Text('مشاركة الـ QR مع الرسالة'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('invite-share-text'),
                        onPressed: _busy ? null : _shareText,
                        child: const Text('مشاركة كنص'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('invite-copy'),
                        onPressed: _copy,
                        child: const Text('نسخ'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
