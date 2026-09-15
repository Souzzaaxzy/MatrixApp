import 'package:flutter/material.dart';

/// Host animado do painel de figurinhas.
///
/// Faz a abertura/fechamento do painel com uma transição CURTA (fade +
/// leve deslize) e um [AnimatedSize] que acompanha a altura, para o composer
/// subir/descer junto sem saltos de layout. É deliberadamente leve:
///
///  * uma única animação de tamanho/opacidade, sem blur, partículas ou
///    efeitos contínuos;
///  * o painel só é MONTADO quando visível — nenhum trabalho de layout
///    enquanto está fechado;
///  * [AnimatedSize] recorta o conteúdo durante a transição, então nada
///    "vaza" por cima do composer nem da barra de navegação.
///
/// Integra-se aos insets existentes: o painel fica dentro do mesmo [Column]
/// do composer, com seu próprio [SafeArea] inferior, então a barra de
/// navegação (gestos ou 3 botões) e o teclado continuam corretos.
class AnimatedStickerPanel extends StatelessWidget {
  const AnimatedStickerPanel({
    super.key,
    required this.visible,
    required this.child,
  });

  /// Se o painel deve estar aberto.
  final bool visible;

  /// O painel (normalmente [StickerPicker]) — montado só quando [visible].
  final Widget child;

  static const Duration duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.hardEdge,
      child: visible
          ? _PanelTransition(child: child)
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Fade + deslize de entrada/saída do conteúdo do painel (uma vez por
/// alternância, sem repetição).
class _PanelTransition extends StatefulWidget {
  const _PanelTransition({required this.child});

  final Widget child;

  @override
  State<_PanelTransition> createState() => _PanelTransitionState();
}

class _PanelTransitionState extends State<_PanelTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AnimatedStickerPanel.duration,
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Entrada suave de uma figurinha na conversa (enviada ou recebida).
///
/// Animação ÚNICA e leve — um fade com uma escala mínima (sem zoom exagerado,
/// sem bounce, sem rotação). Não atrasa o envio: roda em paralelo, e um item
/// já visto da lista (reciclado pelo ListView) não reanima.
class StickerEntrance extends StatefulWidget {
  const StickerEntrance({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;

  /// Desligado em contextos onde a animação não faz sentido (ex.: testes ou
  /// mensagens antigas carregadas de uma vez).
  final bool animate;

  @override
  State<StickerEntrance> createState() => _StickerEntranceState();
}

class _StickerEntranceState extends State<StickerEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.animate ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: widget.child,
      ),
    );
  }
}