import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../data/api_config.dart';
import '../../data/repositories/sticker_repository.dart';

/// Resultado de uma importação concluída pelo [StickerlyImportSheet].
class StickerlyImportResult {
  const StickerlyImportResult({
    required this.packageId,
    required this.packageName,
    required this.created,
  });

  final String packageId;
  final String packageName;
  final int created;
}

/// Modal para adicionar um pacote de figurinhas pelo CÓDIGO do Sticker.ly
/// (ex.: `QSXLKY`) ou pelo link de compartilhamento
/// (`https://sticker.ly/s/QSXLKY`).
///
/// Fluxo: código → [BUSCAR] → prévia (nome/autor/capa/figurinhas) →
/// [ADICIONAR AO MATRIX]. Nada é importado sem confirmação. Consulta e
/// download acontecem no SERVIDOR — o APK nunca fala com o Sticker.ly nem
/// carrega credenciais.
///
/// Reutiliza o sistema de stickers existente: o pacote criado é o mesmo
/// modelo/endpoint usado pelo compartilhamento do Android.
class StickerlyImportSheet extends StatefulWidget {
  const StickerlyImportSheet({super.key, required this.state});

  final AppState state;

  /// Abre o modal com uma transição suave e devolve o resultado (ou null se
  /// o usuário cancelar).
  static Future<StickerlyImportResult?> open(
    BuildContext context, {
    required AppState state,
  }) {
    return showModalBottomSheet<StickerlyImportResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Barreira um pouco mais leve: o painel de figurinhas continua visível
      // atrás, reforçando que o modal é uma etapa do próprio painel.
      barrierColor: AppColors.absoluteBlack.withValues(alpha: 0.62),
      builder: (_) => StickerlyImportSheet(state: state),
    );
  }

  @override
  State<StickerlyImportSheet> createState() => _StickerlyImportSheetState();
}

class _StickerlyImportSheetState extends State<StickerlyImportSheet> {
  final TextEditingController _codeCtrl = TextEditingController();

