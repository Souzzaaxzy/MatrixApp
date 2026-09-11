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
  bool _loading = true;
  String? _error;
  String _groupName = '';
  String? _ownerId;
  StreamSubscription<GroupUpdatedEvent>? _groupSub;

  AppState? _resolvedState;
  AppState? get _state => _resolvedState;
  String get _groupId => widget.args.groupId;

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
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
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
  }

  Widget _memberTile(GroupMemberInfoModel m) {
    final isOwner = m.isOwner || (_ownerId != null && m.id == _ownerId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => openProfileById(
        context,
        id: m.id,
        nickname: m.nickname,
      ),
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
      itemCount: _members.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) => _memberTile(_members[i]),
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