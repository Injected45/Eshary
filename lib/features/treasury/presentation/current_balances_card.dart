import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../domain/account_books.dart';
import 'opening_balances_screen.dart';
import 'treasury_providers.dart';

/// «الأرصدة الآن» at the top of the treasury: the dollars of every account
/// in the cash book and in the bank book (with their value at cost), and the
/// dinars in the box and in the bank. Shown from the opening balances on,
/// before any sale or purchase.
class CurrentBalancesCard extends ConsumerWidget {
  const CurrentBalancesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(accountBooksProvider).valueOrNull;
    final lyd = ref.watch(lydSummaryProvider(kAllTime)).valueOrNull;

    double usd(String book) =>
        books?.values.fold<double>(0, (s, b) => s + b.of(book).balance) ?? 0;
    double? value(String book) {
      if (books == null) return null;
      var sum = 0.0;
      for (final b in books.values) {
        final p = b.of(book);
        if (!p.hasDollars) continue;
        if (p.bookValue == null) return null; // a book without a cost
        sum += p.bookValue!;
      }
      return sum;
    }

    final lydOpen = lyd?.open ?? false;
    final nothingYet = books != null &&
        lyd != null &&
        !lydOpen &&
        usd(kBookCash).abs() < 0.005 &&
        usd(kBookBank).abs() < 0.005;

    void openOpenings() => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const OpeningBalancesScreen(),
          ),
        );

    return GlassCard(
      key: const ValueKey('treasury-balances'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'الأرصدة الآن',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: 'دولار نقدي',
                  value:
                      books == null ? '…' : '\$${formatMoney(usd(kBookCash))}',
                  sub: _valueText(value(kBookCash)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Cell(
                  label: 'دولار مصرفي',
                  value:
                      books == null ? '…' : '\$${formatMoney(usd(kBookBank))}',
                  sub: _valueText(value(kBookBank)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Cell(
                  label: 'دينار الخزينة',
                  value: lyd == null
                      ? '…'
                      : lydOpen
                          ? '${formatMoney(lyd.cash)} د.ل'
                          : 'لم يُسجَّل',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Cell(
                  label: 'دينار المصرف',
                  value: lyd == null
                      ? '…'
                      : lydOpen
                          ? '${formatMoney(lyd.bank)} د.ل'
                          : 'لم يُسجَّل',
                ),
              ),
            ],
          ),
          if (nothingYet || (lyd != null && !lydOpen)) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('treasury-open-openings'),
              onPressed: openOpenings,
              icon: const FaIcon(FontAwesomeIcons.scaleBalanced, size: 12),
              label: const Text('سجّل رصيد أول المدة'),
            ),
          ] else
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: openOpenings,
                child: const Text('رصيد أول المدة'),
              ),
            ),
        ],
      ),
    );
  }

  static String? _valueText(double? v) =>
      v == null || v.abs() < 0.005 ? null : 'بتكلفة ${formatMoney(v)} د.ل';
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            style: const TextStyle(fontSize: 12, color: AppColors.textMid),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textHigh,
              ),
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                sub!,
                style: const TextStyle(fontSize: 11, color: AppColors.textLow),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
