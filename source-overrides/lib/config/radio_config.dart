/// Todos os endereços e valores fixos da rádio vivem exclusivamente aqui.
abstract final class RadioConfig {
  static const String stationName = 'Rádio Palavra Antiga';
  static const String defaultTitle = stationName;
  static const String defaultArtist = 'Em directo';

  static final Uri appPage = Uri.https('palavraantiga.org', '/app1');
  static final Uri mp3Stream = Uri.https(
    'radio.palavraantiga.org',
    '/listen/palavraantiga/radio.mp3',
  );
  static final Uri hlsStream = Uri.https(
    'radio.palavraantiga.org',
    '/hls/palavraantiga/live.m3u8',
  );
  static final Uri nowPlayingApi = Uri.https(
    'radio.palavraantiga.org',
    '/api/nowplaying/palavraantiga',
  );
  static final Uri alternateNowPlayingApi = Uri.https(
    'radio.palavraantiga.org',
    '/public/palavraantiga/nowplaying.json',
  );
  static final Uri onDemandApi = Uri.https(
    'radio.palavraantiga.org',
    '/api/station/palavraantiga/ondemand',
  );
  static final Uri requestableSongsApi = Uri.https(
    'radio.palavraantiga.org',
    '/api/station/palavraantiga/requests',
  );
  static final Uri officialPlaylistsCatalog = Uri.https(
    'raw.githubusercontent.com',
    '/SalomaoNeto1977/radio-palavra-antiga-android/main/'
        'catalog/official_playlists.json',
  );
  static final Uri googlePlaySubscriptions = Uri.https(
    'play.google.com',
    '/store/account/subscriptions',
    <String, String>{'package': 'org.palavraantiga.radio'},
  );
  static final Uri whatsappContact = Uri.https(
    'wa.me',
    '/351800500321',
  );

  /// Endereço originalmente fornecido para a capa da estação.
  ///
  /// É mantido centralizado para poder voltar a ser usado quando o servidor
  /// de rádio o disponibilizar novamente.
  static final Uri configuredDefaultArtwork = Uri.https(
    'radio.palavraantiga.org',
    '/logo512.png',
  );
  static final Uri defaultArtwork = Uri.https(
    'palavraantiga.org',
    '/web/image/website/1/logo/512x512',
  );

  static const Set<String> allowedHosts = <String>{
    'palavraantiga.org',
    'www.palavraantiga.org',
    'radio.palavraantiga.org',
  };

  static const String javascriptChannel = 'RPA';
  static const String userAgent =
      'RadioPalavraAntiga/1.0.13 (Android; Flutter WebView)';
  static const String notificationChannelId = 'org.palavraantiga.radio.audio';
  static const String notificationChannelName =
      'Reprodução da Rádio Palavra Antiga';
  static const String notificationIcon = 'drawable/ic_stat_radio';
  static const String bundledLogoAsset = 'assets/images/logo.png';
  static const String officialPlaylistsAsset =
      'assets/data/official_playlists.json';
  static const String bridgeAsset = 'web_integration/rpa_bridge.js';
  static final Uri androidAutoBrowseIcon = Uri.parse(
    'android.resource://org.palavraantiga.radio/drawable/ic_stat_radio',
  );

  static const Duration metadataPollInterval = Duration(seconds: 12);
  static const Duration networkRequestTimeout = Duration(seconds: 8);
  static const Duration streamStallTimeout = Duration(seconds: 35);
  static const Duration commandDebounce = Duration(milliseconds: 350);
  static const List<Duration> reconnectDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];
  static const int mp3FailuresBeforeHls = 3;

  static bool isAllowedHttpsUri(Uri uri) {
    return uri.scheme == 'https' &&
        uri.hasAuthority &&
        allowedHosts.contains(uri.host.toLowerCase());
  }
}
