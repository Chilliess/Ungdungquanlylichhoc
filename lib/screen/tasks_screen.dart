import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/learning_store.dart';
import '../models/schedule_recurrence.dart';
import '../widgets/app_notice.dart';
import 'confirm_action.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen(
      {super.key, this.embedded = false, this.store, this.loadPlan});
  final bool embedded;
  final LearningStore? store;
  final Future<StudyPlan> Function(List<int> hours)? loadPlan;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final LearningStore _store = widget.store ?? learningStore;
  bool _loading = true, _planning = false, _done = false, _saving = false;
  String? _subjectFilter;
  String? _error;
  Map<String, dynamic>? _suggestion;
  bool _suggestionFailed = false;
  Timer? _suggestionTimer;
  int _suggestionVersion = 0;
  @override
  void initState() {
    super.initState();
    _store.addListener(_storeChanged);
    _load();
  }

  void _storeChanged() {
    if (!mounted) return;
    _suggestionVersion++;
    _suggestion = null;
    _suggestionTimer?.cancel();
    _suggestionTimer =
        Timer(const Duration(milliseconds: 150), _refreshSuggestion);
  }

  Future<void> _refreshSuggestion() async {
    final version = ++_suggestionVersion;
    if (_store.pending.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestion = null;
          _suggestionFailed = false;
        });
      }
      return;
    }
    try {
      final plan = await _loadPlan([18, 22]);
      if (mounted && version == _suggestionVersion) {
        setState(() {
          _suggestion = plan.blocks.isEmpty ? null : plan.blocks.first;
          _suggestionFailed = false;
        });
      }
    } catch (_) {
      if (mounted && version == _suggestionVersion) {
        setState(() {
          _suggestion = null;
          _suggestionFailed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _suggestionTimer?.cancel();
    _store.removeListener(_storeChanged);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _store.load();
    } catch (_) {
      _error = 'Không đọc được dữ liệu công việc.';
    }
    if (mounted) {
      setState(() => _loading = false);
      _storeChanged();
    }
  }

  Future<void> _edit([Map<String, dynamic>? task]) async {
    final owner = Supabase.instance.client.auth.currentUser?.id;
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => TaskEditor(task: task, subjects: _store.subjects));
    if (result == null ||
        !mounted ||
        Supabase.instance.client.auth.currentUser?.id != owner) {
      return;
    }
    _store.tasks.removeWhere((t) => t['id'] == result['id']);
    _store.tasks.add(result);
    // Changes invalidate future proposals; past activity remains in the statistics.
    if (task != null) {
      _store.blocks.removeWhere((b) =>
          b['taskId'] == task['id'] &&
          DateTime.parse(b['start']).isAfter(DateTime.now()));
    }
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _store.save();
    } catch (_) {
      if (mounted) {
        AppNotice.show(
            context,
            const SnackBar(
                content: Text('Chưa lưu được thay đổi. Vui lòng thử lại.')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      await _store.refresh();
    } catch (_) {
      _error = 'Chưa cập nhật được công việc.';
    }
    if (mounted) {
      setState(() {
        _loading = false;
        if (!_store.subjects.any((s) => s['id'] == _subjectFilter)) {
          _subjectFilter = null;
        }
      });
      _storeChanged();
    }
  }

  Future<StudyPlan> _loadPlan(List<int> hours) async {
    if (widget.loadPlan != null) return widget.loadPlan!(hours);
    final client = Supabase.instance.client, now = DateTime.now();
    final owner = client.auth.currentUser?.id;
    if (owner == null) throw StateError('Sign in');
    final results = await Future.wait([
      client.from('schedules').select().eq('user_id', owner),
      client.from('schedule_exams').select().eq('user_id', owner),
    ]);
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    final busy = <BusySlot>[];
    DateTime at(DateTime day, String value) {
      final p = value.split(':');
      return DateTime(
          day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
    }

    for (final row in results[0]) {
      for (var i = 0; i < 14; i++) {
        final day = DateTime(now.year, now.month, now.day + i);
        if (ScheduleRecurrence.occursOn(row, day)) {
          busy.add(
              BusySlot(at(day, row['start_time']), at(day, row['end_time'])));
        }
      }
    }
    for (final row in results[1]) {
      final day = DateTime.parse(row['exam_date']);
      busy.add(BusySlot(at(day, row['start_time']), at(day, row['end_time'])));
    }
    for (final b in _store.blocks) {
      busy.add(BusySlot(DateTime.parse(b['start']), DateTime.parse(b['end'])));
    }
    final tasks = _store.pending.map((t) {
      final planned = _store.blocks
          .where((b) =>
              b['taskId'] == t['id'] && DateTime.parse(b['start']).isAfter(now))
          .fold<int>(
              0,
              (v, b) =>
                  v +
                  DateTime.parse(b['end'])
                      .difference(DateTime.parse(b['start']))
                      .inMinutes);
      return {
        ...t,
        'subject': _store.subjectName(t),
        'remaining':
            ((t['minutes'] as int) - _store.actualFor(t['id']) - planned)
                .clamp(0, 100000)
      };
    }).toList();
    return planStudy(
        tasks: tasks,
        busy: busy,
        now: now,
        startHour: hours[0],
        endHour: hours[1]);
  }

  Future<void> _plan() async {
    final hours = await showDialog<List<int>>(
        context: context, builder: (_) => const StudyHoursDialog());
    if (hours == null || !mounted) return;
    setState(() {
      _planning = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final owner = client.auth.currentUser?.id;
      final plan = await _loadPlan(hours);
      if (!mounted || client.auth.currentUser?.id != owner) return;
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Đề xuất tự học · 14 ngày'),
                content: SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text(
                              'Ưu tiên deadline gần nhất, không trùng lịch đã tải. Nghỉ 10 phút giữa các phiên mới.'),
                          const SizedBox(height: 12),
                          if (plan.blocks.isEmpty)
                            const Text('Chưa có phiên mới để xếp.'),
                          for (final b in plan.blocks)
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(b['title']),
                                subtitle: Text(
                                    '${DateFormat('dd/MM HH:mm').format(DateTime.parse(b['start']))} – ${DateFormat('HH:mm').format(DateTime.parse(b['end']))}')),
                          if (plan.unscheduledMinutes > 0)
                            Text(
                                'Còn ${plan.unscheduledMinutes} phút chưa xếp được trước hạn. Hãy mở rộng giờ rảnh hoặc điều chỉnh khối lượng.',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      onPressed: plan.blocks.isEmpty
                          ? null
                          : () => Navigator.pop(context, true),
                      child: const Text('Lưu vào lịch'))
                ],
              ));
      if (accepted == true && mounted && owner == client.auth.currentUser?.id) {
        _store.blocks.addAll(plan.blocks);
        await _save();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Chưa thể xếp lịch: cần tải đủ lịch học và lịch thi để kiểm tra xung đột. Hãy kiểm tra kết nối.');
      }
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _taskAction(Map<String, dynamic> task, String action) async {
    if (action == 'edit') {
      await _edit(task);
      return;
    }
    if (action == 'delete') {
      if (!await confirmAction(context,
          deleting: true,
          message:
              'Xóa công việc và các phiên tự học đã xếp? Nhật ký học đã ghi nhận được giữ lại.')) {
        return;
      }
      _store.tasks.remove(task);
      _store.blocks.removeWhere((b) => b['taskId'] == task['id']);
    } else {
      task['done'] = task['done'] != true;
      if (task['done'] == true) {
        _store.blocks.removeWhere((b) =>
            b['taskId'] == task['id'] &&
            DateTime.parse(b['start']).isAfter(DateTime.now()));
      }
    }
    await _save();
  }

  Future<void> _focus(Map<String, dynamic> task) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FocusScreen(task: task)));
    if (mounted) {
      setState(() {});
      _refreshSuggestion();
    }
  }

  Widget _taskRow(Map<String, dynamic> task) {
    final colors = Theme.of(context).colorScheme;
    final complete = task['done'] == true;
    final deadline = DateTime.parse(task['deadline']);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
                value: complete,
                onChanged:
                    _planning ? null : (_) => _taskAction(task, 'toggle'),
                semanticLabel: 'Hoàn thành ${task['title']}'),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(task['title'],
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  decoration: complete
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: complete
                                      ? colors.onSurfaceVariant
                                      : colors.onSurface)),
                          const SizedBox(height: 5),
                          Text(_store.subjectName(task),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(
                              'Hạn ${DateFormat('dd/MM · HH:mm').format(deadline)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: !complete &&
                                          deadline.isBefore(DateTime.now())
                                      ? colors.error
                                      : colors.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: colors.primaryContainer
                                      .withValues(alpha: .5),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                  '${[
                                    'Dễ',
                                    'Vừa',
                                    'Khó'
                                  ][(task['difficulty'] as int) - 1]} · ${task['minutes']} phút',
                                  style: TextStyle(
                                      fontSize: 11, color: colors.primary))),
                          if (_store.actualFor(task['id']) > 0)
                            Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    'Đã học ${_store.actualFor(task['id'])} phút',
                                    style: const TextStyle(fontSize: 11))),
                        ]))),
            PopupMenuButton<String>(
                tooltip: 'Thao tác công việc',
                enabled: !_planning,
                onSelected: (action) => _taskAction(task, action),
                itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit', child: Text('Chỉnh sửa')),
                      PopupMenuItem(
                          value: 'toggle',
                          child: Text(complete
                              ? 'Đánh dấu chưa xong'
                              : 'Đánh dấu hoàn thành')),
                      const PopupMenuItem(value: 'delete', child: Text('Xóa')),
                    ]),
          ]),
          if (!complete)
            Padding(
                padding: const EdgeInsets.only(left: 48, top: 4),
                child: TextButton.icon(
                    onPressed: () => _focus(task),
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const Text('Bắt đầu tập trung'))),
        ]));
  }

  Widget _suggestionCard() {
    final colors = Theme.of(context).colorScheme;
    final suggestion = _suggestion;
    final date =
        suggestion == null ? null : DateTime.parse(suggestion['start']);
    final today = DateUtils.dateOnly(DateTime.now());
    final label = date == null
        ? null
        : DateUtils.isSameDay(date, today)
            ? 'Hôm nay'
            : DateUtils.isSameDay(date, today.add(const Duration(days: 1)))
                ? 'Ngày mai'
                : DateFormat('dd/MM').format(date);
    return Container(
        key: const ValueKey('task-free-slot'),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: .48),
            borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('KHOẢNG TRỐNG PHÙ HỢP',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          Text(
              date == null
                  ? (_store.pending.isEmpty
                      ? 'Một khoảng nghỉ cho bạn'
                      : 'Chọn khung giờ phù hợp')
                  : '$label, ${DateFormat('HH:mm').format(date)} – ${DateFormat('HH:mm').format(DateTime.parse(suggestion!['end']))}',
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(
              suggestion == null
                  ? (_store.pending.isEmpty
                      ? 'Thêm công việc để bắt đầu chia nhỏ mục tiêu.'
                      : _suggestionFailed
                          ? 'Chưa tải đủ lịch để gợi ý khoảng trống. Bạn có thể thử xếp lịch lại.'
                          : 'Kiểm tra lịch và hạn chót trước khi chọn phiên tự học.')
                  : 'Một phiên tự học để bắt đầu “${suggestion['title']}”. Đề xuất này chưa được lưu.',
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
              onPressed: _planning || _store.pending.isEmpty ? null : _plan,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Xem phương án xếp lịch')),
        ]));
  }

  Widget _content() {
    final colors = Theme.of(context).colorScheme;
    final tasks = _store.tasks
        .where((t) =>
            (t['done'] == true) == _done &&
            (_subjectFilter == null || t['subjectId'] == _subjectFilter))
        .toList()
      ..sort((a, b) =>
          (a['deadline'] as String).compareTo(b['deadline'] as String));
    final scoped = _store.tasks
        .where(
            (t) => _subjectFilter == null || t['subjectId'] == _subjectFilter)
        .toList();
    final doneCount = scoped.where((t) => t['done'] == true).length;
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 100),
                children: [
                  const Text('Việc cần làm',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.7)),
                  const SizedBox(height: 8),
                  Text('Chia nhỏ mục tiêu, tiến từng bước.',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add),
                          label: const Text('Công việc'))),
                  Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Đồng bộ'))),
                  if (_store.subjects.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _subjectFilter,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Lọc theo môn học'),
                      items: [
                        const DropdownMenuItem<String>(
                            value: null, child: Text('Tất cả môn học')),
                        for (final subject in _store.subjects)
                          DropdownMenuItem(
                              value: subject['id'] as String,
                              child: Text(subject['subject_name'] as String))
                      ],
                      onChanged: (id) => setState(() => _subjectFilter = id),
                    ),
                  const SizedBox(height: 24),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 18),
                      decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          border: Border.all(
                              color:
                                  colors.outlineVariant.withValues(alpha: .5)),
                          borderRadius: BorderRadius.circular(24)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 18,
                                runSpacing: 8,
                                children: [
                                  const Text('Ưu tiên tuần này',
                                      style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w700)),
                                  OutlinedButton.icon(
                                      onPressed:
                                          _planning || _store.pending.isEmpty
                                              ? null
                                              : _plan,
                                      icon: const Icon(
                                          Icons.auto_fix_high_rounded,
                                          size: 18),
                                      label: Text(_planning
                                          ? 'Đang kiểm tra…'
                                          : 'Tự xếp lịch')),
                                ]),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, children: [
                              ChoiceChip(
                                  label: Text(
                                      'Cần làm · ${_store.pending.length}'),
                                  selected: !_done,
                                  onSelected: (_) =>
                                      setState(() => _done = false)),
                              ChoiceChip(
                                  label: Text('Đã xong · $doneCount'),
                                  selected: _done,
                                  onSelected: (_) =>
                                      setState(() => _done = true)),
                            ]),
                            if (_error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(_error!,
                                      style: TextStyle(color: colors.error))),
                            if (tasks.isEmpty)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 30),
                                  child: Text(
                                      _done
                                          ? 'Chưa có công việc hoàn thành.'
                                          : 'Chưa có công việc. Bấm + Công việc để thêm.',
                                      style: TextStyle(
                                          color: colors.onSurfaceVariant))),
                            for (var i = 0; i < tasks.length; i++) ...[
                              _taskRow(tasks[i]),
                              if (i < tasks.length - 1)
                                const Divider(height: 1, indent: 48),
                            ],
                          ])),
                  const SizedBox(height: 22),
                  _suggestionCard(),
                  const SizedBox(height: 16),
                  Text(
                      'Đã hoàn thành $doneCount/${scoped.length} công việc · ${_store.cloudSynced ? 'Đã đồng bộ tài khoản' : 'Đã lưu trên máy · Chờ đồng bộ'}.',
                      style: TextStyle(
                          color: colors.onSurfaceVariant, fontSize: 12)),
                ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF11131D)
            : const Color(0xFFF5F6FB),
        appBar: widget.embedded ? null : AppBar(title: const Text('Công việc')),
        body: SafeArea(
            bottom: false,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListenableBuilder(
                    listenable: _store,
                    builder: (_, __) =>
                        AbsorbPointer(absorbing: _saving, child: _content()))),
      );
}

