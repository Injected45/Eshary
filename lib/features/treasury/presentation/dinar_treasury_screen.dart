import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/libya_time.dart';
import '../../../shared/logger.dart';
import '../../../shared/top_message.dart';
import '../../archive/presentation/archive_filters.dart';
import '../data/treasury_repository.dart';
import '../domain/lyd_treasury.dart';
import 'treasury_providers.dart';

final LibyaDateFormat _when = LibyaDateFormat('yyyy/MM/dd  HH:mm');

String _lyd(double v) => '${formatMoney(v)} د.ل';

/// The dinar treasury (migration 0086): the cash box and the bank. Exits paid
/// in dinars add to them, entries take from them; deposits, withdrawals and
/// transfers between the two are typed here, and the box is counted at the end
/// of the day. Administrator only.
class DinarTreasuryScreen extends ConsumerStatefulWidget {
  const DinarTreasuryScreen({super.key});

  @override
  ConsumerState<DinarTreasuryScreen> createState() =>
      _DinarTreasuryScreenState();
}

class _DinarTreasuryScreenState extends ConsumerState<DinarTreasuryScreen> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;

  bool get _rangeReady => _from != null && _to != null && !_from!.isAfter(_to!);

  DateTimeRange get _range {
    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);
    return DateTimeRange(start: r.start, end: r.end);
  }

  void _refresh() => ref.invalidate(lydSummaryProvider);

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

  /// Runs [action] (a call to the database), then refreshes; shows [done] or
  /// the error.
  Future<bool> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _refresh();
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(done)));
      }
      return true;
    } catch (e, st) {
      AppLogger.error('dinarTreasury', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lydSummaryProvider(_range));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('خزينة الدينار'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: _refresh,
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            friendlyError(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.negative),
          ),
        ),
        data: (s) => ListView(
          padding:
              EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
          children: s.open ? _openBody(s) : [_OpeningCard(onOpen: _open)],
        ),
      ),
    );
  }

  Future<void> _open(double cash, double bank) async {
    await _run(
      () =>
          ref.read(treasuryRepositoryProvider).lydOpen(cash: cash, bank: bank),
      'فُتحت خزينة الدينار.',
    );
  }

  List<Widget> _openBody(LydSummary s) => [
        _BalancesCard(summary: s),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _ActionButton(
              key: const ValueKey('lyd-deposit'),
              icon: FontAwesomeIcons.circlePlus,
              label: 'إيداع',
              color: AppColors.positive,
              onTap: () => _move(deposit: true),
            ),
            _ActionButton(
              key: const ValueKey('lyd-withdraw'),
              icon: FontAwesomeIcons.circleMinus,
              label: 'سحب',
              color: AppColors.negative,
              onTap: () => _move(deposit: false),
            ),
            _ActionButton(
              key: const ValueKey('lyd-transfer'),
              icon: FontAwesomeIcons.rightLeft,
              label: 'تحويل',
              color: AppColors.accent,
              onTap: _transfer,
            ),
            _ActionButton(
              key: const ValueKey('lyd-count'),
              icon: FontAwesomeIcons.calculator,
              label: 'جرد الصندوق',
              color: AppColors.warning,
              onTap: () => _count(s.cash),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _Title('حركة الفترة'),
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
        _FlowsCard(summary: s),
        if (s.movements.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final m in s.movements) _MovementTile(m: m),
        ],
        if (s.counts.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Title('آخر الجرود'),
          for (final c in s.counts) _CountTile(c: c),
        ],
      ];

  Future<void> _move({required bool deposit}) async {
    final r = await showDialog<({String pocket, double amount, String? note})>(
      context: context,
      builder: (_) => _AmountDialog(
        title: deposit ? 'إيداع دينار' : 'سحب دينار',
        withPocket: true,
      ),
    );
    if (r == null) return;
    await _run(
      () => ref.read(treasuryRepositoryProvider).lydMove(
            kind: deposit ? 'in' : 'out',
            pocket: r.pocket,
            amount: r.amount,
            note: r.note,
          ),
      deposit ? 'تم الإيداع.' : 'تم السحب.',
    );
  }

  Future<void> _transfer() async {
    final r = await showDialog<({String pocket, double amount, String? note})>(
      context: context,
      builder: (_) => const _AmountDialog(
        title: 'تحويل بين الصندوق والمصرف',
        withPocket: true,
        pocketLabels: ('من الصندوق إلى المصرف', 'من المصرف إلى الصندوق'),
      ),
    );
    if (r == null) return;
    await _run(
      () => ref.read(treasuryRepositoryProvider).lydMove(
            kind: r.pocket == 'cash' ? 'cash_to_bank' : 'bank_to_cash',
            amount: r.amount,
            note: r.note,
          ),
      'تم التحويل.',
    );
  }

  Future<void> _count(double expected) async {
    final r = await showDialog<({double counted, String? note, bool post})>(
      context: context,
      builder: (_) => _CountDialog(expected: expected),
    );
    if (r == null) return;
    await _run(
      () => ref
          .read(treasuryRepositoryProvider)
          .lydCount(counted: r.counted, note: r.note, post: r.post),
      'حُفظ الجرد.',
    );
  }
}

