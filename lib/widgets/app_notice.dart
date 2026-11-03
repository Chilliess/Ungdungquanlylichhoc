import 'dart:async';
import 'package:flutter/material.dart';

/// Shared foreground notices. System reminders retain the OS presentation.
class AppNotice {
  static OverlayEntry? _entry;

  static void show(BuildContext context, SnackBar notice) {
    if (!context.mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry?.remove();
    _entry?.dispose();
    late final OverlayEntry entry;
    entry = OverlayEntry(
        builder: (_) => _NoticeCard(
              notice: notice,
              onDismiss: () {
                if (_entry != entry) return;
                entry.remove();
                entry.dispose();
                _entry = null;
              },
            ));
    _entry = entry;
    overlay.insert(entry);
  }
}

class _NoticeCard extends StatefulWidget {
  const _NoticeCard({required this.notice, required this.onDismiss});
  final SnackBar notice;
  final VoidCallback onDismiss;
  @override
  State<_NoticeCard> createState() => _NoticeCardState();
}

class _NoticeCardState extends State<_NoticeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.notice.duration, _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _animation.reverse();
    }
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -1.3), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: _animation, curve: Curves.easeOutCubic)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: colors.surfaceContainerHigh,
                  elevation: 6,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(18),
                  child: Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                      child: Row(children: [
                        Icon(Icons.notifications_outlined,
                            color: widget.notice.backgroundColor ??
                                colors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                            child: DefaultTextStyle(
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(color: colors.onSurface),
                                child: widget.notice.content)),
                        IconButton(
                            onPressed: _dismiss,
                            tooltip: 'Đóng thông báo',
                            icon: const Icon(Icons.close, size: 20)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
