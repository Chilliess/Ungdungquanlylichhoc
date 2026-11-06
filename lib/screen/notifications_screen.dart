import '../services/notification_reads.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/home_models.dart';
import '../models/study_notification.dart';
import '../services/home_service.dart';
import '../services/study_data.dart';
import 'view_schedule_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.service});
  final HomeService? service;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? HomeService();
  HomeSnapshot _data = const HomeSnapshot.empty();
  bool _loading = true, _failed = false;
  int _version = 0;
  Timer? _clock;
  StreamSubscription<String?>? _accounts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    studyDataRevision.addListener(_changed);
    notificationReads.addListener(_readChanged);
    _accounts = _service.accountChanges.listen((_) {
      if (!mounted) return;
      setState(() => _data = const HomeSnapshot.empty());
      _load();
    });
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  void _changed() => _load();
  void _readChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await _service.loadSnapshot();
      await notificationReads.load(_service.accountId);
      if (mounted && version == _version) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && version == _version) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _accounts?.cancel();
    studyDataRevision.removeListener(_changed);
    notificationReads.removeListener(_readChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _section(String title, List<StudyNotification> items, String empty,
          {bool due = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (items.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(empty))
        else
          for (final item in items)
            Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(due
                          ? Icons.alarm_rounded
                          : item.lesson.isExam
                              ? Icons.assignment_outlined
                              : Icons.calendar_month_rounded)),
                  title: Text(
                      '${notificationReads.isRead(_service.accountId, item.key) ? '' : '● '}'
                      '${item.lesson.subjectName}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          '${item.lesson.isExam ? 'Lịch thi' : 'Lịch học'} · '
                          '${DateFormat('dd/MM/yyyy · HH:mm').format(item.start)}'
                          ' – ${DateFormat('HH:mm').format(item.end)}'
                          '${item.lesson.room.isEmpty ? '' : '\n${item.lesson.room}'}'
                          '${due ? '\nĐã đến giờ nhắc nhở' : ''}')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final owner = _service.accountId;
                    await _markRead([item.key]);
                    if (!mounted || owner != _service.accountId) return;
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) =>
                            ViewScheduleScreen(initialDate: item.start)));
                    if (mounted) _load();
                  },
                )),
      ]);

  Future<void> _markRead(Iterable<String> keys) async {
    try {
      await notificationReads.mark(_service.accountId, keys);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chưa lưu được trạng thái đã đọc.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final items = StudyNotification.fromSnapshot(_data, now);
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo'), actions: [
        IconButton(
            tooltip: 'Đánh dấu tất cả đã đọc',
            onPressed: _loading || _failed || items.isEmpty
                ? null
                : () => _markRead(items
                    .where((item) => item.isDue(now) || item.start.isAfter(now))
                    .map((item) => item.key)),
            icon: const Icon(Icons.done_all_rounded)),
      ]),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Theo sát lịch học của bạn',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text(
                          'Nhắc nhở đến hạn và lịch học, lịch thi trong 7 ngày tới.'),
                      if (_loading)
                        const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()))
                      else if (_failed) ...[
                        const SizedBox(height: 24),
                        const Text(
                            'Chưa tải được thông báo. Vui lòng thử lại.'),
                        TextButton(
                            onPressed: _load, child: const Text('Thử lại')),
                      ] else ...[
                        for (final warning in _data.loadWarnings)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(warning)),
                        _section(
                            'Nhắc nhở đến hạn',
                            items.where((item) => item.isDue(now)).toList(),
                            'Chưa có nhắc nhở đến hạn.',
                            due: true),
                        _section(
                            'Lịch sắp tới',
                            items
                                .where((item) => item.start.isAfter(now))
                                .toList(),
                            'Bạn chưa có lịch học hoặc lịch thi sắp tới.'),
                      ],
                    ]),
              ))
            ],
          )),
    );
  }
}
