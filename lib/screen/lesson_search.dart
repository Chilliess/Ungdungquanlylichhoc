import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LessonSearch
    extends SearchDelegate<CalendarEventData<Map<String, dynamic>>?> {
  LessonSearch(this.events)
      : super(searchFieldLabel: 'Tìm tên môn học hoặc nhãn');
  final List<CalendarEventData<Map<String, dynamic>>> events;

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
            tooltip: 'Xóa tìm kiếm',
            onPressed: () => query = '',
            icon: const Icon(Icons.clear)),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Quay lại',
        onPressed: () => close(context, null),
        icon: const Icon(Icons.arrow_back),
      );

  Widget _results(BuildContext context) {
    final text = query.trim().toLowerCase();
    final matches = events
        .where((event) => '${event.title} ${event.event?['category'] ?? ''}'
            .toLowerCase()
            .contains(text))
        .toList()
      ..sort(
          (a, b) => (a.startTime ?? a.date).compareTo(b.startTime ?? b.date));
    if (matches.isEmpty) {
      return Center(
          child: Text(text.isEmpty
              ? 'Chưa có lịch học'
              : 'Không tìm thấy môn học phù hợp'));
    }
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final event = matches[index];
        final room = event.event?['room'] ?? '';
        final category = event.event?['category']?.toString() ?? '';
        final start = event.startTime == null
            ? ''
            : DateFormat('HH:mm').format(event.startTime!);
        final end = event.endTime == null
            ? ''
            : DateFormat('HH:mm').format(event.endTime!);
        return ListTile(
          leading: Icon(Icons.event, color: event.color),
          title: Text(event.title),
          subtitle: Text(
              '${DateFormat('dd/MM/yyyy').format(event.date)} · $start – $end\n$room${category.isEmpty ? '' : ' · $category'}'),
          isThreeLine: true,
          onTap: () => close(context, event),
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
}
