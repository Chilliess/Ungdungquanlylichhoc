import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:calendar_view/calendar_view.dart';

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

  List<Map<String, dynamic>> _rawSchedules = [];
  List<Map<String, dynamic>> _filteredSchedules = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _eventController = EventController();
    _tabController = TabController(length: 3, vsync: this);
    _loadDataFromSupabase();

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Hàm chuyển đổi mã Hex từ CSDL sang Color của Flutter
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

  // Hàm tìm kiếm
  void _onSearchChanged() {
    final keyword = _searchController.text.toLowerCase().trim();
    setState(() {
      if (keyword.isEmpty) {
        _filteredSchedules = List.from(_rawSchedules);
      } else {
        _filteredSchedules = _rawSchedules.where((item) {
          final subject = item['subjects'] ?? {};
          final subjectName = (subject['subject_name'] ?? '').toString().toLowerCase();
          final subjectCode = (subject['subject_code'] ?? '').toString().toLowerCase();
          final room = (item['room'] ?? '').toString().toLowerCase();
          final lecturer = (item['lecturer'] ?? '').toString().toLowerCase();

          return subjectName.contains(keyword) ||
              subjectCode.contains(keyword) ||
              room.contains(keyword) ||
              lecturer.contains(keyword);
        }).toList();
      }
    });
  }

  //Hàm hiện Event
  Future<void> _loadDataFromSupabase() async {
    setState(() => _isLoading = true);
    _eventController.removeWhere((element) => true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final scheduleRes = await supabase
          .from('schedules')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId);

      setState(() {
        _rawSchedules = List<Map<String, dynamic>>.from(scheduleRes);
        _filteredSchedules = List<Map<String, dynamic>>.from(_rawSchedules);
      });

      List<CalendarEventData> events = [];

      for (var item in _rawSchedules) {
        final subject = item['subjects'] ?? {};
        final subjectName = subject['subject_name'] ?? 'Môn học';
        final room = item['room'] ?? 'Chưa có phòng';
        final lecturer = item['lecturer'] ?? 'Chưa có GV';

        // Lấy màu sắc từ bảng subjects, nếu không có lấy màu mặc định
        final String? hexColor = subject['color_code'];
        final Color subjectColor = _getColorFromHex(hexColor);

        List<dynamic> rawDays = item['day_of_week'] ?? [2];
        List<int> targetDayOfWeeks = rawDays.map((e) => e is int ? e : int.parse(e.toString())).toList();
        List<int> targetDartWeekdays = targetDayOfWeeks.map((d) => (d == 8) ? 7 : d - 1).toList();

        final startTimeStr = item['start_time']?.toString() ?? '07:00:00';
        final endTimeStr = item['end_time']?.toString() ?? '09:00:00';

        final startParts = startTimeStr.split(':');
        final endParts = endTimeStr.split(':');

        final startHour = int.parse(startParts[0]);
        final startMinute = int.parse(startParts[1]);
        int endHour = int.parse(endParts[0]);
        int endMinute = int.parse(endParts[1]);

        DateTime now = DateTime.now();
        DateTime startDate = item['start_date'] != null ? DateTime.parse(item['start_date']) : now.subtract(const Duration(days: 180));
        DateTime endDate = item['end_date'] != null ? DateTime.parse(item['end_date']) : now.add(const Duration(days: 180));

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
                event: item,
              ),
            );
          }
        }
      }

      if (events.isNotEmpty) {
        _eventController.addAll(events);
      }
    } catch (e) {
      debugPrint('Lỗi tải lịch học: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Hàm hiện thông tin chi tiết
  void _showEventDetail(CalendarEventData event) {
    final item = event.event as Map<String, dynamic>?;
    final subject = item?['subjects'] ?? {};

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.book, color: event.color), // Icon đổi màu theo môn học
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            _buildDetailRow(Icons.room, 'Phòng học:', item?['room'] ?? 'Chưa cập nhật'),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.person, 'Giảng viên:', item?['lecturer'] ?? 'Chưa cập nhật'),
            const SizedBox(height: 10),
            _buildDetailRow(Icons.access_time, 'Thời gian:', '${item?['start_time']} - ${item?['end_time']}'),
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

  // Phần hiện thứ
  String _formatDaysOfWeek(dynamic rawDays) {
    if (rawDays == null) return 'Chưa rõ thứ';
    List<dynamic> list = rawDays is List ? rawDays : [rawDays];
    Map<int, String> mapName = {2: 'T2', 3: 'T3', 4: 'T4', 5: 'T5', 6: 'T6', 7: 'T7', 8: 'CN'};
    list.sort((a, b) => (int.tryParse(a.toString()) ?? 2).compareTo(int.tryParse(b.toString()) ?? 2));
    return list.map((d) => mapName[int.tryParse(d.toString()) ?? 2] ?? 'T2').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return CalendarControllerProvider(
      controller: _eventController,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Xem lịch học'),
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
              Tab(icon: Icon(Icons.search), text: 'Tìm kiếm'),
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

            // Tab 3: Tìm kiếm lịch học
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Nhập tên môn, mã môn, phòng hoặc GV...',
                      prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
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
                  child: _filteredSchedules.isEmpty
                      ? const Center(child: Text('Không tìm thấy lịch học phù hợp.'))
                      : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredSchedules.length,
                    itemBuilder: (context, index) {
                      final item = _filteredSchedules[index];
                      final subject = item['subjects'] ?? {};
                      final daysText = _formatDaysOfWeek(item['day_of_week']);
                      final Color subjectColor = _getColorFromHex(subject['color_code']);

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          // Thêm chấm tròn màu sắc bên trái danh sách tìm kiếm cho đồng bộ
                          leading: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: subjectColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            subject['subject_name'] ?? 'Môn học',
                            style: TextStyle(fontWeight: FontWeight.bold, color: subjectColor),
                          ),
                          subtitle: Text(
                            'Mã: ${subject['subject_code'] ?? 'N/A'}\nThứ: [$daysText] • ${item['start_time']} - ${item['end_time']}\nPhòng: ${item['room']} • GV: ${item['lecturer']}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}