import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/user_avatar.dart';

/// Edit profile screen. Changes are local in Phase 1.
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
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final user = AppStateScope.of(context).currentUser;
    _nameController = TextEditingController(text: user.name);
    _usernameController =
        TextEditingController(text: user.username.replaceAll('@', ''));
    _bioController = TextEditingController(text: user.bio);
    _initialized = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final username = _usernameController.text.trim().replaceAll('@', '');
    AppStateScope.of(context).updateProfile(
      name: _nameController.text.trim(),
      username: username,
      bio: _bioController.text.trim(),
    );
    setState(() => _saving = false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = AppStateScope.of(context).currentUser;
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.techWhite),
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
                  child: Stack(
                    children: [
                      UserAvatar(
                        name: _nameController.text.isEmpty
                            ? user.name
                            : _nameController.text,
                        seed: user.avatarSeed,
                        size: 96,
                        ring: true,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(AppDimensions.spaceSm),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: AppColors.techWhite, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                const Center(child: HudLabel(text: 'ALTERAR FOTO')),
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
                  label: 'Username',
                  controller: _usernameController,
                  prefix: const Text('@',
                      style: TextStyle(color: AppColors.holographicBlue)),
                  textInputAction: TextInputAction.next,
                  validator: (v) => Validators.required(v, label: 'Username obrigatório'),
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
                  label: 'Salvar',
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
