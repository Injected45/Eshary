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
import 'formatters.dart';
import 'glass.dart';

/// Outgoing transfer details popup — two coloured sections:
///   - "خروج من حسابي" (red): admin's own company / exchange / code +
///     reference + amount.
///   - "جهة الاستلام" (green): beneficiary company + account + code.
///
/// Both the admin's transfers screen daily table and the employee's
/// "سجلاتي" tab open this same dialog.
void showTransferDetails(
  BuildContext context, {
  required Transfer transfer,
  String? companyName,
  String? exchangeName,
  String? exchangeCode,
}) {
  showGlassDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeader(
                title: 'تفاصيل عملية خروج',
                accent: AppColors.negative,
                createdAt: transfer.createdAt,
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 12),
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
            ],
          ),
        ),
      ),
    ),
  );
}

/// Incoming currency_buy details popup — mirrors the outgoing layout
/// with role-flipped colours: green for "لحسابي", red-ish accent for
/// the sender.
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
      ? '—'
      : clientMatch!.company!;
  final clientCode = (clientMatch?.code?.isEmpty ?? true)
      ? '—'
      : clientMatch!.code!;

  showGlassDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeader(
                title: 'تفاصيل عملية دخول',
                accent: AppColors.positive,
                createdAt: buy.createdAt,
              ),
              const SizedBox(height: 14),
              _DetailSection(
                title: 'حسابي المستفيد',
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
              const SizedBox(height: 12),
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
            ],
          ),
        ),
      ),
    ),
  );
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.accent,
    required this.createdAt,
  });

  final String title;
  final Color accent;
  final DateTime createdAt;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
                border: Border.all(color: accent, width: 1.5),
              ),
              child: FaIcon(
                FontAwesomeIcons.chevronUp,
                size: 11,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHigh,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const FaIcon(FontAwesomeIcons.xmark, size: 16),
              color: AppColors.textLow,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'التاريخ والوقت : $dateStr ، $timeStr',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textLow,
          ),
        ),
      ],
    );
  }
}

/// A labelled key/value pair, optionally tinted (used to highlight the
/// amount in green / red depending on direction).
class _Kv {
  const _Kv(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                  fontSize: 14,
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
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
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
          const Text(
            ':',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textLow,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
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
