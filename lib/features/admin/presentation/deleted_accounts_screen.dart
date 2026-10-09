import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/theme.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../data/admin_repository.dart';
import '../domain/deleted_account.dart';

final _stamp = DateFormat('yyyy/MM/dd  HH:mm');

/// الإدارة → سجل الحسابات المحذوفة: who deleted which account and when, with the
/// e-mail and phone it had. Read-only; searchable by e-mail or phone.
class DeletedAccountsScreen extends ConsumerStatefulWidget {
  const DeletedAccountsScreen({super.key});

  @override
  ConsumerState<DeletedAccountsScreen> createState() =>
      _DeletedAccountsScreenState();
}

class _DeletedAccountsScreenState extends ConsumerState<DeletedAccountsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deletedAccountsProvider);
    final query = _search.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('سجل الحسابات المحذوفة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(deletedAccountsProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'بحث بالبريد الإلكتروني أو رقم الهاتف',
                  prefixIcon: Icon(Icons.search, color: AppColors.textLow),
                ),
              ),
            ),
            Expanded(
              child: async.when(
                skipLoadingOnReload: true,
                skipError: true,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      friendlyError(e),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textLow),
                    ),
                  ),
                ),
                data: (all) {
                  final rows = query.isEmpty
                      ? all
                      : all
                          .where(
                            (d) =>
                                d.email.toLowerCase().contains(query) ||
                                (d.phone ?? '').contains(query),
                          )
                          .toList();
                  if (rows.isEmpty) {
                    return Center(
                      child: Text(
                        all.isEmpty
                            ? 'لم يُحذف أي حساب بعد.'
                            : 'لا توجد نتائج',
                        style: const TextStyle(color: AppColors.textLow),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      contentBottomPadding(context),
                    ),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _Card(number: rows.length - i, d: rows[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.number, required this.d});
  final int number;
  final DeletedAccount d;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String value, {TextDirection? dir}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.textLow, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  textDirection: dir,
                  style: const TextStyle(
                    color: AppColors.textHigh,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    final setup = [
      if (d.companies > 0) '${d.companies} شركة',
      if (d.clients > 0) '${d.clients} عميل',
      if (d.employees > 0) '${d.employees} موظف',
    ];

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '#$number  ${d.email}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              color: AppColors.negative,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          line(
            'الهاتف',
            (d.phone ?? '').isEmpty ? '—' : d.phone!,
            dir: TextDirection.ltr,
          ),
          line('كان', d.statusLabel),
          if (d.accountCreated != null)
            line('تاريخ التسجيل', _stamp.format(d.accountCreated!)),
          line('وقت الحذف', _stamp.format(d.deletedAt)),
          line('حذفه', d.deletedByEmail ?? '—', dir: TextDirection.ltr),
          line('بيانات حُذفت معه', setup.isEmpty ? 'لا شيء' : setup.join(' · ')),
        ],
      ),
    );
  }
}
