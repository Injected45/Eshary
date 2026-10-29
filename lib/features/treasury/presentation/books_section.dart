import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/logger.dart';
import '../../../shared/request_id.dart';
import '../../../shared/top_message.dart';
import '../data/account_books_repository.dart';
import '../domain/account_books.dart';
import 'treasury_providers.dart';

/// The cash and bank books of one account inside its treasury card
/// (migration 0093): the dollars and the cost of each, the one-time split of
/// the dollars held before 0093, and moving dollars between the books.
// a move between books sent again is saved once (0094)
final _moveIds = RequestIdKeeper();

class BooksSection extends ConsumerWidget {
  const BooksSection({super.key, required this.exchangeId});
  final String exchangeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // a database before 0093 has no books: nothing is shown
    final b = ref.watch(accountBooksProvider).valueOrNull?[exchangeId];
    if (b == null) return const SizedBox.shrink();
    String line(BookPosition p) => p.hasDollars
        ? '\$${formatMoney(p.balance)} · '
            '${p.costRate == null ? 'بلا تكلفة' : '${p.costRate!.toStringAsFixed(4)} د.ل'}'
        : '\$0.00';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row('الدفتر النقدي', line(b.cash),
              key: ValueKey('book-cash-$exchangeId')),
          _Row('الدفتر المصرفي', line(b.bank),
              key: ValueKey('book-bank-$exchangeId')),
          const SizedBox(height: 6),
          if (!b.split)
            FilledButton.icon(
              key: ValueKey('split-books-$exchangeId'),
              onPressed: () => _split(context, ref, b),
              icon: const FaIcon(FontAwesomeIcons.codeBranch, size: 12),
              label: const Text('تقسيم الدولار الحالي على الدفترين'),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey('move-books-$exchangeId'),
                onPressed: () => _move(context, ref, b),
                icon: const FaIcon(FontAwesomeIcons.rightLeft, size: 11),
                label: const Text('تحويل بين الدفترين'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String done,
  ) async {
    try {
      await action();
      ref.invalidate(accountBooksProvider);
      ref.invalidate(treasuryProvider);
      if (context.mounted) {
        showTopSnackBar(context, SnackBar(content: Text(done)));
      }
    } catch (e, st) {
      AppLogger.error('treasury.books', e, st);
      if (context.mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _split(
      BuildContext context, WidgetRef ref, AccountBooks b) async {
    final r = await showDialog<_SplitInput>(
      context: context,
      builder: (_) => _SplitDialog(books: b),
    );
    if (r == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(accountBooksRepositoryProvider).split(
            exchangeId: b.exchangeId,
            cashQty: r.cashQty,
            cashCost: r.cashCost,
            bankCost: r.bankCost,
          ),
      'قُسّم دولار ${b.accountName}: نقدي \$${formatMoney(r.cashQty)}، '
      'مصرفي \$${formatMoney(b.balance - r.cashQty)}.',
    );
  }

  Future<void> _move(
      BuildContext context, WidgetRef ref, AccountBooks b) async {
    final r = await showDialog<_MoveInput>(
      context: context,
      builder: (_) => _MoveDialog(books: b),
    );
    if (r == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () async {
        await ref.read(accountBooksRepositoryProvider).move(
              exchangeId: b.exchangeId,
              from: r.from,
              usd: r.usd,
              price: r.price,
              note: r.note,
              requestId: _moveIds
                  .idFor([b.exchangeId, r.from, r.usd, r.price, r.note]),
            );
        _moveIds.done();
      },
      'حُوّل \$${formatMoney(r.usd)} من الدفتر ${bookLabel(r.from)} '
      'إلى ${bookLabel(r.from == kBookCash ? kBookBank : kBookCash)}.',
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMid),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _SplitInput = ({double cashQty, double? cashCost, double? bankCost});

/// How the dollars held before 0093 split: the cash part and its cost, the
/// rest bank and its cost. Once per account.
class _SplitDialog extends StatefulWidget {
  const _SplitDialog({required this.books});
  final AccountBooks books;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  final _cashQty = TextEditingController();
  late final _cashCost = TextEditingController();
  late final _bankCost = TextEditingController(
    text: widget.books.bank.costRate == null
        ? ''
        : formatRate(widget.books.bank.costRate!),
  );
  String? _error;

  double get _cash => parseMoney(_cashQty.text);
  double get _bank => widget.books.balance - _cash;

  @override
  void dispose() {
    _cashQty.dispose();
    _cashCost.dispose();
    _bankCost.dispose();
    super.dispose();
  }

  void _save() {
    final cash = _cash;
    final cashCost = parseRate(_cashCost.text);
    final bankCost = parseRate(_bankCost.text);
    String? e;
    if (cash < 0 || _bank < -0.005) {
      e = 'النقدي يجب أن يكون بين صفر و\$${formatMoney(widget.books.balance)}.';
    } else if (cash > 0 && !rateInRange(cashCost)) {
      e = 'اكتب تكلفة الدولار النقدي (بين 1 و100 د.ل).';
    } else if (_bank > 0.005 && !rateInRange(bankCost)) {
      e = 'اكتب تكلفة الدولار المصرفي (بين 1 و100 د.ل).';
    }
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    Navigator.of(context).pop<_SplitInput>((
      cashQty: cash,
      cashCost: cash > 0 ? cashCost : null,
      bankCost: _bank > 0.005 ? bankCost : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.books;
    return AlertDialog(
      title: Text('تقسيم دولار ${b.accountName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'في الحساب الآن \$${formatMoney(b.balance)}. اكتب كم منها '
              'اشتُري بدينار نقدي وتكلفته، والباقي مصرفي. يُقسَّم مرة واحدة، '
              'وبعدها يُستعمل «تحويل بين الدفترين».',
              style: const TextStyle(fontSize: 12, color: AppColors.textLow),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('split-cash-qty'),
              controller: _cashQty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(labelText: 'الدولار النقدي (\$)'),
            ),
            TextField(
              key: const ValueKey('split-cash-cost'),
              controller: _cashCost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'تكلفة النقدي (د.ل نقدي)'),
            ),
            const SizedBox(height: 8),
            Text(
              'المصرفي: \$${formatMoney(_bank < 0 ? 0 : _bank)}',
              key: const ValueKey('split-bank-qty'),
            ),
            TextField(
              key: const ValueKey('split-bank-cost'),
              controller: _bankCost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'تكلفة المصرفي (د.ل مصرفي)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.negative),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('split-save'),
          onPressed: _save,
          child: const Text('حفظ التقسيم'),
        ),
      ],
    );
  }
}

typedef _MoveInput = ({String from, double usd, double price, String? note});

/// Dollars from one book to the other: they leave at the source book's cost
/// and enter the other at the price typed (its dinars per dollar).
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.books});
  final AccountBooks books;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  String _from = kBookBank;
  final _usd = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  String get _to => _from == kBookCash ? kBookBank : kBookCash;

  @override
  void dispose() {
    _usd.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final usd = parseMoney(_usd.text);
    final price = parseRate(_price.text);
    final have = widget.books.of(_from).balance;
    String? e;
    if (usd <= 0) {
      e = 'اكتب المبلغ بالدولار.';
    } else if (usd > have + 0.005) {
      e = 'في الدفتر ${bookLabel(_from)} \$${formatMoney(have)} فقط.';
    } else if (!rateInRange(price)) {
      e = 'اكتب سعر الدولار في الدفتر ${bookLabel(_to)} (بين 1 و100).';
    }
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop<_MoveInput>(
      (from: _from, usd: usd, price: price, note: note.isEmpty ? null : note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.books.of(_from);
    return AlertDialog(
      title: const Text('تحويل بين الدفترين'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              key: const ValueKey('move-from'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: kBookBank, label: Text('من المصرفي')),
                ButtonSegment(value: kBookCash, label: Text('من النقدي')),
              ],
              selected: {_from},
              onSelectionChanged: (s) => setState(() => _from = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              'في الدفتر ${bookLabel(_from)} \$${formatMoney(src.balance)}'
              '${src.costRate == null ? '' : ' بتكلفة ${src.costRate!.toStringAsFixed(4)}'}',
              style: const TextStyle(fontSize: 12, color: AppColors.textLow),
            ),
            TextField(
              key: const ValueKey('move-usd'),
              controller: _usd,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ (\$)'),
            ),
            TextField(
              key: const ValueKey('move-price'),
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'سعره في الدفتر ${bookLabel(_to)} (د.ل للدولار)',
              ),
            ),
            TextField(
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.negative)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('move-save'),
          onPressed: _save,
          child: const Text('تحويل'),
        ),
      ],
    );
  }
}
