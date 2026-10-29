import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/libya_time.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/pdf_file_name.dart';
import '../../../shared/request_id.dart';
import '../../../shared/top_message.dart';
import '../../archive/presentation/archive_filters.dart';
import '../../exchange_rates/presentation/lyd_method_selector.dart';
import '../data/customers_repository.dart';
import '../domain/customer_account.dart';
import 'customers_screen.dart';

typedef _StatementKey = ({String clientId, DateTimeRange range, String? book});

final customerStatementProvider = FutureProvider.autoDispose
    .family<CustomerStatement, _StatementKey>((ref, k) {
  return ref
      .watch(customersRepositoryProvider)
      .statement(k.clientId, k.range.start, k.range.end, book: k.book);
});

String _lyd(double v) => '${formatMoney(v)} د.ل';
final LibyaDateFormat _when = LibyaDateFormat('yyyy/MM/dd  HH:mm');

/// One customer's dinar account: the statement of a period, and the
/// administrator's actions — a collection, a payment, the opening balance and
/// the credit limit (migration 0091).
class CustomerStatementScreen extends ConsumerStatefulWidget {
  const CustomerStatementScreen({
    super.key,
    required this.clientId,
    required this.title,
    this.creditLimit,
  });

  final String clientId;
  final String title;
  final double? creditLimit;

  @override
  ConsumerState<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

class _CustomerStatementScreenState
    extends ConsumerState<CustomerStatementScreen> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;
  late double? _limit = widget.creditLimit;

  /// One book's statement (0093), or both (null): cash and bank dinars are
  /// two currencies, so a balance is read per book.
  String? _book;

  bool get _rangeReady => _from != null && _to != null && !_from!.isAfter(_to!);

  _StatementKey get _key {
    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);
    return (
      clientId: widget.clientId,
      range: DateTimeRange(start: r.start, end: r.end),
      book: _book,
    );
  }

  void _refresh() {
    ref.invalidate(customerStatementProvider);
    ref.invalidate(customerBalancesProvider);
  }

  Future<void> _pick({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: from ? DateTime(2020) : (_from ?? DateTime(2020)),
      lastDate: from ? (_to ?? DateTime.now()) : DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => from ? _from = picked : _to = picked);
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _refresh();
      if (mounted) showTopSnackBar(context, SnackBar(content: Text(done)));
    } catch (e, st) {
      AppLogger.error('customers.action', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _entry(String kind) async {
    final r = await showDialog<_EntryInput>(
      context: context,
      builder: (_) => _EntryDialog(kind: kind),
    );
    if (r == null) return;
    final repo = ref.read(customersRepositoryProvider);
    await _run(
      () => repo.addEntry(
        clientId: widget.clientId,
        kind: kind,
        amount: r.amount,
        // collect / pay go through the pocket of their book; an opening
        // names its book only
        pocket: kind == 'opening' ? null : r.pocket,
        book: r.pocket,
        note: r.note,
        requestId: newRequestId(),
      ),
      switch (kind) {
        'collect' => 'سُجّل التحصيل: ${_lyd(r.amount)}',
        'pay' => 'سُجّل السداد: ${_lyd(r.amount)}',
        _ => 'سُجّل الرصيد الافتتاحي.',
      },
    );
  }

  Future<void> _editLimit() async {
    final r = await showDialog<({double? limit})>(
      context: context,
      builder: (_) => _LimitDialog(current: _limit),
    );
    if (r == null) return;
    await _run(
      () async {
        await ref
            .read(customersRepositoryProvider)
            .setLimit(widget.clientId, r.limit);
        if (mounted) setState(() => _limit = r.limit);
      },
      r.limit == null
          ? 'أُلغي حد الدين: لا بيع بالآجل لهذا العميل.'
          : 'حد الدين: ${_lyd(r.limit!)}',
    );
  }

  Future<void> _exportPdf(CustomerStatement s, DateTimeRange range) async {
    try {
      final user = ref.read(supabaseClientProvider).auth.currentUser;
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      final by = ((meta['full_name'] ?? meta['name']) as String?)?.trim();
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildCustomerStatement(
        customer: widget.title,
        creditLimit: _limit,
        statement: s,
        start: range.start,
        end: range.end,
        exportedBy: (by == null || by.isEmpty) ? user?.email : by,
      );
      await PdfExport.sharePdf(
        bytes,
        pdfFileName(
          'كشف حساب عميل',
          who: widget.title,
          start: range.start,
          end: range.end,
        ),
      );
    } catch (e, st) {
      AppLogger.error('customers.exportPdf', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final async = ref.watch(customerStatementProvider(key));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('customer-pdf'),
            tooltip: 'تصدير PDF',
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 15),
            onPressed: async.valueOrNull == null
                ? null
                : () => _exportPdf(async.valueOrNull!, key.range),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
        children: [
          async.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(
              friendlyError(e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.negative),
            ),
            data: (s) => GlassCard(
              child: Column(
                children: [
                  Text(
                    customerBalanceLabel(s.closing, formatMoney),
                    key: const ValueKey('customer-balance'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: balanceColor(s.closing),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _limit == null
                        ? 'بلا حد دين: لا بيع بالآجل له'
                        : 'حد الدين ${_lyd(_limit!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textLow,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final b in const [null, 'cash', 'bank'])
                ChoiceChip(
                  key: ValueKey('customer-book-${b ?? 'all'}'),
                  label: Text(switch (b) {
                    'cash' => 'نقدي',
                    'bank' => 'مصرفي',
                    _ => 'الدفتران',
                  }),
                  selected: _book == b,
                  onSelected: (_) => setState(() => _book = b),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Action(
                key: const ValueKey('customer-collect'),
                icon: FontAwesomeIcons.handHoldingDollar,
                label: 'تحصيل منه',
                color: AppColors.positive,
                onTap: () => _entry('collect'),
              ),
              _Action(
                key: const ValueKey('customer-pay'),
                icon: FontAwesomeIcons.moneyBillTransfer,
                label: 'سداد له',
                color: AppColors.negative,
                onTap: () => _entry('pay'),
              ),
              _Action(
                key: const ValueKey('customer-opening'),
                icon: FontAwesomeIcons.flagCheckered,
                label: 'رصيد افتتاحي',
                color: AppColors.accent,
                onTap: () => _entry('opening'),
              ),
              _Action(
                key: const ValueKey('customer-limit'),
                icon: FontAwesomeIcons.gaugeHigh,
                label: 'حد الدين',
                color: AppColors.warning,
                onTap: _editLimit,
              ),
            ],
          ),
          const SizedBox(height: 16),
          DateFilterBar(
            mode: _mode,
            from: _from,
            to: _to,
            onModeChanged: (m) => setState(() {
              _mode = m;
              if (m == DateFilterMode.today) {
                _from = null;
                _to = null;
              } else {
                _from ??= todayDate();
                _to ??= todayDate();
              }
            }),
            onPickFrom: () => _pick(from: true),
            onPickTo: () => _pick(from: false),
            showInvalidHint: _mode == DateFilterMode.range && !_rangeReady,
          ),
          const SizedBox(height: 10),
          ...async.when(
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const <Widget>[],
            error: (_, __) => const <Widget>[],
            data: (s) => _lines(s),
          ),
        ],
      ),
    );
  }

  List<Widget> _lines(CustomerStatement s) {
    final running = s.running;
    return [
      _Line(
        title: 'الرصيد قبل الفترة',
        amount: null,
        balance: s.opening,
      ),
      if (s.entries.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'لا حركة في هذه الفترة',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textLow),
          ),
        ),
      for (var i = 0; i < s.entries.length; i++)
        _Line(
          title: _describe(s.entries[i]),
          subtitle: _when.format(s.entries[i].createdAt),
          amount: s.entries[i].amount,
          balance: running[i],
        ),
    ];
  }

  String _describe(CustomerEntry e) {
    final parts = <String>[e.label];
    if ((e.reference ?? '').isNotEmpty) parts.add(e.reference!);
    if (e.usd != null && e.rate != null) {
      parts.add('\$${formatMoney(e.usd!)} × ${formatRate(e.rate!)}');
    }
    if (e.pocket != null) parts.add(lydMethodLabel(e.pocket));
    if ((e.note ?? '').isNotEmpty) parts.add(e.note!);
    return parts.join(' · ');
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.title,
    this.subtitle,
    required this.amount,
    required this.balance,
  });
  final String title;
  final String? subtitle;
  final double? amount;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final a = amount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textLow,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (a != null)
                  Text(
                    '${a > 0 ? '+' : '−'}${formatMoney(a.abs())}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: a > 0 ? AppColors.positive : AppColors.negative,
                    ),
                  ),
                Text(
                  customerBalanceLabel(balance, formatMoney),
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMid),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: FaIcon(icon, size: 13, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
    );
  }
}

