import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/audio_feedback.dart';
import '../../../shared/creator_chip.dart';
import '../../../shared/creator_filter.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/transaction_details.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/pdf_file_name.dart';
import '../../../shared/pending_dispatch.dart';
import '../../clients/data/clients_repository.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/add_client_dialog.dart';
import '../../clients/presentation/clients_providers.dart';
import '../../clients/presentation/saved_clients_dialog.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart'
    show AddExchangeCompanyDialog;
import '../../notifications/presentation/notifications_providers.dart';
import '../data/currency_buys_repository.dart';
import '../domain/currency_buy.dart';
import 'currency_buys_providers.dart';

enum _PendingBuyKind { pending, execute }

/// The reference and value boxes share this height and text style.
const double _kFieldHeight = 48;
const TextStyle _kFieldTextStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: AppColors.textHigh,
);

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
  String _senderCodeTyped = '';
  String? _senderCodeFor;

  final _usd = TextEditingController();
  final _rate = TextEditingController(text: '1');
  final _lyd = TextEditingController(text: '0.00');
  final _reference = TextEditingController();

  bool _busy = false;
  int? _activeSection;
  bool _autoPicked = false;
  bool _executedExpanded = false;

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
    _senderCodeTyped = '';
    _senderCodeFor = null;
    _myCompany = null;
    _exchange = null;
    _exchangeCompanyName = null;
    _senderCompany = null;
    _usd.clear();
    _rate.text = '1';
    _lyd.text = '0.00';
    _reference.clear();
    _activeSection = null;
    _autoPicked = false; // a single account is filled in again
  }

  /// "دخول لحسابي" is filled: company, account (so its balance row) and, by
  /// the account itself, its code. An account without a code cannot be asked
  /// for one here.
  bool get _accountComplete =>
      _exchangeCompanyName != null && _myCompany != null && _exchange != null;

  void _showSenderBlocked() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'عذراً لا يمكن فتح الجهة المرسلة.\n'
          'عليك استكمال بيانات حسابك أولاً.',
        ),
      ),
    );
  }

  bool _validateBuyForm() {
    if (parseMoney(_usd.text) <= 0) {
      _snack('قيمة الدولار غير صحيحة');
      return false;
    }
    if (_myCompany == null || _exchange == null) {
      _snack('اختر شركتك وشركة الصرافة');
      return false;
    }
    return true;
  }

  Future<void> _saveDailyAndOpenMessages() async {
    if (!_validateBuyForm()) return;
    await _saveAndOpenBuyMessages(kind: _PendingBuyKind.execute);
  }

  Future<void> _saveAndOpenBuyMessages({
    required _PendingBuyKind kind,
  }) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(currencyBuysRepositoryProvider);
      final saved = kind == _PendingBuyKind.pending
          ? await repo.createPending(
              myCompanyId: _myCompany!.id,
              exchangeId: _exchange!.id,
              clientId: _client?.id,
              clientFromAccount: _client?.company,
              usdAmount: parseMoney(_usd.text),
              rate: parseMoney(_rate.text),
              lydAmount: parseMoney(_lyd.text),
              reference: _reference.text.trim(),
            )
          : await repo.createDaily(
              myCompanyId: _myCompany!.id,
              exchangeId: _exchange!.id,
              clientId: _client?.id,
              clientFromAccount: _client?.company,
              usdAmount: parseMoney(_usd.text),
              rate: parseMoney(_rate.text),
              lydAmount: parseMoney(_lyd.text),
              reference: _reference.text.trim(),
            );

      await _persistSenderCode();

      if (kind == _PendingBuyKind.pending) {
        ref.invalidate(pendingBuysProvider);
      } else {
        ref.invalidate(todayBuysProvider);
        ref.invalidate(archivedBuysProvider);
        ref.invalidate(allExchangesProvider);
        ref.invalidate(exchangesByCompanyProvider(_myCompany!.id));
      }

      final messages = _composeBuyMessages();
      await ref.read(pendingDispatchProvider.notifier).begin(
            PendingDispatch(
              kind: kind == _PendingBuyKind.pending
                  ? DispatchKind.buyPending
                  : DispatchKind.buyDaily,
              savedRecordId: saved.id,
              messages: messages,
              openedIndices: const <int>{},
              cardTitles: const ['للشركة المرسلة', 'لقسم الحسابات'],
              savedAt: DateTime.now(),
            ),
          );

      if (!mounted) return;
      playAlert();
      setState(_resetBuyForm);
      context.push('/messages-dispatch');
    } catch (e, st) {
      AppLogger.error(
        kind == _PendingBuyKind.pending
            ? 'currencyBuy.savePending'
            : 'currencyBuy.saveDaily',
        e,
        st,
      );
      if (mounted) _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _senderCodeStored => (_client?.code ?? '').trim().isNotEmpty;

  /// The code to use for the selected sender: the stored (official) one, or
  /// the one just typed for a sender that has none yet.
  String get _effectiveSenderCode {
    if (_senderCodeStored) return _client!.code!.trim();
    if (_client != null && _senderCodeFor == _client!.id) {
      return _senderCodeTyped.trim();
    }
    return '';
  }

  /// First code typed for a sender without one becomes its official code.
  /// Never overwrites an existing code; a failure here must not fail the entry.
  Future<void> _persistSenderCode() async {
    final c = _client;
    if (c == null || _senderCodeStored) return;
    final code = _effectiveSenderCode;
    if (code.isEmpty) return;
    try {
      await ref.read(clientsRepositoryProvider).update(
            id: c.id,
            name: c.name,
            company: c.company,
            code: code,
          );
      ref.invalidate(clientsListProvider);
    } catch (e, st) {
      AppLogger.error('currencyBuy.persistSenderCode', e, st);
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
    final senderCode =
        _effectiveSenderCode.isEmpty ? '—' : _effectiveSenderCode;
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
  }) {
    final amountText = '${formatMoney(amountUsd)} \$';
    const tint = AppColors.positive;
    const title = 'تأكيد تنفيذ الدخول';
    const confirmLabel = 'تنفيذ';
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
                        const TextSpan(
                          text: 'هل تريد إتمام عملية الدخول بقيمة ',
                        ),
                        TextSpan(
                          text: amountText,
                          style: const TextStyle(
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

  Future<void> _confirmExecuteBuy() async {
    if (!_validateBuyForm()) return;
    final ok = await _showBuyConfirmDialog(
      amountUsd: parseMoney(_usd.text),
    );
    if (ok != true || !mounted) return;
    await _saveDailyAndOpenMessages();
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
      final companies = ref.read(companiesListProvider).value ?? const [];
      final exchanges = ref.read(allExchangesProvider).value ?? const [];
      final clients = ref.read(clientsListProvider).value ?? const [];
      final companyNameById = <String, String>{
        for (final c in companies) c.id: c.name,
      };
      final exchangeById = <String, Exchange>{
        for (final e in exchanges) e.id: e,
      };
      final clientById = <String, Client>{
        for (final c in clients) c.id: c,
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
      final bytes = await pdf.buildDailyBuysReport(
        rows: rows,
        companyNameById: companyNameById,
        exchangeById: exchangeById,
        clientById: clientById,
        notificationText: notif,
        exportedBy: exportedBy,
        employeeName: employeeName,
      );
      await PdfExport.sharePdf(
        bytes,
        pdfFileName(
          'سجل دخول الحوالات اليوم',
          who: employeeName == null ? null : 'الموظف $employeeName',
        ),
      );
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
    // A single account under this company: pick it (and so fill the account
    // name and code) without another tap.
    if (name == null) return;
    final matches = (ref.read(allExchangesProvider).value ?? const <Exchange>[])
        .where((e) => e.name == name)
        .toList();
    if (matches.length != 1) return;
    final companies = ref.read(companiesListProvider).value ?? const <Company>[];
    for (final c in companies) {
      if (c.id == matches.first.companyId) {
        setState(() {
          _myCompany = c;
          _exchange = matches.first;
        });
        break;
      }
    }
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
    final dailyAsync = ref.watch(todayBuysProvider);

    // Exactly one account in total: fill the company, account and code as
    // soon as the screen opens (and again after each save) and go straight
    // to the sender section. With several accounts nothing is chosen for me.
    final loadedExchanges = allExchangesAsync.value;
    final loadedCompanies = companiesAsync.value;
    final loadedExchangeCompanies = exchangeCompaniesAsync.value;
    if (!_autoPicked &&
        loadedExchanges != null &&
        loadedCompanies != null &&
        loadedExchangeCompanies != null) {
      _autoPicked = true;
      if (_exchange == null && _exchangeCompanyName == null) {
        final names = {for (final ec in loadedExchangeCompanies) ec.name};
        final mine =
            loadedExchanges.where((e) => names.contains(e.name)).toList();
        if (mine.length == 1) {
          final only = mine.first;
          Company? owner;
          for (final c in loadedCompanies) {
            if (c.id == only.companyId) {
              owner = c;
              break;
            }
          }
          if (owner != null) {
            final company = owner;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _exchange != null) return;
              setState(() {
                _exchangeCompanyName = only.name;
                _myCompany = company;
                _exchange = only;
                _activeSection = 2;
              });
            });
          }
        }
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, contentTopPadding(context), 16, contentBottomPadding(context)),
      children: [
        _CollapsibleSection(
          color: AppColors.positive,
          header: const _AccentSectionTitle(
            text: 'دخول لحسابي',
            color: AppColors.positive,
            icon: FontAwesomeIcons.userTie,
          ),
          expanded: _activeSection == 1,
          onToggle: () => setState(
            () => _activeSection = _activeSection == 1 ? null : 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LabeledField(
                label: 'اسم الشركة',
                child: exchangeCompaniesAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return _EmptyExchangeCompaniesState(
                        onAdd: _openAddExchangeCompanyDialog,
                      );
                    }
                    if (allExchangesAsync.isLoading &&
                        !allExchangesAsync.hasValue) {
                      return const LinearProgressIndicator();
                    }
                    // Only companies where I actually hold an account
                    // (an exchange with the same name), sorted by name.
                    final accountNames = {
                      for (final e
                          in allExchangesAsync.value ?? const <Exchange>[])
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
                          suffixIcon: _IconBox(
                            FontAwesomeIcons.building,
                            color: AppColors.warning,
                          ),
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

        _CollapsibleSection(
          color: AppColors.accent,
          header: const _AccentSectionTitle(
            text: 'الجهة المرسلة',
            color: AppColors.accent,
            icon: FontAwesomeIcons.paperPlane,
          ),
          // Never open while "دخول لحسابي" is incomplete, even if the header
          // is tapped by hand.
          expanded: _activeSection == 2 && _accountComplete,
          onToggle: () {
            if (_activeSection == 2) {
              setState(() => _activeSection = null);
              return;
            }
            if (!_accountComplete) {
              _showSenderBlocked();
              return;
            }
            setState(() => _activeSection = 2);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!ref.watch(isEmployeeProvider)) ...[
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
              ],
              _LabeledField(
                label: 'الشركة المرسلة',
                child: clientsAsync.when(
                  data: (clients) {
                    if (clients.isEmpty) {
                      return _EmptyClientsState(
                        onAdd: _openAddClientDialog,
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
                // A stored code is official and locked. Only a sender with no
                // code yet may have one typed — once, saved with the entry.
                child: TextFormField(
                  key: ValueKey('sender-code-${_client?.id}'),
                  initialValue: _client?.code ?? '',
                  readOnly: _client == null || _senderCodeStored,
                  onChanged: (v) {
                    _senderCodeTyped = v;
                    _senderCodeFor = _client?.id;
                  },
                  decoration: InputDecoration(
                    hintText: _client == null
                        ? 'كود حساب المرسل'
                        : (_senderCodeStored
                            ? 'كود رسمي — لا يمكن تعديله'
                            : 'أدخل كود المرسل (مرة واحدة)'),
                    suffixIcon: _IconBox(
                      _senderCodeStored
                          ? FontAwesomeIcons.lock
                          : FontAwesomeIcons.user,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Two identical boxes side by side: same width, same height,
              // text centred. No icons: they only squeeze the value.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LabeledField(
                      label: 'الرقم الإشاري',
                      child: SizedBox(
                        height: _kFieldHeight,
                        child: TextField(
                          controller: _reference,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          style: _kFieldTextStyle,
                          decoration: const InputDecoration(
                            hintText: 'أدخل الرقم الإشاري',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LabeledField(
                      label: 'القيمة \$',
                      child: SizedBox(
                        height: _kFieldHeight,
                        child: TextField(
                          controller: _usd,
                          keyboardType: TextInputType.number,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          style: _kFieldTextStyle.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'القيمة بالدولار',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _confirmExecuteBuy,
            icon: const FaIcon(
              FontAwesomeIcons.paperPlane,
              size: 14,
            ),
            label: Text(_busy ? '...' : 'حفظ'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 24),

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
            if (!_executedExpanded)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 8),
                child: _CountBadge(
                  count: dailyAsync.value?.length ?? 0,
                  color: AppColors.positive,
                ),
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '($count)',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
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

/// Empty-state for the "الشركة المرسلة" clients dropdown when the admin
/// has no clients saved. Employees can't insert clients (RLS blocks).
class _EmptyClientsState extends ConsumerWidget {
  const _EmptyClientsState({required this.onAdd});
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
                'لا توجد جهات مرسلة محفوظة. تواصل مع المدير لإضافتها.',
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
        label: const Text('إضافة عميل جديد'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// Empty-state for the "اسم الشركة" dropdown when the admin has no
/// exchange_companies saved. Employees can't insert exchange_companies
/// (RLS blocks), so they see a hint instead of the "+" button.
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

class _DailyBuysTable extends ConsumerStatefulWidget {
  const _DailyBuysTable({required this.rows});
  final List<CurrencyBuy> rows;

  @override
  ConsumerState<_DailyBuysTable> createState() => _DailyBuysTableState();
}

class _DailyBuysTableState extends ConsumerState<_DailyBuysTable> {
  String _filter = kCreatorAll;

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsListProvider);
    final companies = ref.watch(companiesListProvider);
    final clientById = <String, Client>{
      for (final c in (clients.value ?? const <Client>[])) c.id: c,
    };
    final companyById = <String, String>{
      for (final c in (companies.value ?? const <Company>[])) c.id: c.name,
    };
    final tf = DateFormat('HH:mm');
    String fmt(DateTime t) => tf.format(_tripoliTime(t));
    final visible = widget.rows
        .where((b) => creatorPasses(_filter, b.createdByEmployeeId))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CreatorFilter<CurrencyBuy>(
          selected: _filter,
          onChanged: (v) => setState(() => _filter = v),
          rows: widget.rows,
          amountOf: (b) => b.netAmount,
          creatorOf: (b) => b.createdByEmployeeId,
          amountColor: AppColors.positive,
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('لا توجد عمليات منفذة'),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('من شركة')),
                DataColumn(label: Text('المرسل')),
                DataColumn(label: Text('القيمة')),
                DataColumn(label: Text('في حسابي')),
                DataColumn(label: Text('التوقيت')),
                DataColumn(label: Text('المنفّذ')),
              ],
              rows: visible
                  .map((b) => DataRow(
                      onSelectChanged: (_) =>
                          showCurrencyBuyDetails(context, ref, buy: b),
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
                          b.isCancelled
                              ? '\$${formatMoney(b.usdAmount)} ملغاة'
                              : '\$${formatMoney(b.usdAmount)}',
                          style: TextStyle(
                            color: b.isCancelled
                                ? AppColors.cancelled
                                : AppColors.positive,
                            fontWeight: FontWeight.w700,
                          ),
                        )),
                        DataCell(
                            Text(companyById[b.myCompanyId] ?? '—')),
                        DataCell(Text(fmt(b.createdAt))),
                        DataCell(CreatorChip(
                          createdByEmployeeId: b.createdByEmployeeId,
                        )),
                      ]))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

DateTime _tripoliTime(DateTime t) =>
    t.toUtc().add(const Duration(hours: 2));