class _OpeningCard extends StatefulWidget {
  const _OpeningCard({required this.onOpen});
  final Future<void> Function(double cash, double bank) onOpen;

  @override
  State<_OpeningCard> createState() => _OpeningCardState();
}

class _OpeningCardState extends State<_OpeningCard> {
  final _cash = TextEditingController();
  final _bank = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _cash.dispose();
    _bank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const ValueKey('lyd-opening'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'افتتاح خزينة الدينار',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'اكتب ما في الصندوق وما في المصرف الآن بالدينار. من هذه اللحظة '
            'يضيف كل خروج ما قبضته من دينار، ويخصم كل دخول ما دفعته، حسب '
            'طريقة الدفع (نقدًا أو مصرفي). يُفتح مرة واحدة.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textLow, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('lyd-open-cash'),
            controller: _cash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'في الصندوق (د.ل)'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('lyd-open-bank'),
            controller: _bank,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'في المصرف (د.ل)'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('lyd-open-save'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await widget.onOpen(
                      parseMoney(_cash.text),
                      parseMoney(_bank.text),
                    );
                    if (mounted) setState(() => _busy = false);
                  },
            icon: const FaIcon(FontAwesomeIcons.vault, size: 12),
            label: const Text('افتتاح الخزينة'),
          ),
        ],
      ),
    );
  }
}

class _BalancesCard extends StatelessWidget {
  const _BalancesCard({required this.summary});
  final LydSummary summary;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const ValueKey('lyd-balances'),
      child: Column(
        children: [
          const Text(
            'المجموع',
            style: TextStyle(fontSize: 13, color: AppColors.textMid),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _lyd(summary.total),
              key: const ValueKey('lyd-total'),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  icon: FontAwesomeIcons.moneyBill1,
                  label: 'الصندوق',
                  value: _lyd(summary.cash),
                  valueKey: 'lyd-cash',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Figure(
                  icon: FontAwesomeIcons.buildingColumns,
                  label: 'المصرف',
                  value: _lyd(summary.bank),
                  valueKey: 'lyd-bank',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowsCard extends StatelessWidget {
  const _FlowsCard({required this.summary});
  final LydSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return GlassCard(
      child: Column(
        children: [
          _Row('قبض من البيع نقدًا', _lyd(s.salesCash), AppColors.positive),
          _Row('قبض من البيع مصرفي', _lyd(s.salesBank), AppColors.positive),
          _Row('دفع للشراء نقدًا', _lyd(s.buysCash), AppColors.negative),
          _Row('دفع للشراء مصرفي', _lyd(s.buysBank), AppColors.negative),
          const Divider(height: 16),
          _Row(
            'صافي الصندوق من العمليات',
            _lyd(s.netCash),
            s.netCash < 0 ? AppColors.negative : AppColors.positive,
          ),
          _Row(
            'صافي المصرف من العمليات',
            _lyd(s.netBank),
            s.netBank < 0 ? AppColors.negative : AppColors.positive,
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.m});
  final LydMovement m;

  @override
  Widget build(BuildContext context) {
    final color = m.isIn
        ? AppColors.positive
        : (m.isOut ? AppColors.negative : AppColors.accent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHigh,
                    ),
                  ),
                  Text(
                    [
                      _when.format(m.createdAt),
                      if ((m.note ?? '').isNotEmpty) m.note!,
                    ].join(' · '),
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.textLow),
                  ),
                ],
              ),
            ),
            Text(
              _lyd(m.amount),
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.c});
  final LydCount c;

  @override
  Widget build(BuildContext context) {
    final d = c.difference;
    final label =
        d == 0 ? 'مطابق' : (d > 0 ? 'زيادة ${_lyd(d)}' : 'عجز ${_lyd(-d)}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _when.format(c.createdAt),
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.textLow),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: d == 0
                        ? AppColors.positive
                        : (d > 0 ? AppColors.warning : AppColors.negative),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'المتوقع ${_lyd(c.expected)} · المعدود ${_lyd(c.counted)}'
              '${d != 0 && !c.posted ? ' · لم يُرحَّل الفرق' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMid),
            ),
          ],
        ),
      ),
    );
  }
}

