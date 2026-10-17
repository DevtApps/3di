// Editor + visualizador: compila o script a cada edição e renderiza.
import { ScriptError } from './parser.js';
import { Renderer } from './renderer.js';
import { fmtNum } from './runtime.js';
import { sceneTask } from './ide/tasks.js';
import { createGlbPreview } from './ide/glbpreview.js';
import { createEditor } from './ide/editor.js';
import { createFiles } from './ide/files.js';
import { connectBridge } from './ide/bridge.js';
import { setupWorkspace } from './ide/workspace.js';
import { createReference } from './ide/reference.js';

const EXAMPLES = ['boneco', 'animacao', 'materiais', 'vila', 'pinguim', 'gato', 'cachorro', 'robo', 'cemiterio', 'arvore', 'mesa', 'basico', 'castelo', 'organico', 'templo', 'grama', 'campo', 'gramas', 'gramas-estilos', 'plantas', 'arvores', 'arvores-estilos', 'pessoas', 'pessoas-poses', 'veiculos', 'veiculos-estilos', 'formas', 'formulas'];
const STORAGE_KEY = '3di.code';
const TEMPLATE = `# Nova cena 3DI. Digite e veja ao lado; Ctrl+Espaço sugere funções.
chao = plane().color("lightgray")
objeto = box(1, round=0.05).color("red").ground().name("objeto")

show(chao, objeto)
`;

const $ = (id) => document.getElementById(id);
const status = $('status'), canvas = $('view'), partsEl = $('parts');
setupWorkspace();

let renderer;
try {
  renderer = new Renderer(canvas);
} catch (e) {
  status.className = 'err';
  status.textContent = e.message;
  throw e;
}

// ---------- câmera orbital ----------

const cam = { target: [0, 0.5, 0], yaw: 0.6, pitch: 0.35, dist: 4, fov: 45 };
let sceneInfo = { bbox: { min: [-1, 0, -1], max: [1, 1, 1] }, hasPlane: false, scene: null };
let lastCameraKey = null;

function radiusOf(b) {
  return Math.max(0.05, 0.5 * Math.hypot(b.max[0] - b.min[0], b.max[1] - b.min[1], b.max[2] - b.min[2]));
}

// ângulos prontos da câmera (yaw em volta de y, pitch acima do horizonte)
const PRESETS = {
  front: { yaw: 0, pitch: 0.1, label: 'frente' },
  back: { yaw: Math.PI, pitch: 0.1, label: 'trás' },
  right: { yaw: Math.PI / 2, pitch: 0.1, label: 'direita' },
  left: { yaw: -Math.PI / 2, pitch: 0.1, label: 'esquerda' },
  top: { yaw: 0, pitch: 1.5, label: 'topo' },
  perspective: { yaw: 0.6, pitch: 0.38, label: 'perspectiva' },
};

// caixa da cena para enquadrar: com chão, ignora o que fica abaixo dele
function sceneBox() {
  const b = sceneInfo.bbox;
  return sceneInfo.hasPlane && b.max[1] > 0.05 ? { min: [b.min[0], Math.max(0, b.min[1]), b.min[2]], max: b.max } : b;
}

function partBox(name) {
  const p = sceneInfo.parts?.find((q) => q.name === name);
  if (!p) {
    const names = sceneInfo.parts?.map((q) => q.name).join(', ');
    throw new Error(`peça '${name}' não existe${names ? `; peças: ${names}` : ' (dê nomes com .name("..."))'}`);
  }
  return p.bbox;
}

// enquadra a caixa b; view = nome de PRESETS ou null para manter o ângulo atual
function frameBox(b, view = 'perspective') {
  const p = PRESETS[view];
  if (view && !p) throw new Error(`vista desconhecida '${view}'; use ${Object.keys(PRESETS).join(', ')}`);
  cam.target = [0, 1, 2].map((i) => (b.min[i] + b.max[i]) / 2);
  cam.dist = (radiusOf(b) / Math.sin((cam.fov * Math.PI) / 360)) * 1.05;
  if (p) { cam.yaw = p.yaw; cam.pitch = p.pitch; }
  requestRender();
}

