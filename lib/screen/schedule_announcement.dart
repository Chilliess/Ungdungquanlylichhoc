import '../services/study_data.dart';
import 'package:untitled/widgets/app_notice.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'lesson_categories.dart';
import 'confirm_action.dart';
import '../models/schedule_recurrence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

/// Màn hình thiết lập nhắc nhở lịch học và lịch kiểm tra.
class ScheduleAnnouncementScreen extends StatefulWidget {
  const ScheduleAnnouncementScreen({super.key});

  @override
  State<ScheduleAnnouncementScreen> createState() =>
      _ScheduleAnnouncementScreenState();
}

class _ScheduleAnnouncementScreenState extends State<ScheduleAnnouncementScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  late TabController _tabController;

  final List<int> _reminderOptions = const [5, 10, 15, 30, 60, 120];
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _exams = [];

  List<Map<String, dynamic>> _filteredSchedules = [];
  List<Map<String, dynamic>> _filteredExams = [];

  Map<String, Map<String, dynamic>> _remindersBySchedule = {};
  Map<String, Map<String, dynamic>> _remindersByExam = {};

  final TextEditingController _scheduleSearchController =
      TextEditingController();
  final TextEditingController _examSearchController = TextEditingController();

  int _defaultMinutes = 15;
  bool _alarmMode = false;
  bool get _supportsAlarm =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  int _defaultVersion = 0;
  bool? _permissionGranted;
  String? _notificationNotice;
  late final _categoryStore = SupabaseLessonCategoryStore(_supabase);
  bool get _mobile =>
      !const bool.fromEnvironment('dart.library.js_interop') &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool _loading = true;
  bool _saving = false;
  bool _notificationsInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });

    _scheduleSearchController.addListener(_onScheduleSearchChanged);
    _examSearchController.addListener(_onExamSearchChanged);

    _loadScreen();
  }

  @override
  void dispose() {
    _categoryStore.dispose();
    _tabController.dispose();
    _scheduleSearchController.dispose();
    _examSearchController.dispose();
    super.dispose();
  }

  void _onScheduleSearchChanged() {
    final keyword = _scheduleSearchController.text.toLowerCase().trim();
    setState(() {
      if (keyword.isEmpty) {
        _filteredSchedules = List.from(_schedules);
      } else {
        _filteredSchedules = _schedules.where((schedule) {
          final subject = schedule['subjects'] is Map
              ? Map<String, dynamic>.from(schedule['subjects'] as Map)
              : <String, dynamic>{};
          final name = (subject['subject_name'] ?? '').toString().toLowerCase();
          final code = (subject['subject_code'] ?? '').toString().toLowerCase();
          final room = (schedule['room'] ?? '').toString().toLowerCase();
          return name.contains(keyword) ||
              code.contains(keyword) ||
              room.contains(keyword);
        }).toList();
      }
    });
  }

  void _onExamSearchChanged() {
    final keyword = _examSearchController.text.toLowerCase().trim();
    setState(() {
      if (keyword.isEmpty) {
        _filteredExams = List.from(_exams);
      } else {
        _filteredExams = _exams.where((exam) {
          final subject = exam['subjects'] is Map
              ? Map<String, dynamic>.from(exam['subjects'] as Map)
              : <String, dynamic>{};
          final name = (subject['subject_name'] ?? '').toString().toLowerCase();
          final code = (subject['subject_code'] ?? '').toString().toLowerCase();
          final room = (exam['room'] ?? '').toString().toLowerCase();
          final supervisor =
              (exam['supervisor'] ?? '').toString().toLowerCase();
          return name.contains(keyword) ||
              code.contains(keyword) ||
              room.contains(keyword) ||
              supervisor.contains(keyword);
        }).toList();
      }
    });
  }

  Future<void> _loadScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _alarmMode = _supportsAlarm &&
          (prefs.getBool('alarm_mode_${_supabase.auth.currentUser?.id}') ??
              false);
      _defaultMinutes =
          prefs.getInt('reminder_default_${_supabase.auth.currentUser?.id}') ??
              15;
      try {
        await _initializeNotifications();
      } catch (_) {
        _notificationNotice = 'Chưa thể bật thông báo trên thiết bị này.';
      }
      try {
        await _categoryStore.load();
      } catch (_) {}
      await _loadData();
      await _rescheduleAllEnabledReminders();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Không thể khởi tạo nhắc nhở: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _initializeNotifications() async {
    if (_notificationsInitialized) return;
    if (!_mobile) {
      _notificationNotice =
          'Thông báo trên thiết bị hiện hỗ trợ Android và iOS.';
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notifications.initialize(settings);

    tz_data.initializeTimeZones();
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));

    await _requestPermission();

    _notificationsInitialized = true;
  }

  Future<void> _requestPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    _permissionGranted = await android?.requestNotificationsPermission() ??
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
    if (mounted) setState(() {});
    if (_notificationsInitialized && _permissionGranted == true) {
      await _rescheduleAllEnabledReminders();
    }
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Bạn cần đăng nhập để thiết lập nhắc nhở.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Tải lịch học từ bảng schedules
      final scheduleResponse =
          await loadOwnedStudyRows(_supabase, 'schedules', userId);

      // Tải lịch kiểm tra từ bảng schedule_exams
      final examResponse =
          await loadOwnedStudyRows(_supabase, 'schedule_exams', userId);

      // Tải tất cả nhắc nhở từ bảng reminders chung
      final reminderResponse =
          await _supabase.from('reminders').select().eq('user_id', userId);

      final schedules =
          List<Map<String, dynamic>>.from(scheduleResponse as List);
      final exams = List<Map<String, dynamic>>.from(examResponse as List);
      final reminders =
          List<Map<String, dynamic>>.from(reminderResponse as List);

      final reminderMap = <String, Map<String, dynamic>>{};
      final examReminderMap = <String, Map<String, dynamic>>{};

      for (final reminder in reminders) {
        final targetId = reminder['schedule_id']?.toString();
        final type = reminder['schedule_type']?.toString() ?? 'schedule';

        if (targetId != null) {
          if (type == 'exam') {
            examReminderMap[targetId] = reminder;
          } else {
            reminderMap[targetId] = reminder;
          }
        }
      }

      if (mounted) {
        setState(() {
          _schedules = schedules;
          _exams = exams;
          _filteredSchedules = List.from(_schedules);
          _filteredExams = List.from(_exams);
          _remindersBySchedule = reminderMap;
          _remindersByExam = examReminderMap;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Lỗi tải dữ liệu từ Supabase: $e';
        });
      }
    }
  }

  int _minutesFor(Map<String, dynamic> item, {bool isExam = false}) {
    final reminderMap = isExam ? _remindersByExam : _remindersBySchedule;
    final reminder = reminderMap[item['id'].toString()];
    final value = int.tryParse(
      reminder?['remind_before_minutes']?.toString() ?? '',
    );
    return _reminderOptions.contains(value) ? value! : _defaultMinutes;
  }

  bool _isEnabled(Map<String, dynamic> item, {bool isExam = false}) {
    final reminderMap = isExam ? _remindersByExam : _remindersBySchedule;
    final reminder = reminderMap[item['id'].toString()];
    return reminder?['is_enabled'] == true;
  }

  Future<void> _saveReminder(
    Map<String, dynamic> item, {
    required int minutes,
    required bool enabled,
    required bool isExam,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || _saving) return;

    setState(() => _saving = true);
    try {
      if (!await confirmAction(context,
              message: enabled
                  ? 'Bật nhắc trước $minutes phút cho lịch này và các buổi lặp của nó?'
                  : 'Tắt nhắc nhở cho lịch này?') ||
          !mounted) {
        return;
      }
      final itemId = item['id'].toString();
      final reminderMap = isExam ? _remindersByExam : _remindersBySchedule;
      final existing = reminderMap[itemId];

      final data = <String, dynamic>{
        'user_id': userId,
        'schedule_id': itemId,
        'schedule_type': isExam ? 'exam' : 'schedule',
        'remind_before_minutes': minutes,
        'is_enabled': enabled,
      };

      if (existing != null && existing['id'] != null) {
        await _supabase
            .from('reminders')
            .update(data)
            .eq('id', existing['id'].toString())
            .eq('user_id', userId);
      } else {
        final inserted =
            await _supabase.from('reminders').insert(data).select().single();
        reminderMap[itemId] = Map<String, dynamic>.from(inserted);
      }

      await _loadData();
      await _rescheduleAllEnabledReminders();

      if (mounted) {
        AppNotice.show(
          context,
          SnackBar(
            content: Text(
              enabled
                  ? 'Đã bật nhắc nhở trước $minutes phút.'
                  : 'Đã tắt nhắc nhở.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppNotice.show(
          context,
          SnackBar(content: Text('Không thể lưu nhắc nhở: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _notificationId(String id, DateTime date) {
    final input = '$id-${date.year}-${date.month}-${date.day}';
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  List<int> _parseDays(dynamic rawDays) {
    final values = rawDays is List ? rawDays : [rawDays];
    return values
        .map((value) => int.tryParse(value.toString()))
        .whereType<int>()
        .where((day) => day >= 2 && day <= 8)
        .toSet()
        .toList();
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  TimeOfDay? _parseTime(dynamic value) {
    if (value == null) return null;
    final parts = value.toString().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _rescheduleAllEnabledReminders() async {
    if (!_notificationsInitialized || _permissionGranted == false) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _notifications.cancelAll();

    final now = tz.TZDateTime.now(tz.local);
    final candidates = <_PendingReminder>[];

    // 1. Xử lý thông báo cho Lịch học
    for (final schedule in _schedules) {
      final scheduleId = schedule['id']?.toString();
      if (scheduleId == null) continue;

      final reminder = _remindersBySchedule[scheduleId];
      if (reminder == null || reminder['is_enabled'] != true) continue;

      final startTime = _parseTime(schedule['start_time']);
      if (startTime == null) continue;

      final minutes =
          int.tryParse(reminder['remind_before_minutes']?.toString() ?? '') ??
              15;
      final subject = schedule['subjects'] is Map
          ? Map<String, dynamic>.from(schedule['subjects'] as Map)
          : <String, dynamic>{};
      final subjectName = subject['subject_name']?.toString() ?? 'Môn học';

      for (var offset = 0; offset < 30; offset++) {
        final date =
            DateTime(now.year, now.month, now.day).add(Duration(days: offset));
        if (!ScheduleRecurrence.occursOn(schedule, date)) continue;

        final classStart = tz.TZDateTime(tz.local, date.year, date.month,
            date.day, startTime.hour, startTime.minute);
        final notifyAt = classStart.subtract(Duration(minutes: minutes));
        if (!notifyAt.isAfter(now)) continue;

        candidates.add(
          _PendingReminder(
            id: _notificationId(scheduleId, date),
            title: 'Sắp đến giờ học: $subjectName',
            body:
                'Bắt đầu lúc ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}. Còn $minutes phút nữa.',
            scheduledDate: notifyAt,
          ),
        );
      }
    }

    // 2. Xử lý thông báo cho Lịch kiểm tra
    for (final exam in _exams) {
      final examId = exam['id']?.toString();
      if (examId == null) continue;

      final reminder = _remindersByExam[examId];
      if (reminder == null || reminder['is_enabled'] != true) continue;

      final startTime = _parseTime(exam['start_time']);
      final examDate = _parseDate(exam['exam_date']);
      if (startTime == null || examDate == null) continue;

      final minutes =
          int.tryParse(reminder['remind_before_minutes']?.toString() ?? '') ??
              15;
      final subject = exam['subjects'] is Map
          ? Map<String, dynamic>.from(exam['subjects'] as Map)
          : <String, dynamic>{};
      final subjectName = subject['subject_name']?.toString() ?? 'Môn học';

      final examStart = tz.TZDateTime(tz.local, examDate.year, examDate.month,
          examDate.day, startTime.hour, startTime.minute);
      final notifyAt = examStart.subtract(Duration(minutes: minutes));
      if (!notifyAt.isAfter(now)) continue;

      candidates.add(
        _PendingReminder(
          id: _notificationId(examId, examDate),
          title: 'Sắp đến giờ kiểm tra: $subjectName',
          body:
              'Bắt đầu lúc ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}. Còn $minutes phút nữa.',
          scheduledDate: notifyAt,
        ),
      );
    }

    candidates.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final limited = candidates.take(50);

    final details = _notificationDetails();

    for (final item in limited) {
      await _notifications.zonedSchedule(
        item.id,
        item.title,
        item.body,
        item.scheduledDate,
        details,
        androidScheduleMode: _alarmMode
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: item.id.toString(),
      );
    }
  }

  NotificationDetails _notificationDetails() => NotificationDetails(
        android: AndroidNotificationDetails(
          _alarmMode ? 'study_alarms_v1' : 'schedule_reminders',
          _alarmMode ? 'Báo thức học tập' : 'Nhắc nhở lịch',
          channelDescription: 'Thông báo trước giờ bắt đầu',
          importance: Importance.max,
          priority: Priority.high,
          category: _alarmMode
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.reminder,
          audioAttributesUsage: _alarmMode
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          additionalFlags: _alarmMode ? Int32List.fromList([4]) : null,
          actions: _alarmMode
              ? const [
                  AndroidNotificationAction('stop', 'Dừng',
                      cancelNotification: true)
                ]
              : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  String _formatDays(dynamic rawDays) {
    const names = {
      2: 'Thứ 2',
      3: 'Thứ 3',
      4: 'Thứ 4',
      5: 'Thứ 5',
      6: 'Thứ 6',
      7: 'Thứ 7',
      8: 'Chủ nhật',
    };
    final days = _parseDays(rawDays)..sort();
    return days.map((day) => names[day] ?? '').join(', ');
  }

  String _formatTime(dynamic rawTime) {
    final time = _parseTime(rawTime);
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _chooseMinutes(Map<String, dynamic> item, bool exam) async {
    final selected = await showDialog<int>(
        context: context,
        builder: (context) =>
            SimpleDialog(title: const Text('Nhắc trước'), children: [
              for (final minutes in _reminderOptions)
                ListTile(
                    title: Text('$minutes phút'),
                    trailing: minutes == _minutesFor(item, isExam: exam)
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, minutes))
            ]));
    if (selected != null && mounted) {
      await _saveReminder(item, minutes: selected, enabled: true, isExam: exam);
    }
  }

  String _remindTime(Map<String, dynamic> item, int minutes) {
    final time = _parseTime(item['start_time']);
    if (time == null) return '';
    final value = time.hour * 60 + time.minute - minutes;
    final normalized = (value + 1440) % 1440;
    return '${(normalized ~/ 60).toString().padLeft(2, '0')}:${(normalized % 60).toString().padLeft(2, '0')}${value < 0 ? ' hôm trước' : ''}';
  }

  Widget _reminderCard(Map<String, dynamic> item, bool exam) {
    final enabled = _isEnabled(item, isExam: exam),
        minutes = _minutesFor(item, isExam: exam);
    final label = (item['category'] ?? '').toString();
    final subject = item['subjects'] as Map? ?? {};
    final rule = ScheduleRecurrence.frequency(item);
    final date = exam
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(item['exam_date']))
        : rule == 'weekly'
            ? _formatDays(item['day_of_week'])
            : rule == 'none'
                ? (item['start_date'] == null
                    ? ''
                    : DateFormat('dd/MM/yyyy')
                        .format(DateTime.parse(item['start_date'])))
                : ScheduleRecurrence.labels[rule];
    return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
        child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _saving ? null : () => _chooseMinutes(item, exam),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(subject['subject_name'] ?? 'Môn học',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16))),
                        Switch(
                            value: enabled,
                            onChanged: _saving
                                ? null
                                : (v) => _saveReminder(item,
                                    minutes: minutes, enabled: v, isExam: exam))
                      ]),
                      if (label.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: _categoryStore
                                        .colorOf(label)
                                        .withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.label,
                                          size: 16,
                                          color: _categoryStore.colorOf(label)),
                                      const SizedBox(width: 5),
                                      Flexible(child: Text(label))
                                    ]))),
                      Text(
                          '$date · ${_formatTime(item['start_time'])}–${_formatTime(item['end_time'])}'),
                      const SizedBox(height: 8),
                      Text(
                          enabled
                              ? 'Nhắc trước $minutes phút · ${_remindTime(item, minutes)}'
                              : 'Đang tắt · Nhắc trước $minutes phút',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ]))));
  }

  Widget _list(bool exam) {
    final items = exam ? _filteredExams : _filteredSchedules;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Card(
          elevation: 0,
          child: Column(children: [
            SwitchListTile(
                secondary: const Icon(Icons.alarm),
                title: const Text('Chế độ báo thức'),
                subtitle: Text(_supportsAlarm
                    ? 'Phát âm báo lặp lại cho các lịch đã bật nhắc nhở'
                    : 'Báo thức hiện hỗ trợ bản Android. iOS dùng thông báo có âm thanh; web không bảo đảm reo khi đóng ứng dụng.'),
                value: _alarmMode,
                onChanged: !_supportsAlarm || _saving
                    ? null
                    : (value) async {
                        if (!await confirmAction(context,
                                message: value
                                    ? 'Chuyển các nhắc nhở sang báo thức?'
                                    : 'Chuyển về thông báo thường?') ||
                            !mounted) {
                          return;
                        }
                        if (value) {
                          final allowed = await _notifications
                              .resolvePlatformSpecificImplementation<
                                  AndroidFlutterLocalNotificationsPlugin>()
                              ?.requestExactAlarmsPermission();
                          if (allowed != true) {
                            if (mounted) {
                              AppNotice.show(
                                  context,
                                  const SnackBar(
                                      content: Text(
                                          'Cần cho phép báo thức chính xác trong cài đặt thiết bị.')));
                            }
                            return;
                          }
                        }
                        final old = _alarmMode;
                        setState(() {
                          _saving = true;
                          _alarmMode = value;
                        });
                        try {
                          await _rescheduleAllEnabledReminders();
                          await (await SharedPreferences.getInstance()).setBool(
                              'alarm_mode_${_supabase.auth.currentUser?.id}',
                              value);
                        } catch (_) {
                          _alarmMode = old;
                          if (mounted) {
                            AppNotice.show(
                                context,
                                const SnackBar(
                                    content: Text(
                                        'Chưa đổi được chế độ. Kiểm tra quyền báo thức.')));
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      }),
            if (_supportsAlarm)
              TextButton.icon(
                  onPressed: _notificationsInitialized
                      ? () async {
                          await _notifications.show(
                              2147483000,
                              'Thử nhắc học',
                              'Nhấn Dừng hoặc chạm thông báo để tắt.',
                              _notificationDetails());
                        }
                      : null,
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('Thử âm báo')),
          ])),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
          key: ValueKey('$_defaultMinutes-$_defaultVersion'),
          initialValue: _defaultMinutes,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Mặc định cho nhắc nhở mới',
              border: OutlineInputBorder()),
          items: _reminderOptions
              .map((m) =>
                  DropdownMenuItem(value: m, child: Text('Nhắc trước $m phút')))
              .toList(),
          onChanged: _saving
              ? null
              : (v) async {
                  if (v == null || v == _defaultMinutes) return;
                  final old = _defaultMinutes;
                  if (!await confirmAction(context,
                          message:
                              'Dùng mặc định nhắc trước $v phút cho các nhắc nhở mới?') ||
                      !mounted) {
                    if (mounted) {
                      setState(() {
                        _defaultMinutes = old;
                        _defaultVersion++;
                      });
                    }
                    return;
                  }
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt(
                      'reminder_default_${_supabase.auth.currentUser?.id}', v);
                  if (mounted) setState(() => _defaultMinutes = v);
                }),
      if (_notificationNotice != null || _permissionGranted == false)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_notificationNotice ??
                  'Thông báo chưa được bật. Cho phép thông báo trong cài đặt thiết bị.'),
              if (_mobile)
                TextButton(
                    onPressed: _requestPermission,
                    child: const Text('Cho phép thông báo')),
            ])),
      const SizedBox(height: 20),
      TextField(
          controller: exam ? _examSearchController : _scheduleSearchController,
          decoration: const InputDecoration(
              hintText: 'Tìm môn học',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder())),
      const SizedBox(height: 16),
      if (items.isEmpty)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Chưa có lịch phù hợp để đặt nhắc nhở.')),
      for (final item in items) _reminderCard(item, exam),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        appBar: AppBar(
            title: const Text('Nhắc nhở'),
            actions: [
              IconButton(
                  tooltip: 'Làm mới',
                  onPressed: _saving ? null : _loadScreen,
                  icon: const Icon(Icons.refresh))
            ],
            bottom: TabBar(
                controller: _tabController,
                tabs: const [Tab(text: 'Lịch học'), Tab(text: 'Kiểm tra')])),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!)),
                    TextButton(
                        onPressed: _loadScreen, child: const Text('Thử lại'))
                  ]))
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: TabBarView(
                            controller: _tabController,
                            children: [_list(false), _list(true)]))),
      );
}

class _PendingReminder {
  const _PendingReminder(
      {required this.id,
      required this.title,
      required this.body,
      required this.scheduledDate});
  final int id;
  final String title, body;
  final tz.TZDateTime scheduledDate;
}
