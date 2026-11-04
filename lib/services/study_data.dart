import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local writes invalidate the home summary immediately, including dialog saves.
final studyDataRevision = ValueNotifier<int>(0);
void studyDataChanged() => studyDataRevision.value++;

/// Read each owned table explicitly: multiple foreign keys to subjects can make
/// PostgREST's implicit embedded relationship ambiguous on existing databases.
Future<List<Map<String, dynamic>>> loadOwnedStudyRows(
    SupabaseClient client, String table, String owner,
    {Future<List<Map<String, dynamic>>>? subjects}) async {
  if (!['schedules', 'schedule_exams'].contains(table)) {
    throw ArgumentError.value(table, 'table');
  }
  final results = await Future.wait([
    client.from(table).select().eq('user_id', owner),
    subjects ??
        client
            .from('subjects')
            .select()
            .eq('user_id', owner)
            .then((rows) => List<Map<String, dynamic>>.from(rows)),
  ]);
  if (client.auth.currentUser?.id != owner) {
    throw StateError('Tài khoản đã thay đổi trong lúc tải dữ liệu.');
  }
  return attachOwnedSubjects(
      List<Map<String, dynamic>>.from(results[0] as List),
      List<Map<String, dynamic>>.from(results[1] as List),
      owner);
}

List<Map<String, dynamic>> attachOwnedSubjects(List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> subjects, String owner) {
  final byId = {
    for (final subject in subjects)
      if (subject['user_id'] == owner) subject['id']: subject
  };
  return [
    for (final row in rows)
      if (row['user_id'] == owner) {...row, 'subjects': byId[row['subject_id']]}
  ];
}

String? accountDisplayName(
    {String? profileName, Map<String, dynamic>? metadata, String? email}) {
  for (final raw in [
    profileName,
    metadata?['username'],
    metadata?['full_name'],
    metadata?['name'],
    email?.split('@').first
  ]) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  }
  return null;
}
