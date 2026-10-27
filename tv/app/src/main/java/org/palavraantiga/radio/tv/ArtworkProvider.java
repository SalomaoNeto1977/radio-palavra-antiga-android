package org.palavraantiga.radio.tv;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.Locale;

/** Exposes only public radio artwork, read-only; no caller-controlled paths or URLs. */
public final class ArtworkProvider extends ContentProvider {
    static synchronized Uri publish(Context context, byte[] image) throws Exception {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(image, 0, image.length, bounds);
        if (image.length > 2 * 1024 * 1024 || bounds.outWidth < 1 || bounds.outHeight < 1
                || bounds.outWidth > 4096 || bounds.outHeight > 4096) {
            throw new IllegalArgumentException("Imagem inválida");
        }
        StringBuilder name = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(image)) {
            name.append(String.format(Locale.ROOT, "%02x", value & 0xff));
        }
        File directory = new File(context.getCacheDir(), "public-radio-artwork");
        if (!directory.isDirectory() && !directory.mkdirs()) throw new FileNotFoundException();
        File file = new File(directory, name + ".img");
        if (!file.exists()) {
            AtomicFile atomic = new AtomicFile(file);
            FileOutputStream output = null;
            try {
                output = atomic.startWrite();
                output.write(image);
                atomic.finishWrite(output);
            } catch (Exception error) {
                if (output != null) atomic.failWrite(output);
                throw error;
            }
        }
        File[] files = directory.listFiles((parent, child) -> child.matches("[0-9a-f]{64}\\.img"));
        if (files != null && files.length > 20) {
            Arrays.sort(files, (left, right) -> Long.compare(right.lastModified(), left.lastModified()));
            for (int i = 20; i < files.length; i++) if (!files[i].equals(file)) files[i].delete();
        }
        return new Uri.Builder().scheme("content").authority(context.getPackageName() + ".artwork")
                .appendPath("art").appendPath(name.toString()).build();
    }
    @Override public boolean onCreate() { return true; }
    private File resolve(Uri uri) throws FileNotFoundException {
        if (getContext() == null || !("content".equals(uri.getScheme()))
                || !(getContext().getPackageName() + ".artwork").equals(uri.getAuthority())
                || uri.getPathSegments().size() != 2
                || !"art".equals(uri.getPathSegments().get(0))
                || !uri.getPathSegments().get(1).matches("[0-9a-f]{64}")) {
            throw new FileNotFoundException("Imagem desconhecida");
        }
        return new File(new File(getContext().getCacheDir(), "public-radio-artwork"),
                uri.getPathSegments().get(1) + ".img");
    }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Apenas leitura");
        return ParcelFileDescriptor.open(resolve(uri), ParcelFileDescriptor.MODE_READ_ONLY);
    }
    @Override public String getType(Uri uri) {
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(resolve(uri).getPath(), bounds);
            return bounds.outMimeType;
        } catch (FileNotFoundException ignored) { return null; }
    }
    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] arguments, String order) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] arguments) {
        throw new UnsupportedOperationException();
    }
    @Override public int delete(Uri uri, String selection, String[] arguments) {
        throw new UnsupportedOperationException();
    }
}