class StudyHoursDialog extends StatefulWidget {
  const StudyHoursDialog({super.key});
  @override
  State<StudyHoursDialog> createState() => _StudyHoursDialogState();
}

class _StudyHoursDialogState extends State<StudyHoursDialog> {
  int start = 18, end = 22;
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Giờ rảnh để tự học'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Áp dụng mỗi ngày trong 14 ngày tới.'),
            DropdownButtonFormField<int>(
                initialValue: start,
                decoration: const InputDecoration(labelText: 'Từ giờ'),
                items: List.generate(23,
                    (i) => DropdownMenuItem(value: i, child: Text('$i:00'))),
                onChanged: (v) => setState(() => start = v!)),
            DropdownButtonFormField<int>(
                initialValue: end,
                decoration: const InputDecoration(labelText: 'Đến giờ'),
                items: List.generate(
                    24,
                    (i) => DropdownMenuItem(
                        value: i + 1, child: Text('${i + 1}:00'))),
                onChanged: (v) => setState(() => end = v!)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy')),
            FilledButton(
                onPressed: end <= start
                    ? null
                    : () => Navigator.pop(context, [start, end]),
                child: const Text('Tìm khoảng trống'))
          ]);
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, this.task, this.subjects = const []});
  final Map<String, dynamic>? task;
  final List<Map<String, dynamic>> subjects;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController title, subject, minutes;
  late DateTime deadline;
  int difficulty = 2;
  String? _subjectId;
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _subjectId = t?['subjectId'] as String?;
    title = TextEditingController(text: t?['title']);
    subject = TextEditingController(text: t?['subject']);
    final matches = widget.subjects
        .where((s) =>
            s['id'] == t?['subjectId'] ||
            (t?['subjectId'] == null && s['subject_name'] == t?['subject']))
        .toList();
    if (matches.length == 1) {
      _subjectId = matches.single['id'] as String;
      subject.text = matches.single['subject_name'] as String;
    }
    minutes = TextEditingController(text: '${t?['minutes'] ?? 120}');
    deadline = t == null
        ? DateTime.now().add(const Duration(days: 3))
        : DateTime.parse(t['deadline']);
    difficulty = t?['difficulty'] ?? 2;
  }

  @override
  void dispose() {
    title.dispose();
    subject.dispose();
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(
              widget.task == null ? 'Thêm công việc' : 'Chỉnh sửa công việc'),
          content: SizedBox(
              width: 440,
              child: Form(
                  key: _form,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        controller: title,
                        maxLength: 120,
                        decoration:
                            const InputDecoration(labelText: 'Tên công việc *'),
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Nhập tên công việc' : null),
                    DropdownButtonFormField<String>(
                        initialValue: _subjectId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Liên kết môn học'),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Công việc cá nhân / môn khác')),
                          if (_subjectId != null &&
                              !widget.subjects
                                  .any((s) => s['id'] == _subjectId))
                            DropdownMenuItem(
                                value: _subjectId, child: Text(subject.text)),
                          for (final s in widget.subjects)
                            DropdownMenuItem(
                                value: s['id'] as String,
                                child: Text(s['subject_name'] as String))
                        ],
                        onChanged: (id) => setState(() {
                              _subjectId = id;
                              if (id != null) {
                                subject.text = widget.subjects.firstWhere(
                                        (s) => s['id'] == id)['subject_name']
                                    as String;
                              }
                            })),
                    if (_subjectId == null)
                      TextFormField(
                          controller: subject,
                          maxLength: 120,
                          decoration: const InputDecoration(
                              labelText:
                                  'Môn học / nhóm công việc (tùy chọn)')),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Deadline'),
                        subtitle: Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(deadline)),
                        trailing: const Icon(Icons.event),
                        onTap: () async {
                          final day = await showDatePicker(
                              context: context,
                              initialDate: deadline,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100));
                          if (day == null || !context.mounted) return;
                          final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(deadline));
                          if (time != null && mounted) {
                            setState(() => deadline = DateTime(day.year,
                                day.month, day.day, time.hour, time.minute));
                          }
                        }),
                    TextFormField(
                        controller: minutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Thời lượng dự kiến (phút) *'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 5 || n > 10000
                              ? 'Nhập từ 5 đến 10.000 phút'
                              : null;
                        }),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                        initialValue: difficulty,
                        decoration: const InputDecoration(labelText: 'Độ khó'),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Dễ')),
                          DropdownMenuItem(value: 2, child: Text('Vừa')),
                          DropdownMenuItem(value: 3, child: Text('Khó'))
                        ],
                        onChanged: (v) => difficulty = v!),
                  ])))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy')),
            FilledButton(
                onPressed: () async {
                  if (!_form.currentState!.validate()) return;
                  if (widget.task != null &&
                      !await confirmAction(context,
                          message:
                              'Lưu thay đổi và bỏ các phiên tương lai để xếp lại theo thông tin mới?')) {
                    return;
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context, {
                    'id': widget.task?['id'] ?? LearningStore.id(),
                    'title': title.text.trim(),
                    'subject': subject.text.trim().isEmpty
                        ? 'Cá nhân'
                        : subject.text.trim(),
                    'subjectId': _subjectId,
                    'deadline': deadline.toIso8601String(),
                    'difficulty': difficulty,
                    'minutes': int.parse(minutes.text),
                    'done': widget.task?['done'] ?? false
                  });
                },
                child: const Text('Lưu'))
          ]);
}

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.task});
  final Map<String, dynamic> task;
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> with WidgetsBindingObserver {
  late final String? _owner;
  final _watch = Stopwatch();
  Timer? _timer;
  bool _saved = false, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _owner = Supabase.instance.client.auth.currentUser?.id;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _watch.stop();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _watch.stop();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saved || _saving) return;
    _watch.stop();
    if (_watch.elapsed.inMinutes < 1) {
      setState(() => _error = 'Học ít nhất một phút để ghi nhận.');
      return;
    }
    if (!await confirmAction(context,
        message: 'Ghi nhận ${_watch.elapsed.inMinutes} phút tự học?')) {
      return;
    }
    if (!mounted) return;
    if (_owner == null ||
        Supabase.instance.client.auth.currentUser?.id != _owner) {
      setState(() => _error = 'Tài khoản đã thay đổi. Hãy mở lại công việc.');
      return;
    }
    setState(() => _saving = true);
    final log = {
      'id': LearningStore.id(),
      'taskId': widget.task['id'],
      'title': widget.task['title'],
      'subject': widget.task['subject'],
      'subjectId': widget.task['subjectId'],
      'date': DateTime.now().toIso8601String(),
      'minutes': _watch.elapsed.inMinutes
    };
    learningStore.logs.add(log);
    try {
      await learningStore.save();
      _saved = true;
      if (mounted) Navigator.pop(context);
    } catch (_) {
      learningStore.logs.remove(log);
      if (mounted) {
        setState(() => _error = 'Chưa lưu được phiên học. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _saved || _watch.elapsed.inSeconds == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        if (await confirmAction(context,
                message: 'Thoát mà không ghi nhận phiên học này?') &&
            context.mounted) {
          setState(() => _saved = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
          appBar: AppBar(title: const Text('Tập trung')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.self_improvement, size: 56),
                    const SizedBox(height: 24),
                    Text(widget.task['title'],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 24),
                    Text(
                        '${_watch.elapsed.inMinutes.toString().padLeft(2, '0')}:${(_watch.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.displayLarge),
                    const SizedBox(height: 12),
                    const Text(
                        'Gợi ý học 25 phút rồi nghỉ 5 phút. Bộ đếm tạm dừng khi rời ứng dụng.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(() {
                                  _watch.isRunning
                                      ? _watch.stop()
                                      : _watch.start();
                                }),
                        icon: Icon(
                            _watch.isRunning ? Icons.pause : Icons.play_arrow),
                        label: Text(_watch.isRunning
                            ? 'Tạm dừng'
                            : 'Bắt đầu / Tiếp tục')),
                    TextButton(
                        onPressed: _saving ? null : _finish,
                        child: const Text('Kết thúc và ghi nhận')),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])))));
}
