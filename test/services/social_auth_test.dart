import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:untitled/auth/widgets/brand_icon.dart';
import 'package:untitled/services/social_auth.dart';

void main() {
  test('maps Google and Microsoft UI providers to Supabase OAuth providers',
      () {
    expect(supabaseOAuthProvider(AuthProvider.google),
        supabase.OAuthProvider.google);
    expect(supabaseOAuthProvider(AuthProvider.microsoft),
        supabase.OAuthProvider.azure);
  });

  test('uses the Android app callback URL', () {
    expect(
      socialAuthRedirectForPlatform(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      'com.example.untitled://login-callback/',
    );
  });

  test('uses the app callback URL for Windows OAuth', () {
    expect(
      socialAuthRedirectForPlatform(
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      'com.example.untitled://login-callback/',
    );
  });

  test('uses the current origin for web OAuth', () {
    expect(
      socialAuthRedirectForPlatform(
        isWeb: true,
        platform: TargetPlatform.windows,
        currentUri: Uri.parse('https://example.com/login'),
      ),
      'https://example.com',
    );
  });

  test('rejects native OAuth on platforms without a callback', () {
    expect(
      () => socialAuthRedirectForPlatform(
        isWeb: false,
        platform: TargetPlatform.linux,
      ),
      throwsUnsupportedError,
    );
  });

  test('identifies OAuth providers from Supabase auth metadata', () {
    expect(isSocialAuthProvider('google'), isTrue);
    expect(isSocialAuthProvider('azure'), isTrue);
    expect(isSocialAuthProvider('email'), isFalse);
    expect(isSocialAuthProvider(null), isFalse);
  });

  test('does not subscribe when Supabase is not initialized', () {
    expect(listenForSocialAuth(() {}), isNull);
  });
}
