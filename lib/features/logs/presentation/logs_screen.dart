import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  Future<void> _clear() async {
    await AppLogger.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = AppLogger.readAll().reversed.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('سجل الأخطاء'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'مسح السجل',
            icon: const FaIcon(FontAwesomeIcons.broom, size: 16),
            onPressed: entries.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text(
                  'لا توجد سجلات',
                  style: TextStyle(color: AppColors.textLow),
                ),
              ),
            ),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LogEntryCard(entry: entry),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'شركة الرحالة للبرمجيات . جميع الحقوق محفوظة 2026 ©',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogEntryCard extends StatefulWidget {
  const _LogEntryCard({required this.entry});
  final LogEntry entry;

  @override
  State<_LogEntryCard> createState() => _LogEntryCardState();
}

class _LogEntryCardState extends State<_LogEntryCard> {
  bool _expanded = false;

  Color _levelColor() {
    switch (widget.entry.level) {
      case 'error':
        return AppColors.negative;
      case 'warning':
        return AppColors.warning;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor();
    final hasDetails =
        widget.entry.error != null || widget.entry.stackTrace != null;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.entry.level,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dateTime.format(widget.entry.timestamp),
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 11,
                  ),
                ),
              ),
              if (hasDetails)
                IconButton(
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () =>
                      setState(() => _expanded = !_expanded),
                  icon: FaIcon(
                    _expanded
                        ? FontAwesomeIcons.chevronUp
                        : FontAwesomeIcons.chevronDown,
                    size: 12,
                    color: AppColors.textLow,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.entry.message,
            style: const TextStyle(
              color: AppColors.textHigh,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_expanded && hasDetails) ...[
            const SizedBox(height: 10),
            if (widget.entry.error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgPanel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: SelectableText(
                  widget.entry.error!,
                  style: const TextStyle(
                    color: AppColors.textMid,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            if (widget.entry.stackTrace != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgPanel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: SelectableText(
                  widget.entry.stackTrace!,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