function frame() { frameBox(sceneBox(), 'perspective'); }

function describeCam() {
  const r = (a) => `(${a.map((x) => +x.toFixed(3)).join(', ')})`;
  return `câmera em ${r(eye())} olhando para ${r(cam.target)}, fov ${cam.fov}°`;
}

function applyScriptCamera(c) {
  const b = sceneInfo.bbox;
  const look = c.look ?? [0, 1, 2].map((i) => (b.min[i] + b.max[i]) / 2);
  const d = c.pos.map((v, i) => v - look[i]);
  cam.target = look;
  cam.dist = Math.max(0.01, Math.hypot(...d));
  cam.yaw = Math.atan2(d[0], d[2]);
  cam.pitch = Math.asin(Math.max(-1, Math.min(1, d[1] / cam.dist)));
  cam.fov = c.fov;
}

function eye() {
  const cp = Math.cos(cam.pitch);
  return [
    cam.target[0] + cam.dist * cp * Math.sin(cam.yaw),
    cam.target[1] + cam.dist * Math.sin(cam.pitch),
    cam.target[2] + cam.dist * cp * Math.cos(cam.yaw),
  ];
}

// ---------- render sob demanda ----------

let pending = false, interacting = false, settleTimer = null;

// Resolução adaptativa em degraus fixos. Mudar a escala redimensiona o canvas (realoca o
// framebuffer e limpa a imagem), então ela só troca de degrau com a média de vários quadros
// e no máximo a cada ~0,6 s; antes ela variava todo quadro, o que deixava cada quadro mais
// lento, prendia a escala no mínimo e fazia a imagem piscar entre nítida e pixelada.
function adaptiveScale(levels, start) {
  let i = Math.max(0, levels.indexOf(start)), avg = 0, last = 0, since = 0;
  return {
    get value() { return levels[i]; },
    reset() { last = 0; avg = 0; },
    frame(now) {
      const dt = last ? now - last : 0;
      last = now;
      if (dt <= 0 || dt > 250) return levels[i]; // pausa, aba oculta: não conta
      avg = avg ? avg * 0.85 + dt * 0.15 : dt;
      since += dt;
      if (since < 600) return levels[i];
      // custo estimado no próximo degrau acima ~ proporcional à área
      const up = i > 0 ? avg * (levels[i - 1] / levels[i]) ** 2 : Infinity;
      if (avg > 40 && i < levels.length - 1) { i++; since = 0; avg = 0; }
      else if (up < 28) { i--; since = 0; avg = 0; }
      return levels[i];
    },
  };
}

// animação: o relógio só anda enquanto a cena usa time e não está pausada
const anim = { on: false, playing: true, time: 0, last: 0, res: adaptiveScale([1, 0.75, 0.5, 0.35], 1) };

function animLoop(now) {
  if (!anim.on) return;
  const dt = anim.last ? (now - anim.last) / 1000 : 0;
  anim.last = now;
  if (anim.playing) {
    anim.time += Math.min(dt, 0.1);
    // durante a interação usa o degrau da interação, sem disputar a mesma média
    if (interacting) draw(interactRes.frame(now));
    else { interactRes.reset(); draw(anim.res.frame(now)); }
  }
  requestAnimationFrame(animLoop);
}

function setAnimated(on) {
  $('btnPlay').hidden = !on;
  if (on && !anim.on) {
    anim.on = true;
    anim.last = 0;
    requestAnimationFrame(animLoop);
  }
  anim.on = on;
}

// Resolução durante a interação (girar, mover, zoom): degraus de 75% a 22% da tela.
// Ao soltar, volta à resolução cheia.
const interactRes = adaptiveScale([0.75, 0.5, 0.35, 0.22], 0.5);

function requestRender() {
  if (anim.on && anim.playing) return;
  if (pending) return;
  pending = true;
  requestAnimationFrame((now) => {
    pending = false;
    if (interacting) draw(interactRes.frame(now));
    else { interactRes.reset(); draw(1); }
  });
}

