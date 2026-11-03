import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/home_models.dart';
import '../models/schedule_recurrence.dart';
import '../theme/app_palette.dart';

/// Thu thập và tổng hợp dữ liệu trang chủ từ các bảng Supabase sẵn có.
///
/// Không tạo bảng/schema mới: dữ liệu được lấy từ `profiles`, `subjects`,
/// `schedules`, `schedule_exams` và `reminders`.
class HomeService {
  HomeService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// Client Supabase.
  ///
  /// Được tạo lazily để không ném lỗi khi `Supabase.initialize` chưa chạy
  /// (ví dụ trong môi trường test), đồng thời vẫn cho phép inject client
  /// giả khi kiểm thử.
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Tải toàn bộ dữ liệu trang chủ của người dùng hiện tại.
  Future<HomeSnapshot> loadSnapshot({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final userId = _client.auth.currentUser?.id;

    if (userId == null) {
      return const HomeSnapshot.empty();
    }

    final results = await Future.wait([
      _client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle(),
      _client
          .from('subjects')
          .select()
          .eq('user_id', userId)
          .order('subject_code', ascending: true),
      _client
          .from('schedules')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId),
      _client
          .from('schedule_exams')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId),
      _client
          .from('reminders')
          .select(
              'id, schedule_id, schedule_type, remind_before_minutes, is_enabled')
          .eq('user_id', userId),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final subjects = List<Map<String, dynamic>>.from(results[1] as List);
    final schedules = List<Map<String, dynamic>>.from(results[2] as List);
    final exams = List<Map<String, dynamic>>.from(results[3] as List);
    final reminders = List<Map<String, dynamic>>.from(results[4] as List);

    return buildSnapshot(
      username: profile?['username']?.toString(),
      subjects: subjects,
      schedules: schedules,
      exams: exams,
      reminders: reminders,
      now: reference,
    );
  }

  /// Gộp dữ liệu thô thành [HomeSnapshot] (tách riêng để có thể kiểm thử).
  static HomeSnapshot buildSnapshot({
    required List<Map<String, dynamic>> subjects,
    required List<Map<String, dynamic>> schedules,
    required List<Map<String, dynamic>> exams,
    required List<Map<String, dynamic>> reminders,
    String? username,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();

    final weeklyLessons = <TodayLesson>[];
    final subjectLessonCount = <String, int>{};

    for (final schedule in schedules) {
      final days = ScheduleRecurrence.frequency(schedule) == 'weekly'
          ? WeekdayUtils.parseDays(schedule['day_of_week'])
          : {2};
      if (days.isEmpty) continue;

      final subject = _subjectMap(schedule['subjects']);
      final subjectId = schedule['subject_id']?.toString() ?? '';

      for (final day in days) {
        weeklyLessons.add(
          TodayLesson(
            id: '${schedule['id']}-$day',
            schedule: {
              ...schedule,
              if (ScheduleRecurrence.frequency(schedule) == 'weekly')
                'day_of_week': [day]
            },
            subjectName: subject['subject_name']?.toString() ?? 'Môn học',
            subjectCode: subject['subject_code']?.toString() ?? '',
            color: AppPalette.fromHex(subject['color_code']?.toString()),
            startTime: _timeString(schedule['start_time']),
            endTime: _timeString(schedule['end_time']),
            room: schedule['room']?.toString() ?? '',
            lecturer: schedule['lecturer']?.toString() ?? '',
            isExam: false,
            periodsCount: _intValue(schedule['periods_count'], fallback: 1),
            appWeekday: day,
            startDate: _dateValue(schedule['start_date']),
            endDate: _dateValue(schedule['end_date']),
          ),
        );
        subjectLessonCount[subjectId] =
            (subjectLessonCount[subjectId] ?? 0) + 1;
      }
    }

    weeklyLessons.sort(_compareLessons);

    bool validOn(TodayLesson lesson, DateTime date) =>
        ScheduleRecurrence.occursOn(lesson.schedule!, date);
    final todayLessons =
        weeklyLessons.where((lesson) => validOn(lesson, reference)).toList();

    final upcomingExams = <TodayLesson>[];
    for (final exam in exams) {
      final examDate = _dateValue(exam['exam_date']);
      if (examDate == null) continue;

      final subject = _subjectMap(exam['subjects']);
      upcomingExams.add(
        TodayLesson(
          id: exam['id']?.toString() ?? '',
          subjectName: subject['subject_name']?.toString() ?? 'Môn học',
          subjectCode: subject['subject_code']?.toString() ?? '',
          color: AppPalette.fromHex(subject['color_code']?.toString()),
          startTime: _timeString(exam['start_time']),
          endTime: _timeString(exam['end_time']),
          room: exam['room']?.toString() ?? '',
          lecturer: exam['supervisor']?.toString() ?? '',
          isExam: true,
          periodsCount: 1,
          appWeekday: WeekdayUtils.toAppWeekday(examDate),
          date: examDate,
        ),
      );
    }

    upcomingExams.sort((a, b) {
      final aDate = a.date;
      final bDate = b.date;
      if (aDate == null || bDate == null) return 0;
      final dateCompare = aDate.compareTo(bDate);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });

    final todayExams = upcomingExams
        .where((exam) => exam.date != null && _isSameDay(exam.date!, reference))
        .toList();

    for (final exam in todayExams) {
      todayLessons.add(exam);
    }

    todayLessons.sort(_compareLessons);

    final nextLessons = <TodayLesson>[];
    final tomorrow =
        DateTime(reference.year, reference.month, reference.day + 1);
    for (final lesson in weeklyLessons) {
      final row = lesson.schedule!;
      final start = ScheduleRecurrence.date(row['start_date']);
      final earliest =
          start != null && start.isAfter(tomorrow) ? start : tomorrow;
      final end =
          ScheduleRecurrence.date(row['end_date']) ?? DateTime(2100, 12, 31);
      final dates = ScheduleRecurrence.between(row, earliest, end);
      if (dates.isEmpty) continue;
      final date = dates.first;
      nextLessons.add(TodayLesson(
          id: lesson.id,
          subjectName: lesson.subjectName,
          subjectCode: lesson.subjectCode,
          color: lesson.color,
          startTime: lesson.startTime,
          endTime: lesson.endTime,
          room: lesson.room,
          lecturer: lesson.lecturer,
          isExam: false,
          periodsCount: lesson.periodsCount,
          appWeekday: lesson.appWeekday,
          date: date));
    }
    nextLessons.addAll(upcomingExams
        .where((exam) => exam.date != null && !exam.date!.isBefore(tomorrow)));
    nextLessons.sort((a, b) {
      final comparison = a.date!.compareTo(b.date!);
      return comparison == 0 ? a.startTime.compareTo(b.startTime) : comparison;
    });

    final subjectSummaries = <SubjectSummary>[];
    for (final subject in subjects) {
      final id = subject['id']?.toString() ?? '';
      subjectSummaries.add(
        SubjectSummary(
          id: id,
          subjectCode: subject['subject_code']?.toString() ?? '',
          subjectName: subject['subject_name']?.toString() ?? 'Môn học',
          color: AppPalette.fromHex(subject['color_code']?.toString()),
          weeklyLessonCount: subjectLessonCount[id] ?? 0,
        ),
      );
    }

    final reminderItems = <ReminderItem>[];
    var enabledReminderCount = 0;
    for (final reminder in reminders) {
      final isEnabled = reminder['is_enabled'] == true;
      if (isEnabled) enabledReminderCount++;

      final scheduleId = reminder['schedule_id']?.toString() ?? '';
      final type = reminder['schedule_type']?.toString() ?? 'schedule';

      String? subjectName;
      String? startTime;
      DateTime? examDate;

      if (type == 'exam') {
        final exam = exams.where((e) => e['id']?.toString() == scheduleId);
        if (exam.isNotEmpty) {
          final subject = _subjectMap(exam.first['subjects']);
          subjectName = subject['subject_name']?.toString();
          startTime = _timeString(exam.first['start_time']);
          examDate = _dateValue(exam.first['exam_date']);
        }
      } else {
        final schedule =
            schedules.where((s) => s['id']?.toString() == scheduleId);
        if (schedule.isNotEmpty) {
          final subject = _subjectMap(schedule.first['subjects']);
          subjectName = subject['subject_name']?.toString();
          startTime = _timeString(schedule.first['start_time']);
        }
      }

      reminderItems.add(
        ReminderItem(
          scheduleId: scheduleId,
          scheduleType: type,
          remindBeforeMinutes:
              _intValue(reminder['remind_before_minutes'], fallback: 15),
          isEnabled: isEnabled,
          subjectName: subjectName,
          startTime: startTime,
          examDate: examDate,
        ),
      );
    }

    return HomeSnapshot(
      username: username,
      subjects: subjectSummaries,
      weeklyLessons: weeklyLessons,
      todayLessons: todayLessons,
      upcomingExams: upcomingExams,
      upcomingLessons: nextLessons.take(3).toList(),
      reminders: reminderItems,
      enabledReminderCount: enabledReminderCount,
      weeklyLessonCount: weeklyLessons.length,
    );
  }

  /// So sánh hai buổi học theo ngày trong tuần rồi theo giờ bắt đầu.
  static int _compareLessons(TodayLesson a, TodayLesson b) {
    final dayCompare = a.appWeekday.compareTo(b.appWeekday);
    if (dayCompare != 0) return dayCompare;
    return a.startTime.compareTo(b.startTime);
  }

  static Map<String, dynamic> _subjectMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  static String _timeString(dynamic raw) {
    if (raw == null) return '';
    final value = raw.toString();
    if (value.length >= 5) return value.substring(0, 5);
    return value;
  }

  static int _intValue(dynamic raw, {required int fallback}) {
    if (raw is int) return raw;
    if (raw == null) return fallback;
    return int.tryParse(raw.toString()) ?? fallback;
  }

  static DateTime? _dateValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
