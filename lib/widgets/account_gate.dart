import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/account_lifecycle.dart';

class AccountGate extends StatefulWidget {
  const AccountGate(
      {super.key,
      required this.child,
      this.lifecycle,
      this.accountChanges,
      this.initialUserId});
  final Widget child;
  final AccountLifecycle? lifecycle;
  final Stream<String?>? accountChanges;
  final String? initialUserId;
  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> with WidgetsBindingObserver {
  late final AccountLifecycle _service = widget.lifecycle ?? AccountLifecycle();
  StreamSubscription<String?>? _auth;
  Timer? _timer;
  String? _userId, _error;
  String _status = 'checking';
  DateTime? _deadline;
  bool _busy = false, _checking = false;
  int _version = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userId = widget.accountChanges == null
        ? Supabase.instance.client.auth.currentUser?.id
        : widget.initialUserId;
    _auth = (widget.accountChanges ??
            Supabase.instance.client.auth.onAuthStateChange
                .map((e) => e.session?.user.id))
        .listen((id) {
      if (!mounted) return;
      if (id != _userId) {
        _version++;
        _checking = false;
        setState(() {
          _userId = id;
          _status = 'checking';
          _error = null;
        });
      }
      _check();
    });
    accountStatusRefresh.addListener(_check);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _auth?.cancel();
    _timer?.cancel();
    accountStatusRefresh.removeListener(_check);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    if (_userId == null || _checking || _busy) return;
    _checking = true;
    final version = _version;
    try {
      final data = await _service.status();
      if (!mounted || version != _version) return;
      final status = data['status'];
      if (!['active', 'pending', 'expired', 'deleted'].contains(status)) {
        throw const FormatException();
      }
      setState(() {
        _status = status;
        _deadline =
            DateTime.tryParse(data['delete_at']?.toString() ?? '')?.toLocal();
        _error = null;
      });
    } catch (_) {
      if (mounted && version == _version) {
        setState(() {
          _status = 'checking';
          _error =
              'Chưa kiểm tra được trạng thái tài khoản. Vui lòng kiểm tra kết nối và thử lại.';
        });
      }
    } finally {
      if (version == _version) _checking = false;
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final version = _version;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.restore();
      if (result['status'] != 'active') throw const FormatException();
      if (mounted && version == _version) setState(() => _status = 'active');
    } catch (_) {
      if (mounted && version == _version) {
        setState(() => _error =
            'Chưa khôi phục được. Yêu cầu có thể đã hết hạn; hãy kiểm tra lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null || _status == 'active') return widget.child;
    final pending = _status == 'pending';
    return Material(
        child: Scaffold(
            body: SafeArea(
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      pending
                                          ? Icons.restore
                                          : Icons.lock_outline,
                                      size: 52),
                                  const SizedBox(height: 20),
                                  Text(
                                      pending
                                          ? 'Khôi phục tài khoản?'
                                          : _status == 'checking'
                                              ? 'Kiểm tra tài khoản'
                                              : 'Đã hết thời hạn khôi phục',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  if (pending)
                                    Text(
                                        'Tài khoản đang chờ xóa${_deadline == null ? '' : ' từ ${DateFormat('HH:mm dd/MM/yyyy').format(_deadline!)}'}. Bạn có muốn hủy yêu cầu xóa và khôi phục tài khoản để tiếp tục đăng nhập không?',
                                        textAlign: TextAlign.center),
                                  if (_status == 'expired' ||
                                      _status == 'deleted')
                                    const Text(
                                        'Tài khoản không còn có thể khôi phục. Hệ thống sẽ hoàn tất việc xóa dữ liệu trên máy chủ.'),
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Text(_error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                  const SizedBox(height: 24),
                                  if (_busy ||
                                      (_status == 'checking' && _error == null))
                                    const CircularProgressIndicator(),
                                  if (pending)
                                    FilledButton(
                                        onPressed: _busy ? null : _restore,
                                        child:
                                            const Text('Khôi phục tài khoản')),
                                  if (_error != null)
                                    TextButton(
                                        onPressed: _busy ? null : _check,
                                        child: const Text('Thử lại')),
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _service.signOut(),
                                      child: Text(pending
                                          ? 'Không khôi phục · Đăng xuất'
                                          : 'Đăng xuất')),
                                ])))))));
  }
}
