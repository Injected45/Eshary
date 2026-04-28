import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../../shared/share.dart';
import '../../../core/supabase_provider.dart';
import '../../../shared/audio_feedback.dart';
import '../../companies/data/companies_repository.dart';
import '../../companies/domain/company.dart';
import '../../companies/domain/exchange.dart';
import '../../companies/presentation/companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../data/beneficiaries_repository.dart';
import '../data/transfers_repository.dart';
import '../domain/beneficiary.dart';
import '../domain/transfer.dart';
import 'beneficiaries_providers.dart';
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

  final _amount = TextEditingController();
  final _beneficiaryName = TextEditingController();
  final _beneficiaryAccount = TextEditingController();
  final _beneficiaryCode = TextEditingController();

  bool _busy = false;
  List<String>? _composedMessages;

  @override
  void dispose() {
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
    final beneficiary = _beneficiaryName.text;
    final bank = _beneficiaryAccount.text;
    final benCode = _beneficiaryCode.text;
    final ref = _reference ?? '';

    final card1 = '🇹🇷السادة شركة $exchange\n'
        'نرجوا منكم تأكيد استلام الحوالة\n'
        'القادمة من شركة * $company *\n'
        'من حساب : $bank\n'
        'كود :$benCode\n'
        'اشاري ( $ref ) \n'
        '———————————————-\n'
        '🏦 لحساب: شركة $company \n'
        '🔢  كود: $code  \n'
        '💵 المبلغ: (  $amount ) \$🇹🇷  \n'
        'مع خالص الشكر.';

    final card2 = 'السادة شركة : $beneficiary\n\n'
        'نرجو تسليم شركة:  $exchange - 🇹🇷\n'
        '———————————————\n'
        '🏦 لحساب: شركة $company\n'
        '🔢 كود: $code  \n'
        '💵 المبلغ: ( $amount \$ )🇺🇸🇹🇷\n'
        'شكرًا لتعاونكم';

    final card3 = 'الي قسم الحسابات\n'
        ' ------------------------------\n'
        'تم دخول قيمة ( $amount \$ )\n'
        '🏦 لحساب شركة: $company\n'
        '🔢 كود: $code\n'
        'لدى شركة : $exchange🇹🇷🇹🇷\n'
        '------------------------------\n'
        'من حساب شركة $beneficiary\n'
        'من حساب : $bank\n'
        '🔢 كود المستفيد: $benCode\n'
        '💵 المبلغ( $amount\$ ) 🇺🇸\n'
        '📄 الرقم الإشاري: $ref';

    return [card1, card2, card3];
  }

  void _generate() {
    if (_company == null || _exchange == null || _reference == null) {
      _snack('اختر الشركة وشركة الصرافة أولاً');
      return;
    }
    if (parseMoney(_amount.text) <= 0) {
      _snack('المبلغ غير صحيح');
      return;
    }
    if (_beneficiaryName.text.trim().isEmpty) {
      _snack('اسم المستفيد مطلوب');
      return;
    }
    setState(() => _composedMessages = _composeMessages());
  }

  Future<void> _saveToDaily() async {
    if (_company == null || _exchange == null || _reference == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(transfersRepositoryProvider).create(
            companyId: _company!.id,
            exchangeId: _exchange!.id,
            beneficiaryName: _beneficiaryName.text.trim(),
            beneficiaryAccountCompany: _beneficiaryAccount.text.trim(),
            beneficiaryCode: _beneficiaryCode.text.trim(),
            amount: parseMoney(_amount.text),
            reference: _reference!,
          );
      ref.invalidate(dailyTransfersProvider);
      ref.invalidate(allExchangesProvider);
      ref.invalidate(exchangesByCompanyProvider(_company!.id));
      // Refresh next reference for follow-up entries.
      final next = await ref
          .read(companiesRepositoryProvider)
          .nextReference(_company!.id);
      if (!mounted) return;
      setState(() {
        _composedMessages = null;
        _amount.clear();
        _beneficiaryName.clear();
        _beneficiaryAccount.clear();
        _beneficiaryCode.clear();
        _reference = next;
      });
      playAlert();
      _snack('تم الحفظ في السجل اليومي');
    } catch (e, st) {
      AppLogger.error('transfers.saveToDaily', e, st);
      _snack(friendlyError(e));
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
          _composedMessages = null;
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

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openSavedBeneficiariesDialog() async {
    final picked = await showGlassDialog<Beneficiary>(
      context: context,
      builder: (_) => const _SavedBeneficiariesDialog(),
    );
    if (picked != null && mounted) {
      setState(() {
        _beneficiaryName.text = picked.name;
        _beneficiaryAccount.text = picked.account ?? '';
        _beneficiaryCode.text = picked.code ?? '';
      });
    }
  }

  void fillDefaults() {
    setState(() {
      _amount.text = '1000.00';
      _beneficiaryName.text = 'شركة الاختبار التجريبية';
      _beneficiaryAccount.text = 'حساب اختبار';
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
      final pdf = await PdfExport.load();
      final df = DateFormat('yyyy-MM-dd');
      final bytes = await pdf.buildTable(
        title: 'سجل الحوالات اليومي',
        headers: const ['التاريخ', 'الإشاري', 'المستفيد', 'المبلغ \$'],
        rows: rows
            .map((t) => [
                  df.format(t.createdAt),
                  t.reference,
                  t.beneficiaryName,
                  formatMoney(t.amount),
                ])
            .toList(),
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

    if (_composedMessages != null) {
      return _MessagesPreview(
        messages: _composedMessages!,
        busy: _busy,
        onBack: () => setState(() => _composedMessages = null),
        onSave: _saveToDaily,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        // Section 1 — الجهة المنفذة
        _CollapsibleSection(
          header: const _NumberedSectionTitle(1, 'الجهة المنفذة'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LabeledField(
                label: 'شركة الصرافة',
                child: exchangeCompaniesAsync.when(
                  data: (items) {
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
                        hintText: 'اختر شركة الصرافة',
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
                label: 'إسم الحساب',
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
                            ? 'اختر شركة الصرافة أولاً'
                            : 'اختر إسم الحساب',
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
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 2 — جهة الاستلام
        _CollapsibleSection(
          header: const _NumberedSectionTitle(2, 'جهة الاستلام'),
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
                  controller: _beneficiaryName,
                  decoration: const InputDecoration(
                    hintText: 'اسم الشركة المستفيدة',
                    suffixIcon: _IconBox(FontAwesomeIcons.building),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'حساب المستلم',
                child: TextField(
                  controller: _beneficiaryAccount,
                  decoration: const InputDecoration(
                    hintText: 'اسم الحساب أو البنك',
                    suffixIcon: _IconBox(FontAwesomeIcons.wallet),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'كود حساب المستلم',
                child: TextField(
                  controller: _beneficiaryCode,
                  decoration: const InputDecoration(
                    hintText: 'أدخل كود حساب المستلم',
                    suffixIcon: _IconBox(FontAwesomeIcons.user),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Section 3 — قيمة التحويل
        _CollapsibleSection(
          header: const _NumberedSectionTitle(3, 'قيمة التحويل'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LabeledField(
                label: 'القيمة بالدولار (USD)',
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'أدخل قيمة التحويل',
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
          onPressed: _generate,
          icon: const FaIcon(FontAwesomeIcons.paperPlane, size: 16),
          label: const Text('حفظ وإرسال'),
        ),
        const SizedBox(height: 24),
        _CollapsibleSection(
          header: Row(children: [
            Expanded(
              child: _SectionTitle('سجل الحوالات المنفذة'),
            ),
            IconButton(
              tooltip: 'تصدير PDF',
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () =>
                  _exportDailyPdf(dailyAsync.value ?? const []),
            ),
          ]),
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
            'الإقفال اليومي للحوالات',
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

class _MessagesPreview extends StatelessWidget {
  const _MessagesPreview({
    required this.messages,
    required this.busy,
    required this.onBack,
    required this.onSave,
  });

  final List<String> messages;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onSave;

  static const _arabicIndex = ['الرسالة ١', 'الرسالة ٢', 'الرسالة ٣'];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 24, 16, 96),
      children: [
        for (var i = 0; i < messages.length; i++)
          GlassCard(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  i < _arabicIndex.length
                      ? _arabicIndex[i]
                      : 'الرسالة ${i + 1}',
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 12,
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
              label: Text(busy ? '...' : 'حفظ في السجل اليومي'),
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

class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.header,
    required this.child,
    this.initiallyExpanded = true,
  });

  final Widget header;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Row(
              children: [
                Expanded(child: widget.header),
                FaIcon(
                  _expanded
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
            child: _expanded ? widget.child : const SizedBox.shrink(),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('من حساب')),
          DataColumn(label: Text('شركة')),
          DataColumn(label: Text('المبلغ')),
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
                    DataCell(Text(companyById[t.companyId] ?? '—')),
                    DataCell(
                        Text(exchangeById[t.exchangeId]?.name ?? '—')),
                    DataCell(Text(formatMoney(t.amount))),
                  ],
                ))
            .toList(),
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

class _SavedBeneficiariesDialog extends ConsumerStatefulWidget {
  const _SavedBeneficiariesDialog();

  @override
  ConsumerState<_SavedBeneficiariesDialog> createState() =>
      _SavedBeneficiariesDialogState();
}

class _SavedBeneficiariesDialogState
    extends ConsumerState<_SavedBeneficiariesDialog> {
  Future<void> _openAddSheet() async {
    await showGlassDialog<void>(
      context: context,
      builder: (_) => const _AddBeneficiaryDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(beneficiariesListProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.30),
                          AppColors.positive.withValues(alpha: 0.20),
                        ],
                      ),
                      border: Border.all(color: AppColors.glassBorderStrong),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.bookmark,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'الجهات',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إضافة جهة جديدة',
                    onPressed: _openAddSheet,
                    icon: const FaIcon(FontAwesomeIcons.plus, size: 14),
                    color: AppColors.accent,
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              listAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: Text(
                          'لا توجد جهات محفوظة',
                          style: TextStyle(
                            color: AppColors.textLow,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                Navigator.of(context).pop(item),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.glassFill,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.glassBorder),
                              ),
                              child: Row(
                                children: [
                                  const FaIcon(
                                    FontAwesomeIcons.user,
                                    size: 14,
                                    color: AppColors.accent,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textHigh,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (item.account?.isEmpty ?? true)
                                              ? '—'
                                              : item.account!,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const FaIcon(
                                      FontAwesomeIcons.trash,
                                      size: 14,
                                      color: AppColors.negative,
                                    ),
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(
                                              beneficiariesRepositoryProvider,
                                            )
                                            .delete(item.id);
                                        ref.invalidate(
                                          beneficiariesListProvider,
                                        );
                                      } catch (e, st) {
                                        AppLogger.error(
                                          'transfers.beneficiary.delete',
                                          e,
                                          st,
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text(friendlyError(e)),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text(
                  '$e',
                  style: const TextStyle(color: AppColors.negative),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddBeneficiaryDialog extends ConsumerStatefulWidget {
  const _AddBeneficiaryDialog();

  @override
  ConsumerState<_AddBeneficiaryDialog> createState() =>
      _AddBeneficiaryDialogState();
}

class _AddBeneficiaryDialogState
    extends ConsumerState<_AddBeneficiaryDialog> {
  String? _name;
  final _account = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name == null || _name!.trim().isEmpty) {
      setState(() => _error = 'اختر شركة الصرافة');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ownerId = ref.read(currentUserIdProvider);
      if (ownerId == null) {
        setState(() {
          _error = 'لم يتم تسجيل الدخول';
          _busy = false;
        });
        return;
      }
      await ref.read(beneficiariesRepositoryProvider).create(
            ownerId: ownerId,
            name: _name!.trim(),
            account: _account.text.trim(),
            code: _code.text.trim(),
          );
      ref.invalidate(beneficiariesListProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, st) {
      AppLogger.error('transfers.addBeneficiary.save', e, st);
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangeAsync = ref.watch(exchangeCompaniesListProvider);

    return Dialog(
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
                      'إضافة جهة جديدة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _LabeledField(
                label: 'شركة الصرافة',
                child: exchangeAsync.when(
                  data: (companies) => DropdownButtonFormField<String>(
                    value: _name,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'اختر شركة الصرافة',
                      suffixIcon: _IconBox(FontAwesomeIcons.building),
                    ),
                    items: companies
                        .map((c) => DropdownMenuItem(
                              value: c.name,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _name = v),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'حساب المستلم',
                child: TextField(
                  controller: _account,
                  decoration: const InputDecoration(
                    hintText: 'اسم الحساب أو البنك',
                    suffixIcon: _IconBox(FontAwesomeIcons.wallet),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'كود حساب المستلم',
                child: TextField(
                  controller: _code,
                  decoration: const InputDecoration(
                    hintText: 'أدخل كود حساب المستلم',
                    suffixIcon: _IconBox(FontAwesomeIcons.user),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.negative.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.negative.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.negative),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
                label: Text(_busy ? '...' : 'حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
