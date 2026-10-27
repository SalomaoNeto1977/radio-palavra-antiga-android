package org.palavraantiga.radio.automotive;

import static org.junit.Assert.*;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.MediaMetadata;
import android.media.browse.MediaBrowser;
import android.media.session.MediaController;
import android.media.session.PlaybackState;
import android.util.Log;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Runs against a real AAOS system image, including actual network playback. */
@RunWith(AndroidJUnit4.class)
public class RadioCarIntegrationTest {
    @Test public void carBrowserCanBrowsePlayLiveAudioAndPause() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertTrue("The device must run Android Automotive",
                context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE));
        AtomicReference<MediaBrowser> browser = new AtomicReference<>();
        CountDownLatch connected = new CountDownLatch(1);
        ComponentName component = new ComponentName(context, RadioLibraryService.class);
        onMain(() -> {
            MediaBrowser client = new MediaBrowser(context, component,
                    new MediaBrowser.ConnectionCallback() {
                        @Override public void onConnected() { connected.countDown(); }
                        @Override public void onConnectionFailed() { connected.countDown(); }
                    }, null);
            browser.set(client);
            client.connect();
        });
        MediaController controls = null;
        try {
            assertTrue("Car browser connection timed out", connected.await(25, TimeUnit.SECONDS));
            assertTrue("Car browser rejected the service", browser.get().isConnected());
            controls = new MediaController(context, browser.get().getSessionToken());
            PlaybackState initial = controls.getPlaybackState();
            assertTrue("Binding alone must not start the radio",
                    initial == null || initial.getState() != PlaybackState.STATE_PLAYING);
            CountDownLatch loaded = new CountDownLatch(1);
            AtomicReference<List<MediaBrowser.MediaItem>> children = new AtomicReference<>();
            onMain(() -> browser.get().subscribe(browser.get().getRoot(), new MediaBrowser.SubscriptionCallback() {
                @Override public void onChildrenLoaded(String parent, List<MediaBrowser.MediaItem> items) {
                    children.set(items);
                    loaded.countDown();
                }
                @Override public void onError(String parent) { loaded.countDown(); }
            }));
            assertTrue("Station catalogue timed out", loaded.await(15, TimeUnit.SECONDS));
            assertNotNull("Station catalogue failed", children.get());
            assertEquals(1, children.get().size());
            assertEquals(RadioCatalog.LIVE, children.get().get(0).getMediaId());
            assertTrue(children.get().get(0).isPlayable());

            // Put the car's own media host on screen before requesting audio focus.
            Intent open = new Intent("android.car.intent.action.MEDIA_TEMPLATE");
            open.putExtra("android.car.intent.extra.MEDIA_COMPONENT", component.flattenToString());
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            onMain(() -> context.startActivity(open));
            MediaController controller = controls;
            controller.getTransportControls().playFromMediaId(RadioCatalog.LIVE, null);
            await(() -> state(controller) == PlaybackState.STATE_PLAYING, 45000);
            MediaMetadata metadata = controller.getMetadata();
            assertNotNull("Car did not receive metadata", metadata);
            assertNotNull(metadata.getString(MediaMetadata.METADATA_KEY_TITLE));
            assertFalse(metadata.getString(MediaMetadata.METADATA_KEY_TITLE).trim().isEmpty());
            Log.i("RadioCarTest", "AAOS live playback and metadata confirmed");
            controller.getTransportControls().pause();
            await(() -> state(controller) == PlaybackState.STATE_PAUSED
                    || state(controller) == PlaybackState.STATE_STOPPED, 10000);
            Thread.sleep(3000);
            assertNotEquals("Radio resumed after a manual pause",
                    PlaybackState.STATE_PLAYING, state(controller));
            Log.i("RadioCarTest", "AAOS manual pause confirmed");
        } finally {
            if (controls != null) controls.getTransportControls().stop();
            onMain(() -> browser.get().disconnect());
        }
    }
    private static int state(MediaController controller) {
        PlaybackState state = controller.getPlaybackState();
        return state == null ? PlaybackState.STATE_NONE : state.getState();
    }
    private static void await(BooleanSupplier condition, long timeout) throws Exception {
        long end = System.currentTimeMillis() + timeout;
        while (System.currentTimeMillis() < end) {
            if (condition.getAsBoolean()) return;
            Thread.sleep(200);
        }
        fail("Timed out waiting for the expected car playback state");
    }
    private static void onMain(Runnable action) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(action);
    }
}
