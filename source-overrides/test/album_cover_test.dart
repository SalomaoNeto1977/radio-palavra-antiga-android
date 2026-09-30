import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:radio_palavra_antiga/config/radio_config.dart';
import 'package:radio_palavra_antiga/native_music_catalog_service.dart';
import 'package:radio_palavra_antiga/official_playlist_catalog_service.dart';
import 'package:radio_palavra_antiga/radio_audio_handler.dart';
import 'package:radio_palavra_antiga/user_music_library.dart';

class _Library implements UserMusicLibraryStore {
  @override
  Future<UserMusicLibrary> read() async => const UserMusicLibrary(favorites: [], playlists: {});
  @override
  Future<void> write(UserMusicLibrary library) async {}
}

void main() {
  final cover = 'https://raw.githubusercontent.com/SalomaoNeto1977/radio-palavra-antiga-android/main/catalog/covers/${'a' * 64}.jpg';
  String manifest(String artwork) => jsonEncode({
    'schema_version': 1,
    'playlists': [{ 'id': 'a', 'name': 'CD - (70s) Louvor', 'description': '', 'track_ids': ['song'], 'cover_url': artwork }],
  });

  test('catalog retains only images exported by the album cover generator', () {
    final parsed = OfficialPlaylistCatalogService.parseCatalog(manifest(cover))!;
    expect((parsed['playlists'] as List).single['cover_url'], cover);
    for (final invalid in ['https://example.com/cover.jpg', '$cover?key=private', cover.replaceFirst('/main/', '/other/')]) {
      final parsed = OfficialPlaylistCatalogService.parseCatalog(manifest(invalid))!;
      expect((parsed['playlists'] as List).single.containsKey('cover_url'), isFalse);
    }
    expect(RadioConfig.isAllowedArtworkUri(Uri.parse(cover)), isTrue);
  });

  test('folder cover reaches native tracks and Android Auto album folders', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async => http.Response(jsonEncode([{
      'track_id': 'song', 'download_url': 'https://radio.palavraantiga.org/audio/song.mp3',
      'media': {'title': 'Canção', 'artist': 'Artista', 'album': 'CD - (70s) Louvor', 'art': 'https://radio.palavraantiga.org/art/song.jpg'},
    }]), 200));
    final service = NativeMusicCatalogService(bundledOfficialPlaylists: manifest(cover), userLibraryStore: _Library(), client: client);
    final catalog = await service.load();
    expect(catalog.tracks.single.artwork.toString(), cover);
    expect(catalog.tracks.single.album, 'Louvor');
    expect(AndroidAutoMediaLibrary.officialPlaylist(catalog.officialPlaylists.single).artUri.toString(), cover);
    service.close();
    client.close();
  });
}
