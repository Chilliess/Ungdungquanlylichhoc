import 'package:flutter/material.dart';
import '../services/learning_store.dart';
import '../screen/confirm_action.dart';

class LearningSummary extends StatelessWidget {
  const LearningSummary({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: learningStore,
      builder: (context, _) {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day - now.weekday + 1);
        final end = start.add(const Duration(days: 7));
        bool inWeek(String date) {
          final d = DateTime.parse(date);
          return !d.isBefore(start) && d.isBefore(end);
        }

        final planned = learningStore.blocks
            .where((b) => inWeek(b['start']))
            .fold<int>(
                0,
                (sum, b) =>
                    sum +
                    DateTime.parse(b['end'])
                        .difference(DateTime.parse(b['start']))
                        .inMinutes);
        final actual = learningStore.logs
            .where((b) => inWeek(b['date']))
            .fold<int>(0, (sum, b) => sum + (b['minutes'] as int));
        final due = learningStore.pending
            .where((t) => DateTime.parse(t['deadline']).isBefore(end))
            .fold<int>(
                0,
                (sum, t) =>
                    sum +
                    ((t['minutes'] as int) - learningStore.actualFor(t['id']))
                        .clamp(0, 100000));
        final bySubject = <String, int>{};
        for (final log in learningStore.logs.where((b) => inWeek(b['date']))) {
          bySubject.update(
              log['subject'] as String, (v) => v + (log['minutes'] as int),
              ifAbsent: () => log['minutes'] as int);
        }
        return Card(
            elevation: 0,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tự học · Tuần hiện tại',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Text(
                          'Dự kiến: $planned phút  •  Đã ghi nhận: $actual phút'),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                          value:
                              (actual / learningStore.goalMinutes).clamp(0, 1)),
                      TextButton(
                          onPressed: () async {
                            final goal = await showDialog<int>(
                                context: context,
                                builder: (c) => SimpleDialog(
                                        title: const Text(
                                            'Mục tiêu tự học mỗi tuần'),
                                        children: [
                                          for (final hours in [
                                            2,
                                            5,
                                            10,
                                            15,
                                            20
                                          ])
                                            SimpleDialogOption(
                                                onPressed: () => Navigator.pop(
                                                    c, hours * 60),
                                                child: Text('$hours giờ')),
                                        ]));
                            if (goal == null ||
                                !context.mounted ||
                                !await confirmAction(context,
                                    message:
                                        'Đổi mục tiêu thành ${goal ~/ 60} giờ mỗi tuần?')) {
                              return;
                            }
                            final previous = learningStore.goalMinutes;
                            learningStore.goalMinutes = goal;
                            try {
                              await learningStore.save();
                            } catch (_) {
                              learningStore.goalMinutes = previous;
                            }
                          },
                          child: Text(
                              'Mục tiêu: ${learningStore.goalMinutes ~/ 60} giờ / tuần')),
                      if (due > learningStore.goalMinutes)
                        Text(
                            'Khối lượng cần hoàn thành trước cuối tuần ($due phút) vượt mục tiêu tự học. Cân nhắc ưu tiên lại công việc.',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      for (final entry in bySubject.entries)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('${entry.key}: ${entry.value} phút')),
                      if (bySubject.isEmpty)
                        const Text(
                            'Bắt đầu phiên tập trung trong Công việc để ghi nhận thời gian thực tế.'),
                    ])));
      });
}
