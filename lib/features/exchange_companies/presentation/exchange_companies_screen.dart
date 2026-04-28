import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../companies/presentation/add_company_dialog.dart'
    show CountryPickerDialog;
import '../data/exchange_companies_repository.dart';
import '../domain/exchange_company.dart';
import 'exchange_companies_providers.dart';

class ExchangeCompaniesScreen extends ConsumerWidget {
  const ExchangeCompaniesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(exchangeCompaniesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('شركات الصرافة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
            tooltip: 'إضافة شركة صرافة',
            onPressed: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddExchangeCompanyDialog(
                  onSaved: () =>
                      ref.invalidate(exchangeCompaniesListProvider),
                ),
              );
            },
          ),
        ],
      ),
      body: asyncList.when(
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'لا توجد شركات صرافة حتى الآن',
                    style: TextStyle(color: AppColors.textLow),
                  ),
                ),
              ),
            for (final ec in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExchangeCompanyTile(item: ec),
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
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class _ExchangeCompanyTile extends ConsumerWidget {
  const _ExchangeCompanyTile({required this.item});
  final ExchangeCompany item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const FaIcon(
            FontAwesomeIcons.building,
            size: 16,
            color: AppColors.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textHigh,
              ),
            ),
          ),
          IconButton(
            tooltip: 'تعديل',
            icon: const FaIcon(FontAwesomeIcons.penToSquare, size: 14),
            onPressed: () {
              showGlassDialog<void>(
                context: context,
                builder: (_) => AddExchangeCompanyDialog(
                  existing: item,
                  onSaved: () =>
                      ref.invalidate(exchangeCompaniesListProvider),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const FaIcon(
              FontAwesomeIcons.trash,
              size: 14,
              color: AppColors.negative,
            ),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'حذف شركة الصرافة؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHigh,
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(false),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.negative,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(true),
                      child: const Text('حذف'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(exchangeCompaniesRepositoryProvider).delete(item.id);
        ref.invalidate(exchangeCompaniesListProvider);
      } catch (e, st) {
        AppLogger.error('exchangeCompanies.delete', e, st);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}

class AddExchangeCompanyDialog extends ConsumerStatefulWidget {
  const AddExchangeCompanyDialog({required this.onSaved, this.existing});

  final VoidCallback onSaved;
  final ExchangeCompany? existing;

  @override
  ConsumerState<AddExchangeCompanyDialog> createState() =>
      AddExchangeCompanyDialogState();
}

class AddExchangeCompanyDialogState
    extends ConsumerState<AddExchangeCompanyDialog> {
  final _name = TextEditingController();
  String? _country;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _name.text = widget.existing!.name;
      _country = widget.existing!.country;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'الاسم مطلوب');
      return;
    }
    if (_country == null || _country!.isEmpty) {
      setState(() => _error = 'اختر الدولة');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await ref.read(exchangeCompaniesRepositoryProvider).update(
              id: widget.existing!.id,
              name: name,
              country: _country,
            );
      } else {
        final ownerId = ref.read(currentUserIdProvider);
        if (ownerId == null) throw StateError('not signed in');
        await ref.read(exchangeCompaniesRepositoryProvider).create(
              ownerId: ownerId,
              name: name,
              country: _country,
            );
      }
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      AppLogger.error('exchangeCompanies.save', e, st);
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _busy = false;
      });
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
                    child: FaIcon(
                      _isEdit
                          ? FontAwesomeIcons.penToSquare
                          : FontAwesomeIcons.building,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEdit ? 'تعديل شركة صرافة' : 'إضافة شركة صرافة',
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
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 12, bottom: 4),
                child: Text(
                  'الدولة',
                  style: TextStyle(color: AppColors.textLow, fontSize: 12),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final picked = await showGlassDialog<String>(
                      context: context,
                      builder: (_) => const CountryPickerDialog(),
                    );
                    if (picked != null && mounted) {
                      setState(() => _country = picked);
                    }
                  },
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.glassFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          (_country == null || _country!.isEmpty)
                              ? 'اختر الدولة'
                              : _country!,
                          style: TextStyle(
                            color: (_country == null || _country!.isEmpty)
                                ? AppColors.textDim
                                : AppColors.textHigh,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const FaIcon(
                        FontAwesomeIcons.globe,
                        size: 14,
                        color: AppColors.accent,
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'اسم شركة الصرافة',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
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
}
