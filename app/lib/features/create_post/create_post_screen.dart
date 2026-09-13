import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/gallery_picker.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../data/api_config.dart';
import '../../data/services.dart';

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
  String? _videoPath;
  String? _thumbnailPath;
  bool _publishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Unified media picker: ONE button opens the gallery and the user picks a
  /// photo OR a video directly (no prior Foto/Vídeo step). The type is
  /// detected from the file; for videos a cover/thumbnail is generated.
  Future<void> _pickMedia() async {
    final result = await pickGalleryMedia();
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
    final file = result.file!;
    final isVideo = _isVideoPath(file.path);
    setState(() {
      _imagePath = isVideo ? null : file.path;
      _videoPath = isVideo ? file.path : null;
      _thumbnailPath = null;
    });
    if (isVideo) {
      final cover = await _generateThumbnail(file.path);
      if (mounted && cover != null) {
        setState(() => _thumbnailPath = cover);
      }
    }
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp');
  }

  /// Generates a lightweight cover frame from the video (best-frame at 1s)
  /// and writes it as a JPEG in the temp dir — the cover is then uploaded
  /// like a normal image and persisted as the post's thumbnailUrl.
  Future<String?> _generateThumbnail(String videoPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/mc_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Uint8List? thumb = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 80,
        timeMs: 1000,
      );
      if (thumb == null) return null;
      final file = File(outPath);
      await file.writeAsBytes(thumb);
      return file.path;
    } catch (_) {
      return null; // safe fallback: no cover → app uses the video badge
    }
  }

  Future<void> _publish() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _publishing = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final state = AppStateScope.of(context);
    try {
      String? imageUrl;
      String? videoUrl;
      String? thumbnailUrl;
      if (_imagePath != null) {
        imageUrl = await Services.instance.uploads.upload(File(_imagePath!));
      } else if (_videoPath != null) {
        // Videos can be large; the server caps at 100 MB — surface a clear
        // error instead of leaving a broken post.
        final f = File(_videoPath!);
        final sizeMb = f.lengthSync() / (1024 * 1024);
        if (sizeMb > 100) {
          throw ApiException(
            statusCode: 413,
            message: 'O vídeo excede o tamanho permitido (máx. 100 MB).',
          );
        }
        videoUrl = await Services.instance.uploads.uploadVideo(f);
        // Upload the cover when available (same image upload path).
        if (_thumbnailPath != null) {
          try {
            thumbnailUrl =
                await Services.instance.uploads.upload(File(_thumbnailPath!));
          } catch (_) {
            thumbnailUrl = null; // safe fallback
          }
        }
      }
      await state.createPost(
        text: _controller.text,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
      );
      if (!mounted) return;
      // Return to the caller (own profile or feed) — replacing the route
      // would orphan the back stack.
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Erro ao publicar.')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.techWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('NOVA PUBLICAÇÃO',
            style: AppTextStyles.title.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
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
                  validator: (v) =>
                      Validators.required(v, label: 'Escreva algo'),
                ),
                const SizedBox(height: AppDimensions.spaceLg),
                if (_videoPath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                    child: _thumbnailPath != null
                        ? AspectRatio(
                            aspectRatio: 16 / 10,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(_thumbnailPath!),
                                  fit: BoxFit.cover,
                                ),
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            height: 180,
                            color: AppColors.nightBlue,
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam_rounded, size: 44),
                                const SizedBox(height: 6),
                                Text('VÍDEO SELECIONADO',
                                    style: AppTextStyles.hud),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: AppDimensions.spaceSm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.error, size: 18),
                      label: Text('Remover vídeo',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.error)),
                      onPressed: () => setState(() {
                        _videoPath = null;
                        _thumbnailPath = null;
                      }),
                    ),
                  ),
                ] else if (_imagePath != null) ...[
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
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.error)),
                      onPressed: () => setState(() => _imagePath = null),
                    ),
                  ),
                ] else
                  MatrixButton(
                    label: '📷 Foto/Vídeo',
                    icon: Icons.photo_library_outlined,
                    variant: MatrixButtonVariant.outline,
                    expanded: true,
                    onPressed: _pickMedia,
                  ),
                const SizedBox(height: AppDimensions.spaceXxl),
                Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.deepBlue)),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: AppDimensions.spaceMd),
                      child: HudLabel(text: 'PUBLISH'),
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