// opts.size = [w, h] desenha numa resolução fixa; opts.time sobrepõe o relógio da animação
function draw(scale, opts = {}) {
  const sc = sceneInfo.scene;
  const r = radiusOf(sceneInfo.bbox);
  // opts.view = { eye, target, fov } desenha de outro ângulo sem mexer na câmera do editor
  const v = opts.view;
  const dist = v ? Math.hypot(v.eye[0] - v.target[0], v.eye[1] - v.target[1], v.eye[2] - v.target[2]) : cam.dist;
  // névoa padrão proporcional à distância da câmera: só some com o horizonte do chão
  const fog = sc?.fog ?? (sceneInfo.hasPlane ? 1 / (Math.max(dist, r, 1) * 14) : 0);
  renderer.render({
    eye: v ? v.eye : eye(),
    target: v ? v.target : cam.target,
    fov: v ? v.fov : cam.fov,
    fog,
    maxDist: sceneInfo.hasPlane ? Math.max(80, dist * 30) : dist + r * 4,
    sun: sc?.sun?.dir ?? [0.6, 1, 0.4],
    sunColor: sc?.sun?.color ?? [1, 0.95, 0.88],
    sky: sc?.sky ?? [0.3, 0.5, 0.82],
    light: sc?.light,
    time: opts.time ?? anim.time,
    size: opts.size,
    // raios de sombra mais curtos enquanto a câmera se move
    shadowSteps: interacting && !opts.size ? 28 : 80,
  }, scale);
}

// ---------- vistas (frente, lado, topo, perspectiva) ----------

const AXIS_FOV = 30; // fov estreito nas vistas de eixo: quase ortográfico, sem ficar longe demais

// Câmeras das 4 vistas, enquadradas pela bbox da cena. Nas vistas de eixo a distância parte
// da face mais próxima, que é a que aparece maior na perspectiva.
function viewCameras(b) {
  const c = [0, 1, 2].map((i) => (b.min[i] + b.max[i]) / 2);
  const s = [0, 1, 2].map((i) => Math.max(0.05, b.max[i] - b.min[i]));
  const fit = (w, h, depth) => depth / 2 + (Math.max(w, h) / 2) * 1.15 / Math.tan((AXIS_FOV * Math.PI) / 360);
  return [
    { label: 'FRENTE (de +z)', axes: '→ +x   ↑ +y', yaw: 0, pitch: 0, dist: fit(s[0], s[1], s[2]), fov: AXIS_FOV },
    { label: 'LADO (de +x)', axes: '→ −z   ↑ +y', yaw: Math.PI / 2, pitch: 0, dist: fit(s[2], s[1], s[0]), fov: AXIS_FOV },
    { label: 'TOPO (de +y)', axes: '→ +x   ↓ +z', yaw: 0, pitch: Math.PI / 2, dist: fit(s[0], s[2], s[1]), fov: AXIS_FOV },
    { label: 'PERSPECTIVA', axes: '', yaw: 0.6, pitch: 0.38, dist: (radiusOf(b) / Math.sin((45 * Math.PI) / 360)) * 1.05, fov: 45 },
  ].map((v) => ({ ...v, target: c }));
}

// Caixa usada para enquadrar as vistas. Em cenas animadas, roda o script de novo com o
// layout no instante t (a bbox normal é a de t = 0). Com chão, ignora o que fica abaixo dele.
async function viewBBox(time) {
  let b = sceneInfo.bbox;
  if (anim.on && time) {
    try { b = (await sceneTask('compile', sceneInfo.src, { time }).promise).out.bbox; } catch {}
  }
  if (sceneInfo.hasPlane && b.max[1] > 0.05) b = { min: [b.min[0], Math.max(0, b.min[1]), b.min[2]], max: b.max };
  return b;
}

