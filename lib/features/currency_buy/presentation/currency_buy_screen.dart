import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/theme.dart';
import '../../../shared/audio_feedback.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/share.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/companies_providers.dart';
import '../data/currency_buys_repository.dart';
import '../domain/currency_buy.dart';
import 'currency_buys_providers.dart';

class CurrencyBuyScreen extends ConsumerStatefulWidget {
  const CurrencyBuyScreen({super.key});

  @override
  ConsumerState<CurrencyBuyScreen> createState() =>
      _CurrencyBuyScreenState();
}

class _CurrencyBuyScreenState extends ConsumerState<CurrencyBuyScreen> {
  Client? _client;
  Company? _myCompany;
  Exchange? _exchange;

  final _usd = TextEditingController();
  final _rate = TextEditingController();
  final _lyd = TextEditingController(text: '0.00');

  bool _busy = false;
  String? _composedMessage;

  @override
  void initState() {
    super.initState();
    _usd.addListener(_recomputeLyd);
    _rate.addListener(_recomputeLyd);
  }

  @override
  void dispose() {
    _usd.dispose();
    _rate.dispose();
    _lyd.dispose();
    super.dispose();
  }

  void _recomputeLyd() {
    final u = parseMoney(_usd.text);
    final r = parseMoney(_rate.text);
    _lyd.text = formatMoney(u * r);
  }

  String _composeMessage() {
    return 'شراء عملة\n'
        'تم استلام مبلغ: ${formatMoney(parseMoney(_usd.text))}\$\n'
        'من العميل: ${_client?.name ?? ''}\n'
        'تم توجيهها إلى حساب: ${_exchange?.name ?? ''}';
  }

  Future<void> _markPending() async {
    if (parseMoney(_usd.text) <= 0) {
      _snack('قيمة الدولار غير صحيحة');
      return;
    }
    if (_myCompany == null || _exchange == null) {
      _snack('اختر شركتك وشركة الصرافة');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(currencyBuysRepositoryProvider).createPending(
            myCompanyId: _myCompany!.id,
            exchangeId: _exchange!.id,
            clientId: _client?.id,
            clientFromAccount: _client?.company,
            usdAmount: parseMoney(_usd.text),
            rate: parseMoney(_rate.text),
            lydAmount: parseMoney(_lyd.text),
          );
      ref.invalidate(pendingBuysProvider);
      _snack('تم إضافة العملية إلى قيد التنفيذ');
    } catch (e, st) {
      AppLogger.error('currencyBuy.markPending', e, st);
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _markCompleted() {
    if (parseMoney(_usd.text) <= 0) {
      _snack('قيمة الدولار غير صحيحة');
      return;
    }
    if (_myCompany == null || _exchange == null) {
      _snack('اختر شركتك وشركة الصرافة');
      return;
    }
    setState(() => _composedMessage = _composeMessage());
  }

  Future<void> _saveDailyBuy() async {
    if (_myCompany == null || _exchange == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(currencyBuysRepositoryProvider).createDaily(
            myCompanyId: _myCompany!.id,
            exchangeId: _exchange!.id,
            clientId: _client?.id,
            clientFromAccount: _client?.company,
            usdAmount: parseMoney(_usd.text),
            rate: parseMoney(_rate.text),
            lydAmount: parseMoney(_lyd.text),
          );
      ref.invalidate(dailyBuysProvider);
      ref.invalidate(allExchangesProvider);
      ref.invalidate(exchangesByCompanyProvider(_myCompany!.id));
      if (!mounted) return;
      setState(() {
        _composedMessage = null;
        _usd.clear();
        _rate.clear();
        _lyd.text = '0.00';
      });
      _snack('تم الحفظ في سجل المشتريات');
    } catch (e, st) {
      AppLogger.error('currencyBuy.saveDailyBuy', e, st);
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الترحيل'),
        content:
            const Text('إقفال وترحيل سجل المشتريات اليومي للأرشيف العام؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ترحيل'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final n = await ref.read(archiveBuysActionProvider)();
      playAlert();
      _snack('تم ترحيل $n سجل');
    } catch (e, st) {
      AppLogger.error('currencyBuy.archiveAll', e, st);
      _snack(friendlyError(e));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _exportDailyPdf(List<CurrencyBuy> rows) async {
    if (rows.isEmpty) {
      _snack('لا توجد سجلات للتصدير');
      return;
    }
    try {
      final pdf = await PdfExport.load();
      final df = DateFormat('yyyy-MM-dd');
      final bytes = await pdf.buildTable(
        title: 'سجل المشتريات اليومي',
        headers: const ['التاريخ', 'المبلغ \$', 'الحساب'],
        rows: rows
            .map((b) => [
                  df.format(b.createdAt),
                  formatMoney(b.usdAmount),
                  b.clientFromAccount ?? '-',
                ])
            .toList(),
      );
      await PdfExport.sharePdf(bytes, 'daily_buys.pdf');
    } catch (e, st) {
      AppLogger.error('currencyBuy.exportDailyPdf', e, st);
      _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsListProvider);
    final companiesAsync = ref.watch(companiesListProvider);
    final exchangesAsync = _myCompany == null
        ? const AsyncValue<List<Exchange>>.data([])
        : ref.watch(exchangesByCompanyProvider(_myCompany!.id));
    final pendingAsync = ref.watch(pendingBuysProvider);
    final dailyAsync = ref.watch(dailyBuysProvider);

    if (_composedMessage != null) {
      return _BuyMessagePreview(
        message: _composedMessage!,
        busy: _busy,
        onBack: () => setState(() => _composedMessage = null),
        onSave: _saveDailyBuy,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle('بيانات شراء عملة (دولار)'),
        clientsAsync.when(
          data: (clients) {
            final liveValue =
                clients.any((x) => x == _client) ? _client : null;
            if (liveValue == null && _client != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _client = null);
              });
            }
            return DropdownButtonFormField<Client>(
              value: liveValue,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'من حساب (العميل)'),
              items: clients
                  .map((c) =>
                      DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (c) => setState(() => _client = c),
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _usd,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'قيمة الدولار \$'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _rate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'سعر الصرف'),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _lyd,
          readOnly: true,
          decoration:
              const InputDecoration(labelText: 'القيمة بالدينار الليبي'),
        ),
        const SizedBox(height: 16),
        _SectionTitle('توجيه الشراء إلى حساب'),
        companiesAsync.when(
          data: (companies) {
            final liveCompany =
                companies.any((x) => x == _myCompany) ? _myCompany : null;
            if (liveCompany == null && _myCompany != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _myCompany = null;
                    _exchange = null;
                  });
                }
              });
            }
            return Row(children: [
              Expanded(
                child: DropdownButtonFormField<Company>(
                  value: liveCompany,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'شركتك الخاصة'),
                  items: companies
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c.name)))
                      .toList(),
                  onChanged: (c) => setState(() {
                    _myCompany = c;
                    _exchange = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: exchangesAsync.when(
                  data: (exchanges) {
                    final liveExchange =
                        exchanges.any((x) => x == _exchange)
                            ? _exchange
                            : null;
                    if (liveExchange == null && _exchange != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _exchange = null);
                      });
                    }
                    return DropdownButtonFormField<Exchange>(
                      value: liveExchange,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'شركة الصرافة المستلمة'),
                      items: exchanges
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (e) => setState(() => _exchange = e),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
            ]);
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _markPending,
              icon: const FaIcon(FontAwesomeIcons.hourglassHalf, size: 14),
              label: const Text('قيد التنفيذ (لا يرحل)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(
                    color: AppColors.warning.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _markCompleted,
              icon: const FaIcon(FontAwesomeIcons.check, size: 14),
              label: const Text('تم التنفيذ'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.positive,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ]),
            ],
          ),
        ),
        const SizedBox(height: 24),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionTitle('عمليات معلقة (قيد التنفيذ — تمنع الترحيل)'),
              pendingAsync.when(
                data: (rows) => _PendingTable(rows: rows),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _SectionTitle(
                      'سجل المشتريات اليومي (بانتظار الإقفال)'),
                ),
                IconButton(
                  tooltip: 'تصدير PDF',
                  icon: const FaIcon(FontAwesomeIcons.filePdf, size: 16),
                  onPressed: () =>
                      _exportDailyPdf(dailyAsync.value ?? const []),
                ),
              ]),
              dailyAsync.when(
                data: (rows) => _DailyBuysTable(rows: rows),
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _archiveAll,
          icon: const FaIcon(FontAwesomeIcons.lock, size: 16),
          label: const Text(
            'الإقفال اليومي لمشتريات العملة',
            textAlign: TextAlign.center,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.positive,
            foregroundColor: Colors.black,
          ),
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
    );
  }
}

