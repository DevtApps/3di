// Sobreposições (overlay) em React + Tailwind sobre a imagem da cena. Os componentes rodam num
// iframe transparente por cima do canvas: o CSS do Tailwind (gerado no navegador) fica isolado da
// IDE (o color-scheme acompanha o do studio: com esquemas diferentes o Chrome pinta o iframe opaco). O palco tem 1920 px de largura lógica (altura pela proporção da imagem) e é escalado para o
// tamanho real, então o mesmo componente fica igual no preview e no vídeo de qualquer resolução.
// Tudo é função do tempo: cada quadro re-renderiza com t/progress (animações CSS não entram no vídeo).
// No vídeo, o palco é rasterizado num SVG (foreignObject) e composto sobre o quadro WebGL.

const STAGE_W = 1920;
const BUILTIN = ['titulo', 'lower_third', 'texto', 'contador', 'lista'];

// ---------- funções de animação para os componentes (import { interpolate } from '3di') ----------
const clamp01 = (x) => Math.min(1, Math.max(0, x));
export const easing = {
  linear: (x) => x,
  in: (x) => x * x,
  out: (x) => 1 - (1 - x) * (1 - x),
  inOut: (x) => (x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x)),
  smooth: (x) => x * x * (3 - 2 * x),
  back: (x) => { const c = 1.70158; return 1 + (c + 1) * (x - 1) ** 3 + c * (x - 1) ** 2; },
  elastic: (x) => (x <= 0 ? 0 : x >= 1 ? 1 : 2 ** (-10 * x) * Math.sin((x * 10 - 0.75) * (2 * Math.PI / 3)) + 1),
};
// interpolate(t, [0, 1], [0, 100], { easing: 'out', clamp: true }): mapeia t entre faixas
export function interpolate(t, input, output, { easing: e = 'linear', clamp = true } = {}) {
  const f = typeof e === 'function' ? e : easing[e] ?? easing.linear;
  let i = 0;
  while (i < input.length - 2 && t > input[i + 1]) i++;
  let x = (t - input[i]) / Math.max(1e-9, input[i + 1] - input[i]);
  if (clamp) x = clamp01(x);
  return output[i] + (output[i + 1] - output[i]) * f(x);
}
// mola amortecida: vai de from a to começando em delay (s)
export function spring(t, { from = 0, to = 1, delay = 0, stiffness = 120, damping = 12, mass = 1 } = {}) {
  const s = Math.max(0, t - delay);
  const w0 = Math.sqrt(stiffness / mass), z = damping / (2 * Math.sqrt(stiffness * mass));
  let x;
  if (z < 1) { const wd = w0 * Math.sqrt(1 - z * z); x = 1 - Math.exp(-z * w0 * s) * (Math.cos(wd * s) + (z * w0 / wd) * Math.sin(wd * s)); }
  else x = 1 - Math.exp(-w0 * s) * (1 + w0 * s);
  return from + (to - from) * x;
}
// entrada e saída: 0 → 1 em `inDur` no começo, 1 → 0 em `outDur` no fim do trecho
export function fade(local, duration, inDur = 0.4, outDur = 0.4) {
  const a = inDur > 0 ? clamp01(local / inDur) : 1;
  const b = outDur > 0 && Number.isFinite(duration) ? clamp01((duration - local) / outDur) : 1;
  return easing.smooth(Math.min(a, b));
}
// máquina de escrever: o texto revelado até `progress` (0..1)
export const typewriter = (text, progress) => String(text).slice(0, Math.round(String(text).length * clamp01(progress)));
const helpers = { interpolate, spring, fade, typewriter, easing, clamp: (x, a = 0, b = 1) => Math.min(b, Math.max(a, x)) };

let libsP = null;
const libs = () => (libsP ??= import(new URL('../../assets/vendor/overlay-libs.js', import.meta.url).href));

