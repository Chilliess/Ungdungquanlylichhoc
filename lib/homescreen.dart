import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/home_models.dart';
import 'models/schedule_recurrence.dart';
import 'screen/info_account.dart';
import 'screen/schedule_announcement.dart';
import 'screen/settings.dart';
import 'screen/statistical.dart';
import 'screen/subject_management_screen.dart';
import 'screen/view_schedule_screen.dart';
import 'services/home_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.service});
  final HomeService? service;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeService _service = widget.service ?? HomeService();
  HomeSnapshot _snapshot = const HomeSnapshot.empty();
  bool _loading = true, _failed = false;
  DateTime? _selectedUpcomingDate;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => _loading = true);
    try {
      final data = await _service.loadSnapshot();
      if (mounted) {
        setState(() {
          _snapshot = data;
          final now = DateTime.now();
          _selectedUpcomingDate ??= data.upcomingLessons.isEmpty
              ? DateTime(now.year, now.month, now.day)
              : data.upcomingLessons.first.date;
          _loading = false;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
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
    final name = _snapshot.username?.trim() ?? '';
    return Row(children: [
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name.isEmpty ? 'Xin chào!' : 'Xin chào, $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(DateTime.now()),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
      IconButton(
          key: const ValueKey('home-reminders'),
          tooltip: 'Nhắc nhở',
          onPressed: () => _open(const ScheduleAnnouncementScreen()),
          icon: const Icon(Icons.notifications_none_outlined)),
      IconButton(
          tooltip: 'Tài khoản',
          onPressed: () => _open(const AccountScreen()),
          icon: const Icon(Icons.account_circle_outlined)),
    ]);
  }

  Widget _surface(Widget child) => Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
    if (date != null && mounted) setState(() => _selectedUpcomingDate = date);
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
        Text('Quản lý', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _surface(Column(children: [
          _tool(Icons.school_outlined, 'Môn học',
              const SubjectManagementScreen()),
        ])),
      ]);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        body: SafeArea(
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
                        onRefresh: () => _load(showLoader: false),
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
                                      const Divider(height: 1),
                                      const SizedBox(height: 20),
                                      Align(
                                          alignment: Alignment.centerLeft,
                                          child: FilledButton.icon(
                                              key: const ValueKey(
                                                  'home-add-lesson'),
                                              onPressed: () => _open(
                                                  const ViewScheduleScreen(
                                                      openEditorOnStart: true)),
                                              icon: const Icon(Icons.add),
                                              label:
                                                  const Text('Thêm lịch học'))),
                                      const SizedBox(height: 20),
                                      if (_failed)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 16),
                                            child: Row(children: [
                                              const Expanded(
                                                  child: Text(
                                                      'Không tải được lịch. Vui lòng thử lại.')),
                                              TextButton(
                                                  onPressed: () => _load(),
                                                  child: const Text('Thử lại')),
                                            ])),
                                      if (_loading)
                                        const SizedBox(
                                            height: 160,
                                            child: Center(
                                                child:
                                                    CircularProgressIndicator()))
                                      else if (viewport.maxWidth >= 850)
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
                                                          const EdgeInsets.only(
                                                              top: 12),
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
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant))),
          child: Stack(children: [
            NavigationBar(
                selectedIndex: 0,
                onDestinationSelected: (index) {
                  if (index == 0) {
                    _load(showLoader: false);
                    return;
                  }
                  _open([
                    const ViewScheduleScreen(),
                    const StatisticalScreen(),
                    const SettingsScreen()
                  ][index - 1]);
                },
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Trang chủ'),
                  NavigationDestination(
                      icon: Icon(Icons.calendar_today_outlined),
                      label: 'Lịch học'),
                  NavigationDestination(
                      icon: Icon(Icons.bar_chart_outlined), label: 'Thống kê'),
                  NavigationDestination(
                      icon: Icon(Icons.settings_outlined), label: 'Cài đặt'),
                ]),
            Positioned.fill(
                child: IgnorePointer(
                    child: Row(children: [
              const Expanded(child: SizedBox()),
              VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(context).colorScheme.outlineVariant),
              const Expanded(child: SizedBox()),
              VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(context).colorScheme.outlineVariant),
              const Expanded(child: SizedBox()),
              VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(context).colorScheme.outlineVariant),
              const Expanded(child: SizedBox()),
            ]))),
          ]),
        ),
      );
}
