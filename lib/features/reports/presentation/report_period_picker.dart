import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/libya_time.dart';
import '../../../shared/period_label.dart';

/// A period of the reports: Libya calendar days [first]..[last], and the
/// moments they cover. Made once when chosen (a range built from "now" on
/// every rebuild would be a new provider key and reload for ever).
class ReportPeriod {
  ReportPeriod(this.first, this.last)
      : range = DateTimeRange(
          start: libyaDayStart(first).toLocal(),
          end: libyaDayStart(last)
              .add(const Duration(days: 1))
              .subtract(const Duration(microseconds: 1))
              .toLocal(),
        );

  final DateTime first;
  final DateTime last;
  final DateTimeRange range;

  String get label => periodLabel(first, last);

  factory ReportPeriod.today() {
    final t = libyaToday();
    return ReportPeriod(t, t);
  }
}

enum ReportQuick { today, yesterday, week, month, lastMonth, custom }

const _quickLabels = {
  ReportQuick.today: 'اليوم',
  ReportQuick.yesterday: 'أمس',
  ReportQuick.week: 'آخر 7 أيام',
  ReportQuick.month: 'هذا الشهر',
  ReportQuick.lastMonth: 'الشهر الماضي',
  ReportQuick.custom: 'فترة…',
};

/// The chips choosing a report's period; [onChanged] gets the new one.
class ReportPeriodPicker extends StatefulWidget {
  const ReportPeriodPicker({super.key, required this.onChanged});
  final ValueChanged<ReportPeriod> onChanged;

  @override
  State<ReportPeriodPicker> createState() => _ReportPeriodPickerState();
}

class _ReportPeriodPickerState extends State<ReportPeriodPicker> {
  ReportQuick _quick = ReportQuick.today;

  Future<void> _pick(ReportQuick q) async {
    final t = libyaToday();
    ReportPeriod? p;
    switch (q) {
      case ReportQuick.today:
        p = ReportPeriod(t, t);
      case ReportQuick.yesterday:
        final y = t.subtract(const Duration(days: 1));
        p = ReportPeriod(y, y);
      case ReportQuick.week:
        p = ReportPeriod(t.subtract(const Duration(days: 6)), t);
      case ReportQuick.month:
        p = ReportPeriod(DateTime(t.year, t.month), t);
      case ReportQuick.lastMonth:
        final first = DateTime(t.year, t.month - 1);
        p = ReportPeriod(first, DateTime(t.year, t.month, 0));
      case ReportQuick.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: t,
          initialDateRange: DateTimeRange(
            start: t.subtract(const Duration(days: 6)),
            end: t,
          ),
          locale: const Locale('ar'),
        );
        if (picked == null) return;
        // at most 400 days (the database refuses longer)
        final start = picked.end.difference(picked.start).inDays > 399
            ? picked.end.subtract(const Duration(days: 399))
            : picked.start;
        p = ReportPeriod(
          DateTime(start.year, start.month, start.day),
          DateTime(picked.end.year, picked.end.month, picked.end.day),
        );
    }
    if (!mounted) return;
    setState(() => _quick = q);
    widget.onChanged(p);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final q in ReportQuick.values)
          ChoiceChip(
            label: Text(_quickLabels[q]!),
            selected: _quick == q,
            onSelected: (_) => _pick(q),
            selectedColor: AppColors.accent.withValues(alpha: 0.25),
            labelStyle: const TextStyle(fontSize: 12),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
