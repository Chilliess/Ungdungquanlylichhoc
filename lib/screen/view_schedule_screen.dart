import 'package:untitled/widgets/app_notice.dart';
import '../models/schedule_recurrence.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:intl/intl.dart';
import 'lesson_editor.dart';
import 'lesson_categories.dart';
import 'lesson_event_tile.dart';
import 'lesson_search.dart';

enum _ScheduleView { day, month, year }

class ViewScheduleScreen extends StatefulWidget {
  const ViewScheduleScreen(
      {super.key, this.openEditorOnStart = false, this.initialDate});
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
    if (_renderedYear != null && _renderedYear != year && mounted)
      _populateEvents(year);
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
  final GlobalKey<DayViewState<Map<String, dynamic>>> _dayViewKey =
      GlobalKey<DayViewState<Map<String, dynamic>>>();
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
    _loadDataFromSupabase();
    if (widget.openEditorOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editLesson();
      });
    }
  }

  @override
  void dispose() {
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
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      try {
        await _categoryStore.load();
      } catch (_) {
        // Calendars remain readable while the optional category update is pending.
      }
      final scheduleRes = await supabase
          .from('schedules')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId);

      final examRes = await supabase
          .from('schedule_exams')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId);

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
    }

    if (mounted && version == _loadVersion) {
      setState(() => _isLoading = false);
    }
  }

  void _populateEvents(int year) {
    _renderedYear = year;
    final events = _buildEvents(year);
    _eventController.removeWhere((element) => true);
    _eventController.addAll(events);
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
    final start = event.startTime;
    if (start != null) {
      _dayViewKey.currentState?.animateToDuration(Duration(
          minutes: (start.hour * 60 + start.minute - 30).clamp(0, 1439)));
    }
  }

  Future<void> _editLesson(
      [CalendarEventData<Map<String, dynamic>>? event]) async {
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
        initialDate: _selectedDate,
        initial: initial,
        manageRecurrence: item?['is_exam'] != true,
        categoryStore: _categoryStore,
        onCategoriesChanged: _loadDataFromSupabase,
        recurring: item != null &&
            item['is_exam'] != true &&
            item['start_date'] != item['end_date'],
        onSave: (draft) async {
          if (supabase.auth.currentUser == null) {
            throw Exception('Vui lòng đăng nhập để lưu lịch học.');
          }
          try {
            if (item?['is_exam'] == true) {
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
      _dayViewKey.currentState?.jumpToDate(_selectedDate);
      AppNotice.show(context, const SnackBar(content: Text('Đã lưu lịch học')));
    }
  }

  void _showEventDetail(CalendarEventData<Map<String, dynamic>> event) {
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
        _dayViewKey.currentState?.jumpToDate(date);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey('schedule-range-header'),
          constraints: const BoxConstraints(minHeight: 56),
          color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFE3F2FD),
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
                  color: isDark ? Colors.white : Colors.blue.shade900),
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

  static const _timeLabelStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.normal,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _buildTimeLineMark(DateTime date) {
    final now = DateTime.now();
    final isToday = _sameDate(_selectedDate, now);
    final isExactHour = now.minute == 0;
    final activeStyle = _timeLabelStyle.copyWith(color: Colors.red);
    // Keep the live label clear of the fixed hour labels near an hour boundary.
    final liveMinuteOffset = now.minute <= 15
        ? 18.0
        : now.minute >= 45
            ? 36.0
            : now.minute - 7.5;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -7.5,
          left: 0,
          right: 0,
          child: Text(
            DateFormat('HH:mm').format(date),
            textAlign: TextAlign.center,
            style: isToday && isExactHour && date.hour == now.hour
                ? activeStyle
                : _timeLabelStyle,
          ),
        ),
        // The calendar package starts its labels at 01:00.
        if (date.hour == 1 && date.minute == 0) ...[
          Positioned(
            top: -60.0 + 2,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Text(
                '00:00',
                key: const ValueKey('schedule-midnight-label'),
                textAlign: TextAlign.center,
                style: isToday && isExactHour && now.hour == 0
                    ? activeStyle
                    : _timeLabelStyle,
              ),
            ),
          ),
          if (isToday && !isExactHour)
            Positioned(
              top: (now.hour - 1) * 60.0 + liveMinuteOffset,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(
                  DateFormat('HH:mm').format(now),
                  key: const ValueKey('schedule-live-time-label'),
                  textAlign: TextAlign.center,
                  style: activeStyle,
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CalendarControllerProvider(
      controller: _eventController,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lịch học & kiểm tra',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          titleTextStyle: Theme.of(context).textTheme.titleMedium,
          actions: [
            IconButton(
                key: const ValueKey('schedule-search'),
                tooltip: 'Tìm môn học',
                onPressed: _isLoading ? null : _searchLessons,
                icon: const Icon(Icons.search)),
            IconButton(
                key: const ValueKey('schedule-add'),
                tooltip: 'Thêm lịch học',
                onPressed: _isLoading ? null : () => _editLesson(),
                icon: const Icon(Icons.add)),
            IconButton(
              tooltip: 'Tải lại lịch',
              icon: const Icon(Icons.refresh),
              onPressed: _loadDataFromSupabase,
            )
          ],
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  _buildNavigation(),
                  Expanded(
                    child: _buildTransition(_view != _ScheduleView.day
                        ? _buildDateBrowser()
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ScrollConfiguration(
                                behavior:
                                    const MaterialScrollBehavior().copyWith(
                                  dragDevices: const {
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.stylus,
                                    PointerDeviceKind.trackpad,
                                  },
                                ),
                                child: DayView<Map<String, dynamic>>(
                                  key: _dayViewKey,
                                  controller: _eventController,
                                  initialDay: _selectedDate,
                                  minDay: DateTime(2020),
                                  maxDay: DateTime(2100, 12, 31),
                                  heightPerMinute: 1,
                                  timeLineWidth: 60,
                                  verticalLineOffset: 0,
                                  timeLineBuilder: _buildTimeLineMark,
                                  eventTileBuilder:
                                      (date, events, boundary, start, end) =>
                                          LessonEventTile(
                                              event: events.first,
                                              eventCount: events.length),
                                  onPageChange: (date, _) => setState(() {
                                    _selectedDate = date;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (mounted) _ensureVisibleEvents();
                                    });
                                  }),
                                  dayTitleBuilder: (_) => _buildWeekStrip(),
                                  onEventTap: (events, date) {
                                    if (events.isNotEmpty) {
                                      _showEventDetail(events.first);
                                    }
                                  },
                                  backgroundColor: isDark
                                      ? const Color(0xFF121212)
                                      : Colors.white,
                                  headerStyle: HeaderStyle(
                                    decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1F1F1F)
                                            : const Color(0xFFE3F2FD)),
                                    headerTextStyle: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.blue.shade900),
                                  ),
                                  hourIndicatorSettings: HourIndicatorSettings(
                                    color: isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade300,
                                    height: 1,
                                    lineStyle: LineStyle.dashed,
                                  ),
                                  liveTimeIndicatorSettings:
                                      const LiveTimeIndicatorSettings(
                                    color: Colors.red,
                                    showTime: false,
                                  ),
                                ),
                              ),
                            ),
                          )),
                  ),
                ]),
        ),
      ),
    );
  }
}
