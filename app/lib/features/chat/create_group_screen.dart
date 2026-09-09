import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/matrix_card.dart';
import '../../data/api_config.dart';
import '../../data/services.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../models/matrix_user.dart';
import 'chat_navigation.dart';

/// Group creation — photo (optional), mandated name, optional
/// description, multi-select of friends. The creator is always added by
/// the server as admin/creator; the client never sends its own id.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String? _avatarPath;
  String? _avatarUrl;
  bool _pickingPhoto = false;
  bool _creating = false;
  List<MatrixUser> _friends = const [];
  final Set<String> _selectedIds = <String>{};
  bool _loadedFriends = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedFriends) return;
    _loadedFriends = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFriends();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    final current = state.currentUser;
    if (current == null) return;
    try {
      final page = await state.loadFriends(current.id, pageSize: 30);
      if (!mounted) return;
      setState(() {
        _friends = page.friends;
        _selectedIds.removeWhere((id) => !page.friends.any((f) => f.id == id));
      });
    } catch (_) {
      // Best-effort: the "Criar Grupo" button still works with an empty pool.
    }
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto) return;
    _pickingPhoto = true;
    try {
      final picker = ImagePicker();
      final result = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (result == null || !mounted) return;
      setState(() {
        _avatarPath = result.path;
        _avatarUrl = null;
      });
    } finally {
      _pickingPhoto = false;
    }
  }

  void _removePhoto() {
    setState(() {
      _avatarPath = null;
      _avatarUrl = null;
    });
  }

  void _toggleFriend(MatrixUser user) {
    setState(() {
      if (!_selectedIds.add(user.id)) {
        _selectedIds.remove(user.id);
      }
    });
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = AppStateScope.maybeOf(context);
    if (state == null) return;
    setState(() => _creating = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      String? avatarUrl = _avatarUrl;
      if (_avatarPath != null) {
        avatarUrl = await Services.instance.uploads.upload(File(_avatarPath!));
      }
      final group = await state.createGroup(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        avatarUrl: avatarUrl,
        participantIds: _selectedIds.toList(),
      );
      if (!mounted) return;
      navigator.pop();
      openGroupConversation(
          context, GroupConversationRouteArgs.fromGroup(group));
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
          const SnackBar(content: Text('Erro ao criar o grupo.')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  List<MatrixUser> get _selectedFriends =>
      _friends.where((f) => _selectedIds.contains(f.id)).toList();

  @override
  Widget build(BuildContext context) {
    final selected = _selectedFriends;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: AppColors.absoluteBlack,
        surfaceTintColor: Colors.transparent,
        title: Text('NOVO GRUPO',
            style: AppTextStyles.title.copyWith(fontSize: 18)),
      ),
      backgroundColor: AppColors.absoluteBlack,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppDimensions.spaceLg),
            children: [
              _photoPicker(),
              const SizedBox(height: AppDimensions.spaceLg),
              MatrixTextField(
                label: 'Nome do grupo',
                hint: 'Ex.: Grupo MATRIX',
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'O nome do grupo é obrigatório.'
                    : null,
              ),
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixTextField(
                label: 'Descrição',
                hint: 'Descrição do grupo (opcional',
                controller: _descController,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: AppDimensions.spaceLg),
              Text(
                'PARTICIPANTES',
                style: AppTextStyles.hud
                    .copyWith(color: AppColors.holographicBlue),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              Text(
                'Selecione seus amigos para participar. O criador é incluído automaticamente.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.holographicBlue),
              ),
              const SizedBox(height: AppDimensions.spaceMd),
              if (selected.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final u in selected)
                      InputChip(
                        avatar: UserAvatar(
                          name: u.nickname,
                          seed: u.nickname,
                          imageUrl: u.avatarUrl,
                          size: 20,
                        ),
                        label: Text('@${u.nickname}'),
                        labelStyle: AppTextStyles.caption
                            .copyWith(color: AppColors.techWhite),
                        backgroundColor: AppColors.cardSurface,
                        deleteIconColor: AppColors.holographicBlue,
                        shape: StadiumBorder(
                            side: BorderSide(color: AppColors.deepBlue)),
                        onDeleted: () => _toggleFriend(u),
                      ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceMd),
              ],
              if (_friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppDimensions.spaceXl),
                  child: Text(
                    'Nenhum amigo disponível para adicionar.',
                    style: AppTextStyles.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                )
              else
                _friendsList(selected),
              const SizedBox(height: AppDimensions.spaceLg),
              MatrixButton(
                label: 'Criar Grupo',
                icon: Icons.group_add_rounded,
                expanded: true,
                isLoading: _creating,
                onPressed: _creating ? null : _create,
              ),
              const SizedBox(height: AppDimensions.spaceXxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPicker() {
    final hasPhoto = _avatarPath != null || _avatarUrl != null;
    final frameSize = 96.0;
    return Center(
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          GestureDetector(
            onTap: hasPhoto ? null : _pickPhoto,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: frameSize,
              height: frameSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cardSurface,
                border:
                    Border.all(color: AppColors.holographicBlue, width: 1.5),
                image: _avatarPath != null
                    ? DecorationImage(
                        image: FileImage(File(_avatarPath!)),
                        fit: BoxFit.cover,
                      )
                    : (_avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_avatarUrl!),
                            fit: BoxFit.cover,
                          )
                        : null),
              ),
              child: hasPhoto
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_a_photo_rounded,
                            color: AppColors.holographicBlue, size: 28),
                        const SizedBox(height: 4),
                        Text('FOTO DO GRUPO',
                            style: AppTextStyles.hud
                                .copyWith(color: AppColors.holographicBlue)),
                      ],
                    ),
            ),
          ),
          if (hasPhoto)
            GestureDetector(
              onTap: _removePhoto,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryBlue,
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _friendsList(List<MatrixUser> selected) {
    return Column(
      children: [
        for (final u in _friends)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: MatrixCard(
              onTap: () => _toggleFriend(u),
              child: Row(
                children: [
                  FramedAvatar(
                    frame: u.frame,
                    size: 42,
                    child: UserAvatar(
                      name: u.nickname,
                      seed: u.nickname,
                      imageUrl: u.avatarUrl,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NicknameRenderer(
                          u.nickname,
                          baseStyle: AppTextStyles.h3.copyWith(fontSize: 14),
                          background: AppColors.cardSurface,
                          nameColor: u.nameColor,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected.contains(u)
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected.contains(u)
                        ? AppColors.primaryBlue
                        : AppColors.deepBlue,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
