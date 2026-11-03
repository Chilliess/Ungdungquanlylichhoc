/// Mô hình dữ liệu rút gọn cho trang chủ (lấy từ các bảng sẵn có của Supabase).
///
/// Không tạo bảng/schema mới: mọi trường đều suy ra từ
/// `schedules`, `schedule_exams`, `subjects`, `reminders` và `profiles`.
library;

import 'package:flutter/material.dart';

/// Quy ước ngày trong tuần của ứng dụng:
/// Thứ 2 = 2, Thứ 3 = 3, ..., Chủ nhật = 8.
class WeekdayUtils {
  const WeekdayUtils._();

  static const List<String> shortNames = [
    'T2',
    'T3',
    'T4',
    'T5',
    'T6',
    'T7',
    'CN',
  ];

  static const List<String> fullNames = [
    'Thứ hai',
    'Thứ ba',
    'Thứ tư',
    'Thứ năm',
    'Thứ sáu',
    'Thứ bảy',
    'Chủ nhật',
  ];

  /// Đổi `DateTime.weekday` (T2=1..CN=7) sang quy ước của ứng dụng (T2=2..CN=8).
  static int toAppWeekday(DateTime date) => date.weekday + 1;

  /// Đổi quy ước ứng dụng (T2=2..CN=8) về `DateTime.weekday` (T2=1..CN=7).
  static int toDateTimeWeekday(int appWeekday) =>
      appWeekday == 8 ? 7 : appWeekday - 1;

  /// Tên viết tắt của một ngày trong tuần (theo quy ước ứng dụng).
  static String shortName(int appWeekday) {
    if (appWeekday < 2 || appWeekday > 8) return '';
    return shortNames[appWeekday - 2];
  }

  /// Tên đầy đủ của một ngày trong tuần (theo quy ước ứng dụng).
  static String fullName(int appWeekday) {
    if (appWeekday < 2 || appWeekday > 8) return '';
    return fullNames[appWeekday - 2];
  }

  /// Chuỗi mô tả các ngày trong tuần, ví dụ "T2, T4, T6".
  static String describeDays(dynamic rawDays) {
    final days = parseDays(rawDays);
    if (days.isEmpty) return 'Chưa chọn ngày';
    final sorted = [...days]..sort();
    return sorted.map(shortName).join(', ');
  }

  /// Chuẩn hoá dữ liệu `day_of_week` (có thể là List hoặc số đơn) về Set<int>.
  static Set<int> parseDays(dynamic rawDays) {
    final result = <int>{};
    if (rawDays is List) {
      for (final value in rawDays) {
        final day = int.tryParse(value.toString());
        if (day != null && day >= 2 && day <= 8) result.add(day);
      }
    } else if (rawDays != null) {
      final day = int.tryParse(rawDays.toString());
      if (day != null && day >= 2 && day <= 8) result.add(day);
    }
    return result;
  }

