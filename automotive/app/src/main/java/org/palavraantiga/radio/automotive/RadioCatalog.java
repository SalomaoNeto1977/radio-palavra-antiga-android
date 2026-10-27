package org.palavraantiga.radio.automotive;

import java.net.URI;
import java.text.Normalizer;
import java.util.Locale;

/** Public station configuration. Never resolves caller-supplied playback URLs. */
final class RadioCatalog {
    static final String ROOT = "palavraantiga";
    static final String LIVE = "palavraantiga:live";
    static final String NAME = "Rádio Palavra Antiga";
    static final String STREAM = "https://radio.palavraantiga.org/listen/palavraantiga/radio.mp3";
    static final String NOW_PLAYING = "https://radio.palavraantiga.org/api/nowplaying/palavraantiga";

    static boolean matches(String query) {
        String text = normalize(query);
        return text.isEmpty() || text.contains("palavra antiga")
                || text.contains("palavraantiga");
    }

    private static String normalize(String value) {
        if (value == null) return "";
        return Normalizer.normalize(value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "").toLowerCase(Locale.ROOT).trim();
    }

    static boolean allowedArtwork(String value) {
        try {
            URI uri = URI.create(value);
            String host = uri.getHost();
            return "https".equalsIgnoreCase(uri.getScheme())
                    && uri.getUserInfo() == null
                    && (uri.getPort() == -1 || uri.getPort() == 443)
                    && ("radio.palavraantiga.org".equalsIgnoreCase(host)
                    || "palavraantiga.org".equalsIgnoreCase(host)
                    || "www.palavraantiga.org".equalsIgnoreCase(host));
        } catch (IllegalArgumentException | NullPointerException ignored) {
            return false;
        }
    }
}
