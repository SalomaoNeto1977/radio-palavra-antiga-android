import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vehicle_connection_monitor/vehicle_connection_monitor.dart';

import 'config/radio_config.dart';
import 'connectivity_service.dart';
import 'error_mapper.dart';
import 'music_access.dart';
import 'native_music_catalog_service.dart';
import 'now_playing_service.dart';
import 'playback_selection_store.dart';
import 'radio_player_controller.dart';
import 'radio_state.dart';
import 'user_music_library.dart';

abstract final class ReconnectionPolicy {
  static Duration delayForFailure(int failureCount) {
    final int index = (failureCount - 1).clamp(
      0,
      RadioConfig.reconnectDelays.length - 1,
    );
    return RadioConfig.reconnectDelays[index];
  }

  static RadioStreamKind streamForFailure(int failureCount) {
    if (failureCount < RadioConfig.mp3FailuresBeforeHls) {
      return RadioStreamKind.mp3;
    }
    // Depois do limiar, alterna as fontes. Assim, um HLS indisponível nunca
    // impede que o MP3 seja recuperado quando regressar.
    return (failureCount - RadioConfig.mp3FailuresBeforeHls).isEven
        ? RadioStreamKind.hls
        : RadioStreamKind.mp3;
  }
}

/// Decisões puras usadas pela recuperação do leitor e pelos testes.
abstract final class PlaybackRecoveryPolicy {
  static bool shouldResumeAfterTemporaryInterruption({
    required bool wasActiveBeforeInterruption,
    required bool userWantsPlayback,
  }) {
    return wasActiveBeforeInterruption && userWantsPlayback;
  }

  static bool shouldRecoverUnexpectedStop({
    required bool userWantsPlayback,
    required bool interruptionActive,
    required bool connectionInProgress,
    required bool stopping,
  }) {
    return userWantsPlayback &&
        !interruptionActive &&
        !connectionInProgress &&
        !stopping;
  }
}

enum VehiclePlaybackAction { none, pause, resume }

class VehiclePlaybackDecision {
  const VehiclePlaybackDecision({
    required this.action,
    required this.resumePending,
    required this.resumeRoutes,
  });

  final VehiclePlaybackAction action;
  final bool resumePending;
  final Set<String> resumeRoutes;
}

/// Conserva o último estado apenas entre a saída e o regresso ao mesmo carro.
abstract final class VehiclePlaybackPolicy {
  static const String anyAudioRoute = 'audio-route:any';

  static VehiclePlaybackDecision evaluate({
    required VehicleConnectionState? previous,
    required VehicleConnectionState current,
    required bool playbackActive,
    required bool resumePending,
    required Set<String> resumeRoutes,
    required bool automaticResumeEnabled,
  }) {
    final Set<String> previousRoutes = previous?.routes ?? const <String>{};
    final Set<String> removedRoutes = previousRoutes.difference(
      current.routes,
    );
    final Set<String> addedRoutes = current.routes.difference(previousRoutes);

    // Uma projecção USB pode desaparecer enquanto o Bluetooth do mesmo carro
    // permanece ligado. A decisão acompanha a rota removida, não apenas o
    // booleano global "há algum dispositivo externo".
    if (removedRoutes.isNotEmpty && (playbackActive || resumePending)) {
      return VehiclePlaybackDecision(
        action: playbackActive
            ? VehiclePlaybackAction.pause
            : VehiclePlaybackAction.none,
        resumePending: true,
        resumeRoutes: Set<String>.unmodifiable(removedRoutes),
      );
    }

    final Set<String> newlyAvailableRoutes = previous == null
        ? current.routes
        : addedRoutes;
    if (current.connected &&
        resumePending &&
        newlyAvailableRoutes.isNotEmpty) {
      final bool sameRoute =
          resumeRoutes.contains(anyAudioRoute) ||
          newlyAvailableRoutes.any(resumeRoutes.contains);
      if (automaticResumeEnabled && sameRoute) {
        return const VehiclePlaybackDecision(
          action: VehiclePlaybackAction.resume,
          resumePending: false,
          resumeRoutes: <String>{},
        );
      }
      if (!automaticResumeEnabled) {
        return const VehiclePlaybackDecision(
          action: VehiclePlaybackAction.none,
          resumePending: false,
          resumeRoutes: <String>{},
        );
      }
    }

    return VehiclePlaybackDecision(
      action: VehiclePlaybackAction.none,
      resumePending: resumePending,
      resumeRoutes: resumeRoutes,
    );
  }
}

abstract interface class VehicleConnectionPort {
  Stream<VehicleConnectionState> get states;
}

class PlatformVehicleConnectionPort implements VehicleConnectionPort {
  const PlatformVehicleConnectionPort();

  @override
  Stream<VehicleConnectionState> get states =>
      const VehicleConnectionMonitor().states;
}

abstract interface class VehicleResumeStore {
  Future<bool> readAutomaticResumeEnabled();
  Future<bool> readResumePending();
  Future<Set<String>> readResumeRoutes();
  Future<void> writeResumeState({
    required bool pending,
    required Set<String> routes,
  });
}

class SharedPreferencesVehicleResumeStore implements VehicleResumeStore {
  SharedPreferencesVehicleResumeStore({SharedPreferencesAsync? preferences})
    : _providedPreferences = preferences;

  static const String _automaticResumeKey =
      'automatic_vehicle_playback_resume';
  static const String _resumePendingKey = 'vehicle_playback_resume_pending';
  static const String _resumeRoutesKey = 'vehicle_playback_resume_routes';

  // O armazenamento de plataforma só é resolvido quando o estado automóvel
  // precisa realmente de ser lido ou escrito. Isto preserva um arranque leve
  // e permite testar o catálogo Android Auto sem carregar plugins nativos.
  final SharedPreferencesAsync? _providedPreferences;
  SharedPreferencesAsync? _lazyPreferences;

  SharedPreferencesAsync get _preferences =>
      _providedPreferences ?? (_lazyPreferences ??= SharedPreferencesAsync());

  @override
  Future<bool> readAutomaticResumeEnabled() async =>
      await _preferences.getBool(_automaticResumeKey) ?? true;

  @override
  Future<bool> readResumePending() async =>
      await _preferences.getBool(_resumePendingKey) ?? false;

  @override
  Future<Set<String>> readResumeRoutes() async =>
      (await _preferences.getStringList(_resumeRoutesKey) ?? const <String>[])
          .toSet();

  @override
  Future<void> writeResumeState({
    required bool pending,
    required Set<String> routes,
  }) async {
    await _preferences.setBool(_resumePendingKey, pending);
    await _preferences.setStringList(_resumeRoutesKey, routes.toList()..sort());
  }
}

enum RadioMediaButtonAction { play, pause, ignore }

/// Traduz apenas o botão multimédia principal dos auscultadores/automóvel.
/// Avançar e recuar não têm significado numa emissão em directo.
abstract final class RadioMediaButtonPolicy {
  static RadioMediaButtonAction actionFor({
    required MediaButton button,
    required bool playbackActive,
  }) {
    if (button != MediaButton.media) {
      return RadioMediaButtonAction.ignore;
    }
    return playbackActive
        ? RadioMediaButtonAction.pause
        : RadioMediaButtonAction.play;
  }
}

class ReconnectionGuard {
  int _generation = 0;

  int get current => _generation;
  int invalidate() => ++_generation;
  bool isCurrent(int token) => token == _generation;
}

abstract final class AndroidAutoMediaLibrary {
  static const String liveCategoryId = 'rpa://android-auto/live';
  static const String musicCategoryId = 'rpa://android-auto/music';
  static const String allTracksId = 'rpa://android-auto/music/all';
  static const String officialPlaylistsId =
      'rpa://android-auto/music/official';
  static const String favoritesId = 'rpa://android-auto/music/favorites';
  static const String personalPlaylistsId =
      'rpa://android-auto/music/personal';
  static String get stationId => RadioConfig.mp3Stream.toString();

  static MediaItem get liveCategory => MediaItem(
    id: liveCategoryId,
    title: 'Em directo',
    artUri: RadioConfig.androidAutoBrowseIcon,
    playable: false,
  );

  static MediaItem get liveStation => MediaItem(
    id: stationId,
    title: 'Ouvir em directo',
    artist: RadioConfig.stationName,
    album: 'Em directo',
    artUri: RadioConfig.androidAutoBrowseIcon,
    playable: true,
    isLive: true,
    extras: const <String, Object>{'isLive': true},
  );

  static MediaItem get musicCategory => _folder(
    musicCategoryId,
    'Palavra Antiga Music',
    subtitle: 'Músicas, favoritos e playlists',
  );

  static MediaItem get allTracks =>
      _folder(allTracksId, 'Todas as músicas');

  static MediaItem get officialPlaylists => _folder(
    officialPlaylistsId,
    'Playlists da rádio',
  );

  static MediaItem get favorites => _folder(favoritesId, 'Favoritos');

  static MediaItem get personalPlaylists => _folder(
    personalPlaylistsId,
    'As tuas playlists',
  );

  static MediaItem officialPlaylist(NativeMusicPlaylist playlist) => _folder(
    Uri(
      scheme: 'rpa',
      host: 'android-auto',
      path: '/music/official-playlist',
      queryParameters: <String, String>{'id': playlist.id},
    ).toString(),
    playlist.name,
    subtitle: playlist.description,
    artwork: playlist.artwork,
  );

