import 'package:untitled/widgets/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/home_models.dart';
import '../theme/app_palette.dart';
import '../models/schedule_recurrence.dart';
import 'lesson_editor.dart';
import 'lesson_categories.dart';

class SubjectManagementScreen extends StatefulWidget {
  const SubjectManagementScreen({super.key});
  @override
  State<SubjectManagementScreen> createState() =>
      _SubjectManagementScreenState();
}

class _SubjectManagementScreenState extends State<SubjectManagementScreen> {
  final _client = Supabase.instance.client;
  late final _categories = SupabaseLessonCategoryStore(_client);
  List<Map<String, dynamic>> _subjects = [], _schedules = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _categories.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = _client.auth.currentUser?.id;
      if (user == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final results = await Future.wait([
        _client
            .from('subjects')
            .select()
            .eq('user_id', user)
            .order('subject_name'),
        _client
            .from('schedules')
            .select()
            .eq('user_id', user)
            .order('start_date'),
      ]);
      try {
        await _categories.load();
      } catch (_) {
        // Subject information remains available when labels cannot be loaded.
      }
      if (!mounted) return;
      setState(() {
        _subjects = List<Map<String, dynamic>>.from(results[0]);
        _schedules = List<Map<String, dynamic>>.from(results[1]);
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không tải được môn học. Vui lòng thử lại.';
        });
      }
    }
  }

  String _date(dynamic value) => value == null
      ? 'Không giới hạn'
      : DateFormat('dd/MM/yyyy').format(DateTime.parse('$value'));
  String _time(dynamic value) =>
      '$value'.length >= 5 ? '$value'.substring(0, 5) : '--:--';

  Future<void> _edit(
      Map<String, dynamic>? subject, Map<String, dynamic>? schedule) async {
    final initialDate =
        ScheduleRecurrence.date(schedule?['start_date']) ?? DateTime.now();
    final initial = subject == null
        ? null
        : LessonDraft(
            title: subject['subject_name'] ?? '',
            date: initialDate,
            start: WeekdayUtils.parseTime(schedule?['start_time'] ?? '') ??
                TimeOfDay.now(),
            end: WeekdayUtils.parseTime(schedule?['end_time'] ?? '') ??
                TimeOfDay(
                    hour: (TimeOfDay.now().hour + 1) % 24,
                    minute: TimeOfDay.now().minute),
            location: schedule?['room'] ?? '',
            notes: schedule?['notes'] ?? '',
            category: schedule?['category'] ?? '',
            recurrence: schedule == null
                ? 'none'
                : ScheduleRecurrence.frequency(schedule),
            repeatUntil: schedule == null ||
                    ScheduleRecurrence.frequency(schedule) == 'none'
                ? null
                : ScheduleRecurrence.date(schedule['end_date']),
          );
    final saved = await showGeneralDialog<bool>(
        context: context,
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 380),
        transitionBuilder: (_, animation, secondary, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                  scale: Tween<double>(begin: .96, end: 1).animate(curved),
                  child: child));
        },
        pageBuilder: (_, animation, secondary) => LessonEditor(
            initialDate: initialDate,
            initial: initial,
            manageRecurrence: true,
            categoryStore: _categories,
            onSave: (draft) async {
              try {
                await _client.rpc('save_subject_schedule',
                    params: draft.toSubjectParameters(
                        subjectId: subject?['id']?.toString(),
                        scheduleId: schedule?['id']?.toString()));
              } on PostgrestException catch (error) {
                if (error.code == 'PGRST202' || error.code == '42703') {
                  throw Exception(
                      'Vui lòng cập nhật SQL lịch lặp trước khi lưu.');
                }
                throw Exception(error.message);
              }
            }));
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> subject) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Xóa môn học?'),
                content: Text(
                    'Xóa “${subject['subject_name']}” cùng các lịch học, lịch kiểm tra và nhắc nhở liên quan.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Xóa'))
                ]));
    if (confirmed != true) return;
    try {
      await _client.rpc('delete_calendar_subject',
          params: {'p_subject_id': subject['id']});
      await _load();
    } catch (_) {
      if (mounted) {
        AppNotice.show(
            context,
            const SnackBar(
                content: Text(
                    'Không xóa được môn học. Kiểm tra kết nối và bản cập nhật SQL.')));
      }
    }
  }

  Color _scheduleColor(
      Map<String, dynamic> subject, Map<String, dynamic>? schedule) {
    final category = schedule?['category']?.toString() ?? '';
    return category.isEmpty
        ? AppPalette.fromHex(subject['color_code']?.toString())
        : _categories.colorOf(category);
  }

  Widget _subjectLabels(Map<String, dynamic> subject) {
    final labels = _schedules
        .where((s) => s['subject_id'] == subject['id'])
        .map((s) => (s['category'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toSet();
    return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: labels
            .map((label) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: _categories.colorOf(label).withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.label,
                      size: 14, color: _categories.colorOf(label)),
                  const SizedBox(width: 4),
                  Text(label)
                ])))
            .toList());
  }

  Color _tint(Color color) => Color.alphaBlend(
      color.withValues(alpha: .10), Theme.of(context).colorScheme.surface);

  Widget _detailLine(Widget child) =>
      Padding(padding: const EdgeInsets.only(top: 12), child: child);

  Future<void> _details(Map<String, dynamic> subject) async {
    final schedules =
        _schedules.where((s) => s['subject_id'] == subject['id']).toList();
    final action = await showDialog<Object>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(subject['subject_name'] ?? 'Môn học'),
                content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          if (!(subject['subject_code'] ?? '')
                              .toString()
                              .startsWith('AUTO-'))
                            Text('Mã môn: ${subject['subject_code'] ?? ''}'),
                          if (schedules.isEmpty)
                            const Text(
                                'Môn học chưa có lịch. Chọn thiết lập để thêm giờ học và phòng học.'),
                          for (final schedule in schedules)
                            Card(
                                color: _tint(_scheduleColor(subject, schedule)),
                                elevation: 0,
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '${_time(schedule['start_time'])} – ${_time(schedule['end_time'])}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 12),
                                          Text(
                                              'Phòng học: ${schedule['room'] ?? ''}'),
                                          const SizedBox(height: 12),
                                          Text(
                                              'Ngày bắt đầu: ${_date(schedule['start_date'])}'),
                                          const SizedBox(height: 12),
                                          Text(
                                              'Lặp lại: ${ScheduleRecurrence.labels[ScheduleRecurrence.frequency(schedule)]}'),
                                          if (ScheduleRecurrence.frequency(
                                                  schedule) ==
                                              'weekly')
                                            _detailLine(Text(
                                                WeekdayUtils.describeDays(
                                                    schedule['day_of_week']))),
                                          if (ScheduleRecurrence.frequency(
                                                  schedule) !=
                                              'none')
                                            _detailLine(Text(
                                                'Kết thúc: ${_date(schedule['end_date'])}')),
                                          if ((schedule['category'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            _detailLine(Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: _scheduleColor(
                                                        subject, schedule)
                                                    .withValues(alpha: .16),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.label,
                                                        size: 18,
                                                        color: _scheduleColor(
                                                            subject, schedule)),
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                        child: Text(
                                                            schedule['category']
                                                                .toString())),
                                                  ]),
                                            )),
                                          if ((schedule['notes'] ?? '')
                                              .toString()
                                              .isNotEmpty)
                                            _detailLine(Text(
                                                'Ghi chú: ${schedule['notes']}')),
                                          const SizedBox(height: 12),
                                          Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton.icon(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          context, schedule),
                                                  icon: const Icon(
                                                      Icons.edit_outlined),
                                                  label:
                                                      const Text('Chỉnh sửa'))),
                                        ]))),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700),
                      child: const Text('Xóa')),
                  if (schedules.isEmpty)
                    TextButton(
                        onPressed: () => Navigator.pop(context, 'setup'),
                        child: const Text('Thiết lập lịch')),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Đóng'))
                ]));
    if (!mounted) return;
    if (action == 'delete') {
      await _delete(subject);
    } else if (action == 'setup') {
      await _edit(subject, null);
    } else if (action is Map<String, dynamic>) {
      await _edit(subject, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = _subjects
        .where((s) => '${s['subject_name']} ${s['subject_code']}'
            .toLowerCase()
            .contains(_query))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Quản lý môn học')),
        floatingActionButton: FloatingActionButton(
            tooltip: 'Thêm môn học',
            onPressed: () => _edit(null, null),
            child: const Icon(Icons.add)),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                          onChanged: (v) =>
                              setState(() => _query = v.trim().toLowerCase()),
                          decoration: const InputDecoration(
                              hintText: 'Tìm môn học',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder()))),
                  Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                      Text(_error!),
                                      TextButton(
                                          onPressed: _load,
                                          child: const Text('Thử lại'))
                                    ]))
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 88),
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      children: [
                                        if (subjects.isEmpty)
                                          const Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Text(
                                                  'Chưa có môn học phù hợp.')),
                                        for (final subject in subjects)
                                          Card(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surface,
                                              elevation: 0,
                                              child: ListTile(
                                                  leading: Icon(
                                                      Icons.school_outlined,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                                  title: Text(
                                                      subject['subject_name'] ??
                                                          ''),
                                                  subtitle:
                                                      _subjectLabels(subject),
                                                  trailing: const Icon(
                                                      Icons.chevron_right),
                                                  onTap: () =>
                                                      _details(subject))),
                                      ]))),
                ]))));
  }
}
