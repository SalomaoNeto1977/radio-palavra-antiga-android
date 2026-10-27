package org.palavraantiga.radio.tv;

import static org.junit.Assert.*;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public class TvActivityTest {
    @Test public void televisionLauncherIsDeclaredAndAmbientModeIsAllowed() throws Exception {
        try (var lifecycle = Robolectric.buildActivity(TvActivity.class).create().start().resume()) {
            TvActivity screen = lifecycle.get();
            assertEquals(0, screen.getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            Intent launch = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                    .setPackage(screen.getPackageName());
            assertNotNull(screen.getPackageManager().resolveActivity(launch, 0));
        }
    }
    @Test public void everyControlHasAnExplicitHorizontalRemoteNavigationPath() {
        try (var lifecycle = Robolectric.buildActivity(TvActivity.class).create().start().resume()) {
            View root = lifecycle.get().getWindow().getDecorView();
            Button play = root.findViewWithTag("tv_play");
            Button stop = root.findViewWithTag("tv_stop");
            Button about = root.findViewWithTag("tv_about");
            assertTrue(play.isFocusable()); assertTrue(stop.isFocusable()); assertTrue(about.isFocusable());
            assertEquals(stop.getId(), play.getNextFocusRightId());
            assertEquals(play.getId(), stop.getNextFocusLeftId());
            assertEquals(about.getId(), stop.getNextFocusRightId());
            assertEquals(stop.getId(), about.getNextFocusLeftId());
        }
    }
}
