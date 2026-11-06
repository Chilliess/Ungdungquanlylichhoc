import '../services/calendar_conflicts.dart';
import '../services/study_data.dart';
import 'package:untitled/widgets/app_notice.dart';
import '../models/schedule_recurrence.dart';
import 'confirm_action.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:intl/intl.dart';
import 'lesson_editor.dart';
import 'lesson_categories.dart';
import 'lesson_search.dart';
import '../services/learning_store.dart';
import 'tasks_screen.dart';
import 'timetable_import.dart';

enum _ScheduleView { day, month, year }

class ViewScheduleScreen extends StatefulWidget {
  const ViewScheduleScreen(
      {super.key,
      this.openEditorOnStart = false,
      this.initialDate,
      this.embedded = false});
  final bool embedded;
  final DateTime? initialDate;
  final bool openEditorOnStart;

  @override
  State<ViewScheduleScreen> createState() => _ViewScheduleScreenState();
}

class _ViewScheduleScreenState extends State<ViewScheduleScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  List<dynamic> _scheduleRows = [], _examRows = [];
  int? _renderedYear;
  int _loadVersion = 0;

  void _ensureVisibleEvents() {
    final year =
        (_view == _ScheduleView.day ? _selectedDate : _browseDate).year;
    if (_renderedYear != null && _renderedYear != year && mounted) {
      _populateEvents(year);
    }
  }

  bool _isLoading = true;
  late final _categoryStore = SupabaseLessonCategoryStore(supabase);
  bool _isTransitioning = false;
  // Initialize on first use, including for a screen retained during hot reload.
  late final AnimationController _viewTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
    animationBehavior: AnimationBehavior.preserve,
  );
  static const _motionDuration = Duration(milliseconds: 380);
  late final EventController<Map<String, dynamic>> _eventController;
  _ScheduleView _view = _ScheduleView.day;
  DateTime _browseDate = DateTime.now();

  // Ngày đang hiển thị.
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _browseDate = _selectedDate;
    _eventController = EventController<Map<String, dynamic>>();
    studyDataRevision.addListener(_onStudyDataChanged);
    _loadDataFromSupabase();
    if (widget.openEditorOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editLesson();
      });
    }
  }

  @override
  void dispose() {
    studyDataRevision.removeListener(_onStudyDataChanged);
    _viewTransition.dispose();
    _eventController.dispose();
    _categoryStore.dispose();
    super.dispose();
  }

  Color _getColorFromHex(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.blueAccent;
    try {
      final buffer = StringBuffer();
      if (hexString.length == 7 || hexString.length == 6) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  Future<void> _loadDataFromSupabase() async {
    final version = ++_loadVersion;
    if (mounted) setState(() => _isLoading = true);

    try {
      await learningStore.load();
      if (!mounted || version != _loadVersion) return;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        return;
      }

      try {
        await _categoryStore.load();
      } catch (_) {
        // Calendars remain readable while the optional category update is pending.
      }
      final subjectsFuture = supabase
          .from('subjects')
          .select()
          .eq('user_id', userId)
          .then((rows) => List<Map<String, dynamic>>.from(rows));
      final eventRows = await Future.wait([
        loadOwnedStudyRows(supabase, 'schedules', userId,
            subjects: subjectsFuture),
        loadOwnedStudyRows(supabase, 'schedule_exams', userId,
            subjects: subjectsFuture),
      ]);
      final scheduleRes = eventRows[0];
      final examRes = eventRows[1];

      if (!mounted || version != _loadVersion) return;
      _scheduleRows = scheduleRes;
      _examRows = examRes;
      _populateEvents(
          (_view == _ScheduleView.day ? _selectedDate : _browseDate).year);
    } catch (e) {
      debugPrint('Lỗi tải lịch: $e');
      if (mounted) {
        AppNotice.show(
            context,
            const SnackBar(
                content: Text('Không tải được lịch. Vui lòng thử lại.')));
      }
    } finally {
      if (mounted && version == _loadVersion) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onStudyDataChanged() {
    if (mounted) _loadDataFromSupabase();
  }

  Future<void> _deleteEvent(
      CalendarEventData<Map<String, dynamic>> event) async {
    final item = event.event;
    final id = item?['id']?.toString();
    if (id == null) return;
    final isExam = item?['is_exam'] == true;
    final recurring = !isExam &&
        ScheduleRecurrence.frequency(item ?? const {}) != 'none';
    final confirmed = await confirmAction(
      context,
      deleting: true,
      message: recurring
          ? 'Xóa toàn bộ chuỗi lịch lặp này, bao gồm cả các buổi đã qua?'
          : 'Xóa lịch ${isExam ? 'kiểm tra' : 'học'} này?',
    );
    if (!confirmed || !mounted) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      AppNotice.show(
          context,
          const SnackBar(
              content: Text('Vui lòng đăng nhập lại để xóa lịch.')));
      return;
    }

    try {
      final table = isExam ? 'schedule_exams' : 'schedules';
      final deleted = await supabase
          .from(table)
          .delete()
          .eq('id', id)
          .eq('user_id', userId)
          .select('id');
      if (!mounted) return;
      if (deleted.isEmpty) {
        AppNotice.show(
            context,
            const SnackBar(
                content: Text('Không tìm thấy lịch hoặc lịch đã bị xóa.')));
        return;
      }
      studyDataChanged();
      AppNotice.show(
          context,
          SnackBar(
              content:
                  Text('Đã xóa ${isExam ? 'lịch kiểm tra' : 'lịch học'}.')));
    } catch (_) {
      if (mounted) {
        AppNotice.show(
            context,
            const SnackBar(
                content: Text('Không xóa được lịch. Vui lòng thử lại.')));
      }
    }
  }

  void _populateEvents(int year) {
    _renderedYear = year;
    final events = _buildEvents(year);
    _eventController.removeWhere((element) => true);
    _eventController.addAll(events);
    _eventController.addAll(learningStore.blocks.map((b) {
      final start = DateTime.parse(b['start']), end = DateTime.parse(b['end']);
      return CalendarEventData<Map<String, dynamic>>(
          title: 'Tự học: ${b['title']}',
          date: start,
          startTime: start,
          endTime: end,
          color: Colors.teal,
          event: {
            ...b,
            'is_study': true,
            'subjects': {'subject_name': b['title']},
            'room': 'Tự học'
          });
    }).toList());
  }

  List<CalendarEventData<Map<String, dynamic>>> _buildEvents(int year) {
    List<CalendarEventData<Map<String, dynamic>>> events = [];

    for (var item in _scheduleRows) {
      var mapItem = Map<String, dynamic>.from(item);
      mapItem['is_exam'] = false;

      final subject = mapItem['subjects'] ?? {};
      final subjectName = subject['subject_name'] ?? 'Môn học';
      final room = mapItem['room'] ?? 'Chưa có phòng';
      final Color subjectColor = (mapItem['category']?.toString() ?? '').isEmpty
          ? _getColorFromHex(subject['color_code'])
          : _categoryStore.colorOf(mapItem['category'].toString());

      final startTimeStr = mapItem['start_time']?.toString() ?? '07:00:00';
      final endTimeStr = mapItem['end_time']?.toString() ?? '09:00:00';

      final startParts = startTimeStr.split(':');
      final endParts = endTimeStr.split(':');

      final startHour = int.parse(startParts[0]);
      final startMinute = int.parse(startParts[1]);
      int endHour = int.parse(endParts[0]);
      int endMinute = int.parse(endParts[1]);

      final startDate = DateTime(year - 1, 12, 1);
      final endDate = DateTime(year + 1, 1, 31);

      for (DateTime d = startDate;
          !d.isAfter(endDate);
          d = d.add(const Duration(days: 1))) {
        if (ScheduleRecurrence.occursOn(mapItem, d)) {
          var startTime =
              DateTime(d.year, d.month, d.day, startHour, startMinute);
          var endTime = DateTime(d.year, d.month, d.day, endHour, endMinute);

          if (endTime.isBefore(startTime) ||
              endTime.isAtSameMomentAs(startTime)) {
            endTime = startTime.add(const Duration(hours: 2));
          }

          events.add(
            CalendarEventData(
              title: subjectName,
              date: d,
              startTime: startTime,
              endTime: endTime,
              color: subjectColor,
              description:
                  'Phòng: $room\nThời gian: $startTimeStr - $endTimeStr${_extraDescription(mapItem)}',
              event: mapItem,
            ),
          );
        }
      }
    }

    for (var item in _examRows) {
      var mapItem = Map<String, dynamic>.from(item);
      mapItem['is_exam'] = true;

      final subject = mapItem['subjects'] ?? {};
      final subjectName = 'Kiểm tra: ${subject['subject_name'] ?? 'Môn học'}';
      final room = mapItem['room'] ?? 'Chưa có phòng';

      DateTime examDate = DateTime.parse(mapItem['exam_date']);
      if (examDate.isBefore(DateTime(year - 1, 12, 1)) ||
          examDate.isAfter(DateTime(year + 1, 1, 31))) {
        continue;
      }
      final startTimeStr = mapItem['start_time'].toString();
      final endTimeStr = mapItem['end_time'].toString();

      final startParts = startTimeStr.split(':');
      final endParts = endTimeStr.split(':');

      var startTime = DateTime(examDate.year, examDate.month, examDate.day,
          int.parse(startParts[0]), int.parse(startParts[1]));
      var endTime = DateTime(examDate.year, examDate.month, examDate.day,
          int.parse(endParts[0]), int.parse(endParts[1]));

      events.add(
        CalendarEventData(
          title: subjectName,
          date: examDate,
          startTime: startTime,
          endTime: endTime,
          color: (mapItem['category']?.toString() ?? '').isEmpty
              ? Colors.orange
              : _categoryStore.colorOf(mapItem['category'].toString()),
          description:
              'Phòng thi: $room\nThời gian: $startTimeStr - $endTimeStr${_extraDescription(mapItem)}',
          event: mapItem,
        ),
      );
    }

    return events;
  }

  String _extraDescription(Map<String, dynamic> item) {
    final category = item['category']?.toString() ?? '';
    final notes = item['notes']?.toString() ?? '';
    return '${category.isEmpty ? '' : '\n$category'}${notes.isEmpty ? '' : '\nGhi chú: $notes'}';
  }

  List<CalendarEventData<Map<String, dynamic>>> _searchEvents() {
    final result = _eventController.allEvents.toList();
    final present = result.map((event) => event.event?['id']).toSet();
    final years = <int>{};
    for (final raw in _scheduleRows) {
      final row = Map<String, dynamic>.from(raw);
      if (present.contains(row['id'])) continue;
      final start = ScheduleRecurrence.date(row['start_date']) ?? _selectedDate;
      final end =
          ScheduleRecurrence.date(row['end_date']) ?? DateTime(2100, 12, 31);
      final dates = ScheduleRecurrence.between(row, start, end);
      if (dates.isNotEmpty) years.add(dates.first.year);
    }
    for (final row in _examRows) {
      if (!present.contains(row['id'])) {
        years.add(DateTime.parse(row['exam_date']).year);
      }
    }
    for (final year in years) {
      for (final event in _buildEvents(year)) {
        if (present.add(event.event?['id'])) result.add(event);
      }
    }
    return result;
  }

  Future<void> _searchLessons() async {
    final event = await showSearch<CalendarEventData<Map<String, dynamic>>?>(
        context: context, delegate: LessonSearch(_searchEvents()));
    if (event == null || !mounted) return;
    await _selectDate(event.date);
    if (!mounted) return;
  }

  Future<void> _chooseEventType() async {
    final type = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final entry in {
                'lesson': 'Lịch học',
                'exam': 'Lịch thi',
                'study': 'Tự học / Công việc',
                'import': 'Nhập ảnh / PDF'
              }.entries)
                ListTile(
                    title: Text(entry.value),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(c, entry.key)),
            ])));
    if (!mounted || type == null) return;
    if (type == 'lesson' || type == 'exam') {
      await _editLesson(null, type == 'exam');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => type == 'import'
            ? const TimetableImportScreen()
            : const TasksScreen()));
    if (mounted) await _loadDataFromSupabase();
  }

  Future<void> _editLesson(
      [CalendarEventData<Map<String, dynamic>>? event,
      bool newExam = false]) async {
    final item = event?.event;
    final initial = event == null
        ? null
        : LessonDraft(
            title:
                (item?['subjects']?['subject_name'] ?? event.title).toString(),
            date: item?['is_exam'] == true
                ? event.date
                : ScheduleRecurrence.date(item?['start_date']) ?? event.date,
            recurrence:
                item == null ? 'none' : ScheduleRecurrence.frequency(item),
            repeatUntil:
                item == null || ScheduleRecurrence.frequency(item) == 'none'
                    ? null
                    : ScheduleRecurrence.date(item['end_date']),
            start: TimeOfDay.fromDateTime(event.startTime ?? event.date),
            end: TimeOfDay.fromDateTime(
                event.endTime ?? event.date.add(const Duration(hours: 1))),
            location: item?['room']?.toString() ?? '',
            notes: item?['notes']?.toString() ?? '',
            category: item?['category']?.toString() ?? '',
          );
    final saved = await showGeneralDialog<bool>(
      context: context,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _motionDuration,
      transitionBuilder: (context, animation, secondary, child) {
        final motion = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return FadeTransition(
            opacity: motion,
            child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(motion),
                child: child));
      },
      pageBuilder: (context, animation, secondary) => LessonEditor(
        dialogTitle: newExam
            ? 'Thêm lịch thi'
            : item?['is_exam'] == true
                ? 'Chỉnh sửa lịch thi'
                : null,
        initialDate: _selectedDate,
        initial: initial,
        manageRecurrence: !newExam && item?['is_exam'] != true,
        categoryStore: _categoryStore,
        onCategoriesChanged: _loadDataFromSupabase,
        recurring: item != null &&
            item['is_exam'] != true &&
            item['start_date'] != item['end_date'],
        beforeSave: (draft) => confirmCalendarConflicts(
            context, supabase, draft.toConflictRow(),
            excludeId: item?['id']?.toString(),
            isExam: newExam || item?['is_exam'] == true),
        onSave: (draft) async {
          if (supabase.auth.currentUser == null) {
            throw Exception('Vui lòng đăng nhập để lưu lịch học.');
          }
          try {
            if (newExam || item?['is_exam'] == true) {
              await supabase.rpc('save_calendar_lesson',
                  params: draft.toParameters(
                      id: item?['id']?.toString(),
                      isExam: true,
                      occurrenceDate: event?.date));
            } else {
              await supabase.rpc('save_subject_schedule',
                  params: draft.toSubjectParameters(
                      subjectId: item?['subject_id']?.toString(),
                      scheduleId: item?['id']?.toString()));
            }
          } on PostgrestException catch (error) {
            if (error.code == 'PGRST202' || error.code == '42703') {
              throw Exception(
                  'Chưa bật chức năng lưu lịch mới trên máy chủ. Vui lòng cập nhật cơ sở dữ liệu.');
            }
            throw Exception('Không lưu được lịch: ${error.message}');
          }
          if (mounted) setState(() => _selectedDate = draft.date);
        },
      ),
    );
    if (saved == true && mounted) {
      _view = _ScheduleView.day;
      await _loadDataFromSupabase();
      if (!mounted) return;
      AppNotice.show(context, const SnackBar(content: Text('Đã lưu lịch học')));
    }
  }

  void _showEventDetail(CalendarEventData<Map<String, dynamic>> event) {
    if (event.event?['is_study'] == true) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const TasksScreen()))
          .then((_) {
        if (mounted) _loadDataFromSupabase();
      });
      return;
    }
    final item = event.event;
    final subject = item?['subjects'] ?? {};
    final bool isExam = item?['is_exam'] ?? false;

    final subjectName = subject['subject_name'] ?? 'Môn học';
    final fullTitle = isExam ? 'Kiểm tra: $subjectName' : subjectName;
    final room = item?['room'] ?? 'Chưa cập nhật';
    final category = item?['category']?.toString() ?? '';
    final categoryColor = _categoryStore.colorOf(category);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _motionDuration,
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final motion = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return FadeTransition(
            opacity: motion,
            child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(motion),
                child: child));
      },
      pageBuilder: (context, animation, secondaryAnimation) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isExam ? Icons.assignment_turned_in : Icons.book,
                color: event.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fullTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isExam ? Colors.orange.shade800 : Colors.black,
                ),
              ),
            ),
            if (category.isNotEmpty) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Container(
                  key: const ValueKey('lesson-detail-category'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(category,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface)),
                ),
              ),
            ],
          ],
        ),
        content: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(
                Icons.code, 'Mã môn học:', subject['subject_code'] ?? 'N/A'),
            const SizedBox(height: 10),
            _buildDetailRow(
                Icons.room, isExam ? 'Phòng thi:' : 'Phòng học:', room),
            const SizedBox(height: 10),
            if ((item?['notes']?.toString() ?? '').isNotEmpty) ...[
              _buildDetailRow(
                  Icons.notes, 'Ghi chú:', item!['notes'].toString()),
              const SizedBox(height: 10),
            ],
            _buildDetailRow(
              Icons.access_time,
              isExam ? 'Thời gian thi:' : 'Thời gian:',
              isExam
                  ? '${DateFormat('dd/MM/yyyy').format(event.date)} (${item?['start_time']} - ${item?['end_time']})'
                  : '${item?['start_time']} - ${item?['end_time']}',
            ),
          ],
        )),
        actions: [
          TextButton.icon(
            key: const ValueKey('lesson-delete'),
            onPressed: item?['id'] == null
                ? null
                : () {
                    Navigator.pop(context);
                    _deleteEvent(event);
                  },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xóa'),
          ),
          TextButton.icon(
            key: const ValueKey('lesson-edit'),
            onPressed: item?['id'] == null
                ? null
                : () {
                    Navigator.pop(context);
                    _editLesson(event);
                  },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Chỉnh sửa'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 20,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black),
        const SizedBox(width: 8),
        Text('$label ',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black)),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black))),
      ],
    );
  }

  String _fmt(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _transitionTo(VoidCallback update) async {
    if (_isTransitioning) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(update);
      _ensureVisibleEvents();
      return;
    }
    setState(() => _isTransitioning = true);
    try {
      await _viewTransition.forward().orCancel;
      if (!mounted) return;
      setState(update);
      _ensureVisibleEvents();
      await _viewTransition.reverse().orCancel;
    } on TickerCanceled {
      // Leaving the screen cancels its transition.
    } finally {
      if (mounted) setState(() => _isTransitioning = false);
    }
  }

  Widget _buildTransition(Widget child) {
    return IgnorePointer(
      ignoring: _isTransitioning,
      child: AnimatedBuilder(
        animation: _viewTransition,
        child: child,
        builder: (context, child) {
          final progress =
              Curves.easeInOutCubic.transform(_viewTransition.value);
          return Opacity(
            key: const ValueKey('schedule-transition-opacity'),
            opacity: 1 - progress,
            child: Transform.scale(
              key: const ValueKey('schedule-transition-scale'),
              scale: 1 - 0.06 * progress,
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _selectDate(DateTime date) => _transitionTo(() {
        _selectedDate = DateTime(date.year, date.month, date.day);
        _browseDate = _selectedDate;
        _view = _ScheduleView.day;
      });

  void _changePeriod(int direction) {
    _transitionTo(() {
      _browseDate = _view == _ScheduleView.year
          ? DateTime(_browseDate.year + direction)
          : DateTime(_browseDate.year, _browseDate.month + direction);
    });
  }

  Widget _buildNavigation() {
    final isDay = _view == _ScheduleView.day;
    final title = isDay
        ? 'Tháng ${_selectedDate.month}, ${_selectedDate.year}'
        : '${_browseDate.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft),
                        key: const ValueKey('schedule-browse'),
                        icon: const Icon(Icons.chevron_left),
                        label: Text(title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () => _transitionTo(() {
                          if (isDay) {
                            _browseDate = DateTime(
                                _selectedDate.year, _selectedDate.month);
                            _view = _ScheduleView.month;
                          } else if (_view == _ScheduleView.month) {
                            _view = _ScheduleView.year;
                          } else {
                            _view = _ScheduleView.month;
                          }
                        }),
                      )))),
          TextButton(
            key: const ValueKey('schedule-today'),
            onPressed: () => _selectDate(DateTime.now()),
            child: const Text('Hôm nay'),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekStrip() {
    final start = DateTime(_selectedDate.year, _selectedDate.month,
        _selectedDate.day - _selectedDate.weekday + 1);
    final end = DateTime(start.year, start.month, start.day + 6);
    final colors = Theme.of(context).colorScheme;
    final today = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('schedule-range-header'),
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            IconButton(
              tooltip: 'Ngày trước',
              onPressed: _selectedDate.isAfter(DateTime(2020))
                  ? () => _selectDate(DateTime(_selectedDate.year,
                      _selectedDate.month, _selectedDate.day - 1))
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
                child: Text(
              'Từ ngày ${_fmt(start)} đến ngày ${_fmt(end)}',
              key: const ValueKey('schedule-week-range'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface),
            )),
            IconButton(
              tooltip: 'Ngày sau',
              onPressed: _selectedDate.isBefore(DateTime(2100, 12, 31))
                  ? () => _selectDate(DateTime(_selectedDate.year,
                      _selectedDate.month, _selectedDate.day + 1))
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
        ),
        Container(
            key: const ValueKey('schedule-week-strip'),
            decoration: BoxDecoration(
                border: Border(
                    bottom:
                        BorderSide(color: colors.outlineVariant, width: 1))),
            child: Row(children: [
              for (var index = 0; index < 7; index++)
                Expanded(child: Builder(builder: (context) {
                  final date =
                      DateTime(start.year, start.month, start.day + index);
                  final selected = _sameDate(date, _selectedDate);
                  final isToday = _sameDate(date, today);
                  final enabled = !date.isBefore(DateTime(2020)) &&
                      !date.isAfter(DateTime(2100, 12, 31));
                  final accent = isToday ? Colors.red : colors.primary;
                  return InkWell(
                    key: ValueKey(
                        'schedule-week-day-${date.year}-${date.month}-${date.day}'),
                    borderRadius: BorderRadius.circular(24),
                    onTap: enabled ? () => _selectDate(date) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        Text(
                            const [
                              'T2',
                              'T3',
                              'T4',
                              'T5',
                              'T6',
                              'T7',
                              'CN'
                            ][index],
                            style: TextStyle(
                                fontSize: 12, color: colors.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Container(
                          key: selected
                              ? const ValueKey('schedule-selected-week-day')
                              : null,
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: accent, width: 2)
                                : null,
                            color:
                                selected ? accent.withValues(alpha: 0.1) : null,
                          ),
                          child: Text('${date.day}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected || isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: !enabled
                                    ? colors.onSurface.withValues(alpha: 0.3)
                                    : selected || isToday
                                        ? accent
                                        : colors.onSurface,
                              )),
                        ),
                      ]),
                    ),
                  );
                })),
            ])),
      ],
    );
  }

  Widget _buildPeriodHeader() {
    final isYear = _view == _ScheduleView.year;
    final previous =
        isYear ? _browseDate.year > 2020 : _browseDate.isAfter(DateTime(2020));
    final next = isYear
        ? _browseDate.year < 2100
        : _browseDate.isBefore(DateTime(2100, 12));
    return Row(
      children: [
        IconButton(
          tooltip: isYear ? 'Năm trước' : 'Tháng trước',
          onPressed: previous ? () => _changePeriod(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            isYear ? 'Năm ${_browseDate.year}' : 'Tháng ${_browseDate.month}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: isYear ? 'Năm sau' : 'Tháng sau',
          onPressed: next ? () => _changePeriod(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildMonthGrid(DateTime month, {bool miniature = false}) {
    final colors = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month);
    final offset = first.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final cells = miniature ? 42 : ((offset + count + 6) ~/ 7) * 7;
    final today = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final label in ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'])
              Expanded(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: miniature ? 9 : 13,
                          color: colors.onSurfaceVariant))),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
          ),
          itemCount: cells,
          itemBuilder: (context, index) {
            final number = index - offset + 1;
            if (number < 1 || number > count) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, number);
            final selected = _sameDate(date, _selectedDate);
            final isToday = _sameDate(date, today);
            final hasEvents =
                !miniature && _eventController.getEventsOnDay(date).isNotEmpty;
            final content = Center(
              child: Container(
                width: miniature ? 18 : 38,
                height: miniature ? 18 : 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isToday
                      ? Colors.red
                      : selected && !miniature
                          ? colors.primaryContainer
                          : null,
                ),
                child: Text('$number',
                    style: TextStyle(
                      fontSize: miniature ? 9 : 17,
                      fontWeight: isToday || selected ? FontWeight.bold : null,
                      color: isToday ? Colors.white : null,
                    )),
              ),
            );
            if (miniature) return content;
            return InkWell(
              key: ValueKey(
                  'schedule-date-${date.year}-${date.month}-${date.day}'),
              borderRadius: BorderRadius.circular(24),
              onTap: () => _selectDate(date),
              child: Stack(alignment: Alignment.center, children: [
                content,
                if (hasEvents)
                  Positioned(
                      bottom: 2,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                            color: colors.primary, shape: BoxShape.circle),
                      )),
              ]),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDateBrowser() {
    final isYear = _view == _ScheduleView.year;
    return SingleChildScrollView(
      key: ValueKey(isYear ? 'schedule-year' : 'schedule-month'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Center(
          child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isYear ? 760 : 560),
        child: Column(children: [
          _buildPeriodHeader(),
          const SizedBox(height: 20),
          if (isYear)
            LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth < 340 ? 2 : 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                        mainAxisExtent: ((constraints.maxWidth -
                                        (constraints.maxWidth < 340
                                            ? 12
                                            : 24)) /
                                    (constraints.maxWidth < 340 ? 2 : 3)) *
                                6 /
                                7 +
                            90,
                      ),
                      itemCount: 12,
                      itemBuilder: (context, index) {
                        final month = DateTime(_browseDate.year, index + 1);
                        return InkWell(
                          key: ValueKey('schedule-month-${index + 1}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _transitionTo(() {
                            _browseDate = month;
                            _view = _ScheduleView.month;
                          }),
                          child: Column(children: [
                            Text('Tháng ${index + 1}',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            IgnorePointer(
                                child: _buildMonthGrid(month, miniature: true)),
                          ]),
                        );
                      },
                    ))
          else ...[
            _buildMonthGrid(_browseDate),
            const SizedBox(height: 24),
            Text('Chọn ngày để xem lịch học',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ]),
      )),
    );
  }

  Widget _buildAgenda() {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _eventController,
      builder: (context, _) {
        final events = _eventController.getEventsOnDay(_selectedDate).toList()
          ..sort((a, b) =>
              (a.startTime ?? a.date).compareTo(b.startTime ?? b.date));
        return ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(dragDevices: const {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.trackpad,
          }),
          child: ListView(
            key: const ValueKey('schedule-agenda'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              Text('Ngày ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                  key: const ValueKey('schedule-selected-date'),
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              if (events.isEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(children: [
                      Icon(Icons.event_available_outlined,
                          size: 32, color: colors.primary),
                      const SizedBox(height: 12),
                      const Text('Ngày này chưa có lịch trình',
                          textAlign: TextAlign.center),
                    ])),
              for (final event in events) ...[
                _buildAgendaEvent(event),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAgendaEvent(CalendarEventData<Map<String, dynamic>> event) {
    final colors = Theme.of(context).colorScheme;
    final item = event.event ?? <String, dynamic>{};
    final category = item['category']?.toString().trim() ?? '';
    final isExam = item['is_exam'] == true;
    final isStudy = item['is_study'] == true;
    final label = category.isNotEmpty
        ? category
        : isExam
            ? 'Lịch thi'
            : isStudy
                ? 'Tự học'
                : 'Lịch học';
    final accent =
        category.isNotEmpty ? _categoryStore.colorOf(category) : event.color;
    final subject = item['subjects'];
    final title = subject is Map
        ? subject['subject_name']?.toString() ?? event.title
        : event.title;
    final room = item['room']?.toString().trim() ?? '';
    final notes = item['notes']?.toString().trim() ?? '';
    String time(DateTime? value) =>
        value == null ? '—' : DateFormat('HH:mm').format(value);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          width: 48,
          child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(time(event.startTime),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(time(event.endTime),
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  ]))),
      const SizedBox(width: 10),
      Expanded(
          child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side:
                BorderSide(color: colors.outlineVariant.withValues(alpha: .6))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showEventDetail(event),
          child: IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(4)))),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: accent,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(title,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              if (room.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(room,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: colors.onSurfaceVariant)),
                              ],
                              if (notes.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(notes,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: colors.onSurfaceVariant)),
                              ],
                            ]))),
              ])),
        ),
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return CalendarControllerProvider(
      controller: _eventController,
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF11131D)
            : const Color(0xFFF5F6FB),
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          backgroundColor: Colors.transparent,
          title: const Text('Lịch của bạn',
              style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
                key: const ValueKey('schedule-search'),
                tooltip: 'Tìm môn học',
                onPressed: _isLoading ? null : _searchLessons,
                icon: const Icon(Icons.search)),
            IconButton(
                tooltip: 'Tải lại lịch',
                onPressed: _loadDataFromSupabase,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 12),
                                  child: Text(
                                      'Lịch học và lịch thi trong cùng một nơi.',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 13))),
                              _buildNavigation(),
                              if (_view == _ScheduleView.day) _buildWeekStrip(),
                              Expanded(
                                  child: _buildTransition(
                                      _view == _ScheduleView.day
                                          ? _buildAgenda()
                                          : _buildDateBrowser())),
                              if (_view == _ScheduleView.day)
                                Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 8, 20, 16),
                                    child: FilledButton.icon(
                                        key: const ValueKey('schedule-add'),
                                        style: FilledButton.styleFrom(
                                            minimumSize:
                                                const Size.fromHeight(52),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(18))),
                                        onPressed: _chooseEventType,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Thêm lịch học'))),
                            ])))),
      ),
    );
  }
}
