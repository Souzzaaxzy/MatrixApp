import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/gallery_picker.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/utils/chat_format.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../data/dtos/dtos.dart';
import '../../app/routes.dart';
import '../../data/services.dart';
import '../../models/conversation.dart';
import '../../models/matrix_user.dart';
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
  List<GroupMemberInfoModel> _members = const [];
  bool _loading = true;
  String? _error;
  bool _saving = false;
  StreamSubscription<GroupUpdatedEvent>? _groupSub;

  String? get _myId => AppStateScope.maybeOf(context)?.currentUser?.id;

  bool get _isOwner =>
      _ownerId != null &&
      _ownerId!.isNotEmpty &&
      _myId != null &&
      _ownerId == _myId;

  String get _groupId => widget.args.groupId;

  @override
  void initState() {
    super.initState();
    _name = widget.args.initialName;
    _avatarUrl = widget.args.initialAvatarUrl ?? '';
    _description = widget.args.initialDescription ?? '';
    _ownerId = widget.args.initialOwnerId;
    _memberCount = widget.args.initialMemberCount ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
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
    final state = AppStateScope.maybeOf(context);
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
        _error = e is ApiException
            ? e.message
            : 'Não foi possível carregar o grupo.';
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

  Future<void> _editIdentity() async {
    if (_saving) return;
    final nameController = TextEditingController(text: _name);
    final descController = TextEditingController(text: _description);
    final result = await showDialog<_GroupIdentityEdit>(
      context: context,
      builder: (ctx) => _GroupIdentityDialog(
        nameController: nameController,
        descController: descController,
      ),
    );
    if (result == null || !mounted) return;
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.updateGroup(
        _groupId,
        name: result.name,
        description: result.description,
      );
      await _refreshSilent();
      messenger.showSnackBar(
        const SnackBar(content: Text('Grupo atualizado com sucesso.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar o grupo.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      nameController.dispose();
      descController.dispose();
    }
  }

  Future<void> _changeAvatar() async {
    if (_saving) return;
    final result = await pickGalleryImage(imageQuality: 80);
    if (!mounted) return;
    if (!result.isSuccess) {
      if (!result.cancelled && result.error != null && result.error!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
      }
      return;
    }
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await Services.instance.uploads.upload(File(result.file!.path));
      await state.updateGroupAvatar(_groupId, url);
      await _refreshSilent();
      messenger.showSnackBar(
        const SnackBar(content: Text('Foto do grupo atualizada.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível alterar a foto.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshSilent() async {
    final state = AppStateScope.maybeOf(context);
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
      });
    } catch (_) {
      // Best-effort refresh — realtime broadcasts cover the other members.
    }
  }

  Future<void> _addMember() async {
    if (_saving) return;
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    final current = state.currentUser;
    if (current == null) return;
    final existingIds = _members.map((m) => m.id).toSet();
    final chosen = await showModalBottomSheet<_AddMemberResult>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (_) => _AddMemberSheet(
        ownerId: current.id,
        existingIds: existingIds,
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.addGroupMember(_groupId, chosen.userId);
      await _refreshSilent();
      messenger.showSnackBar(
        SnackBar(content: Text('${displayNickname(chosen.nickname)} entrou no grupo.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível adicionar o membro.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.spaceLg),
      children: [
        const SizedBox(height: 8),
        Center(
          child: _GroupAvatar(url: _avatarUrl, name: _name ?? '', size: 104),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _name ?? '',
            textAlign: TextAlign.center,
            style: AppTextStyles.h3.copyWith(color: AppColors.techWhite),
          ),
        ),
        if (_description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              _description.trim(),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
          ),
        ],
        if (_isOwner) ...[
          const SizedBox(height: AppDimensions.spaceLg),
          _AdminActionsGrid(
            actions: [
              _AdminAction(
                icon: Icons.badge_outlined,
                label: 'Editar nome',
                onTap: _editIdentity,
              ),
              _AdminAction(
                icon: Icons.photo_camera_outlined,
                label: 'Alterar foto',
                onTap: _changeAvatar,
              ),
              _AdminAction(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Adicionar',
                onTap: _addMember,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppDimensions.spaceLg),
        Center(
          child: Text(
            '$_memberCount membro${_memberCount == 1 ? '' : 's'}',
            style: AppTextStyles.caption
                .copyWith(color: AppColors.holographicBlue),
          ),
        ),
        const SizedBox(height: AppDimensions.spaceLg),
        _ParticipantesTile(
          memberCount: _memberCount,
          onTap: () {
            if (_groupId.isEmpty) return;
            Navigator.of(context).pushNamed(
              AppRoutes.groupMembers,
              arguments: GroupMembersRouteArgs(
                groupId: _groupId,
                groupName: _name ?? '',
                ownerId: _ownerId,
              ),
            );
          },
        ),
        const SizedBox(height: AppDimensions.spaceXxl),
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
        automaticallyImplyLeading: true,
        leading: BackButton(
          color: AppColors.holographicBlue,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Text('Grupo', style: AppTextStyles.hud.copyWith(fontSize: 16)),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }
}

/// A single admin action (icon + label + tap). Rendered as a square tile in
/// a horizontal row (Etapa 4): organized in squares, responsive wrap, no
/// horizontal overflow.
class _AdminAction {
  const _AdminAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Horizontal grid of admin action squares for the group owner. Uses a
/// [Wrap] so small screens wrap gracefully instead of overflowing.
class _AdminActionsGrid extends StatelessWidget {
  const _AdminActionsGrid({required this.actions});

  final List<_AdminAction> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppDimensions.spaceMd,
      runSpacing: AppDimensions.spaceMd,
      children: [
        for (final action in actions)
          _AdminActionTile(
            icon: action.icon,
            label: action.label,
            onTap: action.onTap,
          ),
      ],
    );
  }
}

class _AdminActionTile extends StatelessWidget {
  const _AdminActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        onTap: onTap,
        child: Container(
          width: 104,
          padding: const EdgeInsets.symmetric(vertical: AppDimensions.spaceMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            border: Border.all(color: AppColors.deepBlue),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.holographicBlue, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.techWhite, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog result for the group identity edit (name + description).
class _GroupIdentityEdit {
  const _GroupIdentityEdit({required this.name, required this.description});

  final String name;
  final String description;
}

class _GroupIdentityDialog extends StatefulWidget {
  const _GroupIdentityDialog({
    required this.nameController,
    required this.descController,
  });

  final TextEditingController nameController;
  final TextEditingController descController;

  @override
  State<_GroupIdentityDialog> createState() => _GroupIdentityDialogState();
}

class _GroupIdentityDialogState extends State<_GroupIdentityDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bluishBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        side: BorderSide(color: AppColors.deepBlue),
      ),
      title: Text('Editar grupo',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MatrixTextField(
            label: 'Nome do grupo',
            hint: 'Ex.: Grupo MATRIX',
            controller: widget.nameController,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppDimensions.spaceMd),
          MatrixTextField(
            label: 'Descrição',
            hint: 'Descrição do grupo (opcional',
            controller: widget.descController,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancelar',
              style: TextStyle(color: AppColors.holographicBlue)),
        ),
        TextButton(
          onPressed: () {
            final name = widget.nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('O nome do grupo é obrigatório.')),
              );
              return;
            }
            Navigator.of(context).pop(_GroupIdentityEdit(
              name: name,
              description: widget.descController.text.trim(),
            ));
          },
          child: Text('Salvar', style: TextStyle(color: AppColors.primaryBlue)),
        ),
      ],
    );
  }
}

class _AddMemberResult {
  const _AddMemberResult({required this.userId, required this.nickname});

  final String userId;
  final String nickname;
}

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({
    required this.ownerId,
    required this.existingIds,
  });

  final String ownerId;
  final Set<String> existingIds;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  List<MatrixUser> _friends = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    final current = state.currentUser;
    if (current == null) return;
    try {
      final page = await state.loadFriends(current.id, pageSize: 50);
      if (!mounted) return;
      setState(() {
        _friends = page.friends
            .where((f) =>
                f.id != widget.ownerId && !widget.existingIds.contains(f.id))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
              child: Text('ADICIONAR MEMBRO',
                  style: AppTextStyles.hud
                      .copyWith(fontSize: 14, color: AppColors.techWhite)),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            if (_loading)
              Padding(
                padding: EdgeInsets.all(24),
                child:
                    Center(child: HudLabel(text: 'CARREGANDO...', dot: true)),
              )
            else if (_friends.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('Nenhum amigo disponível para adicionar.',
                      style: AppTextStyles.bodyMuted,
                      textAlign: TextAlign.center),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in _friends)
                      ListTile(
                        leading: FramedAvatar(
                          frame: u.frame,
                          size: 44,
                          child: UserAvatar(
                            name: u.nickname,
                            seed: u.nickname,
                            imageUrl: u.avatarUrl,
                            size: 36,
                          ),
                        ),
                        title: NicknameRenderer(
                          displayNickname(u.nickname),
                          baseStyle: AppTextStyles.body.copyWith(fontSize: 15),
                          background: AppColors.bluishBlack,
                          nameColor: u.nameColor,
                        ),
                        onTap: () {
                          Navigator.of(context).pop(
                            _AddMemberResult(
                                userId: u.id, nickname: u.nickname),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar(
      {required this.url, required this.name, required this.size});

  final String? url;

  final String name;

  final double size;

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      name: name.isEmpty ? 'G' : name,
      seed: name,
      imageUrl: (url == null || url!.isEmpty) ? null : url,
      size: size,
    );
  }
}

/// Navigable row that opens the dedicated participants screen (Etapa 6).
class _ParticipantesTile extends StatelessWidget {
  const _ParticipantesTile({required this.memberCount, required this.onTap});

  final int memberCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spaceLg,
              vertical: AppDimensions.spaceMd,
          ),
          child: Row(
            children: [
              Icon(Icons.group_rounded, color: AppColors.holographicBlue,
                  size: 26),
              const SizedBox(width: AppDimensions.spaceMd),
              Expanded(
                child: Text(
                  'Participantes',
                  style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
                ),
              ),
              Text(
                '$memberCount membro${memberCount == 1 ? '' : 's'}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.holographicBlue),
              ),
              const SizedBox(width: AppDimensions.spaceSm),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.holographicBlue, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
