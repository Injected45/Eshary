import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/exchange_companies_repository.dart';
import '../domain/exchange_company.dart';
import 'exchange_companies_providers.dart';
import '../../../shared/top_message.dart';

class ExchangeCompaniesScreen extends ConsumerWidget {
  const ExchangeCompaniesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(exchangeCompaniesListProvider);
    // Anything recorded on a company (an account, a saved party, an operation)
    // takes its delete button away. While this is unknown there is no button.
    final usage = ref.watch(exchangeCompanyUsageProvider).valueOrNull;

    void add(String kind) => showGlassDialog<void>(
          context: context,
          builder: (_) => AddExchangeCompanyDialog(
            kind: kind,
            onSaved: () => ref.invalidate(exchangeCompaniesListProvider),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('شركات الصرافة'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
      ),
      body: asyncList.when(
        skipLoadingOnReload: true,
        skipError: true,
        data: (items) {
          final mine = [
            for (final c in items)
              if (c.isMine) c
          ];
          final clients = [
            for (final c in items)
              if (c.isClient) c
          ];
          return ListView(
            padding:
                EdgeInsets.fromLTRB(16, 16, 16, contentBottomPadding(context)),
            children: [
              // My own exchange companies: where I hold accounts.
              _KindHeader(
                key: const ValueKey('kind-mine'),
                title: 'شركات الصرافة الخاصة بي',
                subtitle:
                    'الشركات التي لي حسابات عندها (تظهر في الدخول والخروج وحساباتي)',
                addTooltip: 'إضافة شركة صرافة لي',
                onAdd: () => add(kExchangeCompanyMine),
              ),
              if (mine.isEmpty)
                const _EmptyKind(text: 'لا توجد شركات صرافة حتى الآن'),
              for (final ec in mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ExchangeCompanyTile(
                    item: ec,
                    canDelete: usage?[ec.name]?.unused ?? false,
                  ),
                ),
              const SizedBox(height: 12),
              // My customers' companies: never offered as my own company.
              _KindHeader(
                key: const ValueKey('kind-client'),
                title: 'شركات العملاء',
                subtitle: 'شركات من أرسل لهم أو منهم (لا تظهر كشركة باسمي)',
                addTooltip: 'إضافة شركة عميل',
                onAdd: () => add(kExchangeCompanyClient),
              ),
              if (clients.isEmpty)
                const _EmptyKind(text: 'لا توجد شركات عملاء حتى الآن'),
              for (final ec in clients)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ExchangeCompanyTile(
                    item: ec,
                    canDelete: usage?[ec.name]?.unused ?? false,
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
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

/// The title of one of the two lists, with its own "+".
class _KindHeader extends StatelessWidget {
  const _KindHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.addTooltip,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final String addTooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textLow,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: addTooltip,
            onPressed: onAdd,
            icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _EmptyKind extends StatelessWidget {
  const _EmptyKind({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textLow, fontSize: 13),
          ),
        ),
      );
}

class _ExchangeCompanyTile extends ConsumerWidget {
  const _ExchangeCompanyTile({required this.item, required this.canDelete});
  final ExchangeCompany item;

  /// Only a name that was registered and never used (no account, no saved
  /// party, no operation) can be deleted: otherwise there is no delete button.
  final bool canDelete;

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
                  onSaved: () => ref.invalidate(exchangeCompaniesListProvider),
                ),
              );
            },
          ),
          if (canDelete)
            IconButton(
              key: ValueKey('company-delete-${item.id}'),
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
                      onPressed: () => Navigator.of(dialogContext).pop(false),
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
                      onPressed: () => Navigator.of(dialogContext).pop(true),
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
        showTopSnackBar(
          context,
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }
}

class AddExchangeCompanyDialog extends ConsumerStatefulWidget {
  const AddExchangeCompanyDialog({
    required this.onSaved,
    this.existing,
    this.kind = kExchangeCompanyMine,
  });

  final VoidCallback onSaved;
  final ExchangeCompany? existing;

  /// [kExchangeCompanyMine] (my own exchange company) or
  /// [kExchangeCompanyClient] (a customer's company).
  final String kind;

  @override
  ConsumerState<AddExchangeCompanyDialog> createState() =>
      AddExchangeCompanyDialogState();
}

const kExchangeCompanyCountries = <String>[
  'تركيا',
  'الامارات',
  'مصر',
  'ليبيا',
];

class AddExchangeCompanyDialogState
    extends ConsumerState<AddExchangeCompanyDialog> {
  final _name = TextEditingController();
  String? _country;
  late String _kind = widget.kind;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _name.text = widget.existing!.name;
      _country = widget.existing!.country;
      _kind = widget.existing!.kind;
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
              kind: _kind == widget.existing!.kind ? null : _kind,
            );
      } else {
        final ownerId = ref.read(currentUserIdProvider);
        if (ownerId == null) throw StateError('not signed in');
        await ref.read(exchangeCompaniesRepositoryProvider).create(
              ownerId: ownerId,
              name: name,
              country: _country,
              kind: widget.kind,
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
                      _isEdit
                          ? (widget.existing!.isClient
                              ? 'تعديل شركة عميل'
                              : 'تعديل شركة صرافة')
                          : (widget.kind == kExchangeCompanyClient
                              ? 'إضافة شركة عميل'
                              : 'إضافة شركة صرافة'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
                    color: AppColors.textLow,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: (_country != null &&
                        kExchangeCompanyCountries.contains(_country))
                    ? _country
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'الدولة',
                  hintText: 'اختر الدولة',
                ),
                items: kExchangeCompanyCountries
                    .map((c) =>
                        DropdownMenuItem<String>(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _country = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'اسم شركة الصرافة',
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  key: const ValueKey('company-kind'),
                  segments: const [
                    ButtonSegment(
                      value: kExchangeCompanyMine,
                      label: Text('شركة صرافة لي'),
                    ),
                    ButtonSegment(
                      value: kExchangeCompanyClient,
                      label: Text('شركة عميل'),
                    ),
                  ],
                  selected: {_kind},
                  showSelectedIcon: false,
                  onSelectionChanged:
                      _busy ? null : (v) => setState(() => _kind = v.first),
                ),
              ],
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
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
