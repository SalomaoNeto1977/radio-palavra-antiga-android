"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const bridgeSource = fs.readFileSync(
  path.join(__dirname, "..", "web_integration", "rpa_bridge.js"),
  "utf8"
);

test("o catálogo pago mantém os pedidos fora do bloqueio", () => {
  assert.match(bridgeSource, /window\.__RPA_SET_MUSIC_ACCESS/);
  assert.match(bridgeSource, /OPEN_SUBSCRIPTIONS/);
  assert.match(bridgeSource, /if \(!musicAccess\) \{\s*openSubscriptions\(\);\s*return;\s*\}/);
  assert.match(bridgeSource, /data-request='1'/);
});

class FakeClassList {
  constructor(element) {
    this.element = element;
    this.values = new Set();
  }

  replace(value) {
    this.values = new Set(String(value || "").split(/\s+/).filter(Boolean));
  }

  add(...values) {
    values.forEach(value => this.values.add(value));
  }

  remove(...values) {
    values.forEach(value => this.values.delete(value));
  }

  toggle(value, force) {
    const enabled = force === undefined ? !this.values.has(value) : force;
    if (enabled) this.values.add(value);
    else this.values.delete(value);
    return enabled;
  }

  contains(value) {
    return this.values.has(value);
  }

  toString() {
    return Array.from(this.values).join(" ");
  }
}

class FakeElement {
  constructor(tagName, ownerDocument) {
    this.tagName = tagName.toUpperCase();
    this.ownerDocument = ownerDocument;
    this.parentElement = null;
    this.children = [];
    this.attributes = new Map();
    this.classList = new FakeClassList(this);
    this.listeners = new Map();
    this.style = {};
    this.textContent = "";
    this.disabled = false;
  }

  get id() {
    return this.getAttribute("id") || "";
  }

  set id(value) {
    this.setAttribute("id", value);
  }

  get className() {
    return this.classList.toString();
  }

  set className(value) {
    this.classList.replace(value);
  }

  get firstChild() {
    return this.children[0] || null;
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
    if (name === "class") this.className = value;
  }

  getAttribute(name) {
    if (name === "class") return this.className || null;
    return this.attributes.has(name) ? this.attributes.get(name) : null;
  }

  removeAttribute(name) {
    this.attributes.delete(name);
  }

  appendChild(child) {
    child.remove();
    child.parentElement = this;
    this.children.push(child);
    return child;
  }

  insertBefore(child, reference) {
    child.remove();
    child.parentElement = this;
    const index = this.children.indexOf(reference);
    if (index < 0) this.children.push(child);
    else this.children.splice(index, 0, child);
    return child;
  }

  remove() {
    if (!this.parentElement) return;
    const siblings = this.parentElement.children;
    const index = siblings.indexOf(this);
    if (index >= 0) siblings.splice(index, 1);
    this.parentElement = null;
  }

  replaceWith(replacement) {
    const parent = this.parentElement;
    if (!parent) return;
    const index = parent.children.indexOf(this);
    replacement.remove();
    replacement.parentElement = parent;
    parent.children[index] = replacement;
    this.parentElement = null;
  }

  cloneNode(deep) {
    const clone = this.ownerDocument.createElement(this.tagName);
    this.attributes.forEach((value, key) => clone.setAttribute(key, value));
    clone.className = this.className;
    clone.textContent = this.textContent;
    clone.style = { ...this.style };
    if (deep) this.children.forEach(child => clone.appendChild(child.cloneNode(true)));
    return clone;
  }

  addEventListener(name, handler) {
    const listeners = this.listeners.get(name) || [];
    listeners.push(handler);
    this.listeners.set(name, listeners);
  }

  dispatch(name) {
    const event = {
      preventDefault() {},
      stopPropagation() {},
      stopImmediatePropagation() {}
    };
    (this.listeners.get(name) || []).forEach(handler => handler(event));
    if (typeof this[`on${name}`] === "function") this[`on${name}`](event);
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] || null;
  }

  querySelectorAll(selector) {
    const matches = [];
    const matcher = element => {
      if (selector.startsWith(".")) return element.classList.contains(selector.slice(1));
      const idMatch = selector.match(/^\[id="([^"]+)"\]$/);
      if (idMatch) return element.id === idMatch[1];
      return element.tagName.toLowerCase() === selector.toLowerCase();
    };
    const visit = element => {
      element.children.forEach(child => {
        if (matcher(child)) matches.push(child);
        visit(child);
      });
    };
    visit(this);
    return matches;
  }
}

