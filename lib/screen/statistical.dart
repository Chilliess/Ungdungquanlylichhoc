import '../services/study_data.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/study_statistics.dart';
import 'view_schedule_screen.dart';
import '../services/learning_store.dart';
import '../widgets/learning_summary.dart';

class StatisticalScreen extends StatefulWidget {
  const StatisticalScreen({super.key, this.loadSchedules, this.initialDate});
  final Future<List<Map<String, dynamic>>> Function()? loadSchedules;
  final DateTime? initialDate;
  @override
  State<StatisticalScreen> createState() => _StatisticalScreenState();
}

class _StatisticalScreenState extends State<StatisticalScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _month = false;
  String? _error;
  late DateTime _anchor;
  DateTime? _selected;
  @override
  void initState() {
    super.initState();
    _anchor = widget.initialDate ?? DateTime.now();
    _load();
  }

  DateTime get _start => _month
      ? DateTime(_anchor.year, _anchor.month)
      : DateTime(
          _anchor.year, _anchor.month, _anchor.day - _anchor.weekday + 1);
  DateTime get _end => _month
      ? DateTime(_anchor.year, _anchor.month + 1, 0)
      : DateTime(_start.year, _start.month, _start.day + 6);
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Map<String, dynamic>> rows;
      if (widget.loadSchedules != null) {
        rows = await widget.loadSchedules!();
      } else {
        await learningStore.load();
        final client = Supabase.instance.client,
            user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw Exception('Bạn cần đăng nhập để xem thống kê.');
        rows = List<Map<String, dynamic>>.from(
            await loadOwnedStudyRows(client, 'schedules', user.id));
      }
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Không tải được thống kê. Kiểm tra kết nối hoặc đăng nhập lại.';
          _loading = false;
        });
      }
    }
  }

  void _move(int direction) => setState(() {
        _anchor = _month
            ? DateTime(_anchor.year, _anchor.month + direction)
            : DateTime(
                _anchor.year, _anchor.month, _anchor.day + 7 * direction);
        _selected = null;
      });
  Future<void> _openDay(DateTime date) async {
    await Navigator.of(context).push(PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondary) =>
            ViewScheduleScreen(initialDate: date),
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 380),
        transitionsBuilder: (_, animation, secondary, child) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
                scale: Tween<double>(begin: .96, end: 1).animate(
                    CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic)),
                child: child))));
    if (mounted) await _load();
  }

  Widget _metric(String value, String label) => Expanded(
          child: Column(children: [
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600))),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]));
  Widget _chart(StudyStatistics stats) {
    final entries = stats.dailyMinutes.entries.toList();
    final maxMinutes =
        math.max(60, entries.fold<int>(0, (a, b) => math.max(a, b.value)));
    final ceiling = (maxMinutes / 60).ceil() * 60;
    final color = Theme.of(context).colorScheme;
    return SizedBox(
        height: 205,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: 40,
              child: Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${ceiling ~/ 60} giờ',
                            style: Theme.of(context).textTheme.labelSmall),
                        Text(
                            '${ceiling / 120 == (ceiling / 120).roundToDouble() ? ceiling ~/ 120 : (ceiling / 120).toStringAsFixed(1)}',
                            style: Theme.of(context).textTheme.labelSmall),
                        const Text('0')
                      ]))),
          Expanded(
              child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final index = (details.localPosition.dx /
                                  box.maxWidth *
                                  entries.length)
                              .floor()
                              .clamp(0, entries.length - 1);
                          setState(() => _selected = entries[index].key);
                        },
                        child: Stack(children: [
                          Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: Divider(
                                  height: 1, color: color.outlineVariant)),
                          Positioned(
                              left: 0,
                              right: 0,
                              top: 86,
                              child: Divider(
                                  height: 1, color: color.outlineVariant)),
                          Positioned(
                              left: 0,
                              right: 0,
                              bottom: 32,
                              child: Divider(
                                  height: 1, color: color.outlineVariant)),
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (var i = 0; i < entries.length; i++)
                                  Expanded(
                                      child: Semantics(
                                          label:
                                              '${DateFormat('dd/MM/yyyy').format(entries[i].key)}, ${StudyStatistics.duration(entries[i].value)}',
                                          button: true,
                                          onTap: () => setState(
                                              () => _selected = entries[i].key),
                                          child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                AnimatedContainer(
                                                    duration: MediaQuery
                                                            .disableAnimationsOf(
                                                                context)
                                                        ? Duration.zero
                                                        : const Duration(
                                                            milliseconds: 380),
                                                    height: entries[i].value /
                                                        ceiling *
                                                        172,
                                                    width: _month ? 6 : 24,
                                                    decoration: BoxDecoration(
                                                        color: _selected ==
                                                                entries[i].key
                                                            ? color.primary
                                                            : color.primary
                                                                .withValues(
                                                                    alpha: .65),
                                                        borderRadius:
                                                            const BorderRadius.vertical(
                                                                top: Radius.circular(
                                                                    4)))),
                                                SizedBox(
                                                    height: 32,
                                                    child: Center(
                                                        child: Text(
                                                            _month
                                                                ? (i == 0 ||
                                                                        (i + 1) %
                                                                                5 ==
                                                                            0
                                                                    ? '${i + 1}'
                                                                    : '')
                                                                : [
                                                                    'T2',
                                                                    'T3',
                                                                    'T4',
                                                                    'T5',
                                                                    'T6',
                                                                    'T7',
                                                                    'CN'
                                                                  ][i],
                                                            style: TextStyle(
                                                                fontSize: _month
                                                                    ? 10
                                                                    : 12)))),
                                              ]))),
                              ]),
                        ]),
                      ))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final stats = StudyStatistics(_rows, _start, _end);
    final sorted = stats.subjects.values.toList()
      ..sort((a, b) => b.minutes.compareTo(a.minutes));
    final selected = _selected ??
        stats.dailySessions.entries
            .firstWhere((e) => e.value > 0,
                orElse: () => stats.dailySessions.entries.first)
            .key;
    final color = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: AppBar(title: const Text('Thống kê lịch học'), actions: [
          IconButton(
              tooltip: 'Làm mới',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center)),
                    TextButton(onPressed: _load, child: const Text('Thử lại'))
                  ]))
                : Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                                padding: const EdgeInsets.all(20),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SegmentedButton<bool>(
                                      segments: const [
                                        ButtonSegment(
                                            value: false, label: Text('Tuần')),
                                        ButtonSegment(
                                            value: true, label: Text('Tháng'))
                                      ],
                                      selected: {
                                        _month
                                      },
                                      onSelectionChanged: (v) => setState(() {
                                            _month = v.single;
                                            _selected = null;
                                          })),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    IconButton(
                                        tooltip: 'Khoảng trước',
                                        onPressed:
                                            _start.isAfter(DateTime(2020, 1, 7))
                                                ? () => _move(-1)
                                                : null,
                                        icon: const Icon(Icons.chevron_left)),
                                    Expanded(
                                        child: Text(
                                            _month
                                                ? 'Tháng ${_anchor.month}, ${_anchor.year}'
                                                : '${DateFormat('dd/MM/yyyy').format(_start)} – ${DateFormat('dd/MM/yyyy').format(_end)}',
                                            textAlign: TextAlign.center)),
                                    IconButton(
                                        tooltip: 'Khoảng sau',
                                        onPressed: _end.isBefore(
                                                DateTime(2100, 12, 25))
                                            ? () => _move(1)
                                            : null,
                                        icon: const Icon(Icons.chevron_right))
                                  ]),
                                  const SizedBox(height: 16),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 20),
                                      decoration: BoxDecoration(
                                          color: color.primaryContainer
                                              .withValues(alpha: .35),
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      child: Row(children: [
                                        _metric(
                                            '${stats.sessions}', 'Buổi học'),
                                        _metric(
                                            StudyStatistics.duration(
                                                stats.minutes),
                                            'Giờ học'),
                                        _metric('${stats.subjects.length}',
                                            'Môn học')
                                      ])),
                                  const SizedBox(height: 28),
                                  Text('Phân bố giờ học',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 18),
                                  _chart(stats),
                                  if (widget.loadSchedules == null)
                                    const LearningSummary(),
                                  Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          color: color.surfaceContainerLow,
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                '${DateFormat('dd/MM/yyyy').format(selected)} · ${stats.dailySessions[selected] == 0 ? 'Không có lịch' : StudyStatistics.duration(stats.dailyMinutes[selected] ?? 0)}'),
                                            TextButton(
                                                key: const ValueKey(
                                                    'stats-open-day'),
                                                onPressed: () =>
                                                    _openDay(selected),
                                                child: const Text(
                                                    'Xem lịch ngày này')),
                                          ])),
                                  const SizedBox(height: 24),
                                  Text('Theo môn học',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  if (sorted.isEmpty)
                                    const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 20),
                                        child: Text(
                                            'Chưa có lịch học trong khoảng thời gian này.')),
                                  for (final subject in sorted)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(subject.name,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                  alignment: WrapAlignment
                                                      .spaceBetween,
                                                  spacing: 16,
                                                  children: [
                                                    Text(
                                                        '${subject.sessions} buổi · ${StudyStatistics.duration(subject.minutes)}'),
                                                    Text(
                                                        '${stats.minutes == 0 ? 0 : (subject.minutes / stats.minutes * 100).round()}% thời gian',
                                                        style: TextStyle(
                                                            color: color
                                                                .onSurfaceVariant))
                                                  ]),
                                              const SizedBox(height: 10),
                                              LinearProgressIndicator(
                                                  value: stats.minutes == 0
                                                      ? 0
                                                      : subject.minutes /
                                                          stats.minutes,
                                                  minHeight: 5,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  backgroundColor: color
                                                      .surfaceContainerHighest),
                                            ])),
                                ])))));
  }
}
