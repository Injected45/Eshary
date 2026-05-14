import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_provider.dart';
import '../features/companies/presentation/companies_providers.dart';
import '../features/currency_buy/presentation/currency_buys_providers.dart';
import '../features/transfers/presentation/transfers_providers.dart';
import 'logger.dart';

/// Sets up Supabase Realtime listeners on the workflow tables so that
/// changes coming from other devices (e.g. the admin archiving daily
/// rows while the employee app is open) flow into both apps
/// automatically. Each listener invalidates the relevant FutureProviders
/// so the next read pulls fresh data from the server.
///
/// Active for the lifetime of whichever widget watches this provider —
/// typically [HomeShell] or [EmployeeHomeShell]. The channel is closed
/// in `onDispose` when no widget watches it anymore.
///
/// REQUIRES: the workflow tables must be added to the `supabase_realtime`
/// publication in the Supabase project. See the SQL in the
/// 0027_enable_realtime.sql migration.
final realtimeSyncProvider = Provider<RealtimeChannel>((ref) {
  AppLogger.info('[sync] realtimeSyncProvider initialised — '
      'polling every 5s + Realtime channel attached');

  final client = ref.watch(supabaseClientProvider);
  var tick = 0;

  void invalidateWorkflow() {
    // `refresh` is stronger than `invalidate`: it both marks the provider
    // stale AND re-executes it for current watchers in the same frame.
    // `invalidate` alone leaves the value untouched until the next watch,
    // which is too lazy when the user is actively staring at the screen.
    ref.invalidate(dailyTransfersProvider);
    ref.invalidate(archivedTransfersProvider);
    ref.invalidate(dailyBuysProvider);
    ref.invalidate(pendingBuysProvider);
    ref.invalidate(archivedBuysProvider);
    ref.invalidate(allExchangesProvider);
  }

  // Coalesce bursts (e.g. an INSERT echoing back to this client). 400ms is
  // long enough to flatten a save burst but short enough that the other
  // device feels the change as "immediate". Critically: this also moves
  // the invalidation OUT of the current microtask so an in-flight save's
  // `context.push(...)` runs first and isn't interrupted by a rebuild.
  Timer? debounce;
  void scheduleInvalidate() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () {
      AppLogger.info('[sync] realtime → invalidating workflow providers');
      invalidateWorkflow();
    });
  }

  // Safety net: poll every 5s in case WebSocket / Realtime is blocked
  // (corporate proxy, browser tab throttling, Supabase realtime quota).
  // Riverpod won't re-fetch providers that no one is watching, so the
  // cost is bounded to whatever screen the user is currently on.
  final pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    tick++;
    AppLogger.info('[sync] poll tick #$tick — refreshing workflow data');
    invalidateWorkflow();
  });

  final channel = client
      .channel('eshary-workflow-sync')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'transfers',
        callback: (payload) {
          AppLogger.info('[realtime] transfers event: ${payload.eventType}');
          scheduleInvalidate();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'currency_buys',
        callback: (payload) {
          AppLogger.info('[realtime] currency_buys event: ${payload.eventType}');
          scheduleInvalidate();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'exchanges',
        callback: (payload) {
          AppLogger.info('[realtime] exchanges event: ${payload.eventType}');
          scheduleInvalidate();
        },
      )
      .subscribe((status, [error]) {
        AppLogger.info('[realtime] subscribe status=$status error=$error');
      });

  ref.onDispose(() {
    debounce?.cancel();
    pollTimer.cancel();
    channel.unsubscribe();
  });

  return channel;
});
