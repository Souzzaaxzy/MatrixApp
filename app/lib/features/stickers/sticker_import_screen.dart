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

/// Pantalla de importación de figuritas recibidas por el compartir nativo de
/// Android (ACTION_SEND / ACTION_SEND_MULTIPLE).
///
/// Muestra las previsualizaciones validadas, permite nombrar el paquete y
/// exige confirmación antes de añadir a la colección. Los archivos inválidos
/// o incompatibles se aíslan y se rechazan con un mensaje amigable — nada se
/// importa sin pulsar "AÑADIR".
class StickerImportScreen extends StatefulWidget {
  const StickerImportScreen({super.key, required this.title});

  /// Título del paquete pre-rellenado (vacío = el usuario decide).
  final String title;

  @override
  State<StickerImportScreen> createState() => _StickerImportScreenState();
}

class _StickerImportScreenState extends State<StickerImportScreen> {
  late final Future<List<ValidatedStickerFile>?> _validation;

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

  Future<List<ValidatedStickerFile>?> _validateAll() async {
    final files = await ShareStickerService.instance.currentFiles();
    if (files == null || files.isEmpty) return null;
    final results = <ValidatedStickerFile>[];
    for (final f in files) {
      final v = await StickerImportValidator.validate(
        File(f.path),
        invalidReasons: _invalidReasons,
      );
      if (v != null) results.add(v);
    }
    return results;
  }

  Future<void> _import() async {
    final validated = await _validation;
    if (validated == null || validated.isEmpty || _importing) return;
    setState(() => _importing = true);

    try {
      final counts = await _doImport(validated);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      ShareStickerService.instance.clearCurrent();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            counts.created > 0
                ? '${counts.created} figurita(s) añadida(s) a la colección!'
                : 'Todo ya estaba en tu colección.',
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
        const SnackBar(content: Text('Error al importar las figuritas.')),
      );
    }
  }

  /// Sube los archivos validados por el sistema EXISTENTE de uploads y crea
  /// el paquete del usuario vía la API de stickers (misma persistencia).
  Future<({int created, int skipped})> _doImport(
    List<ValidatedStickerFile> files,
  ) async {
    final state = AppStateScope.of(context);
    final name = _nameCtrl.text.trim();
    return state.importSharedStickers(name: name, stickers: files);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: AppColors.bluishBlack,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.holographicBlue),
          onPressed: () {
            ShareStickerService.instance.clearCurrent();
            Navigator.of(context).maybePop();
          },
          tooltip: 'Cancelar',
        ),
        title: const HudLabel(text: 'IMPORTAR STICKERS'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<List<ValidatedStickerFile>?>(
          future: _validation,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
              child: HudLabel(text: 'VALIDANDO ARCHIVOS...', dot: true),
            );
            }
            final validated = snapshot.data ?? const <ValidatedStickerFile>[];
            if (validated.isEmpty) {
              return _NoValidStickers(invalidCount: _invalidReasons.length);
            }
            return _buildImportBody(validated);
          },
        ),
      ),
    );
  }

  Widget _buildImportBody(List<ValidatedStickerFile> validated) {
    final invalidCount = _invalidReasons.length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppDimensions.spaceLg),
            children: [
              Row(
                children: [
              HudLabel(
                    text: validated.length == 1
                        ? '1 FIGURITA ENCONTRADA'
                        : '${validated.length} FIGURITAS ENCONTRADAS',
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
              const SizedBox(height: AppDimensions.spaceLg),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: AppDimensions.spaceSm,
                  crossAxisSpacing: AppDimensions.spaceSm,
                  childAspectRatio: 1,
                ),
                itemCount: validated.length,
                itemBuilder: (context, index) {
                  final v = validated[index];
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
                    'Archivos que no son imágenes PNG, WebP o JPEG (o que '
                    'están corruptos/más de 5 MB):',
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
                child: Text('NOMBRE DEL PAQUETE', style: AppTextStyles.label),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              TextField(
                controller: _nameCtrl,
                enabled: !_importing,
                maxLength: 40,
                style: AppTextStyles.body,
                cursorColor: AppColors.electricBlue,
                decoration: InputDecoration(
                  hintText: 'Ej.: Mis stickers',
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
                label: 'AÑADIR',
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
}

class _NoValidStickers extends StatelessWidget {
  const _NoValidStickers({required this.invalidCount});

  final int invalidCount;

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
              'Ninguna figurita válida para importar',
              textAlign: TextAlign.center,
              style: AppTextStyles.h3.copyWith(color: AppColors.techWhite),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            Text(
              invalidCount > 0
                  ? 'Los archivos recibidos no son imágenes PNG, WebP o JPEG '
                      'válidas (o exceden 5 MB).'
                  : 'No se recibió ningún archivo de figura.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            MatrixButton(
              label: 'VOLVER',
              variant: MatrixButtonVariant.outline,
              onPressed: () {
                ShareStickerService.instance.clearCurrent();
                Navigator.of(context).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }
}