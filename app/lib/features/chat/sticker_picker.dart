import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/hud_label.dart';
import '../../data/api_config.dart';
import '../../models/sticker.dart';
import 'stickerly_import_sheet.dart';

/// O seletor nativo de figurinhas do MATRIX.
///
/// Painel inferior integrado ao composer (DM e grupos): grade responsiva e
/// COMPACTA de figurinhas com abas Recentes / Favoritos / Pacotes e um botão
/// "+ Adicionar" para importar um pacote pelo código do Sticker.ly. Ao tocar
/// numa figurinha ela é enviada IMEDIATAMENTE (fluxo WhatsApp). Favoritar/
/// desfavoritar é feito com toque longo numa figurinha — o estado é
/// persistido no servidor.
class StickerPicker extends StatefulWidget {
  const StickerPicker({
    super.key,
    required this.state,
    required this.onPick,
  });

  final AppState state;

  /// Chamado quando o usuário toca numa figurinha para enviá-la.
  final void Function(Sticker sticker) onPick;

  /// Altura do painel — usada pelo host para animar a abertura/fechamento
  /// (escala/opacidade) sem medir o conteúdo a cada frame.
  static const double panelHeight = 268;

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

enum _StickerTab { recents, favorites, packages }

class _StickerPickerState extends State<StickerPicker>
    with SingleTickerProviderStateMixin {
  _StickerTab _tab = _StickerTab.recents;
  String? _selectedPackageId;

  /// Anima a troca de conteúdo das abas/pacotes (curta e leve).
  late final AnimationController _switchCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Carrega (ou atualiza) o catálogo/favoritos/recentes ao abrir o
      // painel — operações leves e idempotentes.
      widget.state.loadStickers();
      widget.state.loadStickerFavorites();
      widget.state.loadStickerRecents();
    });
  }

  @override
  void dispose() {
    _switchCtrl.dispose();
    super.dispose();
  }

  /// Troca a aba/pacote re-disparando o fade (nunca reconstrói o catálogo).
  void _switchTo(_StickerTab tab, {String? packageId}) {
    if (_tab == tab && _selectedPackageId == packageId) return;
    setState(() {
      _tab = tab;
      _selectedPackageId = packageId;
    });
    _switchCtrl.forward(from: 0);
  }

  void _pickSticker(Sticker sticker) {
    widget.onPick(sticker);
  }

  void _toggleFavorite(Sticker sticker) {
    if (sticker.favorited) {
      widget.state.unfavoriteSticker(sticker.id);
    } else {
      widget.state.favoriteSticker(sticker.id);
    }
  }

  void _openPackage(String packageId) {
    _switchTo(_StickerTab.packages, packageId: packageId);
  }

  /// Abre o modal "Adicionar pacote" (código do Sticker.ly), com uma
  /// transição suave própria. Ao importar, atualiza o catálogo e abre o
  /// pacote recém-adicionado.
  Future<void> _openAddPackage() async {
    final result = await StickerlyImportSheet.open(
      context,
      state: widget.state,
    );
    if (!mounted || result == null) return;
    await widget.state.loadStickers();
    if (!mounted) return;
    _switchTo(_StickerTab.packages, packageId: result.packageId);
  }

  List<Sticker> get _recents {
    if (widget.state.isLoadingStickerRecents) return const [];
    return widget.state.stickerRecents;
  }

  List<Sticker> get _favorites => widget.state.stickerFavorites;

  List<StickerPackage> get _installedPackages =>
      widget.state.installedStickerPackages;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBarBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.primaryBlue,
            width: AppDimensions.borderWidthThin,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: StickerPicker.panelHeight,
          child: Column(
            children: [
              // Barra de abas
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spaceMd,
                  vertical: AppDimensions.spaceXs,
                ),
                child: Row(
                  children: [
                    _TabButton(
                      label: 'Recentes',
                      selected: _tab == _StickerTab.recents,
                      onTap: () => _switchTo(_StickerTab.recents),
                    ),
                    const SizedBox(width: AppDimensions.spaceXs),
                    _TabButton(
                      label: 'Favoritos',
                      selected: _tab == _StickerTab.favorites,
                      onTap: () => _switchTo(_StickerTab.favorites),
                    ),
                    const Spacer(),
                    // Navegação horizontal dos pacotes instalados.
                    SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        children: [
                          for (final pkg in _installedPackages)
                            _PackageIcon(
                              package: pkg,
                              selected: _selectedPackageId == pkg.id,
                              onTap: () => _openPackage(pkg.id),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spaceXs),
                    // Importa um pacote pelo código do Sticker.ly.
                    _AddPackageButton(onTap: _openAddPackage),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FadeTransition(
                  opacity: _switchCtrl,
                  // Fade curto e barato: sem blur, sem partículas, sem
                  // reconstruir o catálogo — só a opacidade do conteúdo.
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case _StickerTab.recents:
        return _buildGrid(
          stickers: _recents,
          emptyTitle: 'Nenhuma figurinha recente',
          emptyMessage:
              'Envie uma figurinha para vê-la aqui e reutilizá-la com um toque.',
        );
      case _StickerTab.favorites:
        return _buildGrid(
          stickers: _favorites,
          emptyTitle: 'Nenhuma figurinha favorita',
          emptyMessage:
              'Toque e segure numa figurinha para favoritá-la.\nFavoritos continuam disponíveis mesmo se o pacote for removido.',
        );
      case _StickerTab.packages:
        final pkg = _selectedPackage;
        if (pkg == null) {
          return const _PickerEmpty(
            title: 'Nenhum pacote instalado',
            message:
                'Toque em + para adicionar um pacote pelo código do Sticker.ly.',
          );
        }
        return _buildGrid(stickers: pkg.stickers);
    }
  }

  StickerPackage? get _selectedPackage {
    final id = _selectedPackageId;
    if (id == null) return null;
    for (final p in _installedPackages) {
      if (p.id == id) return p;
    }
    return _installedPackages.isNotEmpty ? _installedPackages.first : null;
  }

  Widget _buildGrid({
    required List<Sticker> stickers,
    String emptyTitle = 'Nada por aqui',
    String emptyMessage = '',
  }) {
    if (stickers.isEmpty) {
      return _PickerEmpty(title: emptyTitle, message: emptyMessage);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Grade responsiva: densidade (área alvo por célula) ajustada à
        // largura — mais compacta como pedido, ocupando bem a linha sem
        // fixar colunas que quebrem em telas diferentes.
        final columns =
            (constraints.maxWidth / _kStickerTile).floor().clamp(4, 8);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.spaceMd,
            AppDimensions.spaceSm,
            AppDimensions.spaceMd,
            AppDimensions.spaceSm,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppDimensions.spaceXs,
            crossAxisSpacing: AppDimensions.spaceXs,
            childAspectRatio: 1,
          ),
          itemCount: stickers.length,
          itemBuilder: (context, index) {
            final sticker = stickers[index];
            return _StickerTile(
              sticker: sticker,
              onTap: () => _pickSticker(sticker),
              onLongPress: () => _toggleFavorite(sticker),
            );
          },
        );
      },
    );
  }

  /// Largura alvo de cada célula (compacta, ~5 colunas num telefone comum).
  static const double _kStickerTile = 62;
}

