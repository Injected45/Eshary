import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../features/clients/presentation/clients_providers.dart';
import '../features/companies/domain/company.dart';
import '../features/companies/domain/exchange.dart';
import '../features/companies/presentation/companies_providers.dart';
import '../features/currency_buy/domain/currency_buy.dart';
import '../features/transfers/domain/transfer.dart';
import 'creator_chip.dart';
import 'formatters.dart';
import 'glass.dart';

/// Outgoing transfer details — a full-screen page (no horizontal scrolling),
/// two coloured sections:
///   - "خروج من حسابي" (red): admin's own company / exchange / code +
///     reference + amount.
///   - "جهة الاستلام" (green): beneficiary company + account + code.
///
/// Both the admin's transfers screen daily table and the employee's
/// "سجلاتي" tab open this same page.
void showTransferDetails(
  BuildContext context, {
  required Transfer transfer,
  String? companyName,
  String? exchangeName,
  String? exchangeCode,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _DetailsPage(
        title: 'تفاصيل عملية خروج',
        accent: AppColors.negative,
        createdAt: transfer.createdAt,
        sections: [
          _DetailSection(
            title: 'خروج من حسابي',
            icon: FontAwesomeIcons.shop,
            accent: AppColors.negative,
            rows: [
              _Kv('اسم الشركة', exchangeName ?? '—'),
              _Kv('اسم حسابي', companyName ?? '—'),
              _Kv(
                'رقم حسابي',
                (exchangeCode == null || exchangeCode.isEmpty)
                    ? '—'
                    : exchangeCode,
              ),
              _Kv('الإشاري', transfer.reference),
              _Kv(
                'القيمة',
                '\$ ${formatMoney(transfer.amount)}',
                color: AppColors.negative,
              ),
            ],
          ),
          _DetailSection(
            title: 'جهة الاستلام',
            icon: FontAwesomeIcons.user,
            accent: AppColors.positive,
            rows: [
              _Kv(
                'الشركة المستفيدة',
                (transfer.beneficiaryAccountCompany?.isEmpty ?? true)
                    ? '—'
                    : transfer.beneficiaryAccountCompany!,
              ),
              _Kv('حساب المستلم', transfer.beneficiaryName),
              _Kv(
                'كود حساب المستلم',
                (transfer.beneficiaryCode?.isEmpty ?? true)
                    ? '—'
                    : transfer.beneficiaryCode!,
              ),
            ],
          ),
          _DetailSection(
            title: 'معلومات العملية',
            icon: FontAwesomeIcons.circleInfo,
            accent: AppColors.accent,
            rows: [
              _Kv(
                'المنفّذ',
                '',
                child: CreatorChip(
                  createdByEmployeeId: transfer.createdByEmployeeId,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Incoming currency_buy details — a full-screen page mirroring the outgoing
/// layout with role-flipped colours: green for "لحسابي", red for the sender.
void showCurrencyBuyDetails(
  BuildContext context,
  WidgetRef ref, {
  required CurrencyBuy buy,
}) {
  final companies =
      ref.read(companiesListProvider).value ?? const <Company>[];
  final exchanges =
      ref.read(allExchangesProvider).value ?? const <Exchange>[];
  final clients = ref.read(clientsListProvider).value ?? const [];

  String? findCompany(String id) =>
      companies.where((c) => c.id == id).map((c) => c.name).firstOrNull;
  Exchange? findExchange(String id) =>
      exchanges.where((e) => e.id == id).firstOrNull;

  final exchange = findExchange(buy.exchangeId);
  final clientMatch = buy.clientId == null
      ? null
      : clients.where((c) => c.id == buy.clientId).firstOrNull;
  final clientName = clientMatch?.name ??
      ((buy.clientFromAccount?.isEmpty ?? true)
          ? '—'
          : buy.clientFromAccount!);
  final clientCompany = (clientMatch?.company?.isEmpty ?? true)
      ? ((buy.clientFromAccount?.isEmpty ?? true)
          ? '—'
          : buy.clientFromAccount!)
      : clientMatch!.company!;
  final clientCode = (clientMatch?.code?.isEmpty ?? true)
      ? '—'
      : clientMatch!.code!;

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _DetailsPage(
        title: 'تفاصيل عملية دخول',
        accent: AppColors.positive,
        createdAt: buy.createdAt,
        sections: [
          _DetailSection(
            title: 'دخول الى حسابي',
            icon: FontAwesomeIcons.shop,
            accent: AppColors.positive,
            rows: [
              _Kv('اسم الشركة', exchange?.name ?? '—'),
              _Kv('اسم حسابي', findCompany(buy.myCompanyId) ?? '—'),
              _Kv(
                'رقم حسابي',
                (exchange?.ourCode?.isEmpty ?? true)
                    ? '—'
                    : exchange!.ourCode!,
              ),
            ],
          ),
          _DetailSection(
            title: 'الجهة المرسلة',
            icon: FontAwesomeIcons.user,
            accent: AppColors.negative,
            rows: [
              _Kv('الشركة المرسلة', clientCompany),
              _Kv('حساب المرسل', clientName),
              _Kv('كود حساب المرسل', clientCode),
              _Kv(
                'الإشاري',
                buy.reference.isEmpty ? '—' : buy.reference,
              ),
              _Kv(
                'القيمة',
                '\$ ${formatMoney(buy.usdAmount)}',
                color: AppColors.positive,
              ),
            ],
          ),
          _DetailSection(
            title: 'معلومات العملية',
            icon: FontAwesomeIcons.circleInfo,
            accent: AppColors.accent,
            rows: [
              _Kv(
                'المنفّذ',
                '',
                child: CreatorChip(
                  createdByEmployeeId: buy.createdByEmployeeId,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Full-screen details page: the whole record fits on one screen and only
/// scrolls vertically when the phone is too short.
class _DetailsPage extends StatelessWidget {
  const _DetailsPage({
    required this.title,
    required this.accent,
    required this.createdAt,
    required this.sections,
  });

  final String title;
  final Color accent;
  final DateTime createdAt;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          contentTopPadding(context),
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          _DateLine(createdAt: createdAt, accent: accent),
          const SizedBox(height: 14),
          for (final s in sections) ...[
            s,
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _DateLine extends StatelessWidget {
  const _DateLine({required this.createdAt, required this.accent});

  final DateTime createdAt;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final local = createdAt.toLocal();
    final dateStr = DateFormat('dd-MM-yyyy').format(local);
    final hour12 = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final amPm = local.hour < 12 ? 'ص' : 'م';
    final timeStr =
        '${hour12.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $amPm';

    return Row(
      children: [
        FaIcon(FontAwesomeIcons.calendarDays, size: 14, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'التاريخ والوقت : $dateStr ، $timeStr',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textLow,
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled key/value pair, optionally tinted (used to highlight the
/// amount in green / red depending on direction). [child] replaces the text
/// value when a widget is needed (e.g. the creator chip).
class _Kv {
  const _Kv(this.label, this.value, {this.color, this.child});
  final String label;
  final String value;
  final Color? color;
  final Widget? child;
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<_Kv> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FaIcon(icon, size: 14, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++) ...[
            _DetailRow(
              label: rows[i].label,
              value: rows[i].value,
              valueColor: rows[i].color,
              child: rows[i].child,
            ),
            if (i < rows.length - 1)
              const Divider(
                height: 1,
                thickness: 0.5,
                color: AppColors.glassBorder,
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.child,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textLow,
              ),
            ),
          ),
          const Text(
            ':',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textLow,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: child != null
                ? Align(alignment: Alignment.center, child: child)
                : Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? AppColors.textHigh,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
