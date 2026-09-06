import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config/radio_config.dart';
import 'radio_state.dart';

class NowPlayingService {
  NowPlayingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<NowPlayingMetadata> fetch() async {
    Object? firstFailure;
    for (final Uri endpoint in <Uri>[
      RadioConfig.nowPlayingApi,
      RadioConfig.alternateNowPlayingApi,
    ]) {
      try {
        final http.Response response = await _client
            .get(
              endpoint,
              headers: const <String, String>{
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(RadioConfig.networkRequestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw http.ClientException(
            'Resposta HTTP ${response.statusCode}',
            endpoint,
          );
        }
        final Object? decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Resposta de metadados inválida');
        }
        return parse(decoded);
      } on Object catch (error) {
        firstFailure ??= error;
      }
    }
    throw firstFailure ?? const FormatException('Sem metadados disponíveis');
  }

  static NowPlayingMetadata parse(Map<String, dynamic> json) {
    final Map<String, dynamic> nowPlaying = _map(json['now_playing']);
    final Map<String, dynamic> song = _map(nowPlaying['song']);
    final Map<String, dynamic> live = _map(json['live']);
    final Map<String, dynamic> station = _map(json['station']);

    final String title =
        _clean(song['title']) ??
        _clean(nowPlaying['title']) ??
        _clean(station['name']) ??
        RadioConfig.defaultTitle;
    final bool isLive = live['is_live'] == true;
    final String artist =
        (isLive ? _clean(live['streamer_name']) : null) ??
        _clean(song['artist']) ??
        RadioConfig.defaultArtist;
    final String? album = _clean(song['album']);
    final Uri artwork =
        _safeHttpsUri(song['art']) ??
        _safeHttpsUri(nowPlaying['art']) ??
        RadioConfig.defaultArtwork;

    return NowPlayingMetadata(
      title: title,
      artist: artist,
      album: album,
      artwork: artwork,
      isLive: true,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? item) =>
            MapEntry<String, dynamic>(key.toString(), item),
      );
    }
    return const <String, dynamic>{};
  }

  static String? _clean(Object? value) {
    if (value is! String) {
      return null;
    }
    final String text = value.trim();
    if (text.isEmpty ||
        text.length > 300 ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'undefined' ||
        text.startsWith('{') ||
        text.startsWith('[')) {
      return null;
    }
    return text;
  }

  static Uri? _safeHttpsUri(Object? value) {
    final String? text = _clean(value);
    final Uri? uri = text == null ? null : Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
      return null;
    }
    return uri;
  }

  void close() => _client.close();
}
