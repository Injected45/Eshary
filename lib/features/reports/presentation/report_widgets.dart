import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';

String usdText(double v) => '\$${formatMoney(v)}';
String lydText(double v) =>
    v < 0 ? '−${formatMoney(-v)} د.ل' : '${formatMoney(v)} د.ل';
String signedLydText(double v) =>
    v < 0 ? '−${formatMoney(-v)} د.ل' : '+${formatMoney(v)} د.ل';
Color signedColor(double v) => v < 0
    ? AppColors.negative
    : (v > 0 ? AppColors.positive : AppColors.textHigh);

/// "+12 %" / "−5 %" against the previous period; null → nothing.
String? changeText(double? share) {
  if (share == null) return null;
  final p = (share * 100).round();
  return p < 0 ? '−${-p} %' : '+$p %';
}

class ReportSectionTitle extends StatelessWidget {
  const ReportSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, top: 18, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textHigh,
          ),
        ),
      );
}

/// A label and its value on one line.
class ReportLine extends StatelessWidget {
  const ReportLine(this.label, this.value, {super.key, this.color, this.bold});
  final String label;
  final String value;
  final Color? color;
  final bool? bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: AppColors.textLow),
              ),
            ),
            Text(
              value,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: (bold ?? false) ? FontWeight.w800 : FontWeight.w600,
                color: color ?? AppColors.textHigh,
              ),
            ),
          ],
        ),
      );
}

/// A headline figure: its label, the value and an optional small line.
class ReportTile extends StatelessWidget {
  const ReportTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMid),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color ?? AppColors.textHigh,
                ),
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(
                sub!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 10.5, color: AppColors.textLow),
              ),
            ],
          ],
        ),
      );
}

/// Two tiles side by side.
class ReportTileRow extends StatelessWidget {
  const ReportTileRow(this.tiles, {super.key});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        ),
      );
}

class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class ReportMessage extends StatelessWidget {
  const ReportMessage(this.text, {super.key, this.color = AppColors.textLow});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color),
        ),
      );
}
