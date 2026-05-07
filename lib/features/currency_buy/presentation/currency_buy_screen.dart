import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/audio_feedback.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/share.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/add_client_dialog.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../clients/presentation/saved_clients_dialog.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart'
    show AddExchangeCompanyDialog;
import '../data/currency_buys_repository.dart';
import '../domain/currency_buy.dart';
import 'currency_buys_providers.dart';

enum _PendingBuyKind { pending, execute }

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
  String? _exchangeCompanyName;
  String? _senderCompany;

  final _usd = TextEditingController();
  final _rate = TextEditingController(text: '1');
  final _lyd = TextEditingController(text: '0.00');
  final _reference = TextEditingController();

  bool _busy = false;
  int? _activeSection;
  bool _pendingExpanded = false;
  bool _executedExpanded = false;
  List<String>? _composedBuyMessages;
  _PendingBuyKind? _pendingBuyKind;

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
    _reference.dispose();
    super.dispose();
  }

  void _recomputeLyd() {
    final u = parseMoney(_usd.text);
    final r = parseMoney(_rate.text);
    _lyd.text = formatMoney(u * r);
  }

  void _resetBuyForm() {
    _client = null;
    _myCompany = null;
    _exchange = null;
    _exchangeCompanyName = null;
    _senderCompany = null;
    _usd.clear();
    _rate.text = '1';
    _lyd.text = '0.00';
    _reference.clear();
    _activeSection = null;
    _composedBuyMessages = null;
    _pendingBuyKind = null;
  }

  void _markPending() {
    if (parseMoney(_usd.text) <= 0) {
      _snack('قيمة الدولار غير صحيحة');
      return;
    }
    if (_myCompany == null || _exchange == null) {
      _snack('اختر شركتك وشركة الصرافة');
      return;
    }
    setState(() {
      _composedBuyMessages = _composeBuyMessages();
      _pendingBuyKind = _PendingBuyKind.pending;
    });
  }

  Future<void> _executeMarkPending() async {
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
            reference: _reference.text.trim(),
          );
      ref.invalidate(pendingBuysProvider);
      if (!mounted) return;
      setState(_resetBuyForm);
      playAlert();
      _snack('تم إضافة العملية إلى قيد التنفيذ');
    } catch (e, st) {
      AppLogger.error('currencyBuy.markPending', e, st);
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _composeBuyMessages() {
    final amount = formatMoney(parseMoney(_usd.text));
    final exchangeCompany = _exchangeCompanyName ?? '—';
    final senderCompany =
        (_senderCompany != null && _senderCompany!.isNotEmpty)
            ? _senderCompany!
            : (_client?.company ?? '—');
    final senderAccount = _client?.name ?? '—';
    final senderCode = _client?.code ?? '—';
    final myCompany = _myCompany?.name ?? '—';
    final myCode = _exchange?.ourCode ?? '—';
    final reference = _reference.text.trim().isEmpty
        ? '—'
        : _reference.text.trim();

    final m1 = '🇹🇷 السادة شركة $exchangeCompany\n'
        'نرجوا منكم تأكيد الدخول\n'
        'القادم من شركة * $senderCompany *\n'
        'حساب : $senderAccount\n'
        'كود : $senderCode\n'
        'اشاري ( $reference )\n'
        '———————————————-\n'
        '🏦 لحساب: $myCompany\n'
        '🔢  كود: $myCode\n'
        '💵 المبلغ: ( $amount ) \$🇹🇷\n'
        '———————————————-\n'
        'مع خالص الشكر 🤝';

    final m2 = '‏يطلب تسجيل دخول ( $amount ) \$🇹🇷\n'
        '🧾في حسابنا لدى* $exchangeCompany *🇹🇷\n'
        '🏦 لحساب: $myCompany\n'
        '🔢  كود : $myCode\n'
        '———————————————-\n'
        'مرسلة من شركة $senderCompany 🇹🇷\n'
        'حساب : $senderAccount 🇹🇷\n'
        '🔢  كود : $senderCode\n'
        'الرقم الإشاري : $reference\n'
        '———————————————-\n'
        'شاكر لكم حسن انتباهكم 🫡';

    return [m1, m2];
  }

  Future<bool?> _showBuyConfirmDialog({
    required double amountUsd,
    required _PendingBuyKind kind,
  }) {
    final amountText = '${formatMoney(amountUsd)} \$';
    final isPending = kind == _PendingBuyKind.pending;
    final tint = isPending ? AppColors.warning : AppColors.positive;
    final title = isPending ? 'حفظ كقيد التنفيذ' : 'تأكيد تنفيذ الدخول';
    final confirmLabel = isPending ? 'حفظ كقيد التنفيذ' : 'تنفيذ';
    return showGlassDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: tint, width: 2),
                      color: tint.withValues(alpha: 0.10),
                    ),
                    child: FaIcon(
                      FontAwesomeIcons.circleCheck,
                      color: tint,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHigh,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMid,
                        height: 1.5,
                      ),
                      children: [
                        TextSpan(
                          text: isPending
                              ? 'الدخول قيد التنفيذ لحين التأكيد '
                              : 'هل تريد إتمام عملية الدخول بقيمة ',
                        ),
                        TextSpan(
                          text: amountText,
                          style: TextStyle(
                            color: tint,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: ' ؟'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.glassBorder, height: 1),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      icon: const FaIcon(
                        FontAwesomeIcons.circleXmark,
                        size: 14,
                      ),
                      label: const Text('إلغاء'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.negative,
                        side: BorderSide(
                          color:
                              AppColors.negative.withValues(alpha: 0.6),
                        ),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      icon: const FaIcon(
                        FontAwesomeIcons.circleCheck,
                        size: 14,
                      ),
                      label: Text(confirmLabel),
                      style: FilledButton.styleFrom(
                        backgroundColor: tint,
                        foregroundColor: Colors.black,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmExecuteBuy() {
    if (parseMoney(_usd.text) <= 0) {
      _snack('قيمة الدولار غير صحيحة');
      return;
    }
    if (_myCompany == null || _exchange == null) {
      _snack('اختر شركتك وشركة الصرافة');
      return;
    }
    setState(() {
      _composedBuyMessages = _composeBuyMessages();
      _pendingBuyKind = _PendingBuyKind.execute;
    });
  }

  Future<void> _onPreviewSubmit() async {
    if (_pendingBuyKind == null) return;
    final ok = await _showBuyConfirmDialog(
      amountUsd: parseMoney(_usd.text),
      kind: _pendingBuyKind!,
    );
    if (ok != true || !mounted) return;
    if (_pendingBuyKind == _PendingBuyKind.pending) {
      await _executeMarkPending();
    } else {
      await _saveDailyBuy();
    }
  }

  Future<void> _confirmPendingBuy(CurrencyBuy row) async {
    final ok = await _showBuyConfirmDialog(
      amountUsd: row.usdAmount,
      kind: _PendingBuyKind.execute,
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final repo = ref.read(currencyBuysRepositoryProvider);
      await repo.createDaily(
        myCompanyId: row.myCompanyId,
        exchangeId: row.exchangeId,
        clientId: row.clientId,
        clientFromAccount: row.clientFromAccount,
        usdAmount: row.usdAmount,
        rate: row.rate,
        lydAmount: row.lydAmount,
        reference: row.reference,
      );
      final supabase = ref.read(supabaseClientProvider);
      await supabase.from('currency_buys').delete().eq('id', row.id);

      ref.invalidate(pendingBuysProvider);
      ref.invalidate(dailyBuysProvider);
      ref.invalidate(allExchangesProvider);
      if (mounted) {
        setState(_resetBuyForm);
      }
      playAlert();
      if (mounted) _snack('تم تنفيذ العملية');
    } catch (e, st) {
      AppLogger.error('currencyBuy.confirmPending', e, st);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            reference: _reference.text.trim(),
          );
      ref.invalidate(dailyBuysProvider);
      ref.invalidate(allExchangesProvider);
      ref.invalidate(exchangesByCompanyProvider(_myCompany!.id));
      if (!mounted) return;
      setState(_resetBuyForm);
      playAlert();
      _snack('تم الحفظ في سجل المشتريات');
    } catch (e, st) {
      AppLogger.error('currencyBuy.saveDailyBuy', e, st);
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveAll() async {
    final pendingCount =
        (ref.read(pendingBuysProvider).value ?? const <CurrencyBuy>[])
            .length;
    if (pendingCount > 0) {
      _snack('لا يمكن الترحيل: لديك $pendingCount عملية معلّقة.');
      return;
    }
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

  void _onExchangeCompanyChanged(String? name) {
    setState(() {
      _exchangeCompanyName = name;
      _myCompany = null;
      _exchange = null;
    });
  }

  Future<void> _openAddClientDialog() async {
    await showGlassDialog<void>(
      context: context,
      builder: (_) => AddClientDialog(
        onSaved: () => ref.invalidate(clientsListProvider),
      ),
    );
    if (!mounted) return;
    final updated = await ref.read(clientsListProvider.future);
    if (!mounted) return;
    if (updated.isNotEmpty) {
      setState(() {
        _client = updated.first;
        _senderCompany = updated.first.company;
      });
    }
  }

  Future<void> _openAddExchangeCompanyDialog() async {
    await showGlassDialog<void>(
      context: context,
      builder: (_) => AddExchangeCompanyDialog(
        onSaved: () => ref.invalidate(exchangeCompaniesListProvider),
      ),
    );
    if (!mounted) return;
    final updated = await ref.read(exchangeCompaniesListProvider.future);
    if (!mounted) return;
    if (updated.isNotEmpty) {
      _onExchangeCompanyChanged(updated.first.name);
    }
  }

  Future<void> _openSavedClientsDialog() async {
    final picked = await showGlassDialog<Client>(
      context: context,
      builder: (_) => const SavedClientsDialog(),
    );
    if (picked != null && mounted) {
      setState(() {
        _client = picked;
        _senderCompany = picked.company;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsListProvider);
    final companiesAsync = ref.watch(companiesListProvider);
    final exchangeCompaniesAsync = ref.watch(exchangeCompaniesListProvider);
    final allExchangesAsync = ref.watch(allExchangesProvider);
    final pendingAsync = ref.watch(pendingBuysProvider);
    final dailyAsync = ref.watch(dailyBuysProvider);

    if (_composedBuyMessages != null) {
      return _BuyMessagesPreview(
        messages: _composedBuyMessages!,
        busy: _busy,
        submitLabel: _pendingBuyKind == _PendingBuyKind.pending
            ? 'حفظ كقيد التنفيذ'
            : _pendingBuyKind == _PendingBuyKind.execute
                ? 'تنفيذ الدخول'
                : null,
        onSubmit: _pendingBuyKind == null ? null : _onPreviewSubmit,
        onBack: () => setState(() {
          _composedBuyMessages = null;
          _pendingBuyKind = null;
        }),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        _CollapsibleSection(
          header: const _AccentSectionTitle(
            text: 'الجهة المرسلة',
            color: AppColors.accent,
            icon: FontAwesomeIcons.paperPlane,
          ),
          expanded: _activeSection == 1,
          onToggle: () => setState(
            () => _activeSection = _activeSection == 1 ? null : 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openSavedClientsDialog,
                  icon: const FaIcon(
                    FontAwesomeIcons.bookmark,
                    size: 14,
                  ),
                  label: const Text('الجهات المحفوظة'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _LabeledField(
                label: 'الشركة المرسلة',
                child: clientsAsync.when(
                  data: (clients) {
                    if (clients.isEmpty) {
                      return SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openAddClientDialog,
                          icon: const FaIcon(
                            FontAwesomeIcons.plus,
                            size: 14,
                          ),
                          label: const Text('إضافة عميل جديد'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: BorderSide(
                              color: AppColors.accent.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      );
                    }
                    final companyNames = (<String>{}..addAll(
                            clients
                                .where((c) =>
                                    c.company != null && c.company!.isNotEmpty)
                                .map((c) => c.company!)))
                        .toList();
                    final liveValue =
                        companyNames.contains(_senderCompany)
                            ? _senderCompany
                            : null;
                    if (liveValue == null && _senderCompany != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _senderCompany = null;
                            _client = null;
                          });
                        }
                      });
                    }
                    return DropdownButtonFormField<String>(
                      value: liveValue,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: 'اسم الشركة المرسلة',
                        suffixIcon: _IconBox(
                          FontAwesomeIcons.building,
                          color: AppColors.accent,
                        ),
                      ),
                      items: companyNames
                          .map((n) => DropdownMenuItem<String>(
                                value: n,
                                child: Text(n),
                              ))
                          .toList(),
                      onChanged: (n) => setState(() {
                        _senderCompany = n;
                        _client = null;
                      }),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'اسم حساب المرسل',
                child: clientsAsync.when(
                  data: (clients) {
                    final filtered = _senderCompany == null
                        ? const <Client>[]
                        : clients
                            .where((c) => c.company == _senderCompany)
                            .toList();
                    final liveValue =
                        filtered.any((x) => x == _client) ? _client : null;
                    if (liveValue == null && _client != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _client = null);
                      });
                    }
                    return DropdownButtonFormField<Client>(
                      value: liveValue,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: _senderCompany == null
                            ? 'اختر الشركة المرسلة أولاً'
                            : 'اسم حساب المرسل',
                        suffixIcon: const _IconBox(
                          FontAwesomeIcons.wallet,
                          color: AppColors.accent,
                        ),
                      ),
                      items: filtered
                          .map((c) => DropdownMenuItem<Client>(
                                value: c,
                                child: Text(c.name),
                              ))
                          .toList(),
                      onChanged: _senderCompany == null
                          ? null
                          : (c) => setState(() => _client = c),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'كود حساب المرسل',
                child: TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _client?.code ?? '',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'كود حساب المرسل',
                    suffixIcon: _IconBox(
                      FontAwesomeIcons.user,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'الرقم الإشاري',
                child: TextField(
                  controller: _reference,
                  decoration: const InputDecoration(
                    hintText: 'أدخل الرقم الإشاري',
                    suffixIcon: _IconBox(
                      FontAwesomeIcons.hashtag,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'القيمة \$',
                child: TextField(
                  controller: _usd,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'القيمة بالدولار',
                    suffixIcon: _IconBox(
                      FontAwesomeIcons.dollarSign,
                      color: AppColors.positive,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _CollapsibleSection(
          header: const _AccentSectionTitle(
            text: 'وجهة الدخول',
            color: AppColors.warning,
            icon: FontAwesomeIcons.userTie,
          ),
          expanded: _activeSection == 2,
          onToggle: () => setState(
            () => _activeSection = _activeSection == 2 ? null : 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LabeledField(
                label: 'اسم الشركة',
                child: exchangeCompaniesAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openAddExchangeCompanyDialog,
                          icon: const FaIcon(
                            FontAwesomeIcons.plus,
                            size: 14,
                          ),
                          label: const Text('إضافة شركة صرافة جديدة'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: BorderSide(
                              color: AppColors.accent.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      );
                    }
                    final names =
                        items.map((ec) => ec.name).toList();
                    final liveValue =
                        names.contains(_exchangeCompanyName)
                            ? _exchangeCompanyName
                            : null;
                    if (liveValue == null &&
                        _exchangeCompanyName != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _onExchangeCompanyChanged(null);
                      });
                    }
                    return DropdownButtonFormField<String>(
                      value: liveValue,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: 'اسم الشركة',
                        suffixIcon: _IconBox(
                          FontAwesomeIcons.building,
                          color: AppColors.warning,
                        ),
                      ),
                      items: names
                          .map((n) => DropdownMenuItem<String>(
                                value: n,
                                child: Text(n),
                              ))
                          .toList(),
                      onChanged: _onExchangeCompanyChanged,
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'اسم حسابي',
                child: companiesAsync.when(
                  data: (companies) {
                    final allExchanges =
                        allExchangesAsync.value ?? const <Exchange>[];
                    final filteredExchanges = _exchangeCompanyName == null
                        ? const <Exchange>[]
                        : allExchanges
                            .where((e) => e.name == _exchangeCompanyName)
                            .toList();
                    final filteredCompanies = <Company>[];
                    for (final ex in filteredExchanges) {
                      for (final c in companies) {
                        if (c.id == ex.companyId &&
                            !filteredCompanies.contains(c)) {
                          filteredCompanies.add(c);
                          break;
                        }
                      }
                    }
                    final liveCompany =
                        filteredCompanies.any((x) => x == _myCompany)
                            ? _myCompany
                            : null;
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
                    return DropdownButtonFormField<Company>(
                      value: liveCompany,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: _exchangeCompanyName == null
                            ? 'اختر شركة الصرافة أولاً'
                            : 'اسم الحساب',
                        suffixIcon: const _IconBox(
                          FontAwesomeIcons.wallet,
                          color: AppColors.warning,
                        ),
                      ),
                      items: filteredCompanies
                          .map((c) => DropdownMenuItem<Company>(
                                value: c,
                                child: Text(c.name),
                              ))
                          .toList(),
                      onChanged: _exchangeCompanyName == null
                          ? null
                          : (c) {
                              Exchange? matched;
                              for (final ex in filteredExchanges) {
                                if (c != null && ex.companyId == c.id) {
                                  matched = ex;
                                  break;
                                }
                              }
                              setState(() {
                                _myCompany = c;
                                _exchange = matched;
                              });
                            },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'رقم حسابي',
                child: TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _exchange?.ourCode ?? '',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'كود الحساب',
                    suffixIcon: _IconBox(
                      FontAwesomeIcons.user,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _markPending,
              icon: const FaIcon(FontAwesomeIcons.clock, size: 14),
              label: const Text('دخول قيد التنفيذ'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _confirmExecuteBuy,
              icon: const FaIcon(
                FontAwesomeIcons.circleCheck,
                size: 14,
              ),
              label: const Text('تنفيذ دخول حوالة'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.positive,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),

        _CollapsibleSection(
          header: const _AccentSectionTitle(
            text: 'دخول قيد التنفيذ',
            color: AppColors.accent,
            icon: FontAwesomeIcons.clock,
          ),
          expanded: _pendingExpanded,
          onToggle: () =>
              setState(() => _pendingExpanded = !_pendingExpanded),
          child: pendingAsync.when(
            data: (rows) => _PendingTable(
              rows: rows,
              onTapRow: _confirmPendingBuy,
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
        ),
        const SizedBox(height: 14),

        _CollapsibleSection(
          header: Row(children: [
            const Expanded(
              child: _AccentSectionTitle(
                text: 'دخول منفذ',
                color: AppColors.positive,
                icon: FontAwesomeIcons.circleCheck,
              ),
            ),
            IconButton(
              tooltip: 'تصدير PDF',
              icon: const FaIcon(FontAwesomeIcons.filePdf, size: 16),
              onPressed: () =>
                  _exportDailyPdf(dailyAsync.value ?? const []),
            ),
          ]),
          expanded: _executedExpanded,
          onToggle: () =>
              setState(() => _executedExpanded = !_executedExpanded),
          child: dailyAsync.when(
            data: (rows) => _DailyBuysTable(rows: rows),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: _archiveAll,
          icon: const FaIcon(FontAwesomeIcons.lock, size: 16),
          label: const Text(
            'الإقفال اليومي لحوالات الدخول',
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

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.header,
    required this.child,
    required this.expanded,
    required this.onToggle,
  });

  final Widget header;
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(child: header),
                FaIcon(
                  expanded
                      ? FontAwesomeIcons.chevronUp
                      : FontAwesomeIcons.chevronDown,
                  size: 14,
                  color: AppColors.textLow,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: expanded ? child : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _AccentSectionTitle extends StatelessWidget {
  const _AccentSectionTitle({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FaIcon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
        ),
        Container(
          width: 3,
          height: 18,
          margin: const EdgeInsetsDirectional.only(start: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMid,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, {this.color = AppColors.accent});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: FaIcon(icon, size: 14, color: color),
      ),
    );
  }
}

class _PendingTable extends ConsumerWidget {
  const _PendingTable({required this.rows, required this.onTapRow});
  final List<CurrencyBuy> rows;
  final ValueChanged<CurrencyBuy> onTapRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('لا توجد عمليات معلقة'),
      );
    }
    final clients = ref.watch(clientsListProvider);
    final clientById = <String, Client>{
      for (final c in (clients.value ?? const <Client>[])) c.id: c,
    };
    final tf = DateFormat('hh:mm a');
    String fmt(DateTime t) => tf.format(_tripoliTime(t));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('من شركة')),
          DataColumn(label: Text('المرسل')),
          DataColumn(label: Text('القيمة')),
          DataColumn(label: Text('التوقيت')),
        ],
        rows: rows
            .map((b) => DataRow(
                  onSelectChanged: (_) => onTapRow(b),
                  cells: [
                    DataCell(Text(
                      clientById[b.clientId]?.company ??
                          b.clientFromAccount ??
                          '—',
                    )),
                    DataCell(Text(
                      clientById[b.clientId]?.name ?? '—',
                    )),
                    DataCell(Text(
                      '\$${formatMoney(b.usdAmount)}',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    )),
                    DataCell(Text(fmt(b.createdAt))),
                  ],
                ))
            .toList(),
      ),
    );
  }
}

class _DailyBuysTable extends ConsumerWidget {
  const _DailyBuysTable({required this.rows});
  final List<CurrencyBuy> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('لا توجد عمليات منفذة'),
      );
    }
    final clients = ref.watch(clientsListProvider);
    final clientById = <String, Client>{
      for (final c in (clients.value ?? const <Client>[])) c.id: c,
    };
    final tf = DateFormat('hh:mm a');
    String fmt(DateTime t) => tf.format(_tripoliTime(t));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('من شركة')),
          DataColumn(label: Text('المرسل')),
          DataColumn(label: Text('القيمة')),
          DataColumn(label: Text('التوقيت')),
        ],
        rows: rows
            .map((b) => DataRow(cells: [
                  DataCell(Text(
                    clientById[b.clientId]?.company ??
                        b.clientFromAccount ??
                        '—',
                  )),
                  DataCell(Text(
                    clientById[b.clientId]?.name ?? '—',
                  )),
                  DataCell(Text(
                    '\$${formatMoney(b.usdAmount)}',
                    style: const TextStyle(
                      color: AppColors.positive,
                      fontWeight: FontWeight.w700,
                    ),
                  )),
                  DataCell(Text(fmt(b.createdAt))),
                ]))
            .toList(),
      ),
    );
  }
}

DateTime _tripoliTime(DateTime t) =>
    t.toUtc().add(const Duration(hours: 2));

class _BuyMessagesPreview extends StatelessWidget {
  const _BuyMessagesPreview({
    required this.messages,
    required this.onBack,
    this.onSubmit,
    this.submitLabel,
    this.busy = false,
  });

  final List<String> messages;
  final VoidCallback onBack;
  final Future<void> Function()? onSubmit;
  final String? submitLabel;
  final bool busy;

  static const _cardTitles = [
    'للشركة المرسلة',
    'لقسم الحسابات',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Center(
            child: Text(
              'واجهة رسائل التنفيذ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textHigh,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
        for (var i = 0; i < messages.length; i++)
          GlassCard(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  i < _cardTitles.length
                      ? _cardTitles[i]
                      : 'الرسالة ${i + 1}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  messages[i],
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => shareText(context, messages[i]),
                  icon: const FaIcon(
                    FontAwesomeIcons.shareNodes,
                    size: 14,
                  ),
                  label: const Text('مشاركة'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (onSubmit != null)
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
                onPressed: busy ? null : () => onSubmit!.call(),
                icon: const FaIcon(
                  FontAwesomeIcons.circleCheck,
                  size: 14,
                ),
                label: Text(busy ? '...' : (submitLabel ?? 'إرسال')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.positive,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ])
        else
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('رجوع'),
          ),
      ],
    );
  }
}
