
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StatisticalScreen extends StatefulWidget {
  const StatisticalScreen({super.key});

  @override
  State<StatisticalScreen> createState() =>
      _StatisticalScreenState();
}

class _StatisticalScreenState extends State<StatisticalScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool isLoading = true;
  bool showPeriods = false;
  String? errorMessage;

  List<Map<String, dynamic>> statistics = [];

  int totalSessions = 0;
  int totalPeriods = 0;

  DateTime get today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get weekStart =>
      today.subtract(Duration(days: today.weekday - 1));

  DateTime get weekEnd =>
      weekStart.add(const Duration(days: 6));

  @override
  void initState() {
    super.initState();
    loadStatistics();
  }

  Future<void> loadStatistics() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        throw Exception(
          'Bạn cần đăng nhập để xem thống kê.',
        );
      }

      final response = await supabase
          .from('schedules')
          .select(
        'id, subject_id, day_of_week, periods_count, '
            'start_date, end_date, '
            'subjects(subject_name, subject_code, color_code)',
      )
          .eq('user_id', userId);

      final Map<String, Map<String, dynamic>> result = {};

      int sessionsSum = 0;
      int periodsSum = 0;

      for (final raw in response) {
        final schedule = Map<String, dynamic>.from(raw);

        final subjectId =
        schedule['subject_id']?.toString();

        if (subjectId == null) continue;

        final startDate = _parseDate(schedule['start_date']);
        final endDate = _parseDate(schedule['end_date']);

        // Bỏ qua lịch nằm ngoài tuần hiện tại.
        if (startDate != null &&
            startDate.isAfter(weekEnd)) {
          continue;
        }

        if (endDate != null &&
            endDate.isBefore(weekStart)) {
          continue;
        }

        final firstDate =
        startDate == null || startDate.isBefore(weekStart)
            ? weekStart
            : startDate;

        final lastDate =
        endDate == null || endDate.isAfter(weekEnd)
            ? weekEnd
            : endDate;

        final sessions = countSessions(
          schedule['day_of_week'],
          firstDate,
          lastDate,
        );

        if (sessions == 0) continue;

        final periodsPerSession =
            _toInt(schedule['periods_count']) ?? 0;

        final periods = sessions * periodsPerSession;

        final subjectRaw = schedule['subjects'];
        final subject = subjectRaw is Map
            ? Map<String, dynamic>.from(subjectRaw)
            : <String, dynamic>{};

        final item = result.putIfAbsent(subjectId, () {
          return {
            'subject_id': subjectId,
            'subject_name':
            subject['subject_name']?.toString() ??
                'Môn học chưa đặt tên',
            'subject_code':
            subject['subject_code']?.toString() ?? '',
            'color_code':
            subject['color_code']?.toString() ?? '#4776E6',
            'sessions': 0,
            'periods': 0,
          };
        });

        item['sessions'] =
            (item['sessions'] as int) + sessions;

        item['periods'] =
            (item['periods'] as int) + periods;

        sessionsSum += sessions;
        periodsSum += periods;
      }

      final sortedStatistics = result.values.toList()
        ..sort((a, b) => (a['subject_name'] as String)
            .toLowerCase()
            .compareTo(
          (b['subject_name'] as String).toLowerCase(),
        ));

      if (!mounted) return;

      setState(() {
        statistics = sortedStatistics;
        totalSessions = sessionsSum;
        totalPeriods = periodsSum;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  // Quy ước của ứng dụng:
  // Thứ 2 = 2, Thứ 3 = 3, ..., Chủ nhật = 8.
  int countSessions(
      dynamic rawDays,
      DateTime firstDate,
      DateTime lastDate,
      ) {
    final Set<int> days = {};

    if (rawDays is List) {
      for (final value in rawDays) {
        final day = int.tryParse(value.toString());
        if (day != null) days.add(day);
      }
    } else if (rawDays != null) {
      final day = int.tryParse(rawDays.toString());
      if (day != null) days.add(day);
    }

    if (days.isEmpty || firstDate.isAfter(lastDate)) {
      return 0;
    }

    int count = 0;

    for (
    DateTime date = firstDate;
    !date.isAfter(lastDate);
    date = date.add(const Duration(days: 1))
    ) {
      // DateTime.weekday: Thứ 2 = 1, Chủ nhật = 7.
      // Dữ liệu của ứng dụng cộng thêm 1.
      if (days.contains(date.weekday + 1)) {
        count++;
      }
    }

    return count;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    try {
      final date = DateTime.parse(value.toString());
      return DateTime(date.year, date.month, date.day);
    } catch (_) {
      return null;
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Color parseColor(String? value) {
    if (value == null || value.isEmpty) {
      return const Color(0xFF4776E6);
    }

    String hex = value.replaceAll('#', '');

    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    final colorValue = int.tryParse(hex, radix: 16);

    return colorValue == null
        ? const Color(0xFF4776E6)
        : Color(colorValue);
  }

  String formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê lịch học'),
        actions: [
          IconButton(
            onPressed: isLoading ? null : loadStatistics,
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadStatistics,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return ListView(
        children: const [
          SizedBox(height: 220),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (errorMessage != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Không tải được thống kê:\n$errorMessage',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: loadStatistics,
              child: const Text('Thử lại'),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildWeekHeader(),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                title: 'Số buổi học',
                value: totalSessions,
                icon: Icons.event_available,
                color: const Color(0xFF4776E6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                title: 'Số tiết học',
                value: totalPeriods,
                icon: Icons.menu_book,
                color: const Color(0xFF11998E),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        const Text(
          'Thống kê theo môn học',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('Số buổi'),
              icon: Icon(Icons.event),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Số tiết'),
              icon: Icon(Icons.menu_book),
            ),
          ],
          selected: {showPeriods},
          onSelectionChanged: (selection) {
            setState(() {
              showPeriods = selection.first;
            });
          },
        ),

        const SizedBox(height: 12),

        if (statistics.isEmpty)
          _buildEmptyState()
        else
          ...statistics.map(_buildSubjectCard),

        const SizedBox(height: 16),

        Text(
          'Thống kê từ ${formatDate(weekStart)} đến '
              '${formatDate(weekEnd)}. Số buổi được tính theo '
              'ngày học và khoảng thời gian của từng lịch.',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildWeekHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF4776E6),
            Color(0xFF6A5AE0),
          ],
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tuần hiện tại',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatDate(weekStart)} - '
                      '${formatDate(weekEnd)}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(title),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> item) {
    final int value = showPeriods
        ? item['periods'] as int
        : item['sessions'] as int;

    final int total = showPeriods
        ? totalPeriods
        : totalSessions;

    final double ratio =
    total == 0 ? 0 : value / total;

    final color = parseColor(
      item['color_code']?.toString(),
    );

    final name =
        item['subject_name']?.toString() ?? 'Môn học';

    final code =
        item['subject_code']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.menu_book,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (code.isNotEmpty)
                        Text(
                          code,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '$value ${showPeriods ? 'tiết' : 'buổi'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: color.withOpacity(0.12),
                valueColor:
                AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(
            Icons.event_busy,
            size: 56,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 12),
          const Text(
            'Chưa có lịch học trong tuần này',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hãy thêm lịch học hoặc kiểm tra ngày bắt đầu, '
                'ngày kết thúc và ngày học của lịch.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
