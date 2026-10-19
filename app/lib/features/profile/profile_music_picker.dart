import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
import '../../core/widgets/range_selector.dart';
import '../../data/api_config.dart';
import '../../models/profile_music.dart';
import 'music_search_service.dart';

/// Tela de escolher a música do perfil.
///
/// Fluxo: pesquisar → até 3 opções (música + autor, sem títulos de vídeo) →
/// escolher o TRECHO (máx. 1:00) → confirmar. O download acontece no servidor
/// só na confirmação, então explorar as opções é barato.
class ProfileMusicPicker extends StatefulWidget {
  const ProfileMusicPicker({super.key, required this.initialQuery});

  /// Optional pre-filled search (the user's nickname, so the first screen is
  /// never empty).
  final String initialQuery;

  @override
  State<ProfileMusicPicker> createState() => _ProfileMusicPickerState();
}

class _ProfileMusicPickerState extends State<ProfileMusicPicker> {
  late final TextEditingController _query;
  List<MusicSearchResult> _results = const [];
  MusicSearchResult? _selected;
  bool _searching = false;
  String? _error;

  /// Excerpt length in milliseconds (max 1 minute).
  int _durationMs = 30000;

  /// Where the excerpt starts in the source track.
  int _startMs = 0;

  /// Mínimo de trecho aceito (evita um trecho degenerado).
  static const int _minDurationMs = 5000;

  /// Teto de 1 minuto imposto pelo perfil.
  static const int _maxDurationMs = 60000;

  /// Duração total da faixa escolhida, para a régua. Quando o servidor não
  /// informa a duração, usamos um valor plausível para a régua continuar
  /// funcional (a escolha continua limitada pelo teto de 1 minuto).
  int get _totalMs {
    final total = _selected?.durationMs ?? 0;
    if (total > 0) return total;
    return _maxDurationMs;
  }

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) {
      setState(() => _error = 'Digite o nome de uma música.');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _selected = null;
      _startMs = 0;
    });
    try {
      final results = await searchProfileMusicIn(context, q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        if (results.isEmpty) {
          _error = 'Nenhuma música encontrada. Tente outro nome.';
        }
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e is ApiException ? e.message : 'Não foi possível buscar agora.';
      });
    }
  }

  void _confirmSelection() {
    final selected = _selected;
    if (selected == null) return;
    Navigator.of(context).pop(
      PendingProfileMusic(
        result: selected,
        startMs: _startMs,
        durationMs: _durationMs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.absoluteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.techWhite),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('ESCOLHER MÚSICA',
            style: AppTextStyles.title.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppDimensions.spaceLg),
              MatrixTextField(
                controller: _query,
                hint: 'Nome da música ou artista',
                textInputAction: TextInputAction.search,
                onFieldSubmitted: (_) => _search(),
              ),
              const SizedBox(height: AppDimensions.spaceMd),
              MatrixButton(
                label: _searching ? 'BUSCANDO...' : 'BUSCAR',
                icon: Icons.search_rounded,
                expanded: true,
                onPressed: _searching ? null : _search,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppDimensions.spaceMd),
                Text(
                  _error!,
                  style: AppTextStyles.bodyMuted.copyWith(
                    color: AppColors.electricBlue,
                  ),
                ),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spaceXl),
                const HudLabel(text: 'RESULTADOS'),
                const SizedBox(height: AppDimensions.spaceSm),
                for (final result in _results)
                  _ResultTile(
                    result: result,
                    selected: _selected?.sourceId == result.sourceId,
                    onTap: () => setState(() {
                      _selected = result;
                      _startMs = 0;
                    }),
                  ),
              ],
              if (_selected != null) ...[
                const SizedBox(height: AppDimensions.spaceXl),
                const HudLabel(text: 'TRECHO'),
                const SizedBox(height: AppDimensions.spaceSm),
                Text(
                  'Arraste as pontas para escolher o trecho que vai tocar no '
                  'perfil (máximo 1 minuto).',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: AppDimensions.spaceMd),
                // Régua estilo Instagram: duas alças sobre a faixa inteira,
                // com precisão de SEGUNDO.
                RangeSelector(
                  totalMs: _totalMs,
                  startMs: _startMs,
                  endMs: _startMs + _durationMs,
                  minMs: _minDurationMs,
                  maxMs: _maxDurationMs,
                  color: AppColors.electricBlue,
                  onChanged: (start, end) => setState(() {
                    _startMs = start;
                    _durationMs = end - start;
                  }),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                // Os dois instantes, em destaque: é o que o usuário ajusta.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _TimeChip(
                      label: 'INÍCIO',
                      value: ProfileMusic.formatMs(_startMs),
                    ),
                    _TimeChip(
                      label: 'FIM',
                      value: ProfileMusic.formatMs(_startMs + _durationMs),
                    ),
                    _TimeChip(
                      label: 'DURAÇÃO',
                      value: ProfileMusic.formatMs(_durationMs),
                      highlight: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceXl),
                MatrixButton(
                  label: 'CONFIRMAR',
                  icon: Icons.check_rounded,
                  expanded: true,
                  onPressed: _confirmSelection,
                ),
              ],
              const SizedBox(height: AppDimensions.spaceXl),
            ],
          ),
        ),
      ),
    );
  }
}

/// One search result: title + artist, with the source duration for context.
class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    required this.selected,
    required this.onTap,
  });

  final MusicSearchResult result;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spaceSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.spaceMd),
          decoration: BoxDecoration(
            color: AppColors.nightBlue,
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            border: Border.all(
              color: selected
                  ? AppColors.electricBlue
                  : AppColors.electricBlue.withValues(alpha: 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(fontSize: 14),
                    ),
                    if (result.artist.trim().isNotEmpty)
                      Text(
                        result.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.hud.copyWith(
                          fontSize: 11,
                          color: AppColors.holographicBlue,
                        ),
                      ),
                  ],
                ),
              ),
              if (result.durationMs > 0)
                Text(
                  result.durationLabel,
                  style: AppTextStyles.hud.copyWith(fontSize: 11),
                ),
              if (selected) ...[
                const SizedBox(width: AppDimensions.spaceSm),
                Icon(Icons.check_circle_rounded,
                    size: 18, color: AppColors.electricBlue),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Um dos instantes do trecho (INÍCIO/FIM/DURAÇÃO), em destaque.
///
/// O Instagram mostra os tempos como texto sobre a régua; aqui eles ficam em
/// chips logo abaixo, para o valor exato ser lido sem esforço — é o que o
/// usuário está ajustando segundo a segundo.
class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.hud.copyWith(
            fontSize: 9,
            color: AppColors.holographicBlue,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTextStyles.hud.copyWith(
            fontSize: highlight ? 14 : 13,
            color: highlight ? AppColors.electricBlue : AppColors.techWhite,
          ),
        ),
      ],
    );
  }
}
