import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_provider.dart';
import '../../../core/theme.dart';
import '../../../shared/formatters.dart';
import '../../../shared/glass.dart';
import '../../../shared/logger.dart';
import '../../../shared/pdf_export.dart';
import '../../archive/presentation/archive_filters.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../../sub_users/domain/sub_user.dart';
import '../../sub_users/presentation/sub_users_providers.dart';
import '../domain/account_statement.dart';
import '../domain/company.dart';
import '../domain/exchange.dart';
import 'account_statement_providers.dart';
import 'companies_providers.dart';

/// "كشف حساب": a short statement — دخول | خروج | الرصيد — that the admin can
/// cut by who did the operations (everyone, the admin, one employee), by
/// period and by account. Entries are green, exits red; the balance is a
/// running total.
class AccountStatementScreen extends ConsumerStatefulWidget {
  const AccountStatementScreen({super.key});

  @override
  ConsumerState<AccountStatementScreen> createState() =>
      _AccountStatementScreenState();
}

class _AccountStatementScreenState
    extends ConsumerState<AccountStatementScreen> {
  DateFilterMode _mode = DateFilterMode.today;
  DateTime? _from;
  DateTime? _to;
  StatementScope _scope = StatementScope.all;
  String? _employeeId;
  String? _exchangeId;
  bool _exporting = false;

  static final _dateFmt = DateFormat('yyyy/MM/dd');
  static final _timeFmt = DateFormat('HH:mm');

  bool get _rangeReady =>
      _from != null && _to != null && !_from!.isAfter(_to!);

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: _to ?? DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: _from ?? DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _to = picked);
  }

  String _rangeLabel(({DateTime start, DateTime end}) r) {
    final a = _dateFmt.format(r.start);
    final b = _dateFmt.format(r.end);
    return a == b ? a : '$a → $b';
  }

  String _scopeLabel(Map<String, SubUser> employees) {
    switch (_scope) {
      case StatementScope.all:
        return 'الكل';
      case StatementScope.me:
        return 'أنا';
      case StatementScope.employee:
        return employees[_employeeId]?.employeeName ?? 'موظف';
    }
  }

  Future<void> _export({
    required AccountStatement statement,
    required ({DateTime start, DateTime end}) range,
    required Map<String, SubUser> employees,
    required String accountLabel,
  }) async {
    setState(() => _exporting = true);
    try {
      final user = ref.read(supabaseClientProvider).auth.currentUser;
      final meta = user?.userMetadata ?? const <String, dynamic>{};
      final exportedBy =
          (meta['full_name'] as String?)?.trim().isNotEmpty == true
              ? meta['full_name'] as String
              : (meta['name'] as String?)?.trim().isNotEmpty == true
                  ? meta['name'] as String
                  : (user?.email ?? 'admin');
      String? notif;
      try {
        notif = (await ref.read(latestNotificationProvider.future))?.body;
      } catch (_) {
        notif = null;
      }
      final pdf = await PdfExport.load();
      final bytes = await pdf.buildAccountStatement(
        rows: [
          for (final e in statement.entries)
            (
              at: e.at,
              who: e.employeeId == null
                  ? 'المدير'
                  : (employees[e.employeeId]?.employeeName ?? '—'),
              income: e.income,
              outgoing: e.outgoing,
              balance: e.balance,
            ),
        ],
        incomeTotal: statement.totalIncome,
        outgoingTotal: statement.totalOutgoing,
        scopeLabel: _scopeLabel(employees),
        accountLabel: accountLabel,
        rangeLabel: _rangeLabel(range),
        showWho: _scope == StatementScope.all,
        exportedBy: exportedBy,
        notificationText: notif,
      );
      await PdfExport.sharePdf(bytes, 'account_statement.pdf');
    } catch (e, st) {
      AppLogger.error('accountStatement.export', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = resolveActiveRange(mode: _mode, from: _from, to: _to);
    final range = DateTimeRange(start: r.start, end: r.end);
    final dataAsync = ref.watch(statementDataProvider(range));

    final employeeList =
        ref.watch(subUsersListProvider).valueOrNull ?? const <SubUser>[];
    final employees = {for (final e in employeeList) e.id: e};
    final exchanges =
        ref.watch(allExchangesProvider).valueOrNull ?? const <Exchange>[];
    final companies = {
      for (final c
          in ref.watch(companiesListProvider).valueOrNull ?? const <Company>[])
        c.id: c,
    };
    String exchangeLabel(Exchange e) =>
        '${companies[e.companyId]?.name ?? '—'} — ${e.name}';
    final accountLabel = _exchangeId == null
        ? 'كل الحسابات'
        : exchanges
            .where((e) => e.id == _exchangeId)
            .map(exchangeLabel)
            .firstOrNull ??
            '—';

    AccountStatement? statement;
    final data = dataAsync.valueOrNull;
    if (data != null) {
      statement = buildAccountStatement(
        buys: data.buys,
        transfers: data.transfers,
        start: r.start,
        end: r.end,
        scope: _scope,
        employeeId: _employeeId,
        exchangeId: _exchangeId,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('كشف حساب'),
        backgroundColor: AppColors.bgDeep.withValues(alpha: 0.35),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'تصدير PDF',
            onPressed: (statement == null || _exporting)
                ? null
                : () => _export(
                      statement: statement!,
                      range: r,
                      employees: employees,
                      accountLabel: accountLabel,
                    ),
            icon: _exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const FaIcon(FontAwesomeIcons.filePdf, size: 16),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const FaIcon(FontAwesomeIcons.arrowsRotate, size: 14),
            onPressed: () => ref.invalidate(statementDataProvider(range)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          DateFilterBar(
            mode: _mode,
            from: _from,
            to: _to,
            onModeChanged: (m) => setState(() {
              _mode = m;
              if (m == DateFilterMode.today) {
                _from = null;
                _to = null;
              }
            }),
            onPickFrom: _pickFrom,
            onPickTo: _pickTo,
            showInvalidHint: _mode == DateFilterMode.range && !_rangeReady,
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'كشف حساب',
                  style: TextStyle(
                    color: AppColors.textMid,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<StatementScope>(
                  segments: const [
                    ButtonSegment(
                      value: StatementScope.all,
                      label: Text('الكل'),
                    ),
                    ButtonSegment(
                      value: StatementScope.me,
                      label: Text('أنا'),
                    ),
                    ButtonSegment(
                      value: StatementScope.employee,
                      label: Text('موظف'),
                    ),
                  ],
                  selected: {_scope},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() {
                    _scope = s.first;
                    if (_scope == StatementScope.employee &&
                        _employeeId == null &&
                        employeeList.isNotEmpty) {
                      _employeeId = employeeList.first.id;
                    }
                  }),
                ),
                if (_scope == StatementScope.employee) ...[
                  const SizedBox(height: 10),
                  if (employeeList.isEmpty)
                    const Text(
                      'لا يوجد موظفون بعد.',
                      style: TextStyle(color: AppColors.textLow, fontSize: 12),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: employees.containsKey(_employeeId)
                          ? _employeeId
                          : employeeList.first.id,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(hintText: 'اختر الموظف'),
                      items: [
                        for (final e in employeeList)
                          DropdownMenuItem(
                            value: e.id,
                            child: Text(e.employeeName),
                          ),
                      ],
                      onChanged: (v) => setState(() => _employeeId = v),
                    ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: exchanges.any((e) => e.id == _exchangeId)
                      ? _exchangeId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(hintText: 'الحساب'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل الحسابات'),
                    ),
                    for (final e in exchanges)
                      DropdownMenuItem<String?>(
                        value: e.id,
                        child: Text(
                          exchangeLabel(e),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _exchangeId = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (dataAsync.isLoading && statement == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (dataAsync.hasError && statement == null)
            GlassCard(
              child: Text(
                friendlyError(dataAsync.error!),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textLow),
              ),
            )
          else if (statement != null) ...[
            _Totals(statement: statement),
            const SizedBox(height: 12),
            _StatementTable(
              statement: statement,
              showWho: _scope == StatementScope.all,
              whoOf: (id) => id == null
                  ? 'المدير'
                  : (employees[id]?.employeeName ?? '—'),
              dateFmt: _dateFmt,
              timeFmt: _timeFmt,
            ),
          ],
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.statement});
  final AccountStatement statement;

  @override
  Widget build(BuildContext context) {
    final balance = statement.balance;
    return Row(
      children: [
        Expanded(
          child: _Tile(
            label: 'إجمالي الدخول',
            value: '+\$${formatMoney(statement.totalIncome)}',
            color: AppColors.positive,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            label: 'إجمالي الخروج',
            value: '-\$${formatMoney(statement.totalOutgoing)}',
            color: AppColors.negative,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Tile(
            label: 'الرصيد',
            value:
                '${balance >= 0 ? '' : '-'}\$${formatMoney(balance.abs())}',
            color: balance >= 0 ? AppColors.positive : AppColors.negative,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textLow, fontSize: 11),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementTable extends StatelessWidget {
  const _StatementTable({
    required this.statement,
    required this.showWho,
    required this.whoOf,
    required this.dateFmt,
    required this.timeFmt,
  });

  final AccountStatement statement;
  final bool showWho;
  final String Function(String? employeeId) whoOf;
  final DateFormat dateFmt;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    if (statement.isEmpty) {
      return const GlassCard(
        padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Text(
          'لا توجد عمليات في هذه الفترة.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textLow, fontSize: 13),
        ),
      );
    }

    Widget head(String t) => Expanded(
          child: Text(
            t,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMid,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        );

    Widget money(double? v, Color color, {bool bold = false}) => Expanded(
          child: Text(
            v == null ? '' : formatMoney(v),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        );

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: const Text(
                  'التاريخ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMid,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              head('دخول'),
              head('خروج'),
              head('الرصيد'),
            ],
          ),
          const Divider(color: AppColors.glassBorder, height: 14),
          for (final e in statement.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Text(
                          dateFmt.format(e.at),
                          style: const TextStyle(
                            color: AppColors.textHigh,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          showWho
                              ? '${timeFmt.format(e.at)} · ${whoOf(e.employeeId)}'
                              : timeFmt.format(e.at),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textLow,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  money(e.income, AppColors.positive),
                  money(e.outgoing, AppColors.negative),
                  money(
                    e.balance,
                    e.balance >= 0 ? AppColors.positive : AppColors.negative,
                    bold: true,
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.glassBorder, height: 1),
          ],
        ],
      ),
    );
  }
}
