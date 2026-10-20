import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/gallery_picker.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../models/profile_music.dart';
import 'music_search_service.dart';
import 'profile_music_picker.dart';

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
  late final TextEditingController _nicknameController;
  late final TextEditingController _bioController;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  bool _savingMusic = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final user = AppStateScope.of(context).currentUser;
    _nicknameController =
        TextEditingController(text: (user?.nickname ?? '').replaceAll('@', ''));
    _bioController = TextEditingController(text: user?.bio ?? '');
    _initialized = true;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
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
    final picked = await _pickImage(
      title: 'SELECIONAR FOTO',
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

  /// Picks the banner (cover) image and persists it — same pick → upload →
  /// persist pipeline as the avatar. Banners are wide, so a larger max width
  /// is allowed while still capping the payload.
  Future<void> _pickBanner() async {
    if (_uploadingBanner) return;
    final picked = await _pickImage(
      title: 'SELECIONAR BANNER',
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingBanner = true);
    try {
      await AppStateScope.of(context).changeBanner(File(picked.path));
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Banner atualizado.')),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Não foi possível enviar o banner. Tente novamente.');
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  /// Removes the banner (back to the default cover). The confirm step avoids
  /// destroying a custom cover with a single accidental tap.
  Future<void> _removeBanner() async {
    if (_uploadingBanner) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.nightBlue,
        title: Text('Remover banner?', style: AppTextStyles.title),
        content: Text(
          'O perfil volta a usar a capa padrão do MATRIX.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('REMOVER'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploadingBanner = true);
    try {
      await AppStateScope.of(context).clearBanner();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Banner removido.')),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Não foi possível remover o banner. Tente novamente.');
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  /// Opens the music picker (search → choose excerpt → confirm) and, when the
  /// user confirms, persists the excerpt. The server downloads the audio, so
  /// this can take a few seconds — the button shows progress meanwhile.
  Future<void> _pickMusic() async {
    if (_savingMusic) return;
    final state = AppStateScope.of(context);
    final pending = await Navigator.of(context).push<PendingProfileMusic>(
      MaterialPageRoute(
        builder: (_) => ProfileMusicPicker(
          initialQuery: state.currentUser?.nickname ?? '',
        ),
      ),
    );
    if (pending == null || !mounted) return;

    setState(() => _savingMusic = true);
    try {
      await state.setProfileMusic(
        result: pending.result,
        startMs: pending.startMs,
        durationMs: pending.durationMs,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Música do perfil atualizada.')),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Não foi possível salvar a música. Tente novamente.');
    } finally {
      if (mounted) setState(() => _savingMusic = false);
    }
  }

  /// Removes the pinned song (the confirm step avoids losing it by a stray
  /// tap, same as the banner).
  Future<void> _removeMusic() async {
    if (_savingMusic) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.nightBlue,
        title: Text('Remover música?', style: AppTextStyles.title),
        content: Text(
          'O perfil deixa de tocar a música.',
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('REMOVER'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingMusic = true);
    try {
      await AppStateScope.of(context).clearProfileMusic();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Música removida.')),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Não foi possível remover a música. Tente novamente.');
    } finally {
      if (mounted) setState(() => _savingMusic = false);
    }
  }

  /// Shared image source sheet + picker. Returns the chosen file or null when
  /// the user cancels (or an error was already surfaced).
  Future<XFile?> _pickImage({
    required String title,
    required int imageQuality,
    required double maxWidth,
    required double maxHeight,
  }) async {
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
            HudLabel(text: title),
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
    if (source == null || !mounted) return null;

    XFile? picked;
    if (source == ImageSource.gallery) {
      final result = await pickGalleryImage(
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      if (!mounted) return null;
      if (!result.isSuccess) {
        if (!result.cancelled && result.error != null && result.error!.isNotEmpty) {
          _showError(result.error!);
        }
        return null;
      }
      picked = result.file;
    } else {
      picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    }
    return picked;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await AppStateScope.of(context).updateProfile(
        nickname: _nicknameController.text.trim().replaceAll(RegExp(r'^@+'), ''),
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
                // ── Banner (cover) ─────────────────────────────────────
                // Same pick → upload → persist pipeline as the avatar; the
                // preview mirrors the profile layout (wide cover with the
                // photo overlapping its lower edge).
                _BannerPreview(
                  bannerUrl: user?.bannerUrl,
                  uploading: _uploadingBanner,
                  onPick: _pickBanner,
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _uploadingBanner ? null : _pickBanner,
                      icon: Icon(Icons.wallpaper_rounded,
                          size: 18, color: AppColors.electricBlue),
                      label: Text(
                        _uploadingBanner ? 'ENVIANDO...' : 'ALTERAR BANNER',
                        style: AppTextStyles.hud.copyWith(fontSize: 11),
                      ),
                    ),
                    if (user?.bannerUrl != null)
                      TextButton.icon(
                        onPressed: _uploadingBanner ? null : _removeBanner,
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.error),
                        label: Text(
                          'REMOVER',
                          style: AppTextStyles.hud.copyWith(fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceXl),
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        UserAvatar(
                            name: _nicknameController.text.isEmpty
                                ? (user?.nickname ?? '')
                                : _nicknameController.text,
                            seed: user?.avatarSeed ?? user?.nickname,
                            imageUrl: user?.avatarUrl,
                            size: 84,
                            // No decorative blue ring — the preview shows the
                            // bare photo, matching the profile screen.
                            ring: false,
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
                  label: 'Nickname',
                  controller: _nicknameController,
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
                // ── Música do perfil ──────────────────────────────────
                // Search the catalog → pick one of up to 3 options → choose
                // the excerpt (max 1:00) → confirm. The download happens on
                // the server only on confirm.
                const HudLabel(text: 'MÚSICA DO PERFIL'),
                const SizedBox(height: AppDimensions.spaceSm),
                _MusicPreview(music: user?.music, busy: _savingMusic),
                const SizedBox(height: AppDimensions.spaceSm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _savingMusic ? null : _pickMusic,
                      icon: Icon(Icons.music_note_rounded,
                          size: 18, color: AppColors.electricBlue),
                      label: Text(
                        _savingMusic
                            ? 'SALVANDO...'
                            : (user?.music == null
                                ? 'ESCOLHER MÚSICA'
                                : 'TROCAR MÚSICA'),
                        style: AppTextStyles.hud.copyWith(fontSize: 11),
                      ),
                    ),
                    if (user?.music != null)
                      TextButton.icon(
                        onPressed: _savingMusic ? null : _removeMusic,
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.error),
                        label: Text(
                          'REMOVER',
                          style: AppTextStyles.hud.copyWith(fontSize: 11),
                        ),
                      ),
                  ],
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

/// Preview of the pinned song in the edit screen: the title/artist and the
/// excerpt window, or a "no music yet" hint. Purely informational — the
/// search/choose flow lives in [ProfileMusicPicker].
class _MusicPreview extends StatelessWidget {
  const _MusicPreview({required this.music, required this.busy});

  final ProfileMusic? music;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.nightBlue,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: AppColors.electricBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.music_note_rounded, color: AppColors.electricBlue, size: 20),
          const SizedBox(width: AppDimensions.spaceSm),
          Expanded(
            child: busy
                ? Text('Salvando...', style: AppTextStyles.bodyMuted)
                : music == null
                    ? Text(
                        'Nenhuma música escolhida.',
                        style: AppTextStyles.bodyMuted,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            music!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(fontSize: 13),
                          ),
                          if (music!.artist.trim().isNotEmpty)
                            Text(
                              music!.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.hud.copyWith(
                                fontSize: 10,
                                color: AppColors.holographicBlue,
                              ),
                            ),
                          Text(
                            'Trecho ${music!.excerptLabel}',
                            style: AppTextStyles.hud.copyWith(fontSize: 10),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

/// Banner preview in the edit screen: a wide, rounded cover showing the
/// current banner (or the default gradient when none is set) with a tap
/// target to replace it and a loading overlay while uploading.
class _BannerPreview extends StatelessWidget {
  const _BannerPreview({
    required this.bannerUrl,
    required this.uploading,
    required this.onPick,
  });

  final String? bannerUrl;
  final bool uploading;
  final VoidCallback onPick;

  static const double _height = 120;

  @override
  Widget build(BuildContext context) {
    final hasBanner = bannerUrl != null && bannerUrl!.isNotEmpty;
    return GestureDetector(
      onTap: uploading ? null : onPick,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: SizedBox(
          height: _height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasBanner)
                CachedNetworkImage(
                  imageUrl: ApiConfig.resolveUrl(bannerUrl!),
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const _BannerPlaceholder(),
                  errorWidget: (_, __, ___) => const _BannerPlaceholder(),
                )
              else
                const _BannerPlaceholder(),
              if (uploading)
                const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black54),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.electricBlue,
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  right: AppDimensions.spaceSm,
                  bottom: AppDimensions.spaceSm,
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
    );
  }
}

/// Default cover look (no banner set): the MATRIX gradient + a HUD hint.
class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: const Center(child: HudLabel(text: 'SEM BANNER')),
    );
  }
}