// Desenha as 4 vistas numa grade 2x2 (quadros de size px) com rótulos; devolve um canvas 2D.
async function renderViews({ size = 512, time = anim.time, bbox = null } = {}) {
  const b = bbox ?? await viewBBox(time);
  const out = document.createElement('canvas');
  out.width = out.height = size * 2;
  const g = out.getContext('2d');
  const saved = { ...cam };
  const fs = Math.max(11, Math.round(size / 32));
  const tag = (text, x, y, alignRight = false) => {
    g.font = `600 ${fs}px system-ui, sans-serif`;
    const w = g.measureText(text).width + fs;
    const x0 = alignRight ? x - w : x;
    g.fillStyle = 'rgba(15,17,22,.72)';
    g.fillRect(x0, y, w, fs * 1.7);
    g.fillStyle = '#fff';
    g.fillText(text, x0 + fs / 2, y + fs * 1.22);
  };
  try {
    viewCameras(b).forEach((v, i) => {
      Object.assign(cam, { target: v.target, yaw: v.yaw, pitch: v.pitch, dist: v.dist, fov: v.fov });
      draw(1, { size: [size, size], time });
      const x = (i % 2) * size, y = Math.floor(i / 2) * size;
      g.drawImage(canvas, 0, 0, size, size, x, y, size, size);
      tag(v.label, x + 8, y + 8);
      if (v.axes) tag(v.axes, x + 8, y + size - fs * 1.7 - 8);
    });
  } finally {
    Object.assign(cam, saved);
  }
  const dims = [0, 1, 2].map((i) => fmtNum(+(b.max[i] - b.min[i]).toFixed(3)));
  tag(`bbox ${dims.join(' × ')} m${anim.on ? ` · t = ${time.toFixed(2)} s` : ''}`, size * 2 - 8, size * 2 - fs * 1.7 - 8, true);
  g.strokeStyle = 'rgba(0,0,0,.6)';
  g.lineWidth = 2;
  g.beginPath();
  g.moveTo(size, 0); g.lineTo(size, size * 2);
  g.moveTo(0, size); g.lineTo(size * 2, size);
  g.stroke();
  // devolve o canvas da cena ao tamanho da tela
  draw(1);
  return out;
}

function interact() {
  interacting = true;
  clearTimeout(settleTimer);
  settleTimer = setTimeout(() => { interacting = false; requestRender(); }, 140);
  requestRender();
}

let drag = null;
canvas.addEventListener('contextmenu', (e) => e.preventDefault());
canvas.addEventListener('pointerdown', (e) => {
  canvas.setPointerCapture(e.pointerId);
  drag = { x: e.clientX, y: e.clientY, pan: e.button === 2 || e.shiftKey };
});
canvas.addEventListener('pointermove', (e) => {
  if (!drag) return;
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
  drag.x = e.clientX;
  drag.y = e.clientY;
  if (drag.pan) {
    const k = (cam.dist * 1.6) / canvas.clientHeight;
    const right = [Math.cos(cam.yaw), 0, -Math.sin(cam.yaw)];
    const sp = Math.sin(cam.pitch), cp = Math.cos(cam.pitch);
    const up = [-sp * Math.sin(cam.yaw), cp, -sp * Math.cos(cam.yaw)];
    cam.target = cam.target.map((v, i) => v - right[i] * dx * k + up[i] * dy * k);
  } else {
    cam.yaw -= dx * 0.008;
    cam.pitch = Math.max(-1.5, Math.min(1.5, cam.pitch + dy * 0.008));
  }
  interact();
});
canvas.addEventListener('pointerup', () => { drag = null; });
canvas.addEventListener('wheel', (e) => {
  e.preventDefault();
  cam.dist *= Math.exp(e.deltaY * 0.001);
  interact();
}, { passive: false });
canvas.addEventListener('dblclick', frame);
new ResizeObserver(() => requestRender()).observe(canvas);

// ---------- compilação ----------

function setError(err) {
  status.className = 'err';
  status.textContent = err instanceof ScriptError ? `✗ ${err.toString()}` : `✗ ${err.message}`;
  editor.setError(err.line ? err : null);
}

function markLine() {
  editor.setError(null);
}

let compileId = 0, compileTask = null;

