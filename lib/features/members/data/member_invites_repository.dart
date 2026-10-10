import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_provider.dart';
import '../domain/member_invite.dart';

/// The administrator's side of the invitations (0058_member_invites.sql).
class MemberInvitesRepository {
  MemberInvitesRepository(this._client);
  final SupabaseClient _client;

  Future<CreatedInvite> create({
    required String name,
    required String phone,
    required InviteLicense license,
    int hours = 24,
  }) async {
    final res = await _client.rpc<List<dynamic>>(
      'admin_create_member_invite',
      params: {
        'p_name': name.trim(),
        'p_phone': phone.trim(),
        'p_license': license.db,
        'p_hours': hours,
      },
    );
    return CreatedInvite.fromJson(res.first as Map<String, dynamic>);
  }

  Future<List<MemberInvite>> list() async {
    final res = await _client.rpc<List<dynamic>>('admin_list_member_invites');
    return res
        .cast<Map<String, dynamic>>()
        .map(MemberInvite.fromJson)
        .toList();
  }

  Future<void> revoke(String id) async {
    await _client.rpc<dynamic>(
      'admin_revoke_member_invite',
      params: {'p_id': id},
    );
  }
}

final memberInvitesRepositoryProvider =
    Provider<MemberInvitesRepository>((ref) {
  return MemberInvitesRepository(ref.watch(supabaseClientProvider));
});

final memberInvitesProvider =
    FutureProvider.autoDispose<List<MemberInvite>>((ref) {
  return ref.watch(memberInvitesRepositoryProvider).list();
});
