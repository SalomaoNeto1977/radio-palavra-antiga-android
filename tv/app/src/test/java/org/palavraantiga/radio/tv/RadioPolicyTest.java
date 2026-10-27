package org.palavraantiga.radio.tv;

import static org.junit.Assert.*;
import org.junit.Test;

public class RadioPolicyTest {
    @Test public void reconnectNeverStartsBeforeUserPlay() {
        RetryPolicy retry = new RetryPolicy();
        assertEquals(-1, retry.nextDelay());
        assertFalse(retry.requested());
    }
    @Test public void manualPauseCancelsPendingRetriesAndResumption() {
        RetryPolicy retry = new RetryPolicy();
        retry.play();
        assertEquals(2000, retry.nextDelay());
        retry.pause();
        assertFalse(retry.requested());
        assertEquals(-1, retry.nextDelay());
    }
    @Test public void retriesBackOffAndStayBoundedDuringLongOutage() {
        RetryPolicy retry = new RetryPolicy();
        retry.play();
        assertEquals(2000, retry.nextDelay());
        assertEquals(5000, retry.nextDelay());
        assertEquals(10000, retry.nextDelay());
        assertEquals(20000, retry.nextDelay());
        for (int i = 0; i < 100; i++) assertEquals(30000, retry.nextDelay());
    }
    @Test public void successfulConnectionResetsBackoff() {
        RetryPolicy retry = new RetryPolicy();
        retry.play(); retry.nextDelay(); retry.nextDelay();
        retry.connected();
        assertEquals(2000, retry.nextDelay());
    }
    @Test public void voiceSearchAcceptsStationNameAndRejectsOtherStations() {
        assertTrue(RadioCatalog.matches("Ouvir Rádio PALAVRA ANTIGA"));
        assertTrue(RadioCatalog.matches("palavraantiga"));
        assertFalse(RadioCatalog.matches("outra estação"));
    }
    @Test public void remoteImagesUseExactHttpsHostsOnly() {
        assertTrue(RadioCatalog.allowedArtwork("https://radio.palavraantiga.org/api/albumart/a"));
        assertTrue(RadioCatalog.allowedArtwork("https://www.palavraantiga.org/logo.png"));
        for (String value : new String[] {
                "http://radio.palavraantiga.org/a", "https://radio.palavraantiga.org.evil.example/a",
                "https://evil.example@radio.palavraantiga.org/a",
                "https://radio.palavraantiga.org:8080/a", "file:///a", "invalid", null}) {
            assertFalse(String.valueOf(value), RadioCatalog.allowedArtwork(value));
        }
    }
}
