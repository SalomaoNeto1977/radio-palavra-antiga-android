#!/usr/bin/env python3
"""Generate the public station-playlist manifest embedded in the Android app.

The AzuraCast API key is read only from the environment and is never written to
the generated file.  The output contains only playlist names and public
On-Demand track identifiers.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


class ManifestError(RuntimeError):
    """Raised when a safe playlist manifest cannot be produced."""


def response_rows(payload: Any) -> list[dict[str, Any]]:
    """Accept both AzuraCast's plain-list and paginated response shapes."""
    if isinstance(payload, list):
        return [row for row in payload if isinstance(row, dict)]
    if isinstance(payload, dict):
        for key in ("rows", "data", "items"):
            rows = payload.get(key)
            if isinstance(rows, list):
                return [row for row in rows if isinstance(row, dict)]
    return []


def is_true(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def first_value(row: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in row:
            return row[key]
    return None


def playlist_id(row: dict[str, Any]) -> str:
    return str(first_value(row, "id", "playlist_id", "playlistId") or "").strip()


def playlist_name(row: dict[str, Any]) -> str:
    return str(first_value(row, "name", "playlist_name", "playlistName") or "").strip()


def build_manifest(
    public_on_demand: Any,
    station_playlists: Any,
    station_media: Any,
    *,
    generated_at: str | None = None,
) -> dict[str, Any]:
    public_rows = response_rows(public_on_demand)
    playlist_rows = response_rows(station_playlists)
    media_rows = response_rows(station_media)

    public_track_ids = {
        str(first_value(row, "track_id", "trackId") or "").strip()
        for row in public_rows
    }
    public_track_ids.discard("")
    if not public_track_ids:
        raise ManifestError("O catálogo público On-Demand não contém músicas.")

    eligible: dict[str, dict[str, Any]] = {}
    for row in playlist_rows:
        pid = playlist_id(row)
        name = playlist_name(row)
        enabled = first_value(row, "is_enabled", "isEnabled")
        on_demand = first_value(
            row,
            "include_in_on_demand",
            "includeInOnDemand",
        )
        if not pid or not name or not is_true(enabled) or not is_true(on_demand):
            continue
        eligible[pid] = {
            "id": pid,
            "name": name,
            "description": str(row.get("description") or "").strip(),
            "track_ids": set(),
        }

    if not eligible:
        raise ManifestError(
            "Não existem playlists activas marcadas como Include in On-Demand Player."
        )

    mapped_track_ids: set[str] = set()
    for media in media_rows:
        track_id = str(first_value(media, "unique_id", "uniqueId") or "").strip()
        if not track_id or track_id not in public_track_ids:
            continue
        memberships = media.get("playlists")
        if not isinstance(memberships, list):
            continue
        for membership in memberships:
            pid = (
                playlist_id(membership)
                if isinstance(membership, dict)
                else str(membership or "").strip()
            )
            target = eligible.get(pid)
            if target is None:
                continue
            target["track_ids"].add(track_id)
            mapped_track_ids.add(track_id)

    official_playlists: list[dict[str, Any]] = []
    for playlist in eligible.values():
        tracks = sorted(playlist["track_ids"])
        if not tracks:
            continue
        official_playlists.append(
            {
                "id": playlist["id"],
                "name": playlist["name"],
                "description": playlist["description"],
                "track_ids": tracks,
            }
        )

    official_playlists.sort(key=lambda item: item["name"].casefold())

    unassigned = sorted(public_track_ids - mapped_track_ids)
    if unassigned:
        official_playlists.append(
            {
                "id": "unassigned",
                "name": "Outras músicas",
                "description": "Músicas On-Demand ainda sem uma playlist identificada.",
                "track_ids": unassigned,
                "is_fallback": True,
            }
        )

    if not official_playlists or not mapped_track_ids:
        raise ManifestError(
            "As músicas On-Demand não puderam ser associadas às playlists do AzuraCast."
        )

    return {
        "schema_version": 1,
        "generated_at": generated_at
        or datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "playlists": official_playlists,
        "statistics": {
            "public_tracks": len(public_track_ids),
            "mapped_tracks": len(mapped_track_ids),
            "unassigned_tracks": len(unassigned),
            "official_playlists": sum(
                1 for item in official_playlists if not item.get("is_fallback")
            ),
        },
    }


def fetch_json(base_url: str, path: str, api_key: str | None = None) -> Any:
    url = base_url.rstrip("/") + path
    headers = {
        "Accept": "application/json",
        "User-Agent": "RadioPalavraAntiga-Build/1.0",
    }
    if api_key:
        headers["X-API-Key"] = api_key

    request = Request(url, headers=headers, method="GET")
    try:
        with urlopen(request, timeout=60) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            return json.loads(response.read().decode(charset))
    except HTTPError as error:
        raise ManifestError(
            f"O AzuraCast respondeu HTTP {error.code} ao consultar {path}."
        ) from error
    except (URLError, TimeoutError) as error:
        raise ManifestError(f"Não foi possível consultar o AzuraCast em {path}.") from error
    except json.JSONDecodeError as error:
        raise ManifestError(f"O AzuraCast devolveu JSON inválido em {path}.") from error


def fetch_all_rows(
    base_url: str,
    path: str,
    api_key: str,
    *,
    row_count: int = 500,
) -> list[dict[str, Any]]:
    """Read every page from an AzuraCast Bootgrid-style list endpoint."""
    rows: list[dict[str, Any]] = []
    seen_rows: set[str] = set()
    current = 1

    while current <= 1000:
        separator = "&" if "?" in path else "?"
        payload = fetch_json(
            base_url,
            f"{path}{separator}current={current}&rowCount={row_count}",
            api_key,
        )
        page = response_rows(payload)
        previous_count = len(rows)

        for row in page:
            fingerprint = json.dumps(
                row,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            if fingerprint not in seen_rows:
                seen_rows.add(fingerprint)
                rows.append(row)

        if isinstance(payload, list) or not page:
            break

        total_raw = payload.get("total") if isinstance(payload, dict) else None
        try:
            total = int(total_raw) if total_raw is not None else None
        except (TypeError, ValueError):
            total = None
        if total is not None and len(rows) >= total:
            break

        returned_count_raw = (
            payload.get("rowCount") if isinstance(payload, dict) else None
        )
        try:
            returned_count = int(returned_count_raw)
        except (TypeError, ValueError):
            returned_count = row_count
        if total is None and returned_count > 0 and len(page) < returned_count:
            break

        if len(rows) == previous_count:
            raise ManifestError(f"A paginação do AzuraCast repetiu dados em {path}.")
        current += 1

    else:
        raise ManifestError(f"A paginação do AzuraCast excedeu o limite em {path}.")

    return rows


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base-url",
        default="https://radio.palavraantiga.org",
    )
    parser.add_argument("--station", default="palavraantiga")
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    api_key = os.environ.get("AZURACAST_API_KEY", "").strip()
    if not api_key:
        print(
            "Erro: o segredo AZURACAST_API_KEY não está configurado.",
            file=sys.stderr,
        )
        return 2

    station = quote(args.station, safe="")
    try:
        on_demand = fetch_json(
            args.base_url,
            f"/api/station/{station}/ondemand",
        )
        playlists = fetch_all_rows(
            args.base_url,
            f"/api/station/{station}/playlists",
            api_key,
        )
        media = fetch_all_rows(
            args.base_url,
            f"/api/station/{station}/files",
            api_key,
        )
        manifest = build_manifest(on_demand, playlists, media)
        write_manifest(args.output, manifest)
    except ManifestError as error:
        print(f"Erro: {error}", file=sys.stderr)
        return 1

    stats = manifest["statistics"]
    print(
        "Playlists oficiais preparadas: "
        f"{stats['official_playlists']} playlists, "
        f"{stats['mapped_tracks']}/{stats['public_tracks']} músicas associadas, "
        f"{stats['unassigned_tracks']} por associar."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