typedef _EntryInput = ({double amount, String? pocket, String? note});

/// The amount of a collection / payment (with the box or the bank), or of an
/// opening balance (with who owes whom).
class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.kind});
  final String kind;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _pocket = kLydCash;
  bool _theyOwe = true;
  String? _error;

  bool get _opening => widget.kind == 'opening';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseMoney(_amount.text);
    if (v <= 0) {
      setState(() => _error = 'اكتب المبلغ بالدينار.');
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop<_EntryInput>((
      amount: _opening ? (_theyOwe ? v : -v) : v,
      // the book: for collect / pay also the pocket the dinars go through
      pocket: _pocket,
      note: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        switch (widget.kind) {
          'collect' => 'تحصيل من العميل',
          'pay' => 'سداد للعميل',
          _ => 'رصيد افتتاحي',
        },
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('customer-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ (د.ل)',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            if (_opening)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('لنا عليه')),
                  ButtonSegment(value: false, label: Text('علينا له')),
                ],
                selected: {_theyOwe},
                onSelectionChanged: (s) => setState(() => _theyOwe = s.first),
              ),
            if (_opening) const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const ValueKey('customer-entry-book'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: kLydCash, label: Text('نقدي (الصندوق)')),
                ButtonSegment(value: kLydBank, label: Text('مصرفي (المصرف)')),
              ],
              selected: {_pocket},
              onSelectionChanged: (s) => setState(() => _pocket = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
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
          key: const ValueKey('customer-amount-save'),
          onPressed: _save,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _LimitDialog extends StatefulWidget {
  const _LimitDialog({required this.current});
  final double? current;

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final _limit = TextEditingController(
    text: widget.current == null ? '' : formatMoney(widget.current!),
  );

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حد الدين'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('customer-limit-value'),
            controller: _limit,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'أقصى دين مسموح (د.ل)',
              helperText: 'اتركه فارغًا: لا بيع بالآجل لهذا العميل',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('customer-limit-save'),
          onPressed: () {
            final t = _limit.text.trim();
            Navigator.of(context).pop<({double? limit})>(
              (limit: t.isEmpty ? null : parseMoney(t)),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
