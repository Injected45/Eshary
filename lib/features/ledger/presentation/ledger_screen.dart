import 'dart:typed_data';

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
import '../../../shared/top_message.dart';
import '../../archive/presentation/archive_filters.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger.dart';

/// Which books a statement shows (0093): one book, or both (null) with the
/// bank dinars converted into cash ones at [factor].
typedef LedgerScope = ({String? book, double factor});

final incomeStatementProvider = FutureProvider.autoDispose
    .family<IncomeStatement, (DateTimeRange, LedgerScope)>((ref, k) {
  return ref.watch(ledgerRepositoryProvider).incomeStatement(
        k.$1.start,
        k.$1.end,
        book: k.$2.book,
        factor: k.$2.factor,
      );
});

final balanceSheetProvider = FutureProvider.autoDispose
    .family<BalanceSheet, (DateTime, LedgerScope)>((ref, k) {
  return ref
      .watch(ledgerRepositoryProvider)
      .balanceSheet(k.$1, book: k.$2.book, factor: k.$2.factor);
});

final trialBalanceProvider = FutureProvider.autoDispose
    .family<List<TrialLine>, (DateTime, LedgerScope)>((ref, k) {
  return ref
      .watch(ledgerRepositoryProvider)
      .trialBalance(k.$1, book: k.$2.book, factor: k.$2.factor);
});

final journalProvider = FutureProvider.autoDispose
    .family<Journal, (DateTimeRange, LedgerScope)>((ref, k) {
  return ref
      .watch(ledgerRepositoryProvider)
      .journal(k.$1.start, k.$1.end, book: k.$2.book);
});

final periodClosesProvider =
    FutureProvider.autoDispose<List<PeriodClose>>((ref) {
  return ref.watch(ledgerRepositoryProvider).closes();
});

String _lyd(double v) => '${formatMoney(v)} د.ل';
String _signed(double v) =>
    v < 0 ? '−${formatMoney(-v)} د.ل' : '${formatMoney(v)} د.ل';
Color _tone(double v) => v > 0.005
    ? AppColors.positive
    : (v < -0.005 ? AppColors.negative : AppColors.textMid);

enum _Tab { income, balance, trial, journal, closes }

