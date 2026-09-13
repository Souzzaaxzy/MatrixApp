import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Shared swipe-to-reply gesture (DM + group).
///
/// Mirrors the exact private-chat behavior so both surfaces feel identical:
///  * OTHER users' messages drag left→right toward the reply affordance.
///  * MY OWN messages drag right→left (the row is flipped so both sides
///    slide toward the arrow).
///  * The drag is capped at [replySwipeThreshold] (the bubble can never be
///    dragged off-screen); releasing past [replyDragThreshold] activates the
///    reply composer; otherwise the bubble snaps back with a short ease-out.
///
/// Each bubble carries its OWN drag state ([_ReplySwipeState]) so swiping one
/// never affects its siblings. Only horizontal drags are consumed (and only
/// past a small dead zone), so vertical scroll of the message list is never
/// blocked — the chat never fights the user's vertical scrolling.
const double replySwipeThreshold = 96.0;
const double replyDragThreshold = 90.0;

class ReplySwipe extends StatefulWidget {
  const ReplySwipe({
    super.key,
    required this.mine,
    required this.bubble,
    required this.onStartReply,
    required this.onLongPress,
    this.replySelected = false,
    this.leading,
  });

  /// Whether the bubble belongs to the SESSION user (drives the drag
  /// direction: mine right→left, theirs left→right).
  final bool mine;

  /// The message bubble (content already rendered by the caller).
  final Widget bubble;

  /// Called when a horizontal drag crosses the threshold.
  final VoidCallback onStartReply;

  /// Forwarded to the bubble's underlying long-press handler.
  final VoidCallback onLongPress;

  /// True while this message is the currently-selected reply target — the
  /// bubble stays pinned at the threshold until deselected.
  final bool replySelected;

  /// Optional widget rendered to the LEFT of the reply affordance (the peer
  /// avatar in DM chats). Group chats render their avatar outside this
  /// widget, so they pass null and keep their own layout.
  final Widget? leading;

  @override
  State<ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<ReplySwipe> {
  /// Current displacement magnitude (0 when idle/selected). Direction is
  /// implied by the owner — theirs drags left→right (positive), mine drags
  /// right→left toward the reply affordance (also positive after flipping).
  double _dx = 0;

  bool get _selected => widget.replySelected;

  @override
  void didUpdateWidget(covariant ReplySwipe old) {
    super.didUpdateWidget(old);
    // When the parent marks this message as the reply target, settle at the
    // pinned offset; when it deselects, snap back.
    if (widget.replySelected != old.replySelected) {
      _dx = widget.replySelected ? replySwipeThreshold : 0;
    }
  }

  void _endDragAndMaybeSelect() {
    if (_dx >= replyDragThreshold) {
      widget.onStartReply();
    } else {
      setState(() => _dx = 0); // snap back
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    // Flip the drag so BOTH sides swipe toward the arrow (theirs left→right,
    // mine right→left).
    final dir = mine ? -1.0 : 1.0;
    return GestureDetector(
      // Long-press on a message bubble opens the contextual actions menu
      // (Responder / Excluir / Excluir para todos / Banir usuário).
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: (details) {
        if (_selected) return; // already replying another message
        setState(() {
          _dx = (_dx + details.delta.dx * dir).clamp(0.0, replySwipeThreshold);
        });
      },
      onHorizontalDragEnd: (_) => _endDragAndMaybeSelect(),
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: AnimatedContainer(
        duration: _selected ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(_dx * dir, 0, 0),
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  // Profile picture of the OTHER sender (received messages
                  // only, rendered before the affordance — mirrors the DM
                  // layout: [FOTO] [↩] [MENSAGEM]).
                ],
                // Reply affordance that lights up as the swipe approaches.
                AnimatedOpacity(
                  opacity: _selected || _dx > 8 ? 0.9 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: const Icon(
                    Icons.reply_rounded,
                    color: AppColors.electricBlue,
                    size: 18,
                  ),
                ),
                widget.bubble,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
