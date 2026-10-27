package org.palavraantiga.radio.automotive;

import static org.junit.Assert.*;
import android.content.Context;
import android.content.pm.ProviderInfo;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public class ArtworkProviderTest {
    private Context context;
    private ArtworkProvider provider;
    @Before public void attach() {
        context = RuntimeEnvironment.getApplication();
        provider = new ArtworkProvider();
        ProviderInfo info = new ProviderInfo();
        info.authority = context.getPackageName() + ".artwork";
        provider.attachInfo(context, info);
    }
    @Test public void imageIsAvailableThroughALocalReadOnlyUri() throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try (InputStream input = context.getResources().openRawResource(R.raw.station_logo)) {
            byte[] buffer = new byte[8192]; int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
        }
        byte[] image = output.toByteArray();
        Uri uri = ArtworkProvider.publish(context, image);
        assertEquals("content", uri.getScheme());
        assertEquals("image/png", provider.getType(uri));
        try (ParcelFileDescriptor fd = provider.openFile(uri, "r");
                FileInputStream input = new FileInputStream(fd.getFileDescriptor())) {
            assertEquals(0x89, input.read());
        }
        assertThrows(FileNotFoundException.class, () -> provider.openFile(uri, "rw"));
    }
    @Test public void arbitraryPathsCannotExposePrivateFiles() {
        Uri bad = Uri.parse("content://" + context.getPackageName() + ".artwork/art/../../private");
        assertThrows(FileNotFoundException.class, () -> provider.openFile(bad, "r"));
    }
    @Test public void invalidImagesAreNotPublished() {
        assertThrows(IllegalArgumentException.class, () -> ArtworkProvider.publish(context, new byte[]{1, 2, 3}));
    }
}
