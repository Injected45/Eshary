import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/glass.dart';

enum DateFilterMode { today, range }

final DateFormat archiveFilterDateFmt = DateFormat('yyyy/MM/dd');

bool inDateRange(DateTime? dt, DateTime start, DateTime end) =>
    dt != null && !dt.isBefore(start) && !dt.isAfter(end);

({DateTime start, DateTime end}) resolveActiveRange({
  required DateFilterMode mode,
  required DateTime? from,
  required DateTime? to,
}) {
  final now = DateTime.now();
  final ready = from != null && to != null && !from.isAfter(to);
  if (mode == DateFilterMode.today || !ready) {
    return (
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
    );
  }
  return (
    start: DateTime(from.year, from.month, from.day),
    end: DateTime(to.year, to.month, to.day, 23, 59, 59, 999),
  );
}

class DateFilterBar extends StatelessWidget {
  const DateFilterBar({
    super.key,
    required this.mode,
    required this.from,
    required this.to,
    required this.onModeChanged,
    required this.onPickFrom,
    required this.onPickTo,
    required this.showInvalidHint,
  });

  final DateFilterMode mode;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateFilterMode> onModeChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final bool showInvalidHint;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  label: 'اليوم',
                  icon: FontAwesomeIcons.calendar,
                  selected: mode == DateFilterMode.today,
                  onTap: () => onModeChanged(DateFilterMode.today),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeChip(
                  label: 'خلال فترة',
                  icon: FontAwesomeIcons.calendar,
                  selected: mode == DateFilterMode.range,
                  onTap: () => onModeChanged(DateFilterMode.range),
                ),
              ),
            ],
          ),
          if (mode == DateFilterMode.range) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'من',
                    value: from,
                    onTap: onPickFrom,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateField(
                    label: 'إلى',
                    value: to,
                    onTap: onPickTo,
                  ),
                ),
              ],
            ),
            if (showInvalidHint) ...[
              const SizedBox(height: 6),
              const Text(
                'حدّد تاريخ البداية والنهاية',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.15)
                : AppColors.glassFill,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.glassBorder,
              width: selected ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.accent : AppColors.textMid,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 6),
                FaIcon(
                  icon,
                  size: 13,
                  color: selected ? AppColors.accent : AppColors.textMid,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final display =
        value == null ? '—' : archiveFilterDateFmt.format(value!);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            border: Border.all(color: AppColors.glassBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.calendar,
                size: 13,
                color: AppColors.textLow,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textLow,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  display,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
