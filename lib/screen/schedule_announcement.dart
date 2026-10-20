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

class _ScheduleAnnouncementScreenState
    extends State<ScheduleAnnouncementScreen>
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

  final TextEditingController _scheduleSearchController = TextEditingController();
  final TextEditingController _examSearchController = TextEditingController();

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
          return name.contains(keyword) || code.contains(keyword) || room.contains(keyword);
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
          final supervisor = (exam['supervisor'] ?? '').toString().toLowerCase();
          return name.contains(keyword) || code.contains(keyword) || room.contains(keyword) || supervisor.contains(keyword);
        }).toList();
      }
    });
  }

  Future<void> _loadScreen() async {
    try {
      await _initializeNotifications();
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

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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

    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _notificationsInitialized = true;
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
      final scheduleResponse = await _supabase
          .from('schedules')
          .select('*, subjects(subject_code, subject_name)')
          .eq('user_id', userId);

      // Tải lịch kiểm tra từ bảng schedule_exams
      final examResponse = await _supabase
          .from('schedule_exams')
          .select('*, subjects(subject_code, subject_name)')
          .eq('user_id', userId);

      // Tải tất cả nhắc nhở từ bảng reminders chung
      final reminderResponse = await _supabase
          .from('reminders')
          .select()
          .eq('user_id', userId);

      final schedules = List<Map<String, dynamic>>.from(scheduleResponse as List);
      final exams = List<Map<String, dynamic>>.from(examResponse as List);
      final reminders = List<Map<String, dynamic>>.from(reminderResponse as List);

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
    return _reminderOptions.contains(value) ? value! : 15;
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
    if (userId == null) return;

    setState(() => _saving = true);
    try {
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
        final inserted = await _supabase
            .from('reminders')
            .insert(data)
            .select()
            .single();
        reminderMap[itemId] = Map<String, dynamic>.from(inserted);
      }

      await _loadData();
      await _rescheduleAllEnabledReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
        ScaffoldMessenger.of(context).showSnackBar(
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

      final days = _parseDays(schedule['day_of_week']);
      final startTime = _parseTime(schedule['start_time']);
      final startDate = _parseDate(schedule['start_date']);
      final endDate = _parseDate(schedule['end_date']);
      if (days.isEmpty || startTime == null || startDate == null || endDate == null) {
        continue;
      }

      final minutes = int.tryParse(reminder['remind_before_minutes']?.toString() ?? '') ?? 15;
      final subject = schedule['subjects'] is Map ? Map<String, dynamic>.from(schedule['subjects'] as Map) : <String, dynamic>{};
      final subjectName = subject['subject_name']?.toString() ?? 'Môn học';

      for (var offset = 0; offset < 30; offset++) {
        final date = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
        final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
        final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);
        if (date.isBefore(normalizedStart) || date.isAfter(normalizedEnd)) continue;

        final appDay = date.weekday + 1;
        if (!days.contains(appDay)) continue;

        final classStart = tz.TZDateTime(tz.local, date.year, date.month, date.day, startTime.hour, startTime.minute);
        final notifyAt = classStart.subtract(Duration(minutes: minutes));
        if (!notifyAt.isAfter(now)) continue;

        candidates.add(
          _PendingReminder(
            id: _notificationId(scheduleId, date),
            title: 'Sắp đến giờ học: $subjectName',
            body: 'Bắt đầu lúc ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}. Còn $minutes phút nữa.',
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

      final minutes = int.tryParse(reminder['remind_before_minutes']?.toString() ?? '') ?? 15;
      final subject = exam['subjects'] is Map ? Map<String, dynamic>.from(exam['subjects'] as Map) : <String, dynamic>{};
      final subjectName = subject['subject_name']?.toString() ?? 'Môn học';

      final examStart = tz.TZDateTime(tz.local, examDate.year, examDate.month, examDate.day, startTime.hour, startTime.minute);
      final notifyAt = examStart.subtract(Duration(minutes: minutes));
      if (!notifyAt.isAfter(now)) continue;

      candidates.add(
        _PendingReminder(
          id: _notificationId(examId, examDate),
          title: 'Sắp đến giờ kiểm tra: $subjectName',
          body: 'Bắt đầu lúc ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}. Còn $minutes phút nữa.',
          scheduledDate: notifyAt,
        ),
      );
    }

    candidates.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final limited = candidates.take(50);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'schedule_reminders',
        'Nhắc nhở lịch',
        channelDescription: 'Thông báo trước giờ bắt đầu',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    for (final item in limited) {
      await _notifications.zonedSchedule(
        item.id,
        item.title,
        item.body,
        item.scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: item.id.toString(),
      );
    }
  }

  String _formatDays(dynamic rawDays) {
    const names = {
      2: 'Thứ 2', 3: 'Thứ 3', 4: 'Thứ 4', 5: 'Thứ 5',
      6: 'Thứ 6', 7: 'Thứ 7', 8: 'Chủ nhật',
    };
    final days = _parseDays(rawDays)..sort();
    return days.map((day) => names[day] ?? '').join(', ');
  }

  String _formatTime(dynamic rawTime) {
    final time = _parseTime(rawTime);
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết lập nhắc nhở lịch'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: isDark ? Colors.white : Colors.black,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blueAccent,
          tabs: const [
            Tab(text: 'Lịch học'),
            Tab(text: 'Lịch kiểm tra'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadScreen,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: ĐẶT THÔNG BÁO LỊCH HỌC
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _scheduleSearchController,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87, // Màu chữ khi gõ
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm lịch học (tên môn, mã, phòng)...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, // Màu chữ gợi ý
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark ? Colors.blue.shade300 : Colors.blueAccent,
                    ),
                    suffixIcon: _scheduleSearchController.text.isNotEmpty
                        ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      onPressed: () => _scheduleSearchController.clear(),
                    )
                        : null,
                    filled: true,
                    // Màu nền linh hoạt theo Light/Dark Mode
                    fillColor: isDark ? const Color(0xFF1F1F1F) : Colors.grey.shade100,

                    // Định nghĩa đường viền để không bị cứng nhắc màu sắc
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none, // Bỏ viền cứng nếu muốn thanh tìm kiếm dạng phẳng hiện đại
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Colors.blueAccent,
                        width: 1.5,
                      ),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: _filteredSchedules.isEmpty
                    ? const Center(child: Text('Không tìm thấy lịch học phù hợp.'))
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filteredSchedules.length,
                  itemBuilder: (context, index) {
                    final schedule = _filteredSchedules[index];
                    final subject = schedule['subjects'] is Map
                        ? Map<String, dynamic>.from(schedule['subjects'] as Map)
                        : <String, dynamic>{};
                    final enabled = _isEnabled(schedule, isExam: false);
                    final minutes = _minutesFor(schedule, isExam: false);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject['subject_name']?.toString() ?? 'Môn học chưa xác định',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                            ),
                            if (subject['subject_code'] != null)
                              Text('Mã môn: ${subject['subject_code']}'),
                            const SizedBox(height: 6),
                            Text(
                              '${_formatDays(schedule['day_of_week'])}\n'
                                  '${_formatTime(schedule['start_time'])} - ${_formatTime(schedule['end_time'])}',
                            ),
                            if (schedule['room'] != null && schedule['room'].toString().isNotEmpty)
                              Text('Phòng: ${schedule['room']}'),
                            const Divider(height: 24),
                            Row(
                              children: [
                                const Expanded(child: Text('Bật nhắc nhở', style: TextStyle(fontWeight: FontWeight.w600))),
                                Switch(
                                  value: enabled,
                                  activeColor: Colors.white,
                                  activeTrackColor: Colors.blue,
                                  onChanged: _saving ? null : (value) => _saveReminder(schedule, minutes: minutes, enabled: value, isExam: false),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Nhắc trước giờ học')),
                                DropdownButton<int>(
                                  value: minutes,
                                  items: _reminderOptions.map((value) => DropdownMenuItem<int>(value: value, child: Text('$value phút'))).toList(),
                                  onChanged: _saving ? null : (value) {
                                    if (value == null) return;
                                    _saveReminder(schedule, minutes: value, enabled: enabled, isExam: false);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          // TAB 2: ĐẶT THÔNG BÁO LỊCH KIỂM TRA
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _examSearchController,
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm lịch kiểm tra (tên môn, phòng thi, giám thị)...',
                    prefixIcon: const Icon(Icons.search, color: Colors.orange),
                    suffixIcon: _examSearchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _examSearchController.clear(),
                    )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: _filteredExams.isEmpty
                    ? const Center(child: Text('Không tìm thấy lịch kiểm tra phù hợp.'))
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filteredExams.length,
                  itemBuilder: (context, index) {
                    final exam = _filteredExams[index];
                    final subject = exam['subjects'] is Map
                        ? Map<String, dynamic>.from(exam['subjects'] as Map)
                        : <String, dynamic>{};
                    final enabled = _isEnabled(exam, isExam: true);
                    final minutes = _minutesFor(exam, isExam: true);

                    String examDateStr = '';
                    if (exam['exam_date'] != null) {
                      try {
                        examDateStr = DateFormat('dd/MM/yyyy').format(DateTime.parse(exam['exam_date']));
                      } catch (_) {}
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kiểm tra: ${subject['subject_name']?.toString() ?? 'Môn học'}',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                            ),
                            if (subject['subject_code'] != null)
                              Text('Mã môn: ${subject['subject_code']}'),
                            const SizedBox(height: 6),
                            Text(
                              'Ngày thi: $examDateStr\n'
                                  '${_formatTime(exam['start_time'])} - ${_formatTime(exam['end_time'])}',
                            ),
                            if (exam['room'] != null && exam['room'].toString().isNotEmpty)
                              Text('Phòng thi: ${exam['room']}'),
                            if (exam['supervisor'] != null && exam['supervisor'].toString().isNotEmpty)
                              Text('Giám thị: ${exam['supervisor']}'),
                            const Divider(height: 24),
                            Row(
                              children: [
                                const Expanded(child: Text('Bật nhắc nhở', style: TextStyle(fontWeight: FontWeight.w600))),
                                Switch(
                                  value: enabled,
                                  activeColor: Colors.white,
                                  activeTrackColor: Colors.orange,
                                  onChanged: _saving ? null : (value) => _saveReminder(exam, minutes: minutes, enabled: value, isExam: true),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Nhắc trước giờ thi')),
                                DropdownButton<int>(
                                  value: minutes,
                                  items: _reminderOptions.map((value) => DropdownMenuItem<int>(value: value, child: Text('$value phút'))).toList(),
                                  onChanged: _saving ? null : (value) {
                                    if (value == null) return;
                                    _saveReminder(exam, minutes: value, enabled: enabled, isExam: true);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _saving ? const LinearProgressIndicator(minHeight: 3) : null,
    );
  }
}

class _PendingReminder {
  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledDate;

  const _PendingReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
  });
}