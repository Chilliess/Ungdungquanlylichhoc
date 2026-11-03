import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A timeline tile that prioritizes readable content within the actual duration.
class LessonEventTile extends StatelessWidget {
  const LessonEventTile({super.key, required this.event, this.eventCount = 1});
  final CalendarEventData<Map<String, dynamic>> event;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final room = event.event?['room']?.toString().trim() ?? '';
    final category = event.event?['category']?.toString().trim() ?? '';
    final notes = event.event?['notes']?.toString().trim() ?? '';
    final start = event.startTime;
    final end = event.endTime;
    final time = start == null || end == null
        ? ''
        : '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}';
    final summary = [
      event.title,
      time,
      if (room.isNotEmpty) 'Địa điểm: $room',
      category,
      notes
    ].where((text) => text.isNotEmpty).join('\n');
    return Semantics(
        label: summary,
        child: Tooltip(
          message: summary,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                    event.color.withValues(alpha: 0.14), colors.surface),
                border: Border(left: BorderSide(color: event.color, width: 4)),
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context);
                final padding = constraints.maxHeight >= 100
                    ? 12.0
                    : constraints.maxHeight >= 48
                        ? 8.0
                        : 3.0;
                final gap = constraints.maxHeight >= 100 ? 8.0 : 4.0;
                final width = (constraints.maxWidth - padding * 2 - 4)
                    .clamp(0.0, double.infinity);
                var remaining = (constraints.maxHeight - padding * 2)
                    .clamp(0.0, double.infinity);
                final titleStyle = theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface);
                final secondaryStyle = theme.textTheme.bodySmall!.copyWith(
                    fontSize: 12, height: 1.25, color: colors.onSurfaceVariant);
                final lineHeight = scale.scale(12) * 1.25;
                final rowHeight = lineHeight.clamp(16.0, double.infinity);
                final showBadge = category.isNotEmpty &&
                    width >= 200 &&
                    remaining >= scale.scale(18);
                final badgeWidth =
                    showBadge ? (width * 0.3).clamp(0.0, 110.0) : 0.0;
                final titleWidth = (width - badgeWidth - (showBadge ? 8 : 0))
                    .clamp(1.0, double.infinity);
                final titleLines = remaining >= scale.scale(72) ? 2 : 1;
                final painter = TextPainter(
                    text: TextSpan(text: event.title, style: titleStyle),
                    textDirection: Directionality.of(context),
                    textScaler: scale,
                    maxLines: titleLines,
                    ellipsis: '…')
                  ..layout(maxWidth: titleWidth);
                final titleHeight = painter.height.clamp(0.0, remaining);
                painter.dispose();
                final children = <Widget>[
                  SizedBox(
                      height: titleHeight,
                      child: ClipRect(
                          child: Row(children: [
                        Expanded(
                            child: Text(event.title,
                                style: titleStyle,
                                maxLines: titleLines,
                                overflow: TextOverflow.ellipsis)),
                        if (showBadge) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                              width: badgeWidth,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: event.color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(5)),
                                child: Text(category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        height: 1,
                                        color: colors.onSurface)),
                              )),
                        ],
                      ]))),
                ];
                remaining -= titleHeight;
                void addLine(IconData icon, String text) {
                  if (text.isEmpty || remaining < rowHeight + gap) return;
                  children.add(SizedBox(height: gap));
                  children.add(SizedBox(
                      height: rowHeight,
                      child: Row(children: [
                        Icon(icon, size: 14, color: colors.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Expanded(
                            child: Text(text,
                                style: secondaryStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                      ])));
                  remaining -= rowHeight + gap;
                }

                addLine(Icons.schedule_outlined, time);
                addLine(Icons.location_on_outlined, room);
                if (!showBadge) addLine(Icons.sell_outlined, category);
                if (eventCount > 1) {
                  addLine(Icons.event_note, '+${eventCount - 1} lịch cùng giờ');
                }
                if (notes.isNotEmpty && remaining >= lineHeight + gap) {
                  final lines =
                      ((remaining - gap) / lineHeight).floor().clamp(1, 2);
                  children.add(SizedBox(height: gap));
                  children.add(Text(notes,
                      maxLines: lines,
                      style: secondaryStyle,
                      overflow: TextOverflow.ellipsis));
                }
                return Padding(
                    padding: EdgeInsets.fromLTRB(
                        padding + 4, padding, padding, padding),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: children));
              }),
            ),
          ),
        ));
  }
}
