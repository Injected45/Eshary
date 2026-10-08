import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/employee_auth_repository.dart';
import '../domain/qr_payload.dart';

/// Result of a confirmed QR scan: the one-time token the employee agreed to
/// sign in with.
class ScannedEmployeeQr {
  const ScannedEmployeeQr(this.token, this.employeeName);
  final String token;
  final String employeeName;
}

/// Camera screen that reads the admin's sign-in QR. When a valid QR is found
/// it shows the employee name + phone linked to it and asks for confirmation;
/// on confirm it pops with a [ScannedEmployeeQr] so the caller can sign in.
class EmployeeQrScanScreen extends ConsumerStatefulWidget {
  const EmployeeQrScanScreen({super.key});

  @override
  ConsumerState<EmployeeQrScanScreen> createState() =>
      _EmployeeQrScanScreenState();
}

class _EmployeeQrScanScreenState extends ConsumerState<EmployeeQrScanScreen> {
  // QR only (a product barcode must never be read as a token) and
  // noDuplicates (a held-still QR would otherwise fire ~30 times a second).
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handling = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;

    final token = employeeTokenFromQrPayload(raw);
    if (token == null) {
      setState(() => _error = 'هذا ليس رمز دخول موظف من التطبيق.');
      return;
    }

    _handling = true;
    setState(() => _error = null);
    await _controller.stop();
    try {
      final preview =
          await ref.read(employeeAuthRepositoryProvider).previewQr(token);
      if (!mounted) return;
      final confirmed = await _confirm(preview);
      if (!mounted) return;
      if (confirmed == true) {
        Navigator.of(context).pop(ScannedEmployeeQr(token, preview.employeeName));
        return;
      }
      // Declined: drop the preview session and let the user scan again.
      await ref.read(employeeAuthRepositoryProvider).cancelPending();
    } catch (e, st) {
      AppLogger.error('employeeAuth.previewQr', e, st);
      if (mounted) setState(() => _error = friendlyError(e));
    }
    _handling = false;
    if (mounted) await _controller.start();
  }

  /// For a QR the admin shared as an image (remote branch): pick it from the
  /// gallery instead of pointing the camera at it.
  Future<void> _pickFromGallery() async {
    if (_handling) return;
    final picked = await FilePicker.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final capture = await _controller.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (capture == null || capture.barcodes.isEmpty) {
        if (mounted) setState(() => _error = 'لم يُعثر على QR في هذه الصورة.');
        return;
      }
      await _onDetect(capture);
    } catch (e, st) {
      AppLogger.error('employeeAuth.analyzeImage', e, st);
      if (mounted) setState(() => _error = 'تعذّر قراءة الصورة.');
    }
  }

  Future<bool?> _confirm(QrPreview preview) {
    return showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: FaIcon(
                    FontAwesomeIcons.userCheck,
                    size: 28,
                    color: AppColors.positive,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'تأكيد الدخول',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  preview.employeeName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  preview.phoneNumber,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textLow,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'سيتم ربط هذا الجهاز بحساب الموظف أعلاه.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textLow, fontSize: 12),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('ليس أنا'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('دخول'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('مسح QR الدخول'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'تعذّر تشغيل الكاميرا. اسمح للتطبيق باستخدام الكاميرا '
                    'ثم أعد المحاولة.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.accent, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: AppColors.negative.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                const Text(
                  'وجّه الكاميرا نحو الـ QR الذي أصدره المدير',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const FaIcon(FontAwesomeIcons.image, size: 15),
                    label: const Text('من المعرض (QR مُرسل إليك)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
