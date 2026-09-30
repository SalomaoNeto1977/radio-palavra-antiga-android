import 'package:flutter_test/flutter_test.dart';
import 'package:radio_palavra_antiga/album_title.dart';
import 'package:radio_palavra_antiga/radio_state.dart';

void main() {
  test('public album title removes only a complete administrative prefix', () {
    const cases = <String, String>{
      'CD - (70s) Um dia de Ca...': 'Um dia de Ca...',
      '  cd – (Cig) A Caravana Vai Subindo  ': 'A Caravana Vai Subindo',
      'CD (interno) O Meu Lugar (Ao vivo)': 'O Meu Lugar (Ao vivo)',
      'CD - () Louvor': 'Louvor',
      'Louvor (Ao vivo)': 'Louvor (Ao vivo)',
      'CD - (70s)': 'CD - (70s)',
      'CD - (70s Um dia': 'CD - (70s Um dia',
      'CD - Louvor': 'CD - Louvor',
      'ABCD - (70s) Louvor': 'ABCD - (70s) Louvor',
      '': '',
    };
    for (final entry in cases.entries) {
      expect(publicAlbumTitle(entry.key), entry.value);
      expect(publicAlbumTitle(publicAlbumTitle(entry.key)), entry.value);
    }
  });

  test('restored tracks expose public album metadata without changing identity', () {
    final track = OnDemandTrack.fromWebMap(<String, dynamic>{
      'id': 'stable-track-id',
      'url': 'https://radio.palavraantiga.org/listen/test.mp3',
      'title': 'CD - (70s) song title must stay intact',
      'artist': 'Rádio Palavra Antiga',
      'album': 'CD - (70s) Um dia de cada vez',
      'artwork': 'https://radio.palavraantiga.org/art.jpg',
    });
    expect(track!.id, 'stable-track-id');
    expect(track.title, 'CD - (70s) song title must stay intact');
    expect(track.metadata.album, 'Um dia de cada vez');
    expect(track.toWebMap()['album'], 'Um dia de cada vez');
  });
}