/// An amount in dinars, with a pocket (cash / bank) and an optional note.
class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    this.withPocket = false,
    this.pocketLabels = ('الصندوق', 'المصرف'),
  });

  final String title;
  final bool withPocket;
  final (String, String) pocketLabels;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _pocket = 'cash';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = (parseMoney(_amount.text) * 100).round() / 100;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.withPocket)
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'cash',
                  label: Text(widget.pocketLabels.$1),
                ),
                ButtonSegment(
                  value: 'bank',
                  label: Text(widget.pocketLabels.$2),
                ),
              ],
              selected: {_pocket},
              onSelectionChanged: (s) => setState(() => _pocket = s.first),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('lyd-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'المبلغ (د.ل)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'البيان (اختياري)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('lyd-amount-save'),
          onPressed: amount > 0
              ? () => Navigator.of(context).pop(
                    (
                      pocket: _pocket,
                      amount: amount,
                      note:
                          _note.text.trim().isEmpty ? null : _note.text.trim(),
                    ),
                  )
              : null,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

/// The end-of-day count: what is in the box, against what should be.
class _CountDialog extends StatefulWidget {
  const _CountDialog({required this.expected});
  final double expected;

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  final _counted = TextEditingController();
  final _note = TextEditingController();
  bool _post = true;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _counted.text.trim().isNotEmpty;
    final counted = (parseMoney(_counted.text) * 100).round() / 100;
    final diff = ((counted - widget.expected) * 100).round() / 100;
    return AlertDialog(
      title: const Text('جرد الصندوق'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'المتوقع في الصندوق: ${_lyd(widget.expected)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('lyd-counted'),
            controller: _counted,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'المعدود فعلًا (د.ل)'),
            onChanged: (_) => setState(() {}),
          ),
          if (typed) ...[
            const SizedBox(height: 8),
            Text(
              diff == 0
                  ? 'مطابق'
                  : (diff > 0 ? 'زيادة ${_lyd(diff)}' : 'عجز ${_lyd(-diff)}'),
              key: const ValueKey('lyd-count-diff'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: diff == 0
                    ? AppColors.positive
                    : (diff > 0 ? AppColors.warning : AppColors.negative),
              ),
            ),
            if (diff != 0)
              CheckboxListTile(
                value: _post,
                onChanged: (v) => setState(() => _post = v ?? true),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'ترحيل الفرق إلى الصندوق',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'يصبح رصيد الصندوق مساويًا للمعدود.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('lyd-count-save'),
          onPressed: typed && counted >= 0
              ? () => Navigator.of(context).pop(
                    (
                      counted: counted,
                      note:
                          _note.text.trim().isEmpty ? null : _note.text.trim(),
                      post: _post,
                    ),
                  )
              : null,
          child: const Text('حفظ الجرد'),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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

class _Figure extends StatelessWidget {
  const _Figure({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FaIcon(icon, size: 14, color: AppColors.textLow),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textLow),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            key: ValueKey(valueKey),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMid),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
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
