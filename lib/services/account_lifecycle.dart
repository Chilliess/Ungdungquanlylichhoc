import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final accountStatusRefresh = ValueNotifier<int>(0);

class AccountLifecycle {
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await Supabase.instance.client.rpc('account_deletion_status') as Map);
  Future<Map<String, dynamic>> restore() async =>
      Map<String, dynamic>.from(await Supabase.instance.client
          .rpc('restore_pending_account', params: {'p_confirm': true}) as Map);
  Future<void> signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    }
  }
}
