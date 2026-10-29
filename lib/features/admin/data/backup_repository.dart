import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';

class BackupInfo {
  const BackupInfo({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String id;

  /// 'auto' | 'manual' | 'pre_restore'
  final String kind;
  final DateTime createdAt;
  final int sizeBytes;

  factory BackupInfo.fromJson(Map<String, dynamic> j) => BackupInfo(
        id: j['id'] as String,
        kind: j['kind'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
      );
}

/// One subscriber found in a stored backup.
class BackupOwner {
  const BackupOwner({
    required this.ownerId,
    required this.name,
    required this.email,
    required this.exists,
    required this.transfers,
    required this.currencyBuys,
  });

  final String ownerId;
  final String name;
  final String? email;

  /// false: the account was deleted since; it cannot be restored.
  final bool exists;
  final int transfers;
  final int currencyBuys;

  factory BackupOwner.fromJson(Map<String, dynamic> j) => BackupOwner(
        ownerId: j['owner_id'] as String,
        name: (j['name'] as String?) ?? (j['email'] as String?) ?? '—',
        email: j['email'] as String?,
        exists: j['exists'] as bool? ?? false,
        transfers: (j['transfers'] as num?)?.toInt() ?? 0,
        currencyBuys: (j['currency_buys'] as num?)?.toInt() ?? 0,
      );
}

class BackupRepository {
  BackupRepository(this._client);
  final SupabaseClient _client;

  Future<List<BackupInfo>> list() async {
    final res = await _client.rpc<List<dynamic>>('admin_list_backups');
    return res.cast<Map<String, dynamic>>().map(BackupInfo.fromJson).toList();
  }

  /// Stores a manual snapshot server-side and returns its id.
  Future<String> backupNow() async {
    final id = await _client.rpc<String>('admin_backup_now');
    return id;
  }

  /// Live snapshot of the database, for downloading.
  Future<Map<String, dynamic>> export() async {
    final res = await _client.rpc<Map<String, dynamic>>('admin_export_backup');
    return res;
  }

  Future<Map<String, dynamic>> get(String id) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'admin_get_backup',
      params: {'p_id': id},
    );
    return res;
  }

  /// Deletes the chosen stored snapshots to free space. The database refuses to
  /// delete the last one. Returns how many were deleted.
  Future<int> deleteMany(List<String> ids) async {
    final res = await _client.rpc<dynamic>(
      'admin_delete_backups',
      params: {'p_ids': ids},
    );
    return (res as num).toInt();
  }

  /// The subscribers in the stored backup [id] (admin_backup_owners, 0088).
  Future<List<BackupOwner>> owners(String id) async {
    final res = await _client.rpc<List<dynamic>>(
      'admin_backup_owners',
      params: {'p_backup_id': id},
    );
    return res.cast<Map<String, dynamic>>().map(BackupOwner.fromJson).toList();
  }

  /// Puts ONE subscriber back as in the stored backup [id]; every other
  /// subscriber stays as they are (admin_restore_owner, 0088).
  Future<Map<String, dynamic>> restoreOwner(String id, String ownerId) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'admin_restore_owner',
      params: {'p_backup_id': id, 'p_owner': ownerId},
    );
    return res;
  }

  /// Replaces the WHOLE platform's operational data with [backup] (every
  /// subscriber). For a real disaster only. Returns rows restored per table.
  Future<Map<String, dynamic>> restore(Map<String, dynamic> backup) async {
    final res = await _client.rpc<Map<String, dynamic>>(
      'admin_restore_backup',
      params: {'p_backup': backup},
    );
    return res;
  }
}

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(ref.watch(supabaseClientProvider));
});

final backupsListProvider =
    FutureProvider.autoDispose<List<BackupInfo>>((ref) async {
  return ref.watch(backupRepositoryProvider).list();
});
