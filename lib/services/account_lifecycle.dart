import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final accountStatusRefresh = ValueNotifier<int>(0);

class AccountLifecycle {
  /// Server-maintained app metadata is a UI hint; database RLS remains the
  /// authority for every operation. Normal accounts need no extra status RPC.
  bool get requiresRestoration =>
      Supabase.instance.client.auth.currentUser
          ?.appMetadata['account_deletion_pending'] ==
      true;
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await Supabase.instance.client.rpc('account_deletion_status') as Map);
  Future<Map<String, dynamic>> restore() async {
    final client = Supabase.instance.client;
    final owner = client.auth.currentUser?.id;
    final result = Map<String, dynamic>.from(await client
        .rpc('restore_pending_account', params: {'p_confirm': true}) as Map);
    if (result['status'] == 'active' && client.auth.currentUser?.id == owner) {
      try {
        await client.auth.refreshSession().timeout(const Duration(seconds: 10));
      } catch (_) {
        // Restoration already committed; a refresh failure must not undo it.
      }
    }
    return result;
  }

  Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    }
  }
}
