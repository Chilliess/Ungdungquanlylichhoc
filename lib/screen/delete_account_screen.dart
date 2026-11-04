import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/account_lifecycle.dart';
import '../auth/loginscreen.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, this.request, this.onRequested});
  final Future<void> Function()? onRequested;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body)?
      request;
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmation = TextEditingController();
  bool _agreed = false, _busy = false;
  String? _error;
  DateTime? _deleteAt;
  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _requestDeletion() async {
    if (_busy || !_agreed || _confirmation.text != 'delete') return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = {'action': 'request', 'confirmation': _confirmation.text};
      final data = widget.request != null
          ? await widget.request!(body)
          : Map<String, dynamic>.from((await Supabase.instance.client.functions
                  .invoke('delete-account', body: body))
              .data as Map);
      if (data['status'] != 'pending' || data['delete_at'] is! String) {
        throw const FormatException();
      }
      if (!mounted) return;
      setState(() => _deleteAt = DateTime.parse(data['delete_at']).toLocal());
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await FlutterLocalNotificationsPlugin().cancelAll();
        } catch (_) {/* No platform permission. */}
      }
      await (widget.onRequested ?? _leave)();
    } catch (_) {
      if (mounted) {
        setState(() => _error = _deleteAt == null
            ? 'Chưa gửi được yêu cầu xóa. Kiểm tra kết nối rồi thử lại.'
            : 'Đã tiếp nhận yêu cầu. Vui lòng bấm Đăng xuất để kết thúc phiên.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    await AccountLifecycle().signOut();
    accountStatusRefresh.value++;
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Loginscreen()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy && _deleteAt == null,
      child: Scaffold(
          appBar: AppBar(
              title: const Text('Xóa tài khoản'),
              automaticallyImplyLeading: _deleteAt == null),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(padding: const EdgeInsets.all(24), children: [
                    Icon(
                        _deleteAt == null
                            ? Icons.person_remove_outlined
                            : Icons.hourglass_top,
                        color: Colors.red,
                        size: 48),
                    const SizedBox(height: 20),
                    Text(
                        _deleteAt == null
                            ? 'Bạn muốn xóa tài khoản?'
                            : 'Đã yêu cầu xóa tài khoản',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    if (_deleteAt != null) ...[
                      Text(
                          'Tài khoản sẽ bị xóa từ ${DateFormat('HH:mm, dd/MM/yyyy').format(_deleteAt!)}. Trong 7 ngày chờ, bạn có thể đăng nhập và xác nhận khôi phục để hủy yêu cầu.'),
                      const SizedBox(height: 24),
                      FilledButton(
                          onPressed: _busy ? null : _leave,
                          child: const Text('Đăng xuất')),
                    ] else ...[
                      const Text(
                          'Tài khoản sẽ chuyển sang chờ xóa trong 7 ngày. Dữ liệu được giữ nguyên trong thời gian này. Sau thời hạn, tài khoản và dữ liệu trên máy chủ sẽ bị xóa vĩnh viễn.'),
                      const SizedBox(height: 12),
                      const Text(
                          'Nếu đổi ý, hãy đăng nhập trong 7 ngày và chọn “Khôi phục tài khoản” để tiếp tục sử dụng.'),
                      const SizedBox(height: 24),
                      if (!_agreed)
                        FilledButton(
                            onPressed: () => setState(() => _agreed = true),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white),
                            child: const Text('Đồng ý'))
                      else ...[
                        const Text(
                            'Nhập chính xác delete để xác nhận yêu cầu xóa.'),
                        const SizedBox(height: 12),
                        TextField(
                            key: const ValueKey('delete-confirmation'),
                            controller: _confirmation,
                            enabled: !_busy,
                            autocorrect: false,
                            enableSuggestions: false,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Nhập delete',
                                border: OutlineInputBorder())),
                        const SizedBox(height: 16),
                        FilledButton(
                            key: const ValueKey('request-deletion'),
                            onPressed: !_busy && _confirmation.text == 'delete'
                                ? _requestDeletion
                                : null,
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white),
                            child: const Text('Yêu cầu xóa sau 7 ngày')),
                      ],
                    ],
                    if (_busy)
                      const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator())),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])))));
}
