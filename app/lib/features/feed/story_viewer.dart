import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/framed_avatar.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/nickname_renderer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/api_config.dart';
import '../../models/cosmetic_item.dart';
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

class _StoryViewerState extends State<StoryViewer>
    with SingleTickerProviderStateMixin {
  late int _groupIndex;
  int _storyIndex = 0;

  /// Duração de exibição de uma FOTO (Stories: 5s). Vídeos usam a duração
  /// real do controller.
  static const Duration _imageDuration = Duration(seconds: 5);

  /// Linha de progresso do Story ATUAL: anima de 0→1 em sincronia com a
  /// mídia (5s na foto; a duração real no vídeo) e dispara o avanço no fim.
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _imageDuration,
  )..addStatusListener(_onProgressStatus);

  /// Guarda o controller de vídeo atual para animar a barra pela duração real.
  bool _advancedForStory = false;

  VideoPlayerController? _video;
  bool _videoReady = false;

  // Resposta ao Story: campo de texto + envio (vira MENSAGEM REAL no chat).
  final TextEditingController _replyCtrl = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  bool _sendingReply = false;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.startGroup.clamp(
      0,
      widget.state.storyGroups.isEmpty ? 0 : widget.state.storyGroups.length - 1,
    );
    _markCurrentViewed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncVideo();
      _startProgress();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  /// Auto-avanço quando a linha de progresso completa (foto) — vídeos usam
  /// a posição real do controller. Nunca dispara duas vezes para o mesmo
  /// Story (`_advancedForStory`).
  void _onProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_advancedForStory) return;
    _advancedForStory = true;
    _next();
  }

  /// (Re)inicia a linha de progresso para o Story atual: 5s fixos para foto
  /// (e texto) ou a duração real do vídeo quando disponível.
  void _startProgress() {
    final story = _story;
    if (story == null) return;
    _advancedForStory = false;
    Duration target = _imageDuration;
    final v = _video;
    if (story.isVideo && v != null && v.value.isInitialized) {
      final d = v.value.duration;
      if (d > Duration.zero) target = d;
    }
    _progress.duration = target;
    _progress.forward(from: 0);
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
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(ApiConfig.resolveUrl(story.mediaUrl ?? story.thumbnailUrl ?? '')),
    );
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
      // A barra passa a acompanhar a DURAÇÃO REAL do vídeo.
      _startProgress();
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
      _startProgress();
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
      _startProgress();
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
      _startProgress();
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
      _startProgress();
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

  Future<void> _toggleLike() async {
    final story = _story;
    if (story == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.state.toggleStoryLike(story.id);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível curtir o Story.')),
      );
    }
  }

  /// Envia a resposta: o SERVIDOR cria uma MENSAGEM REAL no chat entre quem
  /// respondeu e o autor do Story (mesma infraestrutura de conversas).
  Future<void> _sendReply() async {
    final story = _story;
    if (story == null || _sendingReply) return;
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sendingReply = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.state.replyToStory(story.id, text);
      if (!mounted) return;
      _replyCtrl.clear();
      _replyFocus.unfocus();
      setState(() => _sendingReply = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Resposta enviada para o chat.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sendingReply = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a resposta.')),
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
    // O viewer também ouve o AppState: curtir (com o flip otimista do
    // coração), marcar como visto e navegar repintam na hora, sem recarregar
    // a tela nem reiniciar o app.
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
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
                  // Linha de progresso: uma por Story do autor; a ATUAL
                  // avança em tempo real (5s na foto, duração real no vídeo)
                  // e as demais ficam concluídas/não iniciadas.
                  _ProgressBars(
                    count: group?.stories.length ?? 0,
                    current: _storyIndex,
                    progress: _progress,
                  ),
                  // Identidade do autor: FOTO centralizada acima do NOME —
                  // os MESMOS componentes usados em grupos/DM.
                  _StoryIdentity(
                    group: group,
                    onDelete: (story?.mine ?? false) ? _confirmDelete : null,
                    onClose: () => Navigator.of(context).maybePop(),
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
                  // Barra de interação: "Responda a esse stories" + coração.
                  // Não é mostrada no próprio Story (não faz sentido
                  // responder/curtir a si mesmo).
                  if (story != null && !story.mine)
                    _StoryInteractionBar(
                      controller: _replyCtrl,
                      focusNode: _replyFocus,
                      sending: _sendingReply,
                      liked: story.liked,
                      likeCount: story.likeCount,
                      onSend: _sendReply,
                      onToggleLike: _toggleLike,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      );
      },
    );
  }
}

