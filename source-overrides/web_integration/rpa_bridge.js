/*
 * Rádio Palavra Antiga — interface leve do leitor nativo Android.
 *
 * A página /app1 é apenas uma interface: nunca reproduz áudio nem decide
 * se a emissão está a tocar. Todos os estados vêm do serviço nativo.
 */
(function () {
  "use strict";

  // A instalação PWA nunca é prova de execução dentro da app Android.
  if (!window.RPA || typeof window.RPA.postMessage !== "function") return;
  if (window.__PA_WEB_PLAYER &&
      typeof window.__PA_WEB_PLAYER.dispose === "function") {
    window.__PA_WEB_PLAYER.dispose();
  }

  if (window.__RPA_BRIDGE_INSTALLED === true) {
    if (window.RPA && typeof window.RPA.postMessage === "function") {
      window.RPA.postMessage("GET_STATE");
    }
    return;
  }

  Object.defineProperty(window, "__RPA_BRIDGE_INSTALLED", {
    value: true,
    configurable: false,
    writable: false
  });

  var DEFAULT_ARTWORK = "https://palavraantiga.org/web/image/website/1/logo/512x512";
  var VALID_STATES = new Set([
    "STOPPED", "CONNECTING", "PLAYING", "PAUSED",
    "BUFFERING", "RECONNECTING", "ERROR"
  ]);
  var ACTIVE_STATES = new Set([
    "PLAYING", "CONNECTING", "BUFFERING", "RECONNECTING"
  ]);
  var STATE_CLASSES = [
    "rpa-stopped", "rpa-connecting", "rpa-playing", "rpa-error"
  ];

  var nativePlayerState = "SYNCING";
  var lastMetadata = {
    title: "Rádio Palavra Antiga",
    artist: "",
    album: "",
    artwork: DEFAULT_ARTWORK,
    error: null,
    mode: "live",
    positionMs: 0,
    durationMs: null,
    queueIndex: -1,
    queueLength: 0,
    canPrevious: false,
    canNext: false
  };
  var lastCommand = "";
  var lastCommandAt = 0;
  var commandPending = true;
  var pendingTimer = null;
  var runtimeRequestedActive = true;
  var runtimeActive = document.hidden !== true;

  try {
    window.open = function (url) {
      if (typeof url === "string" && url.length > 0) {
        window.location.assign(url);
      }
      return null;
    };
  } catch (_) {}

  function blockedAudioPlay() {
    return Promise.reject(new DOMException(
      "A reprodução é controlada pelo leitor nativo.",
      "NotAllowedError"
    ));
  }

  try {
    if (window.HTMLAudioElement && window.HTMLAudioElement.prototype) {
      Object.defineProperty(window.HTMLAudioElement.prototype, "play", {
        configurable: true,
        writable: true,
        value: blockedAudioPlay
      });
    }
  } catch (_) {}

  /*
   * Silencia antes de remover. Recarregar o elemento reabre a saída em algumas
   * WebViews e provocava uma batida curta ao entrar na aplicação.
   */
  function neutralizeLegacyAudio() {
    Array.prototype.slice.call(document.querySelectorAll("audio"))
      .forEach(function (audio) {
        try { audio.muted = true; } catch (_) {}
        try { audio.volume = 0; } catch (_) {}
        try { audio.preload = "none"; } catch (_) {}
        try { audio.removeAttribute("autoplay"); } catch (_) {}
        if (audio.paused === false) {
          try { audio.pause(); } catch (_) {}
        }
        try { audio.removeAttribute("src"); } catch (_) {}
        try {
          Array.prototype.slice.call(audio.querySelectorAll("source"))
            .forEach(function (source) {
              source.removeAttribute("src");
              source.remove();
            });
        } catch (_) {}
        try { audio.remove(); } catch (_) {}
      });
  }

  try {
    if ("mediaSession" in navigator) {
      ["play", "pause", "stop", "seekbackward", "seekforward",
       "previoustrack", "nexttrack", "seekto"].forEach(function (action) {
        try { navigator.mediaSession.setActionHandler(action, null); } catch (_) {}
      });
    }
  } catch (_) {}

  function allById(id) {
    return Array.prototype.slice.call(
      document.querySelectorAll('[id="' + id + '"]')
    );
  }

  function stateClass(state) {
    if (state === "PLAYING") return "rpa-playing";
    if (state === "SYNCING" || state === "CONNECTING" ||
        state === "BUFFERING" || state === "RECONNECTING") {
      return "rpa-connecting";
    }
    if (state === "ERROR") return "rpa-error";
    return "rpa-stopped";
  }

  function updateArtwork(url) {
    var artwork = typeof url === "string" && /^https:\/\//i.test(url)
      ? url
      : DEFAULT_ARTWORK;

    allById("np-capa").forEach(function (image) {
      if (image.getAttribute("src") !== artwork) {
        image.setAttribute("src", artwork);
      }
      image.setAttribute("alt", lastMetadata.title || "Capa da emissão");
    });
  }

  function updateMetadata(metadata) {
    if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
      metadata = {};
    }

    if (typeof metadata.title === "string") {
      // Preserva o título recebido do AzuraCast.
      lastMetadata.title = metadata.title.trim() || "Rádio Palavra Antiga";
    }
    if (typeof metadata.artist === "string") {
      lastMetadata.artist = metadata.artist.trim();
    }
    if (typeof metadata.album === "string") {
      lastMetadata.album = metadata.album.trim();
    }
    lastMetadata.mode = metadata.mode === "ondemand" ? "ondemand" : "live";
    lastMetadata.positionMs = Number.isFinite(metadata.positionMs)
      ? Math.max(0, metadata.positionMs) : 0;
    lastMetadata.durationMs = Number.isFinite(metadata.durationMs)
      ? Math.max(0, metadata.durationMs) : null;
    lastMetadata.queueIndex = Number.isFinite(metadata.queueIndex)
      ? metadata.queueIndex : -1;
    lastMetadata.queueLength = Number.isFinite(metadata.queueLength)
      ? metadata.queueLength : 0;
    lastMetadata.canPrevious = metadata.canPrevious === true;
    lastMetadata.canNext = metadata.canNext === true;

    if (typeof metadata.artwork === "string") {
      lastMetadata.artwork = /^https:\/\//i.test(metadata.artwork)
        ? metadata.artwork
        : DEFAULT_ARTWORK;
    }

    lastMetadata.error = typeof metadata.error === "string" &&
      metadata.error.trim() !== ""
        ? metadata.error.trim()
        : null;

    if (lastMetadata.mode === "live") {
      allById("np-titulo").forEach(function (title) {
        if (title.textContent !== lastMetadata.title) {
          title.textContent = lastMetadata.title;
        }
      });
      updateArtwork(lastMetadata.artwork);
      if (typeof window.CustomEvent === "function" &&
          typeof document.dispatchEvent === "function") {
        document.dispatchEvent(new window.CustomEvent("rpa:live-metadata", {
          detail: {title: lastMetadata.title, artist: lastMetadata.artist}
        }));
      }
    }
  }

  function ensureGlow(button) {
    var glow = button.querySelector(".rpa-btn-glow");
    if (!glow) {
      glow = document.createElement("span");
      glow.className = "rpa-btn-glow";
      glow.setAttribute("aria-hidden", "true");
      button.insertBefore(glow, button.firstChild);
    }
    return glow;
  }

  function updatePlayerDecorations(state) {
    var radioState = lastMetadata.mode === "ondemand" ? "STOPPED" : state;
    var cssState = stateClass(radioState);
    var syncing = radioState === "SYNCING";
    var active = ACTIVE_STATES.has(radioState);
    var label = active ? "Parar rádio" : "Tocar rádio";

    ["appPlayBtn", "playBtn"].forEach(function (id) {
      allById(id).forEach(function (button) {
        STATE_CLASSES.forEach(function (name) {
          button.classList.remove(name);
        });
        button.classList.remove("on", "loading");
        button.classList.add(cssState);
        button.title = label;
        button.setAttribute("aria-label", label);
        button.setAttribute("aria-busy", syncing ? "true" : "false");
        button.disabled = syncing || commandPending;
        ensureGlow(button);
      });
    });

    ["appBtnImg", "btnImg"].forEach(function (id) {
      allById(id).forEach(function (image) {
        image.classList.remove(
          "stopped", "connecting", "playing", "error",
          "rpa-stopped", "rpa-connecting", "rpa-playing", "rpa-error"
        );
        image.alt = label;
      });
    });

    var playing = radioState === "PLAYING" && runtimeActive;
    allById("vinylDisc").forEach(function (disc) {
      disc.classList.toggle("vinyl-spin", playing);
    });
    allById("tonearm").forEach(function (arm) {
      arm.classList.toggle("on", playing);
    });
    allById("needleShadow").forEach(function (shadow) {
      shadow.style.opacity = playing ? "1" : "0";
    });
  }

  function renderState(state, metadata) {
    nativePlayerState = state;
    commandPending = false;
    if (pendingTimer) {
      clearTimeout(pendingTimer);
      pendingTimer = null;
    }
    updateMetadata(metadata);
    updatePlayerDecorations(state);
    if (typeof window.__RPA_MUSIC_RENDER_STATE === "function") {
      window.__RPA_MUSIC_RENDER_STATE(state, lastMetadata);
    }
  }

  function postCommand(action) {
    if (!["PLAY", "STOP", "PAUSE", "TOGGLE", "GET_STATE", "RETRY",
          "MUSIC_RESUME", "NEXT_TRACK", "PREVIOUS_TRACK"]
        .includes(action)) {
      return false;
    }

    if (!window.RPA || typeof window.RPA.postMessage !== "function") {
      return false;
    }

    var now = Date.now();
    if (action !== "GET_STATE" && action === lastCommand &&
        now - lastCommandAt < 400) {
      return false;
    }

    lastCommand = action;
    lastCommandAt = now;
    window.RPA.postMessage(action);
    return true;
  }

  function onPlayerClick(event) {
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    if (commandPending) return;

    var action = lastMetadata.mode === "ondemand"
      ? "PLAY"
      : (ACTIVE_STATES.has(nativePlayerState) ? "STOP" : "PLAY");
    if (!postCommand(action)) return;

    commandPending = true;
    updatePlayerDecorations(action === "PLAY" ? "CONNECTING" : "STOPPED");
    pendingTimer = setTimeout(function () {
      commandPending = false;
      updatePlayerDecorations(nativePlayerState);
      postCommand("GET_STATE");
    }, 5000);
  }

  function bindButtons() {
    ["appPlayBtn", "playBtn"].forEach(function (id) {
      allById(id).forEach(function (oldButton) {
        if (oldButton.getAttribute("data-rpa-native-button") === "true") {
          ensureGlow(oldButton);
          return;
        }

        var button = oldButton.cloneNode(true);
        button.removeAttribute("onclick");
        button.setAttribute("data-rpa-native-button", "true");
        oldButton.replaceWith(button);
        ensureGlow(button);
        button.addEventListener("click", onPlayerClick, true);
      });
    });
  }

  function installStyles() {
    if (document.getElementById("rpa-native-styles")) return;

    var style = document.createElement("style");
    style.id = "rpa-native-styles";
    style.textContent = [
      "button[data-rpa-native-button='true']{position:relative!important;",
      "isolation:isolate;overflow:visible!important;}",
      "button[data-rpa-native-button='true'] img{position:relative;z-index:1;",
      "filter:none!important;animation:none!important;}",
      "button[data-rpa-native-button='true'] .rpa-btn-glow{position:absolute;",
      "inset:12%;z-index:-1;border-radius:50%;pointer-events:none;",
      "opacity:.96;transform:scale(1);will-change:opacity,transform;",
      "background:var(--rpa-glow-soft);box-shadow:0 0 12px 5px ",
      "var(--rpa-glow),0 0 27px 10px var(--rpa-glow-soft);}",
      "button.rpa-stopped{--rpa-glow:rgba(31,118,255,.96);",
      "--rpa-glow-soft:rgba(31,118,255,.43);}",
      "button.rpa-stopped .rpa-btn-glow{animation:none!important;}",
      "button.rpa-connecting{--rpa-glow:rgba(255,197,34,.98);",
      "--rpa-glow-soft:rgba(255,197,34,.48);}",
      "button.rpa-connecting .rpa-btn-glow{animation:rpa-glow-pulse ",
      ".46s ease-in-out infinite alternate;}",
      "button.rpa-playing{--rpa-glow:rgba(234,46,52,.97);",
      "--rpa-glow-soft:rgba(234,46,52,.45);}",
      "button.rpa-playing .rpa-btn-glow{animation:rpa-glow-pulse ",
      "1.8s ease-in-out infinite alternate;}",
      "button.rpa-error{--rpa-glow:rgba(242,40,48,1);",
      "--rpa-glow-soft:rgba(242,40,48,.55);}",
      "button.rpa-error .rpa-btn-glow{animation:rpa-glow-pulse ",
      ".22s ease-in-out infinite alternate;}",
      "@keyframes rpa-glow-pulse{from{opacity:.36;transform:scale(.88);}",
      "to{opacity:1;transform:scale(1.08);}}",
      ".rpa-native-artist,.rpa-native-status,#np-artista,#np-artist,",
      "#np-programa{display:none!important;}",
      "button[data-rpa-native-button='true'][disabled]{cursor:wait!important;}",
      ".rpa-runtime-paused *, .rpa-runtime-paused *::before,",
      ".rpa-runtime-paused *::after{animation-play-state:paused!important;",
      "transition:none!important;}",
      "@media(prefers-reduced-motion:reduce){",
      "button[data-rpa-native-button='true'] .rpa-btn-glow{",
      "animation:none!important;opacity:1!important;}}"
    ].join("");
    (document.head || document.documentElement).appendChild(style);
  }


  function installMusicArea() {
    if (document.getElementById("rpa-music-panel") ||
        typeof window.fetch !== "function") return;

    var API_URL = "https://radio.palavraantiga.org/api/station/palavraantiga/ondemand";
    var REQUESTS_URL = "https://radio.palavraantiga.org/api/station/palavraantiga/requests";
    var BASE_URL = "https://radio.palavraantiga.org";
    var STORAGE_KEY = "rpa.music.library.v1";
    var catalog = [];
    var catalogLoaded = false;
    var catalogLoading = false;
    var requestCatalogLoaded = false;
    var requestCatalogLoading = false;
    var requestSubmitting = false;
    var requestsBySongId = new Map();
    var requestedSongIds = new Set();
    var activeView = "official";
    var selectedTrackId = null;
    var selectedRequestTrack = null;
    var requestFeedbackTimer = null;
    var lastMusicState = "STOPPED";
    var clockStartedAt = Date.now();
    var progressTimer = null;
    var musicRuntimeActive = runtimeActive;
    var musicAccess = window.__RPA_MUSIC_ACCESS === true;

    function escapeHtml(value) {
      return String(value == null ? "" : value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
    }

    function safeLibrary() {
      var fallback = { favorites: [], playlists: {} };
      try {
        var raw = window.localStorage && window.localStorage.getItem(STORAGE_KEY);
        if (!raw) return fallback;
        var parsed = JSON.parse(raw);
        if (!parsed || typeof parsed !== "object") return fallback;
        if (!Array.isArray(parsed.favorites)) parsed.favorites = [];
        if (!parsed.playlists || typeof parsed.playlists !== "object") parsed.playlists = {};
        return parsed;
      } catch (_) {
        return fallback;
      }
    }

    var library = safeLibrary();

    function saveLibrary() {
      try {
        if (window.localStorage) {
          window.localStorage.setItem(STORAGE_KEY, JSON.stringify(library));
        }
      } catch (_) {}
      postJson({ action: "SYNC_LIBRARY", library: library });
    }

    function absoluteUrl(value) {
      try { return new URL(String(value || ""), BASE_URL).href; }
      catch (_) { return ""; }
    }

    function artUrl(value) {
      var candidate = "";
      if (typeof value === "string") candidate = value;
      if (value && typeof value === "object" && typeof value.url === "string") {
        candidate = value.url;
      }
      try {
        var parsed = new URL(candidate, BASE_URL);
        var allowed = [
          "radio.palavraantiga.org",
          "palavraantiga.org",
          "www.palavraantiga.org"
        ];
        return parsed.protocol === "https:" && allowed.includes(parsed.hostname)
          ? parsed.href : DEFAULT_ARTWORK;
      } catch (_) { return DEFAULT_ARTWORK; }
    }

    function normalizeOfficialPlaylists(payload) {
      var rows = Array.isArray(payload)
        ? payload
        : (payload && Array.isArray(payload.playlists) ? payload.playlists : []);
      var usedIds = new Set();
      return rows.map(function (row, index) {
        if (!row || typeof row !== "object") return null;
        var id = String(row.id == null ? "playlist-" + index : row.id).trim();
        var name = String(row.name || "").trim();
        if (!id || !name || usedIds.has(id) || !Array.isArray(row.track_ids)) {
          return null;
        }
        var trackIds = [];
        var usedTracks = new Set();
        row.track_ids.forEach(function (value) {
          var trackId = String(value || "").trim();
          if (trackId && !usedTracks.has(trackId)) {
            usedTracks.add(trackId);
            trackIds.push(trackId);
          }
        });
        if (!trackIds.length) return null;
        usedIds.add(id);
        return {
          id: id,
          name: name,
          description: String(row.description || "").trim(),
          trackIds: trackIds,
          isFallback: row.is_fallback === true
        };
      }).filter(Boolean);
    }

    var officialPlaylists = normalizeOfficialPlaylists(
      window.__RPA_OFFICIAL_PLAYLISTS
    );

    function normalizeTrack(row) {
      if (!row || typeof row !== "object") return null;
      var media = row.media && typeof row.media === "object" ? row.media : {};
      var id = String(row.track_id || media.id || "").trim();
      var url = absoluteUrl(row.download_url);
      if (!id || !/^https:\/\/radio\.palavraantiga\.org\//i.test(url)) return null;
      return {
        id: id,
        requestSongId: String(media.id || "").trim(),
        url: url,
        title: String(media.title || media.text || "Sem título").trim() || "Sem título",
        artist: String(media.artist || "Rádio Palavra Antiga").trim() || "Rádio Palavra Antiga",
        album: String(media.album || "").trim(),
        artwork: artUrl(media.art)
      };
    }

    function normalizeRequest(row) {
      if (!row || typeof row !== "object") return null;
      var song = row.song && typeof row.song === "object" ? row.song : {};
      var requestId = String(row.request_id || "").trim();
      var songId = String(song.id || "").trim();
      if (!/^[a-zA-Z0-9_-]{1,128}$/.test(requestId) || !songId) return null;
      try {
        var requestUrl = new URL(String(row.request_url || ""), BASE_URL);
        var expectedSuffix = "/request/" + encodeURIComponent(requestId);
        if (requestUrl.protocol !== "https:" ||
            requestUrl.hostname !== "radio.palavraantiga.org" ||
            requestUrl.search || requestUrl.hash ||
            !requestUrl.pathname.endsWith(expectedSuffix)) return null;
        return {
          requestId: requestId,
          requestUrl: requestUrl.href,
          songId: songId
        };
      } catch (_) { return null; }
    }

    function nativeTrack(track) {
      return {
        id: track.id,
        url: track.url,
        title: track.title,
        artist: track.artist,
        album: track.album || null,
        artwork: track.artwork || DEFAULT_ARTWORK
      };
    }

    function postJson(payload) {
      if (!window.RPA || typeof window.RPA.postMessage !== "function") return false;
      try {
        window.RPA.postMessage(JSON.stringify(payload));
        return true;
      } catch (_) { return false; }
    }

    postJson({ action: "SYNC_LIBRARY", library: library });

    var panel = document.createElement("section");
    panel.id = "rpa-music-panel";
    panel.setAttribute("aria-hidden", "true");
    panel.innerHTML = [
      "<div class='rpa-music-shell'>",
      "<header class='rpa-music-header'>",
      "<button type='button' id='rpa-music-close' aria-label='Fechar'>‹</button>",
      "<div><strong>Palavra Antiga</strong><span>Music</span></div>",
      "<button type='button' id='rpa-music-live'>● Ao vivo</button>",
      "</header>",
      "<div class='rpa-music-hero'><div class='rpa-music-mark'>♫</div>",
      "<div><h2>A tua música cristã</h2><p>Ouve agora ou pede uma música para a emissão.</p></div></div>",
      "<div id='rpa-access-banner' class='rpa-access-banner' hidden><div><b>🔒 Ouvir o catálogo é para apoiantes</b>",
      "<span>Podes continuar a pedir músicas gratuitamente.</span></div><button id='rpa-unlock-music' type='button'>Ver apoios</button></div>",
      "<div class='rpa-music-search'><span>⌕</span><input id='rpa-music-search' type='search' placeholder='Pesquisar playlist, música ou artista'></div>",
      "<nav class='rpa-music-tabs'>",
      "<button type='button' data-view='official' class='active'>Playlists da rádio</button>",
      "<button type='button' data-view='all'>Todas</button>",
      "<button type='button' data-view='favorites'>♥ Favoritos</button>",
      "<button type='button' data-view='personal'>As tuas playlists</button>",
      "</nav>",
      "<div id='rpa-playlist-bar' class='rpa-playlist-bar'></div>",
      "<div id='rpa-request-feedback' class='rpa-request-feedback' role='status' hidden></div>",
      "<main id='rpa-track-list' class='rpa-track-list'><div class='rpa-music-loading'>Abre esta área para carregar o catálogo…</div></main>",
      "<div id='rpa-music-mini' class='rpa-music-mini' hidden>",
      "<img id='rpa-mini-art' alt='Capa'><div class='rpa-mini-copy'><b id='rpa-mini-title'>Música</b><span id='rpa-mini-artist'></span>",
      "<input id='rpa-mini-progress' type='range' min='0' max='1000' value='0' aria-label='Posição da música'></div>",
      "<div class='rpa-mini-controls'><button id='rpa-mini-prev' type='button'>‹‹</button><button id='rpa-mini-play' type='button'>▶</button><button id='rpa-mini-next' type='button'>››</button></div>",
      "</div>",
      "</div>",
      "<div id='rpa-playlist-modal' class='rpa-playlist-modal' hidden><div><h3>Adicionar à playlist</h3><div id='rpa-playlist-options'></div>",
      "<label>Nova playlist<input id='rpa-new-playlist-name' maxlength='40' placeholder='Ex.: Louvor'></label>",
      "<div class='rpa-modal-actions'><button id='rpa-playlist-cancel' type='button'>Cancelar</button><button id='rpa-playlist-create' type='button'>Criar e adicionar</button></div></div></div>",
      "<div id='rpa-request-modal' class='rpa-playlist-modal' hidden><div><h3>Confirmar pedido</h3>",
      "<p id='rpa-request-copy' class='rpa-request-copy'></p><div class='rpa-modal-actions'>",
      "<button id='rpa-request-cancel' type='button'>Cancelar</button>",
      "<button id='rpa-request-confirm' type='button'>🎙 Pedir na rádio</button></div></div></div>",
      "</section>"
    ].join("");
    document.body.appendChild(panel);

    var style = document.createElement("style");
    style.id = "rpa-music-styles";
    style.textContent = [
      "#rpa-music-panel{position:fixed;inset:0;z-index:2147483001;background:#0b0f0d;color:#f4f7f5;font-family:system-ui,-apple-system,sans-serif;transform:translateY(105%);transition:transform .22s ease;overflow:hidden}",
      "#rpa-music-panel.open{transform:translateY(0)}.rpa-music-shell{height:100%;display:flex;flex-direction:column;padding-bottom:env(safe-area-inset-bottom)}",
      ".rpa-music-header{height:62px;display:flex;align-items:center;gap:12px;padding:0 14px;background:#101613;border-bottom:1px solid rgba(255,255,255,.08)}",
      ".rpa-music-header>div{flex:1;display:flex;gap:6px;align-items:baseline}.rpa-music-header strong{font-family:Georgia,serif;font-size:20px}.rpa-music-header span{font-size:14px;color:#e8ad66}",
      ".rpa-music-header button{border:0;background:transparent;color:#f4f7f5;font-weight:700}.rpa-music-header #rpa-music-close{font-size:34px;line-height:1}.rpa-music-header #rpa-music-live{background:#213c2d;border:1px solid #39694e;border-radius:999px;padding:7px 10px;color:#9be1b5}",
      ".rpa-music-hero{display:flex;align-items:center;gap:14px;margin:14px 14px 8px;padding:17px;border-radius:18px;background:linear-gradient(135deg,#315f43,#18261f 70%,#111713);box-shadow:0 10px 30px rgba(0,0,0,.22)}",
      ".rpa-music-mark{width:58px;height:58px;border-radius:15px;display:grid;place-items:center;background:#e8ad66;color:#17100a;font-size:30px;box-shadow:0 8px 24px rgba(232,173,102,.2)}.rpa-music-hero h2{font-family:Georgia,serif;margin:0 0 3px;font-size:22px}.rpa-music-hero p{margin:0;color:#c5d1ca;font-size:13px}",
      ".rpa-access-banner{display:flex;align-items:center;gap:10px;margin:2px 14px 10px;padding:11px 12px;border:1px solid #9a6733;border-radius:13px;background:#332416;color:#ffe4c2}.rpa-access-banner[hidden]{display:none}.rpa-access-banner>div{min-width:0;flex:1}.rpa-access-banner b,.rpa-access-banner span{display:block}.rpa-access-banner b{font-size:13px}.rpa-access-banner span{margin-top:3px;color:#d9c4aa;font-size:11px}.rpa-access-banner button{border:0;border-radius:999px;padding:8px 10px;background:#e8ad66;color:#17100a;font-weight:800;white-space:nowrap}",
      ".rpa-music-search{margin:6px 14px 10px;height:44px;border:1px solid #34443b;border-radius:13px;background:#f5f7f5;color:#172019;display:flex;align-items:center;padding:0 12px;gap:8px}.rpa-music-search input{border:0;outline:0;width:100%;font:14px system-ui;background:transparent;color:#172019}",
      ".rpa-music-tabs{display:flex;gap:8px;overflow:auto;padding:0 14px 9px}.rpa-music-tabs button,.rpa-playlist-bar button{white-space:nowrap;border:1px solid #34483c;background:#17201b;border-radius:999px;padding:8px 12px;color:#dce6df}.rpa-music-tabs button.active,.rpa-playlist-bar button.active{background:#e8ad66;color:#17100a;border-color:#e8ad66;font-weight:700}",
      ".rpa-playlist-bar{display:flex;gap:7px;overflow:auto;padding:0 14px 8px}.rpa-request-feedback{margin:0 14px 8px;padding:9px 11px;border:1px solid #39694e;border-radius:11px;background:#173222;color:#aee9c1;font-size:12px}.rpa-request-feedback.error{border-color:#80434a;background:#351b1e;color:#ffc2c7}.rpa-request-feedback[hidden]{display:none}.rpa-track-list{flex:1;overflow:auto;padding:2px 12px 110px}.rpa-music-loading,.rpa-music-empty{padding:34px 16px;text-align:center;color:#9eaca3}",
      ".rpa-official-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:13px;padding:4px 2px 16px}.rpa-official-card{min-width:0;border:0;border-radius:16px;padding:9px;background:#17201b;color:#f4f7f5;text-align:left;box-shadow:0 8px 24px rgba(0,0,0,.18)}.rpa-official-card img{display:block;width:100%;aspect-ratio:1;object-fit:cover;border-radius:12px;background:#27342d}.rpa-official-card b,.rpa-official-card span{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rpa-official-card b{font-size:14px;margin:9px 2px 3px}.rpa-official-card span{font-size:11px;color:#9eaca3;margin:0 2px 2px}.rpa-official-card .rpa-card-play{float:right;display:grid;place-items:center;width:34px;height:34px;margin:-44px 5px 0 0;border:0;border-radius:50%;background:#e8ad66;color:#17100a;font-size:15px;box-shadow:0 5px 16px rgba(0,0,0,.35)}.rpa-list-heading{padding:8px 5px 12px}.rpa-list-heading b,.rpa-list-heading span{display:block}.rpa-list-heading b{font-family:Georgia,serif;font-size:21px}.rpa-list-heading span{color:#9eaca3;font-size:12px;margin-top:3px}",
      ".rpa-track{display:grid;grid-template-columns:52px minmax(0,1fr) auto;gap:8px;align-items:center;padding:9px 3px;border-bottom:1px solid rgba(255,255,255,.07)}.rpa-track img{width:52px;height:52px;border-radius:8px;object-fit:cover;background:#243029}.rpa-track-copy{min-width:0}.rpa-track-copy b,.rpa-track-copy span{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.rpa-track-copy b{font-size:14px;color:#f4f7f5}.rpa-track-copy span{font-size:12px;color:#9eaca3;margin-top:3px}.rpa-track-actions{display:flex;align-items:center}.rpa-track-actions button{border:0;background:transparent;font-size:18px;padding:7px 6px;color:#c9d4cd}.rpa-track-actions button[data-play='1']{color:#e8ad66}.rpa-track-actions button[data-request='1']{color:#9be1b5;border:1px solid #39694e;border-radius:999px;font-size:11px;padding:5px 7px;margin:0 2px;white-space:nowrap}.rpa-track-actions button[data-request='1'].sent{color:#71c98f}.rpa-track-actions .fav.on{color:#ef7881}",
      ".rpa-music-locked .rpa-track-actions button[data-play='1']{color:#c7aa87}",
      ".rpa-music-mini{position:absolute;left:8px;right:8px;bottom:8px;display:grid;grid-template-columns:48px minmax(0,1fr) auto;gap:9px;align-items:center;padding:8px;border:1px solid #35443c;border-radius:15px;background:#1a221e;color:#fff;box-shadow:0 10px 35px rgba(0,0,0,.48)}.rpa-music-mini[hidden]{display:none}.rpa-music-mini img{width:48px;height:48px;border-radius:8px;object-fit:cover}.rpa-mini-copy{min-width:0}.rpa-mini-copy b,.rpa-mini-copy span{display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rpa-mini-copy b{font-size:13px}.rpa-mini-copy span{font-size:11px;color:#aebbb3}.rpa-mini-copy input{width:100%;height:3px;margin-top:6px;accent-color:#e8ad66}.rpa-mini-controls{display:flex}.rpa-mini-controls button{border:0;background:transparent;color:#fff;font-size:19px;padding:8px}.rpa-mini-controls #rpa-mini-play{color:#e8ad66}",
      ".rpa-playlist-modal{position:absolute;inset:0;background:rgba(0,0,0,.68);display:grid;place-items:end center;padding:14px;z-index:10}.rpa-playlist-modal[hidden]{display:none}.rpa-playlist-modal>div{box-sizing:border-box;width:min(100%,520px);background:#18201c;color:#f4f7f5;border:1px solid #35443c;border-radius:18px;padding:16px;max-height:70vh;overflow:auto}.rpa-playlist-modal h3{margin:0 0 10px}.rpa-request-copy{margin:5px 0;color:#c8d4cd;line-height:1.5}.rpa-playlist-modal label{display:block;font-size:12px;color:#aebbb3;margin-top:12px}.rpa-playlist-modal input{box-sizing:border-box;width:100%;margin-top:5px;padding:10px;border:1px solid #46584e;border-radius:10px;background:#0f1512;color:#fff}.rpa-playlist-option{display:block;width:100%;text-align:left;border:0;background:#253229;color:#eef4f0;border-radius:10px;padding:10px;margin:6px 0}.rpa-modal-actions{display:flex;gap:8px;justify-content:flex-end;margin-top:12px}.rpa-modal-actions button{border:0;border-radius:10px;padding:9px 12px}.rpa-modal-actions #rpa-playlist-create,.rpa-modal-actions #rpa-request-confirm{background:#e8ad66;color:#17100a;font-weight:700}",
      "@media(min-width:600px){.rpa-official-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(min-width:700px){#rpa-music-panel{background:rgba(0,0,0,.62);display:grid;place-items:center;transform:none;opacity:0;pointer-events:none;transition:opacity .2s}.rpa-music-shell{width:min(720px,94vw);height:min(850px,94vh);background:#0b0f0d;border:1px solid #34443b;border-radius:22px;overflow:hidden;box-shadow:0 20px 70px rgba(0,0,0,.55)}#rpa-music-panel.open{opacity:1;pointer-events:auto}.rpa-music-mini{position:absolute;left:calc(50% - min(352px,45vw));right:calc(50% - min(352px,45vw));bottom:calc(3vh + 8px)}}"
    ].join("");
    (document.head || document.documentElement).appendChild(style);

    var trackList = document.getElementById("rpa-track-list");
    var searchInput = document.getElementById("rpa-music-search");
    var playlistBar = document.getElementById("rpa-playlist-bar");
    var mini = document.getElementById("rpa-music-mini");
    var progress = document.getElementById("rpa-mini-progress");
    var modal = document.getElementById("rpa-playlist-modal");
    var requestModal = document.getElementById("rpa-request-modal");
    var requestFeedback = document.getElementById("rpa-request-feedback");
    var accessBanner = document.getElementById("rpa-access-banner");

    function notifyNavigation(destination) {
      if (!window.RPA || typeof window.RPA.postMessage !== "function") return;
      try { window.RPA.postMessage("NAV_" + destination); } catch (_) {}
    }

    function openSubscriptions() {
      if (!window.RPA || typeof window.RPA.postMessage !== "function") return;
      try { window.RPA.postMessage("OPEN_SUBSCRIPTIONS"); } catch (_) {}
    }

    function openMusic(notifyNative) {
      panel.classList.add("open");
      panel.setAttribute("aria-hidden", "false");
      loadCatalog();
      loadRequestCatalog();
      if (notifyNative) notifyNavigation("MUSIC");
    }

    function closeMusic(notifyNative) {
      panel.classList.remove("open");
      panel.setAttribute("aria-hidden", "true");
      modal.hidden = true;
      requestModal.hidden = true;
      if (notifyNative) notifyNavigation("RADIO");
    }

    window.__RPA_SHOW_MUSIC = function () { openMusic(false); };
    window.__RPA_SHOW_RADIO = function () { closeMusic(false); };
    window.__RPA_UPDATE_OFFICIAL_PLAYLISTS = function (payload) {
      officialPlaylists = normalizeOfficialPlaylists(payload);
      if (panel.classList.contains("open")) renderTracks();
    };
    window.__RPA_SET_MUSIC_ACCESS = function (access) {
      musicAccess = access === true;
      panel.classList.toggle("rpa-music-locked", !musicAccess);
      accessBanner.hidden = musicAccess;
      if (!musicAccess) {
        mini.hidden = true;
        stopProgressTimer();
      }
      renderTracks();
    };
    window.__RPA_SET_MUSIC_ACCESS(musicAccess);

    function personalPlaylistNames() {
      return Object.keys(library.playlists).sort(function (left, right) {
        return left.localeCompare(right, "pt-PT");
      });
    }

    function searchPhrase() {
      return String(searchInput.value || "").trim().toLocaleLowerCase("pt-PT");
    }

    function matchesTrack(track, query) {
      if (!query) return true;
      return (track.title + " " + track.artist + " " + track.album)
        .toLocaleLowerCase("pt-PT").indexOf(query) >= 0;
    }

    function officialPlaylistForView() {
      if (activeView.indexOf("official:") !== 0) return null;
      var id = activeView.slice(9);
      return officialPlaylists.find(function (playlist) {
        return playlist.id === id;
      }) || null;
    }

    function tracksForOfficialPlaylist(playlist) {
      if (!playlist) return [];
      var ids = new Set(playlist.trackIds);
      return catalog.filter(function (track) { return ids.has(track.id); });
    }

    function tracksForView() {
      var list = catalog.slice();
      if (activeView === "official" || activeView === "personal") {
        list = [];
      } else if (activeView.indexOf("official:") === 0) {
        list = tracksForOfficialPlaylist(officialPlaylistForView());
      } else if (activeView === "favorites") {
        var favs = new Set(library.favorites);
        list = list.filter(function (track) { return favs.has(track.id); });
      } else if (activeView.indexOf("personal:") === 0) {
        var name = activeView.slice(9);
        var ids = new Set(library.playlists[name] || []);
        list = list.filter(function (track) { return ids.has(track.id); });
      }
      var query = searchPhrase();
      return query
        ? list.filter(function (track) { return matchesTrack(track, query); })
        : list;
    }

    function renderPlaylistBar() {
      if (activeView.indexOf("official:") === 0) {
        playlistBar.innerHTML = "<button type='button' data-official-home='1'>‹ Todas as playlists</button>";
        return;
      }
      var names = personalPlaylistNames();
      if (activeView !== "personal" && activeView.indexOf("personal:") !== 0) {
        playlistBar.innerHTML = "";
        return;
      }
      var html = "<button type='button' data-new-playlist='1'>＋ Nova</button>";
      names.forEach(function (name) {
        var active = activeView === "personal:" + name ? " active" : "";
        html += "<button type='button' class='" + active + "' data-playlist='" +
          escapeHtml(name) + "'>" + escapeHtml(name) + "</button>";
      });
      playlistBar.innerHTML = html;
    }

    function officialPlaylistMatches(playlist, query) {
      if (!query) return true;
      if ((playlist.name + " " + playlist.description)
          .toLocaleLowerCase("pt-PT").indexOf(query) >= 0) return true;
      return tracksForOfficialPlaylist(playlist).some(function (track) {
        return matchesTrack(track, query);
      });
    }

    function renderOfficialCards() {
      if (!catalogLoaded) {
        trackList.innerHTML = "<div class='rpa-music-loading'>A carregar playlists…</div>";
        return;
      }
      var query = searchPhrase();
      var availablePlaylists = officialPlaylists.filter(function (playlist) {
        return tracksForOfficialPlaylist(playlist).length > 0;
      });
      var playlists = availablePlaylists.filter(function (playlist) {
        return officialPlaylistMatches(playlist, query);
      });
      if (!playlists.length) {
        trackList.innerHTML = availablePlaylists.length
          ? "<div class='rpa-music-empty'>Não encontrei playlists ou músicas.</div>"
          : "<div class='rpa-music-empty'><b>As playlists da rádio não estão disponíveis nesta versão.</b><br>Podes continuar a ouvir em Todas.</div>";
        return;
      }
      trackList.innerHTML = "<section class='rpa-official-grid'>" + playlists.map(function (playlist) {
        var tracks = tracksForOfficialPlaylist(playlist);
        var cover = tracks.length ? tracks[0].artwork : DEFAULT_ARTWORK;
        var count = tracks.length;
        return [
          "<button type='button' class='rpa-official-card' data-open-official='", escapeHtml(playlist.id), "'>",
          "<img src='", escapeHtml(cover), "' alt=''><span class='rpa-card-play'>", musicAccess ? "▶" : "🔒", "</span>",
          "<b>", escapeHtml(playlist.name), "</b><span>", count, " música", count === 1 ? "" : "s", "</span></button>"
        ].join("");
      }).join("") + "</section>";
    }

    function renderPersonalCards() {
      var names = personalPlaylistNames();
      if (!names.length) {
        trackList.innerHTML = "<div class='rpa-music-empty'><b>Ainda não tens playlists pessoais.</b><br>Cria uma e adiciona as tuas músicas preferidas.</div>";
        return;
      }
      trackList.innerHTML = names.map(function (name) {
        var count = (library.playlists[name] || []).length;
        return "<button type='button' class='rpa-playlist-option' data-open-personal='" + escapeHtml(name) + "'><b>♫ " + escapeHtml(name) + "</b><br><small>" + count + " música" + (count === 1 ? "" : "s") + "</small></button>";
      }).join("");
    }

    function renderTrackRows(list, heading) {
      if (!list.length) {
        trackList.innerHTML = catalogLoaded
          ? "<div class='rpa-music-empty'>Não encontrei músicas aqui.</div>"
          : "<div class='rpa-music-loading'>A carregar catálogo…</div>";
        return;
      }
      var favs = new Set(library.favorites);
      var headingHtml = heading
        ? "<div class='rpa-list-heading'><b>" + escapeHtml(heading) +
          "</b><span>" + list.length + " música" + (list.length === 1 ? "" : "s") + "</span></div>"
        : "";
      trackList.innerHTML = headingHtml + list.map(function (track) {
        var request = requestsBySongId.get(track.requestSongId);
        var requestButton = "";
        if (requestedSongIds.has(track.requestSongId)) {
          requestButton = "<button type='button' class='sent' data-request='1' disabled aria-label='Pedido enviado'>✓</button>";
        } else if (request) {
          requestButton = "<button type='button' data-request='1' aria-label='Pedir na rádio' title='Pedir na rádio'>🎙 Pedir</button>";
        } else if (requestCatalogLoading && !requestCatalogLoaded) {
          requestButton = "<button type='button' data-request='1' disabled aria-label='A verificar pedidos'>·</button>";
        }
        return [
          "<article class='rpa-track' data-id='", escapeHtml(track.id), "'>",
          "<img src='", escapeHtml(track.artwork), "' alt=''>",
          "<div class='rpa-track-copy' data-play='1'><b>", escapeHtml(track.title), "</b><span>",
          escapeHtml(track.artist + (track.album ? " · " + track.album : "")), "</span></div>",
          "<div class='rpa-track-actions'><button type='button' data-play='1' aria-label='", musicAccess ? "Tocar" : "Desbloquear música", "'>", musicAccess ? "▶" : "🔒", "</button>",
          requestButton,
          "<button type='button' class='fav", favs.has(track.id) ? " on" : "", "' data-fav='1' aria-label='Favorito'>♥</button>",
          "<button type='button' data-add='1' aria-label='Adicionar à playlist pessoal'>＋</button></div></article>"
        ].join("");
      }).join("");
    }

    function renderTracks() {
      var rootView = activeView.indexOf("official:") === 0
        ? "official"
        : (activeView.indexOf("personal:") === 0 ? "personal" : activeView);
      document.querySelectorAll(".rpa-music-tabs button").forEach(function (button) {
        button.classList.toggle("active", button.getAttribute("data-view") === rootView);
      });
      renderPlaylistBar();
      if (activeView === "official") {
        renderOfficialCards();
        return;
      }
      if (activeView === "personal") {
        renderPersonalCards();
        return;
      }
      var official = officialPlaylistForView();
      if (activeView.indexOf("official:") === 0 && !official) {
        activeView = "official";
        renderTracks();
        return;
      }
      var personalName = activeView.indexOf("personal:") === 0 ? activeView.slice(9) : null;
      renderTrackRows(tracksForView(), official ? official.name : personalName);
    }

    function loadCatalog() {
      if (catalogLoaded || catalogLoading) return;
      catalogLoading = true;
      trackList.innerHTML = "<div class='rpa-music-loading'>A carregar músicas do AzuraCast…</div>";
      window.fetch(API_URL, { headers: { "Accept": "application/json" }, cache: "no-store" })
        .then(function (response) {
          if (!response.ok) throw new Error("HTTP " + response.status);
          return response.json();
        })
        .then(function (data) {
          var rows = Array.isArray(data) ? data : (Array.isArray(data.rows) ? data.rows : []);
          catalog = rows.map(normalizeTrack).filter(Boolean);
          catalogLoaded = true;
          catalogLoading = false;
          renderTracks();
        })
        .catch(function () {
          catalogLoading = false;
          trackList.innerHTML = "<div class='rpa-music-empty'><b>O catálogo ainda não está disponível.</b><br>Confirma no AzuraCast: Enable On-Demand Streaming e Include in On-Demand Player.</div>";
        });
    }

    function setRequestFeedback(message, isError) {
      if (requestFeedbackTimer) {
        clearTimeout(requestFeedbackTimer);
        requestFeedbackTimer = null;
      }
      requestFeedback.textContent = String(message || "");
      requestFeedback.classList.toggle("error", isError === true);
      requestFeedback.hidden = !message;
      if (message) {
        requestFeedbackTimer = setTimeout(function () {
          requestFeedback.hidden = true;
          requestFeedbackTimer = null;
        }, 9000);
      }
    }

    function loadRequestCatalog() {
      if (requestCatalogLoaded || requestCatalogLoading) return;
      requestCatalogLoading = true;
      setRequestFeedback("A verificar as músicas disponíveis para pedidos…", false);
      window.fetch(REQUESTS_URL, {
        headers: { "Accept": "application/json" },
        cache: "no-store",
        credentials: "omit"
      })
        .then(function (response) {
          if (!response.ok) throw new Error("HTTP " + response.status);
          return response.json();
        })
        .then(function (data) {
          var rows = Array.isArray(data) ? data : (Array.isArray(data.rows) ? data.rows : []);
          var nextRequests = new Map();
          rows.map(normalizeRequest).filter(Boolean).forEach(function (request) {
            if (!nextRequests.has(request.songId)) {
              nextRequests.set(request.songId, request);
            }
          });
          requestsBySongId = nextRequests;
          requestCatalogLoaded = true;
          requestCatalogLoading = false;
          setRequestFeedback("", false);
          renderTracks();
        })
        .catch(function () {
          requestCatalogLoading = false;
          setRequestFeedback(
            "Não foi possível carregar os pedidos. Podes continuar a ouvir as músicas.",
            true
          );
          renderTracks();
        });
    }

    function showRequestModal(track) {
      var request = requestsBySongId.get(track.requestSongId);
      if (!request || requestedSongIds.has(track.requestSongId)) return;
      selectedRequestTrack = track;
      document.getElementById("rpa-request-copy").textContent =
        "Queres pedir “" + track.title + "” para tocar na emissão ao vivo? " +
        "O pedido será tocado quando chegar a sua vez.";
      var confirm = document.getElementById("rpa-request-confirm");
      confirm.disabled = false;
      confirm.textContent = "🎙 Pedir na rádio";
      requestModal.hidden = false;
    }

    function submitSelectedRequest() {
      if (requestSubmitting || !selectedRequestTrack) return;
      var track = selectedRequestTrack;
      var request = requestsBySongId.get(track.requestSongId);
      if (!request) return;
      requestSubmitting = true;
      var confirm = document.getElementById("rpa-request-confirm");
      confirm.disabled = true;
      confirm.textContent = "A enviar…";
      window.fetch(request.requestUrl, {
        method: "POST",
        headers: { "Accept": "application/json" },
        cache: "no-store",
        credentials: "omit"
      })
        .then(function (response) {
          return response.text().then(function (body) {
            var payload = null;
            try { payload = body ? JSON.parse(body) : null; } catch (_) {}
            if (!response.ok || (payload && payload.success === false)) {
              var error = new Error("Pedido recusado");
              error.status = response.status;
              throw error;
            }
          });
        })
        .then(function () {
          requestedSongIds.add(track.requestSongId);
          requestSubmitting = false;
          selectedRequestTrack = null;
          requestModal.hidden = true;
          setRequestFeedback(
            "Pedido enviado! A música será tocada quando chegar a sua vez.",
            false
          );
          renderTracks();
        })
        .catch(function (error) {
          requestSubmitting = false;
          selectedRequestTrack = null;
          requestModal.hidden = true;
          var status = Number(error && error.status);
          var message = status === 403 || status === 429
            ? "O AzuraCast está a aplicar o intervalo entre pedidos. Tenta novamente mais tarde."
            : (status === 404
              ? "Esta música deixou de estar disponível para pedidos."
              : "Não foi possível enviar o pedido. Verifica a ligação e tenta novamente.");
          setRequestFeedback(message, true);
          renderTracks();
        });
    }

    function playTrack(track, sourceList) {
      if (!musicAccess) {
        openSubscriptions();
        return;
      }
      var list = sourceList && sourceList.length ? sourceList : [track];
      var index = list.findIndex(function (item) { return item.id === track.id; });
      if (index < 0) index = 0;
      var from = Math.max(0, index - 49);
      var to = Math.min(list.length, from + 100);
      if (to - from < 100) from = Math.max(0, to - 100);
      var queue = list.slice(from, to);
      var queueIndex = queue.findIndex(function (item) { return item.id === track.id; });
      selectedTrackId = track.id;
      postJson({
        action: "PLAY_TRACK",
        track: nativeTrack(track),
        queue: queue.map(nativeTrack),
        queueIndex: queueIndex
      });
    }

    function toggleFavorite(id) {
      var index = library.favorites.indexOf(id);
      if (index >= 0) library.favorites.splice(index, 1);
      else library.favorites.push(id);
      saveLibrary();
      renderTracks();
    }

    function showPlaylistModal(trackId) {
      selectedTrackId = trackId;
      var options = document.getElementById("rpa-playlist-options");
      options.innerHTML = personalPlaylistNames().map(function (name) {
        return "<button type='button' class='rpa-playlist-option' data-add-to='" + escapeHtml(name) + "'>＋ " + escapeHtml(name) + "</button>";
      }).join("") || "<small>Ainda não existem playlists.</small>";
      document.getElementById("rpa-new-playlist-name").value = "";
      modal.hidden = false;
    }

    function addToPlaylist(name, trackId) {
      name = String(name || "").trim();
      if (!name || !trackId) return;
      if (!Array.isArray(library.playlists[name])) library.playlists[name] = [];
      if (!library.playlists[name].includes(trackId)) library.playlists[name].push(trackId);
      saveLibrary();
      modal.hidden = true;
      renderTracks();
    }

    document.getElementById("rpa-music-close").addEventListener("click", function () {
      closeMusic(true);
    });
    document.getElementById("rpa-music-live").addEventListener("click", function () {
      postCommand("PLAY");
      closeMusic(true);
    });
    document.getElementById("rpa-unlock-music").addEventListener("click", openSubscriptions);
    document.querySelectorAll(".rpa-music-tabs button").forEach(function (button) {
      button.addEventListener("click", function () {
        activeView = button.getAttribute("data-view") || "all";
        renderTracks();
      });
    });
    searchInput.addEventListener("input", renderTracks);
    playlistBar.addEventListener("click", function (event) {
      var target = event.target;
      if (!target || typeof target.getAttribute !== "function") return;
      if (target.getAttribute("data-new-playlist") === "1") {
        showPlaylistModal(null);
        return;
      }
      if (target.getAttribute("data-official-home") === "1") {
        activeView = "official";
        renderTracks();
        return;
      }
      var name = target.getAttribute("data-playlist");
      if (name) { activeView = "personal:" + name; renderTracks(); }
    });
    trackList.addEventListener("click", function (event) {
      var target = event.target;
      if (!target || typeof target.closest !== "function") return;
      var openOfficial = target.closest("[data-open-official]");
      if (openOfficial) {
        activeView = "official:" + openOfficial.getAttribute("data-open-official");
        renderTracks();
        return;
      }
      var openPersonal = target.closest("[data-open-personal]");
      if (openPersonal) {
        activeView = "personal:" + openPersonal.getAttribute("data-open-personal");
        renderTracks();
        return;
      }
      var row = target.closest(".rpa-track");
      if (!row) return;
      var id = row.getAttribute("data-id");
      var track = catalog.find(function (item) { return item.id === id; });
      if (!track) return;
      if (target.closest("[data-request]")) { showRequestModal(track); return; }
      if (target.closest("[data-fav]")) { toggleFavorite(id); return; }
      if (target.closest("[data-add]")) { showPlaylistModal(id); return; }
      if (target.closest("[data-play]")) { playTrack(track, tracksForView()); }
    });
    document.getElementById("rpa-playlist-options").addEventListener("click", function (event) {
      var target = event.target;
      if (!target || typeof target.getAttribute !== "function") return;
      var name = target.getAttribute("data-add-to");
      if (name) addToPlaylist(name, selectedTrackId);
    });
    document.getElementById("rpa-playlist-cancel").addEventListener("click", function () { modal.hidden = true; });
    document.getElementById("rpa-playlist-create").addEventListener("click", function () {
      var name = document.getElementById("rpa-new-playlist-name").value;
      if (!selectedTrackId) {
        name = String(name || "").trim();
        if (name && !library.playlists[name]) {
          library.playlists[name] = [];
          saveLibrary();
          modal.hidden = true;
          activeView = "personal:" + name;
          renderTracks();
        }
        return;
      }
      addToPlaylist(name, selectedTrackId);
    });
    document.getElementById("rpa-request-cancel").addEventListener("click", function () {
      if (requestSubmitting) return;
      selectedRequestTrack = null;
      requestModal.hidden = true;
    });
    document.getElementById("rpa-request-confirm").addEventListener("click", submitSelectedRequest);

    document.getElementById("rpa-mini-prev").addEventListener("click", function () { postCommand("PREVIOUS_TRACK"); });
    document.getElementById("rpa-mini-next").addEventListener("click", function () { postCommand("NEXT_TRACK"); });
    document.getElementById("rpa-mini-play").addEventListener("click", function () {
      if (!musicAccess) { openSubscriptions(); return; }
      if (["PLAYING", "CONNECTING", "BUFFERING", "RECONNECTING"].includes(lastMusicState)) postCommand("PAUSE");
      else postCommand("MUSIC_RESUME");
    });
    progress.addEventListener("change", function () {
      if (!musicAccess) { openSubscriptions(); return; }
      if (!lastMetadata.durationMs) return;
      var positionMs = Math.round((Number(progress.value) / 1000) * lastMetadata.durationMs);
      postJson({ action: "SEEK", positionMs: positionMs });
    });

    window.__RPA_MUSIC_RENDER_STATE = function (state, metadata) {
      lastMusicState = state;
      clockStartedAt = Date.now();
      if (metadata.mode !== "ondemand") {
        mini.hidden = true;
        stopProgressTimer();
        return;
      }
      if (!musicAccess) {
        mini.hidden = true;
        stopProgressTimer();
        return;
      }
      mini.hidden = false;
      document.getElementById("rpa-mini-art").src = metadata.artwork || DEFAULT_ARTWORK;
      document.getElementById("rpa-mini-title").textContent = metadata.title || "Música";
      document.getElementById("rpa-mini-artist").textContent = metadata.artist || "";
      document.getElementById("rpa-mini-play").textContent = ["PLAYING", "CONNECTING", "BUFFERING"].includes(state) ? "❚❚" : "▶";
      document.getElementById("rpa-mini-prev").disabled = metadata.canPrevious !== true;
      document.getElementById("rpa-mini-next").disabled = metadata.canNext !== true;
      if (metadata.durationMs) {
        progress.value = Math.round((metadata.positionMs / metadata.durationMs) * 1000);
      } else {
        progress.value = 0;
      }
      startProgressTimer();
    };

    function stopProgressTimer() {
      if (progressTimer != null && typeof window.clearInterval === "function") {
        window.clearInterval(progressTimer);
      }
      progressTimer = null;
    }

    function startProgressTimer() {
      stopProgressTimer();
      if (!musicRuntimeActive || lastMetadata.mode !== "ondemand" ||
          lastMusicState !== "PLAYING" || !lastMetadata.durationMs ||
          typeof window.setInterval !== "function") return;
      progressTimer = window.setInterval(function () {
        var position = Math.min(lastMetadata.durationMs,
          lastMetadata.positionMs + (Date.now() - clockStartedAt));
        progress.value = Math.round((position / lastMetadata.durationMs) * 1000);
      }, 500);
    }

    window.__RPA_MUSIC_SET_RUNTIME_ACTIVE = function (active) {
      musicRuntimeActive = active === true;
      if (musicRuntimeActive) startProgressTimer();
      else stopProgressTimer();
    };
  }

  window.__RPA_SET_STATE = function (state, metadata) {
    if (typeof state !== "string" || !VALID_STATES.has(state)) return;
    renderState(state, metadata || {});
  };

  function applyRuntimeState() {
    var wasActive = runtimeActive;
    runtimeActive = runtimeRequestedActive && document.hidden !== true;
    document.documentElement.classList.toggle(
      "rpa-runtime-paused", !runtimeActive
    );
    if (pendingTimer && !runtimeActive) {
      clearTimeout(pendingTimer);
      pendingTimer = null;
      commandPending = false;
    }
    updatePlayerDecorations(nativePlayerState);
    if (typeof window.__RPA_MUSIC_SET_RUNTIME_ACTIVE === "function") {
      window.__RPA_MUSIC_SET_RUNTIME_ACTIVE(runtimeActive);
    }
    if (runtimeActive && !wasActive) postCommand("GET_STATE");
  }

  window.__RPA_SET_ACTIVE = function (active) {
    runtimeRequestedActive = active === true;
    applyRuntimeState();
  };

  if (typeof document.addEventListener === "function") {
    document.addEventListener("visibilitychange", function () {
      applyRuntimeState();
    });
  }

  neutralizeLegacyAudio();
  installStyles();
  bindButtons();
  installMusicArea();
  updateMetadata(lastMetadata);
  updatePlayerDecorations(nativePlayerState);
  window.__RPA_SET_ACTIVE(runtimeActive);
  postCommand("GET_STATE");
})();
