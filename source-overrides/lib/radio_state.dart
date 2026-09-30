import 'config/radio_config.dart';
import 'album_title.dart';

enum RadioPlaybackState {
  stopped,
  connecting,
  buffering,
  playing,
  paused,
  reconnecting,
  error,
}

enum RadioStreamKind { mp3, hls }

enum PlaybackMode { live, onDemand }

class OnDemandTrack {
  const OnDemandTrack({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    this.album,
    required this.artwork,
  });

  final String id;
  final Uri url;
  final String title;
  final String artist;
  final String? album;
  final Uri artwork;

  NowPlayingMetadata get metadata => NowPlayingMetadata(
    title: title,
    artist: artist,
    album: album,
    artwork: artwork,
    isLive: false,
  );

  Map<String, Object?> toWebMap() => <String, Object?>{
    'id': id,
    'url': url.toString(),
    'title': title,
    'artist': artist,
    'album': album,
    'artwork': artwork.toString(),
  };

  static OnDemandTrack? fromWebMap(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final String id = (value['id'] as String? ?? '').trim();
    final String title = (value['title'] as String? ?? '').trim();
    final String artist = (value['artist'] as String? ?? '').trim();
    final String? rawAlbum = value['album'] as String?;
    final String? album = rawAlbum == null ? null : publicAlbumTitle(rawAlbum);
    final Uri? url = Uri.tryParse((value['url'] as String? ?? '').trim());
    final Uri? artwork = Uri.tryParse(
      (value['artwork'] as String? ?? RadioConfig.defaultArtwork.toString())
          .trim(),
    );

    if (id.isEmpty || title.isEmpty || url == null || artwork == null) {
      return null;
    }
    if (!_isAllowedAudioUri(url) || !RadioConfig.isAllowedArtworkUri(artwork)) {
      return null;
    }

    return OnDemandTrack(
      id: id,
      url: url,
      title: title,
      artist: artist.isEmpty ? RadioConfig.stationName : artist,
      album: album == null || album.isEmpty ? null : album,
      artwork: artwork,
    );
  }

  static bool _isAllowedAudioUri(Uri uri) {
    return uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.host.toLowerCase() == 'radio.palavraantiga.org';
  }


}

class NowPlayingMetadata {
  const NowPlayingMetadata({
    required this.title,
    required this.artist,
    this.album,
    required this.artwork,
    this.isLive = true,
  });

  NowPlayingMetadata.fallback()
    : title = RadioConfig.defaultTitle,
      artist = RadioConfig.defaultArtist,
      album = null,
      artwork = RadioConfig.defaultArtwork,
      isLive = true;

  final String title;
  final String artist;
  final String? album;
  final Uri artwork;
  final bool isLive;

  Map<String, Object?> toWebMap({String? error}) => <String, Object?>{
    'title': title,
    'artist': artist,
    'album': album,
    'artwork': artwork.toString(),
    'isLive': isLive,
    'error': error,
  };

  @override
  bool operator ==(Object other) {
    return other is NowPlayingMetadata &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        other.artwork == artwork &&
        other.isLive == isLive;
  }

  @override
  int get hashCode => Object.hash(title, artist, album, artwork, isLive);
}

class RadioPlaybackSnapshot {
  const RadioPlaybackSnapshot({
    required this.state,
    required this.userWantsPlayback,
    required this.metadata,
    required this.streamKind,
    this.mode = PlaybackMode.live,
    this.position = Duration.zero,
    this.duration,
    this.queueIndex = -1,
    this.queueLength = 0,
    this.error,
  });

  RadioPlaybackSnapshot.initial()
    : state = RadioPlaybackState.stopped,
      userWantsPlayback = false,
      metadata = NowPlayingMetadata.fallback(),
      streamKind = RadioStreamKind.mp3,
      mode = PlaybackMode.live,
      position = Duration.zero,
      duration = null,
      queueIndex = -1,
      queueLength = 0,
      error = null;

  final RadioPlaybackState state;
  final bool userWantsPlayback;
  final NowPlayingMetadata metadata;
  final RadioStreamKind streamKind;
  final PlaybackMode mode;
  final Duration position;
  final Duration? duration;
  final int queueIndex;
  final int queueLength;
  final String? error;

  String get pageState => switch (state) {
    RadioPlaybackState.stopped => 'STOPPED',
    RadioPlaybackState.connecting => 'CONNECTING',
    RadioPlaybackState.buffering => 'BUFFERING',
    RadioPlaybackState.playing => 'PLAYING',
    RadioPlaybackState.paused => 'PAUSED',
    RadioPlaybackState.reconnecting => 'RECONNECTING',
    RadioPlaybackState.error => 'ERROR',
  };

  Map<String, Object?> get playerWebMap => <String, Object?>{
    'mode': mode == PlaybackMode.onDemand ? 'ondemand' : 'live',
    'positionMs': position.inMilliseconds,
    'durationMs': duration?.inMilliseconds,
    'queueIndex': queueIndex,
    'queueLength': queueLength,
    'canPrevious': mode == PlaybackMode.onDemand &&
        (queueIndex > 0 || position > const Duration(seconds: 3)),
    'canNext': mode == PlaybackMode.onDemand &&
        queueIndex >= 0 &&
        queueIndex + 1 < queueLength,
  };

  static const Object _unchanged = Object();

  RadioPlaybackSnapshot copyWith({
    RadioPlaybackState? state,
    bool? userWantsPlayback,
    NowPlayingMetadata? metadata,
    RadioStreamKind? streamKind,
    PlaybackMode? mode,
    Duration? position,
    Object? duration = _unchanged,
    int? queueIndex,
    int? queueLength,
    Object? error = _unchanged,
  }) {
    return RadioPlaybackSnapshot(
      state: state ?? this.state,
      userWantsPlayback: userWantsPlayback ?? this.userWantsPlayback,
      metadata: metadata ?? this.metadata,
      streamKind: streamKind ?? this.streamKind,
      mode: mode ?? this.mode,
      position: position ?? this.position,
      duration: identical(duration, _unchanged)
          ? this.duration
          : duration as Duration?,
      queueIndex: queueIndex ?? this.queueIndex,
      queueLength: queueLength ?? this.queueLength,
      error: identical(error, _unchanged) ? this.error : error as String?,
    );
  }
}
