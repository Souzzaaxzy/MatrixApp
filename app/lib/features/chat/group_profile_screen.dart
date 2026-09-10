import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/dtos/dtos.dart';
import '../../data/repositories/repositories.dart';
import '../../models/conversation.dart';
import 'chat_navigation.dart';

class GroupProfileScreen extends StatefulWidget {
  const GroupProfileScreen({super.key, required this.args});

  final GroupProfileRouteArgs args;

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  String? _name;
  String? _avatarUrl;
  String _description = '';
  String? _ownerId;
  int _memberCount = 0;
  List<GroupMemberInfoModel> _members = const[];
  bool _loading = true;
  String? _error;
  StreamSubscription<GroupUpdatedEvent>? _groupSub;

  String get _groupId => widget.args.groupId;

  @override
  void initState() {
    super.initState();
    _name = widget.args.initialName;
    _avatarUrl = widget.args.initialAvatarUrl;
    _description = widget.args.initialDescription;
    _ownerId = widget.args.initialOwnerId;
    _memberCount = widget.args.initialMemberCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.maybeOf(context);
    if (state != null && _groupSub == null) {
      _groupSub = state.onGroupUpdated.listen(_onGroupUpdated);
    }
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppStateScope.maybeOf(context;
    if (state == null) return;
    try {
      final info = await state.fetchGroupInfo(_groupId);
      if (!mounted) return;
      setState(() {
        _name = info.group.name;
        _avatarUrl = info.group.avatarUrl;
        _description = info.group.description;
        _ownerId = info.group.createdById;
        _memberCount = info.group.memberCount;
        _members = info.members;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Não foi possível carregar o grupo.';
      });
    }
  }

  void _onGroupUpdated(GroupUpdatedEvent event) {
    if (!mounted) return;
    if (event.group.id != _groupId) return;
    setState(() {
      _name = event.group.name;
      _avatarUrl = event.group.avatarUrl;
      _description = event.group.description;
      _ownerId = event.group.createdById;
      _memberCount = event.group.memberCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: AppColors.absoluteBlack,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text('Grupo', style: AppTextStyles.hud.copyWith(fontSize: 16)),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: HudLabel(text: 'CARREGANDO...', dot: true));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: 'TENTAR NOVAMENTE',
                expanded: false,
                onPressed: () {
                  setState(() { _loading = true; _error = null; });
                  _load();
                },
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.spaceLg),
      children: [
        const SizedBox(height: 8),
        Center(
          child: _GroupAvatar(url: _avatarUrl, name: _name ?? '', size: 104),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(_name ?? '', textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(color: AppColors.techWhite),
        ),
        if (_description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(_description!.trim(), textAlign: TextAlign.center,
                style: AppTextStyles.bodyMuted,
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${_memberCount} membro${_memberCount == 1 ? '' : 's'}',
            style: AppTextStyles.caption.copyWith(color: AppColors.holographicBlue),
          ),
        ),
        const SizedBox(height: AppDimensions.spaceLg),
        Text('Participantes',
            style: AppTextStyles.hud.copyWith(fontSize: 14, color: AppColors.techWhite)),
        const SizedBox(height: AppDimensions.spaceSm),
        if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppDimensions.spaceMd),
            child: Center(
              child: Text('Nenhum participante.', style: AppTextStyles.bodyMuted),
            ),
          )
        else
          ..._members.map(_memberTile).toList(),
      ],
    );
  }

  Widget _memberTile(GroupMemberInfoModel m) {
    final isOwner = m.isOwner || (_ownerId != null && m.id == _ownerId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(
        name: m.nickname,
        seed: m.nickname,
        imageUrl: m.avatarUrl,
        size: 44,
      ),
      title: Text(m.nickname, style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
      ),
      trailing:isOwner
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.holographicBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.holographicBlue.withValues(alpha: 0.5),
                ),
              ),
              child: Text('Dono do grupo',
                  style: AppTextStyles.caption.copyWith(
                      fontSize: 11, color: AppColors.holographicBlue),
              ),
            )
          : null,
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.url, required this.name, required this.size});

  final String? url;

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            url!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.deepBlue, AppColors.holographicBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? 'G' : name.substring(0, 1).toUpperCase(),
        style: AppTextStyles.hud.copyWith(
            color: AppColors.techWhite, fontSize: size * 0.34),
      ),
    );
  }
}