class FakeAudioElement extends FakeElement {
  constructor(ownerDocument) {
    super("audio", ownerDocument);
    this.muted = false;
    this.volume = 1;
    this.paused = true;
    this.pauseCalls = 0;
    this.loadCalls = 0;
  }

  play() {
    this.paused = false;
    return Promise.resolve();
  }

  pause() {
    this.pauseCalls += 1;
    this.paused = true;
  }

  load() {
    this.loadCalls += 1;
  }
}

class FakeDocument {
  constructor() {
    this.documentElement = new FakeElement("html", this);
    this.head = this.createElement("head");
    this.body = this.createElement("body");
    this.documentElement.appendChild(this.head);
    this.documentElement.appendChild(this.body);
  }

  createElement(tagName) {
    return tagName.toLowerCase() === "audio"
      ? new FakeAudioElement(this)
      : new FakeElement(tagName, this);
  }

  getElementById(id) {
    return this.querySelectorAll(`[id="${id}"]`)[0] || null;
  }

  querySelectorAll(selector) {
    return this.documentElement.querySelectorAll(selector);
  }
}

function createHarness({ existingGlow = false, playingAudio = false } = {}) {
  const document = new FakeDocument();
  const messages = [];
  const timers = new Map();
  const legacy = { clicks: 0, observers: 0 };
  let nextTimer = 0;

  const append = (tagName, id, parent = document.body) => {
    const element = document.createElement(tagName);
    element.id = id;
    parent.appendChild(element);
    return element;
  };

  const audio = append("audio", "radioPlayer");
  audio.paused = !playingAudio;
  audio.setAttribute("src", "https://example.org/radio.mp3");
  const source = append("source", "legacySource", audio);
  source.setAttribute("src", "https://example.org/alternative.mp3");

  const originalButton = append("button", "playBtn");
  originalButton.onclick = () => { legacy.clicks += 1; };
  const image = append("img", "btnImg", originalButton);
  image.className = "playing rpa-playing";
  if (existingGlow) {
    const glow = append("span", "existingGlow", originalButton);
    glow.className = "rpa-btn-glow";
  }

  append("img", "np-capa");
  append("div", "np-titulo").textContent = "A carregar…";
  append("div", "vinylDisc");
  append("div", "tonearm");
  append("div", "needleShadow");

  const navigator = { mediaSession: { setActionHandler() {} } };
  const window = {
    RPA: { postMessage(message) { messages.push(message); } },
    HTMLAudioElement: FakeAudioElement,
    location: { assign() {} }
  };

  const context = vm.createContext({
    window,
    document,
    navigator,
    DOMException,
    Promise,
    Set,
    Date,
    MutationObserver: class {
      constructor() { legacy.observers += 1; }
    },
    setTimeout(handler) {
      const id = ++nextTimer;
      timers.set(id, handler);
      return id;
    },
    clearTimeout(id) { timers.delete(id); }
  });

  vm.runInContext(bridgeSource, context, { filename: "rpa_bridge.js" });

  return {
    audio,
    context,
    document,
    legacy,
    messages,
    timers,
    window,
    button: () => document.getElementById("playBtn"),
    image: () => document.getElementById("btnImg"),
    title: () => document.getElementById("np-titulo"),
    artwork: () => document.getElementById("np-capa"),
    state: (name, metadata = {}) => window.__RPA_SET_STATE(name, metadata)
  };
}

test("arranque remove áudio silenciosamente, sem load nem observadores", async () => {
  const app = createHarness();
  assert.equal(app.document.getElementById("radioPlayer"), null);
  assert.equal(app.audio.muted, true);
  assert.equal(app.audio.volume, 0);
  assert.equal(app.audio.loadCalls, 0);
  assert.equal(app.audio.pauseCalls, 0);
  assert.equal(app.legacy.observers, 0);
  assert.deepEqual(app.messages, ["GET_STATE"]);
  await assert.rejects(app.audio.play(), { name: "NotAllowedError" });
});

