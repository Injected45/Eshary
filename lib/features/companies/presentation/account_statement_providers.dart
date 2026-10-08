import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../currency_buy/data/currency_buys_repository.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../transfers/data/transfers_repository.dart';
import '../../transfers/domain/transfer.dart';

/// Everything posted in a period, for the account statement.
typedef StatementData = ({List<Transfer> transfers, List<CurrencyBuy> buys});

/// Posted exits and entries from the start of [range] up to now (or to the
/// end of the range, if later), oldest first. The screen shows the part inside
/// the range and uses the rest to work out the opening balance; it filters by
/// person and account without asking the server again.
final statementDataProvider = FutureProvider.autoDispose
    .family<StatementData, DateTimeRange>((ref, range) async {
  final now = DateTime.now();
  final until = range.end.isAfter(now) ? range.end : now;
  final transfers = await ref
      .watch(transfersRepositoryProvider)
      .listArchivedBetween(range.start, until);
  final buys = await ref
      .watch(currencyBuysRepositoryProvider)
      .listArchivedBetween(range.start, until);
  return (transfers: transfers, buys: buys);
});
