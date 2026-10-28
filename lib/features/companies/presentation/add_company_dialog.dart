import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../employee_auth/presentation/employee_auth_providers.dart';
import '../../exchange_companies/domain/exchange_company.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart'
    show AddExchangeCompanyDialog, kExchangeCompanyCountries;
import '../../treasury/data/treasury_repository.dart';
import '../../treasury/presentation/treasury_providers.dart';
import '../data/companies_repository.dart';
import '../data/exchanges_repository.dart';
import '../domain/company.dart';
import '../domain/exchange.dart';
import '../../../shared/top_message.dart';

class AddCompanyDialog extends ConsumerStatefulWidget {
  const AddCompanyDialog({super.key, required this.onSaved, this.existing});

  final VoidCallback onSaved;
  final Company? existing;

  @override
  ConsumerState<AddCompanyDialog> createState() => _AddCompanyDialogState();
}

class _AddCompanyDialogState extends ConsumerState<AddCompanyDialog> {
  final _name = TextEditingController();
  final _exName = TextEditingController();
  final _balance = TextEditingController();
  final _cost = TextEditingController();
  final _ourCode = TextEditingController();
  final _ref = TextEditingController();
  final _country = TextEditingController();
  bool _busy = false;
  Exchange? _existingExchange;
  bool _loading = false;
  bool _hasTx = false;

  bool get _isEdit => widget.existing != null;
  bool get _locked => _isEdit && _hasTx;

  /// The opening cost is typed only for a new account, by the administrator
  /// (set_account_cost refuses an employee). Later corrections are made in
  /// «الخزينة وسعر التكلفة».
  bool get _withCost => !_isEdit && !ref.read(isEmployeeProvider);

  /// The typed cost, or null when the field is empty.
  double? get _costRate =>
      _cost.text.trim().isEmpty ? null : parseRate(_cost.text);

  /// What the opening dollars cost in dinars, for the line under the field.
  double? get _costTotal {
    final balance = parseMoney(_balance.text);
    final rate = _costRate;
    if (balance <= 0 || rate == null || !rateInRange(rate)) return null;
    return lydFor(balance, rate);
  }

  /// Why the cost cannot be saved, or null when it can.
  String? _costProblem() {
    if (!_withCost) return null;
    final rate = _costRate;
    if (rate == null) {
      return parseMoney(_balance.text) > 0
          ? 'اكتب تكلفة الإفتتاحي: سعر الدولار بالدينار'
          : null;
    }
    if (!rateInRange(rate)) {
      return 'تكلفة الإفتتاحي يجب أن تكون أكبر من 1 وحتى 100 د.ل للدولار';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _name.text = widget.existing!.name;
      _ref.text = widget.existing!.startRef;
      _loading = true;
      _loadExistingExchange();
    }
  }

