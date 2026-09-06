'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../web_integration/site/web-player.js'), 'utf8');
class Element extends EventTarget {
  constructor() {
    super(); this.attrs = new Map(); this.style = {}; this.value = '0.85'; this.textContent = 'A carregar...';
    const values = new Set();
    this.classList = {toggle(k, on) { on ? values.add(k) : values.delete(k); }, contains(k) { return values.has(k); }};
  }
  setAttribute(k,v) { this.attrs.set(k,String(v)); }
  getAttribute(k) { return this.attrs.get(k) || null; }
  removeAttribute(k) { this.attrs.delete(k); }
}
function harness({native = false, ua = '', response} = {}) {
  const nodes = Object.fromEntries(['paWebAudio','paPlayerButton','paPlayerSong','paPlayerArtist','paPlayerStatus','paPlayerCover','paPlayerFallback','paVolume','paMuteButton'].map(id => [id,new Element()]));
  const audio = nodes.paWebAudio;
  audio.paused = true; audio.volume = 1; audio.muted = false;
  const plays = [];
  audio.play = () => { audio.paused = false; return new Promise((resolve,reject) => plays.push({resolve,reject})); };
  audio.pause = () => { audio.paused = true; audio.dispatchEvent(new Event('pause')); };
  audio.load = () => {};
  const root = new Element(); root.querySelector = id => nodes[id.slice(1)];
  const document = new Element(); document.hidden = false; document.getElementById = () => root;
  const window = new Element(); if(native) window.RPA = {postMessage() {}};
  window.MediaMetadata = class {constructor(value) {Object.assign(this,value);}};
  let fetches = 0;
  const fetch = async (...args) => {
    fetches++;
    return response ? response(...args) : {ok:true, json:async()=>({now_playing:{song:{title:'Salmo 23 (Versão 2)',artist:'Cláudia',art:'/cover-a.jpg'}}})};
  };
  const timers = new Map(); let id = 0;
  const navigator = {userAgent:ua, platform:'', maxTouchPoints:0, mediaSession:{setActionHandler() {}}};
  class CustomEvent extends Event {constructor(type, options) {super(type); this.detail = options.detail;}}
  const context = vm.createContext({window,document,navigator,URL,AbortController,CustomEvent,
    MediaMetadata:window.MediaMetadata, fetch, console,
    setTimeout(fn, ms) {timers.set(++id,{fn,ms});return id;}, clearTimeout(id){timers.delete(id);}});
  vm.runInContext(source,context);
  return {context,root,document,window,nodes,audio,plays,timers,navigator,get fetches(){return fetches;},
    async flush() {await new Promise(resolve=>setImmediate(resolve));},
    click() {nodes.paPlayerButton.dispatchEvent(new Event('click'));},
    dispose() {window.__PA_WEB_PLAYER?.dispose();}};
}
test('Android não inicia áudio, pedidos ou temporizadores web', () => {
  for(const options of [{native:true},{ua:'RadioPalavraAntiga/1.0.12 (Android; Flutter WebView)'}]) {
    const h = harness(options); assert.equal(h.fetches,0); assert.equal(h.timers.size,0); assert.equal(h.window.__PA_WEB_PLAYER,undefined);
  }
});
test('reinserção do script mantém um só controlador e pedido', async () => {
  const h = harness(); vm.runInContext(source,h.context); await h.flush();
  assert.equal(h.fetches,1); h.click(); assert.equal(h.plays.length,1); h.dispose(); assert.equal(h.timers.size,0);
});
test('toque duplo cancela ligação e rejeição antiga não interrompe a nova tentativa', async () => {
  const h = harness(); await h.flush();
  h.click(); h.click(); assert.equal(h.audio.paused,true);
  h.click(); h.plays[0].reject(new Error('cancelled')); await h.flush();
  assert.equal(h.nodes.paPlayerButton.getAttribute('aria-pressed'),'true');
  h.audio.dispatchEvent(new Event('playing'));
  assert.equal(h.root.classList.contains('is-playing'),true); h.dispose();
});
test('números, versões e artista preservados; capa atualiza na mesma música', async () => {
  let art = '/one.jpg';
  const h = harness({response:async()=>({ok:true,json:async()=>({now_playing:{song:{id:'same',title:'Salmo 23 (Versão 2)',artist:'Cláudia',art}}})})});
  await h.flush(); h.click();
  assert.equal(h.nodes.paPlayerSong.textContent,'Salmo 23 (Versão 2)');
  assert.equal(h.nodes.paPlayerArtist.textContent,'Cláudia');
  art = '/two.jpg'; h.document.dispatchEvent(new Event('visibilitychange')); await h.flush();
  assert.equal(h.nodes.paPlayerCover.getAttribute('src'),'https://radio.palavraantiga.org/two.jpg');
  assert.equal(h.navigator.mediaSession.metadata.artwork[0].src,'https://radio.palavraantiga.org/two.jpg'); h.dispose();
});
test('visibilidade não sobrepõe pedidos e esconder a página não pára áudio', async () => {
  let finish;
  const h = harness({response:()=>new Promise(resolve=>finish=resolve)});
  h.document.dispatchEvent(new Event('visibilitychange'));
  assert.equal(h.fetches,1);
  h.click(); h.audio.dispatchEvent(new Event('playing'));
  h.document.hidden=true; h.document.dispatchEvent(new Event('visibilitychange'));
  assert.equal(h.audio.paused,false);
  finish({ok:true,json:async()=>({})}); await h.flush(); h.dispose(); assert.equal(h.timers.size,0);
});
test('pausa do sistema não provoca retoma automática', async () => {
  const h = harness(); await h.flush(); h.click(); h.audio.pause();
  assert.equal(h.nodes.paPlayerButton.getAttribute('aria-pressed'),'false'); assert.equal(h.plays.length,1); h.dispose();
});
test('iPhone oculta slider e chama play no próprio gesto', async () => {
  const h = harness({ua:'iPhone'}); await h.flush();
  assert.equal(h.nodes.paVolume.hidden,true); h.click(); assert.equal(h.plays.length,1); h.dispose();
});
test('silenciar atualiza o ícone correto', async () => {
  const h = harness(); await h.flush(); h.nodes.paMuteButton.dispatchEvent(new Event('click'));
  assert.equal(h.nodes.paMuteButton.classList.contains('is-muted'),true); h.dispose();
});
