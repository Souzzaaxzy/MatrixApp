import '../../models/profile_music.dart';
import '../api_client.dart';
import '../api_config.dart';
import '../services.dart';

/// Music repository — profile song search, selection and removal.
///
/// The server does all external work (it queries YouTube through yt-dlp and
/// downloads the excerpt), so the app only sends a query and then a choice.
/// No credential or third-party key ever reaches the device.
class MusicRepository {
  MusicRepository(this._api);

  final ApiClient _api;

  /// Searches the music catalog. Returns at most 3 cleaned results (song +
  /// artist), never raw video titles.
  Future<List<MusicSearchResult>> search(String query) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/api/music/profile/search',
      queryParameters: {'q': query},
    );
    final list = (json['results'] as List?) ?? const [];
    return list
        .map(MusicSearchResult.fromJson)
        .whereType<MusicSearchResult>()
        .toList();
  }

  /// Pins [result] to the profile, storing an excerpt of [durationMs]
  /// starting at [startMs]. The server re-validates the length (max 1 minute)
  /// and downloads the audio, so this call may take a few seconds.
  Future<ProfileMusic> set({
    required MusicSearchResult result,
    required int startMs,
    required int durationMs,
  }) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/api/music/profile',
      data: {
        'sourceId': result.sourceId,
        'title': result.title,
        'artist': result.artist,
        if (result.coverUrl != null) 'coverUrl': result.coverUrl,
        'startMs': startMs,
        'durationMs': durationMs,
      },
    );
    final music = ProfileMusic.fromJson(json['music']);
    if (music == null) {
      throw const ApiException(
        statusCode: 500,
        message: 'Resposta inválida do servidor.',
      );
    }
    return music;
  }

  /// Removes the pinned song from the profile.
  Future<void> clear() async {
    await _api.delete('/api/music/profile');
  }

  /// URL do áudio de prévia de uma faixa (a faixa inteira, servida pelo
  /// /static). O servidor baixa e mantém em cache; o app recorta a janela
  /// com `setClip`. É `static` porque o player de prévia precisa dela sem
  /// passar por uma instância de repositório.
  static Future<String> previewUrl(String sourceId) async {
    final api = Services.instance.apiClient;
    final json = await api.get<Map<String, dynamic>>(
      '/api/music/profile/preview',
      queryParameters: {'sourceId': sourceId},
    );
    final url = json['url'];
    if (url is! String || url.isEmpty) {
      throw const ApiException(
        statusCode: 500,
        message: 'Prévia indisponível.',
      );
    }
    return url;
  }
}
