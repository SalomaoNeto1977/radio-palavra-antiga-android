package org.palavraantiga.radio.automotive;

import static org.junit.Assert.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public class StationMetadataTest {
    @Test public void preservesBroadcasterTitleAndArtist() throws Exception {
        StationMetadata value = StationMetadata.parse("{\"now_playing\":{\"song\":{\"title\":\"Salmo 23_Versão 2\",\"artist\":\"Vento Norte\",\"art\":\"https://radio.palavraantiga.org/art.png\"}}}");
        assertEquals("Salmo 23_Versão 2", value.title);
        assertEquals("Vento Norte", value.artist);
        assertEquals("https://radio.palavraantiga.org/art.png", value.artwork);
    }
    @Test public void missingMetadataFallsBackToLiveStation() throws Exception {
        StationMetadata value = StationMetadata.parse("{}");
        assertEquals(RadioCatalog.NAME, value.title);
        assertEquals("Em direto", value.artist);
        assertEquals("", value.artwork);
    }
    @Test public void invalidArtworkAndNullTextNeverReachCarDisplay() throws Exception {
        StationMetadata value = StationMetadata.parse("{\"now_playing\":{\"song\":{\"title\":null,\"artist\":\"undefined\",\"art\":\"https://evil.example/a\"}}}");
        assertEquals(RadioCatalog.NAME, value.title);
        assertEquals("Em direto", value.artist);
        assertEquals("", value.artwork);
    }
}
