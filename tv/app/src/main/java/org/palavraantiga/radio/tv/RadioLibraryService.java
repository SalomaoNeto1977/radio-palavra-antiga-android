package org.palavraantiga.radio.tv;

import android.net.Uri;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.Nullable;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.ForwardingPlayer;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MediaMetadata;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.session.LibraryResult;
import androidx.media3.session.MediaLibraryService;
import androidx.media3.session.MediaSession;
import androidx.media3.session.SessionError;
import com.google.common.collect.ImmutableList;
import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

/**
 * Native TV playback service. Media3 owns the foreground notification and audio focus.
 * Connecting the TV screen never starts audio without an explicit play action.
 */
@UnstableApi
public final class RadioLibraryService extends MediaLibraryService {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final RetryPolicy retry = new RetryPolicy();
    private final ScheduledExecutorService network = Executors.newSingleThreadScheduledExecutor();
    private ExoPlayer engine;
    private MediaLibrarySession session;
    private ScheduledFuture<?> polling;
    private volatile boolean destroyed;
    private int pollGeneration;
    private Uri currentArtwork;
    private Uri cachedArtwork;
    private String artworkUrl = "";
    private long artworkFetchedAt;
    private final Runnable reconnect = () -> {
        if (!destroyed && retry.requested() && engine.getPlayWhenReady()) engine.prepare();
    };

    @Override public void onCreate() {
        super.onCreate();
        currentArtwork = resourceArtwork("station_artwork");
        cachedArtwork = currentArtwork;
        DefaultHttpDataSource.Factory http = new DefaultHttpDataSource.Factory()
                .setUserAgent("RadioPalavraAntiga-TV/1.3.0")
                .setConnectTimeoutMs(10000).setReadTimeoutMs(20000)
                .setAllowCrossProtocolRedirects(false);
        engine = new ExoPlayer.Builder(this)
                .setMediaSourceFactory(new DefaultMediaSourceFactory(http))
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
                .setHandleAudioBecomingNoisy(true)
                .build();
        engine.setMediaItem(station(null));
        engine.addListener(new Player.Listener() {
            @Override public void onPlaybackStateChanged(int state) {
                if (state == Player.STATE_READY) {
                    retry.connected();
                    main.removeCallbacks(reconnect);
                }
            }
            @Override public void onPlayWhenReadyChanged(boolean ready, int reason) {
                // A permanent focus loss must never be undone by a network retry.
                if (!ready) {
                    main.removeCallbacks(reconnect);
                    stopPolling();
                } else if (retry.requested()) startPolling();
            }
            @Override public void onPlayerError(PlaybackException error) {
                main.removeCallbacks(reconnect);
                if (retry.requested() && engine.getPlayWhenReady()) {
                    main.postDelayed(reconnect, retry.nextDelay());
                }
            }
        });
        Player controls = new ForwardingPlayer(engine) {
            @Override public void play() {
                requestPlay();
                super.play();
            }
            @Override public void setPlayWhenReady(boolean ready) {
                if (ready) requestPlay(); else requestPause();
                super.setPlayWhenReady(ready);
            }
            @Override public void pause() { requestPause(); super.pause(); }
            @Override public void stop() { requestPause(); super.stop(); }
            @Override public Commands getAvailableCommands() {
                return super.getAvailableCommands().buildUpon().removeAll(
                        COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM, COMMAND_SEEK_TO_DEFAULT_POSITION,
                        COMMAND_SEEK_TO_NEXT, COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                        COMMAND_SEEK_TO_PREVIOUS, COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                        COMMAND_SEEK_BACK, COMMAND_SEEK_FORWARD,
                        COMMAND_SET_REPEAT_MODE, COMMAND_SET_SHUFFLE_MODE,
                        COMMAND_CHANGE_MEDIA_ITEMS).build();
            }
            @Override public boolean isCommandAvailable(int command) {
                return getAvailableCommands().contains(command);
            }
        };
        PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, TvActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        session = new MediaLibrarySession.Builder(this, controls, new LibraryCallback())
                .setSessionActivity(open).build();
    }

    private void requestPlay() {
        retry.play();
        main.removeCallbacks(reconnect);
        if (engine.getPlaybackState() == Player.STATE_IDLE) engine.prepare();
        startPolling();
    }

    private void requestPause() {
        retry.pause();
        main.removeCallbacks(reconnect);
        stopPolling();
    }

