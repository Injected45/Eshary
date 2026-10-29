import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../../companies/presentation/companies_providers.dart';
import '../data/account_books_repository.dart';
import '../data/treasury_repository.dart';
import '../domain/account_books.dart';
import 'treasury_providers.dart';

/// «رصيد أول المدة» (0094): where a company starts — the dollars each of my
/// accounts holds in its cash book and its bank book, each at its cost, and
/// the dinars in the box and in the bank. Without it there is nothing to sell
/// and nothing to pay a purchase with. Each book is given once; a correction
/// afterwards is «تسوية الرصيد» / the cost, in «الخزينة».
class OpeningBalancesScreen extends ConsumerWidget {
  const OpeningBalancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(accountBooksProvider);
    final range = DateTimeRange(
      start: DateTime(2000),
      end: DateTime.now().add(const Duration(days: 1)),
    );
    final lyd = ref.watch(lydSummaryProvider(range));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('رصيد أول المدة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
        children: [
          const GlassCard(
            padding: EdgeInsets.all(14),
            child: Text(
              'من هنا تبدأ: ما في كل حساب من دولار نقدي ودولار مصرفي بسعر '
              'تكلفته، وما في الخزينة والمصرف من دينار. يُسجَّل مرة واحدة لكل '
              'دفتر، وأي تصحيح بعده من «الخزينة» (تسوية الرصيد أو التكلفة).',
              style: TextStyle(fontSize: 12.5, color: AppColors.textLow),
            ),
          ),
          const SizedBox(height: 16),
          const _Title('الدينار الليبي'),
          lyd.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _ErrorText(friendlyError(e)),
            data: (s) => s.open
                ? GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line('نقدي (الخزينة)',
                            '${formatMoney(s.openingCash)} د.ل'),
                        _Line('مصرفي (المصرف)',
                            '${formatMoney(s.openingBank)} د.ل'),
                        const SizedBox(height: 6),
                        const Text(
                          'سُجّل رصيد الدينار. الإيداع والسحب من «خزينة الدينار».',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  )
                : const _LydOpeningCard(),
          ),
          const SizedBox(height: 20),
          const _Title('الدولار في حساباتي'),
          books.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => _ErrorText(friendlyError(e)),
            data: (map) {
              final list = map.values.toList()
                ..sort((a, b) => '${a.companyName} ${a.accountName}'
                    .compareTo('${b.companyName} ${b.accountName}'));
              if (list.isEmpty) {
                return const _ErrorText(
                  'لا توجد حسابات بعد. أضفها من «حساباتي» ثم ارجع إلى هنا.',
                  color: AppColors.textLow,
                );
              }
              return Column(
                children: [
                  for (final b in list)
                    _AccountOpeningCard(
                      key: ValueKey(b.exchangeId),
                      books: b,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Saves, refreshes what shows balances and costs, and says so; false on an
/// error (shown).
Future<bool> _save(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
  String done,
) async {
  try {
    await action();
    ref.invalidate(accountBooksProvider);
    ref.invalidate(accountCostsProvider);
    ref.invalidate(treasuryProvider);
    ref.invalidate(lydSummaryProvider);
    ref.invalidate(allExchangesProvider);
    if (context.mounted) {
      showTopSnackBar(context, SnackBar(content: Text(done)));
    }
    return true;
  } catch (e, st) {
    AppLogger.error('openingBalances', e, st);
    if (context.mounted) {
      showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
    }
    return false;
  }
}

Future<bool> _confirm(BuildContext context, List<String> lines) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تأكيد رصيد أول المدة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(l),
            ),
          const SizedBox(height: 6),
          const Text(
            'يُسجَّل مرة واحدة. أي تصحيح بعده من «الخزينة».',
            style: TextStyle(fontSize: 12, color: AppColors.textLow),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('رجوع'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('تأكيد'),
        ),
      ],
    ),
  );
  return sure ?? false;
}

class _LydOpeningCard extends ConsumerStatefulWidget {
  const _LydOpeningCard();

  @override
  ConsumerState<_LydOpeningCard> createState() => _LydOpeningCardState();
}

class _LydOpeningCardState extends ConsumerState<_LydOpeningCard> {
  final _cash = TextEditingController();
  final _bank = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cash.dispose();
    _bank.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = tryParseMoney(_cash.text);
    final b = tryParseMoney(_bank.text);
    // given once: an empty or unreadable entry must not open it at 0 (a 0
    // typed on purpose is fine)
    if ((c == null && _cash.text.trim().isNotEmpty) ||
        (b == null && _bank.text.trim().isNotEmpty) ||
        (c == null && b == null)) {
      showTopSnackBar(
        context,
        const SnackBar(
          content: Text('اكتب دينار الخزينة والمصرف (0 إن كان فارغًا).'),
        ),
      );
      return;
    }
    final cash = c ?? 0;
    final bank = b ?? 0;
    if (!await _confirm(context, [
      'نقدي (الخزينة): ${formatMoney(cash)} د.ل',
      'مصرفي (المصرف): ${formatMoney(bank)} د.ل',
    ])) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    await _save(
      context,
      ref,
      () =>
          ref.read(treasuryRepositoryProvider).lydOpen(cash: cash, bank: bank),
      'سُجّل رصيد الدينار.',
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AmountField(controller: _cash, label: 'نقدي في الخزينة (د.ل)'),
          const SizedBox(height: 10),
          _AmountField(controller: _bank, label: 'في المصرف (د.ل)'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '...' : 'حفظ رصيد الدينار'),
          ),
        ],
      ),
    );
  }
}

