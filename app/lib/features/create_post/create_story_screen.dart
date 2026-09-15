import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/gallery_picker.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../data/api_config.dart';
import '../../data/services.dart';

/// Criação de Story — mesmo seletor de mídia e mesmo pipeline de upload do
/// create_post (`pickGalleryMedia` + `/api/uploads`). Requer PREVIEW antes
/// de publicar: nada é publicado sem o toque explícito em "PUBLICAR STORY".
class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  String? _imagePath;
  String? _videoPath;
  String? _thumbnailPath;
  bool _publishing = false;

  /// Mesma regra de detecção de vídeo do create_post (um só critério no app).
  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp');
  }

  Future<void> _pickMedia() async {
    final result = await pickGalleryMedia();
    if (!mounted) return;
    if (!result.isSuccess) {
      if (!result.cancelled &&
          result.error != null &&
          result.error!.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.error!)));
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

  /// Capa do vídeo — MESMA técnica do create_post (frame em 1s via
  /// `video_thumbnail`, gravado como JPEG no diretório temporário).
  Future<String?> _generateThumbnail(String videoPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final coverPath = '${dir.path}/story_cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final generated = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: coverPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: 1000,
        quality: 75,
      );
      return generated;
    } catch (_) {
      return null;
    }
  }

  Future<void> _publish() async {
    if (_publishing) return;
    if (_imagePath == null && _videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma mídia para o Story.')),
      );
      return;
    }
    setState(() => _publishing = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final state = AppStateScope.of(context);
    try {
      String? mediaUrl;
      String mediaType = 'image';
      String? thumbnailUrl;
      if (_imagePath != null) {
        mediaUrl = await Services.instance.uploads.upload(File(_imagePath!));
      } else if (_videoPath != null) {
        final f = File(_videoPath!);
        final sizeMb = f.lengthSync() / (1024 * 1024);
        if (sizeMb > 100) {
          throw const ApiException(
            statusCode: 413,
            message: 'O vídeo excede o tamanho permitido (máx. 100 MB).',
          );
        }
        mediaUrl = await Services.instance.uploads.uploadVideo(f);
        mediaType = 'video';
        if (_thumbnailPath != null) {
          try {
            thumbnailUrl =
                await Services.instance.uploads.upload(File(_thumbnailPath!));
          } catch (_) {
            thumbnailUrl = null; // capa é opcional
          }
        }
      }
      await state.createStory(
        mediaUrl: mediaUrl!,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl,
      );
      if (!mounted) return;
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Erro ao publicar o Story.')),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = _imagePath != null || _videoPath != null;
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.techWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('NOVO STORY',
            style: AppTextStyles.title.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppDimensions.spaceLg),
              // PREVIEW da mídia selecionada (obrigatório antes de publicar).
              Expanded(
                child: Center(
                  child: !hasMedia
                      ? Text(
                          'Selecione uma foto ou um vídeo para o seu Story.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMuted,
                        )
                      : ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusLg),
                          child: _videoPath != null
                              ? _VideoPreviewPlaceholder(
                                  thumbnailPath: _thumbnailPath,
                                )
                              : Image.file(
                                  File(_imagePath!),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Text(
                                    'Não foi possível abrir esta imagem.',
                                    style: AppTextStyles.bodyMuted,
                                  ),
                                ),
                        ),
                ),
              ),
              const SizedBox(height: AppDimensions.spaceMd),
              if (hasMedia)
                const Center(
                  child: HudLabel(
                    text: 'PRÉ-VISUALIZAÇÃO',
                    color: AppColors.electricBlue,
                  ),
                ),
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: hasMedia ? 'Trocar mídia' : 'Selecionar mídia',
                icon: Icons.photo_library_rounded,
                variant: MatrixButtonVariant.outline,
                expanded: true,
                onPressed: _publishing ? null : _pickMedia,
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              MatrixButton(
                label: 'PUBLICAR STORY',
                icon: Icons.send_rounded,
                expanded: true,
                isLoading: _publishing,
                onPressed: (!hasMedia || _publishing) ? null : _publish,
              ),
              const SizedBox(height: AppDimensions.spaceLg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preview de vídeo: mostra a capa gerada (ou a URL local do arquivo no
/// Android; sem player duplicado — o feed já tem o seu).
class _VideoPreviewPlaceholder extends StatelessWidget {
  const _VideoPreviewPlaceholder({required this.thumbnailPath});

  final String? thumbnailPath;

  @override
  Widget build(BuildContext context) {
    if (thumbnailPath != null && File(thumbnailPath!).existsSync()) {
      return Image.file(File(thumbnailPath!), fit: BoxFit.contain);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.videocam_rounded,
            color: AppColors.holographicBlue, size: 44),
        const SizedBox(height: AppDimensions.spaceSm),
        Text('Vídeo selecionado', style: AppTextStyles.bodyMuted),
      ],
    );
  }
}