class _BuyMessagePreview extends StatelessWidget {
  const _BuyMessagePreview({
    required this.message,
    required this.busy,
    required this.onBack,
    required this.onSave,
  });

  final String message;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            message,
            style: const TextStyle(
              fontSize: 16,
              height: 1.6,
              color: AppColors.textHigh,
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => shareText(context, message),
          icon: const FaIcon(FontAwesomeIcons.shareNodes, size: 16),
          label: const Text('مشاركة'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: busy ? null : onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('تعديل'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : onSave,
              icon: const Icon(Icons.save),
              label: Text(busy ? '...' : 'حفظ في سجل المشتريات'),
            ),
          ),
        ]),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            margin: const EdgeInsetsDirectional.only(end: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, AppColors.positive],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.textHigh,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingTable extends StatelessWidget {
  const _PendingTable({required this.rows});
  final List<CurrencyBuy> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('لا توجد عمليات معلقة'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('العميل')),
          DataColumn(label: Text('المبلغ \$')),
          DataColumn(label: Text('الحالة')),
        ],
        rows: rows
            .map((b) => DataRow(cells: [
                  DataCell(Text(b.clientFromAccount ?? '-')),
                  DataCell(Text(formatMoney(b.usdAmount))),
                  const DataCell(
                    Text(
                      'قيد التنفيذ ⏳',
                      style: TextStyle(color: Color(0xFFC2410C)),
                    ),
                  ),
                ]))
            .toList(),
      ),
    );
  }
}

class _DailyBuysTable extends StatelessWidget {
  const _DailyBuysTable({required this.rows});
  final List<CurrencyBuy> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('لا توجد سجلات'),
      );
    }
    final df = DateFormat('yyyy-MM-dd');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('المبلغ \$')),
          DataColumn(label: Text('الحساب')),
        ],
        rows: rows
            .map((b) => DataRow(cells: [
                  DataCell(Text(df.format(b.createdAt))),
                  DataCell(Text(formatMoney(b.usdAmount))),
                  DataCell(Text(b.clientFromAccount ?? '-')),
                ]))
            .toList(),
      ),
    );
  }
}
