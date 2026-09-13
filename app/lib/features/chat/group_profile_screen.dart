import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/utils/chat_format.dart';
import '../../core/utils/gallery_picker.dart';
import '../../core/utils/profile_navigation.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../data/dtos/dtos.dart';
import '../../app/routes.dart';
import '../../data/services.dart';
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
  List<GroupMemberInfoModel> _members = const [];
  bool _loading = true;
  String? _error;
  bool _saving = false;
  StreamSubscription<GroupUpdatedEvent>? _groupSub;
  StreamSubscription<GroupDeletedEvent>? _groupDeletedSub;

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
      _groupDeletedSub = state.onGroupDeleted.listen(_onGroupDeleted);
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
  /// profile screen; nothing stale remains for this group.
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

  Future<void> _editName() async {
    if (_saving) return;
    final nameController = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameEditDialog(controller: nameController),
    );
    if (result == null || !mounted) return;
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.updateGroup(_groupId, name: result);
      await _refreshSilent();
      messenger.showSnackBar(
        const SnackBar(content: Text('Nome do grupo atualizado.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível atualizar o nome.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      nameController.dispose();
    }
  }

  Future<void> _editDescription() async {
    if (_saving) return;
    final descController = TextEditingController(text: _description);
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => _DescriptionEditDialog(controller: descController),
    );
    if (result == null || !mounted) return;
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.updateGroup(_groupId, description: result);
      await _refreshSilent();
      messenger.showSnackBar(
        const SnackBar(content: Text('Descrição do grupo atualizada.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Não foi possível atualizar a descrição.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      descController.dispose();
    }
  }

  Future<void> _showEditMenu() async {
    if (_saving || !_isOwner) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _EditGroupMenu(),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'name':
        await _editName();
      case 'photo':
        await _changeAvatar();
      case 'description':
        await _editDescription();
      case 'delete':
        await _confirmDeleteGroup();
    }
  }

  /// EXCLUIR GRUPO — destructive, owner-only. Asks for an explicit
  /// confirmation (the group, its members, messages and media are removed
  /// for EVERYONE — this is NOT a simple leave) before calling the server,
  /// which re-validates ownership and deletes the group in one transaction.
  Future<void> _confirmDeleteGroup() async {
    if (!_isOwner || _saving) return;
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
          'Excluir grupo?',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite),
        ),
        content: Text(
          'O grupo "${_name ?? ''}" será excluído permanentemente. '
          'Todos os membros serão removidos, o histórico e os dados '
          'relacionados serão apagados conforme as regras do MATRIX, e '
          'nenhum participante poderá mais acessá-lo. Esta ação não pode '
          'ser desfeita e não é uma simples saída.',
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
            child: Text(
              'Excluir',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    setState(() => _saving = true);
    try {
      final ok = await state.deleteGroup(_groupId);
      if (!mounted) return;
      if (ok) {
        messenger.showSnackBar(
          SnackBar(content: Text('Grupo "${_name ?? ''}" excluído.')),
        );
        // Drop every open surface for this group (profile + conversation).
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível excluir o grupo.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAvatar() async {
    if (_saving) return;
    final result = await pickGalleryImage(imageQuality: 80);
    if (!mounted) return;
    if (!result.isSuccess) {
      if (!result.cancelled &&
          result.error != null &&
          result.error!.isNotEmpty) {
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
      final url =
          await Services.instance.uploads.upload(File(result.file!.path));
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
      // Best-effort refresh — realtime broadcasts cover the other members..
    }
  }

  Future<void> _openMembers() async {
    if (_groupId.isEmpty) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.groupMembers,
      arguments: GroupMembersRouteArgs(
        groupId: _groupId,
        groupName: _name ?? '',
        ownerId: _ownerId,
      ),
    );
    if (mounted) await _refreshSilent();
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
        const SizedBox(height: AppDimensions.spaceLg),
        _MembersSection(
          members: _members,
          ownerId: _ownerId,
          memberCount: _memberCount,
          onOpen: _openMembers,
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
        actions: [
          if (_isOwner)
            IconButton(
              tooltip: 'Editar',
              icon: Icon(Icons.edit_rounded, color: AppColors.holographicBlue),
              onPressed: _showEditMenu,
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }
}

/// Mini menu of group editing options (Etapa 2). Opened by the pencil icon
/// in the group profile AppBar (owner-only).
class _EditGroupMenu extends StatelessWidget {
  const _EditGroupMenu();

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
              child: Text('EDITAR GRUPO',
                  style: AppTextStyles.hud
                      .copyWith(fontSize: 14, color: AppColors.techWhite)),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            _EditMenuTile(
              icon: Icons.badge_outlined,
              label: 'Editar nome',
              value: 'name',
            ),
            _EditMenuTile(
              icon: Icons.photo_camera_outlined,
              label: 'Editar foto',
              value: 'photo',
            ),
            _EditMenuTile(
              icon: Icons.notes_rounded,
              label: 'Editar descrição',
              value: 'description',
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            // EXCLUIR GRUPO — same edit menu, owner-only (the sheet is only
            // reachable through the owner AppBar pencil). Destructive action,
            // visually separated from the non-destructive edits.
            Divider(
              height: AppDimensions.spaceLg,
              thickness: 1,
              color: AppColors.deepBlue.withValues(alpha: 0.5),
            ),
            _EditMenuTile(
              icon: Icons.delete_forever_rounded,
              label: 'Excluir grupo',
              value: 'delete',
              destructive: true,
            ),
            const SizedBox(height: AppDimensions.spaceXs),
          ],
        ),
      ),
    );
  }
}

class _EditMenuTile extends StatelessWidget {
  const _EditMenuTile({
    required this.icon,
    required this.label,
    required this.value,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Destructive actions (Excluir grupo) render in MATRIX's error red to
  /// signal irreversible consequences.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.holographicBlue;
    return Material(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        leading: Icon(icon, color: color, size: 24),
        title: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: destructive ? AppColors.error : AppColors.techWhite,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: color, size: 20),
        onTap: () => Navigator.of(context).pop(value),
      ),
    );
  }
}

/// Dialog for editing ONLY the group name (Etapa 2).
class _NameEditDialog extends StatefulWidget {
  const _NameEditDialog({required this.controller});

  final TextEditingController controller;

  @override
  State<_NameEditDialog> createState() => _NameEditDialogState();
}

class _NameEditDialogState extends State<_NameEditDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bluishBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        side: BorderSide(color: AppColors.deepBlue),
      ),
      title: Text('Editar nome',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite)),
      content: MatrixTextField(
        label: 'Nome do grupo',
        hint: 'Ex.: Grupo MATRIX',
        controller: widget.controller,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancelar',
              style: TextStyle(color: AppColors.holographicBlue)),
        ),
        TextButton(
          onPressed: () {
            final name = widget.controller.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('O nome do grupo é obrigatório.')),
              );
              return;
            }
            Navigator.of(context).pop(name);
          },
          child: Text('Salvar', style: TextStyle(color: AppColors.primaryBlue)),
        ),
      ],
    );
  }
}

