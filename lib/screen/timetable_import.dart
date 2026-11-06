import '../services/calendar_conflicts.dart';
import '../services/study_data.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lesson_editor.dart';
import '../models/schedule_recurrence.dart';

class TimetableImportScreen extends StatefulWidget {
  const TimetableImportScreen({super.key});
  @override
  State<TimetableImportScreen> createState() => _TimetableImportScreenState();
}

class _TimetableImportScreenState extends State<TimetableImportScreen> {
  bool _loading = false;
  String? _error, _filename;
  List<Map<String, dynamic>> _rows = [];
  final Set<int> _saved = {};
  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
        withData: true);
    if (result == null || !mounted) return;
    final file = result.files.single;
    if (file.bytes == null || file.size > 5 * 1024 * 1024) {
      setState(() => _error = 'Chọn ảnh hoặc PDF không quá 5 MB.');
      return;
    }
    final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Nhận dạng thời khóa biểu'),
                content: const Text(
                    'File sẽ được gửi tới dịch vụ OpenAI để đọc lịch. Kết quả cần bạn kiểm tra trước khi lưu.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Hủy')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Đồng ý'))
                ]));
    if (accepted != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _filename = file.name;
    });
    try {
      final response = await Supabase.instance.client.functions
          .invoke('import-timetable', body: {
        'filename': file.name,
        'extension': file.extension?.toLowerCase(),
        'data': base64Encode(file.bytes!),
      });
      final rows =
          List<Map<String, dynamic>>.from(response.data['rows'] as List);
      if (mounted) {
        setState(() {
          _rows = rows;
          _saved.clear();
          if (rows.isEmpty) {
            _error = 'Không nhận dạng được buổi học. Thử file rõ hơn.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Chưa nhận dạng được file. Kiểm tra mạng và cấu hình dịch vụ nhập lịch.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(int index) async {
    final row = _rows[index];
    TimeOfDay time(String? text, int fallback) {
      final parts = (text ?? '').split(':');
      return TimeOfDay(
          hour: (int.tryParse(parts.first) ?? fallback).clamp(0, 23),
          minute: (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0)
              .clamp(0, 59));
    }

    final date =
        DateTime.tryParse(row['date']?.toString() ?? '') ?? DateTime.now();
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => LessonEditor(
            initialDate: date,
            initial: LessonDraft(
                title: row['title']?.toString() ?? '',
                date: date,
                start: time(row['start'], 7),
                end: time(row['end'], 9),
                location: row['room']?.toString() ?? '',
                notes: 'Nhập từ $_filename'),
            manageRecurrence: true,
            beforeSave: (draft) => confirmCalendarConflicts(
                context, Supabase.instance.client, draft.toConflictRow()),
            onSave: (draft) async {
              final client = Supabase.instance.client;
              final owner = client.auth.currentUser?.id;
              if (owner == null) throw Exception('Vui lòng đăng nhập lại.');
              final rows = await loadOwnedStudyRows(client, 'schedules', owner);
              final start = draft.start.hour * 60 + draft.start.minute;
              final end = draft.end.hour * 60 + draft.end.minute;
              int minutes(dynamic raw) {
                final p = raw.toString().split(':');
                return int.parse(p[0]) * 60 + int.parse(p[1]);
              }

              for (final row in rows) {
                if (!ScheduleRecurrence.occursOn(row, draft.date)) continue;
                if (minutes(row['start_time']) == start &&
                    minutes(row['end_time']) == end &&
                    row['subjects']?['subject_name'] == draft.title.trim()) {
                  throw Exception(
                      'Buổi học này đã có trong lịch. Hãy kiểm tra để tránh nhập trùng.');
                }
              }
              await client.rpc('save_subject_schedule',
                  params: draft.toSubjectParameters());
            }));
    if (saved == true && mounted) setState(() => _saved.add(index));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Nhập ảnh / PDF')),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const Icon(Icons.document_scanner_outlined, size: 48),
                const SizedBox(height: 16),
                const Text('Đọc thời khóa biểu của bạn',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const Text(
                    'Kiểm tra từng buổi trước khi lưu. Nếu file chỉ ghi thứ hoặc số tiết, bạn cần chọn ngày và giờ cụ thể trong bước xác nhận.'),
                const SizedBox(height: 20),
                FilledButton.icon(
                    onPressed: _loading ? null : _pick,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Chọn ảnh hoặc PDF')),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(20),
                      child: LinearProgressIndicator()),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                for (var i = 0; i < _rows.length; i++)
                  Card(
                      child: ListTile(
                          title: Text(
                              _rows[i]['title']?.toString() ?? 'Chưa rõ môn'),
                          subtitle: Text(
                              '${_rows[i]['date'] ?? 'Cần chọn ngày'} · ${_rows[i]['start'] ?? 'Chưa rõ giờ'} – ${_rows[i]['end'] ?? '?'}\n${_rows[i]['room'] ?? 'Cần nhập phòng'}'),
                          trailing: Icon(_saved.contains(i)
                              ? Icons.check_circle
                              : Icons.edit_outlined),
                          onTap: _saved.contains(i) ? null : () => _review(i))),
              ]))));
}
