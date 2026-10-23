import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from email.message import Message
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit

from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'ci'))
from generate_playlist_manifest import (
    COVERS_BASE_URL, MAX_COVER_BYTES, ManifestError, NoCoverRedirects,
    attach_folder_covers, fetch_cover_image, fetch_folder_cover,
    folder_image_candidates, main, normalize_cover,
)


def image_bytes(format="PNG", color="red", size=(8, 8)):
    output = io.BytesIO()
    Image.new("RGB", size, color).save(output, format=format)
    return output.getvalue()


class ImageResponse:
    def __init__(self, data):
        self.data = data
        self.headers = Message()
        self.headers["Content-Type"] = "application/octet-stream"

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self, limit):
        return self.data[:limit]

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

    def test_arbitrary_names_newest_first_and_only_images_in_same_directory(self):
        rows = [
            {"path": "Álbum/cover.jpg", "timestamp": 1},
            {"path": "Álbum/desenho que fiz.PNG", "timestamp": 30},
            {"path": "Álbum/z.webp", "timestamp": 20},
            {"path": "Álbum/a.jpeg", "timestamp": 20},
            {"path": "Álbum/musica.mp3", "timestamp": 100},
            {"path": "Álbum/subpasta/outra.png", "timestamp": 100},
            {"path": "Outra/capa.png", "timestamp": 100},
            {"path": "Álbum/../outra.png", "timestamp": 100},
            {"path": "/Álbum/absoluta.jpg", "timestamp": 100},
            {"path": "Álbum/.oculta.png", "timestamp": 100},
            {"path": "Álbum/pasta.png", "is_dir": True, "timestamp": 100},
        ]
        expected = ["Álbum/desenho que fiz.PNG", "Álbum/a.jpeg", "Álbum/z.webp", "Álbum/cover.jpg"]
        self.assertEqual(folder_image_candidates(rows, "Álbum"), expected)
        self.assertEqual(folder_image_candidates(list(reversed(rows)), "Álbum"), expected)

    def test_lists_every_page_and_accepts_image_on_later_page(self):
        pages = [
            {"total": 2, "per_page": 1, "rows": [{"path": "Álbum/song.mp3"}]},
            {"total": 2, "per_page": 1, "rows": [{"path": "Álbum/sem nome especial.png", "timestamp": 5}]},
        ]
        with patch("generate_playlist_manifest.fetch_json", side_effect=pages) as listing, patch(
            "generate_playlist_manifest.fetch_cover_image", return_value=b"jpeg"
        ) as download:
            result = fetch_folder_cover("https://radio.palavraantiga.org", "palavraantiga", "Álbum", "secret")
        self.assertEqual(result, b"jpeg")
        self.assertEqual(listing.call_count, 2)
        self.assertIn("current=2", listing.call_args.args[1])
        self.assertIn("currentDirectory=%C3%81lbum", listing.call_args.args[1])
        download.assert_called_once_with("https://radio.palavraantiga.org", "palavraantiga", "Álbum/sem nome especial.png", "secret")

    def test_corrupt_newest_image_falls_back_to_next_valid_image(self):
        rows = [
            {"path": "Album/cover.jpg", "timestamp": 1},
            {"path": "Album/nova.png", "timestamp": 3},
            {"path": "Album/desenho.webp", "timestamp": 2},
        ]
        with patch("generate_playlist_manifest.fetch_all_rows", return_value=rows), patch(
            "generate_playlist_manifest.fetch_cover_image", side_effect=[None, b"valid"]
        ) as download:
            self.assertEqual(fetch_folder_cover("https://radio.palavraantiga.org", "palavraantiga", "Album", "secret"), b"valid")
        self.assertEqual([call.args[2] for call in download.call_args_list], ["Album/nova.png", "Album/desenho.webp"])

    def test_raster_formats_are_exported_as_real_metadata_free_jpegs(self):
        for format in ["JPEG", "PNG", "WEBP", "GIF", "BMP", "TIFF", "AVIF"]:
            with self.subTest(format=format):
                result = normalize_cover(image_bytes(format=format))
                self.assertIsNotNone(result)
                with Image.open(io.BytesIO(result)) as cover:
                    self.assertEqual(cover.format, "JPEG")
                    self.assertEqual(cover.size, (8, 8))
                    self.assertEqual(dict(cover.getexif()), {})
        self.assertIsNone(normalize_cover(b"<html>not an image</html>"))
        self.assertIsNone(normalize_cover(b"<svg xmlns='http://www.w3.org/2000/svg'/>"))

    def test_transparency_scaling_and_image_limits(self):
        output = io.BytesIO()
        Image.new("RGBA", (2048, 1024), (255, 0, 0, 0)).save(output, format="PNG")
        with Image.open(io.BytesIO(normalize_cover(output.getvalue()))) as image:
            self.assertEqual(image.size, (1024, 512))
            self.assertEqual(image.getpixel((0, 0)), (255, 255, 255))
        self.assertIsNone(normalize_cover(b"x" * (MAX_COVER_BYTES + 1)))
        with patch("generate_playlist_manifest.MAX_COVER_PIXELS", 4):
            self.assertIsNone(normalize_cover(image_bytes(size=(3, 3))))

    def test_generic_download_content_type_and_encoded_arbitrary_name(self):
        with patch("generate_playlist_manifest.build_opener") as builder:
            builder.return_value.open.return_value = ImageResponse(image_bytes())
            result = fetch_cover_image("https://radio.palavraantiga.org", "palavraantiga", "Album/Um desenho #1.PNG", "private-key")
        self.assertTrue(result.startswith(b"\xff\xd8\xff"))
        request = builder.return_value.open.call_args.args[0]
        self.assertEqual(parse_qs(urlsplit(request.full_url).query)["file"], ["Album/Um desenho #1.PNG"])
        self.assertEqual(urlsplit(request.full_url).hostname, "radio.palavraantiga.org")
        self.assertIsInstance(builder.call_args.args[0], NoCoverRedirects)
        self.assertIsNone(NoCoverRedirects().redirect_request(request, None, 302, "Found", {}, "https://other.example/"))

    def test_missing_image_is_optional_but_network_and_permissions_fail_safely(self):
        for code in [403, 500, 302]:
            with self.subTest(code=code), patch("generate_playlist_manifest.build_opener") as builder:
                builder.return_value.open.side_effect = HTTPError("url", code, "error", {}, None)
                with self.assertRaises(ManifestError):
                    fetch_cover_image("https://radio.palavraantiga.org", "palavraantiga", "Album/image.png", "secret")
        with patch("generate_playlist_manifest.build_opener") as builder:
            builder.return_value.open.side_effect = HTTPError("url", 404, "missing", {}, None)
            self.assertIsNone(fetch_cover_image("https://radio.palavraantiga.org", "palavraantiga", "Album/image.png", "secret"))
        with patch("generate_playlist_manifest.fetch_all_rows", side_effect=ManifestError("private path")):
            with self.assertRaisesRegex(ManifestError, "catálogo anterior") as error:
                fetch_folder_cover("https://radio.palavraantiga.org", "palavraantiga", "Album", "secret")
        self.assertNotIn("private path", str(error.exception))

    def test_replacing_same_named_image_changes_public_url(self):
        media = [{"unique_id": "song", "path": "Album/song.mp3"}]
        urls = []
        with tempfile.TemporaryDirectory() as directory:
            for color in ["red", "blue"]:
                manifest = {"playlists": [{"id": "a", "track_ids": ["song"]}]}
                with patch("generate_playlist_manifest.fetch_folder_cover", return_value=normalize_cover(image_bytes(color=color))):
                    attach_folder_covers(manifest, media, "https://radio.palavraantiga.org", "palavraantiga", "secret", Path(directory))
                urls.append(manifest["playlists"][0]["cover_url"])
        self.assertNotEqual(*urls)

    def test_failed_cover_sync_does_not_overwrite_existing_catalog(self):
        public = [{"track_id": "song"}]
        playlists = [{"id": "a", "name": "Album", "is_enabled": True, "include_in_on_demand": True}]
        media = [{"unique_id": "song", "path": "Album/song.mp3", "playlists": ["a"]}]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "catalog.json"
            output.write_text("previous-catalog", encoding="utf-8")
            with patch.dict(os.environ, {"AZURACAST_API_KEY": "secret"}), patch(
                "generate_playlist_manifest.fetch_json", return_value=public
            ), patch("generate_playlist_manifest.fetch_all_rows", side_effect=[playlists, media]), patch(
                "generate_playlist_manifest.fetch_folder_cover", side_effect=ManifestError("temporary network failure")
            ), redirect_stderr(io.StringIO()):
                self.assertEqual(main(["--output", str(output), "--covers-dir", str(Path(directory) / "covers")]), 1)
            self.assertEqual(output.read_text(encoding="utf-8"), "previous-catalog")