  static MediaItem personalPlaylist(String name) => _folder(
    Uri(
      scheme: 'rpa',
      host: 'android-auto',
      path: '/music/personal-playlist',
      queryParameters: <String, String>{'name': name},
    ).toString(),
    name,
  );

  static String trackMediaId(String trackId, {required String contextId}) =>
      Uri(
        scheme: 'rpa',
        host: 'android-auto',
        path: '/track',
        queryParameters: <String, String>{
          'id': trackId,
          'context': contextId,
        },
      ).toString();

  static MediaItem track(
    OnDemandTrack track, {
    required String contextId,
  }) => MediaItem(
    id: trackMediaId(track.id, contextId: contextId),
    title: track.title,
    artist: track.artist,
    album: track.album ?? RadioConfig.stationName,
    artUri: track.artwork,
    playable: true,
    isLive: false,
    extras: <String, Object>{
      'isLive': false,
      'trackId': track.id,
      'contextId': contextId,
    },
  );

  static String? trackId(String mediaId) {
    final Uri? uri = Uri.tryParse(mediaId);
    return uri?.scheme == 'rpa' &&
            uri?.host == 'android-auto' &&
            uri?.path == '/track'
        ? uri?.queryParameters['id']
        : null;
  }

  static String? trackContext(String mediaId) {
    final Uri? uri = Uri.tryParse(mediaId);
    return trackId(mediaId) == null ? null : uri?.queryParameters['context'];
  }

  static String? officialPlaylistId(String mediaId) {
    final Uri? uri = Uri.tryParse(mediaId);
    return uri?.path == '/music/official-playlist'
        ? uri?.queryParameters['id']
        : null;
  }

  static String? personalPlaylistName(String mediaId) {
    final Uri? uri = Uri.tryParse(mediaId);
    return uri?.path == '/music/personal-playlist'
        ? uri?.queryParameters['name']
        : null;
  }

  static MediaItem _folder(String id, String title, {String? subtitle, Uri? artwork}) =>
      MediaItem(
        id: id,
        title: title,
        artist: subtitle,
        artUri: artwork ?? RadioConfig.androidAutoBrowseIcon,
        playable: false,
      );

  static bool isStation(String mediaId) => mediaId == stationId;
}

class _EmptyNativeMusicCatalog implements NativeMusicCatalogPort {
  const _EmptyNativeMusicCatalog();

  @override
  Future<NativeMusicCatalog> load() async => const NativeMusicCatalog(
    tracks: <OnDemandTrack>[],
    officialPlaylists: <NativeMusicPlaylist>[],
    userLibrary: UserMusicLibrary(),
  );

  @override
  void close() {}
}

class RadioAudioHandler extends BaseAudioHandler implements RadioPlaybackPort {
  RadioAudioHandler({
    ConnectivityPort? connectivity,
    NowPlayingService? nowPlayingService,
    just_audio.AudioPlayer Function()? playerFactory,
    VehicleConnectionPort? vehicleConnection,
    VehicleResumeStore? vehicleResumeStore,
    PlaybackSelectionStore? playbackSelectionStore,
    NativeMusicCatalogPort? nativeMusicCatalog,
    MusicAccessPort? musicAccess,
    this.bundledArtwork,
  }) : _connectivity = connectivity ?? ConnectivityService(),
       _nowPlayingService = nowPlayingService ?? NowPlayingService(),
       _playerFactory = playerFactory ?? _createPlayer,
       _vehicleConnection =
           vehicleConnection ?? const PlatformVehicleConnectionPort(),
       _vehicleResumeStore =
           vehicleResumeStore ?? SharedPreferencesVehicleResumeStore(),
       _playbackSelectionStore =
           playbackSelectionStore ?? SharedPreferencesPlaybackSelectionStore(),
       _nativeMusicCatalog =
           nativeMusicCatalog ?? const _EmptyNativeMusicCatalog(),
       _musicAccess = musicAccess ?? const AlwaysGrantedMusicAccess() {
    mediaItem.add(_mediaItemFor(_snapshot.metadata));
    playbackState.add(_systemPlaybackState(_snapshot));

    _connectivitySubscription = _connectivity.networkChanges.listen(
      _onConnectivityChanged,
    );
    _musicAccessSubscription = _musicAccess.musicAccessChanges.listen(
      _handleMusicAccessChanged,
    );
    _restoreOperation = _initializePersistenceAndVehicleConnection();
  }

  final ConnectivityPort _connectivity;
  final NowPlayingService _nowPlayingService;
  final just_audio.AudioPlayer Function() _playerFactory;
  final VehicleConnectionPort _vehicleConnection;
  final VehicleResumeStore _vehicleResumeStore;
  final PlaybackSelectionStore _playbackSelectionStore;
  final NativeMusicCatalogPort _nativeMusicCatalog;
  final MusicAccessPort _musicAccess;
  final Uri? bundledArtwork;

  /// É criado apenas no primeiro PLAY e depois reutilizado até ao encerramento.
  just_audio.AudioPlayer? _player;
  final StreamController<RadioPlaybackSnapshot> _snapshotController =
      StreamController<RadioPlaybackSnapshot>.broadcast(sync: true);
  final ReconnectionGuard _reconnectionGuard = ReconnectionGuard();

  RadioPlaybackSnapshot _snapshot = RadioPlaybackSnapshot.initial();
  AudioSession? _audioSession;
  StreamSubscription<just_audio.PlayerState>? _playerStateSubscription;
  StreamSubscription<just_audio.PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<bool>? _musicAccessSubscription;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;
  StreamSubscription<VehicleConnectionState>? _vehicleConnectionSubscription;
  Timer? _reconnectTimer;
  Timer? _metadataTimer;
  Timer? _stallTimer;
  Future<void>? _connectOperation;
  Future<void> _sourceResetOperation = Future<void>.value();
  Future<void> _vehicleEventOperation = Future<void>.value();
  Future<void> _selectionWriteOperation = Future<void>.value();
  late final Future<void> _restoreOperation;

  bool userWantsPlayback = false;
  bool _sessionConfigured = false;
  bool _stopping = false;
  bool _sourceSwitching = false;
  bool _disposed = false;
  bool _lastNetworkAvailable = true;
  bool _wasPlayingBeforeInterruption = false;
  bool _temporaryInterruptionActive = false;
  bool _ducked = false;
  bool _metadataRequestInProgress = false;
  bool _automaticVehicleResumeEnabled = true;
  bool _vehicleResumePending = false;
  Set<String> _vehicleResumeRoutes = <String>{};
  VehicleConnectionState? _lastVehicleConnection;
  int _consecutiveFailures = 0;
  int _attemptId = 0;
  int _failedAttemptId = -1;
  RadioStreamKind _streamKind = RadioStreamKind.mp3;
  PlaybackMode _playbackMode = PlaybackMode.live;
  List<OnDemandTrack> _onDemandQueue = const <OnDemandTrack>[];
  int _onDemandQueueIndex = -1;
  OnDemandTrack? _currentOnDemandTrack;
  Duration? _onDemandDuration;
  bool _onDemandSourceReady = false;
  bool _explicitPlaybackSelection = false;
  Duration _onDemandResumePosition = Duration.zero;
  DateTime? _lastSelectionPersistedAt;
  String _onDemandQueueContext = AndroidAutoMediaLibrary.allTracksId;

  @override
  RadioPlaybackSnapshot get snapshot => _snapshot;

  @override
  Stream<RadioPlaybackSnapshot> get snapshotStream =>
      _snapshotController.stream;

  static just_audio.AudioPlayer _createPlayer() {
    return just_audio.AudioPlayer(
      userAgent: RadioConfig.userAgent,
      handleInterruptions: false,
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: true,
      useProxyForRequestHeaders: false,
      maxSkipsOnError: 0,
    );
  }

