import 'package:flutter/material.dart';

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
import 'story_viewer.dart';

/// Faixa horizontal de Stories no topo do feed.
///
/// Lista rolável horizontalmente de cards QUADRADOS — avatar do autor
/// centralizado + nickname abaixo (com ellipsis: nunca estoura o card).
/// Reutiliza [UserAvatar]/[FramedAvatar]/[NicknameRenderer] (mesmo sistema de
/// avatar/nickname do feed) e abre o [StoryViewer] ao tocar. Nada disso
/// substitui o feed de posts, que continua logo abaixo.
class StoriesHeader extends StatelessWidget {
  const StoriesHeader({super.key, required this.state});

  final AppState state;

  /// Largura alvo de cada card. A quantidade visível se adapta à tela
  /// (responsivo) — sem dimensões presas a uma resolução específica.
  static const double _kCard = 92;

  @override
  Widget build(BuildContext context) {
    final groups = state.storyGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.spaceLg,
            AppDimensions.spaceMd,
            AppDimensions.spaceLg,
            AppDimensions.spaceSm,
          ),
          child: Row(
            children: [
              const HudLabel(text: 'STORIES', color: AppColors.electricBlue),
              const Spacer(),
              if (state.myStories.isEmpty)
                HudLabel(
                  text: 'Crie o seu em +',
                  color: AppColors.holographicBlue,
                ),
            ],
          ),
        ),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.spaceLg,
              0,
              AppDimensions.spaceLg,
              AppDimensions.spaceMd,
            ),
            child: Text(
              'Nenhum Story disponível.',
              style: AppTextStyles.bodyMuted,
            ),
          )
        else
          SizedBox(
            // Altura do card (quadrado) + espaço do nickname. Proporção
            // consistente: o nickname não altera a altura do card.
            height: _kCard + 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceLg,
              ),
              itemCount: groups.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppDimensions.spaceMd),
              // Um quadrado por AUTOR (o viewer avança pelas figurinhas dele).
              itemBuilder: (context, i) => _StoryCard(
                group: groups[i],
                size: _kCard,
                onTap: () => StoryViewer.open(context, state, startGroup: i),
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Um card quadrado de Story: avatar centralizado + nickname abaixo.
class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.group,
    required this.size,
    required this.onTap,
  });

  final StoryGroup group;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unviewed = !group.allViewed;
    final label = group.authorNickname;
    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.nightBlue,
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                border: Border.all(
                  color: unviewed ? AppColors.electricBlue : AppColors.deepBlue,
                  width: unviewed
                      ? AppDimensions.borderWidthActive
                      : AppDimensions.borderWidthThin,
                ),
                boxShadow: unviewed
                    ? [
                        BoxShadow(
                          color: AppColors.glowSmall,
                          blurRadius: AppDimensions.glowSmallBlur,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  // Capa (cover do vídeo ou a própria imagem) preenchendo o
                  // quadrado; o AVATAR vai por cima, centralizado.
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusLg - 2),
                      child: _StoryCover(group: group),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusLg - 2),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.absoluteBlack.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Avatar centralizado horizontalmente.
                  Center(
                    child: FramedAvatar(
                      frame: _frame(group),
                      size: size * 0.46,
                      child: UserAvatar(
                        name: label,
                        seed: label,
                        imageUrl: group.authorAvatarUrl,
                        size: size * 0.4,
                      ),
                    ),
                  ),
                  if (unviewed)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.electricBlue,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.electricBlue,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceXs),
          // Nickname SEMPRE dentro dos limites do card: uma linha + ellipsis.
          SizedBox(
            width: size,
            child: NicknameRenderer(
              label,
              baseStyle: AppTextStyles.caption.copyWith(fontSize: 11),
              background: AppColors.absoluteBlack,
              nameColor: group.authorNicknameColor,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  CosmeticItem? _frame(StoryGroup g) {
    if (g.authorFrameId == null) return null;
    return CosmeticItem(
      id: g.authorFrameId!,
      slot: CosmeticItem.avatarFrame,
      name: g.authorFrameId!,
      assetUrl: g.authorFrameAsset ?? '',
    );
  }
}

/// Capa do card: a primeira figurinha do autor (a mais recente).
class _StoryCover extends StatelessWidget {
  const _StoryCover({required this.group});

  final StoryGroup group;

  @override
  Widget build(BuildContext context) {
    final story = group.stories.first;
    final url = ApiConfig.resolveUrl(story.coverUrl);
    // Imagem de capa/mídia com cache — nunca baixa em resolução máxima
    // desnecessariamente (memCacheWidth limita o decode ao tamanho do card).
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 200,
      // STORIES NÃO USAM NEM UMA IMAGEM QUEBRADA NA CARA: cai no fundo.
      errorBuilder: (_, __, ___) => ColoredBox(
        color: AppColors.nightBlue,
        child: Center(
          child: Icon(
            story.isVideo
                ? Icons.videocam_rounded
                : Icons.image_not_supported_outlined,
            color: AppColors.holographicBlue,
            size: 22,
          ),
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: AppColors.nightBlue,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.electricBlue,
              ),
            ),
          ),
        );
      },
    );
  }
}