/// Botão "+ Adicionar" do painel de figurinhas (abre a importação por
/// código do Sticker.ly). Compacto e alinhado às demais ações do painel.
class _AddPackageButton extends StatelessWidget {
  const _AddPackageButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceSm),
        decoration: BoxDecoration(
          color: AppColors.electricBlue.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
          border: Border.all(color: AppColors.electricBlue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: AppColors.electricBlue, size: 16),
            const SizedBox(width: 2),
            Text(
              'Adicionar',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.electricBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceMd,
          vertical: AppDimensions.spaceXs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.electricBlue.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
          border: Border.all(
            color: selected ? AppColors.electricBlue : AppColors.deepBlue,
          ),
        ),
        child: HudLabel(
          text: label,
          color: selected ? AppColors.electricBlue : AppColors.holographicBlue,
        ),
      ),
    );
  }
}

class _PackageIcon extends StatelessWidget {
  const _PackageIcon({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final StickerPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: AppDimensions.spaceXs),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.electricBlue : AppColors.deepBlue,
            width: selected
                ? AppDimensions.borderWidthActive
                : AppDimensions.borderWidthThin,
          ),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: ApiConfig.resolveUrl(package.iconUrl),
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: AppColors.nightBlue,
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome,
                size: 12,
                color: AppColors.holographicBlue,
              ),
            ),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.nightBlue,
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_awesome,
                size: 12,
                color: AppColors.holographicBlue,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma célula da grade. Responde ao toque com um "punch" de escala rápido
/// (feedback visual leve) sem atrasar o envio — [onTap] dispara na hora.
class _StickerTile extends StatefulWidget {
  const _StickerTile({
    required this.sticker,
    required this.onTap,
    required this.onLongPress,
  });

  final Sticker sticker;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<_StickerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _punch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void dispose() {
    _punch.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap();
    // Feedback independente do envio: encolhe e volta sozinho.
    _punch.forward(from: 0).then((_) {
      if (mounted) _punch.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.sticker.thumbUrl ?? widget.sticker.fileUrl;
    return GestureDetector(
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.86).animate(
          CurvedAnimation(parent: _punch, curve: Curves.easeOut),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: ApiConfig.resolveUrl(url),
                fit: BoxFit.contain,
                placeholder: (_, __) => Container(
                  color: AppColors.nightBlue,
                ),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.nightBlue,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF008CFF),
                    size: 18,
                  ),
                ),
              ),
            ),
            if (widget.sticker.favorited)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.absoluteBlack.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.error,
                    size: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              color: AppColors.holographicBlue,
              size: 36,
            ),
            const SizedBox(height: AppDimensions.spaceMd),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(color: AppColors.techWhite),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spaceSm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}