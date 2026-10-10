import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../domain/member_invite.dart';

/// Camera screen that reads the administrator's invitation QR. Pops with the
/// invitation secret (the QR can also be a picture sent by WhatsApp: "من المعرض").
class InviteScanScreen extends StatefulWidget {
  const InviteScanScreen({super.key});

  @override
  State<InviteScanScreen> createState() => _InviteScanScreenState();
}

class _InviteScanScreenState extends State<InviteScanScreen> {
  // QR only (a product barcode must never be read as an invitation) and
  // noDuplicates (a held-still QR would otherwise fire ~30 times a second).
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    final token = inviteTokenFromText(raw);
    if (token == null) {
      setState(() => _error = 'هذا ليس رمز دعوة من تطبيق إشاري.');
      return;
    }
    _done = true;
    Navigator.of(context).pop(token);
  }

  Future<void> _pickFromGallery() async {
    if (_done) return;
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
      _onDetect(capture);
    } catch (e, st) {
      AppLogger.error('inviteScan.analyzeImage', e, st);
      if (mounted) setState(() => _error = 'تعذّر قراءة الصورة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('مسح QR الدعوة'),
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
              errorBuilder: (context, error) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'تعذّر تشغيل الكاميرا. اسمح للتطبيق باستخدام الكاميرا '
                    'ثم أعد المحاولة، أو اختر صورة من المعرض.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white),
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
                  'وجّه الكاميرا نحو الـ QR الذي أرسله لك المدير',
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
