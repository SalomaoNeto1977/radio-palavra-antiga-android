/* Leitor web/PWA. Nunca controla o áudio nativo Android. */
(function () {
  'use strict';
  if (window.RPA && typeof window.RPA.postMessage === 'function') return;
  if (/RadioPalavraAntiga\//.test(navigator.userAgent)) return;
  if (window.__PA_WEB_PLAYER) return;
  const root = document.getElementById('paWebPlayer');
  if (!root) return;
  const el = id => root.querySelector('#' + id);
  const audio = el('paWebAudio'), button = el('paPlayerButton');
  if (!audio || !button) return;
  const titleEl = el('paPlayerSong'), artistEl = el('paPlayerArtist');
  const statusEl = el('paPlayerStatus'), cover = el('paPlayerCover');
  const fallback = el('paPlayerFallback'), volume = el('paVolume');
  const mute = el('paMuteButton');
  const BASE = 'https://radio.palavraantiga.org';
  const STREAM = BASE + '/listen/palavraantiga/radio.mp3';
  const LOGO = 'https://palavraantiga.org/web/image/website/1/logo/512x512';
  const listeners = [];
  let disposed = false, wanted = false, generation = 0, connectingTimer;
  let pollTimer, request = null, suspended = false, currentArt = '';
  let title = 'Rádio Palavra Antiga', artist = 'Rádio Cristã Portuguesa';
  function on(target, event, handler) {
    if (!target) return;
    target.addEventListener(event, handler);
    listeners.push(() => target.removeEventListener(event, handler));
  }
  function state(value, message) {
    root.classList.toggle('is-playing', value === 'playing');
    root.classList.toggle('is-loading', value === 'loading');
    statusEl.textContent = message;
    button.setAttribute('aria-label', wanted ? 'Parar Rádio Palavra Antiga' : 'Ouvir Rádio Palavra Antiga');
    button.setAttribute('aria-pressed', String(wanted));
    try {
      if ('mediaSession' in navigator) navigator.mediaSession.playbackState =
        value === 'playing' ? 'playing' : (wanted ? 'none' : 'paused');
    } catch (_) {}
  }
  function metadata() {
    if (!wanted || !('mediaSession' in navigator) || !window.MediaMetadata) return;
    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title, artist, album: 'Rádio Palavra Antiga',
        artwork: [{src: currentArt || LOGO}]
      });
    } catch (_) {}
  }
  function stop(message = 'Toca para ouvir') {
    wanted = false;
    generation++;
    clearTimeout(connectingTimer);
    audio.pause();
    audio.removeAttribute('src');
    audio.load();
    state('stopped', message);
  }
  function start() {
    if (disposed || wanted) return;
    const attempt = ++generation;
    wanted = true;
    state('loading', 'A ligar…');
    metadata();
    audio.src = STREAM + '?_pa=' + Date.now();
    clearTimeout(connectingTimer);
    connectingTimer = setTimeout(() => {
      if (wanted && attempt === generation) stop('A ligação demorou demasiado. Toca para tentar novamente.');
    }, 30000);
    // Chamada síncrona no gesto do utilizador: necessária no iPhone.
    try {
      const pending = audio.play();
      if (pending && pending.catch) pending.catch(() => {
        if (!disposed && attempt === generation) stop('Não foi possível iniciar. Toca para tentar novamente.');
      });
    } catch (_) { if (attempt === generation) stop('Toca novamente para ouvir'); }
  }
  on(button, 'click', () => wanted ? stop() : start());
  on(audio, 'playing', () => {
    if (!wanted || disposed) { audio.pause(); return; }
    clearTimeout(connectingTimer);
    state('playing', 'A ouvir em direto');
    metadata();
  });
  on(audio, 'waiting', () => {
    if (!wanted) return;
    state('loading', 'A recuperar ligação…');
    clearTimeout(connectingTimer);
    connectingTimer = setTimeout(() => {
      if (wanted) stop('A ligação foi interrompida. Toca para voltar a ouvir.');
    }, 30000);
  });
  on(audio, 'error', () => { if (wanted) stop('Não foi possível ligar. Toca para tentar novamente.'); });
  on(audio, 'ended', () => { if (wanted) stop('A emissão foi interrompida. Toca para voltar a ouvir.'); });
  on(audio, 'pause', () => {
    // Uma chamada ou pausa do sistema não deve ser contrariada por autoplay.
    if (wanted && audio.paused) stop('Em pausa. Toca para voltar a ouvir.');
  });
  function volumeState() {
    root.classList.toggle('is-muted', audio.muted || audio.volume === 0);
    if (mute) {
      mute.classList.toggle('is-muted', audio.muted || audio.volume === 0);
      mute.setAttribute('aria-pressed', String(audio.muted));
      mute.setAttribute('aria-label', audio.muted ? 'Ativar som' : 'Silenciar');
    }
  }
  on(volume, 'input', () => {
    const v = Number(volume.value);
    if (Number.isFinite(v)) { audio.volume = Math.max(0, Math.min(1, v)); audio.muted = false; }
    volumeState();
  });
  on(mute, 'click', () => { audio.muted = !audio.muted; volumeState(); });
  on(audio, 'volumechange', volumeState);
  // iOS gere o volume no dispositivo; não mostrar um slider inoperante.
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (volume && ios) volume.hidden = true;
  if (volume && !ios) audio.volume = Number(volume.value) || 0.85;
  volumeState();
  function safeArt(value) {
    if (typeof value !== 'string' || !value.trim()) return '';
    try {
      const url = new URL(value.replace(/&amp;/g, '&'), BASE + '/');
      return url.protocol === 'https:' ? url.href : '';
    } catch (_) { return ''; }
  }
  function showArt(url) {
    if (!cover) return;
    if (cover.getAttribute('src') !== url) {
      cover.setAttribute('src', url);
      cover.alt = 'Capa: ' + title;
    }
    if (url !== currentArt) { currentArt = url; metadata(); }
  }
  on(cover, 'load', () => {
    cover.style.opacity = '1';
    if (fallback) fallback.style.display = 'none';
  });
  on(cover, 'error', () => {
    if (cover.getAttribute('src') !== LOGO) { showArt(LOGO); return; }
    cover.style.opacity = '0';
    if (fallback) fallback.style.display = '';
  });
  function text(value, otherwise) {
    return typeof value === 'string' && value.trim() ? value.trim() : otherwise;
  }
  function schedule() {
    clearTimeout(pollTimer);
    if (!disposed && !suspended && !document.hidden) pollTimer = setTimeout(poll, 15000);
  }
  async function poll() {
    clearTimeout(pollTimer);
    if (disposed || suspended || request || document.hidden) return;
    const controller = new AbortController();
    request = controller;
    const deadline = setTimeout(() => controller.abort(), 8000);
    try {
      const response = await fetch(BASE + '/api/nowplaying/palavraantiga', {
        cache: 'no-store', credentials: 'omit', headers: {Accept: 'application/json'}, signal: controller.signal
      });
      if (!response.ok) throw new Error('HTTP ' + response.status);
      const data = await response.json();
      if (disposed || controller.signal.aborted) return;
      const now = data.now_playing || {}, song = now.song || {};
      title = text(song.title, text(song.text, 'Rádio Palavra Antiga'));
      artist = text(song.artist, 'Rádio Cristã Portuguesa');
      titleEl.textContent = title; titleEl.title = title;
      artistEl.textContent = artist; artistEl.title = artist;
      document.dispatchEvent(new CustomEvent('rpa:live-metadata', {detail: {title, artist}}));
      // Avalia a capa em cada resposta, mesmo sem mudança de música.
      const art = [song.art, song.art_url, now.art, now.art_url, data.station?.art]
        .map(safeArt).find(Boolean) || LOGO;
      showArt(art);
      metadata();
    } catch (_) {
      if (!disposed && titleEl.textContent.includes('carregar')) {
        titleEl.textContent = title; artistEl.textContent = artist;
      }
    } finally {
      clearTimeout(deadline);
      if (request === controller) request = null;
      schedule();
    }
  }
  const actions = {play: start, pause: () => stop(), stop: () => stop()};
  if ('mediaSession' in navigator) Object.entries(actions).forEach(([action, handler]) => {
    try { navigator.mediaSession.setActionHandler(action, handler); } catch (_) {}
  });
  function dispose() {
    if (disposed) return;
    disposed = true;
    listeners.splice(0).forEach(remove => remove());
    clearTimeout(pollTimer);
    if (request) request.abort();
    stop();
    if ('mediaSession' in navigator) Object.keys(actions).forEach(action => {
      try { navigator.mediaSession.setActionHandler(action, null); } catch (_) {}
    });
    delete window.__PA_WEB_PLAYER;
  }
  window.__PA_WEB_PLAYER = {dispose};
  on(document, 'visibilitychange', () => {
    if (document.hidden) { clearTimeout(pollTimer); if (request) request.abort(); }
    else poll();
    // Esconder a página não pára a emissão.
  });
  on(window, 'pagehide', event => {
    suspended = true;
    clearTimeout(pollTimer);
    if (request) request.abort();
    if (!event.persisted) dispose();
  });
  on(window, 'pageshow', () => { suspended = false; poll(); });
  state('stopped', 'Toca para ouvir');
  showArt(LOGO);
  poll();
})();
