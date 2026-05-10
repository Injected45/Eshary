import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_provider.dart';
import 'cache.dart';

/// Kind of transaction whose messages are pending dispatch.
enum DispatchKind { transfer, buyDaily, buyPending }

String _kindToDb(DispatchKind k) {
  switch (k) {
    case DispatchKind.transfer:
      return 'transfer';
    case DispatchKind.buyDaily:
      return 'buy_daily';
    case DispatchKind.buyPending:
      return 'buy_pending';
  }
}

DispatchKind _kindFromDb(String s) {
  switch (s) {
    case 'transfer':
      return DispatchKind.transfer;
    case 'buy_daily':
      return DispatchKind.buyDaily;
    case 'buy_pending':
      return DispatchKind.buyPending;
  }
  return DispatchKind.transfer;
}

/// In-flight messaging session: the transaction has already been saved
/// to Supabase, and the user is now sharing the generated messages to
/// external apps (WhatsApp, Telegram, ...). State is mirrored to
/// SharedPreferences so it survives the activity being killed when an
/// external app takes the foreground.
class PendingDispatch {
  PendingDispatch({
    required this.kind,
    required this.savedRecordId,
    required this.messages,
    required this.openedIndices,
    required this.cardTitles,
    required this.savedAt,
  });

  final DispatchKind kind;
  final String savedRecordId;
  final List<String> messages;
  final Set<int> openedIndices;
  final List<String> cardTitles;
  final DateTime savedAt;

  PendingDispatch copyWith({
    Set<int>? openedIndices,
  }) =>
      PendingDispatch(
        kind: kind,
        savedRecordId: savedRecordId,
        messages: messages,
        openedIndices: openedIndices ?? this.openedIndices,
        cardTitles: cardTitles,
        savedAt: savedAt,
      );

  Map<String, dynamic> toJson() => {
        'kind': _kindToDb(kind),
        'saved_record_id': savedRecordId,
        'messages': messages,
        'opened': openedIndices.toList(),
        'titles': cardTitles,
        'saved_at': savedAt.toIso8601String(),
      };

  factory PendingDispatch.fromJson(Map<String, dynamic> j) => PendingDispatch(
        kind: _kindFromDb(j['kind'] as String),
        savedRecordId: j['saved_record_id'] as String,
        messages:
            (j['messages'] as List<dynamic>).map((e) => e as String).toList(),
        openedIndices: <int>{
          for (final v in (j['opened'] as List<dynamic>? ?? const []))
            (v as num).toInt(),
        },
        cardTitles:
            (j['titles'] as List<dynamic>).map((e) => e as String).toList(),
        savedAt: DateTime.parse(j['saved_at'] as String),
      );
}

String _prefsKey(String? uid) => 'cache:pending_dispatch:${uid ?? 'anon'}';

class PendingDispatchNotifier extends StateNotifier<PendingDispatch?> {
  PendingDispatchNotifier(this._prefs, this._uid) : super(null) {
    _restore();
  }

  final SharedPreferences _prefs;
  final String? _uid;

  void _restore() {
    final raw = _prefs.getString(_prefsKey(_uid));
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      state = PendingDispatch.fromJson(map);
    } catch (_) {
      _prefs.remove(_prefsKey(_uid));
    }
  }

  Future<void> begin(PendingDispatch dispatch) async {
    state = dispatch;
    await _prefs.setString(
      _prefsKey(_uid),
      jsonEncode(dispatch.toJson()),
    );
  }

  Future<void> markOpened(int index) async {
    final current = state;
    if (current == null) return;
    if (current.openedIndices.contains(index)) return;
    final updated = current.copyWith(
      openedIndices: {...current.openedIndices, index},
    );
    state = updated;
    await _prefs.setString(
      _prefsKey(_uid),
      jsonEncode(updated.toJson()),
    );
  }

  Future<void> finish() async {
    state = null;
    await _prefs.remove(_prefsKey(_uid));
  }
}

final pendingDispatchProvider =
    StateNotifierProvider<PendingDispatchNotifier, PendingDispatch?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final uid = ref.watch(currentUserIdProvider);
  return PendingDispatchNotifier(prefs, uid);
});