// Compila um componente: código de módulo (export default ...) ou só uma expressão/arrow function
function compile(L, code, name) {
  const mod = /\bexport\s+default\b|\bmodule\.exports\b/.test(code) ? code : `export default (${code.trim().replace(/;$/, '')});`;
  let js;
  try { js = L.transform(mod, { transforms: ['jsx', 'imports'], production: true, jsxRuntime: 'classic', filePath: name }).code; }
  catch (e) { throw new Error(`${name}: ${e.message}`); }
  const module = { exports: {} };
  const req = (m) => {
    if (m === 'react') return L.React;
    if (m === '3di' || m === '@3di') return helpers;
    throw new Error(`${name}: só dá para importar 'react' e '3di' (pedido: '${m}')`);
  };
  new Function('require', 'module', 'exports', 'React', ...Object.keys(helpers), js)(req, module, module.exports, L.React, ...Object.values(helpers));
  const C = module.exports.default ?? module.exports;
  if (typeof C !== 'function') throw new Error(`${name}: o componente deve exportar uma função (export default (props) => <div>…</div>)`);
  return C;
}

/**
 * host: elemento sobre o qual o palco fica (o #right do preview).
 * readFile(name): texto de um .jsx ao lado da cena (null se não der para ler).
 * onError(msg): erro de um componente (aparece no status).
 */
