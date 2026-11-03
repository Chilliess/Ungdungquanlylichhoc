import 'package:untitled/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'confirm_action.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  bool _isLoading = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _loadUserProfile();
  }

  // Tải thông tin người dùng hiện tại từ Auth và bảng Profiles
  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Lấy email từ auth
        _emailController.text = user.email ?? '';

        // Lấy username từ bảng profiles hiện có
        final data = await supabase
            .from('profiles')
            .select('username')
            .eq('id', user.id)
            .maybeSingle();

        if (!mounted) {
          return;
        }
        if (data != null && data['username'] != null) {
          _usernameController.text = data['username'];
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          SnackBar(
              content: Text('Lỗi tải thông tin: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Cập nhật thông tin tài khoản (Tên, Email, Mật khẩu)
  Future<void> _updateAccount() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      if (!await confirmAction(context,
              message: _passwordController.text.isEmpty
                  ? 'Lưu thay đổi tên người dùng?'
                  : 'Lưu tên người dùng và mật khẩu mới?') ||
          !mounted) {
        return;
      }
      final newUsername = _usernameController.text.trim();
      final newPassword = _passwordController.text;

      // 1. Cập nhật bảng profiles (username)
      await supabase.from('profiles').upsert({
        'id': user.id,
        'username': newUsername,
      });

      // 2. Cập nhật Mật khẩu trong Supabase Auth (nếu người dùng có nhập mật khẩu mới)
      if (newPassword.isNotEmpty) {
        final response = await supabase.auth.updateUser(
          UserAttributes(
            password: newPassword,
          ),
        );

        if (response.user == null) {
          throw 'Không thể cập nhật mật khẩu.';
        }
      }

      if (mounted) {
        AppNotice.show(
          context,
          const SnackBar(
            content: Text('Cập nhật tài khoản thành công!'),
            backgroundColor: Colors.green,
          ),
        );
        // Xóa trắng ô mật khẩu sau khi cập nhật thành công
        _passwordController.clear();
      }
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          SnackBar(
            content: Text('Cập nhật thất bại: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    letterSpacing: .7,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: Padding(padding: const EdgeInsets.all(16), child: child)),
      ]));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      appBar: AppBar(
          title: const Text('Quản lý tài khoản'),
          backgroundColor: colors.surfaceContainerLowest),
      body: _isLoading && _usernameController.text.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                        key: _formKey,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                    radius: 28,
                                    backgroundColor: colors.primaryContainer,
                                    child: Icon(Icons.person_outline,
                                        size: 30,
                                        color: colors.onPrimaryContainer)),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text('Tài khoản của bạn',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 4),
                                      Text(
                                          _emailController.text.isEmpty
                                              ? 'Chưa đăng nhập'
                                              : _emailController.text,
                                          style: TextStyle(
                                              color: colors.onSurfaceVariant)),
                                    ])),
                              ]),
                              const SizedBox(height: 28),
                              _section(
                                  'THÔNG TIN CÁ NHÂN',
                                  Column(children: [
                                    TextFormField(
                                        key: const ValueKey('account-name'),
                                        controller: _usernameController,
                                        enabled: !_isLoading,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        decoration: const InputDecoration(
                                            labelText: 'Tên người dùng',
                                            prefixIcon:
                                                Icon(Icons.person_outline),
                                            border: InputBorder.none),
                                        validator: (value) => value == null ||
                                                value.trim().isEmpty
                                            ? 'Vui lòng nhập tên người dùng'
                                            : null),
                                    const Divider(height: 24),
                                    TextFormField(
                                        controller: _emailController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Email đăng nhập',
                                            prefixIcon:
                                                Icon(Icons.mail_outline),
                                            suffixIcon: Icon(Icons.lock_outline,
                                                size: 18),
                                            border: InputBorder.none)),
                                  ])),
                              _section(
                                  'BẢO MẬT',
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding:
                                        const EdgeInsets.only(top: 12),
                                    leading: Icon(Icons.lock_outline,
                                        color: colors.primary),
                                    title: const Text('Đổi mật khẩu'),
                                    children: [
                                      TextFormField(
                                          key: const ValueKey(
                                              'account-password'),
                                          controller: _passwordController,
                                          enabled: !_isLoading,
                                          obscureText: !_showPassword,
                                          enableSuggestions: false,
                                          autocorrect: false,
                                          decoration: InputDecoration(
                                              labelText: 'Mật khẩu mới',
                                              helperText:
                                                  'Để trống nếu giữ nguyên mật khẩu',
                                              helperMaxLines: 2,
                                              border:
                                                  const OutlineInputBorder(),
                                              suffixIcon: IconButton(
                                                  tooltip: _showPassword
                                                      ? 'Ẩn mật khẩu'
                                                      : 'Hiện mật khẩu',
                                                  onPressed: () => setState(
                                                      () => _showPassword =
                                                          !_showPassword),
                                                  icon: Icon(_showPassword
                                                      ? Icons
                                                          .visibility_off_outlined
                                                      : Icons
                                                          .visibility_outlined))),
                                          validator: (value) => value != null &&
                                                  value.isNotEmpty &&
                                                  value.length < 6
                                              ? 'Mật khẩu mới phải có ít nhất 6 ký tự'
                                              : null)
                                    ],
                                  )),
                              FilledButton(
                                  onPressed: _isLoading ? null : _updateAccount,
                                  style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14))),
                                  child: Text(_isLoading
                                      ? 'Đang lưu…'
                                      : 'Lưu thay đổi')),
                            ])),
                  ))),
    );
  }
}
