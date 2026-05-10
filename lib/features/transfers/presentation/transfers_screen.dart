import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/pending_dispatch.dart';
import '../../../shared/audio_feedback.dart';
import '../../companies/data/companies_repository.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/saved_clients_dialog.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart'
    show AddExchangeCompanyDialog;
import '../data/transfers_repository.dart';
import '../domain/transfer.dart';
import 'transfers_providers.dart';

final transfersScreenKey = GlobalKey<TransfersScreenState>();

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => TransfersScreenState();
}

class TransfersScreenState extends ConsumerState<TransfersScreen> {
  Company? _company;
  Exchange? _exchange;
  String? _reference;
  String? _exchangeCompanyName;
  int? _activeSection;
  bool _logExpanded = false;
  bool _autoArchiveChecked = false;

  final _amount = TextEditingController();
  final _beneficiaryName = TextEditingController();
  final _beneficiaryAccount = TextEditingController();
  final _beneficiaryCode = TextEditingController();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmountChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeAutoArchivePreviousDay(),
    );
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  bool get _overBalance {
    if (_exchange == null) return false;
    return parseMoney(_amount.text) > (_exchange?.balance ?? 0);
  }

  @override
  void dispose() {
    _amount.removeListener(_onAmountChanged);
    _amount.dispose();
    _beneficiaryName.dispose();
    _beneficiaryAccount.dispose();
    _beneficiaryCode.dispose();
    super.dispose();
  }

  Future<void> _onCompanyChanged(Company? c) async {
    setState(() {
      _company = c;
      _exchange = null;
      _reference = null;
    });
  }

  void _onExchangeCompanyChanged(String? name) {
    setState(() {
      _exchangeCompanyName = name;
      _exchange = null;
      _company = null;
      _reference = null;
    });
  }

  void _resetTransferForm() {
    setState(() {
      _amount.clear();
      _beneficiaryName.clear();
      _beneficiaryAccount.clear();
      _beneficiaryCode.clear();
      _reference = null;
      _exchangeCompanyName = null;
      _exchange = null;
      _company = null;
      _activeSection = null;
    });
  }

  Future<void> _onExchangeChanged(Exchange? e) async {
    if (e == null) {
      setState(() {
        _exchange = null;
        _company = null;
        _reference = null;
      });
      return;
    }
    setState(() {
      _exchange = e;
      _reference = null;
    });
    final companies = await ref.read(companiesListProvider.future);
    Company? derived;
    for (final c in companies) {
      if (c.id == e.companyId) {
        derived = c;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _company = derived);
    if (derived == null) return;
    final newRef = await ref
        .read(companiesRepositoryProvider)
        .nextReference(derived.id);
    if (mounted) setState(() => _reference = newRef);
  }

  List<String> _composeMessages() {
    final amount = formatMoney(parseMoney(_amount.text));
    final company = _company?.name ?? '';
    final code = _exchange?.ourCode ?? '';
    final exchange = _exchange?.name ?? '';
    final beneficiary = _beneficiaryAccount.text;
    final bank = _beneficiaryName.text;
    final benCode = _beneficiaryCode.text;
    final ref = _reference ?? '';

    final card1 = 'السادة ؛ $exchange 🇹🇷\n'
        'نرجوا تسليم شركة : $beneficiary\n'
        'في حساب : $bank\n'
        '🔢 كود الحساب : $benCode\n'
        '————————————————\n'
        '🏦 من حساب : $company\n'
        '🔢 كود : $code\n'
        '💵 مبلغ : ( $amount \$ ) 🇹🇷\n'
        '📄 الرقم الإشاري : $ref\n'
        '————————————————\n'
        'شكراً علي تعاونكم معنا 🤝';

    final card2 = 'تفضلوا بالإستلام من : $exchange 🇹🇷\n'
        '🏦 من حساب : $company\n'
        '🔢 كود : $code\n'
        '💵 مبلغ : ( $amount \$ ) 🇹🇷\n'
        '📄 الرقم الإشاري : $ref\n'
        '————————————————\n'
        '🏦 تسليمكم في شركة : $beneficiary\n'
        'إسم الحساب : $bank\n'
        '🔢 كود : $benCode\n'
        '————————————————\n'
        'شكراً علي تعاملكم معنا 🤝';

    final card3 = 'إلى قسم الحسابات\n'
        '------------------------------\n'
        'يطلب تسجيل خروج بقيمة ( $amount \$ ) 🇹🇷\n'
        '🏦 من حساب : $company\n'
        '🔢 كود : $code\n'
        'لدى شركة : $exchange 🇹🇷\n'
        '------------------------------\n'
        'إلى حساب شركة : $beneficiary\n'
        'إسم الحساب : $bank\n'
        '🔢 كود : $benCode\n'
        '💵 المبلغ : ( $amount \$ ) 🇹🇷\n'
        '📄 الرقم الإشاري : $ref\n'
        '------------------------------\n'
        'شاكر لكم حسن انتباهكم';

    return [card1, card2, card3];
  }

  Future<void> _saveAndOpenMessages() async {
    if (_company == null || _exchange == null || _reference == null) {
      _snack('اختر الشركة وشركة الصرافة أولاً');
      return;
    }
    if (parseMoney(_amount.text) <= 0) {
      _snack('المبلغ غير صحيح');
      return;
    }
    final amount = parseMoney(_amount.text);
    final balance = _exchange?.balance ?? 0;
    if (amount > balance) {
      _snack('المبلغ يتجاوز رصيد الحساب (${formatMoney(balance)} \$).');
      return;
    }
    if (_beneficiaryName.text.trim().isEmpty) {
      _snack('اسم المستفيد مطلوب');
      return;
    }

    setState(() => _busy = true);
    try {
      final saved = await ref.read(transfersRepositoryProvider).create(
            companyId: _company!.id,
            exchangeId: _exchange!.id,
            beneficiaryName: _beneficiaryName.text.trim(),
            beneficiaryAccountCompany: _beneficiaryAccount.text.trim(),
            beneficiaryCode: _beneficiaryCode.text.trim(),
            amount: amount,
            reference: _reference!,
          );
      ref.invalidate(dailyTransfersProvider);
      ref.invalidate(allExchangesProvider);
      ref.invalidate(exchangesByCompanyProvider(_company!.id));

      final messages = _composeMessages();
      await ref.read(pendingDispatchProvider.notifier).begin(
            PendingDispatch(
              kind: DispatchKind.transfer,
              savedRecordId: saved.id,
              messages: messages,
              openedIndices: const <int>{},
              cardTitles: const ['للشركة المنفذة', 'للمستفيد', 'لقسم الحسابات'],
              savedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      playAlert();
      _resetTransferForm();
      context.push('/messages-dispatch');
    } catch (e, st) {
      AppLogger.error('transfers.saveAndOpenMessages', e, st);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archiveAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('الإقفال اليومي للحوالات'),
        content: const Text(
          'هل تريد ترحيل سجلات الحوالات اليومية إلى الأرشيف العام؟',
        ),
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
      final n = await ref.read(archiveTransfersActionProvider)();
      if (mounted) {
        setState(() {
          _company = null;
          _exchange = null;
          _reference = null;
          _amount.clear();
          _beneficiaryName.clear();
          _beneficiaryAccount.clear();
          _beneficiaryCode.clear();
        });
      }
      playAlert();
      _snack('تم ترحيل $n سجل');
    } catch (e, st) {
      AppLogger.error('transfers.archiveAll', e, st);
      _snack(friendlyError(e));
    }
  }

  Future<void> _maybeAutoArchivePreviousDay() async {
    if (_autoArchiveChecked) return;
    _autoArchiveChecked = true;
    try {
      final rows = await ref.read(dailyTransfersProvider.future);
      final now = DateTime.now();
      bool isStale(Transfer r) {
        final c = r.createdAt.toLocal();
        if (c.year != now.year) return c.year < now.year;
        if (c.month != now.month) return c.month < now.month;
        return c.day < now.day;
      }

      if (rows.any(isStale)) {
        await ref.read(archiveTransfersActionProvider)();
        ref.invalidate(dailyTransfersProvider);
        ref.invalidate(allExchangesProvider);
        if (mounted) _snack('تم الإقفال التلقائي لحوالات اليوم السابق');
      }
    } catch (e, st) {
      AppLogger.error('transfers.autoArchive', e, st);
      if (mounted) _snack(friendlyError(e));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  bool get _outgoingFieldsEnabled =>
      _exchangeCompanyName != null && _exchange != null;

  void _showOutgoingValidation() {
    _snack('اختر الشركة واسم الحساب المراد التحويل منه أولاً');
  }

  Future<void> _openSavedBeneficiariesDialog() async {
    final picked = await showGlassDialog<Client>(
      context: context,
      builder: (_) =>
          const SavedClientsDialog(config: SavedEntitiesConfig.beneficiaries),
    );
    if (picked != null && mounted) {
      setState(() {
        // Label swap (Task 7): the field labeled "الشركة المستفيدة" stays
        // bound to _beneficiaryAccount → DB beneficiary_account_company.
        // The field labeled "حساب المستفيد" stays bound to _beneficiaryName
        // → DB beneficiary_name. Saved client provides .company for the
        // company-labeled field and .name for the account-labeled field.
        _beneficiaryAccount.text = picked.company ?? '';
        _beneficiaryName.text = picked.name;
        _beneficiaryCode.text = picked.code ?? '';
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

  void fillDefaults() {
    setState(() {
      _amount.text = '1000.00';
      // After Task 7 label swap: _beneficiaryAccount is labeled
      // "الشركة المستفيدة" and _beneficiaryName is labeled "حساب المستفيد".
      _beneficiaryAccount.text = 'شركة الاختبار التجريبية';
      _beneficiaryName.text = 'حساب اختبار';
      _beneficiaryCode.text = 'TEST-001';
    });
    if (_exchange == null) {
      final list = ref.read(allExchangesProvider).value ?? const [];
      if (list.isNotEmpty) {
        _onExchangeChanged(list.first);
      } else {
        _snack('لا توجد شركة صرافة محفوظة — أضف واحدة أولًا');
      }
    }
  }

  Future<void> _exportDailyPdf(List<Transfer> rows) async {
    if (rows.isEmpty) {
      _snack('لا توجد سجلات للتصدير');
      return;
    }
    try {
      final companies = ref.read(companiesListProvider).value ?? const [];
      final exchanges = ref.read(allExchangesProvider).value ?? const [];
      final companyNameById = <String, String>{
        for (final c in companies) c.id: c.name,
      };
      final exchangeNameById = <String, String>{
        for (final e in exchanges) e.id: e.name,
      };
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildDailyTransfersReport(
        rows: rows,
        companyNameById: companyNameById,
        exchangeNameById: exchangeNameById,
      );
      await PdfExport.sharePdf(bytes, 'daily_transfers.pdf');
    } catch (e, st) {
      AppLogger.error('transfers.exportDailyPdf', e, st);
      _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangesAsync = ref.watch(allExchangesProvider);
    final dailyAsync = ref.watch(dailyTransfersProvider);
    final exchangeCompaniesAsync = ref.watch(exchangeCompaniesListProvider);
    final companiesAsync = ref.watch(companiesListProvider);
    final companyById = <String, Company>{
      for (final c in companiesAsync.value ?? const <Company>[]) c.id: c,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        // Section 1 (top) — الجهة المستفيدة (Task 11: swapped to top)
        _CollapsibleSection(
          header: const _NumberedSectionTitle(1, 'الجهة المستفيدة'),
          expanded: _activeSection == 1,
          onToggle: () => setState(
            () => _activeSection = _activeSection == 1 ? null : 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openSavedBeneficiariesDialog(),
                  icon: const FaIcon(FontAwesomeIcons.bookmark, size: 14),
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
                label: 'الشركة المستفيدة',
                child: TextField(
                  controller: _beneficiaryAccount,
                  decoration: const InputDecoration(
                    hintText: 'اسم الشركة المستفيدة',
                    suffixIcon: _IconBox(FontAwesomeIcons.building),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'حساب المستفيد',
                child: TextField(
                  controller: _beneficiaryName,
                  decoration: const InputDecoration(
                    hintText: 'اسم حساب المستفيد',
                    suffixIcon: _IconBox(FontAwesomeIcons.wallet),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'كود حساب المستفيد',
                child: TextField(
                  controller: _beneficiaryCode,
                  decoration: const InputDecoration(
                    hintText: 'أدخل كود حساب المستفيد',
                    suffixIcon: _IconBox(FontAwesomeIcons.user),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 2 (bottom) — خروج من حساب (Task 11: renamed from "الجهة المنفذة")
        _CollapsibleSection(
          header: const _NumberedSectionTitle(2, 'خروج من حساب'),
          expanded: _activeSection == 2,
          onToggle: () => setState(
            () => _activeSection = _activeSection == 2 ? null : 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LabeledField(
                label: 'الشركة',
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
                              color: AppColors.accent.withValues(alpha: 0.5),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      );
                    }
                    final names = items.map((ec) => ec.name).toList();
                    final liveValue =
                        names.contains(_exchangeCompanyName)
                            ? _exchangeCompanyName
                            : null;
                    if (liveValue == null && _exchangeCompanyName != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _onExchangeCompanyChanged(null);
                      });
                    }
                    return DropdownButtonFormField<String>(
                      value: liveValue,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        hintText: 'اختر الشركة',
                        suffixIcon: _IconBox(FontAwesomeIcons.building),
                      ),
                      items: names
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text(n)))
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
                label: 'اسم الحساب',
                child: exchangesAsync.when(
                  data: (allExchanges) {
                    final filtered = _exchangeCompanyName == null
                        ? const <Exchange>[]
                        : allExchanges
                            .where((e) => e.name == _exchangeCompanyName)
                            .toList();
                    final liveValue =
                        filtered.any((x) => x == _exchange) ? _exchange : null;
                    if (liveValue == null && _exchange != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _exchange = null;
                            _company = null;
                            _reference = null;
                          });
                        }
                      });
                    }
                    return DropdownButtonFormField<Exchange>(
                      value: liveValue,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: _exchangeCompanyName == null
                            ? 'اختر الشركة أولاً'
                            : 'اختر اسم الحساب',
                        suffixIcon: const _IconBox(FontAwesomeIcons.wallet),
                      ),
                      items: filtered
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  companyById[e.companyId]?.name ?? '—',
                                ),
                              ))
                          .toList(),
                      onChanged: _exchangeCompanyName == null
                          ? null
                          : _onExchangeChanged,
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'كود الحساب',
                child: TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _exchange?.ourCode ?? '',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'اختر الشركة واسم الحساب أولاً ليتم جلب الكود تلقائياً',
                    suffixIcon: _IconBox(FontAwesomeIcons.hashtag),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'رصيد الحساب',
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.glassFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(
                    children: [
                      Text(
                        formatMoney(_exchange?.balance ?? 0),
                        style: const TextStyle(
                          color: AppColors.textHigh,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const _IconBox(
                        FontAwesomeIcons.dollarSign,
                        color: AppColors.positive,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'الرقم الإشاري',
                child: TextField(
                  readOnly: true,
                  controller:
                      TextEditingController(text: _reference ?? ''),
                  decoration: const InputDecoration(
                    hintText: 'أدخل الرقم الإشاري',
                    suffixIcon: _IconBox(FontAwesomeIcons.hashtag),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'القيمة بالدولار (USD)',
                child: _outgoingFieldsEnabled
                    ? TextField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHigh,
                        ),
                        decoration: InputDecoration(
                          hintText: 'أدخل قيمة التحويل',
                          suffixIcon: const _IconBox(
                            FontAwesomeIcons.dollarSign,
                            color: AppColors.positive,
                          ),
                          errorText: _overBalance
                              ? 'المبلغ يتجاوز رصيد الحساب (${formatMoney(_exchange?.balance ?? 0)} \$)'
                              : null,
                        ),
                      )
                    : GestureDetector(
                        onTap: _showOutgoingValidation,
                        child: AbsorbPointer(
                          child: Opacity(
                            opacity: 0.55,
                            child: TextField(
                              controller: _amount,
                              enabled: false,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textHigh,
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    'اختر الشركة واسم الحساب أولاً',
                                suffixIcon: _IconBox(
                                  FontAwesomeIcons.dollarSign,
                                  color: AppColors.positive,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                FontAwesomeIcons.lock,
                size: 11,
                color: AppColors.textDim,
              ),
              SizedBox(width: 6),
              Text(
                'تأكد من صحة البيانات قبل الحفظ والإرسال',
                style: TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: (_overBalance || _busy) ? null : _saveAndOpenMessages,
          icon: const FaIcon(FontAwesomeIcons.paperPlane, size: 16),
          label: Text(_busy ? '...' : 'حفظ وفتح الرسائل'),
        ),
        const SizedBox(height: 24),
        _CollapsibleSection(
          header: Row(children: [
            Expanded(
              child: _SectionTitle('خروج منفذ'),
            ),
            IconButton(
              tooltip: 'تصدير PDF',
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () =>
                  _exportDailyPdf(dailyAsync.value ?? const []),
            ),
          ]),
          expanded: _logExpanded,
          onToggle: () => setState(() => _logExpanded = !_logExpanded),
          child: dailyAsync.when(
            data: (rows) => _DailyTransfersTable(rows: rows),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _archiveAll,
          icon: const FaIcon(FontAwesomeIcons.lock, size: 16),
          label: const Text(
            'الإقفال اليومي لحوالات الخروج',
            textAlign: TextAlign.center,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.negative,
            foregroundColor: Colors.white,
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

class _NumberedSectionTitle extends StatelessWidget {
  const _NumberedSectionTitle(this.number, this.text);
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.5),
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number.',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textHigh,
            ),
          ),
        ],
      ),
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

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    super.key,
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

class _DailyTransfersTable extends ConsumerWidget {
  const _DailyTransfersTable({required this.rows});
  final List<Transfer> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('لا توجد سجلات'),
      );
    }
    final companies = ref.watch(companiesListProvider);
    final exchangesAsync = ref.watch(allExchangesProvider);
    final companyById = <String, String>{
      for (final c in companies.value ?? const <Company>[]) c.id: c.name,
    };
    final exchangeById = <String, Exchange>{
      for (final e in exchangesAsync.value ?? const <Exchange>[]) e.id: e,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('الإشاري')),
              DataColumn(label: Text('شركة')),
              DataColumn(label: Text('من حساب')),
              DataColumn(label: Text('القيمة')),
              DataColumn(label: Text('المستفيد')),
            ],
            rows: rows
                .map((t) => DataRow(
                      onSelectChanged: (_) => _showTransferDetails(
                        context,
                        transfer: t,
                        companyName: companyById[t.companyId],
                        exchangeName: exchangeById[t.exchangeId]?.name,
                      ),
                      cells: [
                        DataCell(Text(t.reference)),
                        DataCell(Text(
                            exchangeById[t.exchangeId]?.name ?? '—')),
                        DataCell(Text(companyById[t.companyId] ?? '—')),
                        DataCell(Text(
                          '\$${formatMoney(t.amount)}',
                          style: const TextStyle(
                            color: AppColors.positive,
                            fontWeight: FontWeight.w700,
                          ),
                        )),
                        DataCell(Text(
                          t.beneficiaryName.isEmpty ? '—' : t.beneficiaryName,
                        )),
                      ],
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

void _showTransferDetails(
  BuildContext context, {
  required Transfer transfer,
  String? companyName,
  String? exchangeName,
}) {
  showGlassDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'تفاصيل الحوالة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DetailRow(label: 'من حساب', value: companyName ?? '—'),
              _DetailRow(label: 'من شركة', value: exchangeName ?? '—'),
              _DetailRow(
                  label: 'المبلغ', value: '${formatMoney(transfer.amount)} \$'),
              _DetailRow(
                  label: 'الرقم الإشاري', value: transfer.reference),
              _DetailRow(
                  label: 'المستفيد', value: transfer.beneficiaryName),
              _DetailRow(
                label: 'حساب المستفيد',
                value: (transfer.beneficiaryAccountCompany?.isEmpty ?? true)
                    ? '—'
                    : transfer.beneficiaryAccountCompany!,
              ),
              _DetailRow(
                label: 'كود حساب المستفيد',
                value: (transfer.beneficiaryCode?.isEmpty ?? true)
                    ? '—'
                    : transfer.beneficiaryCode!,
              ),
              _DetailRow(
                label: 'التاريخ',
                value: DateFormat('yyyy-MM-dd  HH:mm')
                    .format(transfer.createdAt),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textLow,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