export function createOverlays({ host, readFile = async () => null, onError = () => {} }) {
  let frame = null, doc = null, root = null, stage = null, L = null, ready = null;
  let items = [], comps = new Map(), sceneKey = '', fps = 30, duration = 0, lastErr = '';

  const setup = () => (ready ??= (async () => {
    L = await libs();
    frame = document.createElement('iframe');
    frame.className = 'overlay-stage';
    frame.setAttribute('aria-hidden', 'true');
    frame.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;border:0;pointer-events:none;background:transparent';
    const tw = new URL('../../assets/vendor/tailwind-browser.js', import.meta.url).href;
    frame.srcdoc = `<!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="dark"><style>html,body{margin:0;background:transparent;overflow:hidden;color-scheme:dark}#stage{position:absolute;left:0;top:0;transform-origin:0 0;overflow:hidden;font-family:var(--font-sans,ui-sans-serif,system-ui,sans-serif);line-height:1.5;-webkit-font-smoothing:antialiased}</style><script src="${tw}"></script></head><body><div id="stage"></div></body></html>`;
    const loaded = new Promise((r) => frame.addEventListener('load', r, { once: true }));
    host.querySelector('canvas')?.after(frame) ?? host.append(frame);
    await loaded;
    doc = frame.contentDocument;
    stage = doc.getElementById('stage');
    root = L.createRoot(stage);
  })());

  // componente por nome: embutido do 3DI, arquivo .jsx do projeto ou código JSX direto
  async function load(src) {
    if (comps.has(src)) return comps.get(src);
    let code, name = src;
    if (/[<(]/.test(src)) { code = src; name = 'overlay (código)'; }
    else if (BUILTIN.includes(src)) code = await (await fetch(new URL(`../overlays/${src}.jsx`, import.meta.url))).text();
    else if (/\.(jsx|js|tsx)$/i.test(src)) {
      code = await readFile(src);
      if (code === null) throw new Error(`overlay: não consegui ler '${src}' (salve a cena e deixe o .jsx na mesma pasta)`);
    } else throw new Error(`overlay: componente '${src}' não existe; use ${BUILTIN.join(', ')}, um arquivo .jsx ou código JSX`);
    const C = compile(L, code, name);
    comps.set(src, C);
    return C;
  }

  // palco no tamanho (w, h) em pixels reais
  function size(w, h) {
    const s = w / STAGE_W, H = Math.round(h / s);
    stage.style.width = `${STAGE_W}px`;
    stage.style.height = `${H}px`;
    stage.style.transform = `scale(${s})`;
    return H;
  }

  function render(t, w, h) {
    const H = size(w, h);
    const { React } = L;
    const visible = items.filter((o) => t >= o.start && (o.end === null || t < o.end) && o.C).sort((a, b) => a.z - b.z);
    const tree = visible.map((o, i) => {
      const dur = (o.end ?? duration) - o.start, local = t - o.start;
      const props = { ...o.props, t, local, duration: dur, progress: dur > 0 ? clamp01(local / dur) : 1, frame: Math.round(t * fps), fps, width: STAGE_W, height: H };
      return React.createElement(Boundary, { key: `${i}:${o.src}`, name: o.name, onError: report }, React.createElement(o.C, props));
    });
    L.flushSync(() => root.render(React.createElement('div', { style: { position: 'absolute', inset: 0 } }, tree)));
  }

  const report = (msg) => { if (msg !== lastErr) { lastErr = msg; onError(msg); } };
  let Boundary = null;
  const makeBoundary = () => {
    const { React } = L;
    Boundary = class extends React.Component {
      constructor(p) { super(p); this.state = { err: null }; }
      static getDerivedStateFromError(err) { return { err }; }
      componentDidCatch(err) { this.props.onError(`${this.props.name}: ${err.message}`); }
      render() { return this.state.err ? null : this.props.children; }
    };
  };

  // espera o Tailwind terminar de gerar o CSS das classes novas (as builds marcam o performance)
  async function tailwindIdle() {
    const w = frame.contentWindow;
    for (let i = 0; i < 200; i++) {
      await new Promise((r) => setTimeout(r, i ? 5 : 0));
      const m = w.performance.getEntriesByType('mark').map((e) => e.name).filter((n) => /^Build #\d+ \(/.test(n));
      const starts = m.filter((n) => !n.endsWith('(end)')).length, ends = m.length - starts;
      if (starts === ends && i >= 1) return;
    }
  }

  return {
    // cena nova: carrega os componentes usados
    async setScene(scene) {
      const list = scene?.overlays ?? [];
      fps = scene?.fps ?? 30;
      duration = scene?.duration ?? 0;
      const key = JSON.stringify(list.map((o) => o.src));
      if (!list.length && !frame) { items = []; return; }
      await setup();
      if (!Boundary) makeBoundary();
      if (key !== sceneKey) { comps = new Map(); sceneKey = key; }
      lastErr = '';
      const out = [];
      for (const o of list) {
        try { out.push({ ...o, name: /[<(]/.test(o.src) ? 'overlay' : o.src, C: await load(o.src) }); }
        catch (e) { report(e.message); out.push({ ...o, C: null }); }
      }
      items = out;
      frame.hidden = !items.length;
    },
    // recarrega arquivos .jsx (depois de editar o componente)
    reload() { comps = new Map(); sceneKey = ''; },
    // preview: desenha o instante t no tamanho do canvas
    update(t) {
      if (!frame || !items.length) return;
      const r = host.getBoundingClientRect();
      render(t, r.width, r.height);
    },
    has: () => items.length > 0,
    // vídeo: compõe a sobreposição sobre o canvas WebGL (já desenhado no tamanho w x h) num canvas 2D.
    // draw() desenha o WebGL; é chamado só depois da sobreposição estar pronta (sem esperar entre os dois).
    async compose(t, w, h, draw) {
      const out = document.createElement('canvas');
      out.width = w; out.height = h;
      const g = out.getContext('2d');
      let img = null;
      if (frame && items.some((o) => t >= o.start && (o.end === null || t < o.end))) {
        render(t, w, h);
        await tailwindIdle();
        img = await rasterize(w, h);
      }
      const gl = draw();
      g.drawImage(gl, 0, 0, w, h);
      if (img) g.drawImage(img, 0, 0, w, h);
      return out;
    },
  };

  async function rasterize(w, h) {
    const css = [...doc.querySelectorAll('style')].map((s) => s.textContent).join('\n');
    const html = new XMLSerializer().serializeToString(stage);
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><foreignObject x="0" y="0" width="${w}" height="${h}">` +
      `<div xmlns="http://www.w3.org/1999/xhtml" style="position:relative;width:${w}px;height:${h}px;overflow:hidden"><style><![CDATA[${css.replace(/]]>/g, ']]]]><![CDATA[>')}]]></style>${html}</div></foreignObject></svg>`;
    const img = new Image();
    img.decoding = 'sync';
    // data: URL (um blob: com foreignObject "suja" o canvas e o quadro não pode ser lido)
    await new Promise((ok, fail) => { img.onload = ok; img.onerror = () => fail(new Error('não consegui rasterizar a sobreposição')); img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`; });
    return img;
  }
}