  just_audio.AudioPlayer _ensurePlayer() {
    final just_audio.AudioPlayer? existing = _player;
    if (existing != null) {
      return existing;
    }
    if (_disposed) {
      throw StateError('O leitor já foi encerrado');
    }

    final just_audio.AudioPlayer created = _playerFactory();
    _player = created;
    _playerStateSubscription = created.playerStateStream.listen(_onPlayerState);
    _playbackEventSubscription = created.playbackEventStream.listen(
      _onPlaybackEvent,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_handlePlayerError(error));
      },
    );
    return created;
  }

  @visibleForTesting
  bool get hasCreatedPlayer => _player != null;

  @visibleForTesting
  just_audio.AudioPlayer ensurePlayerForTesting() => _ensurePlayer();

  @visibleForTesting
  MediaItem mediaItemForTesting(NowPlayingMetadata metadata) =>
      _mediaItemFor(metadata);

  @visibleForTesting
  Future<void> get restorationForTesting => _restoreOperation;

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      return <MediaItem>[
        AndroidAutoMediaLibrary.liveCategory,
        if (_musicAccess.hasMusicAccess)
          AndroidAutoMediaLibrary.musicCategory,
      ];
    }
    if (parentMediaId == AndroidAutoMediaLibrary.liveCategoryId ||
        parentMediaId == AudioService.recentRootId) {
      return <MediaItem>[AndroidAutoMediaLibrary.liveStation];
    }
    if (parentMediaId == AndroidAutoMediaLibrary.musicCategoryId) {
      if (!_musicAccess.hasMusicAccess) return const <MediaItem>[];
      final NativeMusicCatalog catalog = await _nativeMusicCatalog.load();
      return <MediaItem>[
        AndroidAutoMediaLibrary.allTracks,
        AndroidAutoMediaLibrary.officialPlaylists,
        if (catalog.userLibrary.favorites.isNotEmpty)
          AndroidAutoMediaLibrary.favorites,
        if (catalog.userLibrary.playlists.isNotEmpty)
          AndroidAutoMediaLibrary.personalPlaylists,
      ];
    }

    if (!_musicAccess.hasMusicAccess) return const <MediaItem>[];
    final NativeMusicCatalog catalog = await _nativeMusicCatalog.load();
    if (parentMediaId == AndroidAutoMediaLibrary.officialPlaylistsId) {
      return _paginate(
        catalog.officialPlaylists
            .map(AndroidAutoMediaLibrary.officialPlaylist)
            .toList(growable: false),
        options,
      );
    }
    if (parentMediaId == AndroidAutoMediaLibrary.personalPlaylistsId) {
      return _paginate(
        catalog.userLibrary.playlists.keys
            .map(AndroidAutoMediaLibrary.personalPlaylist)
            .toList(growable: false),
        options,
      );
    }
    if (_isTrackContext(parentMediaId)) {
      return _paginate(
        _tracksForContext(catalog, parentMediaId)
            .map(
              (OnDemandTrack track) => AndroidAutoMediaLibrary.track(
                track,
                contextId: parentMediaId,
              ),
            )
            .toList(growable: false),
        options,
      );
    }
    return const <MediaItem>[];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId == AndroidAutoMediaLibrary.liveCategoryId) {
      return AndroidAutoMediaLibrary.liveCategory;
    }
    if (mediaId == AndroidAutoMediaLibrary.musicCategoryId) {
      return _musicAccess.hasMusicAccess
          ? AndroidAutoMediaLibrary.musicCategory
          : null;
    }
    if (!_musicAccess.hasMusicAccess &&
        !AndroidAutoMediaLibrary.isStation(mediaId) &&
        mediaId != AndroidAutoMediaLibrary.liveCategoryId) {
      return null;
    }
    if (mediaId == AndroidAutoMediaLibrary.allTracksId) {
      return AndroidAutoMediaLibrary.allTracks;
    }
    if (mediaId == AndroidAutoMediaLibrary.officialPlaylistsId) {
      return AndroidAutoMediaLibrary.officialPlaylists;
    }
    if (mediaId == AndroidAutoMediaLibrary.favoritesId) {
      return AndroidAutoMediaLibrary.favorites;
    }
    if (mediaId == AndroidAutoMediaLibrary.personalPlaylistsId) {
      return AndroidAutoMediaLibrary.personalPlaylists;
    }
    if (AndroidAutoMediaLibrary.isStation(mediaId)) {
      return AndroidAutoMediaLibrary.liveStation;
    }
    final NativeMusicCatalog catalog = await _nativeMusicCatalog.load();
    final String? officialId = AndroidAutoMediaLibrary.officialPlaylistId(
      mediaId,
    );
    if (officialId != null) {
      for (final NativeMusicPlaylist playlist in catalog.officialPlaylists) {
        if (playlist.id == officialId) {
          return AndroidAutoMediaLibrary.officialPlaylist(playlist);
        }
      }
    }
    final String? personalName = AndroidAutoMediaLibrary.personalPlaylistName(
      mediaId,
    );
    if (personalName != null &&
        catalog.userLibrary.playlists.containsKey(personalName)) {
      return AndroidAutoMediaLibrary.personalPlaylist(personalName);
    }
    final String? trackId = AndroidAutoMediaLibrary.trackId(mediaId);
    final String? contextId = AndroidAutoMediaLibrary.trackContext(mediaId);
    final OnDemandTrack? track = trackId == null
        ? null
        : catalog.trackById(trackId);
    if (track != null && contextId != null) {
      return AndroidAutoMediaLibrary.track(track, contextId: contextId);
    }
    return null;
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final String phrase = query.trim().toLowerCase();
    final List<MediaItem> results = <MediaItem>[];
    if (phrase.isEmpty ||
        'rádio palavra antiga em directo'.contains(phrase) ||
        phrase.contains('rádio') ||
        phrase.contains('direto') ||
        phrase.contains('directo')) {
      results.add(AndroidAutoMediaLibrary.liveStation);
    }
    if (phrase.isNotEmpty && _musicAccess.hasMusicAccess) {
      final NativeMusicCatalog catalog = await _nativeMusicCatalog.load();
      for (final OnDemandTrack track in catalog.tracks) {
        final String searchable =
            '${track.title} ${track.artist} ${track.album ?? ''}'.toLowerCase();
        if (searchable.contains(phrase)) {
          results.add(
            AndroidAutoMediaLibrary.track(
              track,
              contextId: AndroidAutoMediaLibrary.allTracksId,
            ),
          );
        }
        if (results.length >= 50) break;
      }
    }
    return results.isEmpty
        ? <MediaItem>[AndroidAutoMediaLibrary.liveStation]
        : results;
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    if (AndroidAutoMediaLibrary.isStation(mediaId)) {
      await playLive();
      return;
    }
    if (!_musicAccess.hasMusicAccess) return;
    final String? trackId = AndroidAutoMediaLibrary.trackId(mediaId);
    final String? contextId = AndroidAutoMediaLibrary.trackContext(mediaId);
    if (trackId == null || contextId == null) return;
    final NativeMusicCatalog catalog = await _nativeMusicCatalog.load();
    final List<OnDemandTrack> contextQueue = _tracksForContext(
      catalog,
      contextId,
    );
    final int index = contextQueue.indexWhere(
      (OnDemandTrack track) => track.id == trackId,
    );
    if (index >= 0) {
      await playOnDemand(
        contextQueue[index],
        queue: contextQueue,
        queueIndex: index,
        contextId: contextId,
      );
    }
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    await playFromMediaId(mediaItem.id);
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final List<MediaItem> results = await search(query, extras);
    if (results.isNotEmpty) await playFromMediaId(results.first.id);
  }

  static List<MediaItem> _paginate(
    List<MediaItem> items,
    Map<String, dynamic>? options,
  ) {
    final int page =
        (options?['android.media.browse.extra.PAGE'] as num?)?.toInt() ?? 0;
    final int requestedSize =
        (options?['android.media.browse.extra.PAGE_SIZE'] as num?)?.toInt() ??
        100;
    final int size = requestedSize.clamp(1, 200).toInt();
    final int start = page < 0 ? 0 : page * size;
    if (start >= items.length) return const <MediaItem>[];
    return items.sublist(start, (start + size).clamp(0, items.length).toInt());
  }

  static bool _isTrackContext(String mediaId) =>
      mediaId == AndroidAutoMediaLibrary.allTracksId ||
      mediaId == AndroidAutoMediaLibrary.favoritesId ||
      AndroidAutoMediaLibrary.officialPlaylistId(mediaId) != null ||
      AndroidAutoMediaLibrary.personalPlaylistName(mediaId) != null;

  static List<OnDemandTrack> _tracksForContext(
    NativeMusicCatalog catalog,
    String contextId,
  ) {
    if (contextId == AndroidAutoMediaLibrary.allTracksId) {
      return catalog.tracks;
    }
    Iterable<String> ids = const <String>[];
    if (contextId == AndroidAutoMediaLibrary.favoritesId) {
      ids = catalog.userLibrary.favorites;
    } else {
      final String? officialId = AndroidAutoMediaLibrary.officialPlaylistId(
        contextId,
      );
      final String? personalName =
          AndroidAutoMediaLibrary.personalPlaylistName(contextId);
      if (officialId != null) {
        for (final NativeMusicPlaylist playlist in catalog.officialPlaylists) {
          if (playlist.id == officialId) {
            ids = playlist.trackIds;
            break;
          }
        }
      } else if (personalName != null) {
        ids = catalog.userLibrary.playlists[personalName] ?? const <String>[];
      }
    }
    final Map<String, OnDemandTrack> byId = <String, OnDemandTrack>{
      for (final OnDemandTrack track in catalog.tracks) track.id: track,
    };
    return ids.map((String id) => byId[id]).whereType<OnDemandTrack>().toList(
      growable: false,
    );
  }

  @override
  Future<void> play() async {
    await _restoreOperation;
    if (_playbackMode == PlaybackMode.onDemand &&
        _currentOnDemandTrack != null) {
      if (!_musicAccess.hasMusicAccess) {
        await playLive();
        return;
      }
      await _resumeOnDemand();
      return;
    }
    await playLive();
  }

  @override
  Future<void> playLive() async {
    _explicitPlaybackSelection = true;
    if (_disposed ||
        (_playbackMode == PlaybackMode.live &&
            (_snapshot.state == RadioPlaybackState.playing ||
                _snapshot.state == RadioPlaybackState.connecting ||
                _snapshot.state == RadioPlaybackState.buffering ||
                _snapshot.state == RadioPlaybackState.reconnecting))) {
      return;
    }

    _playbackMode = PlaybackMode.live;
    _currentOnDemandTrack = null;
    _onDemandQueue = const <OnDemandTrack>[];
    _onDemandQueueIndex = -1;
    _onDemandSourceReady = false;
    _onDemandDuration = null;
    _onDemandResumePosition = Duration.zero;
    _onDemandQueueContext = AndroidAutoMediaLibrary.allTracksId;
    queue.add(const <MediaItem>[]);
    _persistPlaybackSelection(force: true);
    _rememberVehicleResume(pending: false, routes: const <String>{});
    userWantsPlayback = true;
    _stopping = false;
    _cancelReconnect();
    _cancelMetadataUpdates();
    final int token = _reconnectionGuard.invalidate();

    if (_temporaryInterruptionActive) {
      _wasPlayingBeforeInterruption = true;
      _publish(
        state: RadioPlaybackState.paused,
        userWants: true,
        mode: PlaybackMode.live,
        error: null,
      );
      return;
    }

    _publish(
      state: RadioPlaybackState.connecting,
      userWants: true,
      mode: PlaybackMode.live,
      metadata: NowPlayingMetadata.fallback(),
      position: Duration.zero,
      duration: null,
      queueIndex: -1,
      queueLength: 0,
      error: null,
    );

    try {
      final AudioSession session = await _ensureAudioSession();
      if (!_isPlaybackRequestCurrent(token)) {
        return;
      }
      final bool focusGranted = await session.setActive(true);
      if (!focusGranted) {
        throw StateError('Audio focus not granted');
      }
      if (!_isPlaybackRequestCurrent(token)) {
        await session.setActive(false);
        return;
      }

      _consecutiveFailures = 0;
      _streamKind = RadioStreamKind.mp3;
      _sourceSwitching = true;
      await _queueSourceReset();
      _sourceSwitching = false;
      await _connectToStream(token);
    } on Object catch (error) {
      _sourceSwitching = false;
      if (_isPlaybackRequestCurrent(token)) {
        if (_isAudioFocusFailure(error)) {
          await _failIrrecoverably(error);
        } else {
          await _handleFailure(error, attemptId: _attemptId);
        }
      }
    }
  }

  @override
  Future<void> playOnDemand(
    OnDemandTrack track, {
    List<OnDemandTrack> queue = const <OnDemandTrack>[],
    int queueIndex = -1,
    String? contextId,
  }) async {
    if (_disposed || !_musicAccess.hasMusicAccess) return;
    _explicitPlaybackSelection = true;

    final List<OnDemandTrack> mutableQueue = queue.isEmpty
        ? <OnDemandTrack>[track]
        : List<OnDemandTrack>.of(queue);
    int safeIndex = queueIndex;
    if (safeIndex < 0 ||
        safeIndex >= mutableQueue.length ||
        mutableQueue[safeIndex].id != track.id) {
      safeIndex = mutableQueue.indexWhere(
        (OnDemandTrack item) => item.id == track.id,
      );
    }
    if (safeIndex < 0) {
      mutableQueue.insert(0, track);
      safeIndex = 0;
    }
    final List<OnDemandTrack> safeQueue =
        List<OnDemandTrack>.unmodifiable(mutableQueue);

    _playbackMode = PlaybackMode.onDemand;
    _onDemandQueue = safeQueue;
    _onDemandQueueIndex = safeIndex;
    _currentOnDemandTrack = track;
    _onDemandDuration = null;
    _onDemandSourceReady = false;
    _onDemandResumePosition = Duration.zero;
    _onDemandQueueContext = contextId ?? AndroidAutoMediaLibrary.allTracksId;
    _publishSystemQueue();
    _persistPlaybackSelection(force: true);
    _rememberVehicleResume(pending: false, routes: const <String>{});
    userWantsPlayback = true;
    _stopping = false;
    _reconnectionGuard.invalidate();
    _cancelReconnect();
    _cancelMetadataUpdates();
    _cancelStallWatchdog();

    if (_temporaryInterruptionActive) {
      _wasPlayingBeforeInterruption = true;
      _publishOnDemand(
        state: RadioPlaybackState.paused,
        userWants: true,
        error: null,
      );
      return;
    }

    _publishOnDemand(
      state: RadioPlaybackState.connecting,
      userWants: true,
      position: Duration.zero,
      error: null,
    );

    try {
      final AudioSession session = await _ensureAudioSession();
      final bool focusGranted = await session.setActive(true);
      if (!focusGranted) {
        throw StateError('Audio focus not granted');
      }
      _sourceSwitching = true;
      await _queueSourceReset();
      _sourceSwitching = false;
      if (_disposed ||
          _playbackMode != PlaybackMode.onDemand ||
          _currentOnDemandTrack?.id != track.id ||
          !userWantsPlayback) {
        return;
      }
      final just_audio.AudioPlayer player = _ensurePlayer();
      final Duration? duration = await player.setAudioSource(
        just_audio.AudioSource.uri(track.url),
        preload: true,
      );
      if (_disposed ||
          _playbackMode != PlaybackMode.onDemand ||
          _currentOnDemandTrack?.id != track.id ||
          !userWantsPlayback) {
        return;
      }
      _onDemandDuration = duration ?? player.duration;
      _onDemandSourceReady = true;
      _publishOnDemand(
        state: RadioPlaybackState.connecting,
        userWants: true,
        position: player.position,
        error: null,
      );
      unawaited(
        player.play().catchError((Object error, StackTrace stackTrace) async {
          await _handlePlayerError(error);
        }),
      );
    } on Object catch (error) {
      _sourceSwitching = false;
      await _failOnDemand(error);
    }
  }

  Future<void> _resumeOnDemand() async {
    final OnDemandTrack? track = _currentOnDemandTrack;
    if (_disposed || track == null) return;
    if (_player?.playing ?? false) {
      return;
    }
    if (_snapshot.state == RadioPlaybackState.connecting &&
        !_onDemandSourceReady) {
      return;
    }

    _explicitPlaybackSelection = true;
    _rememberVehicleResume(pending: false, routes: const <String>{});
    userWantsPlayback = true;
    _stopping = false;
    _cancelReconnect();
    _cancelStallWatchdog();
    try {
      final AudioSession session = await _ensureAudioSession();
      final bool focusGranted = await session.setActive(true);
      if (!focusGranted) throw StateError('Audio focus not granted');
      final just_audio.AudioPlayer player = _ensurePlayer();
      if (!_onDemandSourceReady) {
        final Duration? duration = await player.setAudioSource(
          just_audio.AudioSource.uri(track.url),
          preload: true,
        );
        _onDemandDuration = duration ?? player.duration;
        _onDemandSourceReady = true;
        final Duration resumePosition = _onDemandResumePosition;
        if (resumePosition > Duration.zero) {
          final Duration? durationLimit = player.duration ?? _onDemandDuration;
          final Duration safePosition =
              durationLimit != null && resumePosition > durationLimit
              ? durationLimit
              : resumePosition;
          await player.seek(safePosition);
          _onDemandResumePosition = Duration.zero;
        }
      }
      _publishOnDemand(
        state: RadioPlaybackState.connecting,
        userWants: true,
        position: player.position,
        error: null,
      );
      unawaited(
        player.play().catchError((Object error, StackTrace stackTrace) async {
          await _handlePlayerError(error);
        }),
      );
    } on Object catch (error) {
      await _failOnDemand(error);
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) {
      return;
    }

    _rememberVehicleResume(pending: false, routes: const <String>{});
    userWantsPlayback = false;
    _stopping = true;
    _reconnectionGuard.invalidate();
    _cancelReconnect();
    _cancelMetadataUpdates();
    _cancelStallWatchdog();
    _wasPlayingBeforeInterruption = false;
    _temporaryInterruptionActive = false;
    _consecutiveFailures = 0;
    _streamKind = RadioStreamKind.mp3;

    await _queueSourceReset();
    _onDemandSourceReady = false;
    await _deactivateAudioSession();
    if (_playbackMode == PlaybackMode.onDemand &&
        _currentOnDemandTrack != null) {
      _publishOnDemand(
        state: RadioPlaybackState.stopped,
        userWants: false,
        position: Duration.zero,
        error: null,
      );
    } else {
      _publish(
        state: RadioPlaybackState.stopped,
        userWants: false,
        streamKind: RadioStreamKind.mp3,
        mode: PlaybackMode.live,
        position: Duration.zero,
        duration: null,
        queueIndex: -1,
        queueLength: 0,
        error: null,
      );
    }
    _stopping = false;
    _clearPlaybackSelection();

    await super.stop();
  }

  @override
  Future<void> pause() async {
    await _pauseInternal(clearVehicleResume: true);
  }

  Future<void> _pauseInternal({required bool clearVehicleResume}) async {
    if (_disposed) {
      return;
    }
    if (clearVehicleResume) {
      _rememberVehicleResume(pending: false, routes: const <String>{});
    }
    userWantsPlayback = false;
    _reconnectionGuard.invalidate();
    _cancelReconnect();
    _cancelMetadataUpdates();
    _cancelStallWatchdog();
    _wasPlayingBeforeInterruption = false;
    _temporaryInterruptionActive = false;

    if (_playbackMode == PlaybackMode.onDemand &&
        _currentOnDemandTrack != null) {
      final just_audio.AudioPlayer? player = _player;
      try {
        await player?.pause();
      } on Object {
        // O estado local continua a ser actualizado.
      }
      await _deactivateAudioSession();
      _publishOnDemand(
        state: RadioPlaybackState.paused,
        userWants: false,
        position: player?.position ?? _snapshot.position,
        error: null,
      );
      _persistPlaybackSelection(force: true);
      return;
    }

    await _queueSourceReset();
    await _deactivateAudioSession();
    _publish(
      state: RadioPlaybackState.paused,
      userWants: false,
      mode: PlaybackMode.live,
      error: null,
    );
    _persistPlaybackSelection(force: true);
  }

  @override
  Future<void> retry() async {
    if (_disposed || _snapshot.state == RadioPlaybackState.playing) {
      return;
    }
    _rememberVehicleResume(pending: false, routes: const <String>{});
    _playbackMode = PlaybackMode.live;
    _currentOnDemandTrack = null;
    _onDemandQueue = const <OnDemandTrack>[];
    _onDemandQueueIndex = -1;
    _onDemandDuration = null;
    _onDemandSourceReady = false;
    userWantsPlayback = true;
    _cancelReconnect();
    _consecutiveFailures = 0;
    _streamKind = RadioStreamKind.mp3;
    final int token = _reconnectionGuard.invalidate();
    if (_temporaryInterruptionActive) {
      _wasPlayingBeforeInterruption = true;
      _publish(
        state: RadioPlaybackState.paused,
        userWants: true,
        streamKind: RadioStreamKind.mp3,
        error: null,
      );
      return;
    }
    _publish(
      state: RadioPlaybackState.reconnecting,
      userWants: true,
      streamKind: RadioStreamKind.mp3,
      error: null,
    );
    try {
      final AudioSession session = await _ensureAudioSession();
      final bool focusGranted = await session.setActive(true);
      if (!focusGranted) {
        throw StateError('Audio focus not granted');
      }
      await _queueSourceReset();
      await _connectToStream(token);
    } on Object catch (error) {
      if (_isPlaybackRequestCurrent(token)) {
        if (_isAudioFocusFailure(error)) {
          await _failIrrecoverably(error);
        } else {
          await _handleFailure(error, attemptId: _attemptId);
        }
      }
    }
  }

  bool _isAudioFocusFailure(Object error) {
    return error is StateError &&
        error.message.toString().contains('Audio focus');
  }

  Future<void> _failIrrecoverably(Object error) async {
    userWantsPlayback = false;
    _reconnectionGuard.invalidate();
    _cancelReconnect();
    _cancelMetadataUpdates();
    await _queueSourceReset();
    await _deactivateAudioSession();
    _publish(
      state: RadioPlaybackState.error,
      userWants: false,
      error: ErrorMapper.friendly(error),
    );
  }

  Future<AudioSession> _ensureAudioSession() async {
    final AudioSession session = _audioSession ??= await AudioSession.instance;
    if (_sessionConfigured) {
      return session;
    }

    await session.configure(const AudioSessionConfiguration.music());
    _interruptionSubscription = session.interruptionEventStream.listen(
      (AudioInterruptionEvent event) => unawaited(_handleInterruption(event)),
    );
    _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
      if ((_player?.playing ?? false) || userWantsPlayback) {
        unawaited(_pauseForVehicleDisconnect());
      }
    });
    _sessionConfigured = true;
    return session;
  }

  Future<void> _initializePersistenceAndVehicleConnection() async {
    try {
      final PlaybackSelection? selection =
          await _playbackSelectionStore.read();
      if (!_explicitPlaybackSelection && selection != null) {
        _restorePlaybackSelection(selection);
      }
    } on Object {
      // O leitor arranca no directo se o estado persistido estiver corrompido.
    }
    try {
      _automaticVehicleResumeEnabled =
          await _vehicleResumeStore.readAutomaticResumeEnabled();
      _vehicleResumePending = await _vehicleResumeStore.readResumePending();
      _vehicleResumeRoutes = await _vehicleResumeStore.readResumeRoutes();
    } on Object {
      _automaticVehicleResumeEnabled = true;
      _vehicleResumePending = false;
      _vehicleResumeRoutes = <String>{};
    }
    if (_disposed) {
      return;
    }
    _vehicleConnectionSubscription = _vehicleConnection.states.listen(
      _queueVehicleConnectionState,
      onError: (Object _) {
        // O áudio continua funcional mesmo num telefone sem serviço automóvel.
      },
    );
  }

  void _restorePlaybackSelection(PlaybackSelection selection) {
    if (selection.mode == PlaybackMode.live ||
        selection.track == null ||
        !_musicAccess.hasMusicAccess) {
      _playbackMode = PlaybackMode.live;
      return;
    }
    _playbackMode = PlaybackMode.onDemand;
    _currentOnDemandTrack = selection.track;
    _onDemandQueue = selection.queue;
    _onDemandQueueIndex = selection.queueIndex;
    _onDemandDuration = null;
    _onDemandSourceReady = false;
    _onDemandResumePosition = selection.position;
    _onDemandQueueContext = selection.contextId.isEmpty
        ? AndroidAutoMediaLibrary.allTracksId
        : selection.contextId;
    _publishSystemQueue();
    _publishOnDemand(
      state: RadioPlaybackState.paused,
      userWants: false,
      position: selection.position,
      error: null,
    );
  }

  void _handleMusicAccessChanged(bool hasAccess) {
    if (!hasAccess) unawaited(_revokeOnDemandPlayback());
  }

  Future<void> _revokeOnDemandPlayback() async {
    if (_disposed || _playbackMode != PlaybackMode.onDemand) return;
    _playbackMode = PlaybackMode.live;
    _currentOnDemandTrack = null;
    _onDemandQueue = const <OnDemandTrack>[];
    _onDemandQueueIndex = -1;
    _onDemandDuration = null;
    _onDemandSourceReady = false;
    _onDemandResumePosition = Duration.zero;
    _onDemandQueueContext = AndroidAutoMediaLibrary.allTracksId;
    queue.add(const <MediaItem>[]);
    await stop();
  }

  void _queueVehicleConnectionState(VehicleConnectionState state) {
    _vehicleEventOperation = _vehicleEventOperation
        .catchError((Object _) {})
        .then((_) => _handleVehicleConnectionState(state));
  }

  Future<void> _handleVehicleConnectionState(
    VehicleConnectionState current,
  ) async {
    if (_disposed) {
      return;
    }
    final VehicleConnectionState? previous = _lastVehicleConnection;
    _lastVehicleConnection = current;
    final VehiclePlaybackDecision decision = VehiclePlaybackPolicy.evaluate(
      previous: previous,
      current: current,
      playbackActive: _isPlaybackActiveForVehicle,
      resumePending: _vehicleResumePending,
      resumeRoutes: _vehicleResumeRoutes,
      automaticResumeEnabled: _automaticVehicleResumeEnabled,
    );
    _rememberVehicleResume(
      pending: decision.resumePending,
      routes: decision.resumeRoutes,
    );
    switch (decision.action) {
      case VehiclePlaybackAction.none:
        return;
      case VehiclePlaybackAction.pause:
        await _pauseInternal(clearVehicleResume: false);
      case VehiclePlaybackAction.resume:
        await play();
    }
  }

  bool get _isPlaybackActiveForVehicle =>
      userWantsPlayback &&
      ((_player?.playing ?? false) ||
          _snapshot.state == RadioPlaybackState.connecting ||
          _snapshot.state == RadioPlaybackState.buffering ||
          _snapshot.state == RadioPlaybackState.playing ||
          _snapshot.state == RadioPlaybackState.reconnecting);

  Future<void> _pauseForVehicleDisconnect() async {
    if (!_isPlaybackActiveForVehicle || _disposed) {
      return;
    }
    final Set<String> routes =
        _lastVehicleConnection?.routes.isNotEmpty == true
        ? _lastVehicleConnection!.routes
        : const <String>{VehiclePlaybackPolicy.anyAudioRoute};
    _rememberVehicleResume(pending: true, routes: routes);
    await _pauseInternal(clearVehicleResume: false);
  }

  void _rememberVehicleResume({
    required bool pending,
    required Set<String> routes,
  }) {
    _vehicleResumePending = pending;
    _vehicleResumeRoutes = Set<String>.unmodifiable(routes);
    unawaited(
      _vehicleResumeStore
          .writeResumeState(pending: pending, routes: routes)
          .catchError((Object _) {}),
    );
  }

  void _persistPlaybackSelection({required bool force}) {
    if (_disposed || !_explicitPlaybackSelection) return;
    final DateTime now = DateTime.now();
    if (!force &&
        _lastSelectionPersistedAt != null &&
        now.difference(_lastSelectionPersistedAt!) <
            const Duration(seconds: 5)) {
      return;
    }
    _lastSelectionPersistedAt = now;
    final PlaybackSelection selection;
    if (_playbackMode == PlaybackMode.onDemand &&
        _currentOnDemandTrack != null &&
        _onDemandQueueIndex >= 0) {
      selection = PlaybackSelection.onDemand(
        track: _currentOnDemandTrack!,
        queue: _onDemandQueue,
        queueIndex: _onDemandQueueIndex,
        position: _player?.position ?? _snapshot.position,
        contextId: _onDemandQueueContext,
      );
    } else {
      selection = const PlaybackSelection.live();
    }
    _selectionWriteOperation = _selectionWriteOperation
        .catchError((Object _) {})
        .then((_) => _playbackSelectionStore.write(selection));
    unawaited(_selectionWriteOperation.catchError((Object _) {}));
  }

  void _clearPlaybackSelection() {
    _explicitPlaybackSelection = false;
    _selectionWriteOperation = _selectionWriteOperation
        .catchError((Object _) {})
        .then((_) => _playbackSelectionStore.clear());
    unawaited(_selectionWriteOperation.catchError((Object _) {}));
  }

  Future<void> _connectToStream(int token) async {
    if (!_isPlaybackRequestCurrent(token)) {
      return;
    }

    final Future<void>? previousOperation = _connectOperation;
    if (previousOperation != null) {
      await previousOperation;
      if (!_isPlaybackRequestCurrent(token)) {
        return;
      }
    }

    await _sourceResetOperation;
    if (!_isPlaybackRequestCurrent(token)) {
      return;
    }

    final Future<void> operation = _performConnect(token);
    _connectOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_connectOperation, operation)) {
        _connectOperation = null;
      }
    }
  }

  Future<void> _performConnect(int token) async {
    final int attempt = ++_attemptId;
    _failedAttemptId = -1;
    _streamKind = ReconnectionPolicy.streamForFailure(_consecutiveFailures);
    _publish(
      state: _consecutiveFailures == 0
          ? RadioPlaybackState.connecting
          : RadioPlaybackState.reconnecting,
      userWants: true,
      streamKind: _streamKind,
      error: null,
    );

    final Uri uri = _streamKind == RadioStreamKind.mp3
        ? RadioConfig.mp3Stream
        : RadioConfig.hlsStream;
    _armStallWatchdog(attempt);
    try {
      final just_audio.AudioPlayer player = _ensurePlayer();
      await player.setAudioSource(
        just_audio.AudioSource.uri(uri),
        preload: true,
      );
      if (!_isPlaybackRequestCurrent(token)) {
        return;
      }
      _startPlayer(token);
    } on Object catch (error) {
      if (_isPlaybackRequestCurrent(token)) {
        await _handleFailure(error, attemptId: attempt);
      }
    }
  }

  void _startPlayer(int token) {
    final just_audio.AudioPlayer? player = _player;
    if (player == null || !_isPlaybackRequestCurrent(token)) {
      return;
    }
    unawaited(
      player.play().catchError((Object error, StackTrace stackTrace) async {
        await _handleFailure(error, attemptId: _attemptId);
      }),
    );
  }

  bool _isPlaybackRequestCurrent(int token) {
    return !_disposed &&
        userWantsPlayback &&
        _reconnectionGuard.isCurrent(token);
  }

  void _onPlayerState(just_audio.PlayerState playerState) {
    if (_disposed) {
      return;
    }
    if (_playbackMode == PlaybackMode.onDemand) {
      _onOnDemandPlayerState(playerState);
      return;
    }

    switch (playerState.processingState) {
      case just_audio.ProcessingState.idle:
        if (_stopping || !userWantsPlayback) {
          _publish(
            state: _snapshot.state == RadioPlaybackState.paused
                ? RadioPlaybackState.paused
                : RadioPlaybackState.stopped,
            userWants: userWantsPlayback,
            error: null,
          );
        } else if (PlaybackRecoveryPolicy.shouldRecoverUnexpectedStop(
          userWantsPlayback: userWantsPlayback,
          interruptionActive: _temporaryInterruptionActive,
          connectionInProgress: _connectOperation != null,
          stopping: _stopping || _sourceSwitching,
        )) {
          unawaited(
            _handleFailure(
              StateError('O leitor ficou inactivo inesperadamente'),
              attemptId: _attemptId,
            ),
          );
        }
      case just_audio.ProcessingState.loading:
        if (userWantsPlayback) {
          _armStallWatchdog(_attemptId);
          _publish(
            state: _consecutiveFailures == 0
                ? RadioPlaybackState.connecting
                : RadioPlaybackState.reconnecting,
            userWants: true,
            error: null,
          );
        }
      case just_audio.ProcessingState.buffering:
        if (userWantsPlayback) {
          _armStallWatchdog(_attemptId);
          _publish(
            state: RadioPlaybackState.buffering,
            userWants: true,
            error: null,
          );
        }
      case just_audio.ProcessingState.ready:
        if (playerState.playing) {
          _cancelStallWatchdog();
          _consecutiveFailures = 0;
          _publish(
            state: RadioPlaybackState.playing,
            userWants: true,
            error: null,
          );
        } else if (PlaybackRecoveryPolicy.shouldRecoverUnexpectedStop(
          userWantsPlayback: userWantsPlayback,
          interruptionActive: _temporaryInterruptionActive,
          connectionInProgress: _connectOperation != null,
          stopping: _stopping || _sourceSwitching,
        )) {
          unawaited(
            _handleFailure(
              StateError('A reprodução parou inesperadamente'),
              attemptId: _attemptId,
            ),
          );
        } else if (!userWantsPlayback &&
            _snapshot.state != RadioPlaybackState.stopped) {
          _publish(
            state: RadioPlaybackState.paused,
            userWants: false,
            error: null,
          );
        }
      case just_audio.ProcessingState.completed:
        if (userWantsPlayback) {
          unawaited(
            _handleFailure(
              StateError('A emissão em directo terminou'),
              attemptId: _attemptId,
            ),
          );
        }
    }
  }

  void _onPlaybackEvent(just_audio.PlaybackEvent event) {
    if (_disposed) return;
    if (_playbackMode == PlaybackMode.onDemand && _currentOnDemandTrack != null) {
      final just_audio.AudioPlayer? player = _player;
      if (player != null) {
        _onDemandDuration = player.duration ?? _onDemandDuration;
      }
      // O audio_service recebe a posição real sem inundar a WebView com eventos.
      playbackState.add(_systemPlaybackState(_snapshot));
      _persistPlaybackSelection(force: false);
    }
  }

  Future<void> _handlePlayerError(Object error) async {
    if (_playbackMode == PlaybackMode.onDemand) {
      await _failOnDemand(error);
      return;
    }
    await _handleFailure(error, attemptId: _attemptId);
  }

  Future<void> _failOnDemand(Object error) async {
    if (_disposed || _playbackMode != PlaybackMode.onDemand) return;
    userWantsPlayback = false;
    _cancelStallWatchdog();
    final just_audio.AudioPlayer? player = _player;
    try {
      await player?.pause();
    } on Object {
      // A falha original é a informação útil a publicar ao utilizador.
    }
    _publishOnDemand(
      state: RadioPlaybackState.error,
      userWants: false,
      position: player?.position ?? _snapshot.position,
      error: ErrorMapper.friendly(error),
    );
  }

  void _onOnDemandPlayerState(just_audio.PlayerState playerState) {
    if (_disposed || _currentOnDemandTrack == null) return;
    final just_audio.AudioPlayer? player = _player;
    _onDemandDuration = player?.duration ?? _onDemandDuration;

    switch (playerState.processingState) {
      case just_audio.ProcessingState.idle:
        if (_stopping || !userWantsPlayback) {
          _publishOnDemand(
            state: _snapshot.state == RadioPlaybackState.paused
                ? RadioPlaybackState.paused
                : RadioPlaybackState.stopped,
            userWants: userWantsPlayback,
            position: player?.position ?? _snapshot.position,
            error: null,
          );
        }
      case just_audio.ProcessingState.loading:
        if (userWantsPlayback) {
          _publishOnDemand(
            state: RadioPlaybackState.connecting,
            userWants: true,
            position: player?.position ?? Duration.zero,
            error: null,
          );
        }
      case just_audio.ProcessingState.buffering:
        if (userWantsPlayback) {
          _publishOnDemand(
            state: RadioPlaybackState.buffering,
            userWants: true,
            position: player?.position ?? _snapshot.position,
            error: null,
          );
        }
      case just_audio.ProcessingState.ready:
        _onDemandSourceReady = true;
        if (playerState.playing) {
          _publishOnDemand(
            state: RadioPlaybackState.playing,
            userWants: true,
            position: player?.position ?? _snapshot.position,
            error: null,
          );
        } else if (!userWantsPlayback) {
          _publishOnDemand(
            state: RadioPlaybackState.paused,
            userWants: false,
            position: player?.position ?? _snapshot.position,
            error: null,
          );
        }
      case just_audio.ProcessingState.completed:
        if (userWantsPlayback) {
          unawaited(_advanceOnDemand());
        }
    }
  }

  Future<void> _advanceOnDemand() async {
    if (_playbackMode != PlaybackMode.onDemand || _disposed) return;
    if (_onDemandQueueIndex >= 0 &&
        _onDemandQueueIndex + 1 < _onDemandQueue.length) {
      final int nextIndex = _onDemandQueueIndex + 1;
      await playOnDemand(
        _onDemandQueue[nextIndex],
        queue: _onDemandQueue,
        queueIndex: nextIndex,
        contextId: _onDemandQueueContext,
      );
      return;
    }
    userWantsPlayback = false;
    final just_audio.AudioPlayer? player = _player;
    _publishOnDemand(
      state: RadioPlaybackState.paused,
      userWants: false,
      position: _onDemandDuration ?? player?.position ?? _snapshot.position,
      error: null,
    );
  }

  @override
  Future<void> skipToNext() async {
    if (_playbackMode != PlaybackMode.onDemand ||
        _onDemandQueueIndex < 0 ||
        _onDemandQueueIndex + 1 >= _onDemandQueue.length) {
      return;
    }
    final int nextIndex = _onDemandQueueIndex + 1;
    await playOnDemand(
      _onDemandQueue[nextIndex],
      queue: _onDemandQueue,
      queueIndex: nextIndex,
      contextId: _onDemandQueueContext,
    );
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playbackMode != PlaybackMode.onDemand || _currentOnDemandTrack == null) {
      return;
    }
    final just_audio.AudioPlayer? player = _player;
    if ((player?.position ?? Duration.zero) > const Duration(seconds: 3) ||
        _onDemandQueueIndex <= 0) {
      await seek(Duration.zero);
      return;
    }
    final int previousIndex = _onDemandQueueIndex - 1;
    await playOnDemand(
      _onDemandQueue[previousIndex],
      queue: _onDemandQueue,
      queueIndex: previousIndex,
      contextId: _onDemandQueueContext,
    );
  }

  @override
  Future<void> seek(Duration position) async {
    if (_playbackMode != PlaybackMode.onDemand || _currentOnDemandTrack == null) {
      return;
    }
    final just_audio.AudioPlayer? player = _player;
    if (player == null || !_onDemandSourceReady) return;
    Duration target = position;
    final Duration? duration = player.duration ?? _onDemandDuration;
    if (duration != null && target > duration) target = duration;
    if (target.isNegative) target = Duration.zero;
    await player.seek(target);
    _publishOnDemand(
      state: _snapshot.state,
      userWants: userWantsPlayback,
      position: target,
      error: _snapshot.error,
    );
    _persistPlaybackSelection(force: true);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_playbackMode != PlaybackMode.onDemand ||
        index < 0 ||
        index >= _onDemandQueue.length) {
      return;
    }
    await playOnDemand(
      _onDemandQueue[index],
      queue: _onDemandQueue,
      queueIndex: index,
      contextId: _onDemandQueueContext,
    );
  }

  Future<void> _handleFailure(Object error, {required int attemptId}) async {
    if (_disposed ||
        !userWantsPlayback ||
        _stopping ||
        _sourceSwitching ||
        _temporaryInterruptionActive ||
        attemptId != _attemptId ||
        attemptId == _failedAttemptId) {
      return;
    }
    _cancelStallWatchdog();
    _failedAttemptId = attemptId;
    _consecutiveFailures += 1;
    _streamKind = ReconnectionPolicy.streamForFailure(_consecutiveFailures);
    _publish(
      state: RadioPlaybackState.reconnecting,
      userWants: true,
      streamKind: _streamKind,
      error: null,
    );

    await _queueSourceReset();

    final bool hasNetwork = await _connectivity.hasNetwork();
    _lastNetworkAvailable = hasNetwork;
    if (!hasNetwork || !userWantsPlayback || _disposed) {
      return;
    }
    _scheduleReconnect(
      ReconnectionPolicy.delayForFailure(_consecutiveFailures),
    );
  }

  void _scheduleReconnect(Duration delay) {
    if (_disposed || !userWantsPlayback) {
      return;
    }
    _cancelReconnect();
    final int token = _reconnectionGuard.current;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_isPlaybackRequestCurrent(token)) {
        unawaited(_connectToStream(token));
      }
    });
  }

  void _scheduleAudioFocusRetry(Duration delay) {
    if (_disposed || !userWantsPlayback) {
      return;
    }
    _cancelReconnect();
    final int token = _reconnectionGuard.current;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_isPlaybackRequestCurrent(token)) {
        unawaited(_resumeAfterTemporaryInterruption());
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _armStallWatchdog(int attemptId) {
    if (_disposed || !userWantsPlayback || _temporaryInterruptionActive) {
      return;
    }
    _stallTimer?.cancel();
    _stallTimer = Timer(RadioConfig.streamStallTimeout, () {
      _stallTimer = null;
      if (attemptId == _attemptId &&
          PlaybackRecoveryPolicy.shouldRecoverUnexpectedStop(
            userWantsPlayback: userWantsPlayback,
            interruptionActive: _temporaryInterruptionActive,
            connectionInProgress: false,
            stopping: _stopping || _sourceSwitching,
          ) &&
          _snapshot.state != RadioPlaybackState.playing) {
        unawaited(
          _handleFailure(
            StateError('A ligação ao directo ficou bloqueada'),
            attemptId: attemptId,
          ),
        );
      }
    });
  }

  void _cancelStallWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  Future<void> _queueSourceReset() {
    if (_player == null) {
      return _sourceResetOperation;
    }
    _sourceResetOperation = _sourceResetOperation
        .catchError((Object _) {})
        .then((_) => _resetPlayerSource());
    return _sourceResetOperation;
  }

  Future<void> _resetPlayerSource() async {
    final just_audio.AudioPlayer? player = _player;
    if (player == null) {
      return;
    }
    try {
      await player.stop();
      await player.clearAudioSources();
    } on Object {
      // A fonte pode já ter sido libertada por uma falha do motor.
    }
  }

  void _onConnectivityChanged(bool isConnected) {
    final bool wasConnected = _lastNetworkAvailable;
    _lastNetworkAvailable = isConnected;

    if (_playbackMode == PlaybackMode.onDemand) {
      if (!isConnected && userWantsPlayback) {
        final just_audio.AudioPlayer? player = _player;
        unawaited(player?.pause() ?? Future<void>.value());
        _publishOnDemand(
          state: RadioPlaybackState.buffering,
          userWants: true,
          position: player?.position ?? _snapshot.position,
          error: null,
        );
        return;
      }
      if (!wasConnected && isConnected && userWantsPlayback) {
        unawaited(_resumeOnDemand());
      }
      return;
    }

    final bool shouldRetry = ConnectivityRecoveryDecider.shouldRetry(
      wasConnected: wasConnected,
      isConnected: isConnected,
      userWantsPlayback: userWantsPlayback,
    );

    if (!isConnected && userWantsPlayback) {
      _reconnectionGuard.invalidate();
      _cancelReconnect();
      _cancelStallWatchdog();
      unawaited(_queueSourceReset());
      _publish(
        state: RadioPlaybackState.reconnecting,
        userWants: true,
        error: null,
      );
      return;
    }
    if (shouldRetry) {
      _scheduleReconnect(Duration.zero);
    }
  }

  Future<void> _handleInterruption(AudioInterruptionEvent event) async {
    if (_disposed) {
      return;
    }

    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          final just_audio.AudioPlayer? player = _player;
          if (player != null && player.playing) {
            _ducked = true;
            unawaited(player.setVolume(0.35));
          }
        case AudioInterruptionType.pause:
          _temporaryInterruptionActive = true;
          _wasPlayingBeforeInterruption =
              userWantsPlayback &&
              ((_player?.playing ?? false) ||
                  _snapshot.state == RadioPlaybackState.connecting ||
                  _snapshot.state == RadioPlaybackState.buffering ||
                  _snapshot.state == RadioPlaybackState.playing ||
                  _snapshot.state == RadioPlaybackState.reconnecting);
          if (_wasPlayingBeforeInterruption) {
            _reconnectionGuard.invalidate();
            _cancelReconnect();
            _cancelStallWatchdog();
            if (_playbackMode == PlaybackMode.onDemand) {
              final just_audio.AudioPlayer? player = _player;
              try {
                await player?.pause();
              } on Object {
                // A interrupção do sistema continua a ter prioridade.
              }
              _publishOnDemand(
                state: RadioPlaybackState.paused,
                userWants: true,
                position: player?.position ?? _snapshot.position,
                error: null,
              );
            } else {
              _publish(
                state: RadioPlaybackState.paused,
                userWants: true,
                mode: PlaybackMode.live,
                error: null,
              );
              await _queueSourceReset();
            }
          }
        case AudioInterruptionType.unknown:
          _temporaryInterruptionActive = false;
          _wasPlayingBeforeInterruption = false;
          userWantsPlayback = false;
          _reconnectionGuard.invalidate();
          _cancelReconnect();
          _cancelStallWatchdog();
          await _queueSourceReset();
          _onDemandSourceReady = false;
          if (_playbackMode == PlaybackMode.onDemand &&
              _currentOnDemandTrack != null) {
            _publishOnDemand(
              state: RadioPlaybackState.paused,
              userWants: false,
              position: Duration.zero,
              error: null,
            );
          } else {
            _publish(
              state: RadioPlaybackState.paused,
              userWants: false,
              mode: PlaybackMode.live,
              error: null,
            );
          }
      }
      return;
    }

    if (event.type == AudioInterruptionType.duck && _ducked) {
      _ducked = false;
      final just_audio.AudioPlayer? player = _player;
      if (player != null) {
        unawaited(player.setVolume(1));
      }
      return;
    }

    if (event.type == AudioInterruptionType.pause &&
        _temporaryInterruptionActive) {
      final bool shouldResume =
          PlaybackRecoveryPolicy.shouldResumeAfterTemporaryInterruption(
            wasActiveBeforeInterruption: _wasPlayingBeforeInterruption,
            userWantsPlayback: userWantsPlayback,
          );
      _wasPlayingBeforeInterruption = false;
      _temporaryInterruptionActive = false;
      if (shouldResume) {
        await _resumeAfterTemporaryInterruption();
      }
    }
  }

  Future<void> _resumeAfterTemporaryInterruption() async {
    if (!userWantsPlayback || _disposed) {
      return;
    }
    if (_playbackMode == PlaybackMode.onDemand) {
      await _resumeOnDemand();
      return;
    }

    final int token = _reconnectionGuard.current;
    _publish(
      state: RadioPlaybackState.reconnecting,
      userWants: true,
      mode: PlaybackMode.live,
      error: null,
    );
    try {
      final AudioSession session = await _ensureAudioSession();
      final bool focusGranted = await session.setActive(true);
      if (!_isPlaybackRequestCurrent(token)) {
        return;
      }
      if (!focusGranted) {
        _consecutiveFailures += 1;
        _scheduleAudioFocusRetry(
          ReconnectionPolicy.delayForFailure(_consecutiveFailures),
        );
        return;
      }
      _consecutiveFailures = 0;
      _streamKind = RadioStreamKind.mp3;
      await _connectToStream(token);
    } on Object {
      if (_isPlaybackRequestCurrent(token)) {
        _consecutiveFailures += 1;
        _scheduleAudioFocusRetry(
          ReconnectionPolicy.delayForFailure(_consecutiveFailures),
        );
      }
    }
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    final bool playbackActive =
        (_player?.playing ?? false) ||
        _snapshot.state == RadioPlaybackState.connecting ||
        _snapshot.state == RadioPlaybackState.buffering ||
        _snapshot.state == RadioPlaybackState.reconnecting;
    switch (RadioMediaButtonPolicy.actionFor(
      button: button,
      playbackActive: playbackActive,
    )) {
      case RadioMediaButtonAction.play:
        await play();
      case RadioMediaButtonAction.pause:
        await pause();
      case RadioMediaButtonAction.ignore:
        return;
    }
  }

  Future<void> _deactivateAudioSession() async {
    try {
      await _audioSession?.setActive(false);
    } on Object {
      // O estado do leitor é actualizado mesmo se o sistema já retirou o foco.
    }
  }

  void _publish({
    required RadioPlaybackState state,
    required bool userWants,
    RadioStreamKind? streamKind,
    NowPlayingMetadata? metadata,
    PlaybackMode? mode,
    Duration? position,
    Object? duration = _keepValue,
    int? queueIndex,
    int? queueLength,
    Object? error = _keepValue,
  }) {
    if (_disposed) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      state: state,
      userWantsPlayback: userWants,
      streamKind: streamKind ?? _streamKind,
      metadata: metadata,
      mode: mode,
      position: position,
      duration: identical(duration, _keepValue) ? _snapshot.duration : duration,
      queueIndex: queueIndex,
      queueLength: queueLength,
      error: identical(error, _keepValue) ? _snapshot.error : error,
    );
    _snapshotController.add(_snapshot);
    playbackState.add(_systemPlaybackState(_snapshot));

    if (metadata != null || mode == PlaybackMode.onDemand) {
      mediaItem.add(_mediaItemFor(_snapshot.metadata));
    }

    if (state == RadioPlaybackState.playing &&
        _snapshot.mode == PlaybackMode.live) {
      _startMetadataUpdates();
    } else {
      _cancelMetadataUpdates();
    }
  }

  void _publishOnDemand({
    required RadioPlaybackState state,
    required bool userWants,
    Duration? position,
    Object? error = _keepValue,
  }) {
    final OnDemandTrack? track = _currentOnDemandTrack;
    if (track == null) return;
    final just_audio.AudioPlayer? player = _player;
    _onDemandDuration = player?.duration ?? _onDemandDuration;
    _publish(
      state: state,
      userWants: userWants,
      metadata: track.metadata,
      mode: PlaybackMode.onDemand,
      position: position ?? player?.position ?? _snapshot.position,
      duration: _onDemandDuration,
      queueIndex: _onDemandQueueIndex,
      queueLength: _onDemandQueue.length,
      error: error,
    );
  }

  void _publishSystemQueue() {
    queue.add(
      _onDemandQueue
          .map(
            (OnDemandTrack track) => AndroidAutoMediaLibrary.track(
              track,
              contextId: _onDemandQueueContext,
            ),
          )
          .toList(growable: false),
    );
  }

  static const Object _keepValue = Object();

  void _startMetadataUpdates() {
    if (_metadataTimer != null || _playbackMode != PlaybackMode.live) {
      return;
    }
    unawaited(_refreshMetadata());
    _metadataTimer = Timer.periodic(
      RadioConfig.metadataPollInterval,
      (_) => unawaited(_refreshMetadata()),
    );
  }

  void _cancelMetadataUpdates() {
    _metadataTimer?.cancel();
    _metadataTimer = null;
  }

  Future<void> _refreshMetadata() async {
    if (_metadataRequestInProgress ||
        _disposed ||
        _playbackMode != PlaybackMode.live ||
        _snapshot.state != RadioPlaybackState.playing) {
      return;
    }
    _metadataRequestInProgress = true;
    try {
      final NowPlayingMetadata metadata = await _nowPlayingService.fetch();
      if (_disposed ||
          _playbackMode != PlaybackMode.live ||
          _snapshot.state != RadioPlaybackState.playing) {
        return;
      }
      _snapshot = _snapshot.copyWith(metadata: metadata, error: null);
      mediaItem.add(_mediaItemFor(metadata));
      _snapshotController.add(_snapshot);
      playbackState.add(_systemPlaybackState(_snapshot));
    } on Object {
      // Uma falha da API nunca interrompe a emissão.
    } finally {
      _metadataRequestInProgress = false;
    }
  }

  MediaItem _mediaItemFor(NowPlayingMetadata metadata) {
    final Uri artwork = metadata.artwork == RadioConfig.defaultArtwork
        ? bundledArtwork ?? metadata.artwork
        : metadata.artwork;
    final bool isLive = metadata.isLive;
    return MediaItem(
      id: isLive
          ? AndroidAutoMediaLibrary.stationId
          : _currentOnDemandTrack == null
          ? metadata.title
          : AndroidAutoMediaLibrary.trackMediaId(
              _currentOnDemandTrack!.id,
              contextId: _onDemandQueueContext,
            ),
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album ?? RadioConfig.stationName,
      artUri: artwork,
      duration: isLive ? null : _onDemandDuration,
      playable: true,
      isLive: isLive,
      extras: <String, Object>{'isLive': isLive},
    );
  }

  PlaybackState _systemPlaybackState(RadioPlaybackSnapshot snapshot) {
    final bool isPlaying =
        snapshot.userWantsPlayback &&
        (snapshot.state == RadioPlaybackState.connecting ||
            snapshot.state == RadioPlaybackState.buffering ||
            snapshot.state == RadioPlaybackState.playing ||
            snapshot.state == RadioPlaybackState.reconnecting);
    final bool isActive =
        snapshot.state != RadioPlaybackState.stopped &&
        snapshot.state != RadioPlaybackState.error;

    late final List<MediaControl> controls;
    late final List<int> compact;
    late final Set<MediaAction> systemActions;
    if (snapshot.mode == PlaybackMode.onDemand) {
      controls = isActive
          ? <MediaControl>[
              MediaControl.skipToPrevious,
              isPlaying ? MediaControl.pause : MediaControl.play,
              MediaControl.skipToNext,
              MediaControl.stop,
            ]
          : const <MediaControl>[];
      compact = controls.isEmpty ? const <int>[] : const <int>[0, 1, 2];
      systemActions = const <MediaAction>{
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      };
    } else {
      controls = isActive
          ? <MediaControl>[
              isPlaying ? MediaControl.pause : MediaControl.play,
              MediaControl.stop,
            ]
          : const <MediaControl>[];
      compact = controls.isEmpty ? const <int>[] : const <int>[0, 1];
      systemActions = const <MediaAction>{
        MediaAction.playFromMediaId,
        MediaAction.playFromSearch,
      };
    }

    final just_audio.AudioPlayer? player = _player;
    return PlaybackState(
      controls: controls,
      systemActions: systemActions,
      androidCompactActionIndices: compact,
      processingState: switch (snapshot.state) {
        RadioPlaybackState.stopped => AudioProcessingState.idle,
        RadioPlaybackState.connecting => AudioProcessingState.loading,
        RadioPlaybackState.buffering => AudioProcessingState.buffering,
        RadioPlaybackState.playing => AudioProcessingState.ready,
        RadioPlaybackState.paused => AudioProcessingState.ready,
        RadioPlaybackState.reconnecting => AudioProcessingState.loading,
        RadioPlaybackState.error => AudioProcessingState.error,
      },
      playing: isPlaying,
      updatePosition: snapshot.mode == PlaybackMode.onDemand
          ? player?.position ?? snapshot.position
          : Duration.zero,
      bufferedPosition: snapshot.mode == PlaybackMode.onDemand
          ? player?.bufferedPosition ?? Duration.zero
          : Duration.zero,
      speed: 1,
      queueIndex: snapshot.mode == PlaybackMode.onDemand &&
              snapshot.queueIndex >= 0
          ? snapshot.queueIndex
          : null,
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    // Fechar a Activity não é uma ordem de STOP. O foreground service e a
    // MediaSession mantêm legitimamente a reprodução.
  }

  /// Usado por testes e pelo encerramento controlado do processo.
  Future<void> disposeHandler() async {
    if (_disposed) {
      return;
    }
    userWantsPlayback = false;
    _reconnectionGuard.invalidate();
    _cancelReconnect();
    _cancelMetadataUpdates();
    _cancelStallWatchdog();
    await _queueSourceReset();
    await _deactivateAudioSession();
    await _playerStateSubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _musicAccessSubscription?.cancel();
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    await _vehicleConnectionSubscription?.cancel();
    await _vehicleEventOperation.catchError((Object _) {});
    await _selectionWriteOperation.catchError((Object _) {});
    _nativeMusicCatalog.close();
    _nowPlayingService.close();
    final just_audio.AudioPlayer? player = _player;
    _player = null;
    await player?.dispose();
    _disposed = true;
    await _snapshotController.close();
  }
}
