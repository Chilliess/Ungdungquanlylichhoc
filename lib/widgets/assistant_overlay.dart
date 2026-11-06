import '../services/calendar_conflicts.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../services/app_preferences.dart';
import '../services/chat_history.dart';
import '../services/assistant_error.dart';
import '../services/assistant_context.dart';
import '../services/assistant_consent.dart';
import '../services/image_paste.dart';
import '../services/study_data.dart';

final assistantPrompt = ValueNotifier<String?>(null);
final assistantDialog = ValueNotifier<bool>(false);

class AssistantChatPage extends StatelessWidget {
  const AssistantChatPage({super.key});

  @override
  Widget build(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AssistantScope>()?.panel() ??
      const SizedBox.shrink();
}

class _AssistantScope extends InheritedWidget {
  const _AssistantScope({required this.panel, required super.child});
  final Widget Function() panel;
  @override
  bool updateShouldNotify(_AssistantScope oldWidget) => true;
}

/// Lives above the navigator so minimising/navigating does not lose the chat.
/// History is stored locally per account; active state resets on account changes.
class AssistantOverlay extends StatefulWidget {
  const AssistantOverlay(
      {super.key,
      required this.child,
      this.initialUserId,
      this.accountChanges,
      this.sendMessage});
  final Widget child;
  final String? initialUserId;
  final Stream<String?>? accountChanges;
  final Future<String> Function(List<Map<String, String>> messages)?
      sendMessage;
  @override
  State<AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends State<AssistantOverlay> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Map<String, String>>[];
  StreamSubscription<String?>? _auth;
  String? _userId;
  String? _error;
  bool _open = false, _busy = false, _consent = false;
  bool _consentLoading = false;
  bool _useSchedule = true;
  bool _expanded = false;
  String _historyQuery = '';
  Uint8List? _image;
  String? _imageMime;
  StreamSubscription<Uint8List>? _paste;
  List<Map<String, dynamic>> _actions = [];

  void _attachImage(Uint8List bytes) {
    if (!mounted || _busy || !_consent || (!_open && !_expanded)) return;
    final mime = bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
        ? 'png'
        : bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216
            ? 'jpeg'
            : bytes.length >= 12 &&
                    ascii.decode(bytes.sublist(0, 4), allowInvalid: true) ==
                        'RIFF' &&
                    ascii.decode(bytes.sublist(8, 12), allowInvalid: true) ==
                        'WEBP'
                ? 'webp'
                : null;
    setState(() {
      if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024 || mime == null) {
        _error = 'Chọn ảnh PNG, JPEG hoặc WebP không quá 3 MB.';
      } else {
        _image = bytes;
        _imageMime = mime;
        _error = null;
      }
    });
  }

