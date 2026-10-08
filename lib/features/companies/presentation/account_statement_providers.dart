import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../currency_buy/data/currency_buys_repository.dart';
import '../../currency_buy/domain/currency_buy.dart';
import '../../transfers/data/transfers_repository.dart';
import '../../transfers/domain/transfer.dart';

/// Everything posted in a period, for the account statement.
typedef StatementData = ({List<Transfer> transfers, List<CurrencyBuy> buys});

/// Posted exits and entries in [range], oldest first. The statement screen
/// filters them further (whose, which account) without asking the server again.
final statementDataProvider = FutureProvider.autoDispose
    .family<StatementData, DateTimeRange>((ref, range) async {
  final transfers = await ref
      .watch(transfersRepositoryProvider)
      .listArchivedBetween(range.start, range.end);
  final buys = await ref
      .watch(currencyBuysRepositoryProvider)
      .listArchivedBetween(range.start, range.end);
  return (transfers: transfers, buys: buys);
});
