import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../exchange_companies/presentation/exchange_companies_providers.dart';
import '../data/clients_repository.dart';
import '../domain/client.dart';

class AddClientDialog extends ConsumerStatefulWidget {
  const AddClientDialog({super.key, required this.onSaved, this.existing});

  final VoidCallback onSaved;
  final Client? existing;

  @override
  ConsumerState<AddClientDialog> createState() => _AddClientDialogState();
}

class _AddClientDialogState extends ConsumerState<AddClientDialog> {
  final _name = TextEditingController();
  String? _companySelection;
  final _code = TextEditingController();
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _name.text = widget.existing!.name;
      _companySelection = widget.existing!.company;
      _code.text = widget.existing!.code ?? '';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        await ref.read(clientsRepositoryProvider).update(
              id: widget.existing!.id,
              name: _name.text.trim(),
              company: _companySelection?.trim(),
              code: _code.text.trim(),
            );
      } else {
        final ownerId = ref.read(currentUserIdProvider);
        if (ownerId == null) throw StateError('not signed in');
        await ref.read(clientsRepositoryProvider).create(
              ownerId: ownerId,
              name: _name.text.trim(),
              company: _companySelection?.trim(),
              code: _code.text.trim(),
            );
      }
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      AppLogger.error('clients.addClient.save', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
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
                          : FontAwesomeIcons.userPlus,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEdit ? 'تعديل عميل' : 'إضافة عميل جديد',
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
              TextField(
                controller: _name,
                decoration:
                    const InputDecoration(labelText: 'اسم العميل'),
              ),
              const SizedBox(height: 14),
              ref.watch(exchangeCompaniesListProvider).when(
                    data: (companies) => DropdownButtonFormField<String>(
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
                      onChanged: (v) =>
                          setState(() => _companySelection = v),
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e'),
                  ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                decoration:
                    const InputDecoration(labelText: 'كود الحساب'),
              ),
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