  Future<void> _loadExistingExchange() async {
    try {
      final repo = ref.read(exchangesRepositoryProvider);
      final exchanges = await repo.listForCompany(widget.existing!.id);
      if (exchanges.isNotEmpty) {
        _existingExchange = exchanges.first;
        _exName.text = _existingExchange!.name;
        _balance.text = formatMoney(_existingExchange!.balance);
        _ourCode.text = _existingExchange!.ourCode ?? '';
        _country.text = _existingExchange!.country ?? '';
        _hasTx = await repo.hasTransactions(_existingExchange!.id);
      }
    } catch (_) {
      // swallow — fields stay empty, user can re-enter
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _exName.dispose();
    _balance.dispose();
    _cost.dispose();
    _ourCode.dispose();
    _ref.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _exName.text.trim().isEmpty) return;
    final problem = _costProblem();
    if (problem != null) {
      showTopSnackBar(context, SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        await ref.read(companiesRepositoryProvider).update(
              id: widget.existing!.id,
              name: widget.existing!.name,
              startRef: _ref.text.trim(),
            );
        if (_existingExchange != null) {
          await ref.read(exchangesRepositoryProvider).update(
                id: _existingExchange!.id,
                name: _existingExchange!.name,
                ourCode: _ourCode.text.trim(),
                country: _existingExchange!.country,
              );
        } else {
          await ref.read(exchangesRepositoryProvider).create(
                companyId: widget.existing!.id,
                name: _exName.text.trim(),
                balance: parseMoney(_balance.text),
                ourCode: _ourCode.text.trim(),
                country:
                    _country.text.trim().isEmpty ? null : _country.text.trim(),
              );
        }
      } else {
        final ownerId = ref.read(currentUserIdProvider);
        if (ownerId == null) throw StateError('not signed in');
        final company = await ref.read(companiesRepositoryProvider).create(
              ownerId: ownerId,
              name: _name.text.trim(),
              startRef: _ref.text.trim(),
            );
        final exchange = await ref.read(exchangesRepositoryProvider).create(
              companyId: company.id,
              name: _exName.text.trim(),
              balance: parseMoney(_balance.text),
              ourCode: _ourCode.text.trim(),
              country:
                  _country.text.trim().isEmpty ? null : _country.text.trim(),
            );
        final rate = _withCost ? _costRate : null;
        if (rate != null) await _saveCost(exchange.id, rate);
      }
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      AppLogger.error('companies.addCompany.save', e, st);
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The account is already saved: a failure here must not keep the dialog
  /// open (a second «حفظ» would create the account twice), so it is reported
  /// and the cost is left to be set from the treasury.
  Future<void> _saveCost(String exchangeId, double rate) async {
    try {
      await ref.read(treasuryRepositoryProvider).setCost(exchangeId, rate);
      ref.invalidate(treasuryProvider);
      ref.invalidate(accountCostsProvider);
    } catch (e, st) {
      AppLogger.error('companies.addCompany.cost', e, st);
      if (!mounted) return;
      showTopSnackBar(
        context,
        SnackBar(
          content: Text(
            'حُفظ الحساب ولم تُحفظ تكلفة الإفتتاحي (${friendlyError(e)}). '
            'حدّدها من «الخزينة وسعر التكلفة».',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
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
                            border:
                                Border.all(color: AppColors.glassBorderStrong),
                          ),
                          child: FaIcon(
                            _isEdit
                                ? FontAwesomeIcons.penToSquare
                                : FontAwesomeIcons.buildingCircleArrowRight,
                            size: 16,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isEdit ? 'تعديل بيانات الحساب' : 'إضافة حساب جديد',
                            style: const TextStyle(
                              fontSize: 17,
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
                    const SizedBox(height: 16),
                    // Row 1: country first, then exchange-company filtered by country
                    _buildCountryField(),
                    const SizedBox(height: 14),
                    _buildExchangeCompanyField(),
                    const SizedBox(height: 14),
                    // Row 2: [إسم الحساب | كود الحساب]
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          enabled: !_isEdit,
                          decoration: const InputDecoration(
                            labelText: 'إسم الحساب',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ourCode,
                          enabled: !_locked,
                          decoration: const InputDecoration(
                            labelText: 'كود الحساب',
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    // Row 3: [الرصيد الإفتتاحي | الإشاري الإفتتاحي]
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _balance,
                          enabled: !_isEdit,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'الرصيد الإفتتاحي',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _ref,
                          enabled: !_locked,
                          decoration: const InputDecoration(
                            labelText: 'الإشاري الإفتتاحي',
                          ),
                        ),
                      ),
                    ]),
                    if (_withCost) ...[
                      const SizedBox(height: 14),
                      // Row 4: [تكلفة الإفتتاحي | إجمالي التكلفة]
                      _buildCostRow(),
                    ],
                    const SizedBox(height: 20),
                    if (_locked)
                      Center(
                        child: OutlinedButton.icon(
                          onPressed:
                              _busy ? null : () => Navigator.of(context).pop(),
                          icon: const FaIcon(
                            FontAwesomeIcons.lock,
                            size: 12,
                          ),
                          label: const Text('إغلاق'),
                        ),
                      )
                    else
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: const FaIcon(
                              FontAwesomeIcons.floppyDisk,
                              size: 14,
                            ),
                            label: Text(_busy ? '...' : 'حفظ'),
                          ),
                        ),
                      ]),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildCostRow() {
    final total = _costTotal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('opening-cost'),
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'تكلفة الإفتتاحي',
              hintText: 'د.ل للدولار',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'إجمالي التكلفة',
              enabled: false,
            ),
            child: Text(
              total == null ? '—' : '${formatMoney(total)} د.ل',
              key: const ValueKey('opening-cost-total'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHigh),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExchangeCompanyField() {
    if (_isEdit) {
      // Disabled TextField showing the loaded exchange company name.
      return TextField(
        controller: _exName,
        enabled: false,
        decoration: const InputDecoration(labelText: 'شركة الصرافة'),
      );
    }
    final asyncList = ref.watch(myExchangeCompaniesProvider);
    return asyncList.when(
      skipLoadingOnReload: true,
      skipError: true,
      data: (items) {
        final filtered = _country.text.trim().isEmpty
            ? <ExchangeCompany>[]
            : items.where((ec) => ec.country == _country.text.trim()).toList();
        if (filtered.isEmpty) {
          return _buildEmptyExchangeCompanyAddPill();
        }
        final names = filtered.map((ec) => ec.name).toList();
        final currentValue =
            (_exName.text.isNotEmpty && names.contains(_exName.text))
                ? _exName.text
                : null;
        return DropdownButtonFormField<String>(
          value: currentValue,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'شركة الصرافة',
            hintText: 'اختر شركة الصرافة',
          ),
          items: names
              .map((n) => DropdownMenuItem(value: n, child: Text(n)))
              .toList(),
          onChanged: (picked) {
            if (picked == null) return;
            setState(() => _exName.text = picked);
          },
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('$e'),
    );
  }

  Widget _buildEmptyExchangeCompanyAddPill() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 12, bottom: 4),
          child: Text(
            'شركة الصرافة',
            style: TextStyle(color: AppColors.textLow, fontSize: 12),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddExchangeCompanyDialog(
                  onSaved: () => ref.invalidate(exchangeCompaniesListProvider),
                ),
              );
            },
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: const [
                  Expanded(
                    child: Text(
                      'إضافة شركة صرافة جديدة',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FaIcon(
                    FontAwesomeIcons.plus,
                    size: 14,
                    color: AppColors.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountryField() {
    if (_isEdit) {
      return TextField(
        controller: _country,
        enabled: false,
        decoration: const InputDecoration(labelText: 'الدولة'),
      );
    }
    final current = _country.text.trim();
    final value = kExchangeCompanyCountries.contains(current) ? current : null;
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'الدولة',
        hintText: 'اختر الدولة',
      ),
      items: kExchangeCompanyCountries
          .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
          .toList(),
      onChanged: (picked) {
        if (picked == null) return;
        setState(() {
          _country.text = picked;
          _exName.text = '';
        });
      },
    );
  }
}