// Executa o script e compila a cena. O shader compila em segundo plano; a cena anterior
// fica na tela até o novo ficar pronto. Devolve uma promise com o texto final do status.
async function compile() {
  const id = ++compileId;
  const src = editor.getValue();
  try { localStorage.setItem(STORAGE_KEY, src); } catch {}
  const t0 = performance.now();
  compileTask?.cancel();
  compileTask = sceneTask('compile', src);
  let result;
  try { result = await compileTask.promise; }
  catch (e) {
    if (id === compileId && e.name !== 'AbortError') setError(e);
    return status.textContent;
  }
  if (id !== compileId) return status.textContent;
  const { out, logs: scriptLogs, scene } = result;
  const logs = scriptLogs.map((l) => `› ${l}`).join('\n');
  const tScript = performance.now() - t0;
  const summary = `${out.leaves} primitivas${out.instances ? ` (${out.instances} em BVH)` : ''} · script ${tScript.toFixed(0)} ms`;
  const pending = setTimeout(() => {
    if (id !== compileId) return;
    markLine(null);
    status.className = 'ok';
    status.textContent = `⧗ ${summary} · compilando shader…`;
  }, 60);
  let tShader;
  try {
    tShader = await renderer.setScene(out.glsl, out.data);
  } catch (e) {
    clearTimeout(pending);
    console.error(e.message);
    if (id === compileId) setError(new Error('erro interno no shader (veja o console)'));
    return status.textContent;
  }
  clearTimeout(pending);
  // substituída por uma edição mais nova, ou um erro de script apareceu enquanto compilava
  if (tShader === null || id !== compileId) return status.textContent;

  sceneInfo = { bbox: out.bbox, hasPlane: out.hasPlane, scene, src, parts: out.parts, animated: out.animated, leaves: out.leaves };
  const camKey = JSON.stringify(scene.camera);
  if (scene.camera && camKey !== lastCameraKey) applyScriptCamera(scene.camera);
  else if (lastCameraKey === null) frame();
  lastCameraKey = camKey;

  setAnimated(out.animated);
  markLine(null);
  status.className = 'ok';
  status.textContent = `✓ ${summary}${tShader ? ` · shader ${tShader.toFixed(0)} ms` : ''}${out.animated ? ' · animado' : ''}`;
  if (logs) {
    const el = document.createElement('div');
    el.className = 'log';
    el.textContent = logs;
    status.appendChild(el);
  }
  const v = (a) => a.map(fmtNum).join(', ');
  partsEl.innerHTML = out.parts.length
    ? out.parts.map((p, i) => {
      const sz = p.bbox.max.map((x, k) => x - p.bbox.min[k]);
      return `<div class="part" data-i="${i}" title="clique para enquadrar"><b>${escapeHtml(p.name)}</b> ${v(sz.map((x) => +x.toFixed(3)))}<br>&nbsp; em ${v(p.bbox.min.map((x) => +x.toFixed(3)))}</div>`;
    }).join('')
    : '<div>nenhuma peça nomeada<br>use .name("...")</div>';
  requestRender();
  return status.textContent;
}

function escapeHtml(s) {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}

// ---------- editor e arquivos ----------

let compileTimer = null;
function scheduleCompile() {
  clearTimeout(compileTimer);
  compileTimer = setTimeout(compile, 350);
}

const editor = await createEditor({
  wrap: $('editorWrap'),
  textarea: $('code'),
  gutter: $('gutter'),
  keys: {
    save: () => files.save(),
    saveAs: () => files.saveAs(),
    open: () => files.open(),
    newFile: () => files.newFile(),
    run: () => { clearTimeout(compileTimer); compile(); },
  },
});

const files = createFiles({
  getText: () => editor.getValue(),
  setText: (t) => { editor.setValue(t); lastCameraKey = null; },
  onOpen: () => compile(),
  template: TEMPLATE,
  onState: ({ name, dirty, where }) => {
    $('fileName').textContent = `${dirty ? '• ' : ''}${name}`;
    $('fileName').title = where ? `salvo em ${where}` : 'ainda não salvo em disco (Ctrl+S para salvar)';
  },
});

