import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/build_flavor.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';

/// The privacy policy, shown inside the app (Google Play requires it to be
/// reachable in the app as well as on a web page). The text is the same file
/// that is published on the web: docs/privacy-policy.md.
const kPrivacyPolicyAsset = 'docs/privacy-policy.md';
const kTermsOfUseAsset = 'docs/terms-of-use.md';

/// Where to write: the support e-mail when the build has one, otherwise the
/// administration inside the app.
String supportContactText() =>
    kSupportEmail.isEmpty ? 'إدارة الحساب داخل التطبيق' : kSupportEmail;

/// Fills the placeholders of the policy text.
String fillPolicy(String raw) =>
    raw.replaceAll('{{SUPPORT}}', supportContactText());

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalDocumentScreen(
      title: 'سياسة الخصوصية', asset: kPrivacyPolicyAsset);
}

/// "شروط الاستخدام": the terms, shown in the app (and before sign-in).
class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalDocumentScreen(
      title: 'شروط الاستخدام', asset: kTermsOfUseAsset);
}

/// A legal text from the app's assets, with the contact filled in.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen(
      {super.key, required this.title, required this.asset});

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    // Opened from the welcome screen the stack holds only this page, so the
    // arrow (and the phone's own back button) must lead to the main screen
    // instead of doing nothing. "/" sends a signed-out visitor to the welcome
    // screen, a signed-in user to the home and an employee to theirs.
    final canPop = context.canPop();
    void back() => canPop ? context.pop() : context.go('/');
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(
          title: Text(title),
          leading: BackButton(
            key: const ValueKey('legal-back'),
            onPressed: back,
          ),
        ),
        body: SafeArea(
          child: FutureBuilder<String>(
            future: rootBundle.loadString(asset),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(18),
                    child: PolicyText(fillPolicy(snap.data!)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A tiny renderer for the policy file: "# title", "## heading", "- bullet",
/// anything else a paragraph.
class PolicyText extends StatelessWidget {
  const PolicyText(this.markdown, {super.key});
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        children.add(const SizedBox(height: 6));
      } else if (line.startsWith('## ')) {
        children.add(const SizedBox(height: 10));
        children.add(Text(
          line.substring(3),
          style: const TextStyle(
            color: AppColors.accent,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ));
        children.add(const SizedBox(height: 4));
      } else if (line.startsWith('# ')) {
        children.add(Text(
          line.substring(2),
          style: const TextStyle(
            color: AppColors.textHigh,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ));
      } else if (line.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(color: AppColors.textLow)),
              Expanded(
                child: Text(
                  line.substring(2),
                  style: const TextStyle(
                    color: AppColors.textMid,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        children.add(Text(
          line,
          style: const TextStyle(
            color: AppColors.textMid,
            fontSize: 13,
            height: 1.7,
          ),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
