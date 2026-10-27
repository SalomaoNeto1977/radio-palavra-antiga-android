package org.palavraantiga.radio.tv;

import org.json.JSONObject;

/** Keeps the broadcaster's titles intact, including numbers and underscores. */
final class StationMetadata {
    final String title;
    final String artist;
    final String artwork;
    StationMetadata(String title, String artist, String artwork) {
        this.title = title;
        this.artist = artist;
        this.artwork = artwork;
    }
    static StationMetadata parse(String json) throws Exception {
        JSONObject payload = new JSONObject(json);
        JSONObject now = payload.optJSONObject("now_playing");
        JSONObject song = now == null ? null : now.optJSONObject("song");
        String title = song == null ? "" : text(song.optString("title", ""));
        String artist = song == null ? "" : text(song.optString("artist", ""));
        String art = song == null ? "" : song.optString("art", "");
        return new StationMetadata(title.isEmpty() ? RadioCatalog.NAME : title,
                artist.isEmpty() ? "Em direto" : artist,
                RadioCatalog.allowedArtwork(art) ? art : "");
    }
    private static String text(String value) {
        String text = value.trim();
        return text.equalsIgnoreCase("null") || text.equalsIgnoreCase("undefined") ? "" : text;
    }
}
