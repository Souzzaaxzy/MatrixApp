import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/utils/sticker_import_validator.dart';
import '../../core/widgets/app_state_scope.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../data/api_config.dart';
import '../../data/share_sticker_service.dart';

/// Tela de importação de figurinhas recebidas pelo compartilhamento nativo
/// do Android (ACTION_SEND / ACTION_SEND_MULTIPLE / ACTION_VIEW).
///
/// Toda a interface está em português (pt-BR). Mostra as pré-visualizações
/// validadas, permite nomear o pacote e exige confirmação antes de adicionar
/// à coleção. Arquivos inválidos ou incompatíveis são isolados e recusados
/// com uma mensagem amigável — nada é importado sem tocar em "ADICIONAR".
///
/// Um pacote `.wastickers` (ZIP) chega já extraído pelo nativo com seu
/// título/autor/capa; imagens soltas funcionam igual, sem metadados.
class StickerImportScreen extends StatefulWidget {
  const StickerImportScreen({super.key, required this.title});

  /// Nome do pacote pré-preenchido (vazio = o usuário decide).
  final String title;

  @override
  State<StickerImportScreen> createState() => _StickerImportScreenState();
}

class _StickerImportScreenState extends State<StickerImportScreen> {
  late final Future<_ImportData?> _validation;

  final TextEditingController _nameCtrl = TextEditingController();
  final Map<String, String> _invalidReasons = {};
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.title;
    _validation = _validateAll();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<_ImportData?> _validateAll() async {
    final batch = await ShareStickerService.instance.currentBatch();
    if (batch == null) return null;
    if (batch.kind == SharedBatchKind.error) {
      return _ImportData(
        kind: SharedBatchKind.error,
        stickers: const [],
        error: batch.error,
      );
    }
    final results = <ValidatedStickerFile>[];
    for (final f in batch.stickers) {
      final v = await StickerImportValidator.validate(
        File(f.path),
        invalidReasons: _invalidReasons,
      );
      if (v != null) results.add(v);
    }
    return _ImportData(
      kind: batch.kind,
      stickers: results,
      coverPath: batch.coverPath,
      author: batch.author,
      rejectedByNative: batch.rejected,
    );
  }

