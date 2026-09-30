import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config/radio_config.dart';
import 'album_title.dart';
import 'official_playlist_catalog_service.dart';
import 'radio_state.dart';
import 'user_music_library.dart';

class NativeMusicPlaylist {
  const NativeMusicPlaylist({
    required this.id,
    required this.name,
    required this.description,
    required this.trackIds,
  });

  final String id;
  final String name;
  final String description;
  final List<String> trackIds;
}

class NativeMusicCatalog {
  const NativeMusicCatalog({
    required this.tracks,
    required this.officialPlaylists,
    required this.userLibrary,
  });

  final List<OnDemandTrack> tracks;
  final List<NativeMusicPlaylist> officialPlaylists;
  final UserMusicLibrary userLibrary;

  OnDemandTrack? trackById(String id) {
    for (final OnDemandTrack track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }
}

abstract interface class NativeMusicCatalogPort {
  Future<NativeMusicCatalog> load();
  void close();
}

class NativeMusicCatalogService implements NativeMusicCatalogPort {
  NativeMusicCatalogService({
    required this.bundledOfficialPlaylists,
    required UserMusicLibraryStore userLibraryStore,
    http.Client? client,
    OfficialPlaylistCatalogService? officialPlaylistService,
  }) : _userLibraryStore = userLibraryStore,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _officialPlaylistService =
           officialPlaylistService ?? OfficialPlaylistCatalogService(),
       _ownsOfficialPlaylistService = officialPlaylistService == null;

  static const int _maximumResponseBytes = 12 * 1024 * 1024;
  static const Duration _cacheDuration = Duration(minutes: 10);

  final String bundledOfficialPlaylists;
  final UserMusicLibraryStore _userLibraryStore;
  final http.Client _client;
  final bool _ownsClient;
  final OfficialPlaylistCatalogService _officialPlaylistService;
  final bool _ownsOfficialPlaylistService;
  List<OnDemandTrack>? _cachedTracks;
  List<NativeMusicPlaylist>? _cachedOfficialPlaylists;
  DateTime? _cachedAt;
  Future<void>? _catalogLoad;

  @override
  Future<NativeMusicCatalog> load() async {
    final DateTime now = DateTime.now();
    if (_cachedAt == null ||
        now.difference(_cachedAt!) > _cacheDuration ||
        _cachedTracks == null ||
        _cachedOfficialPlaylists == null) {
      _catalogLoad ??= _loadPublicCatalog().whenComplete(() {
        _catalogLoad = null;
      });
      await _catalogLoad;
    }
    return NativeMusicCatalog(
      tracks: _cachedTracks ?? const <OnDemandTrack>[],
      officialPlaylists:
          _cachedOfficialPlaylists ?? const <NativeMusicPlaylist>[],
      userLibrary: await _userLibraryStore.read(),
    );
  }

  Future<void> _loadPublicCatalog() async {
    final Map<String, Object?> official =
        await _officialPlaylistService.loadBest(bundledOfficialPlaylists);
    final List<NativeMusicPlaylist> playlists = _parseOfficial(official);
    List<OnDemandTrack> tracks = _cachedTracks ?? const <OnDemandTrack>[];
    try {
      final http.Response response = await _client.get(
        RadioConfig.onDemandApi,
        headers: const <String, String>{
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(RadioConfig.networkRequestTimeout);
      if (response.statusCode == 200 &&
          response.bodyBytes.isNotEmpty &&
          response.bodyBytes.length <= _maximumResponseBytes) {
        tracks = _parseTracks(utf8.decode(response.bodyBytes));
      }
    } on Object {
      // Mantém o último catálogo válido. A emissão em directo continua sempre.
    }
    _cachedTracks = List<OnDemandTrack>.unmodifiable(tracks);
    _cachedOfficialPlaylists = List<NativeMusicPlaylist>.unmodifiable(playlists);
    _cachedAt = DateTime.now();
  }

  static List<NativeMusicPlaylist> _parseOfficial(
    Map<String, Object?> catalog,
  ) {
    final Object? rows = catalog['playlists'];
    if (rows is! List) return const <NativeMusicPlaylist>[];
    return rows.whereType<Map<String, Object?>>().map((row) {
      return NativeMusicPlaylist(
        id: row['id']! as String,
        name: publicAlbumTitle(row['name']! as String),
        description: row['description']! as String,
        trackIds: List<String>.unmodifiable(
          (row['track_ids']! as List).whereType<String>(),
        ),
      );
    }).toList(growable: false);
  }

  static List<OnDemandTrack> _parseTracks(String source) {
    try {
      final Object? decoded = jsonDecode(source);
      final List<Object?> rows = decoded is List
          ? decoded
          : decoded is Map<String, dynamic> && decoded['rows'] is List
          ? decoded['rows'] as List<Object?>
          : const <Object?>[];
      final List<OnDemandTrack> tracks = <OnDemandTrack>[];
      final Set<String> ids = <String>{};
      for (final Object? raw in rows.take(10000)) {
        if (raw is! Map<String, dynamic>) continue;
        final Object? rawMedia = raw['media'];
        final Map<String, dynamic> media = rawMedia is Map<String, dynamic>
            ? rawMedia
            : const <String, dynamic>{};
        final String id = (raw['track_id'] ?? media['id'] ?? '')
            .toString()
            .trim();
        final String download = (raw['download_url'] ?? '').toString().trim();
        final Uri? rawUri = Uri.tryParse(download);
        final Uri? url = rawUri == null
            ? null
            : (rawUri.hasAuthority
                  ? rawUri
                  : RadioConfig.onDemandApi.resolveUri(rawUri));
        if (id.isEmpty || url == null || !ids.add(id)) continue;

        Object? rawArt = media['art'];
        if (rawArt is Map<String, dynamic>) rawArt = rawArt['url'];
        final Uri? rawArtwork = Uri.tryParse((rawArt ?? '').toString());
        final Uri artwork = rawArtwork == null
            ? RadioConfig.defaultArtwork
            : (rawArtwork.hasAuthority
                  ? rawArtwork
                  : RadioConfig.onDemandApi.resolveUri(rawArtwork));
        final OnDemandTrack? track = OnDemandTrack.fromWebMap(
          <String, dynamic>{
            'id': id,
            'url': url.toString(),
            'title': (media['title'] ?? media['text'] ?? 'Sem título')
                .toString()
                .trim(),
            'artist': (media['artist'] ?? RadioConfig.stationName)
                .toString()
                .trim(),
            'album': (media['album'] ?? '').toString().trim(),
            'artwork': artwork.toString(),
          },
        );
        if (track != null) tracks.add(track);
      }
      return tracks;
    } on Object {
      return const <OnDemandTrack>[];
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
    if (_ownsOfficialPlaylistService) _officialPlaylistService.close();
  }
}
