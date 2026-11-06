import 'models/study_notification.dart';
import 'services/notification_reads.dart';
import 'dart:async';
import 'services/study_data.dart';
import 'widgets/assistant_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/home_models.dart';
import 'models/schedule_recurrence.dart';
import 'screen/info_account.dart';
import 'screen/schedule_announcement.dart';
import 'screen/notifications_screen.dart';
import 'screen/settings.dart';
import 'screen/statistical.dart';
import 'screen/subject_management_screen.dart';
import 'screen/view_schedule_screen.dart';
import 'services/home_service.dart';
import 'services/learning_store.dart';
import 'screen/tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.service});
  final HomeService? service;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final HomeService _service = widget.service ?? HomeService();
  HomeSnapshot _snapshot = const HomeSnapshot.empty();
  bool _loading = true, _failed = false, _hasSnapshot = false;
  int _loadVersion = 0;
  Timer? _refreshDebounce;
  Timer? _notificationClock;
  StreamSubscription<String?>? _accounts;
  String? _owner;
  DateTime? _selectedUpcomingDate;
  bool _upcomingDatePicked = false;
  int _activeTab = 0;
  ViewScheduleScreen? _calendarTab;
  TasksScreen? _tasksTab;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    studyDataRevision.addListener(_dataChanged);
    learningStore.addListener(_learningChanged);
    notificationReads.addListener(_learningChanged);
    _notificationClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _owner = _service.accountId;
    _accounts = _service.accountChanges.listen((owner) {
      if (!mounted || owner == _owner) return;
      _refreshDebounce?.cancel();
      _loadVersion++;
      setState(() {
        _owner = owner;
        _activeTab = 0;
        _calendarTab = null;
        _tasksTab = null;
        _snapshot = const HomeSnapshot.empty();
        _hasSnapshot = false;
        _selectedUpcomingDate = null;
        _upcomingDatePicked = false;
      });
      _load();
    });
    _load();
  }

  void _dataChanged() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _load(showLoader: false);
    });
  }

  void _learningChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(showLoader: false);
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _accounts?.cancel();
    studyDataRevision.removeListener(_dataChanged);
    learningStore.removeListener(_learningChanged);
    notificationReads.removeListener(_learningChanged);
    _notificationClock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    final version = ++_loadVersion;
    if (showLoader) setState(() => _loading = true);
    try {
      final data = await _service.loadSnapshot();
      await learningStore.load();
      await notificationReads.load(_owner);
      if (mounted && version == _loadVersion) {
        setState(() {
          _snapshot = data;
          _hasSnapshot = true;
          final now = DateTime.now();
          if (!_upcomingDatePicked) {
            _selectedUpcomingDate = data.upcomingLessons.isEmpty
                ? DateTime(now.year, now.month, now.day)
                : data.upcomingLessons.first.date;
          }
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
    if (screen is TasksScreen) {
      assistantDialog.value = false;
      setState(() {
        _activeTab = 2;
        _tasksTab ??= const TasksScreen(embedded: true);
      });
      return;
    }
    if (screen is ViewScheduleScreen) {
      assistantDialog.value = false;
      setState(() {
        _activeTab = 1;
        _calendarTab = ViewScheduleScreen(
          key: UniqueKey(),
          embedded: true,
          initialDate: screen.initialDate,
          openEditorOnStart: screen.openEditorOnStart,
        );
      });
      return;
    }
    final reduced = MediaQuery.disableAnimationsOf(context);
    await Navigator.push<void>(
        context,
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, secondary) => screen,
          transitionDuration:
              reduced ? Duration.zero : const Duration(milliseconds: 380),
          reverseTransitionDuration:
              reduced ? Duration.zero : const Duration(milliseconds: 280),
          transitionsBuilder: (_, animation, secondary, child) {
            final motion =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
                opacity: motion,
                child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1).animate(motion),
                    child: child));
          },
        ));
    if (mounted) await _load(showLoader: false);
  }

  Widget _header() {
    final notificationNow = DateTime.now();
    final unreadCount =
        StudyNotification.fromSnapshot(_snapshot, notificationNow)
            .where((item) =>
                (item.isDue(notificationNow) ||
                    item.start.isAfter(notificationNow)) &&
                !notificationReads.isRead(_owner, item.key))
            .length;
    final name = _snapshot.username?.trim().isNotEmpty == true
        ? _snapshot.username!.trim()
        : (_service.accountName ?? '');
    final dark = Theme.of(context).brightness == Brightness.dark;
    final words =
        name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? 'B'
        : words
            .skip(words.length > 1 ? words.length - 2 : 0)
            .map((word) => word.characters.first)
            .join()
            .toUpperCase();
    final hour = DateTime.now().hour;
    final greeting = hour >= 5 && hour < 11
        ? 'Chào buổi sáng'
        : hour >= 11 && hour < 14
            ? 'Chào buổi trưa'
            : hour >= 14 && hour < 18
                ? 'Chào buổi chiều'
                : hour >= 18 && hour < 22
                    ? 'Chào buổi tối'
                    : 'Chào buổi đêm';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF23212E) : const Color(0xFFF7F6FB),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(children: [
        Tooltip(
          message: 'Tài khoản',
          child: Material(
            color: dark ? const Color(0xFF37304F) : const Color(0xFFEEE9FF),
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(const AccountScreen()),
              child: Semantics(
                button: true,
                label: 'Tài khoản',
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Center(
                      child: Text(initials,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: dark
                                  ? const Color(0xFFC1B2FF)
                                  : const Color(0xFF6950E8)))),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(greeting,
                style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(name.isEmpty ? 'Bạn học' : name,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface)),
          ],
        )),
        const SizedBox(width: 12),
        IconButton.outlined(
            key: const ValueKey('home-notifications'),
            tooltip: 'Thông báo',
            onPressed: () => _open(NotificationsScreen(service: _service)),
            style: IconButton.styleFrom(
                backgroundColor: dark ? const Color(0xFF2C2938) : Colors.white,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                side: BorderSide(
                    color: dark
                        ? const Color(0xFF454052)
                        : const Color(0xFFE9E5F3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                minimumSize: const Size(52, 54)),
            icon: Badge(
                key: const ValueKey('home-unread-notifications'),
                isLabelVisible: unreadCount > 0,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: const Icon(Icons.notifications_none_rounded, size: 22))),
      ]),
    );
  }

  Widget _surface(Widget child) => Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _lesson(TodayLesson lesson, {bool upcoming = false}) => InkWell(
      onTap: () => _open(ViewScheduleScreen(
          initialDate: upcoming ? _selectedUpcomingDate : lesson.date)),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 3,
                height: 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                    color: lesson.color,
                    borderRadius: BorderRadius.circular(4))),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(lesson.subjectName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('${lesson.startTime} – ${lesson.endTime}'),
                  if (lesson.room.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(lesson.room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant))),
                ])),
            if (lesson.isExam)
              const Padding(
                  padding: EdgeInsets.only(left: 8), child: Text('Kiểm tra')),
          ])));
  List<TodayLesson> _lessonsOn(DateTime date, HomeSnapshot snapshot) {
    final day = DateTime(date.year, date.month, date.day);
    final lessons = snapshot.weeklyLessons
        .where((lesson) =>
            (lesson.schedule != null
                ? ScheduleRecurrence.occursOn(lesson.schedule!, day)
                : lesson.appWeekday == WeekdayUtils.toAppWeekday(day)) &&
            (lesson.startDate == null || !day.isBefore(lesson.startDate!)) &&
            (lesson.endDate == null || !day.isAfter(lesson.endDate!)))
        .toList();
    lessons.addAll(snapshot.upcomingExams.where(
        (exam) => exam.date != null && DateUtils.isSameDay(exam.date, day)));
    lessons.sort((a, b) => a.startTime.compareTo(b.startTime));
    return lessons;
  }

  Future<void> _chooseUpcomingDate() async {
    final initial = _selectedUpcomingDate ?? DateTime.now();
    final date = await showDatePicker(
        context: context,
        helpText: 'Chọn ngày xem lịch',
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100, 12, 31));
    if (date != null && mounted) {
      setState(() {
        _selectedUpcomingDate = date;
        _upcomingDatePicked = true;
      });
    }
  }

  Widget _upcomingHeader() {
    final date = _selectedUpcomingDate;
    final label = date == null
        ? 'Chưa có lịch'
        : '${WeekdayUtils.shortName(date.weekday + 1)}, ${DateFormat('dd/MM/yyyy').format(date)}';
    return Row(key: const ValueKey('home-upcoming-header'), children: [
      Text('Sắp tới', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(width: 8),
      Expanded(
          child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('home-upcoming-date'),
                onPressed: _chooseUpcomingDate,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: Text(label,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, size: 18),
                ]),
              ))),
      TextButton(
          key: const ValueKey('home-open-upcoming'),
          style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 6)),
          onPressed: date == null
              ? null
              : () => _open(ViewScheduleScreen(initialDate: date)),
          child: const Text('Mở lịch')),
    ]);
  }

  Widget _agenda() {
    final today = _snapshot.todayLessons;
    final next = _selectedUpcomingDate == null
        ? <TodayLesson>[]
        : _lessonsOn(_selectedUpcomingDate!, _snapshot);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
            child: Text('Hôm nay',
                style: Theme.of(context).textTheme.titleMedium)),
        TextButton(
            onPressed: () => _open(const ViewScheduleScreen()),
            child: const Text('Mở lịch')),
      ]),
      const SizedBox(height: 8),
      _surface(today.isEmpty
          ? Padding(
              key: const ValueKey('home-empty-today'),
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(Icons.event_available_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Hôm nay không có lịch',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Bạn có thể xem các buổi học sắp tới.'),
                    ])),
              ]))
          : Column(children: [
              for (var i = 0; i < today.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _lesson(today[i]),
              ]
            ])),
      const SizedBox(height: 24),
      _upcomingHeader(),
      const SizedBox(height: 12),
      if (next.isEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Ngày này chưa có lịch trình.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)))
      else
        _surface(Column(children: [
          for (var i = 0; i < next.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _lesson(next[i], upcoming: true),
          ]
        ])),
    ]);
  }

  Widget _tool(IconData icon, String label, Widget screen) => ListTile(
      leading: Icon(icon, size: 22),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _open(screen));
  Widget _tools() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (learningStore.pending.isNotEmpty) ...[
          Text('Deadline gần nhất',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _surface(ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(learningStore.pending.first['title']),
              subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(
                  DateTime.parse(learningStore.pending.first['deadline']))),
              onTap: () => _open(const TasksScreen()))),
          const SizedBox(height: 16),
        ],
        Text('Quản lý', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _surface(Column(children: [
          _tool(Icons.school_outlined, 'Môn học',
              const SubjectManagementScreen()),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _tool(Icons.insights_rounded, 'Thống kê', const StatisticalScreen()),
          const Divider(height: 1, indent: 56, endIndent: 16),
          _tool(Icons.alarm_rounded, 'Nhắc nhở',
              const ScheduleAnnouncementScreen()),
        ])),
      ]);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF11131D)
            : const Color(0xFFF5F6FB),
        body: ValueListenableBuilder<bool>(
          valueListenable: assistantDialog,
          builder: (context, chatOpen, home) => IndexedStack(
            index: chatOpen ? 3 : _activeTab,
            children: [
              home!,
              _calendarTab ?? const SizedBox.shrink(),
              _tasksTab ?? const SizedBox.shrink(),
              if (chatOpen)
                SafeArea(
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 820),
                            child: const AssistantChatPage())))
              else
                const SizedBox.shrink(),
            ],
          ),
          child: SafeArea(
              child: LayoutBuilder(
                  builder: (context, viewport) => ScrollConfiguration(
                        behavior: const MaterialScrollBehavior()
                            .copyWith(dragDevices: const {
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.touch,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus
                        }),
                        child: RefreshIndicator(
                          onRefresh: () async {
                            await learningStore.refresh();
                            await _load(showLoader: false);
                          },
                          child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(20),
                              children: [
                                Center(
                                    child: ConstrainedBox(
                                  key: const ValueKey('home-content'),
                                  constraints:
                                      const BoxConstraints(maxWidth: 1040),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _header(),
                                        const SizedBox(height: 16),
                                        const SizedBox(height: 20),
                                        Align(
                                            alignment: Alignment.centerLeft,
                                            child: FilledButton.icon(
                                                key: const ValueKey(
                                                    'home-add-lesson'),
                                                onPressed: () => _open(
                                                    const ViewScheduleScreen(
                                                        openEditorOnStart:
                                                            true)),
                                                icon: const Icon(Icons.add),
                                                label: const Text(
                                                    'Thêm lịch học'))),
                                        const SizedBox(height: 20),
                                        if (_failed ||
                                            _snapshot.loadWarnings.isNotEmpty)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 16),
                                              child: Row(children: [
                                                Expanded(
                                                    child: Text(_failed
                                                        ? (_hasSnapshot
                                                            ? 'Chưa cập nhật được lịch. Đang hiển thị dữ liệu gần nhất.'
                                                            : 'Không tải được lịch. Vui lòng thử lại.')
                                                        : _snapshot.loadWarnings
                                                            .join(' '))),
                                                TextButton(
                                                    onPressed: () => _load(),
                                                    child:
                                                        const Text('Thử lại')),
                                              ])),
                                        if (_loading)
                                          const SizedBox(
                                              height: 160,
                                              child: Center(
                                                  child:
                                                      CircularProgressIndicator()))
                                        else if (_failed && !_hasSnapshot) ...[
                                          _surface(const Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Column(children: [
                                                Icon(Icons.cloud_off_outlined,
                                                    size: 36),
                                                SizedBox(height: 12),
                                                Text(
                                                    'Chưa xác định được lịch hôm nay'),
                                                SizedBox(height: 6),
                                                Text(
                                                    'Tải lại dữ liệu để xem lịch chính xác.',
                                                    textAlign: TextAlign.center)
                                              ]))),
                                          const SizedBox(height: 24),
                                          _tools(),
                                        ] else if (viewport.maxWidth >= 850)
                                          Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                    flex: 2, child: _agenda()),
                                                const SizedBox(width: 32),
                                                Expanded(
                                                    child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 12),
                                                        child: _tools())),
                                              ])
                                        else ...[
                                          _agenda(),
                                          const SizedBox(height: 28),
                                          _tools()
                                        ],
                                      ]),
                                ))
                              ]),
                        ),
                      ))),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: ValueListenableBuilder<bool>(
                      valueListenable: assistantDialog,
                      builder: (context, chatOpen, _) => NavigationBar(
                            height: 76,
                            selectedIndex: chatOpen ? 3 : _activeTab,
                            onDestinationSelected: (index) {
                              if (index == 3) {
                                assistantDialog.value = true;
                                return;
                              }
                              assistantDialog.value = false;
                              if (index == 1) {
                                setState(() {
                                  _activeTab = 1;
                                  _calendarTab ??=
                                      const ViewScheduleScreen(embedded: true);
                                });
                                return;
                              }
                              if (index == 0) {
                                setState(() => _activeTab = 0);
                                _load(showLoader: false);
                                return;
                              }
                              if (index == 2) {
                                _open(const TasksScreen());
                                return;
                              }
                              _open(index == 2
                                  ? const TasksScreen()
                                  : const SettingsScreen());
                            },
                            destinations: const [
                              NavigationDestination(
                                  icon: Icon(Icons.home_outlined),
                                  selectedIcon: Icon(Icons.home_rounded),
                                  label: 'Trang chủ'),
                              NavigationDestination(
                                  icon: Icon(Icons.calendar_month_outlined),
                                  label: 'Lịch học'),
                              NavigationDestination(
                                  icon: Icon(Icons.checklist_rounded),
                                  label: 'Công việc'),
                              NavigationDestination(
                                  icon: Icon(Icons.forum_outlined),
                                  selectedIcon: Icon(Icons.forum_rounded),
                                  label: 'Chat AI'),
                              NavigationDestination(
                                  icon: Icon(Icons.tune_rounded),
                                  label: 'Cài đặt'),
                            ],
                          )))),
        ),
      );
}
