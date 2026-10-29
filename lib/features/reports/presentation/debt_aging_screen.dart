import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../customers/presentation/customer_statement_screen.dart';
import '../data/reports_repository.dart';
import '../domain/reports.dart';
import 'report_pdf.dart';
import 'report_widgets.dart';

enum DebtSide { ours, theirs }

/// The follow-up filters.
enum DebtFilter { all, late30, late90, overLimit, noSettle30 }

enum DebtSort { amount, oldest, waiting, name }

const _filterLabels = {
  DebtFilter.all: 'الكل',
  DebtFilter.late30: 'متأخر +30 يومًا',
  DebtFilter.late90: 'متأخر +90 يومًا',
  DebtFilter.overLimit: 'تجاوز الحد',
  DebtFilter.noSettle30: 'بلا تحصيل منذ 30 يومًا',
};

const _sortLabels = {
  DebtSort.amount: 'الأكبر قيمة',
  DebtSort.oldest: 'الأقدم دينًا',
  DebtSort.waiting: 'الأطول انتظارًا',
  DebtSort.name: 'الاسم',
};

/// The rows of [side] that pass [filter] and [search], in [sort] order.
List<DebtRow> debtView(
  DebtAging a, {
  required DebtSide side,
  DebtFilter filter = DebtFilter.all,
  DebtSort sort = DebtSort.amount,
  String search = '',
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final s = search.trim().toLowerCase();
  final rows = (side == DebtSide.ours ? a.debtors : a.creditors).where((r) {
    if (s.isNotEmpty &&
        !'${r.name} ${r.company ?? ''} ${r.code ?? ''}'
            .toLowerCase()
            .contains(s)) {
      return false;
    }
    return switch (filter) {
      DebtFilter.all => true,
      DebtFilter.late30 => r.late30 > 0.005,
      DebtFilter.late90 => r.older > 0.005,
      DebtFilter.overLimit => r.overLimit,
      DebtFilter.noSettle30 => (r.daysWaiting(at) ?? 0) > 30,
    };
  }).toList();
  int byDate(DateTime? x, DateTime? y) =>
      (x ?? at).compareTo(y ?? at); // the earliest first
  rows.sort(switch (sort) {
    DebtSort.amount => (x, y) => y.owed.compareTo(x.owed),
    DebtSort.oldest => (x, y) => byDate(x.oldest, y.oldest),
    DebtSort.waiting => (x, y) =>
        (y.daysWaiting(at) ?? 0).compareTo(x.daysWaiting(at) ?? 0),
    DebtSort.name => (x, y) => x.name.compareTo(y.name),
  });
  return rows;
}

/// «كشف المديونيات»: the names of who owes us and whom we owe, with the
/// amounts (cash / bank), the age of the debt, the last collection or
/// payment and how long ago — with filters to follow them up. A tap opens
/// the customer's statement (collect / pay from there).
class DebtAgingScreen extends ConsumerStatefulWidget {
  const DebtAgingScreen({super.key});

  @override
  ConsumerState<DebtAgingScreen> createState() => _DebtAgingScreenState();
}

class _DebtAgingScreenState extends ConsumerState<DebtAgingScreen> {
  DebtSide _side = DebtSide.ours;
  DebtFilter _filter = DebtFilter.all;
  DebtSort _sort = DebtSort.amount;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(debtAgingProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('كشف المديونيات'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'PDF',
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 15),
            onPressed: async.valueOrNull == null
                ? null
                : () => exportDebtAgingPdf(context, ref, aging: async.value!),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(debtAgingProvider),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const LinearProgressIndicator(),
        error: (e, _) =>
            ReportMessage(friendlyError(e), color: AppColors.negative),
        data: (a) => _body(context, a),
      ),
    );
  }

  Widget _body(BuildContext context, DebtAging a) {
    final ours = _side == DebtSide.ours;
    final rows = debtView(
      a,
      side: _side,
      filter: _filter,
      sort: _sort,
      search: _search.text,
    );
    final shownTotal = rows.fold<double>(0, (s, r) => s + r.owed);
    final sideRows = ours ? a.debtors : a.creditors;
    final late30 = sideRows.fold<double>(0, (s, r) => s + r.late30);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, contentBottomPadding(context)),
      children: [
        ReportTileRow([
          ReportTile(
            label: 'لنا على العملاء',
            value: lydText(a.owedToUs),
            sub: '${a.debtors.length} عميل',
            color: AppColors.positive,
          ),
          ReportTile(
            label: 'علينا للدائنين',
            value: lydText(a.weOwe),
            sub: '${a.creditors.length} جهة',
            color: AppColors.negative,
          ),
        ]),
        ReportTileRow([
          ReportTile(
            label: 'الصافي (لنا − علينا)',
            value: signedLydText(a.net),
            color: signedColor(a.net),
          ),
          ReportTile(
            label:
                ours ? 'متأخر أكثر من 30 يومًا' : 'علينا منذ أكثر من 30 يومًا',
            value: lydText(late30),
            color: late30 > 0 ? AppColors.warning : null,
            sub: ours && a.overLimit > 0 ? '${a.overLimit} تجاوز الحد' : null,
          ),
        ]),
        const SizedBox(height: 4),
        SegmentedButton<DebtSide>(
          segments: [
            ButtonSegment(
              value: DebtSide.ours,
              label: Text('لنا (${a.debtors.length})'),
            ),
            ButtonSegment(
              value: DebtSide.theirs,
              label: Text('علينا (${a.creditors.length})'),
            ),
          ],
          selected: {_side},
          onSelectionChanged: (s) => setState(() {
            _side = s.first;
            if (_side == DebtSide.theirs && _filter == DebtFilter.overLimit) {
              _filter = DebtFilter.all;
            }
          }),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('debts-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: 'بحث بالاسم أو الشركة أو الكود',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in DebtFilter.values)
              if (ours || f != DebtFilter.overLimit)
                ChoiceChip(
                  label: Text(
                    f == DebtFilter.noSettle30 && !ours
                        ? 'بلا سداد منذ 30 يومًا'
                        : _filterLabels[f]!,
                  ),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  labelStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text(
              'الترتيب:',
              style: TextStyle(fontSize: 12, color: AppColors.textLow),
            ),
            const SizedBox(width: 8),
            DropdownButton<DebtSort>(
              value: _sort,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in DebtSort.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text(
                      _sortLabels[s]!,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: (s) => setState(() => _sort = s ?? _sort),
            ),
            const Spacer(),
            Text(
              '${rows.length} · ${lydText(shownTotal)}',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMid,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          ReportMessage(
            sideRows.isEmpty
                ? (ours ? 'لا يوجد عميل مدين.' : 'لا يوجد دائن.')
                : 'لا أحد يطابق هذا البحث أو الفلتر.',
          )
        else
          for (final r in rows) _DebtCard(row: r, ours: ours),
      ],
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.row, required this.ours});
  final DebtRow row;
  final bool ours;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final f = DateFormat('yyyy/MM/dd');
    final waiting = r.daysWaiting(DateTime.now());
    final settleWord = ours ? 'آخر تحصيل' : 'آخر سداد';
    final ages = [
      if (r.d7 > 0.005) 'حتى 7 أيام ${formatMoney(r.d7)}',
      if (r.d30 > 0.005) '8–30 يومًا ${formatMoney(r.d30)}',
      if (r.d90 > 0.005) '31–90 يومًا ${formatMoney(r.d90)}',
      if (r.older > 0.005) 'أكثر من 90 ${formatMoney(r.older)}',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CustomerStatementScreen(
            clientId: r.clientId,
            title: r.name,
            creditLimit: r.limit,
          ),
        ),
      ),
      child: ReportCard(children: [
        Row(
          children: [
            Expanded(
              child: Text(
                r.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              lydText(r.owed),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: r.overLimit
                    ? AppColors.negative
                    : (ours ? AppColors.positive : AppColors.textHigh),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'نقدي ${formatMoney(r.cash)} · مصرفي ${formatMoney(r.bank)}',
          style: const TextStyle(fontSize: 12, color: AppColors.textLow),
        ),
        if (ages.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            ages.join('  ·  '),
            style: TextStyle(
              fontSize: 12,
              color: r.older > 0.005
                  ? AppColors.negative
                  : (r.d90 > 0.005 ? AppColors.warning : AppColors.textMid),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                r.lastSettle == null
                    ? (ours ? 'لم يُحصَّل منه شيء بعد' : 'لم نسدد له شيئًا بعد')
                    : '$settleWord ${f.format(r.lastSettle!)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMid),
              ),
            ),
            if (waiting != null)
              Text(
                'منذ $waiting يوم',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: waiting > 30 ? AppColors.warning : AppColors.textMid,
                ),
              ),
          ],
        ),
        if (r.overLimit)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              r.limit == null || r.limit == 0
                  ? 'تجاوز الحد: لا حد دين له'
                  : 'تجاوز حد الدين (${formatMoney(r.limit!)} د.ل)',
              style: const TextStyle(fontSize: 12, color: AppColors.negative),
            ),
          ),
      ]),
    );
  }
}
