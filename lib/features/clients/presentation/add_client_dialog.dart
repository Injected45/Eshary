import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../exchange_companies/domain/exchange_company.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../../exchange_companies/presentation/exchange_companies_screen.dart';
import '../data/clients_repository.dart';
import '../domain/client.dart';
import 'clients_providers.dart';
import 'saved_clients_dialog.dart';
import '../../../shared/top_message.dart';

class AddClientDialog extends ConsumerStatefulWidget {
  const AddClientDialog({
    super.key,
    required this.onSaved,
    this.existing,
    this.config = const SavedEntitiesConfig(),
  });

  final VoidCallback onSaved;
  final Client? existing;
  final SavedEntitiesConfig config;

  @override
  ConsumerState<AddClientDialog> createState() => _AddClientDialogState();
}

class _AddClientDialogState extends ConsumerState<AddClientDialog> {
  final _name = TextEditingController();
  String? _companySelection;
  final _code = TextEditingController();
  final _refPrefix = TextEditingController();
  bool _busy = false;
  String? _nameError;
  String? _codeError;

  bool get _isEdit => widget.existing != null;

  bool get _codeLocked =>
      _isEdit && (widget.existing!.code ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _name.text = widget.existing!.name;
      _companySelection = widget.existing!.company;
      _code.text = widget.existing!.code ?? '';
      _refPrefix.text = widget.existing!.refPrefix ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _refPrefix.dispose();
    super.dispose();
  }

  /// Opens the add-exchange-company dialog on top of this one and, once it
  /// closes, selects the company that was just created so the user can keep
  /// filling the form without leaving the screen.
  Future<void> _addNewCompany() async {
    final before = (ref.read(exchangeCompaniesListProvider).valueOrNull ??
            const <ExchangeCompany>[])
        .map((c) => c.name)
        .toSet();
    await showGlassDialog<void>(
      context: context,
      builder: (_) => AddExchangeCompanyDialog(
        onSaved: () => ref.invalidate(exchangeCompaniesListProvider),
      ),
    );
    if (!mounted) return;
    final after = await ref.read(exchangeCompaniesListProvider.future);
    if (!mounted) return;
    final added = after.where((c) => !before.contains(c.name));
    if (added.isNotEmpty) {
      setState(() => _companySelection = added.first.name);
    }
  }

  Future<void> _save() async {
    final typedName = _name.text.trim();
    final code =
        _codeLocked ? widget.existing!.code!.trim() : cleanCode(_code.text);
    // The name is optional when there is a code: most merchants are known by
    // their code only. Such a party is called by its code.
    if (typedName.isEmpty && code.isEmpty) {
      setState(() => _nameError = 'اكتب الكود أو الاسم على الأقل');
      return;
    }
    final name = typedName.isEmpty ? nameForCode(code) : typedName;
    setState(() => _busy = true);
    try {
      final existing = await ref.read(clientsListProvider.future);
      final others = existing.where((c) => c.id != widget.existing?.id);

      // A code identifies a party within ONE company: the same code at another
      // company is another party, the same code twice at one company is not
      // allowed (the database refuses it too: migration 0068).
      if (code.isNotEmpty && !_codeLocked) {
        final clash = others
            .where(
              (c) =>
                  partyKey(c.code) == partyKey(code) &&
                  partyKey(c.company) == partyKey(_companySelection),
            )
            .firstOrNull;
        if (clash != null) {
          if (mounted) {
            setState(() {
              _busy = false;
              _codeError = 'هذا الكود مسجّل مسبقًا على نفس الشركة'
                  '${clash.name.trim().isEmpty ? '' : ' (${clash.name.trim()})'}';
            });
          }
          return;
        }
      }
      // Same name under the same company is a duplicate; the same name under
      // a different company is allowed.
      if (typedName.isNotEmpty &&
          others.any(
            (c) =>
                c.name.trim().toLowerCase() == typedName.toLowerCase() &&
                partyKey(c.company) == partyKey(_companySelection),
          )) {
        if (mounted) {
          setState(() {
            _busy = false;
            _nameError = 'هذه الجهة مسجلة مسبقًا على نفس الشركة';
          });
        }
        return;
      }

      if (_isEdit) {
        await ref.read(clientsRepositoryProvider).update(
              id: widget.existing!.id,
              name: name,
              company: _companySelection?.trim(),
              code: code,
              // sent only when it changed (a database without 0069 still saves)
              updateRefPrefix: _refPrefix.text.trim() !=
                  (widget.existing!.refPrefix ?? '').trim(),
              refPrefix: _refPrefix.text,
            );
      } else {
        final ownerId = ref.read(currentUserIdProvider);
        if (ownerId == null) throw StateError('not signed in');
        await ref.read(clientsRepositoryProvider).create(
              ownerId: ownerId,
              name: name,
              company: _companySelection?.trim(),
              code: code,
              refPrefix: _refPrefix.text,
            );
      }
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      AppLogger.error('clients.addClient.save', e, st);
      if (!mounted) return;
      showTopSnackBar(context, SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final nameField = TextField(
      controller: _name,
      onChanged: (_) {
        if (_nameError != null) setState(() => _nameError = null);
      },
      decoration: InputDecoration(
        labelText: cfg.nameLabel,
        helperText: 'اختياري إذا كتبت الكود',
        errorText: _nameError,
      ),
    );
    final codeField = TextField(
      controller: _code,
      // An existing code is official: it cannot be edited here.
      readOnly: _codeLocked,
      keyboardType: TextInputType.visiblePassword,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) {
        if (_codeError != null || _nameError != null) {
          setState(() {
            _codeError = null;
            _nameError = null;
          });
        }
      },
      decoration: InputDecoration(
        labelText: 'كود الحساب',
        helperText: _codeLocked ? 'كود رسمي — لا يمكن تعديله' : null,
        errorText: _codeError,
        suffixIcon:
            _codeLocked ? const Icon(Icons.lock_outline, size: 18) : null,
      ),
    );
    final companyField = ref.watch(exchangeCompaniesListProvider).when(
          skipLoadingOnReload: true,
          skipError: true,
          data: (companies) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _companySelection,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'من حساب شركة',
                  hintText: 'اختر الشركة',
                ),
                items: companies
                    .map((c) => DropdownMenuItem<String>(
                          value: c.name,
                          child: Text(c.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _companySelection = v;
                  _nameError = null;
                  _codeError = null;
                }),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addNewCompany,
                  icon: const FaIcon(FontAwesomeIcons.plus, size: 12),
                  label: const Text('إضافة شركة جديدة'),
                ),
              ),
            ],
          ),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
        );

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
                          : FontAwesomeIcons.userPlus,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEdit ? cfg.editTitle : cfg.addTitle,
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
              companyField,
              const SizedBox(height: 14),
              codeField,
              const SizedBox(height: 14),
              nameField,
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('ref-prefix'),
                controller: _refPrefix,
                maxLength: 20,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'حروف الرقم الإشاري الثابتة (اختياري)',
                  hintText: 'مثال: TRC',
                  helperText: 'تظهر ثابتة في خانة الإشاري ويُكتب الرقم فقط',
                  counterText: '',
                ),
              ),
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
}
