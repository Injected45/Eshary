import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/logger.dart';
import '../domain/exchange.dart';
import 'companies_providers.dart';

/// What the exit / entry forms say when no exchange company can be offered. It
/// tells the three causes apart instead of one message for all of them:
///  * the accounts could not be LOADED (a failure, not an empty list);
///  * there really is no account yet;
///  * accounts exist, but none carries the name of a company in the exchange
///    companies list (an account is linked to its company by NAME).
class NoAccountNotice extends ConsumerWidget {
  const NoAccountNotice({
    super.key,
    required this.exchanges,
    required this.exchangeCompanyNames,
  });

  final AsyncValue<List<Exchange>> exchanges;

  /// The names in "شركات الصرافة".
  final List<String> exchangeCompanyNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = exchanges.valueOrNull ?? const <Exchange>[];

    Widget box(Widget child) => InputDecorator(
          decoration: const InputDecoration(),
          child: child,
        );
    const low = TextStyle(color: AppColors.textLow, height: 1.5);

    if (exchanges.hasError && !exchanges.hasValue) {
      return box(
        Column(
          key: const ValueKey('accounts-load-failed'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تعذّر تحميل حساباتك الآن، وليس أنها غير موجودة.',
              style: TextStyle(color: AppColors.negative, height: 1.5),
            ),
            Text(friendlyError(exchanges.error!), style: low),
            TextButton(
              key: const ValueKey('accounts-retry'),
              onPressed: () => ref.invalidate(allExchangesProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (mine.isEmpty) {
      return box(
        const Text(
          'لا توجد شركة لديك فيها حساب — أضف حساباً من تبويب حساباتي',
          key: ValueKey('accounts-none'),
          style: low,
        ),
      );
    }

    final known = exchangeCompanyNames.toSet();
    final missing = {for (final e in mine) e.name}.difference(known).toList()
      ..sort();
    return box(
      Column(
        key: const ValueKey('accounts-unmatched'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'لديك ${mine.length} حساب، لكن اسم شركته ليس في قائمة '
            '«شركات الصرافة»: ${missing.join('، ')}',
            style: const TextStyle(color: AppColors.warning, height: 1.5),
          ),
          const Text(
            'أضف الشركة بالاسم نفسه تمامًا من إعدادات الحوالات ← شركات الصرافة، '
            'أو عدّل اسم الحساب ليطابقها.',
            style: low,
          ),
        ],
      ),
    );
  }
}