  /// Phân tích chuỗi giờ "HH:mm" hoặc "HH:mm:ss" thành [TimeOfDay].
  static TimeOfDay? parseTime(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Định dạng [TimeOfDay] thành chuỗi "HH:mm".
  static String formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Một buổi học / buổi thi trong ngày (đã gộp từ `schedules` và `schedule_exams`).
class TodayLesson {
  const TodayLesson({
    required this.id,
    required this.subjectName,
    required this.subjectCode,
    required this.color,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.lecturer,
    required this.isExam,
    required this.periodsCount,
    this.appWeekday = 2,
    this.date,
    this.startDate,
    this.endDate,
    this.schedule,
  });

  final String id;
  final Map<String, dynamic>? schedule;
  final String subjectName;
  final String subjectCode;
  final Color color;
  final String startTime;
  final String endTime;
  final String room;
  final String lecturer;
  final bool isExam;
  final int periodsCount;

  /// Ngày trong tuần theo quy ước ứng dụng (Thứ 2 = 2 ... Chủ nhật = 8).
  final int appWeekday;

  /// Ngày cụ thể (dùng cho lịch thi / lịch học trong tuần).
  final DateTime? date;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Buổi học này đã kết thúc chưa.
  bool isFinished(DateTime now) {
    final end = _parseTime(endTime);
    if (end == null) return false;
    final endDate = DateTime(
      now.year,
      now.month,
      now.day,
      end.hour,
      end.minute,
    );
    return now.isAfter(endDate);
  }

  /// Buổi học này đang diễn ra chưa.
  bool isOngoing(DateTime now) {
    final start = _parseTime(startTime);
    final end = _parseTime(endTime);
    if (start == null || end == null) return false;
    final startDate =
        DateTime(now.year, now.month, now.day, start.hour, start.minute);
    final endDate =
        DateTime(now.year, now.month, now.day, end.hour, end.minute);
    return !now.isBefore(startDate) && now.isBefore(endDate);
  }

  /// Phân tích chuỗi giờ "HH:mm" hoặc "HH:mm:ss" thành [TimeOfDay].
  static TimeOfDay? _parseTime(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }
}

/// Tóm tắt một môn học kèm số buổi học trong tuần.
class SubjectSummary {
  const SubjectSummary({
    required this.id,
    required this.subjectCode,
    required this.subjectName,
    required this.color,
    this.weeklyLessonCount = 0,
  });

  final String id;
  final String subjectCode;
  final String subjectName;
  final Color color;

  /// Số buổi học trong tuần của môn này.
  final int weeklyLessonCount;
}

/// Một nhắc nhở đang bật cho lịch học / lịch kiểm tra.
class ReminderItem {
  const ReminderItem({
    required this.scheduleId,
    required this.scheduleType,
    required this.remindBeforeMinutes,
    required this.isEnabled,
    this.subjectName,
    this.startTime,
    this.examDate,
  });

  final String scheduleId;

  /// 'schedule' (lịch học) hoặc 'exam' (lịch kiểm tra).
  final String scheduleType;
  final int remindBeforeMinutes;
  final bool isEnabled;
  final String? subjectName;
  final String? startTime;
  final DateTime? examDate;

  bool get isExam => scheduleType == 'exam';
}

/// Toàn bộ dữ liệu trang chủ đã được tổng hợp từ Supabase.
class HomeSnapshot {
  const HomeSnapshot({
    required this.username,
    required this.subjects,
    required this.weeklyLessons,
    required this.todayLessons,
    required this.upcomingExams,
    required this.reminders,
    required this.enabledReminderCount,
    required this.weeklyLessonCount,
    this.upcomingLessons = const [],
  });

  const HomeSnapshot.empty()
      : username = null,
        subjects = const [],
        weeklyLessons = const [],
        todayLessons = const [],
        upcomingExams = const [],
        upcomingLessons = const [],
        reminders = const [],
        enabledReminderCount = 0,
        weeklyLessonCount = 0;

  /// Tên hiển thị lấy từ bảng `profiles`.
  final String? username;

  /// Danh sách môn học kèm số buổi học trong tuần.
  final List<SubjectSummary> subjects;

  /// Các buổi học trong tuần (nhóm theo ngày).
  final List<TodayLesson> weeklyLessons;

  /// Các buổi học / thi của hôm nay, đã sắp xếp theo giờ.
  final List<TodayLesson> todayLessons;

  /// Các kỳ thi sắp tới.
  final List<TodayLesson> upcomingExams;
  final List<TodayLesson> upcomingLessons;

  /// Các nhắc nhở đã cấu hình.
  final List<ReminderItem> reminders;

  /// Số nhắc nhở đang bật.
  final int enabledReminderCount;

  /// Tổng số buổi học trong tuần.
  final int weeklyLessonCount;

  bool get isEmpty =>
      subjects.isEmpty &&
      weeklyLessons.isEmpty &&
      todayLessons.isEmpty &&
      upcomingExams.isEmpty;
}
