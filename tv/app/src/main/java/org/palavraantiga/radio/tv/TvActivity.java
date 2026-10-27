package org.palavraantiga.radio.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ComponentName;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.session.MediaController;
import androidx.media3.session.SessionToken;
import com.google.common.util.concurrent.ListenableFuture;
import java.io.InputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** A complete D-pad interface; playback lives in the service, independently of this screen. */
@UnstableApi
public final class TvActivity extends Activity {
    private static final int INK = Color.rgb(12, 23, 38);
    private static final int GOLD = Color.rgb(232, 190, 115);
    private static final int MUTED = Color.rgb(179, 191, 207);
    private ListenableFuture<MediaController> connection;
    private MediaController controller;
    private TextView status;
    private TextView title;
    private TextView artist;
    private Button play;
    private ImageView artwork;
    private Uri visibleArtwork;
    private int artworkGeneration;
    private final ExecutorService images = Executors.newSingleThreadExecutor();
    private final Player.Listener listener = new Player.Listener() {
        @Override public void onEvents(Player player, Player.Events events) { render(); }
    };

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        // Audio-only apps must allow Ambient Mode; deliberately no KEEP_SCREEN_ON or wake lock.
        setContentView(content());
        connection = new MediaController.Builder(this,
                new SessionToken(this, new ComponentName(this, RadioLibraryService.class))).buildAsync();
        connection.addListener(() -> {
            if (isFinishing() || isDestroyed()) return;
            try {
                controller = connection.get();
                controller.addListener(listener);
                play.setEnabled(true);
                play.requestFocus();
                render();
            } catch (Exception error) {
                status.setText("Não foi possível abrir o leitor. Volta a abrir a Rádio.");
            }
        }, this::runOnUiThread);
    }

    private View content() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setPadding(dp(48), dp(30), dp(48), dp(26));
        root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[] {INK, Color.rgb(19, 36, 53), Color.rgb(11, 25, 37)}));
        TextView top = text("PALAVRA ANTIGA  /  RÁDIO CRISTÃ PORTUGUESA", 14, GOLD);
        top.setLetterSpacing(.12f);
        root.addView(top);

        LinearLayout hero = new LinearLayout(this);
        hero.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams heroParams = new LinearLayout.LayoutParams(-1, 0, 1);
        heroParams.setMargins(0, dp(18), 0, dp(12));
        root.addView(hero, heroParams);
        artwork = new ImageView(this);
        artwork.setImageResource(R.drawable.station_artwork);
        artwork.setScaleType(ImageView.ScaleType.FIT_CENTER);
        artwork.setContentDescription("Capa da emissão");
        artwork.setBackground(round(Color.rgb(25, 39, 52), dp(18), 1, Color.rgb(64, 77, 87)));
        artwork.setClipToOutline(true);
        int artSize = Math.min(dp(254), getResources().getDisplayMetrics().heightPixels - dp(218));
        hero.addView(artwork, new LinearLayout.LayoutParams(artSize, artSize));
        LinearLayout details = new LinearLayout(this);
        details.setOrientation(LinearLayout.VERTICAL);
        details.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams detailsParams = new LinearLayout.LayoutParams(0, -2, 1);
        detailsParams.setMargins(dp(34), 0, 0, 0);
        hero.addView(details, detailsParams);
        details.addView(text("A TUA RÁDIO, SEMPRE CONTIGO", 12, GOLD));
        TextView brand = text("Palavra Antiga", 36, Color.WHITE);
        brand.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        details.addView(brand);
        TextView slogan = text("Passam-se as gerações,\nmas a Sua Palavra permanece.", 17, MUTED);
        LinearLayout.LayoutParams sloganParams = new LinearLayout.LayoutParams(-1, -2);
        sloganParams.setMargins(0, dp(8), 0, dp(18));
        details.addView(slogan, sloganParams);
        status = text("A preparar o leitor…", 13, GOLD);
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        details.addView(status);
        title = text(RadioCatalog.NAME, 21, Color.WHITE);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        details.addView(title);
        artist = text("Emissão em direto", 16, MUTED);
        artist.setMaxLines(1);
        artist.setEllipsize(android.text.TextUtils.TruncateAt.END);
        details.addView(artist);

        LinearLayout controls = new LinearLayout(this);
        controls.setGravity(Gravity.CENTER_VERTICAL);
        root.addView(controls);
        play = button("Ouvir em direto", "tv_play");
        play.setEnabled(false);
        play.setOnClickListener(v -> toggle());
        controls.addView(play, new LinearLayout.LayoutParams(dp(224), dp(54)));
        Button stop = button("Parar", "tv_stop");
        stop.setOnClickListener(v -> {
            if (controller != null) { controller.pause(); controller.stop(); render(); }
        });
        LinearLayout.LayoutParams stopParams = new LinearLayout.LayoutParams(dp(116), dp(54));
        stopParams.setMargins(dp(14), 0, 0, 0);
        controls.addView(stop, stopParams);
        Button about = button("Sobre a Rádio", "tv_about");
        about.setOnClickListener(v -> showAbout());
        LinearLayout.LayoutParams aboutParams = new LinearLayout.LayoutParams(dp(192), dp(54));
        aboutParams.setMargins(dp(14), 0, 0, 0);
        controls.addView(about, aboutParams);
        play.setNextFocusRightId(stop.getId());
        stop.setNextFocusLeftId(play.getId());
        stop.setNextFocusRightId(about.getId());
        about.setNextFocusLeftId(stop.getId());
        TextView footer = text("Usa as setas do comando · OK para escolher · Voltar para sair", 12, MUTED);
        LinearLayout.LayoutParams footerParams = new LinearLayout.LayoutParams(-1, -2);
        footerParams.setMargins(0, dp(14), 0, 0);
        root.addView(footer, footerParams);
        play.post(play::requestFocus);
        return root;
    }

    private void showAbout() {
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("Rádio Palavra Antiga")
                .setMessage("Rádio Cristã Portuguesa\n\nMúsica cristã, reflexão e ensino bíblico, "
                        + "para toda a família.\n\nOuvir é gratuito e não exige conta. "
                        + "É necessária uma ligação à Internet.\n\npalavraantiga.org\nradio@palavraantiga.org")
                .setPositiveButton("Voltar à Rádio", (d, which) -> play.requestFocus()).create();
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).requestFocus());
        dialog.show();
    }

    private void toggle() {
        if (controller == null) return;
        if (controller.getPlayWhenReady()) controller.pause();
        else {
            if (controller.getPlaybackState() == Player.STATE_IDLE) controller.prepare();
            controller.play();
        }
        render();
    }

    private void render() {
        if (controller == null) return;
        boolean requested = controller.getPlayWhenReady();
        play.setText(requested ? "Pausar" : "Ouvir em direto");
        play.setContentDescription(play.getText());
        if (controller.getPlayerError() != null) {
            status.setText(requested ? "A tentar restabelecer a ligação…" : "Ligação interrompida · tenta novamente");
        } else if (controller.isPlaying()) status.setText("● EM DIRETO");
        else if (requested) status.setText("A ligar à emissão…");
        else status.setText("Pronto para ouvir");
        MediaMetadata metadata = controller.getMediaMetadata();
        title.setText(metadata.title == null ? RadioCatalog.NAME : metadata.title);
        artist.setText(metadata.artist == null ? "Emissão em direto" : metadata.artist);
        Uri uri = metadata.artworkUri;
        if (uri != null && !uri.equals(visibleArtwork)) loadArtwork(uri);
    }

    private void loadArtwork(Uri uri) {
        if (!"android.resource".equals(uri.getScheme()) && !"content".equals(uri.getScheme())) return;
        visibleArtwork = uri;
        int generation = ++artworkGeneration;
        images.execute(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri)) {
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inSampleSize = 2;
                Bitmap image = BitmapFactory.decodeStream(input, null, options);
                runOnUiThread(() -> {
                    if (!isDestroyed() && generation == artworkGeneration && image != null) artwork.setImageBitmap(image);
                });
            } catch (Exception ignored) { /* The last valid cover remains visible. */ }
        });
    }

    @Override public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (controller != null) {
            if (keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) { if (event.getRepeatCount() == 0) toggle(); return true; }
            if (keyCode == KeyEvent.KEYCODE_MEDIA_PLAY) { controller.prepare(); controller.play(); return true; }
            if (keyCode == KeyEvent.KEYCODE_MEDIA_PAUSE) { controller.pause(); return true; }
            if (keyCode == KeyEvent.KEYCODE_MEDIA_STOP) { controller.pause(); controller.stop(); return true; }
        }
        return super.onKeyDown(keyCode, event);
    }

    private Button button(String label, String tag) {
        Button button = new Button(this);
        button.setId(View.generateViewId());
        button.setTag(tag);
        button.setText(label);
        button.setAllCaps(false);
        button.setTextSize(16);
        button.setTypeface(Typeface.DEFAULT_BOLD);
        button.setTextColor(Color.WHITE);
        button.setPadding(dp(10), 0, dp(10), 0);
        button.setFocusable(true);
        button.setFocusableInTouchMode(true);
        button.setBackground(round(Color.rgb(33, 50, 66), dp(10), 1, Color.rgb(78, 92, 107)));
        button.setOnFocusChangeListener((v, focused) -> {
            button.setTextColor(focused ? INK : Color.WHITE);
            button.setBackground(round(focused ? GOLD : Color.rgb(33, 50, 66), dp(10),
                    focused ? 3 : 1, focused ? Color.WHITE : Color.rgb(78, 92, 107)));
            button.setScaleX(focused ? 1.025f : 1f);
            button.setScaleY(focused ? 1.025f : 1f);
        });
        return button;
    }

    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(color);
        view.setIncludeFontPadding(false);
        return view;
    }
    private GradientDrawable round(int color, int radius, int stroke, int line) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color); drawable.setCornerRadius(radius); drawable.setStroke(dp(stroke), line);
        return drawable;
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    @Override protected void onDestroy() {
        ++artworkGeneration;
        images.shutdownNow();
        if (controller != null) controller.removeListener(listener);
        if (connection != null) MediaController.releaseFuture(connection);
        super.onDestroy();
    }
}
