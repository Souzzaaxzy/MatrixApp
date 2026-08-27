import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/glow_container.dart';
import '../../data/api_config.dart';
import '../../models/friend_request.dart';

/// The big friendship button with the full server-managed state machine:
///
///   SOLICITAR   → tap → sends the request → SOLICITADO
///   SOLICITADO  → tap → CANCELS the request → SOLICITAR
///   AMIGOS      → tap → confirmation modal → NÃO (nothing) / SIM → SOLICITAR
///
/// Every transition is confirmed by the server first (a fresh profile load
/// always reports the persisted state), so closing/reopening the app or
/// screen never desyncs the button. The state is read from the loaded
/// profile's `friendship` — not a local optimistic flag.
class FriendshipButton extends StatefulWidget {
  const FriendshipButton({
    super.key,
    required this.userId,
    required this.nickname,
    required this.friendship,
  });

  final String userId;
  final String nickname;
  final Friendship? friendship;

  @override
  State<FriendshipButton> createState() => _FriendshipButtonState();
}

class _FriendshipButtonState extends State<FriendshipButton> {
  bool _busy = false;

  Friendship get _state => widget.friendship ?? Friendship.none;

  Future<void> _run(Future<void> Function(AppState state) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = AppStateScope.of(context);
    try {
      await action(state);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro de conexão.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleTap() {
    switch (_state) {
      case Friendship.none:
        _run((s) => s.sendFriendRequest(widget.userId));
      case Friendship.outgoingPending:
        _run((s) => s.cancelFriendRequest(widget.userId));
      case Friendship.incomingPending:
        // A request the current user received must be answered in the
        // Atividades tab — tapping here does nothing (kept as a hint).
        break;
      case Friendship.friends:
        _confirmUnfriend();
    }
  }

  Future<void> _confirmUnfriend() async {
    final confirmed = await showUnfriendDialog(context, nickname: widget.nickname);
    if (confirmed != true) return; // NÃO / dismiss → absolutely nothing.
    await _run((s) => s.removeFriend(widget.userId));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: _buildButton(keyName: _state.name),
    );
  }

  Widget _buildButton({required String keyName}) {
    final label = switch (_state) {
      Friendship.none => 'SOLICITAR',
      Friendship.outgoingPending => 'SOLICITADO',
      Friendship.incomingPending => 'SOLICITADO',
      Friendship.friends => 'AMIGOS',
    };
    final icon = switch (_state) {
      Friendship.none => Icons.person_add_rounded,
      Friendship.outgoingPending => Icons.watch_later_rounded,
      Friendship.incomingPending => Icons.call_received_rounded,
      Friendship.friends => Icons.favorite_rounded,
    };
    final isFriends = _state == Friendship.friends;
    final isIncoming = _state == Friendship.incomingPending;

    return _StateButton(
      key: ValueKey(keyName),
      label: label,
      icon: icon,
      isLoading: _busy,
      onPressed: (_busy || isIncoming) ? null : _handleTap,
      variant: isFriends ? _StateButtonVariant.outline : _StateButtonVariant.filled,
    );
  }
}

/// A self-contained neon button with press-scale and dark/light support.
/// Uses the same language as MATRIX's [GlowContainer] + icon + label.
class _StateButton extends StatefulWidget {
  const _StateButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.variant,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final _StateButtonVariant variant;
  final bool isLoading;

  @override
  State<_StateButton> createState() => _StateButtonState();
}

class _StateButtonState extends State<_StateButton> {
  bool _pressing = false;

  bool get _disabled => widget.onPressed == null || widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final isOutline = widget.variant == _StateButtonVariant.outline;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressing = true),
      onTapUp: (_) => setState(() => _pressing = false),
      onTapCancel: () => setState(() => _pressing = false),
      onTap: _disabled ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _pressing ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: GlowContainer(
          glow: _pressing ? Glow.medium : Glow.none,
          background: isOutline
              ? Colors.transparent
              : _disabled
                  ? AppColors.deepBlue.withValues(alpha: 0.5)
                  : AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: isOutline
              ? Border.all(
                  color: AppColors.techWhite.withValues(alpha: 0.4),
                  width: AppDimensions.borderWidthActive,
                )
              : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceXl,
            vertical: AppDimensions.spaceLg,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: double.infinity),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 18, color: AppColors.techWhite),
                const SizedBox(width: AppDimensions.spaceSm),
                if (widget.isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.techWhite),
                    ),
                  )
                else
                  Text(
                    widget.label,
                    style: AppTextStyles.button,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _StateButtonVariant { filled, outline }

/// Opens the MATRIX-styled confirmation for removing a friendship.
///
/// Returns `true` when the user tapped SIM, `false`/null otherwise (NÃO or
/// dismissing the modal) — in which case NOTHING is sent to the server.
/// Uses the user's REAL nickname (never prefixed with '@').
Future<bool?> showUnfriendDialog(
  BuildContext context, {
  required String nickname,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (dialogContext) {
      return _UnfriendDialog(nickname: nickname);
    },
  );
}

class _UnfriendDialog extends StatefulWidget {
  const _UnfriendDialog({required this.nickname});

  final String nickname;

  @override
  State<_UnfriendDialog> createState() => _UnfriendDialogState();
}

class _UnfriendDialogState extends State<_UnfriendDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss(bool result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width * 0.82).clamp(280.0, 420.0);

    return ScaleTransition(
      scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      child: FadeTransition(
        opacity: _controller,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: width,
              margin: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
              padding: const EdgeInsets.all(AppDimensions.spaceXl),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
                border: Border.all(color: AppColors.primaryBlue, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlowContainer(
                    glow: Glow.small,
                    color: AppColors.glowSmall,
                    background: AppColors.nightBlue,
                    borderRadius: BorderRadius.circular(999),
                    padding: const EdgeInsets.all(AppDimensions.spaceLg),
                    child: Icon(Icons.person_remove_rounded,
                        color: AppColors.error, size: 28),
                  ),
                  const SizedBox(height: AppDimensions.spaceXl),
                  Text('Deixar de ser amigo?',
                      style: AppTextStyles.h3, textAlign: TextAlign.center),
                  const SizedBox(height: AppDimensions.spaceMd),
                  Text(
                    'Deixar de ser amigo de ${widget.nickname}?',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMuted,
                  ),
                  const SizedBox(height: AppDimensions.spaceXl),
                  Row(
                    children: [
                      Expanded(
                        child: _DialogButton(
                          label: 'NÃO',
                          variant: _DialogButtonVariant.outline,
                          onPressed: () => _dismiss(false),
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spaceMd),
                      Expanded(
                        child: _DialogButton(
                          label: 'SIM',
                          variant: _DialogButtonVariant.filled,
                          onPressed: () => _dismiss(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _DialogButtonVariant { filled, outline }

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.label,
    required this.variant,
    required this.onPressed,
  });

  final String label;
  final _DialogButtonVariant variant;
  final VoidCallback onPressed;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final isOutline = widget.variant == _DialogButtonVariant.outline;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressing = true),
      onTapUp: (_) => setState(() => _pressing = false),
      onTapCancel: () => setState(() => _pressing = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressing ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: GlowContainer(
          glow: _pressing ? Glow.medium : Glow.none,
          background: isOutline ? Colors.transparent : AppColors.error,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: isOutline
              ? Border.all(color: AppColors.deepBlue, width: 1)
              : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceLg,
            vertical: AppDimensions.spaceLg,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: double.infinity),
            child: Center(
              child: Text(
                widget.label,
                style: AppTextStyles.button,
              ),
            ),
          ),
        ),
      ),
    );
  }
}