    @Override @Nullable public MediaLibrarySession onGetSession(MediaSession.ControllerInfo controller) {
        return session;
    }

    private MediaItem root() {
        return new MediaItem.Builder().setMediaId(RadioCatalog.ROOT)
                .setMediaMetadata(new MediaMetadata.Builder().setTitle(RadioCatalog.NAME)
                        .setIsBrowsable(true).setIsPlayable(false)
                        .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_RADIO_STATIONS).build()).build();
    }

    private MediaItem station(@Nullable StationMetadata metadata) {
        MediaMetadata.Builder description = new MediaMetadata.Builder()
                .setTitle(metadata == null ? RadioCatalog.NAME : metadata.title)
                .setArtist(metadata == null ? "Em direto" : metadata.artist)
                .setDisplayTitle(metadata == null ? RadioCatalog.NAME : metadata.title)
                .setIsBrowsable(false).setIsPlayable(true)
                .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION);
        description.setArtworkUri(metadata == null ? resourceArtwork("station_artwork") : currentArtwork);
        return new MediaItem.Builder().setMediaId(RadioCatalog.LIVE)
                .setUri(RadioCatalog.STREAM).setMediaMetadata(description.build()).build();
    }

    private MediaItem liveCategory() {
        return new MediaItem.Builder().setMediaId(RadioCatalog.LIVE_CATEGORY)
                .setMediaMetadata(new MediaMetadata.Builder()
                        .setTitle(getString(R.string.live))
                        .setIsBrowsable(true).setIsPlayable(false)
                        .setArtworkUri(resourceArtwork("ic_live"))
                        .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_RADIO_STATIONS).build()).build();
    }

    private Uri resourceArtwork(String name) {
        return Uri.parse("android.resource://" + getPackageName() + "/drawable/" + name);
    }

    final class LibraryCallback implements MediaLibrarySession.Callback {
        @Override public ListenableFuture<LibraryResult<MediaItem>> onGetLibraryRoot(
                MediaLibrarySession s, MediaSession.ControllerInfo b, @Nullable LibraryParams p) {
            return Futures.immediateFuture(LibraryResult.ofItem(root(), p));
        }
        @Override public ListenableFuture<LibraryResult<MediaItem>> onGetItem(
                MediaLibrarySession s, MediaSession.ControllerInfo b, String id) {
            if (RadioCatalog.ROOT.equals(id)) return Futures.immediateFuture(LibraryResult.ofItem(root(), null));
            if (RadioCatalog.LIVE_CATEGORY.equals(id)) return Futures.immediateFuture(LibraryResult.ofItem(liveCategory(), null));
            if (RadioCatalog.LIVE.equals(id)) return Futures.immediateFuture(LibraryResult.ofItem(station(null), null));
            return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_BAD_VALUE));
        }
        @Override public ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> onGetChildren(
                MediaLibrarySession s, MediaSession.ControllerInfo b, String parent,
                int page, int pageSize, @Nullable LibraryParams p) {
            if ((!RadioCatalog.ROOT.equals(parent) && !RadioCatalog.LIVE_CATEGORY.equals(parent))
                    || page < 0 || pageSize < 1) {
                return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_BAD_VALUE));
            }
            MediaItem item = RadioCatalog.ROOT.equals(parent) ? liveCategory() : station(null);
            return Futures.immediateFuture(LibraryResult.ofItemList(
                    page == 0 ? ImmutableList.of(item) : ImmutableList.of(), p));
        }
        @Override public ListenableFuture<List<MediaItem>> onAddMediaItems(
                MediaSession s, MediaSession.ControllerInfo c, List<MediaItem> items) {
            // A controller can select the station or search for it, never supply an arbitrary stream.
            for (MediaItem item : items) {
                String query = item.requestMetadata.searchQuery;
                if (!RadioCatalog.LIVE.equals(item.mediaId)
                        && !(query != null && RadioCatalog.matches(query))) {
                    return Futures.immediateFailedFuture(new IllegalArgumentException("Estação desconhecida"));
                }
            }
            return Futures.immediateFuture(items.isEmpty() ? ImmutableList.of() : ImmutableList.of(station(null)));
        }
        @Override public ListenableFuture<MediaSession.MediaItemsWithStartPosition> onPlaybackResumption(
                MediaSession s, MediaSession.ControllerInfo c, boolean isForPlayback) {
            return Futures.immediateFuture(new MediaSession.MediaItemsWithStartPosition(
                    ImmutableList.of(station(null)), 0, C.TIME_UNSET));
        }
        @Override public ListenableFuture<LibraryResult<Void>> onSearch(
                MediaLibrarySession s, MediaSession.ControllerInfo b, String query, @Nullable LibraryParams p) {
            s.notifySearchResultChanged(b, query, RadioCatalog.matches(query) ? 1 : 0, p);
            return Futures.immediateFuture(LibraryResult.ofVoid(p));
        }
        @Override public ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> onGetSearchResult(
                MediaLibrarySession s, MediaSession.ControllerInfo b, String query,
                int page, int pageSize, @Nullable LibraryParams p) {
            if (page < 0 || pageSize < 1) return Futures.immediateFuture(LibraryResult.ofError(SessionError.ERROR_BAD_VALUE));
            return Futures.immediateFuture(LibraryResult.ofItemList(
                    page == 0 && RadioCatalog.matches(query) ? ImmutableList.of(station(null)) : ImmutableList.of(), p));
        }
    }

    private void startPolling() {
        if (polling != null && !polling.isCancelled()) return;
        final int generation = ++pollGeneration;
        polling = network.scheduleWithFixedDelay(() -> {
            try {
                StationMetadata value = StationMetadata.parse(new String(
                        download(RadioCatalog.NOW_PLAYING, 512 * 1024), StandardCharsets.UTF_8));
                // Publish text promptly; a slow image request must not hold the title back.
                main.post(() -> applyMetadata(value, null, generation));
                Uri image = cachedArtwork;
                if (value.artwork.isEmpty()) {
                    image = resourceArtwork("station_artwork");
                    artworkUrl = "";
                } else if (!value.artwork.equals(artworkUrl)
                        || System.currentTimeMillis() - artworkFetchedAt > 60000) {
                    try {
                        byte[] candidate = download(value.artwork, 2 * 1024 * 1024);
                        if (candidate.length > 0) {
                            image = ArtworkProvider.publish(this, candidate);
                            cachedArtwork = image;
                            artworkUrl = value.artwork;
                            artworkFetchedAt = System.currentTimeMillis();
                        }
                    } catch (Exception ignored) { /* Keep the last valid image. */ }
                }
                final Uri artwork = image;
                main.post(() -> applyMetadata(value, artwork, generation));
            } catch (Exception ignored) { /* A metadata outage must not interrupt audio. */ }
        }, 0, 15, TimeUnit.SECONDS);
    }

    private void applyMetadata(StationMetadata value, @Nullable Uri artwork, int generation) {
        if (destroyed || generation != pollGeneration || !retry.requested()
                || engine.getMediaItemCount() != 1) return;
        if (artwork != null) currentArtwork = artwork;
        // Same playback URI: updating title/artwork does not reconnect the stream.
        engine.replaceMediaItem(0, station(value));
    }

    private void stopPolling() {
        ++pollGeneration;
        if (polling != null) polling.cancel(true);
        polling = null;
    }

    private byte[] download(String address, int limit) throws Exception {
        // Validate every redirect, as image endpoints can redirect too.
        for (int redirects = 0; redirects <= 3; redirects++) {
            if (!RadioCatalog.allowedArtwork(address)) throw new SecurityException("Endereço não autorizado");
            HttpURLConnection connection = (HttpURLConnection) new URL(address).openConnection();
            connection.setConnectTimeout(8000);
            connection.setReadTimeout(8000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("User-Agent", "RadioPalavraAntiga-TV/1.3.0");
            try {
                int status = connection.getResponseCode();
                if (status >= 300 && status < 400) {
                    String location = connection.getHeaderField("Location");
                    if (location == null) throw new IllegalStateException("Redirecionamento sem destino");
                    address = new URL(new URL(address), location).toString();
                    continue;
                }
                if (status != 200) throw new IllegalStateException("HTTP " + status);
                try (InputStream input = connection.getInputStream()) { return readBounded(input, limit); }
            } finally { connection.disconnect(); }
        }
        throw new IllegalStateException("Demasiados redirecionamentos");
    }

    private static byte[] readBounded(InputStream input, int limit) throws Exception {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer)) != -1) {
            if (output.size() + count > limit) throw new IllegalStateException("Resposta demasiado grande");
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    @Override public void onDestroy() {
        destroyed = true;
        requestPause();
        main.removeCallbacksAndMessages(null);
        network.shutdownNow();
        if (session != null) session.release();
        if (engine != null) engine.release();
        super.onDestroy();
    }
}
