package org.palavraantiga.radio.tv;

import static org.junit.Assert.*;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.media.browse.MediaBrowser;
import android.media.session.MediaController;
import android.media.session.PlaybackState;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.Until;
import java.io.File;
import java.io.FileOutputStream;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Runs on Android TV with real network audio; every UI action uses the remote's D-pad. */
@RunWith(AndroidJUnit4.class)
public class RadioTvIntegrationTest {
    @Test public void remoteCanPlayPauseStopOpenAboutAndReturnFromHome() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertTrue("An actual TV system image is required",
                context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_LEANBACK));
        AtomicReference<MediaBrowser> browser = new AtomicReference<>();
        CountDownLatch connected = new CountDownLatch(1);
        onMain(() -> {
            MediaBrowser client = new MediaBrowser(context, new ComponentName(context, RadioLibraryService.class),
                    new MediaBrowser.ConnectionCallback() {
                        @Override public void onConnected() { connected.countDown(); }
                        @Override public void onConnectionFailed() { connected.countDown(); }
                    }, null);
            browser.set(client); client.connect();
        });
        assertTrue(connected.await(25, TimeUnit.SECONDS));
        assertTrue(browser.get().isConnected());
        MediaController controller = new MediaController(context, browser.get().getSessionToken());
        UiDevice device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        try {
            assertNotEquals("Binding alone must be silent", PlaybackState.STATE_PLAYING, state(controller));
            open(context);
            assertTrue(device.wait(Until.hasObject(By.text("Ouvir em direto").focused(true)), 20000));
            screenshot("ready");
            device.pressDPadCenter();
            await(() -> state(controller) == PlaybackState.STATE_PLAYING, 45000);
            assertTrue(device.wait(Until.hasObject(By.text("● EM DIRETO")), 15000));
            assertNotNull(controller.getMetadata());
            screenshot("playing");

            device.pressHome();
            Thread.sleep(2500);
            assertEquals("Background audio must continue", PlaybackState.STATE_PLAYING, state(controller));
            open(context);
            assertTrue(device.wait(Until.hasObject(By.text("Pausar").focused(true)), 15000));
            device.pressDPadCenter();
            await(() -> state(controller) == PlaybackState.STATE_PAUSED, 10000);
            Thread.sleep(2500);
            assertNotEquals("A manual pause must not restart the stream", PlaybackState.STATE_PLAYING, state(controller));
            screenshot("paused");

            device.pressDPadRight();
            assertTrue(device.wait(Until.hasObject(By.text("Parar").focused(true)), 5000));
            device.pressDPadCenter();
            await(() -> state(controller) != PlaybackState.STATE_PLAYING, 5000);
            device.pressDPadRight();
            assertTrue(device.wait(Until.hasObject(By.text("Sobre a Rádio").focused(true)), 5000));
            device.pressDPadCenter();
            assertTrue("The dialog's return button must receive remote focus",
                    device.wait(Until.hasObject(By.text("Voltar à Rádio").focused(true)), 5000));
            screenshot("about");
            device.pressBack();
            assertTrue(device.wait(Until.hasObject(By.text("Sobre a Rádio")), 5000));
            device.pressBack();
            assertTrue("Back must leave the app", device.wait(Until.gone(By.pkg(context.getPackageName())), 10000));
        } finally {
            controller.getTransportControls().stop();
            onMain(() -> browser.get().disconnect());
        }
    }
    private static void open(Context context) {
        onMain(() -> context.startActivity(new Intent(context, TvActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP)));
    }
    private static int state(MediaController controller) {
        PlaybackState state = controller.getPlaybackState();
        return state == null ? PlaybackState.STATE_NONE : state.getState();
    }
    private static void await(BooleanSupplier check, long timeout) throws Exception {
        long end = System.currentTimeMillis() + timeout;
        while (System.currentTimeMillis() < end) {
            if (check.getAsBoolean()) return;
            Thread.sleep(200);
        }
        fail("Expected TV playback state was not reached");
    }
    private static void onMain(Runnable action) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(action);
    }
    private static void screenshot(String state) throws Exception {
        Bitmap image = InstrumentationRegistry.getInstrumentation().getUiAutomation().takeScreenshot();
        assertNotNull(image);
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        File directory = new File(context.getFilesDir(), "tv-captures");
        assertTrue(directory.isDirectory() || directory.mkdirs());
        try (FileOutputStream output = new FileOutputStream(new File(directory, state + ".png"))) {
            assertTrue(image.compress(Bitmap.CompressFormat.PNG, 100, output));
        } finally { image.recycle(); }
    }
}
