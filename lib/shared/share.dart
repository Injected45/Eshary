import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Share [text] via the native share sheet, falling back to the clipboard
/// (with the source's `alert("تم النسخ!")` SnackBar) if sharing isn't
/// supported on the current platform.
Future<void> shareText(BuildContext context, String text,
    {String? subject}) async {
  try {
    await Share.share(text, subject: subject);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم النسخ!')),
    );
  }
}
