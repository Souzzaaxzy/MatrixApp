import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../data/api_config.dart';
import '../../models/conversation.dart';

/// Bloco de referência ao Story dentro de uma mensagem de RESPOSTA.
///
/// Mostra "respondeu ao seu stories" + a thumbnail do Story (ou o texto, no
/// caso de um Story de texto). A thumbnail vem da SNAPSHOT guardada junto da
/// mensagem, então a referência continua renderizando mesmo depois de o
/// Story expirar (24h) — a conversa nunca quebra por causa disso.
///
/// Para VÍDEO usa SEMPRE a capa (thumbnailUrl), nunca baixando o vídeo.
class StoryReplyReference extends StatelessWidget {
  const StoryReplyReference({
    super.key,
    required this.story,
    required this.mine,
  });

  final StoryReference story;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTextStyles.caption.copyWith(
      fontSize: 11,
      color: mine ? AppColors.techWhite : AppColors.holographicBlue,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: mine ? AppColors.techWhite : AppColors.electricBlue,
            ),
            const SizedBox(width: 4),
            Text('respondeu ao seu stories', style: labelStyle),
          ],
        ),
        const SizedBox(height: AppDimensions.spaceXs),
        // Caixa da referência (thumb ou o próprio texto do Story).
        ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          child: Container(
            width: 150,
            height: 90,
            color: AppColors.nightBlue,
            child: story.isText
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.spaceSm),
                      child: Text(
                        story.preview.isNotEmpty
                            ? story.preview
                            : '(Story de texto)',
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.techWhite,
                        ),
                      ),
                    ),
                  )
                : _thumb(),
          ),
        ),
      ],
    );
  }

  Widget _thumb() {
    final url = story.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return Center(
        child: Icon(
          Icons.auto_awesome_rounded,
          color: AppColors.holographicBlue,
          size: 22,
        ),
      );
    }
    return Image.network(
      ApiConfig.resolveUrl(url),
      fit: BoxFit.cover,
      cacheWidth: 300,
      // Referência indisponível (Story expirado/removido) → placeholder,
      // NUNCA um erro quebrando a bolha.
      errorBuilder: (_, __, ___) => Center(
        child: Icon(
          Icons.auto_awesome_rounded,
          color: AppColors.holographicBlue,
          size: 22,
        ),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.electricBlue,
            ),
          ),
        );
      },
    );
  }
}