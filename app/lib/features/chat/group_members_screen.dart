import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/chat_format.dart';
import '../../core/utils/profile_navigation.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../data/dtos/dtos.dart';
import '../../models/conversation.dart';
import 'add_member_sheet.dart';
import 'chat_navigation.dart';

/// Dedicated participants screen for a group. Shows the member list with
/// the real photo/nickname; tapping a member opens their profile (the same
/// behavior as every other MATRIX surface). A simple back arrow returns to
/// the group profile (Etapa 6).
class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({super.key, required this.args});

  final GroupMembersRouteArgs args;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  List<GroupMemberInfoModel> _members = const [];
  List<GroupMemberInfoModel> _bannedMembers = const [];
  bool _loading = true;
  String? _error;
  String _groupName = '';
  String? _ownerId;
  StreamSubscription<GroupUpdatedEvent>? _groupSub;
  StreamSubscription<GroupDeletedEvent>? _groupDeletedSub;

  AppState? _resolvedState;
  AppState? get _state => _resolvedState;
  String get _groupId => widget.args.groupId;

  bool get _isOwner {
    final me = _resolvedState?.currentUser?.id;
    return _ownerId != null &&
        _ownerId!.isNotEmpty &&
        me != null &&
        _ownerId == me;
  }

  @override
  void initState() {
    super.initState();
    _groupName = widget.args.groupName;
    _ownerId = widget.args.ownerId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.maybeOf(context);
    if (_resolvedState != state) {
      _resolvedState = state;
      _groupSub?.cancel();
      _groupSub = state?.onGroupUpdated.listen(_onGroupUpdated);
      _groupDeletedSub?.cancel();
      _groupDeletedSub = state?.onGroupDeleted.listen(_onGroupDeleted);
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    _groupDeletedSub?.cancel();
    super.dispose();
  }

  /// The session user LOST ACCESS to this group (realtime — the owner
  /// permanently deleted it or the user left from another device). Close the
  /// participants screen.
  void _onGroupDeleted(GroupDeletedEvent event) {
    if (!mounted) return;
    if (event.groupId != _groupId) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          event.groupName.isEmpty
              ? 'Você não faz mais parte deste grupo.'
              : '"${event.groupName}" já não está disponível.',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  Future<void> _load() async {
    final state = _state;
    if (state == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await state.fetchGroupInfo(_groupId);
      if (!mounted) return;
      setState(() {
        _members = info.members;
        _bannedMembers = info.bannedMembers;
        _groupName = info.group.name;
        _ownerId = info.group.createdById;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar os participantes.';
      });
    }
  }

  void _onGroupUpdated(GroupUpdatedEvent event) {
    if (!mounted) return;
    if (event.group.id != _groupId) return;
    setState(() {
      _groupName = event.group.name;
      _ownerId = event.group.createdById;
    });
    // Membership changed (someone was banned/unbanned on another device).
    // Refresh the active + banned lists so the section stays live; only if
    // the banned set actually differs to avoid refetch spam.
    final currentBanned = _bannedMembers.map((m) => m.id).toSet();
    if (event.bannedUserIds.length != currentBanned.length ||
        event.bannedUserIds.difference(currentBanned).isNotEmpty) {
      _load();
    }
  }

  Future<void> _addMember() async {
    final state = _state;
    if (state == null) return;
    final current = state.currentUser;
    if (current == null) return;
    final existingIds = _members.map((m) => m.id).toSet();
    final chosen = await showModalBottomSheet<AddMemberResult>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (_) => AddMemberSheet(
        ownerId: current.id,
        existingIds: existingIds,
        bannedIds: _bannedMembers.map((m) => m.id).toSet(),
      ),
    );
    if (chosen == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.addGroupMember(_groupId, chosen.userId);
      await _load();
      messenger.showSnackBar(
        SnackBar(
            content:
                Text('${displayNickname(chosen.nickname)} entrou no grupo.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível adicionar o membro.')),
      );
    }
  }

  /// Opens the participant's personal mini menu (bottom sheet): "Ver perfil"
  /// (existing behavior) plus "Sair do grupo" for the SESSION user when they
  /// are an active non-owner member. "Sair do grupo" affects the CURRENT
  /// user — never the tapped participant.
  Future<void> _showParticipantMenu(GroupMemberInfoModel member) async {
    final state = _state;
    if (state == null) return;
    final me = state.currentUser;
    final canLeave = me != null && _ownerId != null && me.id != _ownerId;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _ParticipantMiniMenu(
        member: member,
        canLeave: canLeave,
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'profile':
        openProfileById(
          context,
          id: member.id,
          nickname: member.nickname,
        );
      case 'leave':
        await _confirmLeaveGroup();
    }
  }

  /// SAIR DO GRUPO — removes the SESSION user from this group only. The
  /// group keeps existing for the other members. The server re-validates
  /// membership and rejects the OWNER (a group must never be orphaned).
  Future<void> _confirmLeaveGroup() async {
    final state = _state;
    if (state == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bluishBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          side: BorderSide(color: AppColors.deepBlue),
        ),
        title: Text(
          'Sair do grupo?',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite),
        ),
        content: Text(
          'Você sairá de "$_groupName". O grupo continuará existindo para '
          'os outros participantes e você não receberá mais as mensagens.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: TextStyle(color: AppColors.holographicBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Sair', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await state.leaveGroup(_groupId);
    if (!mounted) return;
    if (ok) {
      // The server removed the session user; pop every group surface. The
      // realtime `chat_group_deleted` frame also covers other devices.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você saiu do grupo.')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível sair do grupo.')),
      );
    }
  }

  Widget _memberTile(GroupMemberInfoModel m) {
    final isOwner = m.isOwner || (_ownerId != null && m.id == _ownerId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _showParticipantMenu(m),
      leading: UserAvatar(
        name: m.nickname,
        seed: m.nickname,
        imageUrl: m.avatarUrl,
        size: 48,
      ),
      title: Text(
        displayNickname(m.nickname),
        style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
      ),
      trailing: isOwner
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.holographicBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.holographicBlue.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'Dono do grupo',
                style: AppTextStyles.caption
                    .copyWith(fontSize: 11, color: AppColors.holographicBlue),
              ),
            )
          : null,
    );
  }

  /// A currently-BANNED participant tile (owner view). Banned users are NOT
  /// active members — they never appear in the regular list; this section
  /// lets the owner unban them (server-validated) so they can be re-added.
  Widget _bannedMemberTile(GroupMemberInfoModel m) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(
        name: m.nickname,
        seed: m.nickname,
        imageUrl: m.avatarUrl,
        size: 48,
      ),
      title: Text(
        displayNickname(m.nickname),
        style: AppTextStyles.body.copyWith(
          color: AppColors.techWhite.withValues(alpha: 0.7),
        ),
      ),
      subtitle: Text(
        'banido(a)',
        style: AppTextStyles.caption.copyWith(
          fontSize: 11,
          color: AppColors.error,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: _isOwner
          ? OutlinedButton(
              onPressed: () => _unbanMember(m),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.holographicBlue,
                side: BorderSide(color: AppColors.holographicBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Text(
                'DESBANIR',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }

  /// Owner-only unban (server re-validates). After success the banned member
  /// becomes an active member again and the list reloads.
  Future<void> _unbanMember(GroupMemberInfoModel banned) async {
    final state = _state;
    if (state == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await state.unbanGroupMember(_groupId, banned.id);
    if (!mounted) return;
    if (ok) {
      await _load();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${displayNickname(banned.nickname)} foi desbanido e voltou ao grupo.',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível desbanir o usuário.'),
        ),
      );
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: HudLabel(text: 'CARREGANDO...', dot: true));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: 'TENTAR NOVAMENTE',
                expanded: false,
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceLg,
        vertical: AppDimensions.spaceLg,
      ),
      itemCount: _members.length + (_bannedMembers.isEmpty ? 1 : 2),
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        final activeEnd = _members.length;
        if (i == 0) {
          return _isOwner
              ? MatrixButton(
                  label: 'ADICIONAR MEMBRO',
                  expanded: true,
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: _addMember,
                )
              : const SizedBox.shrink();
        }
        if (i <= activeEnd) {
          return _memberTile(_members[i - 1]);
        }
        return _bannedSection();
      },
    );
  }

  /// BANNED participants section header + tiles. Only owner sees the header
  /// context (regular members only see their own active list); the tiles
  /// carry the "banido(a)" subtitle and DESBANIR action.
  Widget _bannedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_bannedMembers.isNotEmpty) ...[
          const SizedBox(height: AppDimensions.spaceMd),
          Text(
            'BANIDOS',
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: AppColors.error.withValues(alpha: 0.9),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceXs),
          for (final m in _bannedMembers) _bannedMemberTile(m),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: AppColors.absoluteBlack,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: BackButton(
          color: AppColors.holographicBlue,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text(
          _groupName.isEmpty ? 'Participantes' : _groupName,
          style: AppTextStyles.hud.copyWith(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }
}

/// Participant mini menu — opened when tapping a member in the group's
/// participants screen. Shows the tapped participant's identity and the
/// existing "Ver perfil" action; "Sair do grupo" is added for the SESSION
/// user (an active NON-owner member). The leave action ALWAYS affects the
/// session user — never the tapped participant.
class _ParticipantMiniMenu extends StatelessWidget {
  const _ParticipantMiniMenu({
    required this.member,
    required this.canLeave,
  });

  final GroupMemberInfoModel member;
  final bool canLeave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bluishBlack,
          borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (member.nickname.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spaceLg,
                    vertical: AppDimensions.spaceSm,
                  ),
                  child: Text(
                    displayNickname(member.nickname),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.hud
                        .copyWith(fontSize: 14, color: AppColors.techWhite),
                  ),
                ),
              const SizedBox(height: AppDimensions.spaceSm),
              _ParticipantMenuItem(
                icon: Icons.person_outline_rounded,
                label: 'Ver perfil',
                color: AppColors.holographicBlue,
                onTap: () => Navigator.of(context).pop('profile'),
              ),
              if (canLeave) ...[
                Divider(
                  height: AppDimensions.spaceLg,
                  thickness: 1,
                  color: AppColors.deepBlue.withValues(alpha: 0.5),
                ),
                _ParticipantMenuItem(
                  icon: Icons.exit_to_app_rounded,
                  label: 'Sair do grupo',
                  color: AppColors.error,
                  onTap: () => Navigator.of(context).pop('leave'),
                ),
              ],
              const SizedBox(height: AppDimensions.spaceXs),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantMenuItem extends StatelessWidget {
  const _ParticipantMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.holographicBlue;
    return Material(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        leading: Icon(icon, color: accent, size: 24),
        title: Text(
          label,
          style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
        ),
        onTap: onTap,
      ),
    );
  }
}
