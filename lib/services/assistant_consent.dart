import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Consent is a preference, never an authorization or access-control flag.
class AssistantConsent {
  AssistantConsent({this.readAccount, this.acceptAccount});

  factory AssistantConsent.supabase(SupabaseClient client) => AssistantConsent(
        readAccount: (owner) async {
          final user =
              (await client.auth.getUser().timeout(const Duration(seconds: 10)))
                  .user;
          if (user?.id != owner) throw StateError('Account changed');
          return user?.userMetadata?['study_assistant_consent_version'] == 1;
        },
        acceptAccount: (owner) async {
          if (client.auth.currentUser?.id != owner) {
            throw StateError('Account changed');
          }
          final result = await client.auth
              .updateUser(UserAttributes(data: {
                'study_assistant_consent_version': 1,
                'study_assistant_consent_at':
                    DateTime.now().toUtc().toIso8601String(),
              }))
              .timeout(const Duration(seconds: 10));
          if (result.user?.id != owner) throw StateError('Account changed');
        },
      );

  final Future<bool> Function(String owner)? readAccount;
  final Future<void> Function(String owner)? acceptAccount;
  static String key(String owner) => 'assistant_consent_v1_$owner';

  Future<bool> load(String owner) async {
    final preferences = await SharedPreferences.getInstance();
    final cached = preferences.getBool(key(owner)) == true;
    if (readAccount == null) return cached;
    try {
      if (await readAccount!(owner)) {
        // Account remains authoritative even if browser storage is unavailable.
        try {
          await preferences.setBool(key(owner), true);
        } catch (_) {}
        return true;
      }
      if (cached) {
        // Migrate an explicit acceptance recorded by older app versions.
        await acceptAccount?.call(owner);
      }
      return cached;
    } catch (_) {
      if (cached) return true;
      rethrow;
    }
  }

  Future<void> accept(String owner) async {
    if (acceptAccount != null) await acceptAccount!(owner);
    try {
      final saved = await (await SharedPreferences.getInstance())
          .setBool(key(owner), true);
      if (!saved && acceptAccount == null) throw StateError('Not saved');
    } catch (_) {
      if (acceptAccount == null) rethrow;
    }
  }
}
