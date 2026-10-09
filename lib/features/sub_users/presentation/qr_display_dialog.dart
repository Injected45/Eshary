import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/sub_users_repository.dart';
import '../../../shared/top_message.dart';

/// Shows the one-time sign-in QR for an employee. The employee scans it from
/// the employee sign-in screen; it works once and expires after 10 minutes.
class QrDisplayDialog extends StatefulWidget {
  const QrDisplayDialog({
    super.key,
    required this.employeeName,
    required this.phoneNumber,
    required this.qr,
  });

  final String employeeName;
  final String phoneNumber;
  final SubUserQr qr;

  /// What the QR image encodes. Exposed so a test can tie what is DRAWN to
  /// what the scanner ACCEPTS.
  String get payload => qr.payload;

  @override
  State<QrDisplayDialog> createState() => _QrDisplayDialogState();
}

class _QrDisplayDialogState extends State<QrDisplayDialog> {
  late Duration _left;
  Timer? _timer;
  final _qrBoundaryKey = GlobalKey();
  bool _sharing = false;

  /// Renders the QR to a PNG and opens the share sheet, for employees who
  /// are not in front of the admin (e.g. a remote branch). The employee then
  /// opens the image on their phone and picks it in "مسح QR" → "من المعرض".
  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _qrBoundaryKey.currentContext?.findRenderObject()
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
            name: 'eshary-employee-qr.png',
          ),
        ],
        text: 'QR دخول ${widget.employeeName} — يعمل مرة واحدة وينتهي خلال '
            '10 دقائق. افتح التطبيق ← دخول الموظف ← مسح QR ← من المعرض.',
      );
    } catch (e, st) {
      AppLogger.error('subUsers.shareQr', e, st);
      if (mounted) {
        showTopSnackBar(
          context,
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _left = _remaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _remaining());
      if (_left == Duration.zero) _timer?.cancel();
    });
  }

  Duration _remaining() {
    final d = widget.qr.expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _clock {
    final m = _left.inMinutes.toString().padLeft(2, '0');
    final s = (_left.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _left == Duration.zero;
    // Never wider than the dialog: 48 inset + 44 card padding + 24 QR padding.
    final qrSize = math.min(
      220.0,
      math.min(400.0, MediaQuery.sizeOf(context).width - 48) - 44 - 24,
    );
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
                  'QR دخول الموظف',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.employeeName} · ${widget.phoneNumber}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: RepaintBoundary(
                    key: _qrBoundaryKey,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: expired
                          ? SizedBox(
                              width: qrSize,
                              height: qrSize,
                              child: Center(
                                child: Text(
                                  'انتهت صلاحية الـ QR',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          // Fixed colours, never theme colours: a camera needs dark
                          // modules on a light quiet zone, even in dark mode.
                          : QrImageView(
                              data: widget.qr.payload,
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
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FaIcon(
                      FontAwesomeIcons.clock,
                      size: 13,
                      color: expired ? AppColors.negative : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(
                      expired ? 'منتهي' : 'ينتهي خلال $_clock',
                      style: TextStyle(
                        color: expired ? AppColors.negative : AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    )),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'يعمل مرة واحدة فقط. يمسحه الموظف أمامك، أو شاركه معه إن كان بعيداً '
                  '(أرسله له وحده فقط، فمن يملك الصورة يستطيع الدخول خلال 10 دقائق).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (expired || _sharing) ? null : _share,
                  icon: const FaIcon(FontAwesomeIcons.shareNodes, size: 15),
                  label: const Text('مشاركة الـ QR'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
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