  bool _loadingPreview = false;
  bool _importing = false;
  String? _error;
  StickerlyPackPreview? _preview;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Digite o código do pacote do Sticker.ly.');
      return;
    }
    setState(() {
      _loadingPreview = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await widget.state.previewStickerlyPack(code);
      if (!mounted) return;
      setState(() => _preview = preview);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Não foi possível carregar o pacote. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || _importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await widget.state.importStickerlyPack(preview.code);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final created = result.created;
      final already = result.already || created == 0;
      final packageId = result.package?.id ?? '';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            already
                ? 'Este pacote já está na sua coleção.'
                : '$created figurinha(s) adicionada(s) à sua coleção!',
          ),
        ),
      );
      navigator.pop(
        StickerlyImportResult(
          packageId: packageId,
          packageName: result.package?.name ?? preview.name,
          created: created,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = 'Não foi possível importar o pacote. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // O modal sobe junto com o teclado quando o usuário digita o código.
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusXl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spaceXl,
                AppDimensions.spaceMd,
                AppDimensions.spaceXl,
                AppDimensions.spaceXl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.holographicBlue.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),
                  const Center(
                    child: HudLabel(text: 'ADICIONAR PACOTE'),
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),
                  if (_preview == null) ..._buildCodeForm() else ..._buildPreview(_preview!),
                  if (_error != null) ...[
                    const SizedBox(height: AppDimensions.spaceMd),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: AppDimensions.spaceSm),
                        Expanded(
                          child: Text(
                            _error!,
                            style: AppTextStyles.bodyMuted
                                .copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCodeForm() {
    return [
      Text('Código do pacote Sticker.ly', style: AppTextStyles.label),
      const SizedBox(height: AppDimensions.spaceSm),
      TextField(
        controller: _codeCtrl,
        enabled: !_loadingPreview,
        autocorrect: false,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9/:.\\-]')),
          LengthLimitingTextInputFormatter(200),
        ],
        style: AppTextStyles.body,
        cursorColor: AppColors.electricBlue,
        decoration: InputDecoration(
          hintText: 'Ex.: QSXLKY ou sticker.ly/s/QSXLKY',
          hintStyle: AppTextStyles.bodyMuted,
          filled: true,
          fillColor: AppColors.bluishBlack,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spaceLg,
            vertical: AppDimensions.spaceMd,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.spaceSm),
            borderSide: BorderSide(color: AppColors.deepBlue),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.spaceSm),
            borderSide: BorderSide(
              color: AppColors.primaryBlue,
              width: AppDimensions.borderWidthActive,
            ),
          ),
        ),
      ),
      const SizedBox(height: AppDimensions.spaceSm),
      Text(
        'No Sticker.ly, toque em compartilhar o pacote e copie o código '
        '(ou cole o link).',
        style: AppTextStyles.caption
            .copyWith(color: AppColors.holographicBlue),
      ),
      const SizedBox(height: AppDimensions.spaceLg),
      Row(
        children: [
          Expanded(
            child: MatrixButton(
              label: 'CANCELAR',
              variant: MatrixButtonVariant.outline,
              onPressed: _loadingPreview
                  ? null
                  : () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: AppDimensions.spaceMd),
          Expanded(
            child: MatrixButton(
              label: 'BUSCAR',
              icon: Icons.search_rounded,
              isLoading: _loadingPreview,
              onPressed: _loadingPreview ? null : _search,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildPreview(StickerlyPackPreview preview) {
    final name = preview.name.isNotEmpty ? preview.name : 'Pacote ${preview.code}';
    final author = preview.author.isNotEmpty ? preview.author : 'Sticker.ly';
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            child: ColoredBox(
              color: AppColors.nightBlue,
              child: SizedBox(
                width: 64,
                height: 64,
                child: preview.iconUrl.isEmpty
                    ? Icon(Icons.auto_awesome,
                        color: AppColors.holographicBlue, size: 26)
                    : CachedNetworkImage(
                        imageUrl: preview.iconUrl,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.auto_awesome,
                          color: AppColors.holographicBlue,
                          size: 26,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text('por $author', style: AppTextStyles.bodyMuted),
                const SizedBox(height: AppDimensions.spaceXs),
                HudLabel(
                  text: preview.stickerCount == 1
                      ? '1 FIGURINHA'
                      : '${preview.stickerCount} FIGURINHAS',
                  color: AppColors.electricBlue,
                ),
              ],
            ),
          ),
        ],
      ),
      if (preview.alreadyInstalled) ...[
        const SizedBox(height: AppDimensions.spaceMd),
        Container(
          padding: const EdgeInsets.all(AppDimensions.spaceMd),
          decoration: BoxDecoration(
            color: AppColors.electricBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: Border.all(color: AppColors.electricBlue),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.electricBlue, size: 18),
              const SizedBox(width: AppDimensions.spaceSm),
              Expanded(
                child: Text(
                  'Este pacote já está na sua coleção.',
                  style: AppTextStyles.bodyMuted
                      .copyWith(color: AppColors.techWhite),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: AppDimensions.spaceLg),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: AppDimensions.spaceXs,
          crossAxisSpacing: AppDimensions.spaceXs,
          childAspectRatio: 1,
        ),
        itemCount: preview.previewUrls.length,
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          child: ColoredBox(
            color: AppColors.nightBlue,
            child: CachedNetworkImage(
              imageUrl: preview.previewUrls[index],
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                color: AppColors.holographicBlue,
                size: 18,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: AppDimensions.spaceLg),
      MatrixButton(
        label: 'ADICIONAR AO MATRIX',
        icon: Icons.add_rounded,
        expanded: true,
        isLoading: _importing,
        onPressed: _importing ? null : _import,
      ),
      const SizedBox(height: AppDimensions.spaceSm),
      MatrixButton(
        label: 'CANCELAR',
        variant: MatrixButtonVariant.outline,
        expanded: true,
        onPressed: _importing ? null : () => Navigator.of(context).maybePop(),
      ),
    ];
  }
}