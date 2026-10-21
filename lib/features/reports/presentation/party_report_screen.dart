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
import '../../clients/domain/client.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../currency_buy/presentation/currency_buys_providers.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../../transfers/domain/transfer.dart';
import '../../transfers/presentation/transfers_providers.dart';
import '../domain/party_report.dart';

/// "تقرير حسب الجهة": every operation done with one company, customer or code
/// in a period, in the same statement as the movement report.
class PartyReportScreen extends ConsumerStatefulWidget {
  const PartyReportScreen({super.key});

  @override
  ConsumerState<PartyReportScreen> createState() => _PartyReportScreenState();
}

class _PartyReportScreenState extends ConsumerState<PartyReportScreen> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;
  PartyField _field = PartyField.company;
  final _query = TextEditingController();
  final _focus = FocusNode();
  bool _exporting = false;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _rangeReady => _from != null && _to != null && !_from!.isAfter(_to!);

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: _to ?? DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _from = picked);
      if (!mounted) return;
      await _pickTo();
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: _from ?? DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _to = picked);
  }

  DateTime _stampBuy(CurrencyBuy b) => b.archivedAt ?? b.createdAt;
  DateTime _stampTransfer(Transfer t) => t.archivedAt ?? t.createdAt;

  Future<void> _export({
    required List<CurrencyBuy> buys,
    required List<Transfer> transfers,
    required DateTime start,
    required DateTime end,
    required String scopeLabel,
  }) async {
    setState(() => _exporting = true);
    try {
      final companies =
          ref.read(companiesListProvider).value ?? const <Company>[];
      final exchanges =
          ref.read(allExchangesProvider).value ?? const <Exchange>[];
      final clients = ref.read(clientsListProvider).value ?? const <Client>[];

      final user = ref.read(supabaseClientProvider).auth.currentUser;
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      final exportedBy =
          (meta['full_name'] as String?)?.trim().isNotEmpty == true
              ? meta['full_name'] as String
              : (meta['name'] as String?)?.trim().isNotEmpty == true
                  ? meta['name'] as String
                  : (user?.email ?? 'admin');

      final pdf = await PdfExport.load();
      String? notif;
      try {
        notif = (await ref.read(latestNotificationProvider.future))?.body;
      } catch (_) {
        notif = null;
      }
      final title = 'تقرير ${_field.label} ${_query.text.trim()}';
      final bytes = await pdf.buildDetailedTransfersReport(
        buys: buys,
        transfers: transfers,
        companyById: {for (final c in companies) c.id: c},
        exchangeById: {for (final e in exchanges) e.id: e},
        clientById: {for (final c in clients) c.id: c},
        start: start,
        end: end,
        title: 'تقرير المعاملات مع ${_field.label}: ${_query.text.trim()}',
        scopeLabel: scopeLabel,
        exportedBy: exportedBy,
        notificationText: notif,
      );
      await PdfExport.sharePdf(
        bytes,
        pdfFileName(title, start: start, end: end),
      );
    } catch (e, st) {
      AppLogger.error('partyReport.export', e, st);
      if (mounted) {
        showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allBuys =
        ref.watch(archivedBuysProvider).value ?? const <CurrencyBuy>[];
    final allTransfers =
        ref.watch(archivedTransfersProvider).value ?? const <Transfer>[];
    final clients = ref.watch(clientsListProvider).value ?? const <Client>[];
    final clientById = {for (final c in clients) c.id: c};
    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);

    final options = partyValues(
      _field,
      buys: allBuys,
      transfers: allTransfers,
      clientById: clientById,
    );

    final asked = _query.text.trim();
    final found = operationsOfParty(
      field: _field,
      query: asked,
      buys: allBuys.where((b) => inDateRange(_stampBuy(b), r.start, r.end)),
      transfers: allTransfers
          .where((t) => inDateRange(_stampTransfer(t), r.start, r.end)),
      clientById: clientById,
    );
    final buys = [...found.buys]
      ..sort((a, b) => _stampBuy(a).compareTo(_stampBuy(b)));
    final transfers = [...found.transfers]
      ..sort((a, b) => _stampTransfer(a).compareTo(_stampTransfer(b)));
    final hasAny = buys.isNotEmpty || transfers.isNotEmpty;

    // Like the movement report: a cancelled operation stays on its side and
    // its reversing entry is counted on the other.
    final incomeTotal = buys.fold<double>(0, (s, b) => s + b.usdAmount) +
        transfers.where((t) => t.isCancelled).fold<double>(
              0,
              (s, t) => s + t.amount,
            );
    final outgoingTotal = transfers.fold<double>(0, (s, t) => s + t.amount) +
        buys.where((b) => b.isCancelled).fold<double>(
              0,
              (s, b) => s + b.usdAmount,
            );
    final net = incomeTotal - outgoingTotal;
    final scopeLabel = 'الجهة: ${_field.label} — $asked';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('تقرير حسب الجهة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('party-report-pdf'),
            tooltip: 'تصدير PDF',
            onPressed: (hasAny && !_exporting)
                ? () => _export(
                      buys: buys,
                      transfers: transfers,
                      start: r.start,
                      end: r.end,
                      scopeLabel: scopeLabel,
                    )
                : null,
            icon: const FaIcon(FontAwesomeIcons.filePdf, size: 16),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<PartyField>(
                  key: const ValueKey('party-report-field'),
                  segments: [
                    for (final f in PartyField.values)
                      ButtonSegment(value: f, label: Text(f.label)),
                  ],
                  selected: {_field},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _field = s.first;
                    _query.clear();
                  }),
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  // a new field starts a new box
                  key: ValueKey('party-report-query-${_field.name}'),
                  textEditingController: _query,
                  focusNode: _focus,
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    return q.isEmpty
                        ? options
                        : options.where((o) => o.toLowerCase().contains(q));
                  },
                  onSelected: (_) => setState(() {}),
                  fieldViewBuilder: (context, controller, focus, submit) =>
                      TextField(
                    controller: controller,
                    focusNode: focus,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'اكتب ${_field.label} أو اخترها',
                      prefixIcon: const Icon(Icons.search, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
            onPickFrom: _pickFrom,
            onPickTo: _pickTo,
            showInvalidHint: _mode == DateFilterMode.range && !_rangeReady,
          ),
          const SizedBox(height: 14),
          if (asked.isEmpty)
            const _Hint('اختر الشركة أو اكتب الاسم أو الكود لعرض معاملاتها')
          else if (!hasAny)
            const _Hint('لا توجد معاملات مع هذه الجهة في الفترة المحددة')
          else ...[
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Tile(
                      label: 'إجمالي الدخول',
                      value: '\$${formatMoney(incomeTotal)}',
                      tint: AppColors.positive,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Tile(
                      label: 'إجمالي الخروج',
                      value: '\$${formatMoney(outgoingTotal)}',
                      tint: AppColors.negative,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Tile(
                      key: const ValueKey('party-report-net'),
                      label: 'الصافي',
                      value:
                          '${net >= 0 ? '+' : '-'}\$${formatMoney(net.abs())}',
                      tint: net >= 0 ? AppColors.positive : AppColors.negative,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _OperationsList(
              buys: buys,
              transfers: transfers,
              clientById: clientById,
            ),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textLow, fontSize: 13),
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textLow, fontSize: 11),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: tint,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
}

/// The operations found, oldest first: when, which way, the other side, the
/// amount (dark amber when cancelled).
class _OperationsList extends StatelessWidget {
  const _OperationsList({
    required this.buys,
    required this.transfers,
    required this.clientById,
  });

  final List<CurrencyBuy> buys;
  final List<Transfer> transfers;
  final Map<String, Client> clientById;

  @override
  Widget build(BuildContext context) {
    final tf = LibyaDateFormat('HH:mm');
    final df = LibyaDateFormat('yyyy/MM/dd');
    final rows = <({
      DateTime t,
      bool income,
      double amount,
      String party,
      bool cancelled
    })>[
      for (final b in buys)
        (
          t: b.archivedAt ?? b.createdAt,
          income: true,
          amount: b.usdAmount,
          party: _label(factsOfBuy(b, clientById)),
          cancelled: b.isCancelled,
        ),
      for (final t in transfers)
        (
          t: t.archivedAt ?? t.createdAt,
          income: false,
          amount: t.amount,
          party: _label(factsOfTransfer(t)),
          cancelled: t.isCancelled,
        ),
    ]..sort((a, b) => a.t.compareTo(b.t));

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final r in rows)
            ListTile(
              dense: true,
              title: Text(
                r.party,
                style: const TextStyle(color: AppColors.textHigh, fontSize: 13),
              ),
              subtitle: Text(
                '${r.income ? 'دخول' : 'خروج'} · ${df.format(r.t)} ${tf.format(r.t)}'
                '${r.cancelled ? ' · ملغاة' : ''}',
                style: const TextStyle(color: AppColors.textLow, fontSize: 11),
              ),
              trailing: Text(
                '${r.income ? '+' : '-'}\$${formatMoney(r.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: r.cancelled
                      ? AppColors.cancelled
                      : r.income
                          ? AppColors.positive
                          : AppColors.negative,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _label(PartyFacts f) {
    final parts = [
      if (f.company.isNotEmpty) f.company,
      if (f.name.isNotEmpty) f.name,
      if (f.code.isNotEmpty) 'كود ${f.code}',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}
