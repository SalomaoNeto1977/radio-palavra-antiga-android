import sys
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "tools"))

from generate_playlist_manifest import (  # noqa: E402
    ManifestError,
    build_manifest,
    fetch_all_rows,
)


class PlaylistManifestTest(unittest.TestCase):
    def test_groups_only_public_tracks_in_on_demand_playlists(self):
        public = [
            {"track_id": "track-a"},
            {"track_id": "track-b"},
            {"track_id": "track-c"},
        ]
        playlists = {
            "rows": [
                {
                    "id": 10,
                    "name": "Louvor",
                    "is_enabled": True,
                    "include_in_on_demand": True,
                },
                {
                    "id": 11,
                    "name": "Rotação interna",
                    "is_enabled": True,
                    "include_in_on_demand": False,
                },
            ]
        }
        media = [
            {
                "unique_id": "track-a",
                "playlists": [{"id": 10}, {"id": 11}],
            },
            {"unique_id": "track-b", "playlists": [10]},
            {"unique_id": "track-c", "playlists": [{"id": 11}]},
            {"unique_id": "not-public", "playlists": [{"id": 10}]},
        ]

        manifest = build_manifest(
            public,
            playlists,
            media,
            generated_at="2026-08-30T00:00:00+00:00",
        )

        self.assertEqual(manifest["statistics"]["mapped_tracks"], 2)
        self.assertEqual(manifest["statistics"]["unassigned_tracks"], 1)
        self.assertEqual(manifest["playlists"][0]["name"], "Louvor")
        self.assertEqual(
            manifest["playlists"][0]["track_ids"],
            ["track-a", "track-b"],
        )
        self.assertEqual(manifest["playlists"][1]["name"], "Outras músicas")
        self.assertEqual(manifest["playlists"][1]["track_ids"], ["track-c"])

    def test_rejects_catalog_without_on_demand_playlists(self):
        with self.assertRaises(ManifestError):
            build_manifest(
                [{"track_id": "track-a"}],
                [{"id": 1, "name": "Desligada", "is_enabled": False}],
                [],
            )

    def test_fetches_every_paginated_media_row(self):
        pages = [
            {
                "current": 1,
                "rowCount": 2,
                "total": 3,
                "rows": [{"unique_id": "a"}, {"unique_id": "b"}],
            },
            {
                "current": 2,
                "rowCount": 2,
                "total": 3,
                "rows": [{"unique_id": "c"}],
            },
        ]
        with patch("generate_playlist_manifest.fetch_json", side_effect=pages) as fetch:
            rows = fetch_all_rows(
                "https://radio.example",
                "/api/station/test/files",
                "secret-used-only-by-the-request",
                row_count=2,
            )

        self.assertEqual([row["unique_id"] for row in rows], ["a", "b", "c"])
        self.assertEqual(fetch.call_count, 2)
        self.assertIn("current=1&rowCount=2", fetch.call_args_list[0].args[1])
        self.assertIn("current=2&rowCount=2", fetch.call_args_list[1].args[1])


if __name__ == "__main__":
    unittest.main()