  Future<void> _pickImage() async {
    final generation = _generation;
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true);
    if (!mounted || generation != _generation || result == null) return;
    final bytes = result.files.single.bytes;
    if (bytes != null) _attachImage(bytes);
  }

  String _requestId() {
    final random = math.Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _applyAction(Map<String, dynamic> item) async {
    if (_busy || item['done'] == true) return;
    final owner = _userId, generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != owner) {
        throw StateError('Account changed');
      }
      final action = item['action'] as Map;
      if (action['operation'] == 'create') {
        if (!await confirmCalendarConflicts(
            context,
            client,
            {
              'start_date': action['date'],
              'end_date': action['date'],
              'recurrence': 'none',
              'start_time': action['start'],
              'end_time': action['end'],
            },
            isExam: action['kind'] == 'exam')) {
          return;
        }
        if (!mounted || generation != _generation) return;
      }
      await client.rpc('apply_assistant_calendar_action', params: {
        'p_request_id': item['request_id'],
        'p_action': item['action'],
      }).timeout(const Duration(seconds: 20));
      studyDataChanged();
      if (mounted && generation == _generation) {
        setState(() {
          item['done'] = true;
          _messages.add({
            'role': 'assistant',
            'content':
                '${(item['action'] as Map)['operation'] == 'delete' ? 'Đã xóa' : 'Đã tạo'}: ${(item['action'] as Map)['title']}.'
          });
        });
        await _saveThread();
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Chưa xác nhận được thao tác. Bạn có thể thử lại cùng mục này; yêu cầu đã lưu sẽ không tạo trùng.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Widget _actionCard(Map<String, dynamic> item) {
    final action = item['action'] as Map;
    final deleting = action['operation'] == 'delete';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${deleting ? 'Xóa' : 'Tạo'} ${action['kind'] == 'exam' ? 'lịch thi' : 'lịch học'} · ${action['title']}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                  '${action['date']} · ${action['start']} — ${action['end']}\nPhòng: ${action['room'] ?? ''}'),
              if (deleting && action['recurrence'] != 'none')
                const Text('Thao tác này xóa toàn bộ chuỗi lịch lặp.'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton(
                    onPressed: _busy || item['done'] == true
                        ? null
                        : () => _applyAction(item),
                    child:
                        Text(item['done'] == true ? 'Đã áp dụng' : 'Áp dụng')),
                if (item['done'] != true)
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _actions.remove(item)),
                      child: const Text('Bỏ qua')),
              ]),
            ])));
  }

  void _handleDialog() {
    if (!mounted || _userId == null) return;
    if (assistantDialog.value) {
      setState(() {
        _open = true;
        _expanded = true;
      });
    } else if (_expanded) {
      setState(() {
        _open = false;
        _expanded = false;
      });
    }
  }

  void _closePanel() {
    if (_expanded) {
      assistantDialog.value = false;
    } else {
      setState(() => _open = false);
    }
  }

  int _generation = 0;
  List<Map<String, dynamic>> _threads = [];
  String? _threadId, _deleteId;
  bool _history = false, _loadingHistory = false;
  Future<void> _writes = Future.value();

  void _openPrompt() {
    if (assistantPrompt.value == null || !mounted || _userId == null) return;
    if (!appPreferences.showAssistant) appPreferences.update(assistant: true);
    setState(() {
      _open = true;
      _history = false;
      _input.text = assistantPrompt.value!;
    });
  }

  Future<void> _loadHistory() async {
    final owner = _userId, generation = _generation;
    if (owner == null) return;
    setState(() => _loadingHistory = true);
    try {
      final saved = await ChatHistory.load(owner);
      if (mounted && generation == _generation) {
        setState(() => _threads = saved);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Không đọc được lịch sử trò chuyện.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  late final AssistantConsent _consentStore;

  Future<void> _loadConsent(String? userId, int generation) async {
    if (userId == null) return;
    try {
      final accepted = await _consentStore.load(userId);
      if (mounted && generation == _generation) {
        setState(() {
          _consent = accepted;
          _consentLoading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _consent = false;
          _consentLoading = false;
          _error =
              'Chưa tải được lựa chọn đồng ý của tài khoản. Vui lòng thử lại khi có mạng.';
        });
      }
    }
  }

  Future<void> _acceptConsent() async {
    final owner = _userId;
    final generation = _generation;
    if (owner == null || _consentLoading) return;
    setState(() => _consentLoading = true);
    try {
      await _consentStore.accept(owner);
      if (mounted && generation == _generation) {
        setState(() {
          _consent = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Chưa lưu được lựa chọn đồng ý vào tài khoản. Vui lòng thử lại.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _consentLoading = false);
      }
    }
  }

  int _historyRevision = 0;
  void _toggleHistory() {
    setState(() {
      _history = !_history;
      _historyQuery = '';
    });
    if (_history) _loadHistory();
  }

  Future<void> _persist() async {
    final revision = ++_historyRevision;
    final owner = _userId, generation = _generation;
    if (owner == null) return;
    final snapshot = _threads.map((t) => Map<String, dynamic>.from(t)).toList();
    _writes = _writes.catchError((_) {}).then((_) async {
      final merged = await ChatHistory.save(owner, snapshot);
      if (mounted &&
          generation == _generation &&
          revision == _historyRevision) {
        setState(() => _threads = merged);
      }
    });
    try {
      await _writes;
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'Chưa lưu được lịch sử. Nội dung vẫn còn trong phiên này.');
      }
    }
  }

  Future<void> _saveThread() async {
    _threadId ??= _requestId();
    final title = _messages.first['content']!;
    final thread = <String, dynamic>{
      'id': _threadId,
      'title': title.length > 65 ? '${title.substring(0, 65)}…' : title,
      'updated': DateTime.now().toIso8601String(),
      'use_schedule': _useSchedule,
      'messages': _messages.map((m) => Map<String, String>.from(m)).toList()
    };
    _threads.removeWhere((t) => t['id'] == _threadId);
    _threads.insert(0, thread);
    await _persist();
  }

  void _newChat() => setState(() {
        _actions = [];
        _image = null;
        _threadId = null;
        _messages.clear();
        _input.clear();
        _history = false;
        _historyQuery = '';
        _error = null;
      });

  Widget _historyList() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Lịch sử trò chuyện',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(_userId != null && ChatHistory.isSynced(_userId!)
            ? 'Đã đồng bộ với tài khoản.'
            : 'Đã lưu trên máy · Chờ đồng bộ khi có mạng.'),
        TextButton.icon(
            onPressed: _busy || _loadingHistory ? null : _loadHistory,
            icon: const Icon(Icons.sync),
            label: const Text('Đồng bộ lịch sử')),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: _busy || _loadingHistory ? null : _newChat,
                icon: const Icon(Icons.add_comment_outlined, size: 18),
                label: const Text('Trò chuyện mới'))),
        const SizedBox(height: 12),
        TextField(
            decoration: const InputDecoration(
                hintText: 'Tìm cuộc trò chuyện…',
                prefixIcon: Icon(Icons.search)),
            onChanged: (value) =>
                setState(() => _historyQuery = value.trim().toLowerCase())),
        const SizedBox(height: 16),
        if (_loadingHistory) const LinearProgressIndicator(),
        if (!_loadingHistory && _threads.isEmpty)
          const Text('Chưa có cuộc trò chuyện nào.'),
        if (_threads.isNotEmpty && !_threads.any(_matchesHistory))
          const Text('Không tìm thấy cuộc trò chuyện phù hợp.'),
        for (final t in _threads.where(_matchesHistory))
          Card(
              elevation: 0,
              child: Column(children: [
                ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(t['title'] as String,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text((t['updated'] as String).substring(0, 10)),
                    trailing: IconButton(
                        tooltip: 'Xóa cuộc trò chuyện',
                        color: Colors.red,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy
                            ? null
                            : () =>
                                setState(() => _deleteId = t['id'] as String)),
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _threadId = t['id'] as String;
                              _actions = [];
                              _image = null;
                              _messages
                                ..clear()
                                ..addAll((t['messages'] as List).map(
                                    (m) => Map<String, String>.from(m as Map)));
                              _history = false;
                              _useSchedule = t['use_schedule'] != false;
                              // Opening history does not grant provider consent.
                              _error = null;
                              _input.clear();
                              _toBottom();
                            })),
                if (_deleteId == t['id'])
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(spacing: 8, children: [
                        const Text('Xóa vĩnh viễn cuộc trò chuyện này?'),
                        TextButton(
                            onPressed: () => setState(() => _deleteId = null),
                            child: const Text('Hủy')),
                        FilledButton(
                            onPressed: () async {
                              final id = _deleteId;
                              setState(() {
                                _threads.removeWhere((t) => t['id'] == id);
                                _deleteId = null;
                                if (_threadId == id) {
                                  _messages.clear();
                                  _threadId = null;
                                }
                              });
                              await _persist();
                            },
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white),
                            child: const Text('Xóa')),
                      ])),
              ])),
      ]);

  bool _matchesHistory(Map<String, dynamic> thread) =>
      _historyQuery.isEmpty ||
      (thread['title'] as String).toLowerCase().contains(_historyQuery) ||
      (thread['messages'] as List).any((message) =>
          (message['content'] as String).toLowerCase().contains(_historyQuery));

  Widget _suggestion(
      IconData icon, String title, String subtitle, String prompt) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _input.text = prompt,
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(12)),
                          child: Icon(icon, size: 21, color: colors.primary)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Text(subtitle,
                                style: Theme.of(context).textTheme.bodySmall),
                          ])),
                      const Icon(Icons.north_west, size: 16),
                    ])))));
  }

  @override
  void initState() {
    super.initState();
    _paste = pastedImages().listen(_attachImage);
    _consentStore = widget.accountChanges == null
        ? AssistantConsent.supabase(Supabase.instance.client)
        : AssistantConsent();
    _userId = widget.accountChanges == null
        ? Supabase.instance.client.auth.currentUser?.id
        : widget.initialUserId;
    _consentLoading = _userId != null;
    final changes = widget.accountChanges ??
        Supabase.instance.client.auth.onAuthStateChange
            .map((event) => event.session?.user.id);
    _auth = changes.listen((id) {
      if (id != _userId && mounted) {
        setState(() {
          _userId = id;
          _generation++;
          _messages.clear();
          _actions = [];
          _image = null;
          _input.clear();
          _open = _busy = _consent = _expanded = false;
          _consentLoading = id != null;
          _useSchedule = true;
          assistantDialog.value = false;
          _error = null;
          _threads = [];
          _threadId = null;
          _history = false;
          _historyQuery = '';
          _deleteId = null;
        });
        _loadConsent(id, _generation);
        _loadHistory();
      }
    });
    assistantPrompt.addListener(_openPrompt);
    assistantDialog.addListener(_handleDialog);
    _loadConsent(_userId, _generation);
    _loadHistory();
  }

  @override
  void dispose() {
    _paste?.cancel();
    assistantPrompt.removeListener(_openPrompt);
    assistantDialog.removeListener(_handleDialog);
    _auth?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });

  Future<void> _send() async {
    final text = _input.text.trim().isEmpty && _image != null
        ? 'Đọc ảnh và chuẩn bị các lịch để tôi kiểm tra trước khi cập nhật. Hỏi lại nếu thiếu ngày, giờ hoặc phòng.'
        : _input.text.trim();
    if (text.isEmpty || _busy || !_consent || _loadingHistory) return;
    final generation = _generation;
    setState(() {
      _actions = [];
      _messages.add({'role': 'user', 'content': text});
      _input.clear();
      _error = null;
      _busy = true;
    });
    _toBottom();
    try {
      final history = assistantContext(_messages);
      final reply = await (widget.sendMessage ?? _request)(history)
          .timeout(const Duration(seconds: 45));
      if (reply.trim().isEmpty) throw const FormatException();
      if (mounted && generation == _generation) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': reply});
          _image = null;
        });
        await _saveThread();
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _messages.removeLast();
          _input.text = text;
          _error = assistantErrorMessage(error);
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        _toBottom();
      }
    }
  }

  Future<String> _request(List<Map<String, String>> history) async {
    final generation = _generation;
    final response = await Supabase.instance.client.functions
        .invoke('study-assistant', body: {
      'messages': history,
      'earlier_user_messages': assistantEarlierMessages(_messages, history),
      'use_schedule': _useSchedule,
      'allow_actions': _useSchedule,
      if (_image != null)
        'image': 'data:image/$_imageMime;base64,${base64Encode(_image!)}',
    });
    final reply = response.data is Map ? response.data['reply'] : null;
    if (reply is! String) throw const FormatException();
    if (mounted &&
        generation == _generation &&
        response.data['actions'] is List) {
      _actions = (response.data['actions'] as List)
          .map((a) => <String, dynamic>{
                'action': Map<String, dynamic>.from(a as Map),
                'request_id': _requestId(),
                'done': false,
              })
          .toList();
    }
    return reply;
  }

  Widget _miniHeader() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 12, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.smart_toy_outlined, size: 18, color: colors.onSurface),
          const SizedBox(height: 4),
          const Text('Trợ lý học tập',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ])),
        IconButton(
            tooltip: 'Lịch sử trò chuyện',
            onPressed: _busy ? null : _toggleHistory,
            icon: Icon(
                _history ? Icons.chat_bubble_outline : Icons.history_rounded,
                size: 20)),
        IconButton(
            tooltip: 'Thu gọn',
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              _closePanel();
            },
            icon: const Icon(Icons.remove_rounded, size: 20)),
      ]),
    );
  }

  Widget _miniSuggestion(IconData icon, String title, String prompt) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
            color: colors.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
                side: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .6)),
                borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: () => _input.text = prompt,
                child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, size: 18, color: colors.onSurface),
                              const SizedBox(height: 4),
                              Text(title,
                                  style: TextStyle(
                                      fontSize: 15, color: colors.onSurface)),
                            ]))))));
  }

  Widget _miniComposer() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_image != null)
            Row(children: [
              Image.memory(_image!, width: 36, height: 30, fit: BoxFit.cover),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Ảnh lịch đã đính kèm',
                      style: TextStyle(fontSize: 12))),
              IconButton(
                  tooltip: 'Bỏ ảnh',
                  onPressed: _busy ? null : () => setState(() => _image = null),
                  icon: const Icon(Icons.close, size: 18)),
            ]),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
                child: TextField(
                    controller: _input,
                    enabled: !_busy,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                        hintText: 'Bạn cần hỗ trợ gì?',
                        counterText: '',
                        filled: true,
                        fillColor:
                            Theme.of(context).brightness == Brightness.light
                                ? const Color(0xFFF5F6FA)
                                : colors.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 17),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(
                                color: colors.outlineVariant
                                    .withValues(alpha: .6))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(
                                color: colors.outlineVariant
                                    .withValues(alpha: .6))),
                        suffixIcon: PopupMenuButton<String>(
                            tooltip: 'Ảnh và lịch cá nhân',
                            enabled: !_busy,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            onSelected: (value) {
                              if (value == 'image') {
                                _pickImage();
                              } else {
                                setState(() => _useSchedule = !_useSchedule);
                              }
                            },
                            itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'image',
                                      child: Text('Chọn ảnh lịch')),
                                  CheckedPopupMenuItem(
                                      value: 'calendar',
                                      checked: _useSchedule,
                                      child: const Text('Lịch cá nhân')),
                                ])),
                    onSubmitted: (_) => _send())),
            const SizedBox(width: 12),
            ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (_, value, child) => IconButton.filled(
                    tooltip: 'Gửi',
                    onPressed: !_busy &&
                            (value.text.trim().isNotEmpty || _image != null)
                        ? _send
                        : null,
                    style: IconButton.styleFrom(
                        minimumSize: const Size(52, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 22))),
          ]),
        ]));
  }

  Widget _panel() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: _expanded ? const ValueKey('assistant-dialog') : null,
      elevation: _expanded ? 0 : 12,
      color: _expanded
          ? Theme.of(context).scaffoldBackgroundColor
          : colors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(_expanded ? 0 : 24),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        if (!_expanded)
          _miniHeader()
        else
          Padding(
            padding: EdgeInsets.fromLTRB(16, _expanded ? 20 : 8, 16, 12),
            child: SizedBox(
                width: double.infinity,
                child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tooltip(
                          message: 'Lịch sử trò chuyện',
                          child: TextButton.icon(
                              onPressed: _busy ? null : _toggleHistory,
                              icon: Icon(
                                  _history
                                      ? Icons.chat_bubble_outline
                                      : Icons.history,
                                  size: 19),
                              label: Text(_history ? 'Trò chuyện' : 'Lịch sử'),
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  backgroundColor: colors.primaryContainer
                                      .withValues(alpha: .5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14))))),
                      Tooltip(
                          message: 'Trò chuyện mới',
                          child: TextButton.icon(
                              onPressed:
                                  _busy || _loadingHistory ? null : _newChat,
                              icon: const Icon(Icons.add, size: 17),
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  backgroundColor: colors.primaryContainer
                                      .withValues(alpha: .5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14))),
                              label: const Text('Chat mới'))),
                      if (!_expanded)
                        IconButton(
                            tooltip: 'Thu gọn',
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _closePanel();
                            },
                            icon: const Icon(Icons.close_rounded, size: 20)),
                    ])),
          ),
        Expanded(
            child: _history
                ? _historyList()
                : ListView(
                    controller: _scroll,
                    padding: _expanded
                        ? const EdgeInsets.all(16)
                        : const EdgeInsets.fromLTRB(22, 12, 22, 0),
                    children: [
                        if (_consent && _expanded) ...[
                          const Padding(
                              padding: EdgeInsets.only(top: 8, bottom: 12),
                              child: Text('Cùng bạn\nhiểu sâu hơn.',
                                  style: TextStyle(
                                      fontSize: 32,
                                      height: 1.18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.9))),
                          Text('Trợ lý học tập AI',
                              style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 13)),
                          const SizedBox(height: 26),
                        ],
                        if (_consentLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (!_consent) ...[
                          const Text('Cùng bạn học tập hiệu quả hơn',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          const Text(
                              'AI đọc lịch và đề xuất tạo/xóa, bạn bấm Áp dụng để lưu. Dán/chọn ảnh để nhập lịch. Nội dung liên quan gửi đến Groq. Lịch sử chat đồng bộ riêng theo tài khoản Supabase; ảnh không lưu.'),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: _acceptConsent,
                              child: const Text('Đồng ý và bắt đầu')),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(_error!,
                                style: TextStyle(color: colors.error)),
                          ],
                        ] else if (_messages.isEmpty && !_expanded) ...[
                          Text('Cùng bạn sắp xếp một tuần nhẹ nhàng hơn.',
                              style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 13)),
                          const SizedBox(height: 16),
                          _miniSuggestion(
                              Icons.event_available_outlined,
                              'Lên kế hoạch ôn thi',
                              'Giúp tôi lên kế hoạch ôn thi. Hãy hỏi tôi môn học, ngày thi và thời gian rảnh trước.'),
                          _miniSuggestion(
                              Icons.format_list_bulleted_rounded,
                              'Chia nhỏ bài tập khó',
                              'Giúp tôi chia nhỏ một bài tập. Hãy hỏi tôi đề bài và deadline.'),
                        ] else if (_messages.isEmpty) ...[
                          const Text('Hôm nay mình giúp gì cho bạn?',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('Chọn một ý tưởng để bắt đầu.'),
                          const SizedBox(height: 18),
                          _suggestion(
                              Icons.school_outlined,
                              'Ôn thi có kế hoạch',
                              'Chia nội dung ôn thành từng bước',
                              'Giúp tôi lên kế hoạch ôn thi. Hãy hỏi tôi môn học, ngày thi và thời gian rảnh trước.'),
                          _suggestion(
                              Icons.checklist_rounded,
                              'Chia nhỏ bài tập',
                              'Biến bài khó thành việc dễ bắt đầu',
                              'Giúp tôi chia nhỏ một bài tập. Hãy hỏi tôi đề bài và deadline.'),
                          _suggestion(
                              Icons.psychology_outlined,
                              'Hiểu bài sâu hơn',
                              'Giải thích kèm ví dụ dễ hiểu',
                              'Giải thích một kiến thức khó bằng ví dụ. Trước tiên hỏi tôi chủ đề.'),
                        ],
                        for (final message in _messages)
                          Align(
                              alignment: message['role'] == 'user'
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                  margin: EdgeInsets.only(
                                      bottom: 20,
                                      left: message['role'] == 'user' ? 36 : 0),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: message['role'] == 'user'
                                          ? colors.primaryContainer
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (message['role'] == 'assistant') ...[
                                          Row(children: [
                                            Icon(Icons.auto_awesome,
                                                size: 20,
                                                color: colors.primary),
                                            const SizedBox(width: 10),
                                            const Text('Trợ lý AI',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ]),
                                          const SizedBox(height: 12),
                                        ],
                                        SelectableText(message['content']!,
                                            style: const TextStyle(
                                                fontSize: 15, height: 1.6)),
                                        if (message['role'] == 'assistant')
                                          Align(
                                              alignment: Alignment.centerRight,
                                              child: IconButton(
                                                  tooltip:
                                                      'Sao chép câu trả lời',
                                                  icon: const Icon(
                                                      Icons.copy_outlined,
                                                      size: 18),
                                                  onPressed: () async {
                                                    await Clipboard.setData(
                                                        ClipboardData(
                                                            text: message[
                                                                'content']!));
                                                    if (mounted) {
                                                      ScaffoldMessenger.maybeOf(
                                                              context)
                                                          ?.showSnackBar(
                                                              const SnackBar(
                                                                  content: Text(
                                                                      'Đã sao chép câu trả lời.')));
                                                    }
                                                  })),
                                      ]))),
                        for (final action in _actions) _actionCard(action),
                        if (_busy)
                          const Row(children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('Đang trả lời…')
                          ]),
                        if (_error != null)
                          Text(_error!, style: TextStyle(color: colors.error)),
                      ])),
        if (!_history && _consent) ...[
          if (!_expanded)
            _miniComposer()
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: .6)),
                    borderRadius: BorderRadius.circular(22)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_image != null)
                    Row(children: [
                      ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_image!,
                              width: 44, height: 36, fit: BoxFit.cover)),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('Ảnh lịch đã đính kèm',
                              style: TextStyle(fontSize: 12))),
                      IconButton(
                          tooltip: 'Bỏ ảnh',
                          onPressed: _busy
                              ? null
                              : () => setState(() => _image = null),
                          icon: const Icon(Icons.close, size: 18)),
                    ]),
                  TextField(
                      controller: _input,
                      enabled: !_busy,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          hintText: 'Nhắn tin hoặc gửi ảnh lịch…',
                          counterText: '',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 10)),
                      onSubmitted: (_) => _send()),
                  const SizedBox(height: 6),
                  Row(children: [
                    IconButton.filledTonal(
                        tooltip: 'Chọn ảnh lịch (hoặc Ctrl+V trên web)',
                        onPressed: _busy ? null : _pickImage,
                        style: IconButton.styleFrom(
                            minimumSize: const Size(42, 42),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13))),
                        icon: const Icon(Icons.add_photo_alternate_outlined,
                            size: 21)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Tooltip(
                              message: _useSchedule
                                  ? 'AI có thể đọc lịch cá nhân và chuẩn bị thay đổi theo yêu cầu. Bấm để tắt.'
                                  : 'Lịch cá nhân đang tắt. Bấm để cho AI truy cập lịch.',
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(
                                        () => _useSchedule = !_useSchedule),
                                style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                    foregroundColor: _useSchedule
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                    backgroundColor: _useSchedule
                                        ? colors.primaryContainer
                                            .withValues(alpha: .45)
                                        : Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(13))),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          _useSchedule
                                              ? Icons.event_available_rounded
                                              : Icons.event_busy_outlined,
                                          size: 17),
                                      const SizedBox(width: 6),
                                      const Flexible(
                                          child: Text('Lịch cá nhân',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w500))),
                                    ]),
                              ),
                            ))),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _input,
                      builder: (context, value, _) => IconButton.filled(
                          tooltip: 'Gửi',
                          onPressed: !_busy &&
                                  (value.text.trim().isNotEmpty ||
                                      _image != null)
                              ? _send
                              : null,
                          style: IconButton.styleFrom(
                              minimumSize: const Size(42, 42),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13))),
                          icon:
                              const Icon(Icons.arrow_upward_rounded, size: 22)),
                    ),
                  ]),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Overlay.wrap(
          child: ListenableBuilder(
        listenable: appPreferences,
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final media = MediaQuery.of(context);
          final keyboard = media.viewInsets.bottom;
          final bottom =
              keyboard > 0 ? keyboard + 8 : media.padding.bottom + 96.0;
          final height = math.max(
              0.0,
              math.min(box.maxWidth < 500 ? 400.0 : 440.0,
                  box.maxHeight - bottom - 72 - media.padding.top - 12));
          return Stack(children: [
            _AssistantScope(panel: _panel, child: widget.child),
            if (_userId != null &&
                !_expanded &&
                appPreferences.showAssistant &&
                height > 120) ...[
              Positioned(
                  right: 12,
                  bottom: bottom + 72,
                  child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      reverseDuration: Duration.zero,
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                              scale: Tween<double>(begin: .94, end: 1)
                                  .animate(animation),
                              alignment: Alignment.bottomRight,
                              child: child)),
                      child: _open
                          ? SizedBox(
                              key: const ValueKey('assistant-panel'),
                              width: math.min(440, box.maxWidth - 24),
                              height: height,
                              child: _panel())
                          : const SizedBox.shrink())),
              Positioned(
                  right: 12,
                  bottom: bottom,
                  child: FloatingActionButton(
                      key: const ValueKey('assistant-launcher'),
                      heroTag: 'global-assistant',
                      tooltip: _open ? 'Thu gọn trợ lý AI' : 'Mở trợ lý AI',
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      onPressed: () => setState(() => _open = !_open),
                      child: const Icon(Icons.smart_toy_outlined))),
            ],
          ]);
        }),
      ));
}
