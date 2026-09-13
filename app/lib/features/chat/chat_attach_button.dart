import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/gallery_picker.dart';
import '../../data/api_config.dart';
import '../../data/services.dart';

/// 📎 attach button inside the chat composer (private + group).
///
/// Opens a compact pop-up above the composer with two actions:
///  * "Galeria" → then choose Foto ou Vídeo → pick from the device;
///  * "Câmera" → then choose Foto ou Vídeo → capture right now.
///
/// The picked file is uploaded (image → /api/uploads, video →
/// /api/uploads/video) and sent as a MEDIA message through [onSendMedia],
/// preserving the active reply reference the composer already holds. The
/// upload/send runs inside this widget (with error feedback) so the chat
/// composer never breaks.
class ChatAttachButton extends StatelessWidget {
  const ChatAttachButton({
    super.key,
    required this.iconColor,
    required this.onSendMedia,
  });

  final Color iconColor;

  /// Called after upload with the real media URL; [kind] is 'image'|'video'.
  /// The composer supplies the current replyToMessageId.
  final Future<void> Function(String kind, String url) onSendMedia;

  Future<void> _openMenu(BuildContext context) async {
    final action = await showModalBottomSheet<_AttachAction>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const _AttachPopup(),
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    // Pick media DIRECTLY from the gallery (photo OR video in the same
    // native picker — no extra Foto/Vídeo step). The type is detected from
    // the file.
    final result = await (action == _AttachAction.gallery
        ? pickGalleryMedia()
        : _captureCameraMedia(context));
    if (!context.mounted) return;
    if (!result.isSuccess || result.file == null) return;
    final file = File(result.file!.path);
    final kind = _isVideoPath(file.path) ? 'video' : 'image';

    // Size guard (server re-validates) + upload + send.
    try {
      if (kind == 'video' && file.lengthSync() > 100 * 1024 * 1024) {
        messenger.showSnackBar(
          const SnackBar(content: Text('O vídeo excede o limite de 100 MB.')),
        );
        return;
      }
      final url = kind == 'video'
          ? await Services.instance.uploads.uploadVideo(file)
          : await Services.instance.uploads.upload(file);
      await onSendMedia(kind, url);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Erro ao enviar a mídia.')));
    }
  }

  /// Camera capture: opens the native camera and lets the user switch
  /// between taking a PHOTO or recording a VIDEO (image_picker has no
  /// single "camera media" entry, so the camera action offers Foto/Vídeo —
  /// the gallery action stays unified).
  Future<GalleryPickResult> _captureCameraMedia(BuildContext context) async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => _CameraKindPopup(),
    );
    if (kind == null) return const GalleryPickResult.cancelled();
    return kind == 'video' ? pickCameraVideo() : pickCameraImage();
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: IconButton(
        icon: Icon(Icons.attach_file_rounded, color: iconColor, size: 26),
        onPressed: () => _openMenu(context),
        tooltip: 'Anexar mídia',
      ),
    );
  }
}

enum _AttachAction { gallery, camera }

/// Compact bottom pop-up listing the attach actions (Galeria / Câmera).
class _AttachPopup extends StatelessWidget {
  const _AttachPopup();

  @override
  Widget build(BuildContext context) {
    return _menuShell(
      context,
      icon1: Icons.photo_library_rounded,
      label1: 'Galeria',
      on1: () => Navigator.of(context).pop(_AttachAction.gallery),
      icon2: Icons.videocam_rounded,
      label2: 'Câmera',
      on2: () => Navigator.of(context).pop(_AttachAction.camera),
    );
  }
}

/// Camera sub-menu: Foto ou Vídeo (only for the camera — image_picker's
/// native camera has separate photo/video intents).
class _CameraKindPopup extends StatelessWidget {
  const _CameraKindPopup();

  @override
  Widget build(BuildContext context) {
    return _menuShell(
      context,
      icon1: Icons.photo_camera_outlined,
      label1: 'Foto',
      on1: () => Navigator.of(context).pop('image'),
      icon2: Icons.video_camera_back_outlined,
      label2: 'Vídeo',
      on2: () => Navigator.of(context).pop('video'),
    );
  }
}

Widget _menuShell(
  BuildContext context, {
  required IconData icon1,
  required String label1,
  required VoidCallback on1,
  required IconData icon2,
  required String label2,
  required VoidCallback on2,
}) {
  return SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bluishBlack,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.deepBlue),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuTile(context, icon1, label1, on1),
            _menuTile(context, icon2, label2, on2),
            const SizedBox(height: AppDimensions.spaceXs),
          ],
        ),
      ),
    ),
  );
}

Widget _menuTile(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback onTap,
) {
  return ListTile(
    leading: Icon(icon, color: AppColors.holographicBlue, size: 24),
    title: Text(label,
        style: AppTextStyles.body.copyWith(color: AppColors.techWhite)),
    trailing: Icon(Icons.chevron_right_rounded,
        color: AppColors.holographicBlue, size: 20),
    onTap: onTap,
  );
}
