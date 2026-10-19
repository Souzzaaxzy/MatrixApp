import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/widgets/hud_label.dart';
import '../../core/widgets/matrix_button.dart';
import '../../core/widgets/matrix_text_field.dart';
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

  /// Clamp so the excerpt never runs past the end of the source track.
  int get _maxStartMs {
    final total = _selected?.durationMs ?? 0;
    if (total <= 0) return 0;
    final maxStart = total - _durationMs;
    return maxStart < 0 ? 0 : maxStart;
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
                  'Escolha a duração e o início do trecho que vai tocar no '
                  'perfil (máximo 1 minuto).',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: AppDimensions.spaceMd),
                _DurationStepper(
                  durationMs: _durationMs,
                  onChanged: (value) => setState(() {
                    _durationMs = value;
                    // A shorter excerpt can free up room, but the start never
                    // moves on its own — only clamp when it would overflow.
                    if (_startMs > _maxStartMs) _startMs = _maxStartMs;
                  }),
                ),
                const SizedBox(height: AppDimensions.spaceMd),
                _StartStepper(
                  startMs: _startMs,
                  maxStartMs: _maxStartMs,
                  onChanged: (value) => setState(() => _startMs = value),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                Text(
                  'No perfil: ${ProfileMusic.formatMs(_startMs)} – '
                  '${ProfileMusic.formatMs(_startMs + _durationMs)} '
                  '(${ProfileMusic.formatMs(_durationMs)})',
                  style: AppTextStyles.hud.copyWith(
                    fontSize: 11,
                    color: AppColors.holographicBlue,
                  ),
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

/// Duration chooser, in 5-second steps, hard-capped at 1 minute.
class _DurationStepper extends StatelessWidget {
  const _DurationStepper({required this.durationMs, required this.onChanged});

  final int durationMs;
  final ValueChanged<int> onChanged;

  static const int _min = 5000;
  static const int _max = 60000;
  static const int _step = 5000;

  @override
  Widget build(BuildContext context) {
    return _StepperRow(
      label: 'Duração',
      value: ProfileMusic.formatMs(durationMs),
      onMinus: durationMs > _min ? () => onChanged(durationMs - _step) : null,
      onPlus: durationMs < _max ? () => onChanged(durationMs + _step) : null,
    );
  }
}

/// Start-offset chooser, clamped so the excerpt never overruns the track.
class _StartStepper extends StatelessWidget {
  const _StartStepper({
    required this.startMs,
    required this.maxStartMs,
    required this.onChanged,
  });

  final int startMs;
  final int maxStartMs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepperRow(
      label: 'Início',
      value: ProfileMusic.formatMs(startMs),
      onMinus: startMs > 0 ? () => onChanged(startMs - 5000) : null,
      onPlus: startMs < maxStartMs
          ? () => onChanged((startMs + 5000).clamp(0, maxStartMs))
          : null,
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTextStyles.body.copyWith(fontSize: 13)),
        ),
        IconButton(
          onPressed: onMinus,
          icon: const Icon(Icons.remove_rounded),
          color: AppColors.electricBlue,
        ),
        SizedBox(
          width: 56,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: AppTextStyles.hud.copyWith(fontSize: 13),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_rounded),
          color: AppColors.electricBlue,
        ),
      ],
    );
  }
}
