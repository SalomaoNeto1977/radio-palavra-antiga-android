import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config/radio_config.dart';

/// Mantém o mapa público de playlists atualizado sem colocar credenciais na app.
class OfficialPlaylistCatalogService {
  OfficialPlaylistCatalogService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  static const String _cacheKey = 'rpa.official_playlists.catalog.v1';
  static const int _maximumResponseBytes = 2 * 1024 * 1024;
  static const Map<String, Object> emptyCatalog = <String, Object>{
    'schema_version': 1,
    'playlists': <Object>[],
    'statistics': <String, int>{
      'public_tracks': 0,
      'mapped_tracks': 0,
      'unassigned_tracks': 0,
      'official_playlists': 0,
    },
  };

  final http.Client _client;
  final bool _ownsClient;

  Future<Map<String, Object?>> loadBest(String bundledSource) async {
    final Map<String, Object?> bundled =
        parseCatalog(bundledSource) ?? Map<String, Object?>.from(emptyCatalog);
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String? cachedSource = preferences.getString(_cacheKey);
      final Map<String, Object?>? cached = parseCatalog(cachedSource);
      return cached == null ? bundled : preferNewest(bundled, cached);
    } on Object {
      return bundled;
    }
  }

  Future<Map<String, Object?>?> refresh() async {
    try {
      final Uri requestUri = RadioConfig.officialPlaylistsCatalog.replace(
        queryParameters: <String, String>{
          'v': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final http.Response response = await _client
          .get(
            requestUri,
            headers: const <String, String>{
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(RadioConfig.networkRequestTimeout);
      if (response.statusCode != 200 ||
          response.bodyBytes.isEmpty ||
          response.bodyBytes.length > _maximumResponseBytes) {
        return null;
      }
      final Map<String, Object?>? catalog = parseCatalog(
        utf8.decode(response.bodyBytes),
      );
      if (catalog == null) {
        return null;
      }
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final Map<String, Object?>? cached = parseCatalog(
        preferences.getString(_cacheKey),
      );
      final Map<String, Object?> newest = cached == null
          ? catalog
          : preferNewest(cached, catalog);
      if (identical(newest, catalog)) {
        await preferences.setString(_cacheKey, jsonEncode(catalog));
      }
      return newest;
    } on Object {
      return null;
    }
  }

  static Map<String, Object?>? parseCatalog(String? source) {
    if (source == null ||
        source.isEmpty ||
        source.length > _maximumResponseBytes) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> || decoded['schema_version'] != 1) {
        return null;
      }
      final Object? rawPlaylists = decoded['playlists'];
      if (rawPlaylists is! List || rawPlaylists.length > 500) {
        return null;
      }

      final List<Map<String, Object?>> playlists = <Map<String, Object?>>[];
      final Set<String> usedPlaylistIds = <String>{};
      int totalTrackReferences = 0;
      for (final Object? value in rawPlaylists) {
        if (value is! Map<String, dynamic>) {
          return null;
        }
        final String id = (value['id'] as Object?)?.toString().trim() ?? '';
        final String name = (value['name'] as Object?)?.toString().trim() ?? '';
        final String description =
            (value['description'] as Object?)?.toString().trim() ?? '';
        final Object? rawTrackIds = value['track_ids'];
        if (id.isEmpty ||
            id.length > 128 ||
            name.isEmpty ||
            name.length > 160 ||
            description.length > 1000 ||
            !usedPlaylistIds.add(id) ||
            rawTrackIds is! List ||
            rawTrackIds.length > 10000) {
          return null;
        }
        final List<String> trackIds = <String>[];
        final Set<String> usedTrackIds = <String>{};
        for (final Object? rawTrackId in rawTrackIds) {
          if (rawTrackId is! String) {
            return null;
          }
          final String trackId = rawTrackId.trim();
          if (trackId.isEmpty || trackId.length > 160) {
            return null;
          }
          if (usedTrackIds.add(trackId)) {
            trackIds.add(trackId);
          }
        }
        totalTrackReferences += trackIds.length;
        if (totalTrackReferences > 100000) {
          return null;
        }
        playlists.add(<String, Object?>{
          'id': id,
          'name': name,
          'description': description,
          'track_ids': trackIds,
          if (value['is_fallback'] == true) 'is_fallback': true,
          if (value['cover_url'] is String && RadioConfig.isAlbumCoverUri(Uri.tryParse(value['cover_url'] as String) ?? Uri()))
            'cover_url': value['cover_url'],
        });
      }

      final Map<String, int> statistics = <String, int>{};
      final Object? rawStatistics = decoded['statistics'];
      if (rawStatistics is Map<String, dynamic>) {
        for (final String key in const <String>[
          'public_tracks',
          'mapped_tracks',
          'unassigned_tracks',
          'official_playlists',
          'selected_on_demand_playlists',
          'empty_on_demand_playlists',
        ]) {
          final Object? value = rawStatistics[key];
          if (value is int && value >= 0) {
            statistics[key] = value;
          }
        }
      }

      return <String, Object?>{
        'schema_version': 1,
        if (decoded['generated_at'] is String)
          'generated_at': decoded['generated_at'],
        'playlists': playlists,
        'statistics': statistics,
      };
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> preferNewest(
    Map<String, Object?> current,
    Map<String, Object?> candidate,
  ) {
    final DateTime? currentDate = DateTime.tryParse(
      current['generated_at'] as String? ?? '',
    );
    final DateTime? candidateDate = DateTime.tryParse(
      candidate['generated_at'] as String? ?? '',
    );
    if (currentDate != null &&
        (candidateDate == null || candidateDate.isBefore(currentDate))) {
      return current;
    }
    return candidate;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
