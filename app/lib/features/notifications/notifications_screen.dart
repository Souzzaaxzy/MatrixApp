import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/date_utils.dart' as matrix;
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_card.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../models/matrix_notification.dart';

/// Notifications tab — persistent server-side notifications.
///
/// LIKE / COMMENT rows navigate to the post; a PENDING FRIEND_REQUEST
/// renders the actionable Aceitar / Recusar card inside the same list.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _requested = false;
  String? _error;
  final Set<String> _acting = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await AppStateScope.of(context).loadNotifications();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Sem conexão com o MATRIX.');
    }
  }

  Future<void> _respond(String requestId, {required bool accept}) async {
    setState(() => _acting.add(requestId));
    final state = AppStateScope.of(context);
    try {
      if (accept) {
        await state.acceptFriendRequest(requestId);
      } else {
        await state.rejectFriendRequest(requestId);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro de conexão.')),
      );
    } finally {
      if (mounted) setState(() => _acting.remove(requestId));
    }
  }

  void _open(MatrixNotification notification) {
    AppStateScope.of(context).markNotificationRead(notification.id);
    if (notification.postId != null) {
      Navigator.of(context)
          .pushNamed(AppRoutes.postDetail, arguments: notification.postId);
    } else {
      Navigator.of(context)
          .pushNamed(AppRoutes.profile, arguments: notification.actorUsername);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final notifications = state.notifications;
    final loading = state.isLoadingNotifications && notifications.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: RefreshIndicator(
        color: AppColors.electricBlue,
        backgroundColor: AppColors.nightBlue,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: AppColors.absoluteBlack,
              surfaceTintColor: Colors.transparent,
              title: Text('ATIVIDADES',
                  style: AppTextStyles.title.copyWith(fontSize: 18)),
              actions: [
                if (state.unreadNotifications > 0)
                  IconButton(
                    tooltip: 'Marcar todas como lidas',
                    icon: Icon(Icons.checklist_rounded,
                        color: AppColors.holographicBlue),
                    onPressed: state.markAllNotificationsRead,
                  ),
              ],
            ),
            if (loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: HudLabel(text: 'LOADING...', dot: true)),
              )
            else if (_error != null && notifications.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'CONNECTION ERROR',
                  hud: 'OFFLINE',
                  subtitle: _error!,
                  action: MatrixButton(
                    label: 'Tentar novamente',
                    icon: Icons.refresh_rounded,
                    onPressed: _load,
                  ),
                ),
              )
            else if (notifications.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'ALL CLEAR',
                  hud: 'NO SIGNAL',
                  subtitle: 'Nenhuma notificação por aqui.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spaceLg,
                ),
                sliver: SliverList.builder(
                  itemCount: notifications.length,
                  itemBuilder: (context, i) {
                    final n = notifications[i];
                    if (n.type == 'FRIEND_REQUEST' &&
                        n.friendRequestStatus == 'PENDING' &&
                        n.friendRequestId != null) {
                      return _FriendRequestCard(
                        notification: n,
                        busy: _acting.contains(n.friendRequestId),
                        onAccept: () => _respond(n.friendRequestId!, accept: true),
                        onReject: () => _respond(n.friendRequestId!, accept: false),
                      );
                    }
                    return _NotificationTile(
                      notification: n,
                      onTap: () => _open(n),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppDimensions.spaceXxl),
            ),
          ],
        ),
      ),
    );
  }
}

/// Regular notification row: avatar, actor, description, relative time and
/// an unread glow dot.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final MatrixNotification notification;
  final VoidCallback onTap;

  static String description(MatrixNotification n) {
    switch (n.type) {
      case 'LIKE':
        return 'curtiu sua publicação.';
      case 'COMMENT':
        return 'comentou na sua publicação.';
      case 'FRIEND_REQUEST':
        return 'enviou uma solicitação de amizade.';
      case 'FRIEND_ACCEPTED':
        // Rendered by the dedicated spans in [build]: "Agora você e @x
        // são amigos."
        return 'são amigos.';
      default:
        return 'interagiu com você.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return MatrixCard(
      margin: const EdgeInsets.symmetric(vertical: AppDimensions.spaceSm),
      onTap: onTap,
      border: Border.all(
        color: n.read
            ? AppColors.deepBlue.withValues(alpha: 0.5)
            : AppColors.primaryBlue,
        width: n.read
            ? AppDimensions.borderWidthThin
            : AppDimensions.borderWidthActive,
      ),
      child: Row(
        children: [
          if (!n.read)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.electricBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.glowSmall, blurRadius: 8),
                ],
              ),
            ),
          if (!n.read) const SizedBox(width: AppDimensions.spaceSm),
          UserAvatar(
            name: n.actorName,
            seed: n.actorUsername,
            imageUrl: n.actorAvatarUrl,
            size: 42,
          ),
          const SizedBox(width: AppDimensions.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: AppTextStyles.bodyMuted,
                    children: n.type == 'FRIEND_ACCEPTED'
                        ? [
                            const TextSpan(text: 'Agora você e '),
                            TextSpan(
                              text: '@${n.actorUsername}',
                              style:
                                  AppTextStyles.h3.copyWith(fontSize: 14),
                            ),
                            const TextSpan(text: ' são amigos.'),
                          ]
                        : [
                            TextSpan(
                              text: '@${n.actorUsername}',
                              style:
                                  AppTextStyles.h3.copyWith(fontSize: 14),
                            ),
                            TextSpan(text: ' ${description(n)}'),
                          ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXs),
                Text(
                  matrix.relativeTime(n.createdAt),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The actionable friend request card: avatar, sender nickname and the two
/// Aceitar / Recusar buttons — both execute real server actions.
class _FriendRequestCard extends StatelessWidget {
  const _FriendRequestCard({
    required this.notification,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final MatrixNotification notification;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return MatrixCard(
      margin: const EdgeInsets.symmetric(vertical: AppDimensions.spaceSm),
      padding: const EdgeInsets.all(AppDimensions.spaceXl),
      border: const Border.fromBorderSide(
        BorderSide(
          color: AppColors.primaryBlue,
          width: AppDimensions.borderWidthActive,
        ),
      ),
      child: Column(
        children: [
          UserAvatar(
            name: n.actorName,
            seed: n.actorUsername,
            imageUrl: n.actorAvatarUrl,
            size: 64,
            ring: true,
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '@',
                  style: TextStyle(
                    color: AppColors.holographicBlue,
                    fontSize: 16,
                    shadows: const [
                      Shadow(color: AppColors.electricBlue, blurRadius: 8),
                    ],
                  ),
                ),
                TextSpan(
                  text: n.actorUsername,
                  style: AppTextStyles.h2.copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceXs),
          Text(
            'enviou uma solicitação de amizade.',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          MatrixButton(
            label: 'Aceitar',
            icon: Icons.check_rounded,
            expanded: true,
            isLoading: busy,
            onPressed: busy ? null : onAccept,
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          MatrixButton(
            label: 'Recusar',
            icon: Icons.close_rounded,
            variant: MatrixButtonVariant.outline,
            expanded: true,
            onPressed: busy ? null : onReject,
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          Text(
            matrix.relativeTime(n.createdAt),
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