test("áudio já activo é silenciado antes de ser parado", () => {
  const app = createHarness({ playingAudio: true });
  assert.equal(app.audio.muted, true);
  assert.equal(app.audio.volume, 0);
  assert.equal(app.audio.pauseCalls, 1);
  assert.equal(app.audio.loadCalls, 0);
});

test("apresenta exactamente os títulos já formatados pelo serviço nativo", () => {
  const app = createHarness();
  const examples = [
    ["Jardim À Beira Do Mar", "Jardim À Beira Do Mar"],
    ["Meu Deus E Fiel", "Meu Deus E Fiel"],
    ["Grande É o Senhor", "Grande É o Senhor"],
    ["Ação De Graças", "Ação De Graças"],
    ["Águas vivas", "Águas vivas"],
    ["  Título recebido sem alteração  ", "Título recebido sem alteração"],
    ["", "Rádio Palavra Antiga"]
  ];
  examples.forEach(([input, expected]) => {
    app.state("PLAYING", { title: input });
    assert.equal(app.title().textContent, expected);
  });
  assert.doesNotMatch(bridgeSource, /function\s+formatTitle\s*\(/);
});

test("estados do botão usam uma única camada luminosa e não pintam a imagem", () => {
  const app = createHarness({ existingGlow: true });
  const expected = new Map([
    ["STOPPED", "rpa-stopped"],
    ["PAUSED", "rpa-stopped"],
    ["CONNECTING", "rpa-connecting"],
    ["BUFFERING", "rpa-connecting"],
    ["RECONNECTING", "rpa-connecting"],
    ["PLAYING", "rpa-playing"],
    ["ERROR", "rpa-error"]
  ]);

  expected.forEach((className, state) => {
    app.state(state);
    assert.equal(app.button().classList.contains(className), true, state);
    assert.equal(app.button().querySelectorAll(".rpa-btn-glow").length, 1);
    assert.equal(app.image().classList.contains(className), false);
  });
});

test("o botão arranca em amarelo imediato e pára também durante ligação", () => {
  const app = createHarness();
  app.state("STOPPED");
  assert.equal(app.button().disabled, false);

  app.button().dispatch("click");
  assert.deepEqual(app.messages, ["GET_STATE", "PLAY"]);
  assert.equal(app.button().classList.contains("rpa-connecting"), true);
  assert.equal(app.legacy.clicks, 0);

  app.state("CONNECTING");
  assert.equal(app.button().disabled, false);
  app.button().dispatch("click");
  assert.deepEqual(app.messages, ["GET_STATE", "PLAY", "STOP"]);
  assert.equal(app.button().classList.contains("rpa-stopped"), true);
});

test("o disco, o braço e a agulha seguem apenas o estado nativo", () => {
  const app = createHarness();
  const disc = app.document.getElementById("vinylDisc");
  const tonearm = app.document.getElementById("tonearm");
  const shadow = app.document.getElementById("needleShadow");

  app.state("PLAYING");
  assert.equal(disc.classList.contains("vinyl-spin"), true);
  assert.equal(tonearm.classList.contains("on"), true);
  assert.equal(shadow.style.opacity, "1");

  app.state("STOPPED");
  assert.equal(disc.classList.contains("vinyl-spin"), false);
  assert.equal(tonearm.classList.contains("on"), false);
  assert.equal(shadow.style.opacity, "0");
});

test("modo inactivo suspende animações e retira o disco da rotação", () => {
  const app = createHarness();
  const disc = app.document.getElementById("vinylDisc");

  app.state("PLAYING");
  assert.equal(disc.classList.contains("vinyl-spin"), true);
  app.window.__RPA_SET_ACTIVE(false);
  assert.equal(disc.classList.contains("vinyl-spin"), false);
  assert.equal(app.document.documentElement.classList.contains(
    "rpa-runtime-paused"), true);

  const css = app.document.getElementById("rpa-native-styles").textContent;
  assert.match(css, /animation-play-state:paused!important/);

  app.window.__RPA_SET_ACTIVE(true);
  assert.equal(disc.classList.contains("vinyl-spin"), true);
});

test("capa inválida regressa ao logótipo oficial", () => {
  const app = createHarness();
  app.state("PLAYING", {
    title: "cântico_02_novo",
    artwork: "https://radio.palavraantiga.org/capa.jpg"
  });
  assert.equal(app.artwork().getAttribute("src"),
    "https://radio.palavraantiga.org/capa.jpg");

  app.state("PLAYING", { artwork: "http://example.org/capa.jpg" });
  assert.equal(app.artwork().getAttribute("src"),
    "https://palavraantiga.org/web/image/website/1/logo/512x512");
});

test("a ponte não cria artista/estado e usa animações leves", () => {
  const app = createHarness();
  assert.equal(app.document.querySelectorAll(".rpa-native-artist").length, 0);
  assert.equal(app.document.querySelectorAll(".rpa-native-status").length, 0);

  const css = app.document.getElementById("rpa-native-styles").textContent;
  assert.match(css, /\.46s ease-in-out/);
  assert.match(css, /1\.8s ease-in-out/);
  assert.match(css, /\.22s ease-in-out/);
  assert.doesNotMatch(css, /drop-shadow\s*\(/);
  assert.doesNotMatch(css, /:has\s*\(/);
  assert.doesNotMatch(bridgeSource, /new\s+MutationObserver/);
  assert.doesNotMatch(bridgeSource, /offsetHeight/);
});

test("reinjectar a ponte mantém um único botão e pede o estado real", () => {
  const app = createHarness();
  app.state("STOPPED");
  vm.runInContext(bridgeSource, app.context, { filename: "rpa_bridge.js" });

  assert.deepEqual(app.messages, ["GET_STATE", "GET_STATE"]);
  assert.equal(app.button().querySelectorAll(".rpa-btn-glow").length, 1);
  app.button().dispatch("click");
  assert.deepEqual(app.messages, ["GET_STATE", "GET_STATE", "PLAY"]);
});

test("ignora estados desconhecidos sem bloquear o leitor", () => {
  const app = createHarness();
  app.state("STOPPED", { title: "Música Boa" });
  app.state("UNKNOWN", { title: "Não Deve Mudar" });
  assert.equal(app.title().textContent, "Música Boa");
  assert.equal(app.button().classList.contains("rpa-stopped"), true);
});

test("a área Música é comandada pela navegação nativa permanente", () => {
  assert.match(bridgeSource, /window\.__RPA_SHOW_MUSIC\s*=/);
  assert.match(bridgeSource, /window\.__RPA_SHOW_RADIO\s*=/);
  assert.doesNotMatch(bridgeSource, /rpa-music-launcher/);
  assert.match(bridgeSource, /notifyNavigation\("RADIO"\)/);
});

test("a área Música separa playlists oficiais das playlists pessoais", () => {
  assert.match(bridgeSource, /window\.__RPA_OFFICIAL_PLAYLISTS/);
  assert.match(bridgeSource, /window\.__RPA_UPDATE_OFFICIAL_PLAYLISTS/);
  assert.match(bridgeSource, /data-view='official'/);
  assert.match(bridgeSource, /data-open-official/);
  assert.match(bridgeSource, /data-open-personal/);
  assert.match(bridgeSource, /tracksForOfficialPlaylist/);
  assert.doesNotMatch(bridgeSource, /AZURACAST_API_KEY|X-API-Key/);
  assert.match(bridgeSource, /action:\s*"SYNC_LIBRARY"/);
  assert.match(bridgeSource, /stopProgressTimer/);
  assert.match(bridgeSource, /clearInterval\(progressTimer\)/);
});

test("cada faixa pode pedir música sem misturar o pedido com o play", () => {
  assert.match(bridgeSource, /\/api\/station\/palavraantiga\/requests/);
  assert.match(bridgeSource, /data-request='1'/);
  assert.match(bridgeSource, /showRequestModal/);
  assert.match(bridgeSource, /submitSelectedRequest/);
  assert.match(bridgeSource, /method:\s*"POST"/);
  assert.match(bridgeSource, /Confirmar pedido/);
  assert.doesNotMatch(bridgeSource, /NAV_REQUESTS/);
});

 test("a ponte não altera um navegador ou PWA sem canal nativo", () => {
   const window = {};
   const context = vm.createContext({window});
   vm.runInContext(bridgeSource, context);
   assert.equal(window.__RPA_BRIDGE_INSTALLED, undefined);
 });