editor.onChange(() => { files.changed(); scheduleCompile(); });
document.addEventListener('keydown', (e) => {
  // atalhos fora do editor (com o foco na vista 3D)
  if (!(e.ctrlKey || e.metaKey) || e.target.closest?.('#editorWrap')) return;
  const k = e.key.toLowerCase();
  if (k === 's') { e.preventDefault(); (e.shiftKey ? files.saveAs : files.save)(); }
  if (k === 'o') { e.preventDefault(); files.open(); }
});
addEventListener('beforeunload', (e) => { if (files.state().dirty && files.state().handle) { e.preventDefault(); e.returnValue = ''; } });

// ---------- botões ----------

$('btnFrame').onclick = frame;
$('btnPlay').onclick = () => {
  anim.playing = !anim.playing;
  $('btnPlay').textContent = anim.playing ? '⏸' : '▶';
  anim.last = 0;
  if (!anim.playing) requestRender();
};
$('btnViews').onclick = async () => {
  const box = $('views');
  const img = box.querySelector('img');
  img.src = (await renderViews({ size: 640 })).toDataURL('image/png');
  box.hidden = false;
};
$('views').onclick = () => { $('views').hidden = true; };
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') $('views').hidden = true; });
$('btnParts').onclick = () => partsEl.classList.toggle('show');
const baseName = () => files.state().name.replace(/\.3di$/i, '');

$('btnPng').onclick = () => {
  draw(2 / Math.min(window.devicePixelRatio || 1, 1.5));
  canvas.toBlob(async (blob) => {
    requestRender();
    const name = await files.saveBinary(blob, `${baseName()}.png`, 'Imagem PNG', '.png', 'image/png');
    if (name) { status.className = 'ok'; status.textContent = `✓ imagem salva: ${name}`; }
  });
};
$('btnNew').onclick = () => files.newFile();
$('btnOpen').onclick = () => files.open();
$('btnSave').onclick = () => files.save();
document.querySelectorAll('#camBar [data-view]').forEach((b) => {
  b.onclick = () => frameBox(sceneBox(), b.dataset.view);
});
partsEl.addEventListener('click', (e) => {
  const el = e.target.closest('.part');
  if (el) frameBox(sceneInfo.parts[+el.dataset.i].bbox, null);
});

$('btnGlb').onclick = () => {
  const code = editor.getValue();
  status.className = 'ok';
  status.textContent = '⧗ gerando malhas para o .glb…';
  // deixa o status aparecer antes do trabalho pesado
  setTimeout(async () => {
    try {
      const { glb, stats } = await sceneTask('export', code, { res: 128 }).promise;
      const name = await files.saveBinary(new Blob([glb], { type: 'model/gltf-binary' }), `${baseName()}.glb`, 'Modelo glTF binário', '.glb', 'model/gltf-binary');
      if (!name) { status.textContent = 'exportação cancelada'; return; }
      status.textContent = `✓ ${name}: ${(stats.bytes / 1024).toFixed(0)} KB · ${stats.parts} partes · ${stats.triangles} triângulos` +
        `${stats.bones ? ` · ${stats.bones} ossos` : ''}${stats.animated ? ' · animado' : ''} · ${(stats.ms / 1000).toFixed(1)} s` +
        stats.warnings.map((w) => `\naviso: ${w}`).join('');
    } catch (e) {
      console.error(e);
      setError(new Error(`erro ao exportar: ${e.message}`));
    }
  }, 30);
};

// ---------- Conferir GLB: o resultado do export ao lado do shader ----------

// o shader num ângulo qualquer, para comparar com a malha exportada (a câmera do editor não muda)
async function renderShaderAt(view, w, h) {
  draw(1, { size: [w, h], view });
  const out = document.createElement('canvas');
  out.width = w; out.height = h;
  out.getContext('2d').drawImage(canvas, 0, 0);
  draw(1);
  return out.toDataURL('image/png');
}