class _AccountOpeningCard extends ConsumerStatefulWidget {
  const _AccountOpeningCard({super.key, required this.books});
  final AccountBooks books;

  @override
  ConsumerState<_AccountOpeningCard> createState() =>
      _AccountOpeningCardState();
}

class _AccountOpeningCardState extends ConsumerState<_AccountOpeningCard> {
  final _qty = {
    kBookCash: TextEditingController(),
    kBookBank: TextEditingController(),
  };
  final _cost = {
    kBookCash: TextEditingController(),
    kBookBank: TextEditingController(),
  };
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._qty.values, ..._cost.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Dollars from before 0093 are all in the bank book until split.
  bool get _needsSplit => !widget.books.split && widget.books.balance > 0.005;

  /// A book that never held anything takes an opening (the database checks
  /// that it never moved at all).
  bool _open(String book) {
    final p = widget.books.of(book);
    return !_needsSplit && !p.hasDollars && p.costRate == null;
  }

  Future<void> _submit() async {
    final toSave = <({String book, double usd, double cost})>[];
    for (final book in [kBookCash, kBookBank]) {
      if (!_open(book)) continue;
      final qText = _qty[book]!.text.trim();
      final cText = _cost[book]!.text.trim();
      if (qText.isEmpty && cText.isEmpty) continue;
      final usd = parseMoney(qText);
      final cost = parseRate(cText);
      if (usd <= 0) {
        _snack('اكتب عدد الدولار ${bookLabel(book)}.');
        return;
      }
      if (!rateInRange(cost)) {
        _snack('اكتب تكلفة الدولار ${bookLabel(book)} (بين 1 و100 د.ل).');
        return;
      }
      toSave.add((book: book, usd: usd, cost: cost));
    }
    if (toSave.isEmpty) {
      _snack('اكتب الدولار وتكلفته في دفتر واحد على الأقل.');
      return;
    }
    if (!await _confirm(context, [
      '${widget.books.companyName} — ${widget.books.accountName}',
      for (final s in toSave)
        'دولار ${bookLabel(s.book)}: \$${formatMoney(s.usd)} × '
            '${formatRate(s.cost)} = ${formatMoney(lydFor(s.usd, s.cost))} د.ل',
    ])) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final repo = ref.read(accountBooksRepositoryProvider);
    await _save(
      context,
      ref,
      () async {
        for (final s in toSave) {
          await repo.setOpening(
            exchangeId: widget.books.exchangeId,
            book: s.book,
            usd: s.usd,
            cost: s.cost,
          );
        }
      },
      'سُجّل رصيد أول المدة لـ ${widget.books.accountName}.',
    );
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String text) =>
      showTopSnackBar(context, SnackBar(content: Text(text)));

  Widget _book(String book) {
    final p = widget.books.of(book);
    if (!_open(book)) {
      return _Line(
        'دولار ${bookLabel(book)}',
        p.costRate == null
            ? '\$${formatMoney(p.balance)}'
            : '\$${formatMoney(p.balance)} × ${formatRate(p.costRate!)}',
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'دولار ${bookLabel(book)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _AmountField(
                  controller: _qty[book]!,
                  label: 'الكمية (\$)',
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AmountField(
                  controller: _cost[book]!,
                  label: 'التكلفة (د.ل للدولار)',
                  onChanged: () => setState(() {}),
                ),
              ),
            ],
          ),
          Builder(
            builder: (_) {
              final usd = parseMoney(_qty[book]!.text);
              final cost = parseRate(_cost[book]!.text);
              if (usd <= 0 || !rateInRange(cost)) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'القيمة: ${formatMoney(lydFor(usd, cost))} د.ل',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textLow,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.books;
    final anyOpen = _open(kBookCash) || _open(kBookBank);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${b.companyName} — ${b.accountName}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          if (_needsSplit)
            Text(
              'في الحساب \$${formatMoney(b.balance)} لم تُقسَّم بعد بين '
              'النقدي والمصرفي. قسّمها من «الخزينة» ← دفاتر الحسابات.',
              style: const TextStyle(fontSize: 12, color: AppColors.textLow),
            )
          else ...[
            _book(kBookCash),
            _book(kBookBank),
            if (anyOpen) ...[
              const SizedBox(height: 4),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? '...' : 'حفظ رصيد أول المدة'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 4),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.textLow),
              ),
            ),
            Text(
              value,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text, {this.color = AppColors.negative});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text,
            textAlign: TextAlign.center, style: TextStyle(color: color)),
      );
}
