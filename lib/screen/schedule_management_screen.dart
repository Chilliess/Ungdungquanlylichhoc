import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});

  @override
  State<ScheduleManagementScreen> createState() => _ScheduleManagementScreenState();
}

class _SessionGroup {
  Set<int> daysOfWeek;
  TimeOfDay startTime;
  TimeOfDay endTime;
  DateTime startDate;
  DateTime endDate;

  _SessionGroup({
    required this.daysOfWeek,
    required this.startTime,
    required this.endTime,
    required this.startDate,
    required this.endDate,
  });
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _filteredSchedules = []; // Danh sách sau khi tìm kiếm
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Hàm lọc tìm kiếm
  void _onSearchChanged() {
    final keyword = _searchController.text.toLowerCase().trim();
    setState(() {
      if (keyword.isEmpty) {
        _filteredSchedules = List.from(_schedules);
      } else {
        _filteredSchedules = _schedules.where((item) {
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

  // Phần hiện các lịch học
  Future<void> _fetchData() async {
    try {
      setState(() => _isLoading = true);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final subjectRes = await supabase
          .from('subjects')
          .select()
          .eq('user_id', userId);

      final scheduleRes = await supabase
          .from('schedules')
          .select('*, subjects(subject_code, subject_name, color_code)')
          .eq('user_id', userId);

      setState(() {
        _subjects = List<Map<String, dynamic>>.from(subjectRes);
        _schedules = List<Map<String, dynamic>>.from(scheduleRes);
        // Cập nhật lại danh sách lọc theo từ khóa hiện tại (nếu có)
        _onSearchChanged();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
      );
    }
  }

  // Kiểm tra nếu trùng lịch
  String? _checkConflictWithExisting({
    required List<int> newDays,
    required TimeOfDay newStart,
    required TimeOfDay newEnd,
    required DateTime newStartDate,
    required DateTime newEndDate,
    String? editingScheduleId,
  }) {
    int newStartMinutes = newStart.hour * 60 + newStart.minute;
    int newEndMinutes = newEnd.hour * 60 + newEnd.minute;

    if (newStartMinutes >= newEndMinutes) {
      return 'Giờ kết thúc phải lớn hơn giờ bắt đầu!';
    }
    if (newStartDate.isAfter(newEndDate)) {
      return 'Ngày bắt đầu không được lớn hơn ngày kết thúc!';
    }

    for (var existing in _schedules) {
      if (editingScheduleId != null && existing['id'].toString() == editingScheduleId) {
        continue;
      }

      if (existing['start_date'] != null && existing['end_date'] != null) {
        DateTime exStartDate = DateTime.parse(existing['start_date']);
        DateTime exEndDate = DateTime.parse(existing['end_date']);

        bool isDateOverlap = !(newEndDate.isBefore(exStartDate) || newStartDate.isAfter(exEndDate));
        if (!isDateOverlap) continue;
      }

      List<dynamic> existingDaysRaw = existing['day_of_week'] is List ? existing['day_of_week'] : [existing['day_of_week']];
      List<int> existingDays = existingDaysRaw.map((d) => int.tryParse(d.toString()) ?? 2).toList();

      bool hasCommonDay = newDays.any((day) => existingDays.contains(day));
      if (!hasCommonDay) continue;

      if (existing['start_time'] == null || existing['end_time'] == null) continue;

      final startParts = existing['start_time'].toString().split(':');
      final endParts = existing['end_time'].toString().split(':');

      int exStartMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      int exEndMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

      bool isTimeOverlap = (newStartMinutes < exEndMinutes) && (newEndMinutes > exStartMinutes);

      if (isTimeOverlap) {
        final subName = existing['subjects']?['subject_name'] ?? 'Môn học khác';
        return 'Bị trùng lịch với môn "$subName" vào khung giờ ${existing['start_time']} - ${existing['end_time']}!';
      }
    }
    return null;
  }

  // Hàm hiện phần Thêm / Sửa
  void _showScheduleDialog({Map<String, dynamic>? schedule}) {
    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn cần tạo Môn học trước khi thêm lịch học!')),
      );
      return;
    }

    final isEditing = schedule != null;
    String? selectedSubjectId = schedule?['subject_id'] ?? _subjects.first['id'];

    final roomController = TextEditingController(text: schedule?['room'] ?? '');
    final lecturerController = TextEditingController(text: schedule?['lecturer'] ?? '');
    final periodsCountController = TextEditingController(text: schedule?['periods_count']?.toString() ?? '3');

    List<_SessionGroup> sessionGroups = [];

    if (isEditing) {
      Set<int> currentDays = {};
      if (schedule['day_of_week'] is List) {
        for (var d in schedule['day_of_week']) {
          int? val = int.tryParse(d.toString());
          if (val != null) currentDays.add(val);
        }
      } else if (schedule['day_of_week'] != null) {
        int? val = int.tryParse(schedule['day_of_week'].toString());
        if (val != null) currentDays.add(val);
      }
      if (currentDays.isEmpty) currentDays.add(2);

      TimeOfDay sTime = const TimeOfDay(hour: 7, minute: 0);
      if (schedule['start_time'] != null) {
        final parts = schedule['start_time'].split(':');
        sTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }

      TimeOfDay eTime = const TimeOfDay(hour: 9, minute: 15);
      if (schedule['end_time'] != null) {
        final parts = schedule['end_time'].split(':');
        eTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }

      DateTime sDate = schedule['start_date'] != null ? DateTime.parse(schedule['start_date']) : DateTime.now();
      DateTime eDate = schedule['end_date'] != null ? DateTime.parse(schedule['end_date']) : DateTime.now().add(const Duration(days: 90));

      sessionGroups.add(_SessionGroup(
        daysOfWeek: currentDays,
        startTime: sTime,
        endTime: eTime,
        startDate: sDate,
        endDate: eDate,
      ));
    } else {
      sessionGroups.add(_SessionGroup(
        daysOfWeek: {2},
        startTime: const TimeOfDay(hour: 7, minute: 0),
        endTime: const TimeOfDay(hour: 9, minute: 15),
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 90)),
      ));
    }

    final Map<int, String> daysOfWeekMap = {
      2: 'T2', 3: 'T3', 4: 'T4', 5: 'T5', 6: 'T6', 7: 'T7', 8: 'CN',
    };

    // Giao diện phần Thêm / Sửa
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEditing ? 'Sửa lịch học' : 'Thêm lịch học mới'),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Chọn môn học:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: selectedSubjectId,
                        isExpanded: true,
                        items: _subjects.map((sub) {
                          return DropdownMenuItem<String>(
                            value: sub['id'].toString(),
                            child: Text(
                              '${sub['subject_code']} - ${sub['subject_name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() => selectedSubjectId = val);
                        },
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: roomController,
                        decoration: const InputDecoration(labelText: 'Phòng học chung (VD: P.402 A2)', border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: lecturerController,
                        decoration: const InputDecoration(labelText: 'Giảng viên', border: OutlineInputBorder(), isDense: true),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Các khung giờ & ngày học:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                          if (!isEditing)
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.green),
                              tooltip: 'Thêm khung giờ khác',
                              onPressed: () {
                                setDialogState(() {
                                  sessionGroups.add(_SessionGroup(
                                    daysOfWeek: {3},
                                    startTime: const TimeOfDay(hour: 13, minute: 30),
                                    endTime: const TimeOfDay(hour: 16, minute: 15),
                                    startDate: sessionGroups.first.startDate,
                                    endDate: sessionGroups.first.endDate,
                                  ));
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: sessionGroups.length,
                        itemBuilder: (context, index) {
                          final group = sessionGroups[index];
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Khung giờ #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                                      if (sessionGroups.length > 1 && !isEditing)
                                        InkWell(
                                          onTap: () {
                                            setDialogState(() => sessionGroups.removeAt(index));
                                          },
                                          child: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  const Text('Chọn các ngày trong tuần:', style: TextStyle(fontSize: 12)),
                                  const SizedBox(height: 4),

                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 0,
                                    children: daysOfWeekMap.entries.map((entry) {
                                      final dayKey = entry.key;
                                      final dayName = entry.value;
                                      final isSelected = group.daysOfWeek.contains(dayKey);

                                      return FilterChip(
                                        label: Text(dayName, style: const TextStyle(fontSize: 11)),
                                        selected: isSelected,
                                        visualDensity: VisualDensity.compact,
                                        selectedColor: Colors.blue.shade100,
                                        checkmarkColor: Colors.blue,
                                        onSelected: (bool selected) {
                                          setDialogState(() {
                                            if (selected) {
                                              group.daysOfWeek.add(dayKey);
                                            } else {
                                              if (group.daysOfWeek.length > 1) {
                                                group.daysOfWeek.remove(dayKey);
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Cần chọn ít nhất 1 ngày!'), duration: Duration(milliseconds: 600)),
                                                );
                                              }
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                                          onPressed: () async {
                                            final picked = await showTimePicker(context: context, initialTime: group.startTime);
                                            if (picked != null) {
                                              setDialogState(() => group.startTime = picked);
                                            }
                                          },
                                          child: Text('BĐ: ${group.startTime.format(context)}', style: const TextStyle(fontSize: 11)),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                                          onPressed: () async {
                                            final picked = await showTimePicker(context: context, initialTime: group.endTime);
                                            if (picked != null) {
                                              setDialogState(() => group.endTime = picked);
                                            }
                                          },
                                          child: Text('KT: ${group.endTime.format(context)}', style: const TextStyle(fontSize: 11)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: group.startDate,
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2030),
                                            );
                                            if (picked != null) {
                                              setDialogState(() => group.startDate = picked);
                                            }
                                          },
                                          child: Text('Từ: ${DateFormat('dd/MM/yyyy').format(group.startDate)}', style: const TextStyle(fontSize: 10)),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: group.endDate,
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2030),
                                            );
                                            if (picked != null) {
                                              setDialogState(() => group.endDate = picked);
                                            }
                                          },
                                          child: Text('Đến: ${DateFormat('dd/MM/yyyy').format(group.endDate)}', style: const TextStyle(fontSize: 10)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),

                      TextField(
                        controller: periodsCountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Số tiết học mỗi buổi (VD: 3)', border: OutlineInputBorder(), isDense: true),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                ElevatedButton(
                  onPressed: () async {
                    final userId = supabase.auth.currentUser?.id;
                    if (userId == null || selectedSubjectId == null) return;

                    for (int i = 0; i < sessionGroups.length; i++) {
                      for (int j = i + 1; j < sessionGroups.length; j++) {
                        var g1 = sessionGroups[i];
                        var g2 = sessionGroups[j];

                        bool isDateOverlap = !(g2.endDate.isBefore(g1.startDate) || g2.startDate.isAfter(g1.endDate));
                        if (!isDateOverlap) continue;

                        bool hasCommonDay = g1.daysOfWeek.any((d) => g2.daysOfWeek.contains(d));
                        if (hasCommonDay) {
                          int s1 = g1.startTime.hour * 60 + g1.startTime.minute;
                          int e1 = g1.endTime.hour * 60 + g1.endTime.minute;
                          int s2 = g2.startTime.hour * 60 + g2.startTime.minute;
                          int e2 = g2.endTime.hour * 60 + g2.endTime.minute;

                          if ((s1 < e2) && (e1 > s2)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Các khung giờ mới thêm bị trùng lịch lẫn nhau!'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                        }
                      }
                    }

                    for (var group in sessionGroups) {
                      String? conflictError = _checkConflictWithExisting(
                        newDays: group.daysOfWeek.toList(),
                        newStart: group.startTime,
                        newEnd: group.endTime,
                        newStartDate: group.startDate,
                        newEndDate: group.endDate,
                        editingScheduleId: isEditing ? schedule['id'].toString() : null,
                      );

                      if (conflictError != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(conflictError),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        return;
                      }
                    }

                    final periods = int.tryParse(periodsCountController.text) ?? 3;
                    final room = roomController.text.trim();
                    final lecturer = lecturerController.text.trim();

                    try {
                      if (isEditing) {
                        final group = sessionGroups.first;
                        final formattedStartTime = '${group.startTime.hour.toString().padLeft(2, '0')}:${group.startTime.minute.toString().padLeft(2, '0')}:00';
                        final formattedEndTime = '${group.endTime.hour.toString().padLeft(2, '0')}:${group.endTime.minute.toString().padLeft(2, '0')}:00';
                        final formattedStartDate = DateFormat('yyyy-MM-dd').format(group.startDate);
                        final formattedEndDate = DateFormat('yyyy-MM-dd').format(group.endDate);

                        final dataMap = {
                          'user_id': userId,
                          'subject_id': selectedSubjectId,
                          'room': room,
                          'lecturer': lecturer,
                          'day_of_week': group.daysOfWeek.toList(),
                          'start_time': formattedStartTime,
                          'end_time': formattedEndTime,
                          'start_date': formattedStartDate,
                          'end_date': formattedEndDate,
                          'periods_count': periods,
                        };

                        await supabase.from('schedules').update(dataMap).eq('id', schedule['id']);
                      } else {
                        for (var group in sessionGroups) {
                          final formattedStartTime = '${group.startTime.hour.toString().padLeft(2, '0')}:${group.startTime.minute.toString().padLeft(2, '0')}:00';
                          final formattedEndTime = '${group.endTime.hour.toString().padLeft(2, '0')}:${group.endTime.minute.toString().padLeft(2, '0')}:00';
                          final formattedStartDate = DateFormat('yyyy-MM-dd').format(group.startDate);
                          final formattedEndDate = DateFormat('yyyy-MM-dd').format(group.endDate);

                          final dataMap = {
                            'user_id': userId,
                            'subject_id': selectedSubjectId,
                            'room': room,
                            'lecturer': lecturer,
                            'day_of_week': group.daysOfWeek.toList(),
                            'start_time': formattedStartTime,
                            'end_time': formattedEndTime,
                            'start_date': formattedStartDate,
                            'end_date': formattedEndDate,
                            'periods_count': periods,
                          };

                          await supabase.from('schedules').insert(dataMap);
                        }
                      }

                      Navigator.pop(context);
                      _fetchData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isEditing ? 'Đã cập nhật lịch học!' : 'Đã thêm lịch học thành công!')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                    }
                  },
                  child: Text(isEditing ? 'Lưu' : 'Thêm tất cả'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Hàm xóa lịch
  void _deleteSchedule(String scheduleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Bạn có chắc chắn muốn xóa lịch học này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('schedules').delete().eq('id', scheduleId);
        _fetchData();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa lịch học!')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xóa: $e')));
      }
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Lịch học'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Thanh tìm kiếm
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên môn, mã môn, phòng, GV...',
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

          // Danh sách lịch học đã lọc
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

                String dateRangeStr = '';
                if (item['start_date'] != null && item['end_date'] != null) {
                  try {
                    final sDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(item['start_date']));
                    final eDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(item['end_date']));
                    dateRangeStr = '\nThời gian: $sDate đến $eDate';
                  } catch (_) {}
                }

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    title: Text(
                      subject['subject_name'] ?? 'Môn học',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                    subtitle: Text(
                      'Mã: ${subject['subject_code'] ?? 'N/A'}\nThứ: [$daysText] • ${item['start_time']} - ${item['end_time']}\nPhòng: ${item['room']} • GV: ${item['lecturer']}$dateRangeStr',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showScheduleDialog(schedule: item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteSchedule(item['id']),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showScheduleDialog(),
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}