  Future<void> _import() async {
    final validated = await _validation;
    if (validated == null ||
        validated.kind == SharedBatchKind.error ||
        validated.stickers.isEmpty ||
        _importing) {
      return;
    }
    setState(() => _importing = true);

    try {
      final counts = await _doImport(validated.stickers);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      _cleanupTemporaries();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            counts.created > 0
                ? '${counts.created} figurinha(s) adicionada(s) à sua coleção!'
                : 'Tudo já estava na sua coleção.',
          ),
        ),
      );
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao importar as figurinhas.')),
      );
    }
  }

  /// Sobe os arquivos validados pelo sistema EXISTENTE de uploads e cria
  /// o pacote do usuário pela API de figurinhas (mesma persistência).
  Future<({int created, int skipped})> _doImport(
    List<ValidatedStickerFile> files,
  ) async {
    final state = AppStateScope.of(context);
    final name = _nameCtrl.text.trim();
    return state.importSharedStickers(name: name, stickers: files);
  }

  /// Consome o lote e elimina los temporales del compartir (éxito o
  /// cancelación) — nunca se dejan copias del contenido externo.
  void _cleanupTemporaries() {
    ShareStickerService.instance.clearCurrent();
    unawaited(ShareStickerService.instance.cleanupTemporaries());
  }

  void _cancel() {
    _cleanupTemporaries();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: AppColors.bluishBlack,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.holographicBlue),
          onPressed: _cancel,
          tooltip: 'Cancelar',
        ),
        title: const HudLabel(text: 'IMPORTAR FIGURINHAS'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<_ImportData?>(
          future: _validation,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: HudLabel(text: 'VALIDANDO ARQUIVOS...', dot: true),
              );
            }
            final data = snapshot.data;
            if (data == null) {
              return _NoValidStickers(
                invalidCount: _invalidReasons.length,
                message: 'Nenhum arquivo de figurinha recebido.',
              );
            }
            if (data.kind == SharedBatchKind.error) {
              return _NoValidStickers(
                invalidCount: 0,
                message: data.error ??
                    'O conteúdo compartilhado não é compatível com o MATRIX.',
              );
            }
            if (data.stickers.isEmpty) {
              return _NoValidStickers(invalidCount: _invalidReasons.length);
            }
            return _buildImportBody(data);
          },
        ),
      ),
    );
  }

  Widget _buildImportBody(_ImportData data) {
    final invalidCount = _invalidReasons.length + data.rejectedByNative;
    final cover = _resolveCover(data);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppDimensions.spaceLg),
            children: [
              Row(
                children: [
                  HudLabel(
                    text: data.stickers.length == 1
                        ? '1 FIGURINHA ENCONTRADA'
                        : '${data.stickers.length} FIGURINHAS ENCONTRADAS',
                    color: AppColors.electricBlue,
                  ),
                  const Spacer(),
                  if (invalidCount > 0)
                    HudLabel(
                      text: '$invalidCount IGNORADA(S)',
                      color: AppColors.error,
                    ),
                ],
              ),
              if (data.kind == SharedBatchKind.pack && data.author.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spaceSm),
                HudLabel(text: 'POR ${data.author.toUpperCase()}'),
              ],
              const SizedBox(height: AppDimensions.spaceLg),
              if (cover != null) ...[
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                      child: ColoredBox(
                        color: AppColors.nightBlue,
                        child: SizedBox(
                          width: 72,
                          height: 72,
                          child: Image.file(
                            File(cover),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spaceMd),
                    Expanded(
                      child: Text(
                        'Capa do pacote',
                        style: AppTextStyles.bodyMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceLg),
              ],
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: AppDimensions.spaceSm,
                  crossAxisSpacing: AppDimensions.spaceSm,
                  childAspectRatio: 1,
                ),
                itemCount: data.stickers.length,
                itemBuilder: (context, index) {
                  final v = data.stickers[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    child: ColoredBox(
                      color: AppColors.nightBlue,
                      child: Image.file(
                        v.file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (invalidCount > 0) ...[
                const SizedBox(height: AppDimensions.spaceLg),
                Text(
                  'Arquivos que não são imagens PNG, WebP ou JPEG (ou que '
                  'estão corrompidos/maiores que 5 MB):',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                ..._invalidReasons.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${e.value}',
                      style: AppTextStyles.bodyMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bluishBlack,
            border: Border(
              top: BorderSide(
                color: AppColors.primaryBlue,
                width: AppDimensions.borderWidthThin,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.spaceLg,
            AppDimensions.spaceMd,
            AppDimensions.spaceLg,
            AppDimensions.spaceLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('NOME DO PACOTE', style: AppTextStyles.label),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              TextField(
                controller: _nameCtrl,
                enabled: !_importing,
                maxLength: 40,
                style: AppTextStyles.body,
                cursorColor: AppColors.electricBlue,
                decoration: InputDecoration(
                  hintText: 'Ex.: Minhas figurinhas',
                  hintStyle: AppTextStyles.bodyMuted,
                  counterText: '',
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
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: 'ADICIONAR',
                icon: Icons.add_rounded,
                expanded: true,
                isLoading: _importing,
                onPressed: _importing ? null : _import,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Capa do pacote se o nativo a extraiu e ela ainda existe.
  String? _resolveCover(_ImportData data) {
    final cover = data.coverPath;
    if (cover == null || cover.isEmpty) return null;
    return File(cover).existsSync() ? cover : null;
  }
}

/// Dados validados que alimentam a tela.
class _ImportData {
  const _ImportData({
    required this.kind,
    required this.stickers,
    this.coverPath,
    this.author = '',
    this.rejectedByNative = 0,
    this.error,
  });

  final SharedBatchKind kind;
  final List<ValidatedStickerFile> stickers;
  final String? coverPath;
  final String author;
  final int rejectedByNative;
  final String? error;
}

class _NoValidStickers extends StatelessWidget {
  const _NoValidStickers({
    required this.invalidCount,
    this.message,
  });

  final int invalidCount;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              color: AppColors.holographicBlue,
              size: 44,
            ),
            const SizedBox(height: AppDimensions.spaceMd),
            Text(
              'Nenhuma figurinha válida para importar',
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(color: AppColors.techWhite),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            Text(
              message ??
                  (invalidCount > 0
                      ? 'Os arquivos recebidos não são imagens PNG, WebP ou '
                          'JPEG válidas (ou passam de 5 MB).'
                      : 'Nenhum arquivo de figurinha recebido.'),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            MatrixButton(
              label: 'VOLTAR',
              variant: MatrixButtonVariant.outline,
              onPressed: () {
                ShareStickerService.instance.clearCurrent();
                unawaited(ShareStickerService.instance.cleanupTemporaries());
                Navigator.of(context).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
