import 'dart:async';

import 'package:untitled/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/app_logo.dart';
import '../homescreen.dart';
import 'loginscreen.dart';
import 'widgets/brand_icon.dart';
import 'widgets/social_auth_button.dart';
import '../services/social_auth.dart';

class Signinscreen extends StatefulWidget {
  const Signinscreen({super.key});

  @override
  State<Signinscreen> createState() => _SigninscreenState();
}

class _SigninscreenState extends State<Signinscreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  StreamSubscription<AuthState>? _authSubscription;

  static const Color _primary = Color(0xFF4A90E2);

  @override
  void initState() {
    super.initState();
    _authSubscription = listenForSocialAuth(_openHome);
  }

  void _openHome() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (password != _confirmPasswordController.text) {
      _showSnackBar('Mật khẩu nhập lại không khớp!');
      return;
    }

    setState(() => _loading = true);

    try {
      final result = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': name,
        },
      );

      if (!mounted) return;

      if (result.user != null && result.session != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else if (result.user != null) {
        // Supabase đang bật xác nhận email: cần xác minh trước khi đăng nhập.
        _showSnackBar(
          'Đăng ký thành công! Vui lòng kiểm tra email để xác nhận tài khoản.',
          isError: false,
        );
      } else {
        _showSnackBar('Đăng ký thất bại. Vui lòng kiểm tra lại thông tin.');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Đăng ký thất bại. Vui lòng kiểm tra lại thông tin.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    AppNotice.show(
      context,
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? (isDark ? Colors.grey[800] : Colors.redAccent)
            : (isDark ? Colors.grey[800] : Colors.green),
      ),
    );
  }

  Future<void> _handleOAuth(AuthProvider provider) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final launched = await signInWithSocialProvider(provider);
      if (!launched && mounted) {
        _showSnackBar('Không mở được cửa sổ đăng ký ${provider.label}.');
      }
    } on AuthException {
      if (mounted) {
        _showSnackBar(
            'Không thể đăng ký bằng ${provider.label}. Hãy kiểm tra cấu hình OAuth.');
      }
    } on UnsupportedError {
      if (mounted) {
        _showSnackBar(
          'Đăng ký bằng ${provider.label} hiện chỉ hỗ trợ Android, Windows và web.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar(
            'Không thể bắt đầu đăng ký bằng ${provider.label}. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Style chung cho các ô nhập liệu.
  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppLogo(size: 96),
                      const SizedBox(height: 12),
                      Text(
                        'Tạo tài khoản',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Đăng ký để bắt đầu quản lý lịch học của bạn.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                              height: 1.4,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Name field
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          label: 'Họ và tên',
                          hint: 'Nguyễn Văn A',
                          icon: Icons.person_outline,
                          isDark: isDark,
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Vui lòng nhập họ và tên'
                                : null,
                      ),
                      const SizedBox(height: 16),

                      // Email field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          label: 'Email',
                          hint: 'example@email.com',
                          icon: Icons.email_outlined,
                          isDark: isDark,
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'Vui lòng nhập email';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(email)) {
                            return 'Email không hợp lệ';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          label: 'Mật khẩu',
                          hint: '••••••••',
                          icon: Icons.lock_outline,
                          isDark: isDark,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final password = value ?? '';
                          if (password.isEmpty) {
                            return 'Vui lòng nhập mật khẩu';
                          }
                          if (password.length < 8) {
                            return 'Mật khẩu tối thiểu 8 ký tự';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Confirm password field
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _signUp(),
                        decoration: _inputDecoration(
                          label: 'Nhập lại mật khẩu',
                          hint: '••••••••',
                          icon: Icons.lock_outline,
                          isDark: isDark,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            ),
                          ),
                        ),
                        validator: (value) => value != _passwordController.text
                            ? 'Mật khẩu nhập lại không khớp'
                            : null,
                      ),
                      const SizedBox(height: 28),

                      // Register button (with loading state)
                      SizedBox(
                        height: 52,
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _signUp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      _primary.withValues(alpha: 0.6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Tạo tài khoản',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 28),

                      // Divider: "Hoặc đăng ký bằng"
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color:
                                  isDark ? Colors.grey[700] : Colors.grey[300],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Hoặc đăng ký bằng',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[500]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color:
                                  isDark ? Colors.grey[700] : Colors.grey[300],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Social buttons: Google, Microsoft
                      Row(
                        children: [
                          SocialAuthButton(
                            provider: AuthProvider.google,
                            label: AuthProvider.google.label,
                            onPressed: _loading
                                ? null
                                : () => _handleOAuth(AuthProvider.google),
                          ),
                          const SizedBox(width: 12),
                          SocialAuthButton(
                            provider: AuthProvider.microsoft,
                            label: AuthProvider.microsoft.label,
                            onPressed: _loading
                                ? null
                                : () => _handleOAuth(AuthProvider.microsoft),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      // Link back to login
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Đã có tài khoản? ',
                            style: TextStyle(
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const Loginscreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Đăng nhập',
                              style: TextStyle(
                                color: _primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
