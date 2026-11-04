import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../auth/widgets/brand_icon.dart';

const socialAuthRedirectUrl = 'com.example.untitled://login-callback/';

String socialAuthRedirectForPlatform({
  required bool isWeb,
  required TargetPlatform platform,
  Uri? currentUri,
}) {
  if (isWeb) return (currentUri ?? Uri.base).origin;
  if (platform == TargetPlatform.android ||
      platform == TargetPlatform.windows) {
    return socialAuthRedirectUrl;
  }
  throw UnsupportedError(
    'Google and Microsoft OAuth are configured for Android, Windows, and web only.',
  );
}

supabase.OAuthProvider supabaseOAuthProvider(AuthProvider provider) =>
    switch (provider) {
      AuthProvider.google => supabase.OAuthProvider.google,
      AuthProvider.microsoft => supabase.OAuthProvider.azure,
    };

bool isSocialAuthProvider(String? provider) =>
    provider == 'google' || provider == 'azure';

StreamSubscription<supabase.AuthState>? listenForSocialAuth(
  void Function() onSignedIn,
) {
  // Login screens also render in previews and tests before Supabase initializes.
  try {
    return supabase.Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == supabase.AuthChangeEvent.signedIn &&
            isSocialAuthProvider(state.session?.user.appMetadata['provider'])) {
          onSignedIn();
        }
      },
    );
  } on AssertionError {
    return null;
  }
}

Future<bool> signInWithSocialProvider(AuthProvider provider) {
  return supabase.Supabase.instance.client.auth.signInWithOAuth(
    supabaseOAuthProvider(provider),
    redirectTo: socialAuthRedirectForPlatform(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      currentUri: Uri.base,
    ),
    scopes: provider == AuthProvider.microsoft ? 'email' : null,
  );
}
