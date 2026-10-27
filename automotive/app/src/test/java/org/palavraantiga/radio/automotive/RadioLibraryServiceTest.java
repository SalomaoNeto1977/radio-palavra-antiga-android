package org.palavraantiga.radio.automotive;

import static org.junit.Assert.*;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.session.MediaLibraryService.MediaLibrarySession;
import androidx.media3.session.LibraryResult;
import androidx.media3.session.SessionError;
import com.google.common.collect.ImmutableList;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ServiceController;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public class RadioLibraryServiceTest {
    private ServiceController<RadioLibraryService> lifecycle;
    private RadioLibraryService service;
    private RadioLibraryService.LibraryCallback callback;
    private MediaLibrarySession session;

    @Before public void create() {
        lifecycle = Robolectric.buildService(RadioLibraryService.class).create();
        service = lifecycle.get();
        callback = service.new LibraryCallback();
        session = service.onGetSession(null);
    }
    @After public void destroy() { lifecycle.destroy(); }

    @Test public void browserConnectionDoesNotStartPlayback() {
        assertNotNull(session);
        assertFalse(session.getPlayer().getPlayWhenReady());
        assertEquals(Player.STATE_IDLE, session.getPlayer().getPlaybackState());
    }
    @Test public void rootContainsBrowsableTabWithOnePlayableStationAndSupportsPagination() throws Exception {
        LibraryResult<ImmutableList<MediaItem>> first = callback.onGetChildren(session, null, RadioCatalog.ROOT, 0, 10, null).get();
        assertEquals(1, first.value.size());
        assertEquals(RadioCatalog.LIVE_CATEGORY, first.value.get(0).mediaId);
        assertEquals(Boolean.TRUE, first.value.get(0).mediaMetadata.isBrowsable);
        assertEquals(Boolean.FALSE, first.value.get(0).mediaMetadata.isPlayable);
        MediaItem station = callback.onGetChildren(session, null, RadioCatalog.LIVE_CATEGORY, 0, 10, null).get().value.get(0);
        assertEquals(RadioCatalog.LIVE, station.mediaId);
        assertEquals(Boolean.TRUE, station.mediaMetadata.isPlayable);
        assertEquals("android.resource", station.mediaMetadata.artworkUri.getScheme());
        assertTrue(callback.onGetChildren(session, null, RadioCatalog.ROOT, 1, 10, null).get().value.isEmpty());
        assertEquals(SessionError.ERROR_BAD_VALUE,
                callback.onGetChildren(session, null, "unknown", 0, 10, null).get().resultCode);
    }
    @Test public void callerCannotReplaceStationStreamWithAnExternalUrl() throws Exception {
        MediaItem request = new MediaItem.Builder().setMediaId(RadioCatalog.LIVE)
                .setUri("https://unrelated.example/audio.mp3").build();
        MediaItem resolved = callback.onAddMediaItems(session, null, ImmutableList.of(request)).get().get(0);
        assertEquals(RadioCatalog.STREAM, resolved.localConfiguration.uri.toString());
    }
    @Test public void unknownMediaIdsAreRejected() throws Exception {
        assertEquals(SessionError.ERROR_BAD_VALUE, callback.onGetItem(session, null, "unknown").get().resultCode);
        assertThrows(java.util.concurrent.ExecutionException.class, () ->
                callback.onAddMediaItems(session, null,
                        ImmutableList.of(new MediaItem.Builder().setMediaId("unknown").build())).get());
    }
    @Test public void liveStationDoesNotExposeSeekOrPlaylistEditingControls() {
        assertFalse(session.getPlayer().isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM));
        assertFalse(session.getPlayer().isCommandAvailable(Player.COMMAND_CHANGE_MEDIA_ITEMS));
        assertTrue(session.getPlayer().isCommandAvailable(Player.COMMAND_PLAY_PAUSE));
    }
}
