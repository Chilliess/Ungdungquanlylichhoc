import 'dart:async';
import 'package:untitled/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.initialEmail = '',
    this.sendRecoveryCode,
    this.currentTime,
  });

  final String initialEmail;
  final Future<void> Function(String email)? sendRecoveryCode;
  final DateTime Function()? currentTime;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  GoTrueClient get _auth => Supabase.instance.client.auth;
  DateTime _now() => widget.currentTime?.call() ?? DateTime.now();

  // 0: email, 1: OTP, 2: mật khẩu mới.
  int _step = 0;
  bool _loading = false;
  bool _recoverySession = false;
  bool _passwordChanged = false;
  DateTime? _lastSent;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  void _startResendCountdown() {
    _resendTimer?.cancel();
    _lastSent = _now();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = 60 - _now().difference(_lastSent!).inSeconds;
      setState(() => _resendSeconds = remaining.clamp(0, 60));
      if (_resendSeconds == 0) timer.cancel();
    });
  }

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    AppNotice.show(
      context,
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _sendOtp() async {
    if (_loading) return;
    final email = _emailController.text.trim();

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showMessage('Vui lòng nhập email hợp lệ.');
      return;
    }

    final lastSent = _lastSent;
    if (lastSent != null && _now().difference(lastSent).inSeconds < 60) {
      _showMessage('Vui lòng thử lại sau $_resendSeconds giây');
      return;
    }

    setState(() => _loading = true);

    try {
      if (widget.sendRecoveryCode != null) {
        await widget.sendRecoveryCode!(email);
      } else {
        await _auth.resetPasswordForEmail(email);
      }

      if (!mounted) return;

      _startResendCountdown();
      _otpController.clear();

      setState(() => _step = 1);

      _showMessage(
        'Nếu email có tài khoản phù hợp, mã khôi phục sẽ được gửi. '
        'Hãy kiểm tra cả thư rác.',
      );
    } on AuthException catch (e) {
      if (mounted &&
          (e.statusCode == '429' ||
              e.code == 'over_email_send_rate_limit' ||
              e.code == 'over_request_rate_limit')) {
        _startResendCountdown();
      }
      _showMessage('Chưa gửi được mã: ${e.message}');
    } catch (_) {
      _showMessage('Không thể gửi mã. Kiểm tra kết nối và thử lại.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.isEmpty) {
      _showMessage('Vui lòng nhập mã trong email.');
      return;
    }

    setState(() => _loading = true);

    try {
      final result = await _auth.verifyOTP(
        email: _emailController.text.trim(),
        token: otp,
        type: OtpType.recovery,
      );

      if (result.session == null) {
        _showMessage('Chưa xác thực được mã. Vui lòng thử lại.');
        return;
      }

      _recoverySession = true;

      if (!mounted) return;
      setState(() => _step = 2);
    } on AuthException catch (e) {
      _showMessage('Không xác thực được mã: ${e.message}');
    } catch (_) {
      _showMessage('Không thể xác thực. Kiểm tra kết nối và thử lại.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePassword() async {
    if (!_passwordChanged) {
      final password = _passwordController.text;

      // Điều chỉnh nếu dự án Supabase yêu cầu mật khẩu mạnh hơn.
      if (password.length < 8) {
        _showMessage('Mật khẩu cần ít nhất 8 ký tự.');
        return;
      }

      if (password != _confirmController.text) {
        _showMessage('Hai mật khẩu không khớp.');
        return;
      }
    }

    setState(() => _loading = true);

    try {
      if (!_passwordChanged) {
        await _auth.updateUser(
          UserAttributes(password: _passwordController.text),
        );
        _passwordChanged = true;
      }

      await _auth.signOut(scope: SignOutScope.local);
      _recoverySession = false;

      if (!mounted) return;
      Navigator.pop(context, true);
    } on AuthException catch (e) {
      _showMessage(
        _passwordChanged
            ? 'Mật khẩu đã đổi. Bấm Hoàn tất để thử kết thúc phiên.'
            : 'Chưa đổi được mật khẩu: ${e.message}',
      );
    } catch (_) {
      _showMessage(
        _passwordChanged
            ? 'Mật khẩu đã đổi. Kiểm tra kết nối rồi bấm Hoàn tất.'
            : 'Không thể đổi mật khẩu. Kiểm tra kết nối và thử lại.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Quên mật khẩu',
      'Nhập mã xác thực',
      'Đặt mật khẩu mới',
    ];

    return PopScope(
      canPop: !_loading && !_recoverySession,
      child: Scaffold(
        appBar: AppBar(
          title: Text(titles[_step]),
          automaticallyImplyLeading: !_recoverySession,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step == 0) ...[
                    const Text(
                      'Nhập email đã đăng ký tài khoản để nhận mã OTP.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      enabled: !_loading,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email đã đăng ký',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_step == 1) ...[
                    Text(
                      'Kiểm tra mã gửi tới '
                      '${_emailController.text.trim()}, kể cả thư rác.',
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _otpController,
                      enabled: !_loading,
                      keyboardType: TextInputType.number,
                      autofillHints: const [
                        AutofillHints.oneTimeCode,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Mã OTP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          _loading || _resendSeconds > 0 ? null : _sendOtp,
                      child: Text(_resendSeconds > 0
                          ? 'Vui lòng thử lại sau $_resendSeconds giây'
                          : 'Gửi lại mã'),
                    ),
                  ],
                  if (_step == 2 && !_passwordChanged) ...[
                    TextField(
                      controller: _passwordController,
                      enabled: !_loading,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu mới',
                        helperText: 'Ít nhất 8 ký tự',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _confirmController,
                      enabled: !_loading,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu mới',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _loading || (_step == 0 && _resendSeconds > 0)
                        ? null
                        : () {
                            if (_step == 0) {
                              _sendOtp();
                            } else if (_step == 1) {
                              _verifyOtp();
                            } else {
                              _savePassword();
                            }
                          },
                    child: Text(
                      _loading
                          ? 'Đang xử lý...'
                          : _step == 0 && _resendSeconds > 0
                              ? 'Vui lòng thử lại sau $_resendSeconds giây'
                              : _passwordChanged
                                  ? 'Hoàn tất'
                                  : [
                                      'Gửi mã OTP',
                                      'Xác thực mã',
                                      'Lưu mật khẩu mới',
                                    ][_step],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
