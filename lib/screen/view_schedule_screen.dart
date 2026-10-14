import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:intl/intl.dart';

class ViewScheduleScreen extends StatefulWidget {
  const ViewScheduleScreen({super.key});

  @override
  State<ViewScheduleScreen> createState() => _ViewScheduleScreenState();
}

class _ViewScheduleScreenState extends State<ViewScheduleScreen> with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  bool _isLoading = true;
  late final EventController _eventController;

  late TabController _tabController;

  List<Map<String, dynamic>> _allItems = []; // Gộp cả lịch học và lịch kiểm tra cho phần tìm kiếm

  @override
  void initState() {
    super.initState();
    _eventController = EventController();
    _tabController = TabController(length: 2, vsync: this);
    _loadDataFromSupabase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventController.dispose();
    super.dispose();
  }

  // Hàm chuyển đổi mã Hex sang Color
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

  // Tải dữ liệu từ cả 2 bảng schedules và schedule_exams
  Future<void> _loadDataFromSupabase() async {
    setState(() => _isLoading = true);
    _eventController.removeWhere((element) => true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 1. Lấy lịch học định kỳ
      final scheduleRes = await supabase
          .from('schedules')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId);

      // 2. Lấy lịch kiểm tra từ bảng mới schedule_exams
      final examRes = await supabase
          .from('schedule_exams')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId);

      List<Map<String, dynamic>> combinedItems = [];
      List<CalendarEventData> events = [];

      // Xử lý đưa Lịch học vào danh sách sự kiện
      for (var item in scheduleRes) {
        var mapItem = Map<String, dynamic>.from(item);
        mapItem['is_exam'] = false;
        combinedItems.add(mapItem);

        final subject = mapItem['subjects'] ?? {};
        final subjectName = subject['subject_name'] ?? 'Môn học';
        final room = mapItem['room'] ?? 'Chưa có phòng';
        final lecturer = mapItem['lecturer'] ?? 'Chưa có GV';
        final Color subjectColor = _getColorFromHex(subject['color_code']);

        List<dynamic> rawDays = mapItem['day_of_week'] ?? [2];
        List<int> targetDayOfWeeks = rawDays.map((e) => e is int ? e : int.parse(e.toString())).toList();
        List<int> targetDartWeekdays = targetDayOfWeeks.map((d) => (d == 8) ? 7 : d - 1).toList();

        final startTimeStr = mapItem['start_time']?.toString() ?? '07:00:00';
        final endTimeStr = mapItem['end_time']?.toString() ?? '09:00:00';

        final startParts = startTimeStr.split(':');
        final endParts = endTimeStr.split(':');

        final startHour = int.parse(startParts[0]);
        final startMinute = int.parse(startParts[1]);
        int endHour = int.parse(endParts[0]);
        int endMinute = int.parse(endParts[1]);

        DateTime now = DateTime.now();
        DateTime startDate = mapItem['start_date'] != null ? DateTime.parse(mapItem['start_date']) : now.subtract(const Duration(days: 180));
        DateTime endDate = mapItem['end_date'] != null ? DateTime.parse(mapItem['end_date']) : now.add(const Duration(days: 180));

        for (DateTime d = startDate; d.isBefore(endDate); d = d.add(const Duration(days: 1))) {
          if (targetDartWeekdays.contains(d.weekday)) {
            var startTime = DateTime(d.year, d.month, d.day, startHour, startMinute);
            var endTime = DateTime(d.year, d.month, d.day, endHour, endMinute);

            if (endTime.isBefore(startTime) || endTime.isAtSameMomentAs(startTime)) {
              endTime = startTime.add(const Duration(hours: 2));
            }

            events.add(
              CalendarEventData(
                title: subjectName,
                date: d,
                startTime: startTime,
                endTime: endTime,
                color: subjectColor,
                description: 'Phòng: $room\nGiảng viên: $lecturer\nThời gian: $startTimeStr - $endTimeStr',
                event: mapItem,
              ),
            );
          }
        }
      }

      // Xử lý đưa Lịch kiểm tra vào danh sách sự kiện
      for (var item in examRes) {
        var mapItem = Map<String, dynamic>.from(item);
        mapItem['is_exam'] = true;
        combinedItems.add(mapItem);

        final subject = mapItem['subjects'] ?? {};
        final subjectName = 'Kiểm tra: ${subject['subject_name'] ?? 'Môn học'}';
        final room = mapItem['room'] ?? 'Chưa có phòng';
        final supervisor = mapItem['supervisor'] ?? 'Chưa có';

        DateTime examDate = DateTime.parse(mapItem['exam_date']);
        final startTimeStr = mapItem['start_time'].toString();
        final endTimeStr = mapItem['end_time'].toString();

        final startParts = startTimeStr.split(':');
        final endParts = endTimeStr.split(':');

        var startTime = DateTime(examDate.year, examDate.month, examDate.day, int.parse(startParts[0]), int.parse(startParts[1]));
        var endTime = DateTime(examDate.year, examDate.month, examDate.day, int.parse(endParts[0]), int.parse(endParts[1]));

        events.add(
          CalendarEventData(
            title: subjectName,
            date: examDate,
            startTime: startTime,
            endTime: endTime,
            color: Colors.orange, // Lịch kiểm tra dùng màu cam nổi bật
            description: 'Phòng thi: $room\nGiảng viên coi thi: $supervisor\nThời gian: $startTimeStr - $endTimeStr',
            event: mapItem,
          ),
        );
      }

      setState(() {
        _allItems = combinedItems;
      });

      if (events.isNotEmpty) {
        _eventController.addAll(events);
      }
    } catch (e) {
      debugPrint('Lỗi tải lịch: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Hàm hiện thông tin chi tiết khi bấm vào sự kiện trên lịch
  void _showEventDetail(CalendarEventData event) {
    final item = event.event as Map<String, dynamic>?;
    final subject = item?['subjects'] ?? {};
    final bool isExam = item?['is_exam'] ?? false;

    final subjectName = subject['subject_name'] ?? 'Môn học';
    final fullTitle = isExam ? 'Kiểm tra: $subjectName' : subjectName;
    final room = item?['room'] ?? 'Chưa cập nhật';
    final person = isExam ? (item?['supervisor'] ?? 'Chưa cập nhật') : (item?['lecturer'] ?? 'Chưa cập nhật');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isExam ? Icons.assignment_turned_in : Icons.book,
              color: event.color,
            ),
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
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(Icons.code, 'Mã môn học:', subject['subject_code'] ?? 'N/A'),
            const SizedBox(height: 10),
            _buildDetailRow(
              Icons.room,
              isExam ? 'Phòng thi:' : 'Phòng học:',
              room,
            ),
            const SizedBox(height: 10),
            _buildDetailRow(
              Icons.person,
              isExam ? 'Giảng viên coi thi:' : 'Giảng viên:',
              person,
            ),
            const SizedBox(height: 10),
            _buildDetailRow(
              Icons.access_time,
              isExam ? 'Thời gian thi:' : 'Thời gian:',
              isExam
                  ? '${DateFormat('dd/MM/yyyy').format(event.date)} (${item?['start_time']} - ${item?['end_time']})'
                  : '${item?['start_time']} - ${item?['end_time']}',
            ),
          ],
        ),
        actions: [
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
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(value, style: TextStyle(color: Colors.grey[800])),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CalendarControllerProvider(
      controller: _eventController,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Xem lịch học & kiểm tra'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadDataFromSupabase,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blueAccent,
            tabs: const [
              Tab(icon: Icon(Icons.view_week), text: 'Tuần'),
              Tab(icon: Icon(Icons.calendar_today), text: 'Ngày'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Xem theo tuần
            WeekView(
              onEventTap: (events, date) {
                if (events.isNotEmpty) {
                  _showEventDetail(events.first);
                }
              },
              minDay: DateTime(2020),
              maxDay: DateTime(2100),
              initialDay: DateTime.now(),
              timeLineWidth: 60,
              liveTimeIndicatorSettings: const LiveTimeIndicatorSettings(
                color: Colors.red,
                showTime: true,
              ),
            ),

            // Tab 2: Xem theo ngày
            DayView(
              onEventTap: (events, date) {
                if (events.isNotEmpty) {
                  _showEventDetail(events.first);
                }
              },
              minDay: DateTime(2020),
              maxDay: DateTime(2100),
              initialDay: DateTime.now(),
              timeLineWidth: 60,
              liveTimeIndicatorSettings: const LiveTimeIndicatorSettings(
                color: Colors.red,
                showTime: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}