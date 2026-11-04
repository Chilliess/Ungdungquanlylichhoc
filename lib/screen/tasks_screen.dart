import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/learning_store.dart';
import '../models/schedule_recurrence.dart';
import '../widgets/app_notice.dart';
import 'confirm_action.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _loading = true, _planning = false, _done = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await learningStore.load();
    } catch (_) {
      _error = 'Không đọc được dữ liệu công việc.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Map<String, dynamic>? task]) async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => TaskEditor(task: task));
    if (result == null || !mounted) return;
    learningStore.tasks.removeWhere((t) => t['id'] == result['id']);
    learningStore.tasks.add(result);
    // Changes invalidate future proposals; past activity remains in the statistics.
    if (task != null) {
      learningStore.blocks.removeWhere((b) =>
          b['taskId'] == task['id'] &&
          DateTime.parse(b['start']).isAfter(DateTime.now()));
    }
    await _save();
  }

  Future<void> _save() async {
    try {
      await learningStore.save();
    } catch (_) {
      if (mounted) {
        AppNotice.show(
            context,
            const SnackBar(
                content: Text(
                    'Chưa lưu được thay đổi trên thiết bị. Vui lòng thử lại.')));
      }
    }
    if (mounted) setState(() {});
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
      final client = Supabase.instance.client, now = DateTime.now();
      final owner = client.auth.currentUser?.id;
      if (owner == null) throw StateError('Sign in');
      final results = await Future.wait([
        client.from('schedules').select().eq('user_id', owner),
        client.from('schedule_exams').select().eq('user_id', owner),
      ]);
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
        busy.add(
            BusySlot(at(day, row['start_time']), at(day, row['end_time'])));
      }
      for (final b in learningStore.blocks) {
        busy.add(
            BusySlot(DateTime.parse(b['start']), DateTime.parse(b['end'])));
      }
      final tasks = learningStore.pending.map((t) {
        final planned = learningStore.blocks
            .where((b) =>
                b['taskId'] == t['id'] &&
                DateTime.parse(b['start']).isAfter(now))
            .fold<int>(
                0,
                (v, b) =>
                    v +
                    DateTime.parse(b['end'])
                        .difference(DateTime.parse(b['start']))
                        .inMinutes);
        return {
          ...t,
          'remaining': ((t['minutes'] as int) -
                  learningStore.actualFor(t['id']) -
                  planned)
              .clamp(0, 100000)
        };
      }).toList();
      final plan = planStudy(
          tasks: tasks,
          busy: busy,
          now: now,
          startHour: hours[0],
          endHour: hours[1]);
      if (!mounted) return;
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
        learningStore.blocks.addAll(plan.blocks);
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Công việc'), actions: [
          IconButton(
              tooltip: 'Thêm công việc',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add))
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListenableBuilder(
                listenable: learningStore,
                builder: (context, _) => Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              Text('Từng bước tới mục tiêu',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 8),
                              const Text(
                                  'Bài tập, ôn thi và lịch tự học của bạn. Dữ liệu công việc lưu trên thiết bị này.'),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                  onPressed: _planning ? null : _plan,
                                  icon: const Icon(Icons.auto_fix_high),
                                  label: Text(_planning
                                      ? 'Đang kiểm tra lịch…'
                                      : 'Tự xếp lịch học')),
                              const SizedBox(height: 16),
                              SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(
                                        value: false, label: Text('Cần làm')),
                                    ButtonSegment(
                                        value: true, label: Text('Hoàn thành'))
                                  ],
                                  selected: {
                                    _done
                                  },
                                  onSelectionChanged: (v) =>
                                      setState(() => _done = v.first)),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              const SizedBox(height: 16),
                              if (!learningStore.tasks
                                  .any((t) => (t['done'] == true) == _done))
                                const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                        'Chưa có công việc trong mục này. Nhấn + để thêm.')),
                              for (final task in learningStore.tasks
                                  .where((t) => (t['done'] == true) == _done))
                                Card(
                                    elevation: 0,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Expanded(
                                                    child: Text(task['title'],
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium)),
                                                PopupMenuButton<String>(
                                                    onSelected: (action) async {
                                                      if (action == 'edit') {
                                                        await _edit(task);
                                                        return;
                                                      }
                                                      if (!await confirmAction(
                                                          context,
                                                          deleting: action ==
                                                              'delete',
                                                          message: action ==
                                                                  'delete'
                                                              ? 'Xóa công việc và các phiên tự học đã xếp? Nhật ký học đã ghi nhận được giữ lại.'
                                                              : 'Thay đổi trạng thái công việc này?')) {
                                                        return;
                                                      }
                                                      if (action == 'delete') {
                                                        learningStore.tasks
                                                            .remove(task);
                                                        learningStore.blocks
                                                            .removeWhere((b) =>
                                                                b['taskId'] ==
                                                                task['id']);
                                                      } else {
                                                        task['done'] = !_done;
                                                        if (task['done'] ==
                                                            true) {
                                                          learningStore.blocks
                                                              .removeWhere((b) =>
                                                                  b['taskId'] ==
                                                                      task[
                                                                          'id'] &&
                                                                  DateTime.parse(b[
                                                                          'start'])
                                                                      .isAfter(
                                                                          DateTime
                                                                              .now()));
                                                        }
                                                      }
                                                      await _save();
                                                    },
                                                    itemBuilder: (_) => [
                                                          const PopupMenuItem(
                                                              value: 'edit',
                                                              child: Text(
                                                                  'Chỉnh sửa')),
                                                          PopupMenuItem(
                                                              value: 'done',
                                                              child: Text(_done
                                                                  ? 'Đánh dấu chưa xong'
                                                                  : 'Hoàn thành')),
                                                          const PopupMenuItem(
                                                              value: 'delete',
                                                              child: Text('Xóa',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .red)))
                                                        ])
                                              ]),
                                              Text(task['subject']),
                                              const SizedBox(height: 8),
                                              Text(
                                                  'Hạn ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(task['deadline']))}',
                                                  style: TextStyle(
                                                      color: DateTime.parse(task[
                                                                      'deadline'])
                                                                  .isBefore(DateTime
                                                                      .now()) &&
                                                              !_done
                                                          ? Theme.of(context)
                                                              .colorScheme
                                                              .error
                                                          : null)),
                                              const SizedBox(height: 8),
                                              Text('${[
                                                'Dễ',
                                                'Vừa',
                                                'Khó'
                                              ][(task['difficulty'] as int) - 1]} · Dự kiến ${task['minutes']} phút · Đã học ${learningStore.actualFor(task['id'])} phút'),
                                              if (!_done)
                                                Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: TextButton.icon(
                                                        onPressed: () async {
                                                          await Navigator.of(
                                                                  context)
                                                              .push(MaterialPageRoute(
                                                                  builder: (_) =>
                                                                      FocusScreen(
                                                                          task:
                                                                              task)));
                                                          if (mounted) {
                                                            setState(() {});
                                                          }
                                                        },
                                                        icon: const Icon(Icons
                                                            .play_circle_outline),
                                                        label: const Text(
                                                            'Bắt đầu tập trung'))),
                                            ]))),
                            ])))),
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
  const TaskEditor({super.key, this.task});
  final Map<String, dynamic>? task;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController title, subject, minutes;
  late DateTime deadline;
  int difficulty = 2;
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    title = TextEditingController(text: t?['title']);
    subject = TextEditingController(text: t?['subject']);
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
                    TextFormField(
                        controller: subject,
                        maxLength: 120,
                        decoration:
                            const InputDecoration(labelText: 'Môn học *'),
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Nhập môn học' : null),
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
                    'subject': subject.text.trim(),
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
  final _watch = Stopwatch();
  Timer? _timer;
  bool _saved = false, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
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
    setState(() => _saving = true);
    final log = {
      'id': LearningStore.id(),
      'taskId': widget.task['id'],
      'title': widget.task['title'],
      'subject': widget.task['subject'],
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
