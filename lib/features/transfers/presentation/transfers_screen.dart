import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/creator_chip.dart';
import '../../../shared/creator_filter.dart';
import '../../../shared/glass.dart';
import '../../../shared/transaction_details.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/pdf_file_name.dart';
import '../../../shared/pending_dispatch.dart';
import '../../../shared/audio_feedback.dart';
import '../../companies/data/companies_repository.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../clients/data/clients_repository.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../clients/presentation/saved_clients_dialog.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart'
    show AddExchangeCompanyDialog;
import '../../notifications/presentation/notifications_providers.dart';
import '../data/transfers_repository.dart';
import '../domain/transfer.dart';
import 'transfers_providers.dart';

final transfersScreenKey = GlobalKey<TransfersScreenState>();

/// The four boxes of "خروج من حسابي" share this height and text style.
const double _kFieldHeight = 48;
const TextStyle _kFieldTextStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: AppColors.textHigh,
);

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
  bool _autoPicked = false;

  final _amount = TextEditingController();
  final _beneficiaryName = TextEditingController();
  final _beneficiaryAccount = TextEditingController();
  final _beneficiaryCode = TextEditingController();
  Client? _pickedBeneficiary;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  /// The selected account as it is now: the list is refreshed after every
  /// save, and the balance moves at save, so read it from the live list.
  Exchange? get _currentExchange {
    final ex = _exchange;
    if (ex == null) return null;
    final live = ref.read(allExchangesProvider).valueOrNull;
    if (live == null) return ex;
    for (final e in live) {
      if (e.id == ex.id) return e;
    }
    return ex;
  }

  /// What the account can pay out: its balance (exits are posted at save).
  double get _available => _currentExchange?.balance ?? 0;

  bool get _overBalance {
    if (_exchange == null) return false;
    return parseMoney(_amount.text) > _available;
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
    // A single account under this company: pick it (and so fill the account
    // name, code and balance) without another tap.
    if (name == null) return;
    final matches = (ref.read(allExchangesProvider).value ?? const <Exchange>[])
        .where((e) => e.name == name)
        .toList();
    if (matches.length == 1) _onExchangeChanged(matches.first);
  }

  void _resetTransferForm() {
    setState(() {
      _amount.clear();
      _beneficiaryName.clear();
      _beneficiaryAccount.clear();
      _beneficiaryCode.clear();
      _pickedBeneficiary = null;
      _reference = null;
      _exchangeCompanyName = null;
      _exchange = null;
      _company = null;
      _activeSection = null;
      _autoPicked = false; // a single account is filled in again
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
    final balance = _available;
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
      await _persistBeneficiaryCode();
      ref.invalidate(todayTransfersProvider);
      ref.invalidate(archivedTransfersProvider);
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
      // Someone else may have just used the balance: show the new figure.
      ref.invalidate(allExchangesProvider);
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
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

  /// Every field of "خروج من حسابي" is filled: company, account (so its code
  /// and balance), reference and a positive amount. The account code comes
  /// from the account itself, so an account that has none cannot be asked for.
  bool get _exitFormComplete =>
      _outgoingFieldsEnabled &&
      _company != null &&
      (_reference ?? '').isNotEmpty &&
      parseMoney(_amount.text) > 0;

  /// The beneficiary section opens only after the transfer data is complete
  /// and the account can cover the amount (the account's balance decides, not
  /// the employee's own totals).
  bool get _beneficiaryUnlocked => _exitFormComplete && !_overBalance;

  void _showBeneficiaryBlocked() {
    if (!mounted) return;
    final over = _exitFormComplete && _overBalance;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          over
              ? 'عذراً لا يمكن فتح الجهة المستفيدة.\n'
                  'المبلغ يتجاوز رصيد الحساب '
                  '(${formatMoney(_available)} \$).'
              : 'عذراً لا يمكن فتح الجهة المستفيدة.\n'
                  'عليك استكمال بيانات الحوالة أولاً.',
        ),
      ),
    );
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
        _pickedBeneficiary = picked;
      });
    }
  }

  /// The picked saved beneficiary, only while the name / company fields
  /// still match it (editing them detaches the entry from that record).
  Client? get _matchedBeneficiary {
    final p = _pickedBeneficiary;
    if (p == null) return null;
    final matches = _beneficiaryName.text.trim() == p.name.trim() &&
        _beneficiaryAccount.text.trim() == (p.company ?? '').trim();
    return matches ? p : null;
  }

  /// True when the matched beneficiary already has an official code.
  bool get _beneficiaryCodeLocked =>
      (_matchedBeneficiary?.code ?? '').trim().isNotEmpty;

  /// First code typed for a saved beneficiary without one becomes its
  /// official code. Never overwrites an existing code; a failure here must
  /// not fail the transfer.
  Future<void> _persistBeneficiaryCode() async {
    final p = _matchedBeneficiary;
    final code = _beneficiaryCode.text.trim();
    if (p == null || _beneficiaryCodeLocked || code.isEmpty) return;
    try {
      await ref.read(clientsRepositoryProvider).update(
            id: p.id,
            name: p.name,
            company: p.company,
            code: code,
          );
      ref.invalidate(clientsListProvider);
    } catch (e, st) {
      AppLogger.error('transfers.persistBeneficiaryCode', e, st);
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
        final n = await ref.read(latestNotificationProvider.future);
        notif = n?.body;
      } catch (_) {
        notif = null;
      }
      final employeeName =
          ref.read(currentEmployeeProvider).value?.employeeName;
      final bytes = await pdf.buildDailyTransfersReport(
        rows: rows,
        companyNameById: companyNameById,
        exchangeNameById: exchangeNameById,
        notificationText: notif,
        exportedBy: exportedBy,
        employeeName: employeeName,
      );
      await PdfExport.sharePdf(
        bytes,
        pdfFileName(
          'سجل خروج الحوالات اليوم',
          who: employeeName == null ? null : 'الموظف $employeeName',
        ),
      );
    } catch (e, st) {
      AppLogger.error('transfers.exportDailyPdf', e, st);
      _snack(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangesAsync = ref.watch(allExchangesProvider);
    final dailyAsync = ref.watch(todayTransfersProvider);
    final exchangeCompaniesAsync = ref.watch(exchangeCompaniesListProvider);
    final companiesAsync = ref.watch(companiesListProvider);
    final companyById = <String, Company>{
      for (final c in companiesAsync.value ?? const <Company>[]) c.id: c,
    };

    // Exactly one account in total: fill the company, account, code, balance
    // and reference as soon as the screen opens (and again after each save),
    // so only the amount is left to type. With several accounts the fields
    // stay empty for a manual choice.
    final loadedExchanges = exchangesAsync.value;
    final loadedCompanies = exchangeCompaniesAsync.value;
    if (!_autoPicked && loadedExchanges != null && loadedCompanies != null) {
      _autoPicked = true;
      if (_exchange == null && _exchangeCompanyName == null) {
        final names = {for (final ec in loadedCompanies) ec.name};
        final mine =
            loadedExchanges.where((e) => names.contains(e.name)).toList();
        if (mine.length == 1) {
          final only = mine.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _exchange != null) return;
            setState(() {
              _exchangeCompanyName = only.name;
              _activeSection = 1;
            });
            _onExchangeChanged(only);
          });
        }
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, contentTopPadding(context), 16, contentBottomPadding(context)),
      children: [
        // Section 1 (top) — خروج من حسابي
        _CollapsibleSection(
          color: AppColors.negative,
          header: const _NumberedSectionTitle(
            1,
            'خروج من حسابي',
            color: AppColors.negative,
          ),
          expanded: _activeSection == 1,
          onToggle: () => setState(
            () => _activeSection = _activeSection == 1 ? null : 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LabeledField(
                label: 'الشركة',
                child: exchangeCompaniesAsync.when(
                  skipLoadingOnReload: true,
                  skipError: true,
                  data: (items) {
                    if (items.isEmpty) {
                      return _EmptyExchangeCompaniesState(
                        onAdd: _openAddExchangeCompanyDialog,
                      );
                    }
                    if (exchangesAsync.isLoading && !exchangesAsync.hasValue) {
                      return const LinearProgressIndicator();
                    }
                    // Only companies where I actually hold an account
                    // (an exchange with the same name), sorted by name.
                    final accountNames = {
                      for (final e in exchangesAsync.value ?? const <Exchange>[])
                        e.name,
                    };
                    final names = items
                        .map((ec) => ec.name)
                        .where(accountNames.contains)
                        .toSet()
                        .toList()
                      ..sort();
                    if (names.isEmpty) {
                      return const InputDecorator(
                        decoration: InputDecoration(
                          suffixIcon: _IconBox(FontAwesomeIcons.building),
                        ),
                        child: Text(
                          'لا توجد شركة لديك فيها حساب — أضف حساباً من تبويب حساباتي',
                          style: TextStyle(color: AppColors.textLow),
                        ),
                      );
                    }
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
                  skipLoadingOnReload: true,
                  skipError: true,
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
              // Four equal boxes (same width, same height) in two rows:
              // balance | account code, then reference | amount.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LabeledField(
                      label: 'رصيد الحساب',
                      child: SizedBox(
                        height: _kFieldHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.glassFill,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  formatMoney(_available),
                                  style: _kFieldTextStyle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LabeledField(
                      label: 'كود الحساب',
                      child: SizedBox(
                        height: _kFieldHeight,
                        child: TextField(
                          readOnly: true,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.center,
                          textAlign: TextAlign.center,
                          style: _kFieldTextStyle,
                          controller: TextEditingController(
                            text: _exchange?.ourCode ?? '',
                          ),
                          decoration: const InputDecoration(
                            hintText: 'يظهر تلقائياً',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LabeledField(
                      label: 'الرقم الإشاري',
                      child: SizedBox(
                        height: _kFieldHeight,
                        child: TextField(
                          readOnly: true,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.center,
                          textAlign: TextAlign.center,
                          style: _kFieldTextStyle,
                          controller:
                              TextEditingController(text: _reference ?? ''),
                          decoration: const InputDecoration(
                            hintText: 'يظهر تلقائياً',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LabeledField(
                      label: 'القيمة بالدولار (USD)',
                      child: SizedBox(
                        height: _kFieldHeight,
                        child: _outgoingFieldsEnabled
                            ? TextField(
                                controller: _amount,
                                keyboardType: TextInputType.number,
                                expands: true,
                                minLines: null,
                                maxLines: null,
                                textAlignVertical: TextAlignVertical.center,
                                textAlign: TextAlign.center,
                                style: _kFieldTextStyle.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'أدخل القيمة',
                                  // Over the limit: red outline here, the
                                  // message goes below so the box keeps its
                                  // height.
                                  enabledBorder: _overBalance
                                      ? OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          borderSide: const BorderSide(
                                            color: AppColors.negative,
                                          ),
                                        )
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
                                      expands: true,
                                      minLines: null,
                                      maxLines: null,
                                      textAlignVertical: TextAlignVertical.center,
                                      textAlign: TextAlign.center,
                                      style: _kFieldTextStyle,
                                      decoration: const InputDecoration(
                                        hintText: 'اختر الحساب أولاً',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_outgoingFieldsEnabled && _overBalance)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'يتجاوز رصيد الحساب',
                    style: TextStyle(fontSize: 12, color: AppColors.negative),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 2 (bottom) — الجهة المستفيدة
        _CollapsibleSection(
          color: AppColors.accent,
          header: const _NumberedSectionTitle(2, 'الجهة المستفيدة'),
          // Never open while the transfer data above is incomplete, even
          // if the header is tapped by hand.
          expanded: _activeSection == 2 && _beneficiaryUnlocked,
          onToggle: () {
            if (_activeSection == 2) {
              setState(() => _activeSection = null);
              return;
            }
            if (!_beneficiaryUnlocked) {
              _showBeneficiaryBlocked();
              return;
            }
            setState(() => _activeSection = 2);
          },
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
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'اسم حساب المستفيد',
                    suffixIcon: _IconBox(FontAwesomeIcons.wallet),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'كود حساب المستفيد',
                // A stored code is official and locked. A saved beneficiary
                // with no code yet may have one typed — once, saved with the
                // transfer.
                child: TextField(
                  controller: _beneficiaryCode,
                  readOnly: _beneficiaryCodeLocked,
                  decoration: InputDecoration(
                    hintText: _beneficiaryCodeLocked
                        ? 'كود رسمي — لا يمكن تعديله'
                        : 'أدخل كود حساب المستفيد',
                    suffixIcon: _IconBox(
                      _beneficiaryCodeLocked
                          ? FontAwesomeIcons.lock
                          : FontAwesomeIcons.user,
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
            if (!_logExpanded)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: _CountBadge(count: dailyAsync.value?.length ?? 0),
              ),
          ]),
          expanded: _logExpanded,
          onToggle: () => setState(() => _logExpanded = !_logExpanded),
          child: dailyAsync.when(
            skipLoadingOnReload: true,
            skipError: true,
            data: (rows) => _DailyTransfersTable(rows: rows),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
        ),
        const SizedBox(height: 16),
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
  const _NumberedSectionTitle(
    this.number,
    this.text, {
    this.color = AppColors.accent,
  });
  final int number;
  final String text;
  final Color color;

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
              color: color.withValues(alpha: 0.15),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number.',
              style: TextStyle(
                color: color,
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

/// Empty-state for the "اسم الشركة" dropdown when the admin has no
/// exchange_companies saved. Admins see an actionable "Add" button;
/// employees see a read-only hint asking them to contact the admin,
/// since RLS prevents them from inserting exchange_companies anyway.
class _EmptyExchangeCompaniesState extends ConsumerWidget {
  const _EmptyExchangeCompaniesState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isEmployeeProvider)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            const FaIcon(
              FontAwesomeIcons.circleInfo,
              size: 14,
              color: AppColors.textLow,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: const Text(
                'لا توجد شركات صرافة. تواصل مع المدير لإضافتها.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMid,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onAdd,
        icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
        label: const Text('إضافة شركة صرافة جديدة'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        '($count)',
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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
    this.color,
  });

  final Widget header;
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;

  /// Optional tint that sets this section apart from its neighbour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      fill: color?.withValues(alpha: 0.16) ?? AppColors.glassFill,
      border: color?.withValues(alpha: 0.55) ?? AppColors.glassBorder,
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

class _DailyTransfersTable extends ConsumerStatefulWidget {
  const _DailyTransfersTable({required this.rows});
  final List<Transfer> rows;

  @override
  ConsumerState<_DailyTransfersTable> createState() =>
      _DailyTransfersTableState();
}

class _DailyTransfersTableState extends ConsumerState<_DailyTransfersTable> {
  String _filter = kCreatorAll;

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesListProvider);
    final exchangesAsync = ref.watch(allExchangesProvider);
    final companyById = <String, String>{
      for (final c in companies.value ?? const <Company>[]) c.id: c.name,
    };
    final exchangeById = <String, Exchange>{
      for (final e in exchangesAsync.value ?? const <Exchange>[]) e.id: e,
    };
    final visible = widget.rows
        .where((t) => creatorPasses(_filter, t.createdByEmployeeId))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CreatorFilter<Transfer>(
          selected: _filter,
          onChanged: (v) => setState(() => _filter = v),
          rows: widget.rows,
          amountOf: (t) => t.netAmount,
          creatorOf: (t) => t.createdByEmployeeId,
          amountColor: AppColors.negative,
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('لا توجد سجلات'),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('الشركة')),
                    DataColumn(label: Text('من حسابي')),
                    DataColumn(label: Text('الإشاري')),
                    DataColumn(label: Text('القيمة')),
                    DataColumn(label: Text('المستفيد')),
                    DataColumn(label: Text('المنفّذ')),
                  ],
                  rows: visible
                      .map((t) => DataRow(
                            onSelectChanged: (_) => showTransferDetails(
                              context,
                              transfer: t,
                              companyName: companyById[t.companyId],
                              exchangeName:
                                  exchangeById[t.exchangeId]?.name,
                              exchangeCode:
                                  exchangeById[t.exchangeId]?.ourCode,
                            ),
                            cells: [
                              DataCell(Text(
                                  exchangeById[t.exchangeId]?.name ?? '—')),
                              DataCell(
                                  Text(companyById[t.companyId] ?? '—')),
                              DataCell(Text(t.reference)),
                              DataCell(Text(
                                t.isCancelled
                                    ? '\$${formatMoney(t.amount)} ملغاة'
                                    : '\$${formatMoney(t.amount)}',
                                style: TextStyle(
                                  color: t.isCancelled
                                      ? AppColors.cancelled
                                      : AppColors.negative,
                                  fontWeight: FontWeight.w700,
                                ),
                              )),
                              DataCell(Text(
                                t.beneficiaryName.isEmpty
                                    ? '—'
                                    : t.beneficiaryName,
                              )),
                              DataCell(CreatorChip(
                                createdByEmployeeId: t.createdByEmployeeId,
                              )),
                            ],
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Transfer details dialog moved to lib/shared/transaction_details.dart so
// both the admin's daily table and the employee's "سجلاتي" tab share the
// exact same presentation.