const glbCheck = createGlbPreview({
  getView: () => ({ eye: eye(), target: [...cam.target], fov: cam.fov }),
  getSun: () => sceneInfo.scene?.sun?.dir ?? [0.6, 1, 0.4],
  getTime: () => anim.time,
  getCode: () => editor.getValue(),
  renderShader: renderShaderAt,
  saveGlb: async (glb) => {
    const name = await files.saveBinary(new Blob([glb], { type: 'model/gltf-binary' }), `${baseName()}.glb`, 'Modelo glTF binário', '.glb', 'model/gltf-binary');
    if (name) { status.className = 'ok'; status.textContent = `✓ ${name} salvo`; }
  },
});
$('btnGlbCheck').onclick = () => glbCheck.open();

const sel = $('examples');
sel.innerHTML = '<option value="">exemplos…</option>' + EXAMPLES.map((n) => `<option>${n}</option>`).join('');
sel.onchange = async () => {
  if (!sel.value) return;
  await loadExample(sel.value);
  sel.value = '';
};

async function loadExample(name) {
  if (files.state().dirty && !confirm(`Descartar as alterações em ${files.state().name}?`)) return null;
  const res = await fetch(`examples/${name}.3di`);
  files.loadUntitled(`${name}.3di`, await res.text());
  clearTimeout(compileTimer);
  return compile();
}

// API mínima para automação (testes, agentes): window.tdi.load(src) / .shot()
window.tdi = {
  load(src) { editor.setValue(src); lastCameraKey = null; clearTimeout(compileTimer); return compile(); },
  view(yaw, pitch, dist) { Object.assign(cam, { yaw, pitch, dist: dist ?? cam.dist }); draw(1); },
  // pausa a animação num instante (s) e desenha
  at(t) { anim.playing = false; anim.time = t; draw(1); },
  status: () => status.textContent,
  // diagnóstico: resolução usada durante a interação (0.22 a 0.75)
  interactScale: () => interactRes.value,
  animScale: () => anim.res.value,
  glbCheck,
  reference: () => reference,
  // grade 2x2 com frente, lado, topo e perspectiva (PNG em data URL); t fixa o instante da animação
  async views({ size = 512, t } = {}) { return (await renderViews({ size, time: t ?? anim.time })).toDataURL('image/png'); },
  // tempo médio de um quadro em resolução cheia (ms)
  bench(n = 5) {
    const gl = renderer.gl, px = new Uint8Array(4);
    const sync = () => gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
    draw(1);
    sync();
    const t0 = performance.now();
    for (let i = 0; i < n; i++) { draw(1); sync(); }
    return +((performance.now() - t0) / n).toFixed(1);
  },
};

// ---------- ponte com o MCP (agentes de IA controlam esta vista) ----------