/// Dialog for editing/removing ONLY the group description (Etapa 2). The
/// description is optional; 'Remover descrição' clears it ..
class _DescriptionEditDialog extends StatefulWidget {
  const _DescriptionEditDialog({required this.controller});

  final TextEditingController controller;

  @override
  State<_DescriptionEditDialog> createState() => _DescriptionEditDialogState();
}

class _DescriptionEditDialogState extends State<_DescriptionEditDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bluishBlack,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        side: BorderSide(color: AppColors.deepBlue),
      ),
      title: Text('Editar descrição',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite)),
      content: MatrixTextField(
        label: 'Descrição',
        hint: 'Descrição do grupo (opcional)',
        controller: widget.controller,
        maxLines: 3,
        minLines: 2,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancelar',
              style: TextStyle(color: AppColors.holographicBlue)),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(widget.controller.text.trim());
          },
          child: Text('Salvar', style: TextStyle(color: AppColors.primaryBlue)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: Text('Remover descrição',
              style: TextStyle(color: AppColors.error)),
        ),
      ],
    );
  }
}

/// "Membros" section shown inthe group profile (Etapa 3): header +
/// inline member list (with owner badge) + a row to open the full screen.
class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.members,
    required this.ownerId,
    required this.memberCount,
    required this.onOpen,
  });

  final List<GroupMemberInfoModel> members;
  final String? ownerId;
  final int memberCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final preview = members.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.group_rounded,
                color: AppColors.holographicBlue, size: 22),
            const SizedBox(width: 8),
            Text(
              'Membros',
              style: AppTextStyles.hud
                  .copyWith(fontSize: 14, color: AppColors.techWhite),
            ),
            const Spacer(),
            Text(
              '$memberCount',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.holographicBlue),
            ),
          ],
        ),
        const SizedBox(height: AppDimensions.spaceMd),
        if (preview.isEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: AppDimensions.spaceMd),
            child: Center(
              child: Text('Sem membros.',
                  style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
            ),
          )
        else
          for (final m in preview) ...[
            _MemberRow(member: m, isOwner: m.id == ownerId),
            const SizedBox(height: 4),
          ],
        const SizedBox(height: AppDimensions.spaceSm),
        Material(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg,
                vertical: AppDimensions.spaceMd,
              ),
              child: Row(
                children: [
                  Icon(Icons.group_add_rounded,
                      color: AppColors.holographicBlue, size: 22),
                  const SizedBox(width: AppDimensions.spaceMd),
                  Expanded(
                    child: Text(
                      'Ver todos',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.techWhite),
                    ),
                  ),
                  Text(
                    '$memberCount',
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
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.isOwner});

  final GroupMemberInfoModel member;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => openProfileById(
        context,
        id: member.id,
        nickname: member.nickname,
      ),
      leading: UserAvatar(
        name: member.nickname,
        seed: member.nickname,
        imageUrl: member.avatarUrl,
        size: 40,
      ),
      title: Text(
        displayNickname(member.nickname),
        style: AppTextStyles.body.copyWith(fontSize: 15),
      ),
      trailing: isOwner
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.holographicBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.holographicBlue.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'Dono',
                style: AppTextStyles.caption
                    .copyWith(fontSize: 10, color: AppColors.holographicBlue),
              ),
            )
          : null,
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
