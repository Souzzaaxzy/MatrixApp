import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/akame_message_bubble.dart';
import '../../core/widgets/glow_container.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/neon_icon_button.dart';

/// Futuristic Akame chat interface.
///
/// Messages are mocked in Phase 1. The send path is isolated so a real
/// AI API can replace the mock later without UI changes.
class AkameScreen extends StatefulWidget {
  const AkameScreen({super.key});

  @override
  State<AkameScreen> createState() => _AkameScreenState();
}

class _AkameScreenState extends State<AkameScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {}

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    AppStateScope.of(context).sendAkameMessage(text);
    _controller.clear();
    setState(() => _isTyping = true);
    _scrollToBottom();
    // Hide typing indicator after the simulated reply lands.
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() => _isTyping = false);
        _scrollToBottom();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final messages = state.akameMessages;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: Column(
        children: [
          _AkameHeader(),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlowContainer(
                          glow: Glow.medium,
                          color: AppColors.glowSmall,
                          background: AppColors.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
                          padding: const EdgeInsets.all(AppDimensions.spaceXl),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: AppColors.electricBlue, size: 36),
                        ),
                        const SizedBox(height: AppDimensions.spaceLg),
                        Text('AKAME READY', style: AppTextStyles.h2),
                        const SizedBox(height: AppDimensions.spaceSm),
                        Text('Comece uma conversa.', style: AppTextStyles.bodyMuted),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spaceLg,
                      vertical: AppDimensions.spaceLg,
                    ),
                    itemCount: messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == messages.length) return _TypingIndicator();
                      final m = messages[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppDimensions.spaceMd),
                        child: AkameMessageBubble(
                          text: m.text,
                          fromUser: m.fromUser,
                          timestamp: relativeTime(m.createdAt),
                        ),
                      );
                    },
                  ),
          ),
          _AkameInputBar(
            controller: _controller,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _AkameHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceLg,
          vertical: AppDimensions.spaceMd,
        ),
        decoration: BoxDecoration(
          color: AppColors.bluishBlack,
          border: Border(
            bottom: BorderSide(color: AppColors.deepBlue, width: 1),
          ),
        ),
        child: Row(
          children: [
            GlowContainer(
              glow: Glow.medium,
              color: AppColors.glowMedium,
              background: AppColors.nightBlue,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              padding: const EdgeInsets.all(AppDimensions.spaceSm),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.electricBlue),
            ),
            const SizedBox(width: AppDimensions.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AKAME', style: AppTextStyles.h3.copyWith(letterSpacing: 2)),
                  const SizedBox(height: 2),
                  const HudLabel(text: 'ONLINE', color: AppColors.success, dot: true),
                ],
              ),
            ),
            const HudLabel(text: 'AKAME CORE', glow: true),
          ],
        ),
      ),
    );
  }
}

class _AkameInputBar extends StatelessWidget {
  const _AkameInputBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceLg,
          vertical: AppDimensions.spaceSm,
        ),
        decoration: BoxDecoration(
          color: AppColors.bluishBlack,
          border: Border(top: BorderSide(color: AppColors.deepBlue, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: AppTextStyles.body,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Escreva uma mensagem...',
                  hintStyle: AppTextStyles.bodyMuted,
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.spaceSm),
            NeonIconButton(
              icon: Icons.send_rounded,
              onPressed: onSend,
              semanticLabel: 'Enviar mensagem',
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppDimensions.spaceMd),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceLg,
          vertical: AppDimensions.spaceMd,
        ),
        decoration: BoxDecoration(
          color: AppColors.nightBlue,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          border: Border.all(
            color: AppColors.electricBlue.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _Dot(delay: i * 0.2),
            );
          }),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delay});
  final double delay;
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppColors.electricBlue,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
