import { Renderer } from '../src/renderer.js';
import './preview.css';

declare function acquireVsCodeApi(): { postMessage(message: unknown): void; getState(): any; setState(state: unknown): void };
const vscode = acquireVsCodeApi();
const canvas = document.getElementById('view') as HTMLCanvasElement;
const status = document.getElementById('status')!;
const parts = document.getElementById('parts')!;
let renderer: Renderer;
let scene: any;
let loading: Promise<unknown> = Promise.resolve();
let renderFailed: Error | undefined;
let sequence = 0;
const cam = { target: [0, 0.5, 0], yaw: 0.6, pitch: 0.38, dist: 4, fov: 45 };
const previous = vscode.getState();
if (previous?.camera) Object.assign(cam, previous.camera);
let playing = true, time = 0, last = 0;
const views: Record<string, [number, number]> = {
  front: [0, 0], back: [Math.PI, 0], left: [-Math.PI / 2, 0], right: [Math.PI / 2, 0], top: [0, Math.PI / 2], perspective: [0.6, 0.38],
};
function box(target?: string) {
  if (target) {
    const part = scene?.out.parts.find((p: any) => p.name === target);
    if (!part) throw new Error(`Peça '${target}' não encontrada`);
    return part.bbox;
  }
  return scene?.out.bbox ?? { min: [-1, 0, -1], max: [1, 1, 1] };
}
function frame(view = 'perspective', target?: string) {
  const b = box(target);
  cam.target = b.min.map((v: number, i: number) => (v + b.max[i]) / 2);
  cam.dist = Math.max(0.3, Math.hypot(...b.max.map((v: number, i: number) => v - b.min[i])) * 1.5);
  if (views[view]) [cam.yaw, cam.pitch] = views[view];
  cam.fov = 45;
  persist(); draw();
}
function persist() { vscode.setState({ camera: cam }); }
let pendingDraw = false, interacting = false;
let settleTimer: ReturnType<typeof setTimeout>;
function navigate() {
  interacting = true; clearTimeout(settleTimer);
  settleTimer = setTimeout(() => { if (!drag) { interacting = false; persist(); draw(); } }, 180);
  draw();
}
function draw(size?: [number, number], t = time) {
  if (size) { renderFrame(size, t, true); return; }
  if (pendingDraw) return;
  pendingDraw = true;
  requestAnimationFrame(() => { pendingDraw = false; renderFrame(); });
}
function renderFrame(size?: [number, number], t = time, capture = false) {
  if (!renderer || !scene) return;
  const b = box();
  const radius = Math.max(1, Math.hypot(...b.max.map((v: number, i: number) => v - b.min[i])));
  const cp = Math.cos(cam.pitch);
  const rendered = renderer.render({
    eye: [cam.target[0] + cam.dist * cp * Math.sin(cam.yaw), cam.target[1] + cam.dist * Math.sin(cam.pitch), cam.target[2] + cam.dist * cp * Math.cos(cam.yaw)],
    target: cam.target, fov: cam.fov,
    fog: scene.scene.fog ?? (scene.out.hasPlane ? 1 / (Math.max(cam.dist, radius) * 14) : 0),
    maxDist: scene.out.hasPlane ? Math.max(80, cam.dist * 30) : cam.dist + radius * 4,
    sun: scene.scene.sun?.dir ?? [0.6, 1, 0.4], sunColor: scene.scene.sun?.color ?? [1, 0.95, 0.88],
    sky: scene.scene.sky ?? [0.3, 0.5, 0.82], time: t, size, capture, interactive: interacting, animated: scene.out.animated && playing,
  }, interacting && !capture ? 0.5 : 1);
  if (rendered === false) draw();
}
function setCamera({ pos, look, fov }: any) {
  cam.target = look ?? cam.target;
  const d = pos.map((v: number, i: number) => v - cam.target[i]);
  cam.dist = Math.max(0.01, Math.hypot(...d));
  cam.yaw = Math.atan2(d[0], d[2]); cam.pitch = Math.asin(Math.max(-1, Math.min(1, d[1] / cam.dist)));
  cam.fov = fov ?? cam.fov; persist(); draw();
}
function screenshot({ view = 'current', target, time: t = time }: any) {
  const saved = { ...cam, target: [...cam.target] };
  try {
    if (view === 'grid') {
      const out = document.createElement('canvas'); out.width = out.height = 1024;
      const ctx = out.getContext('2d')!;
      ['front', 'right', 'top', 'perspective'].forEach((v, i) => {
        frame(v, target); renderFrame([512, 512], t, true);
        const x = (i % 2) * 512, y = Math.floor(i / 2) * 512;
        ctx.drawImage(canvas, x, y); ctx.fillStyle = '#111b'; ctx.fillRect(x, y, 150, 30);
        ctx.fillStyle = '#fff'; ctx.font = '14px sans-serif'; ctx.fillText(['Frente', 'Lado', 'Topo', 'Perspectiva'][i], x + 10, y + 21);
      });
      return { png: out.toDataURL('image/png').split(',')[1] };
    }
    if (view !== 'current' || target) frame(view === 'current' ? 'perspective' : view, target);
    renderFrame(undefined, t, true);
    return { png: canvas.toDataURL('image/png').split(',')[1] };
  } finally { Object.assign(cam, saved); persist(); draw(); }
}
async function request(command: string, args: any) {
  await loading;
  if (renderFailed) throw renderFailed;
  if (!scene) throw new Error('Nenhuma cena compilada');
  switch (command) {
    case 'screenshot': return screenshot(args);
    case 'setCamera': setCamera(args); return cam;
    case 'frame': frame(args.view, args.target); return cam;
    case 'setTime':
      if (args.time !== undefined) { time = args.time; if (args.playing === undefined) playing = false; }
      if (args.playing !== undefined) playing = args.playing;
      draw(); return { time, playing };
    default: throw new Error(`Comando desconhecido: ${command}`);
  }
}
try { renderer = new Renderer(canvas); }
catch (cause) { status.textContent = (cause as Error).message; vscode.postMessage({ type: 'renderError', message: status.textContent }); }
window.addEventListener('message', ({ data: msg }) => {
  if (msg.type === 'scene') {
    const id = ++sequence;
    loading = (async () => {
      try {
        if (!renderer) throw new Error('WebGL2 não disponível');
        const result = msg.result;
        const data = result.out.data;
        if (data) { data.inst = new Float32Array(data.inst); data.bvh = new Float32Array(data.bvh); }
        const compiled = await renderer.setScene(result.out.glsl, data);
        if (id !== sequence || compiled === null) return;
        const first = !scene; const oldCamera = JSON.stringify(scene?.scene.camera);
        scene = result; renderFailed = undefined;
        if (result.scene.camera && oldCamera !== JSON.stringify(result.scene.camera)) setCamera(result.scene.camera);
        else if (first && !previous?.camera) frame();
        status.textContent = `✓ ${result.out.leaves} primitivas${result.out.animated ? ' · animado' : ''}${result.logs.length ? ' · ' + result.logs.join(' · ') : ''}`;
        parts.replaceChildren();
        for (const part of result.out.parts) {
          const button = document.createElement('button');
          const dimensions = part.bbox.max.map((v: number, i: number) => +(v - part.bbox.min[i]).toFixed(3));
          button.textContent = `${part.name} · ${dimensions.join(' × ')} m`;
          button.onclick = () => frame('perspective', part.name); parts.append(button);
        }
        document.getElementById('play')!.hidden = !result.out.animated;
        draw(); vscode.postMessage({ type: 'rendered', primitives: result.out.leaves });
      } catch (cause) {
        renderFailed = cause as Error; status.textContent = renderFailed.message;
        vscode.postMessage({ type: 'renderError', message: renderFailed.message });
      }
    })();
  }
  if (msg.type === 'error') status.textContent = `Erro: ${msg.message}`;
  if (msg.type === 'request') void request(msg.command, msg.args).then((result) => vscode.postMessage({ type: 'reply', id: msg.id, result }), (error) => vscode.postMessage({ type: 'reply', id: msg.id, error: error.message }));
});
document.querySelectorAll<HTMLButtonElement>('[data-view]').forEach((b) => { b.onclick = () => frame(b.dataset.view); });
for (const [id, command] of Object.entries({ code: 'showCode', focus: 'previewOnly', png: 'exportPng', glb: 'exportGlb', integrations: 'integrations' })) {
  document.getElementById(id)!.onclick = () => vscode.postMessage({ type: 'command', command });
}
document.getElementById('play')!.onclick = () => {
  playing = !playing; document.getElementById('play')!.textContent = playing ? 'Pausar' : 'Reproduzir';
};
let drag: { x: number; y: number; pan: boolean } | undefined;
canvas.oncontextmenu = (e) => e.preventDefault();
canvas.onpointerdown = (e) => { navigate(); canvas.setPointerCapture(e.pointerId); drag = { x: e.clientX, y: e.clientY, pan: e.button === 2 || e.shiftKey }; };
canvas.onpointermove = (e) => {
  if (!drag) return;
  const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
  drag.x = e.clientX; drag.y = e.clientY;
  if (drag.pan) {
    const k = cam.dist * 1.6 / Math.max(1, canvas.clientHeight);
    const right = [Math.cos(cam.yaw), 0, -Math.sin(cam.yaw)];
    const up = [-Math.sin(cam.pitch) * Math.sin(cam.yaw), Math.cos(cam.pitch), -Math.sin(cam.pitch) * Math.cos(cam.yaw)];
    cam.target = cam.target.map((v, i) => v - right[i] * dx * k + up[i] * dy * k);
  } else { cam.yaw -= dx * 0.008; cam.pitch = Math.max(-1.5, Math.min(1.5, cam.pitch + dy * 0.008)); }
  navigate();
};
canvas.onpointerup = canvas.onpointercancel = canvas.onlostpointercapture = () => { drag = undefined; navigate(); };
canvas.addEventListener('wheel', (e) => { e.preventDefault(); cam.dist = Math.max(0.02, Math.min(100000, cam.dist * Math.exp(Math.max(-1000, Math.min(1000, e.deltaY)) * 0.001))); navigate(); }, { passive: false });
canvas.ondblclick = () => frame();
new ResizeObserver(() => draw()).observe(canvas);
function tick(now: number) {
  if (scene?.out.animated && playing) { time += last ? Math.min((now - last) / 1000, 0.1) : 0; draw(); }
  last = now; requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
vscode.postMessage({ type: 'ready' });
