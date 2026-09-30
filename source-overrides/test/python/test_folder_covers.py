import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from generate_playlist_manifest import attach_folder_covers, COVERS_BASE_URL

class FolderCoversTest(unittest.TestCase):
    def test_folder_image_wins_and_is_downloaded_once_without_exposing_paths(self):
        manifest = {'playlists': [
            {'id': 'a', 'track_ids': ['one', 'two']},
            {'id': 'b', 'track_ids': ['one']},
            {'id': 'mixed', 'track_ids': ['one', 'three']},
            {'id': 'unknown', 'track_ids': ['missing']},
        ]}
        media = [{'unique_id': 'one', 'path': 'Private Album/one.mp3'},
                 {'unique_id': 'two', 'path': 'Private Album/two.mp3'},
                 {'unique_id': 'three', 'path': 'Other/three.mp3'}]
        with tempfile.TemporaryDirectory() as directory, patch('generate_playlist_manifest.fetch_folder_cover', return_value=b'jpeg-fixture') as download:
            attach_folder_covers(manifest, media, 'https://radio.palavraantiga.org', 'palavraantiga', 'private-key', Path(directory))
            download.assert_called_once_with('https://radio.palavraantiga.org', 'palavraantiga', 'Private Album', 'private-key')
            self.assertEqual(manifest['playlists'][0]['cover_url'], manifest['playlists'][1]['cover_url'])
            self.assertTrue(manifest['playlists'][0]['cover_url'].startswith(COVERS_BASE_URL + '/'))
            self.assertNotIn('cover_url', manifest['playlists'][2])
            self.assertNotIn('cover_url', manifest['playlists'][3])
            self.assertEqual(len(list(Path(directory).glob('*.jpg'))), 1)
            self.assertNotIn('Private Album', str(manifest))
            self.assertNotIn('private-key', str(manifest))

    def test_missing_cover_and_unsafe_paths_preserve_original_fallback(self):
        manifest = {'playlists': [{'id': 'a', 'track_ids': ['one']}, {'id': 'bad', 'track_ids': ['two']}]}
        media = [{'unique_id': 'one', 'path': 'Album/one.mp3'}, {'unique_id': 'two', 'path': '../private/two.mp3'}]
        with tempfile.TemporaryDirectory() as directory, patch('generate_playlist_manifest.fetch_folder_cover', return_value=None) as download:
            attach_folder_covers(manifest, media, 'https://radio.palavraantiga.org', 'palavraantiga', 'key', Path(directory))
            self.assertEqual(download.call_count, 1)
            self.assertTrue(all('cover_url' not in p for p in manifest['playlists']))
            self.assertEqual(list(Path(directory).iterdir()), [])