/// «الحسابات الختامية» (migration 0092): the income statement, the balance
/// sheet, the trial balance and the journal, all in dinars, and the period
/// closes. Administrator only.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  _Tab _tab = _Tab.income;

  /// The book shown (0093): null = both, the bank converted at [_factor].
  String? _book;
  final _factorText = TextEditingController(text: '1');
  double get _factor {
    final f = parseRate(_factorText.text);
    return f > 0 ? f : 1;
  }

  LedgerScope get _scope => (book: _book, factor: _book == null ? _factor : 1);

  @override
  void dispose() {
    _factorText.dispose();
    super.dispose();
  }

  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;

  bool get _rangeReady => _from != null && _to != null && !_from!.isAfter(_to!);

  DateTimeRange get _range {
    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);
    return DateTimeRange(start: r.start, end: r.end);
  }

  /// "Now" for the statements, fixed when the screen opens (or is refreshed):
  /// a new moment on every build would ask the server again and again.
  DateTime _now = DateTime.now();

  /// The end of the period, never later than [_now].
  DateTime get _at => _range.end.isAfter(_now) ? _now : _range.end;

  void _refresh() {
    setState(() => _now = DateTime.now());
    ref.invalidate(incomeStatementProvider);
    ref.invalidate(balanceSheetProvider);
    ref.invalidate(trialBalanceProvider);
    ref.invalidate(journalProvider);
    ref.invalidate(periodClosesProvider);
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

  String? _exportedBy() {
    final user = ref.read(supabaseClientProvider).auth.currentUser;
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    final name = ((meta['full_name'] ?? meta['name']) as String?)?.trim();
    return (name == null || name.isEmpty) ? user?.email : name;
  }

  Future<void> _share(
    Future<Uint8List> Function(PdfExport) build,
    String title,
    DateTimeRange range,
  ) async {
    try {
      final pdf = await PdfExport.load();
      final bytes = await build(pdf);
      await PdfExport.sharePdf(
        bytes,
        pdfFileName(title, start: range.start, end: range.end),
      );
    } catch (e, st) {
      AppLogger.error('ledger.exportPdf', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _closePeriod() async {
    // at least five minutes back (the database refuses later): a save still
    // in flight is never cut in two
    final latest = DateTime.now().subtract(const Duration(minutes: 5));
    final at = _range.end.isAfter(latest) ? latest : _range.end;
    final when = LibyaDateFormat('yyyy/MM/dd HH:mm').format(at);
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إقفال الفترة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'يُختم ميزان المراجعة حتى $when. '
              'إذا تغيّر شيء قبل هذا الوقت لاحقًا (باسترجاع نسخة مثلًا) '
              'يظهر الإقفال «غير مطابق».',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const ValueKey('close-period-ok'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('إقفال'),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    try {
      final net = await ref
          .read(ledgerRepositoryProvider)
          .closePeriod(at, note: text.isEmpty ? null : text);
      ref.invalidate(periodClosesProvider);
      if (mounted) {
        showTopSnackBar(
          context,
          SnackBar(content: Text('أُقفلت الفترة. صافي الربح: ${_signed(net)}')),
        );
      }
    } catch (e, st) {
      AppLogger.error('ledger.close', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('الحسابات الختامية'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: _refresh,
          ),
          if (_tab != _Tab.journal && _tab != _Tab.closes)
            IconButton(
              key: const ValueKey('ledger-pdf'),
              tooltip: 'تصدير PDF',
              icon: const FaIcon(FontAwesomeIcons.filePdf, size: 15),
              onPressed: _exportCurrent,
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, contentBottomPadding(context)),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final t in _Tab.values)
                ChoiceChip(
                  key: ValueKey('ledger-tab-${t.name}'),
                  label: Text(switch (t) {
                    _Tab.income => 'قائمة الدخل',
                    _Tab.balance => 'الميزانية',
                    _Tab.trial => 'ميزان المراجعة',
                    _Tab.journal => 'دفتر اليومية',
                    _Tab.closes => 'الإقفالات',
                  }),
                  selected: _tab == t,
                  onSelected: (_) => setState(() => _tab = t),
                ),
            ],
          ),
          if (_tab != _Tab.closes) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final b in const [null, 'cash', 'bank'])
                  ChoiceChip(
                    key: ValueKey('ledger-book-${b ?? 'all'}'),
                    label: Text(switch (b) {
                      'cash' => 'النقدي',
                      'bank' => 'المصرفي',
                      _ => 'المجموع',
                    }),
                    selected: _book == b,
                    onSelected: (_) => setState(() => _book = b),
                  ),
              ],
            ),
            if (_book == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  key: const ValueKey('ledger-factor'),
                  controller: _factorText,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'سعر التسييل: الدينار المصرفي = كم دينار نقدي',
                    helperText:
                        'يُحوَّل المصرفي إلى نقدي بهذا السعر في المجموع',
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          if (_tab != _Tab.closes) ...[
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
            if (_tab == _Tab.balance || _tab == _Tab.trial)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'كما في ${LibyaDateFormat('yyyy/MM/dd HH:mm').format(_at)}',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textLow),
                ),
              ),
            const SizedBox(height: 12),
          ],
          ...switch (_tab) {
            _Tab.income => _income(range),
            _Tab.balance => _balance(),
            _Tab.trial => _trial(),
            _Tab.journal => _journal(range),
            _Tab.closes => _closes(),
          },
        ],
      ),
    );
  }

  Future<void> _exportCurrent() async {
    final range = _range;
    final by = _exportedBy();
    switch (_tab) {
      case _Tab.income:
        final s =
            await ref.read(incomeStatementProvider((range, _scope)).future);
        await _share(
          (pdf) => pdf.buildIncomeStatement(
            statement: s,
            start: range.start,
            end: range.end,
            exportedBy: by,
          ),
          'قائمة الدخل',
          range,
        );
      case _Tab.balance:
        final s = await ref.read(balanceSheetProvider((_at, _scope)).future);
        await _share(
          (pdf) => pdf.buildBalanceSheet(sheet: s, at: _at, exportedBy: by),
          'الميزانية',
          range,
        );
      case _Tab.trial:
        final s = await ref.read(trialBalanceProvider((_at, _scope)).future);
        await _share(
          (pdf) => pdf.buildTrialBalance(lines: s, at: _at, exportedBy: by),
          'ميزان المراجعة',
          range,
        );
      case _Tab.journal:
      case _Tab.closes:
        break;
    }
  }

  List<Widget> _loading<T>(
    AsyncValue<T> async,
    List<Widget> Function(T) data,
  ) =>
      async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const [LinearProgressIndicator()],
        error: (e, _) => [
          Text(
            friendlyError(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.negative),
          ),
        ],
        data: data,
      );

  List<Widget> _income(DateTimeRange range) =>
      _loading(ref.watch(incomeStatementProvider((range, _scope))), (s) {
        return [
          GlassCard(
            child: Column(
              children: [
                const Text(
                  'صافي الربح',
                  style: TextStyle(fontSize: 12, color: AppColors.textMid),
                ),
                const SizedBox(height: 4),
                Text(
                  _signed(s.net),
                  key: const ValueKey('ledger-net'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _tone(s.net),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section('الإيرادات', [
            for (final l in s.income) _Row(l.name, _lyd(l.amount)),
            if (s.income.isEmpty) const _Row('لا شيء', ''),
          ]),
          const SizedBox(height: 10),
          _Section('المصروفات والخسائر', [
            for (final l in s.expenses) _Row(l.name, _lyd(-l.amount)),
            if (s.expenses.isEmpty) const _Row('لا شيء', ''),
          ]),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              '«نتيجة بيع العملة» = ما قبضته من البيع ناقص تكلفة الدولار '
              'المباع. تكلفة دولار حسابات لم تُحدَّد تكلفتها لا تدخل هنا.',
              style: TextStyle(fontSize: 11, color: AppColors.textLow),
            ),
          ),
        ];
      });

  List<Widget> _balance() =>
      _loading(ref.watch(balanceSheetProvider((_at, _scope))), (b) {
        final balanced =
            (b.totalAssets - b.totalLiabilitiesAndEquity).abs() < 0.01;
        return [
          _Section('الأصول', [
            _Row('الصندوق', _lyd(b.cash)),
            _Row('المصرف', _lyd(b.bank)),
            _Row('ذمم العملاء (لنا عليهم)', _lyd(b.receivable)),
            _Row('الدولار بالتكلفة', _lyd(b.dollarsAtCost)),
            if (b.unvalued.abs() >= 0.005)
              _Row('دولار غير مقيّم', _lyd(b.unvalued)),
            _Row('مجموع الأصول', _lyd(b.totalAssets), bold: true),
          ]),
          const SizedBox(height: 10),
          _Section('الالتزامات وحقوق الملكية', [
            _Row('ذمم دائنة (علينا للبائعين)', _lyd(b.payable)),
            _Row('رأس المال والأرصدة الافتتاحية', _lyd(b.capital)),
            if (b.revaluation.abs() >= 0.005)
              _Row('إعادة تقييم التكلفة', _signed(b.revaluation)),
            if (b.outsideTreasury.abs() >= 0.005)
              _Row('نقدية خارج خزينة الدينار', _signed(b.outsideTreasury)),
            _Row('الأرباح حتى التاريخ', _signed(b.profitToDate)),
            _Row(
              'المجموع',
              _lyd(b.totalLiabilitiesAndEquity),
              bold: true,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              balanced ? 'الميزانية متوازنة ✓' : 'الميزانية غير متوازنة!',
              key: const ValueKey('ledger-balanced'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: balanced ? AppColors.positive : AppColors.negative,
              ),
            ),
          ),
          _Section('الدولار في كل حساب: الدفتر مقابل الرصيد × التكلفة', [
            for (final i in b.inventory)
              _Row(
                '${i.companyName} / ${i.accountName}',
                i.bookValue == null
                    ? 'بلا تكلفة'
                    : '${_lyd(i.ledgerValue)}'
                        '${(i.difference ?? 0).abs() >= 0.01 ? '  (فرق ${_signed(i.difference!)})' : ''}',
              ),
          ]),
        ];
      });

  List<Widget> _trial() =>
      _loading(ref.watch(trialBalanceProvider((_at, _scope))), (lines) {
        final t = trialTotals(lines);
        return [
          _Section('ميزان المراجعة', [
            for (final l in lines)
              _Row(
                '${l.account}  ${l.name}',
                l.balance >= 0
                    ? 'مدين ${formatMoney(l.balance)}'
                    : 'دائن ${formatMoney(-l.balance)}',
              ),
            _Row('مجموع المدين', formatMoney(t.debit), bold: true),
            _Row('مجموع الدائن', formatMoney(t.credit), bold: true),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t.debit == t.credit ? 'متوازن ✓' : 'غير متوازن!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: t.debit == t.credit
                    ? AppColors.positive
                    : AppColors.negative,
              ),
            ),
          ),
        ];
      });

  List<Widget> _journal(DateTimeRange range) =>
      _loading(ref.watch(journalProvider((range, _scope))), (j) {
        final groups = <String, List<JournalLine>>{};
        for (final l in j.lines) {
          groups
              .putIfAbsent(
                '${l.sourceId}|${l.at.toIso8601String()}|${l.source}',
                () => [],
              )
              .add(l);
        }
        final when = LibyaDateFormat('yyyy/MM/dd HH:mm');
        return [
          if (j.cut)
            Text(
              'يظهر أول ${j.lines.length} سطر من ${j.total}. ضيّق الفترة لترى البقية.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لا قيود في هذه الفترة',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textLow),
              ),
            ),
          for (final g in groups.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      [
                        g.first.sourceLabel,
                        if ((g.first.ref ?? '').isNotEmpty) g.first.ref!,
                        if ((g.first.exchange ?? '').isNotEmpty)
                          g.first.exchange!,
                        if ((g.first.client ?? '').isNotEmpty) g.first.client!,
                        when.format(g.first.at),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final l in g)
                      _Row(
                        l.amount > 0
                            ? 'من حـ/ ${l.name}'
                            : '   إلى حـ/ ${l.name}',
                        formatMoney(l.amount.abs()),
                      ),
                  ],
                ),
              ),
            ),
        ];
      });

  List<Widget> _closes() => [
        FilledButton.icon(
          key: const ValueKey('close-period'),
          onPressed: _closePeriod,
          icon: const FaIcon(FontAwesomeIcons.lock, size: 13),
          label: const Text('إقفال الفترة حتى نهاية المدة المختارة'),
        ),
        const SizedBox(height: 12),
        ..._loading(ref.watch(periodClosesProvider), (all) {
          final when = LibyaDateFormat('yyyy/MM/dd HH:mm');
          return [
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'لم تُقفل أي فترة بعد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textLow),
                ),
              ),
            for (final c in all)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text('حتى ${when.format(c.periodEnd)}'),
                    subtitle: Text(
                      [
                        'صافي الربح ${_signed(c.netProfit)}',
                        if ((c.closedBy ?? '').isNotEmpty) c.closedBy!,
                        if ((c.note ?? '').isNotEmpty) c.note!,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      c.intact ? 'مطابق ✓' : 'غير مطابق!',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:
                            c.intact ? AppColors.positive : AppColors.negative,
                      ),
                    ),
                  ),
                ),
              ),
          ];
        }),
      ];
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const Divider(height: 14),
          ...rows,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
