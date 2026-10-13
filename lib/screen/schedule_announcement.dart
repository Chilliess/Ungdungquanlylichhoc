import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Màn hình thiết lập nhắc nhở lịch học.
///
/// Dữ liệu được lưu trên Supabase:
/// - reminders(user_id, schedule_id, remind_before_minutes, is_enabled)
/// - schedules(id, user_id, subject_id, day_of_week, start_time,
///   start_date, end_date)
///
/// Lưu ý: day_of_week có thể là một số (2..8) hoặc một danh sách số,
/// để tương thích với cả hai kiểu dữ liệu đã xuất hiện trong dự án.
class ScheduleAnnouncementScreen extends StatefulWidget {
  const ScheduleAnnouncementScreen({super.key});

  @override
  State<ScheduleAnnouncementScreen> createState() =>
      _ScheduleAnnouncementScreenState();
}

class _ScheduleAnnouncementScreenState
    extends State<ScheduleAnnouncementScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  final List<int> _reminderOptions = const [5, 10, 15, 30, 60, 120];
  List<Map<String, dynamic>> _schedules = [];
  Map<String, Map<String, dynamic>> _remindersBySchedule = {};
  bool _loading = true;
  bool _saving = false;
  bool _notificationsInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadScreen();
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
    // Tránh khởi tạo plugin và hỏi quyền lặp lại khi người dùng tải lại màn hình.
    if (_notificationsInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
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

    // Khởi tạo múi giờ của thiết bị để lịch nhắc chạy đúng giờ địa phương.
    tz_data.initializeTimeZones();
    final timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));

    // Xin quyền sau khi người dùng vào màn hình thiết lập nhắc nhở.
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
      final scheduleResponse = await _supabase
          .from('schedules')
          .select('*, subjects(subject_code, subject_name)')
          .eq('user_id', userId);

      final reminderResponse = await _supabase
          .from('reminders')
          .select()
          .eq('user_id', userId);

      final schedules =
      List<Map<String, dynamic>>.from(scheduleResponse as List);
      final reminders =
      List<Map<String, dynamic>>.from(reminderResponse as List);

      final reminderMap = <String, Map<String, dynamic>>{};
      for (final reminder in reminders) {
        final scheduleId = reminder['schedule_id']?.toString();
        if (scheduleId != null) {
          reminderMap[scheduleId] = reminder;
        }
      }

      if (mounted) {
        setState(() {
          _schedules = schedules;
          _remindersBySchedule = reminderMap;
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

  int _minutesFor(Map<String, dynamic> schedule) {
    final reminder = _remindersBySchedule[schedule['id'].toString()];
    final value = int.tryParse(
      reminder?['remind_before_minutes']?.toString() ?? '',
    );
    return _reminderOptions.contains(value) ? value! : 15;
  }

  bool _isEnabled(Map<String, dynamic> schedule) {
    final reminder = _remindersBySchedule[schedule['id'].toString()];
    return reminder?['is_enabled'] == true;
  }

  Future<void> _saveReminder(
      Map<String, dynamic> schedule, {
        required int minutes,
        required bool enabled,
      }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _saving = true);
    try {
      final scheduleId = schedule['id'].toString();
      final existing = _remindersBySchedule[scheduleId];

      final data = <String, dynamic>{
        'user_id': userId,
        'schedule_id': scheduleId,
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
        _remindersBySchedule[scheduleId] =
        Map<String, dynamic>.from(inserted);
      }

      // Đọc lại để đồng bộ ID và dữ liệu thực tế từ Supabase.
      await _loadData();
      await _rescheduleAllEnabledReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Đã bật nhắc nhở trước $minutes phút.'
                  : 'Đã tắt nhắc nhở cho lịch học này.',
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

  /// Tạo ID notification ổn định giữa các lần mở ứng dụng.
  int _notificationId(String scheduleId, DateTime classDate) {
    final input =
        '$scheduleId-${classDate.year}-${classDate.month}-${classDate.day}';
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

    // Xóa các lịch thông báo cũ trước khi dựng lại từ dữ liệu Supabase.
    // Nếu sau này app có thêm loại thông báo khác, nên tách quản lý ID riêng
    // thay vì dùng cancelAll().
    await _notifications.cancelAll();

    final now = tz.TZDateTime.now(tz.local);
    final candidates = <_PendingReminder>[];

    for (final schedule in _schedules) {
      final scheduleId = schedule['id']?.toString();
      if (scheduleId == null) continue;

      final reminder = _remindersBySchedule[scheduleId];
      if (reminder == null || reminder['is_enabled'] != true) continue;

      final days = _parseDays(schedule['day_of_week']);
      final startTime = _parseTime(schedule['start_time']);
      final startDate = _parseDate(schedule['start_date']);
      final endDate = _parseDate(schedule['end_date']);
      if (days.isEmpty ||
          startTime == null ||
          startDate == null ||
          endDate == null) {
        continue;
      }

      final minutes = int.tryParse(
        reminder['remind_before_minutes']?.toString() ?? '',
      ) ??
          15;
      final subject = schedule['subjects'] is Map
          ? Map<String, dynamic>.from(schedule['subjects'] as Map)
          : <String, dynamic>{};
      final subjectName =
          subject['subject_name']?.toString() ?? 'Môn học';

      // Chỉ dựng lịch trong 30 ngày tới. iOS giới hạn số thông báo chờ,
      // nên phía dưới chỉ lấy tối đa 50 thông báo gần nhất.
      for (var offset = 0; offset < 30; offset++) {
        final date = DateTime(now.year, now.month, now.day)
            .add(Duration(days: offset));

        final normalizedStart = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        );
        final normalizedEnd =
        DateTime(endDate.year, endDate.month, endDate.day);
        if (date.isBefore(normalizedStart) || date.isAfter(normalizedEnd)) {
          continue;
        }

        // Quy ước dự án: T2=2, ..., T7=7, CN=8.
        final appDay = date.weekday + 1;
        if (!days.contains(appDay)) continue;

        final classStart = tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          startTime.hour,
          startTime.minute,
        );
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

    candidates.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final limited = candidates.take(50);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_schedule_reminders',
        'Nhắc nhở lịch học',
        channelDescription: 'Thông báo trước giờ bắt đầu buổi học',
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
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết lập nhắc nhở lịch học'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
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
          : _schedules.isEmpty
          ? const Center(
        child: Text(
          'Bạn chưa có lịch học.\nHãy thêm lịch học trước.',
          textAlign: TextAlign.center,
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadScreen,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _schedules.length,
          itemBuilder: (context, index) {
            final schedule = _schedules[index];
            final subject = schedule['subjects'] is Map
                ? Map<String, dynamic>.from(
              schedule['subjects'] as Map,
            )
                : <String, dynamic>{};
            final enabled = _isEnabled(schedule);
            final minutes = _minutesFor(schedule);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject['subject_name']?.toString() ??
                          'Môn học chưa xác định',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subject['subject_code'] != null)
                      Text('Mã môn: ${subject['subject_code']}'),
                    const SizedBox(height: 6),
                    Text(
                      '${_formatDays(schedule['day_of_week'])}\n'
                          '${_formatTime(schedule['start_time'])} - '
                          '${_formatTime(schedule['end_time'])}',
                    ),
                    if (schedule['room'] != null &&
                        schedule['room'].toString().isNotEmpty)
                      Text('Phòng: ${schedule['room']}'),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Bật nhắc nhở',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: enabled,
                          activeColor: Colors.white,
                          activeTrackColor: Colors.blue,
                          onChanged: _saving
                              ? null
                              : (value) => _saveReminder(
                            schedule,
                            minutes: minutes,
                            enabled: value,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Nhắc trước giờ học'),
                        ),
                        DropdownButton<int>(
                          value: minutes,
                          items: _reminderOptions
                              .map(
                                (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value phút'),
                            ),
                          )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (value) {
                            if (value == null) return;
                            _saveReminder(
                              schedule,
                              minutes: value,
                              enabled: enabled,
                            );
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
      bottomNavigationBar: _saving
          ? const LinearProgressIndicator(minHeight: 3)
          : null,
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
