import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import 'party_report_screen.dart';

/// One report in the "التقارير" tab.
class ReportEntry {
  const ReportEntry({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.open,
  });

  final String keyName;
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder open;
}

/// The reports the app can produce. New reports are added here, one entry each.
final List<ReportEntry> kReports = [
  ReportEntry(
    keyName: 'party',
    title: 'تقرير حسب الجهة',
    subtitle: 'معاملات شركة أو عميل أو كود خلال فترة، مع ملف PDF',
    icon: FontAwesomeIcons.userGroup,
    open: (_) => const PartyReportScreen(),
  ),
];

/// The "التقارير" tab: a list of reports; each opens its own screen.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        contentTopPadding(context),
        16,
        contentBottomPadding(context),
      ),
      children: [
        for (final r in kReports) ...[
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              key: ValueKey('report-${r.keyName}'),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: FaIcon(r.icon, size: 20, color: AppColors.accent),
              title: Text(
                r.title,
                style: const TextStyle(
                  color: AppColors.textHigh,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                r.subtitle,
                style: const TextStyle(color: AppColors.textLow, fontSize: 12),
              ),
              trailing: const FaIcon(
                FontAwesomeIcons.chevronLeft,
                size: 14,
                color: AppColors.textLow,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: r.open),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