/// Barra inferior do visualizador: campo "Responda a esse stories" (bordas
/// arredondadas) + botão de coração no MESMO padrão do feed (♡/♥).
class _StoryInteractionBar extends StatelessWidget {
  const _StoryInteractionBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.liked,
    required this.likeCount,
    required this.onSend,
    required this.onToggleLike,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool liked;
  final int likeCount;
  final VoidCallback onSend;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spaceLg,
        0,
        AppDimensions.spaceLg,
        AppDimensions.spaceMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.absoluteBlack.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
                border: Border.all(color: AppColors.deepBlue),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg,
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !sending,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: AppTextStyles.body.copyWith(color: AppColors.techWhite),
                cursorColor: AppColors.electricBlue,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Responda a esse stories',
                  hintStyle: AppTextStyles.bodyMuted,
                  suffixIcon: sending
                      ? const Padding(
                          padding: EdgeInsets.all(
                            AppDimensions.spaceSm,
                          ),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.electricBlue,
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Enviar resposta',
                          icon: Icon(
                            Icons.send_rounded,
                            color: AppColors.electricBlue,
                            size: 20,
                          ),
                          onPressed: onSend,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spaceSm),
          // Coração: MESMO padrão visual do sistema de curtidas do feed.
          Semantics(
            label: 'Curtir Story',
            button: true,
            child: GestureDetector(
              onTap: onToggleLike,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(AppDimensions.spaceXs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked ? AppColors.error : AppColors.techWhite,
                      size: 28,
                    ),
                    if (likeCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$likeCount',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.techWhite,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
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
    // Story de TEXTO: sem mídia — o texto aparece CENTRALIZADO e legível.
    if (story.isText) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceXxl),
          child: Text(
            story.text,
            textAlign: TextAlign.center,
            style: AppTextStyles.h3.copyWith(
              fontSize: 24,
              color: AppColors.techWhite,
            ),
          ),
        ),
      );
    }
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
    return _StoryImage(url: story.mediaUrl ?? '');
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

/// Barras de progresso (uma por Story do autor). A barra ATUAL anima em
/// tempo real (0→1) sincronizada à mídia; as anteriores ficam cheias e as
/// seguintes vazias.
class _ProgressBars extends StatelessWidget {
  const _ProgressBars({
    required this.count,
    required this.current,
    required this.progress,
  });

  final int count;
  final int current;
  final Animation<double> progress;

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
                  color: AppColors.techWhite.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: i < current
                        // Já visto neste passe → cheio.
                        ? FractionallySizedBox(
                            widthFactor: 1,
                            child: ColoredBox(
                              color: AppColors.electricBlue,
                              child: const SizedBox(height: 3),
                            ),
                          )
                        : i == current
                            // Atual → anima de 0→1 em sincronia com a mídia.
                            ? AnimatedBuilder(
                                animation: progress,
                                builder: (context, _) => FractionallySizedBox(
                                  widthFactor: progress.value.clamp(0.0, 1.0),
                                  child: ColoredBox(
                                    color: AppColors.electricBlue,
                                    child: const SizedBox(height: 3),
                                  ),
                                ),
                              )
                            // Ainda não iniciado → vazio.
                            : const SizedBox(height: 3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Identidade do autor dentro do Story: FOTO centralizada ACIMA do NOME,
/// reutilizando `UserAvatar`/`FramedAvatar`/`NicknameRenderer` — o mesmo
/// visual de grupos/DM. O nickname trunca com ellipsis (nunca sai da tela).
class _StoryIdentity extends StatelessWidget {
  const _StoryIdentity({
    required this.group,
    required this.onDelete,
    required this.onClose,
  });

  final StoryGroup? group;
  final VoidCallback? onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final g = group;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceLg,
        vertical: AppDimensions.spaceSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Botão de fechar alinhado ao topo (área segura/touch target).
          IconButton(
            tooltip: 'Fechar',
            icon: Icon(Icons.close_rounded, color: AppColors.techWhite),
            onPressed: onClose,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (g != null)
                  FramedAvatar(
                    frame: _frameOf(g),
                    size: 56,
                    child: UserAvatar(
                      name: g.authorNickname,
                      seed: g.authorNickname,
                      imageUrl: g.authorAvatarUrl,
                      size: 48,
                    ),
                  ),
                const SizedBox(height: AppDimensions.spaceXs),
                if (g != null)
                  NicknameRenderer(
                    g.authorNickname,
                    baseStyle: AppTextStyles.h3.copyWith(fontSize: 16),
                    background: AppColors.absoluteBlack,
                    nameColor: g.authorNicknameColor,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
          // Espaço espelhando o botão de fechar (mantém o nome centralizado)
          // + ação de excluir quando é o próprio Story.
          SizedBox(
            width: 48,
            child: onDelete != null
                ? IconButton(
                    tooltip: 'Excluir Story',
                    icon: Icon(Icons.delete_outline_rounded,
                        color: AppColors.error),
                    onPressed: onDelete,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  CosmeticItem? _frameOf(StoryGroup g) {
    if (g.authorFrameId == null) return null;
    return CosmeticItem(
      id: g.authorFrameId!,
      slot: CosmeticItem.avatarFrame,
      name: g.authorFrameId!,
      assetUrl: g.authorFrameAsset ?? '',
    );
  }
}
