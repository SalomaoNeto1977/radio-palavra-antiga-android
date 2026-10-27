package org.palavraantiga.radio.automotive;

import static org.junit.Assert.*;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.media.MediaMetadata;
import android.media.browse.MediaBrowser;
import android.media.session.MediaController;
import android.media.session.PlaybackState;
import android.util.Log;
import android.util.Base64;
import android.os.Bundle;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.Until;
import java.io.ByteArrayOutputStream;
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
            assertEquals(RadioCatalog.LIVE_CATEGORY, children.get().get(0).getMediaId());
            assertTrue(children.get().get(0).isBrowsable());
            CountDownLatch stationLoaded = new CountDownLatch(1);
            onMain(() -> browser.get().subscribe(RadioCatalog.LIVE_CATEGORY, new MediaBrowser.SubscriptionCallback() {
                @Override public void onChildrenLoaded(String parent, List<MediaBrowser.MediaItem> items) {
                    children.set(items);
                    stationLoaded.countDown();
                }
                @Override public void onError(String parent) { stationLoaded.countDown(); }
            }));
            assertTrue("Live category timed out", stationLoaded.await(15, TimeUnit.SECONDS));
            assertEquals(RadioCatalog.LIVE, children.get().get(0).getMediaId());
            assertTrue(children.get().get(0).isPlayable());

            // Put the car's own media host on screen before requesting audio focus.
            Intent open = new Intent("android.car.intent.action.MEDIA_TEMPLATE");
            open.putExtra("android.car.intent.extra.MEDIA_COMPONENT", component.flattenToString());
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            onMain(() -> context.startActivity(open));
            UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
            assertTrue("The car must show the live category, not an empty screen",
                    device.wait(Until.hasObject(By.text(
                            java.util.regex.Pattern.compile("(?i).*em direto.*"))), 15000));
            MediaController controller = controls;
            controller.getTransportControls().playFromMediaId(RadioCatalog.LIVE, null);
            await(() -> state(controller) == PlaybackState.STATE_PLAYING, 45000);
            MediaMetadata metadata = controller.getMetadata();
            assertNotNull("Car did not receive metadata", metadata);
            assertNotNull(metadata.getString(MediaMetadata.METADATA_KEY_TITLE));
            assertFalse(metadata.getString(MediaMetadata.METADATA_KEY_TITLE).trim().isEmpty());
            Log.i("RadioCarTest", "AAOS live playback and metadata confirmed");
            screenshot(context, "playing");
            controller.getTransportControls().pause();
            await(() -> state(controller) == PlaybackState.STATE_PAUSED
                    || state(controller) == PlaybackState.STATE_STOPPED, 10000);
            Thread.sleep(3000);
            assertNotEquals("Radio resumed after a manual pause",
                    PlaybackState.STATE_PLAYING, state(controller));
            Log.i("RadioCarTest", "AAOS manual pause confirmed");
            screenshot(context, "paused");
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
    private static void screenshot(Context context, String state) throws Exception {
        String label = InstrumentationRegistry.getArguments().getString("screenshotLabel", "landscape");
        Bitmap image = InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();
        assertNotNull("Screenshot not available", image);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        assertTrue(image.compress(Bitmap.CompressFormat.PNG, 100, bytes));
        image.recycle();
        Bundle report = new Bundle();
        report.putString("stream", "\nAAOS_SCREENSHOT " + label + "-" + state + ".png "
                + Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP) + "\n");
        InstrumentationRegistry.getInstrumentation().sendStatus(2, report);
    }
}
