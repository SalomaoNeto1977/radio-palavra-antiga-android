(function () {
  'use strict';
  if (window.__RPA_PWA_V2) return;
  window.__RPA_PWA_V2 = true;
  const native = Boolean(window.RPA && typeof window.RPA.postMessage === 'function') ||
    /RadioPalavraAntiga\//.test(navigator.userAgent);
  const standalone = () => window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const ios = () => /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  document.documentElement.classList.toggle('rpa-native-app', native);
  document.documentElement.classList.toggle('rpa-installed', standalone());
  const SELECTOR = '#installAppButton, .js-installAppButton, [data-install-pwa]';
  let prompt = null, installing = false;
  function meta(name, content) {
    let tag = document.querySelector('meta[name="' + name + '"]');
    if (!tag) { tag = document.createElement('meta'); tag.name = name; document.head.appendChild(tag); }
    tag.content = content;
  }
  // Não duplicar viewport/manifest que o Odoo já fornece.
  let viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) meta('viewport', 'width=device-width, initial-scale=1, viewport-fit=cover');
  else if (!/viewport-fit\s*=/.test(viewport.content)) viewport.content += ', viewport-fit=cover';
  if (!native) {
    meta('apple-mobile-web-app-capable', 'yes');
    meta('apple-mobile-web-app-title', 'Palavra Antiga');
    if (!document.querySelector('link[rel="manifest"]')) {
      const link = document.createElement('link'); link.rel = 'manifest'; link.href = '/manifest.json'; document.head.appendChild(link);
    }
    if (!document.querySelector('link[rel="apple-touch-icon"]')) {
      const icon = document.createElement('link'); icon.rel = 'apple-touch-icon';
      icon.href = '/web/image/716-4be0b7f2/logo-palavraantiga-192.png'; document.head.appendChild(icon);
    }
  }
  async function install(event) {
    event?.preventDefault();
    if (native || standalone() || installing) return;
    if (ios()) {
      alert('No iPhone/iPad, abre este site no Safari, toca em Partilhar e escolhe “Adicionar ao Ecrã Principal”.');
      return;
    }
    if (!prompt) {
      alert('Abre o menu do navegador e procura “Instalar aplicação” ou “Adicionar ao ecrã principal”. A opção depende do navegador.');
      return;
    }
    installing = true;
    const pending = prompt; prompt = null;
    try { await pending.prompt(); await pending.userChoice; }
    catch (_) { alert('Não foi possível abrir a instalação. Tenta pelo menu do navegador.'); }
    finally { installing = false; }
  }
  window.installPWA = install;
  document.addEventListener('click', event => {
    const target = event.target instanceof Element ? event.target.closest(SELECTOR) : null;
    if (!target) return;
    event.preventDefault();
    event.stopImmediatePropagation(); // Evita o segundo disparo de onclick legado.
    install(event);
  }, true);
  window.addEventListener('beforeinstallprompt', event => {
    if (native) return;
    event.preventDefault(); prompt = event;
  });
  window.addEventListener('appinstalled', () => {
    prompt = null; document.documentElement.classList.add('rpa-installed');
  });
  if (native) return;
  async function register() {
    if (!('serviceWorker' in navigator) || !window.isSecureContext) return;
    try {
      // Mantém o worker já existente. Não apaga caches nem registos de terceiros.
      const registration = await navigator.serviceWorker.getRegistration('/');
      if (!registration) await navigator.serviceWorker.register('/service-worker.js', {scope: '/', updateViaCache: 'none'});
      else if ([registration.active, registration.waiting, registration.installing].some(worker =>
        worker && new URL(worker.scriptURL).pathname === '/service-worker.js')) await registration.update();
    } catch (error) { console.warn('RPA: não foi possível atualizar a instalação PWA.', error); }
  }
  if (document.readyState === 'complete') register();
  else window.addEventListener('load', register, {once: true});
})();