const shot = () => canvas.toDataURL('image/png').split(',')[1];
const reference = createReference({ host: $('right'), button: $('btnRef'), getShot: () => { draw(1); return shot(); } });
connectBridge({
  getScript: () => editor.getValue(),
  setScript: ({ code }) => window.tdi.load(code),
  // salva no arquivo aberto; sem arquivo ligado ao disco, pede para o usuário escolher no editor
  save: async () => {
    const st = files.state();
    if (!st.handle && !st.path) throw new Error(`'${st.name}' ainda não tem lugar no disco: use Salvar no editor para escolher onde salvar`);
    await files.save();
    return `salvo: ${st.path ?? st.name}`;
  },
  fileState: () => ({ path: files.state().path, dirty: files.state().dirty }),
  openScene: ({ path, name, text }) => { files.loadFile({ path, name, text }); compile(); return { opened: path }; },
  detachScene: () => { files.detach(); return { detached: true }; },
  parts: () => {
    const r = (a) => `(${a.map((x) => +x.toFixed(3)).join(', ')})`;
    const ps = sceneInfo.parts ?? [];
    return [
      `${sceneInfo.leaves ?? 0} primitivas${sceneInfo.animated ? `, animada (t = ${anim.time.toFixed(2)} s, ${anim.playing ? 'tocando' : 'pausada'})` : ''}`,
      `cena: de ${r(sceneInfo.bbox.min)} até ${r(sceneInfo.bbox.max)}`,
      ...(ps.length ? ps.map((p) => `  ${p.name}: tamanho ${r(p.bbox.max.map((x, i) => x - p.bbox.min[i]))}, de ${r(p.bbox.min)} até ${r(p.bbox.max)}`) : ['  (nenhuma peça nomeada)']),
      describeCam(),
    ].join('\n');
  },
  // imagem de referência por cima da vista; data = PNG/JPEG em base64
  setReference: ({ data, mime = 'image/png', opacity, scale, x, y, side }) => {
    const opts = Object.fromEntries(Object.entries({ opacity, scale, x, y, side }).filter(([, v]) => v !== undefined && v !== null));
    if (data) opts.src = `data:${mime};base64,${data}`;
    reference.set(opts);
    return `referência ${data ? 'definida' : 'ajustada'}: ${JSON.stringify(reference.state())}`;
  },
  compareReference: async () => ({ png: await reference.compare(), info: `referência | cena | sobreposição; ${describeCam()}` }),
  setCamera: ({ pos, look, fov }) => {
    applyScriptCamera({ pos, look: look ?? null, fov: fov ?? cam.fov });
    requestRender();
    return describeCam();
  },
  frame: ({ target, view }) => {
    frameBox(target ? partBox(target) : sceneBox(), view ?? 'perspective');
    return `enquadrado ${target ? `'${target}'` : 'a cena'}${view ? ` (${PRESETS[view].label})` : ''}; ${describeCam()}`;
  },
  setTime: ({ time, playing }) => {
    if (typeof time === 'number') { anim.time = time; if (playing === undefined) anim.playing = false; }
    if (typeof playing === 'boolean') anim.playing = playing;
    $('btnPlay').textContent = anim.playing ? '⏸' : '▶';
    anim.last = 0;
    draw(1);
    return `t = ${anim.time.toFixed(2)} s, ${anim.playing ? 'tocando' : 'pausada'}${anim.on ? '' : ' (a cena não usa time)'}`;
  },
  // exporta, abre o painel Conferir GLB e devolve a imagem da malha + o relatório por peça
  glbCheck: async ({ res = 128, style = 'solid', mode = 'glb' } = {}) => {
    await glbCheck.open(Number(res) || 128);
    const report = glbCheck.reportText();
    if (!glbCheck.hasModel()) throw new Error(report);
    return { png: await glbCheck.capture({ style, mode: mode === 'split' ? 'split' : mode }), report };
  },
  screenshot: async ({ view = 'current', target, time }) => {
    const t = time ?? anim.time;
    if (view === 'grid') {
      const png = (await renderViews({ size: 512, time: t, bbox: target ? partBox(target) : null })).toDataURL('image/png').split(',')[1];
      return { png, info: `4 vistas${target ? ` de '${target}'` : ''}${anim.on ? `, t = ${t.toFixed(2)} s` : ''}` };
    }
    const saved = { ...cam };
    try {
      if (view !== 'current' || target) frameBox(target ? partBox(target) : sceneBox(), view === 'current' ? null : view);
      draw(1, { time: t });
      return { png: shot(), info: `vista ${view}${target ? ` de '${target}'` : ''}${anim.on ? `, t = ${t.toFixed(2)} s` : ''}; ${describeCam()}` };
    } finally {
      Object.assign(cam, saved);
      draw(1);
    }
  },
}, (on) => {
  $('mcpState').classList.toggle('on', on);
  $('bridgeLabel').textContent = on ? 'Ponte ativa' : 'Ponte offline';
  $('mcpState').title = on ? 'ponte do editor conectada; confira o estado do agente externo no próprio cliente' : 'sem servidor MCP (rode node tools/mcp.mjs ou o app 3DI)';
});

// ---------- início: arquivo da linha de comando, rascunho salvo ou exemplo ----------

let saved = null;
try { saved = localStorage.getItem(STORAGE_KEY); } catch {}
if (await files.openFromHash()) compile();
else if (saved) { files.loadUntitled('sem título.3di', saved); compile(); }
else loadExample(EXAMPLES[0]);
