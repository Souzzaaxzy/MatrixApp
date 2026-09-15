import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../data/api_config.dart';
import '../../models/story.dart';

/// Visualizador de Story — tela cheia, mídia em `BoxFit.contain` (proporção
/// preservada, nada deformado). Navegação:
///  * toque à DIREITA → próximo; à ESQUERDA → anterior;
///  * arrastar para BAIXO ou o botão de fechar encerra;
///  * o Android Back fecha (rota normal do Navigator — o back global continua
///    funcionando).
///
/// Um único vídeo é instanciado por vez (o controller é descartado ao trocar
/// de Story) — nada de vários vídeos simultâneos consumindo RAM.
class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.state,
    required this.startGroup,
  });

  final AppState state;

  /// Grupo do autor por onde o viewer começa.
  final int startGroup;

  /// Abre o viewer com a transição padrão do Navigator (back preservado).
  static Future<void> open(
    BuildContext context,
    AppState state, {
    required int startGroup,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StoryViewer(state: state, startGroup: startGroup),
      ),
    );
  }

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late int _groupIndex;
  int _storyIndex = 0;

  VideoPlayerController? _video;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.startGroup.clamp(
      0,
      widget.state.storyGroups.isEmpty ? 0 : widget.state.storyGroups.length - 1,
    );
    _markCurrentViewed();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVideo());
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    super.dispose();
  }

  List<StoryGroup> get _groups => widget.state.storyGroups;

  StoryGroup? get _group =>
      _groups.isEmpty ? null : _groups[_groupIndex.clamp(0, _groups.length - 1)];

  Story? get _story {
    final g = _group;
    if (g == null || g.stories.isEmpty) return null;
    return g.stories[_storyIndex.clamp(0, g.stories.length - 1)];
  }

  void _markCurrentViewed() {
    final story = _story;
    if (story != null && !story.viewed) {
      // Fire-and-forget: a marcação nunca bloqueia o viewer.
      widget.state.markStoryViewed(story.id);
    }
  }

  /// Cria/descarta o controller do vídeo conforme o Story atual — apenas UM
  /// vídeo vivo por vez.
  Future<void> _syncVideo() async {
    final story = _story;
    await _disposeVideo();
    if (story == null || !story.isVideo) return;
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(ApiConfig.resolveUrl(story.mediaUrl)));
    try {
      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(0); // stories começam mudos
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onVideoTick);
      setState(() {
        _video = controller;
        _videoReady = true;
      });
    } catch (_) {
      await controller.dispose();
    }
  }

  Future<void> _disposeVideo() async {
    final v = _video;
    _video = null;
    _videoReady = false;
    if (v != null) {
      v.removeListener(_onVideoTick);
      await v.dispose();
    }
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null || !mounted) return;
    final value = v.value;
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _next();
    }
  }

  void _next() {
    if (!mounted) return;
    final g = _group;
    if (g == null) return;
    if (_storyIndex < g.stories.length - 1) {
      setState(() => _storyIndex++);
      _markCurrentViewed();
      _syncVideo();
      return;
    }
    // Fim do autor → próximo AUTOR.
    if (_groupIndex < _groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _markCurrentViewed();
      _syncVideo();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _previous() {
    if (!mounted) return;
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _markCurrentViewed();
      _syncVideo();
      return;
    }
    if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        final g = _groups[_groupIndex];
        _storyIndex = g.stories.isEmpty ? 0 : g.stories.length - 1;
      });
      _markCurrentViewed();
      _syncVideo();
    }
  }

  Future<void> _deleteCurrent() async {
    final story = _story;
    if (story == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.state.deleteStory(story.id);
      if (!mounted) return;
      if (_groups.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        if (_groupIndex >= _groups.length) _groupIndex = _groups.length - 1;
        final g = _groups[_groupIndex];
        _storyIndex = g.stories.isEmpty
            ? 0
            : _storyIndex.clamp(0, g.stories.length - 1);
      });
      _syncVideo();
      messenger.showSnackBar(
        const SnackBar(content: Text('Story excluído.')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível excluir o Story.')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bluishBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          side: BorderSide(color: AppColors.deepBlue),
        ),
        title: Text(
          'Excluir Story?',
          style: AppTextStyles.hud
              .copyWith(fontSize: 16, color: AppColors.techWhite),
        ),
        content: Text(
          'O Story será removido do MATRIX.',
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
            child: Text('Excluir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _deleteCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final group = _group;
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      body: GestureDetector(
        // Arrastar para baixo fecha (gesto natural de stories).
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 250) {
            Navigator.of(context).maybePop();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: story == null
                  ? Center(
                      child: const HudLabel(text: 'STORY INDISPONÍVEL'),
                    )
                  : _StoryMedia(story: story, video: _video, videoReady: _videoReady),
            ),
            // Toque esquerda/direita para navegar.
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _previous,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _next,
                    ),
                  ),
                ],
              ),
            ),
            // Cabeçalho: progresso + autor + fechar (+ excluir quando é meu).
            SafeArea(
              child: Column(
                children: [
                  _ProgressBars(
                    count: group?.stories.length ?? 0,
                    current: _storyIndex,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spaceLg,
                      vertical: AppDimensions.spaceSm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            group?.authorNickname ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.h3.copyWith(fontSize: 16),
                          ),
                        ),
                        if (story?.mine ?? false)
                          IconButton(
                            tooltip: 'Excluir Story',
                            icon: Icon(Icons.delete_outline_rounded,
                                color: AppColors.error),
                            onPressed: _confirmDelete,
                          ),
                        IconButton(
                          tooltip: 'Fechar',
                          icon: Icon(Icons.close_rounded,
                              color: AppColors.techWhite),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                  if ((story?.caption ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.spaceLg,
                      ),
                      child: Text(
                        story!.caption,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.techWhite),
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mídia do Story: imagem (cache) ou vídeo, sempre `contain`.
class _StoryMedia extends StatelessWidget {
  const _StoryMedia({
    required this.story,
    required this.video,
    required this.videoReady,
  });

  final Story story;
  final VideoPlayerController? video;
  final bool videoReady;

  @override
  Widget build(BuildContext context) {
    if (story.isVideo) {
      final v = video;
      if (v != null && videoReady && v.value.isInitialized) {
        return Center(
          child: AspectRatio(
            aspectRatio: v.value.aspectRatio == 0 ? 9 / 16 : v.value.aspectRatio,
            child: VideoPlayer(v),
          ),
        );
      }
      // Enquanto o vídeo não está pronto, mostra a capa (se houver).
      return _StoryImage(url: story.coverUrl);
    }
    return _StoryImage(url: story.mediaUrl);
  }
}

class _StoryImage extends StatelessWidget {
  const _StoryImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CachedNetworkImage(
        imageUrl: ApiConfig.resolveUrl(url),
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
          child: CircularProgressIndicator(color: AppColors.electricBlue),
        ),
        errorWidget: (_, __, ___) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: AppColors.holographicBlue,
            size: 42,
          ),
        ),
      ),
    );
  }
}

/// Barras de progresso (uma por Story do autor) — a atual destacada.
class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceXs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i <= current
                      ? AppColors.electricBlue
                      : AppColors.techWhite.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
