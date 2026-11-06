import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/schedule_recurrence.dart';
import 'study_data.dart';

/// Compare actual occurrences; touching endpoints do not overlap.
List<String> calendarConflicts(Map<String, dynamic> draft,
    List<Map<String, dynamic>> schedules, List<Map<String, dynamic>> exams,
    {String? excludeId, bool isExam = false}) {
  int minute(dynamic raw) {
    final parts = raw.toString().split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  final start = ScheduleRecurrence.date(draft['start_date'])!;
  final until =
      ScheduleRecurrence.date(draft['end_date']) ?? DateTime(2100, 12, 31);
  final result = <String>[];
  for (final entry in [
    for (final row in schedules) (row: row, exam: false),
    for (final row in exams) (row: row, exam: true),
  ]) {
    final row = entry.row;
    if (entry.exam == isExam && row['id']?.toString() == excludeId) continue;
    if (minute(draft['start_time']) >= minute(row['end_time']) ||
        minute(draft['end_time']) <= minute(row['start_time'])) {
      continue;
    }
    final otherStart = ScheduleRecurrence.date(
        entry.exam ? row['exam_date'] : row['start_date']);
    final otherEnd = ScheduleRecurrence.date(
            entry.exam ? row['exam_date'] : row['end_date']) ??
        DateTime(2100, 12, 31);
    var day =
        otherStart != null && otherStart.isAfter(start) ? otherStart : start;
    final end = otherEnd.isBefore(until) ? otherEnd : until;
    while (!day.isAfter(end)) {
      if (ScheduleRecurrence.occursOn(draft, day) &&
          (entry.exam || ScheduleRecurrence.occursOn(row, day))) {
        final subject = row['subjects'];
        final title = subject is Map
            ? subject['subject_name'] ?? 'Lịch đã có'
            : 'Lịch đã có';
        result.add(
            '${entry.exam ? 'Thi' : 'Học'}: $title · ${DateFormat('dd/MM/yyyy').format(day)} · ${row['start_time'].toString().substring(0, 5)}–${row['end_time'].toString().substring(0, 5)}');
        break;
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }
  return result;
}

Future<bool> confirmCalendarConflicts(
    BuildContext context, SupabaseClient client, Map<String, dynamic> draft,
    {String? excludeId, bool isExam = false}) async {
  final owner = client.auth.currentUser?.id;
  if (owner == null) throw Exception('Vui lòng đăng nhập để lưu lịch học.');
  final rows = await Future.wait([
    loadOwnedStudyRows(client, 'schedules', owner),
    loadOwnedStudyRows(client, 'schedule_exams', owner),
  ]);
  if (!context.mounted || client.auth.currentUser?.id != owner) return false;
  final conflicts = calendarConflicts(draft, rows[0], rows[1],
      excludeId: excludeId, isExam: isExam);
  if (conflicts.isEmpty) return true;
  final accepted = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: const Text('Lịch bị trùng giờ'),
                content: SingleChildScrollView(
                    child: Text(
                        '${conflicts.take(5).join('\n\n')}${conflicts.length > 5 ? '\n\nVà ${conflicts.length - 5} lịch khác.' : ''}\n\nBạn muốn quay lại chỉnh giờ hay vẫn lưu lịch này?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Quay lại')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Vẫn lưu')),
                ],
              )) ??
      false;
  return accepted && context.mounted && client.auth.currentUser?.id == owner;
}
