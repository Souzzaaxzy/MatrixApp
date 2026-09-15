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
    // Acabamento arredondado na BASE da faixa (sem linha separadora) — a
    // transição para o feed fica contínua, no estilo stories do Instagram.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bluishBlack.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppDimensions.radiusXl),
        ),
      ),
      child: Column(
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
            // Altura do card: avatar (acima) + quadrado do preview +
            // nickname (abaixo). O nickname/avatar são estáveis, então a
            // altura é determinística (sem depender do conteúdo).
            height: _kCard * 1.30 + 32,
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
        const SizedBox(height: AppDimensions.spaceSm),
      ],
      ),
    );
  }
}

/// Um card de Story: AVATAR acima, PREVIEW (quadrado, preenchido por
/// inteiro) no meio e nickname abaixo.
///
/// O avatar NÃO fica sobre a mídia nem ocupa área interna do preview — ele é
/// um elemento separado ACIMA do quadrado, então a mídia usa 100% da área do
/// Story (foto/vídeo: capa; texto: o próprio texto).
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
    final story = group.stories.first;
    // Avatar FORA do preview (acima), em tamanho consistente.
    final avatarSize = size * 0.30;
    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1) FOTO DE PERFIL — acima do preview, nunca sobre a mídia.
          FramedAvatar(
            frame: _frame(group),
            size: avatarSize,
            child: UserAvatar(
              name: label,
              seed: label,
              imageUrl: group.authorAvatarUrl,
              size: avatarSize * 0.86,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceXs),
          // 2) PREVIEW — quadrado do Story, totalmente preenchido pela mídia.
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.nightBlue,
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                // NÃO VISTO → borda BRANCA clara; visto → borda neutra.
                border: Border.all(
                  color: unviewed ? Colors.white : AppColors.deepBlue,
                  width: unviewed ? 2 : AppDimensions.borderWidthThin,
                ),
                boxShadow: unviewed
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: AppDimensions.glowSmallBlur,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg - 2),
                // A mídia ocupa TODO o quadrado (sem avatar interno nem
                // margens indevidas).
                child: _StoryCover(story: story),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceXs),
          // 3) NICKNAME — abaixo do preview, dentro dos limites do card.
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
  const _StoryCover({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    // Story de TEXTO: sem mídia — mostra o texto em um painel legível
    // (mesma estrutura de card, apenas outro conteúdo).
    if (story.isText) {
      return ColoredBox(
        color: AppColors.bluishBlack,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              story.text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontSize: 10,
                color: AppColors.techWhite,
              ),
            ),
          ),
        ),
      );
    }
    final url = ApiConfig.resolveUrl(story.coverUrl);
    // Imagem de capa/mídia com cache — nunca baixa em resolução máxima
    // desnecessariamente (cacheWidth limita o decode ao tamanho do card).
    // Para VÍDEO usa a CAPA (thumbnail), nunca o vídeo completo.
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 200,
      // NÃO MOSTRAR IMAGEM QUEBRADA: cai num fundo com ícone do tipo.
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
