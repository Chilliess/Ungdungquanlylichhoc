import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_preferences.dart';
import '../services/chat_history.dart';
import '../services/assistant_error.dart';
import '../services/assistant_context.dart';

final assistantPrompt = ValueNotifier<String?>(null);
final assistantDialog = ValueNotifier<bool>(false);

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
  bool _webSearch = false;
  bool _expanded = false;
  String _historyQuery = '';

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
    _loadingHistory = true;
    try {
      final saved = await ChatHistory.load(owner);
      if (mounted && generation == _generation) {
        setState(() => _threads = saved);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Không đọc được lịch sử trên thiết bị.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  Future<void> _persist() async {
    final owner = _userId, generation = _generation;
    if (owner == null) return;
    final snapshot = _threads.map((t) => Map<String, dynamic>.from(t)).toList();
    _writes = _writes
        .catchError((_) {})
        .then((_) => ChatHistory.save(owner, snapshot));
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
    _threadId ??= DateTime.now().microsecondsSinceEpoch.toString();
    final title = _messages.first['content']!;
    final thread = <String, dynamic>{
      'id': _threadId,
      'title': title.length > 65 ? '${title.substring(0, 65)}…' : title,
      'updated': DateTime.now().toIso8601String(),
      'web_search': _webSearch,
      'messages': _messages.map((m) => Map<String, String>.from(m)).toList()
    };
    _threads.removeWhere((t) => t['id'] == _threadId);
    _threads.insert(0, thread);
    await _persist();
  }

  void _newChat() => setState(() {
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
        const Text('Lưu riêng theo tài khoản trên thiết bị này.'),
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
                              _messages
                                ..clear()
                                ..addAll((t['messages'] as List).map(
                                    (m) => Map<String, String>.from(m as Map)));
                              _history = false;
                              _webSearch = t['web_search'] == true;
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
    _userId = widget.accountChanges == null
        ? Supabase.instance.client.auth.currentUser?.id
        : widget.initialUserId;
    final changes = widget.accountChanges ??
        Supabase.instance.client.auth.onAuthStateChange
            .map((event) => event.session?.user.id);
    _auth = changes.listen((id) {
      if (id != _userId && mounted) {
        setState(() {
          _userId = id;
          _generation++;
          _messages.clear();
          _input.clear();
          _open = _busy = _consent = _webSearch = _expanded = false;
          assistantDialog.value = false;
          _error = null;
          _threads = [];
          _threadId = null;
          _history = false;
          _historyQuery = '';
          _deleteId = null;
        });
        _loadHistory();
      }
    });
    assistantPrompt.addListener(_openPrompt);
    assistantDialog.addListener(_handleDialog);
    _loadHistory();
  }

  @override
  void dispose() {
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
    final text = _input.text.trim();
    if (text.isEmpty || _busy || !_consent || _loadingHistory) return;
    final generation = _generation;
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _input.clear();
      _error = null;
      _busy = true;
    });
    _toBottom();
    try {
      final history = assistantContext(_messages, webSearch: _webSearch);
      final reply = await (widget.sendMessage ?? _request)(history)
          .timeout(const Duration(seconds: 45));
      if (reply.trim().isEmpty) throw const FormatException();
      if (mounted && generation == _generation) {
        setState(() => _messages.add({'role': 'assistant', 'content': reply}));
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
    final response = await Supabase.instance.client.functions.invoke(
        'study-assistant',
        body: {'messages': history, 'web_search': _webSearch});
    final reply = response.data is Map ? response.data['reply'] : null;
    if (reply is! String) throw const FormatException();
    return reply;
  }

  Widget _panel() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      color: colors.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(children: [
              CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.smart_toy_rounded,
                      color: colors.primary, size: 23)),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Trợ lý AI',
                      style: TextStyle(fontWeight: FontWeight.w600))),
              IconButton(
                  tooltip: 'Trò chuyện mới',
                  onPressed: _busy || _loadingHistory ? null : _newChat,
                  icon: const Icon(Icons.add_comment_outlined, size: 20)),
              IconButton(
                  tooltip: 'Lịch sử trò chuyện',
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _history = !_history;
                            _historyQuery = '';
                          }),
                  icon: Icon(
                      _history ? Icons.chat_bubble_outline : Icons.history,
                      size: 20)),
              IconButton(
                  tooltip: 'Thu gọn',
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    _closePanel();
                  },
                  icon: const Icon(Icons.keyboard_arrow_down)),
            ])),
        const Divider(height: 1),
        Expanded(
            child: _history
                ? _historyList()
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                        if (!_consent) ...[
                          const Text('Cùng bạn học tập hiệu quả hơn',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          const Text(
                              'Tin nhắn được gửi đến Groq. Khi bật tra cứu web, truy vấn có thể được gửi tới dịch vụ tìm kiếm Exa. Tránh gửi thông tin nhạy cảm. Lịch sử lưu trên thiết bị theo tài khoản; bạn có thể mở lại hoặc xóa. Trợ lý chưa tự đọc hay thay đổi lịch.'),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: () => setState(() => _consent = true),
                              child: const Text('Đồng ý và bắt đầu')),
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
                        if (_consent) ...[
                          FilterChip(
                              label: const Text('Tra cứu web'),
                              selected: _webSearch,
                              onSelected: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _webSearch = value)),
                          Text(
                              _webSearch
                                  ? 'Yêu cầu tra cứu nguồn web. Máy chủ cần được bật tính năng này.'
                                  : 'Đang tư vấn từ kiến thức AI và cuộc trò chuyện, chưa tra cứu web.',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 12),
                        ],
                        for (final message in _messages)
                          Align(
                              alignment: message['role'] == 'user'
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: message['role'] == 'user'
                                          ? colors.primaryContainer
                                          : colors.surfaceContainer,
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SelectableText(message['content']!),
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
        if (!_history)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                    child: TextField(
                        controller: _input,
                        enabled: _consent && !_busy,
                        maxLength: 2000,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            hintText: 'Nhắn cho trợ lý…',
                            counterText: '',
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(18)))),
                        onSubmitted: (_) => _send())),
                IconButton(
                    tooltip: 'Gửi',
                    onPressed: _consent && !_busy ? _send : null,
                    icon: const Icon(Icons.arrow_upward_rounded)),
              ])),
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
          final height = math.max(0.0,
              math.min(520.0, box.maxHeight - bottom - media.padding.top - 12));
          return Stack(children: [
            widget.child,
            if (_userId != null && _expanded) ...[
              Positioned.fill(
                  child: ModalBarrier(
                      color: Colors.black.withValues(alpha: .28),
                      dismissible: true,
                      onDismiss: _closePanel)),
              Positioned.fill(
                  child: Padding(
                      padding: EdgeInsets.fromLTRB(16, media.padding.top + 16,
                          16, keyboard + media.padding.bottom + 16),
                      child: Center(
                          child: ConstrainedBox(
                              key: const ValueKey('assistant-dialog'),
                              constraints: const BoxConstraints(
                                  maxWidth: 820, maxHeight: 760),
                              child: CallbackShortcuts(bindings: {
                                const SingleActivator(
                                    LogicalKeyboardKey.escape): _closePanel,
                              }, child: _panel()))))),
            ],
            if (_userId != null &&
                !_expanded &&
                appPreferences.showAssistant &&
                height > 120)
              Positioned(
                  right: 12,
                  bottom: bottom,
                  child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
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
                              width: math.min(380, box.maxWidth - 24),
                              height: height,
                              child: _panel())
                          : FloatingActionButton.small(
                              key: const ValueKey('assistant-launcher'),
                              heroTag: 'global-assistant',
                              tooltip: 'Mở trợ lý AI',
                              onPressed: () => setState(() => _open = true),
                              child: const Icon(Icons.smart_toy_rounded)))),
          ]);
        }),
      ));
}
