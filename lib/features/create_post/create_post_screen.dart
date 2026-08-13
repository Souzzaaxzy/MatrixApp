import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';

/// Create publication screen.
///
/// Text + optional image from the device. Posts are published locally.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  String? _imagePath;
  bool _publishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final result = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (result != null) {
      setState(() => _imagePath = result.path);
    }
  }

  Future<void> _publish() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _publishing = true);
    // Simulated local publish — no remote upload in Phase 1.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    AppStateScope.of(context).createPost(
      text: _controller.text,
      imageUrl: _imagePath,
    );
    setState(() => _publishing = false);
    Navigator.of(context)
      ..pop()
      ..pushReplacementNamed(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.techWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('NOVA PUBLICAÇÃO', style: AppTextStyles.title.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppDimensions.spaceLg),
                MatrixTextField(
                  label: 'Publicação',
                  hint: 'O que você está pensando?',
                  controller: _controller,
                  maxLines: 5,
                  minLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => Validators.required(v, label: 'Escreva algo'),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                if (_imagePath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Image.file(
                        File(_imagePath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceSm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.error, size: 18),
                      label: Text('Remover imagem',
                          style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                      onPressed: () => setState(() => _imagePath = null),
                    ),
                  ),
                ] else
                  MatrixButton(
                    label: 'Adicionar imagem',
                    icon: Icons.add_photo_alternate_outlined,
                    variant: MatrixButtonVariant.outline,
                    expanded: true,
                    onPressed: _pickImage,
                  ),
                const SizedBox(height: AppDimensions.spaceXxl),
                const Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.deepBlue)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppDimensions.spaceMd),
                      child: HudLabel(text: 'LOCAL PUBLISH'),
                    ),
                    Expanded(child: Divider(color: AppColors.deepBlue)),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceXxl),
                MatrixButton(
                  label: 'Publicar',
                  icon: Icons.send_rounded,
                  expanded: true,
                  isLoading: _publishing,
                  onPressed: _publish,
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
