import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';

/// Edit profile screen.
///
/// All changes are persisted on the server (PATCH /api/users/me). The
/// avatar flow is pick → preview → upload (POST /api/uploads) → persist
/// the returned URL on the profile. Nothing here is local-only.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final user = AppStateScope.of(context).currentUser;
    _nameController = TextEditingController(text: user?.name ?? '');
    _usernameController =
        TextEditingController(text: (user?.username ?? '').replaceAll('@', ''));
    _bioController = TextEditingController(text: user?.bio ?? '');
    _initialized = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.nightBlue,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusXl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppDimensions.spaceMd),
            const HudLabel(text: 'SELECIONAR FOTO'),
            const SizedBox(height: AppDimensions.spaceMd),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.electricBlue),
              title: Text('Galeria', style: AppTextStyles.body),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.electricBlue),
              title: Text('Câmera', style: AppTextStyles.body),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            const SizedBox(height: AppDimensions.spaceMd),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      await AppStateScope.of(context).changeAvatar(File(picked.path));
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil atualizada.')),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Não foi possível enviar a foto. Tente novamente.');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await AppStateScope.of(context).updateProfile(
        name: _nameController.text.trim(),
        username: _usernameController.text.trim().replaceAll(RegExp(r'^@+'), ''),
        bio: _bioController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      // Surface the server's real message (validation, conflict, network) —
      // never a generic "credenciais inválidas".
      _showError(e.message);
    } catch (_) {
      _showError('Erro ao salvar perfil. Tente novamente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppStateScope.of(context).currentUser;
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.techWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('EDITAR PERFIL', style: AppTextStyles.title.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppDimensions.spaceXl),
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        UserAvatar(
                          name: _nameController.text.isEmpty
                              ? (user?.name ?? '')
                              : _nameController.text,
                          seed: user?.avatarSeed ?? user?.username,
                          imageUrl: user?.avatarUrl,
                          size: 96,
                          ring: true,
                        ),
                        if (_uploadingAvatar)
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.electricBlue,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: AppColors.primaryBlue,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(AppDimensions.spaceSm),
                              child: Icon(Icons.camera_alt_rounded,
                                  color: AppColors.techWhite, size: 16),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                Center(
                  child: HudLabel(
                    text: _uploadingAvatar ? 'ENVIANDO FOTO...' : 'ALTERAR FOTO',
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                MatrixTextField(
                  label: 'Nome',
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: Validators.name,
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                MatrixTextField(
                  label: 'Nickname',
                  controller: _usernameController,
                  prefix: Icon(Icons.person_outline_rounded,
                      color: AppColors.holographicBlue, size: 20),
                  textInputAction: TextInputAction.next,
                  validator: (v) => Validators.required(v, label: 'Nickname obrigatório'),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                MatrixTextField(
                  label: 'Bio',
                  controller: _bioController,
                  maxLines: 4,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                MatrixButton(
                  label: _saving ? 'Salvando...' : 'Salvar',
                  icon: Icons.check_rounded,
                  expanded: true,
                  isLoading: _saving,
                  onPressed: _save,
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
