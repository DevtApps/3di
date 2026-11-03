// Poliedros convexos de faces planas (low poly): o casco convexo de uma nuvem de pontos.
// A forma guarda os planos das faces (para o SDF e o shader: a distância é o maior afastamento
// entre os planos) e os polígonos das faces (para a malha direta, que sai exata no GLB).
import { ScriptError } from './parser.js';

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

// Casco convexo por força bruta (até 64 pontos): cada trinca define um plano; ele é face se todos
// os pontos ficam do mesmo lado. Faces coplanares viram um polígono só, em ordem anti-horária vista
// de fora. Devolve { pts, planes: [[nx, ny, nz, d]], faces: [[índices]] } ou lança ScriptError.
export function convexHull(input, what = 'hull()') {
  const pts = [];
  let ext = 0;
  for (const p of input) for (const q of input) ext = Math.max(ext, Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1]), Math.abs(p[2] - q[2]));
  const eps = Math.max(1e-9, ext * 1e-7);
  for (const p of input) if (!pts.some((q) => Math.abs(p[0] - q[0]) <= eps && Math.abs(p[1] - q[1]) <= eps && Math.abs(p[2] - q[2]) <= eps)) pts.push([...p]);
  if (pts.length < 4) throw new ScriptError(`${what} precisa de pelo menos 4 pontos diferentes`, null);
  const n = pts.length;
  const planes = [];
  const same = (a, b) => Math.abs(a[0] - b[0]) < 1e-6 && Math.abs(a[1] - b[1]) < 1e-6 && Math.abs(a[2] - b[2]) < 1e-6 && Math.abs(a[3] - b[3]) < eps * 10;
  for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) for (let k = j + 1; k < n; k++) {
    let nn = cross(sub(pts[j], pts[i]), sub(pts[k], pts[i]));
    const l = Math.hypot(...nn);
    if (l < eps * eps) continue;
    nn = nn.map((v) => v / l);
    const d = dot(nn, pts[i]);
    let above = false, below = false;
    for (const p of pts) {
      const s = dot(nn, p) - d;
      if (s > eps) above = true;
      else if (s < -eps) below = true;
      if (above && below) break;
    }
    if (above && below) continue;
    const pl = below ? [...nn, d] : [-nn[0], -nn[1], -nn[2], -d];
    if (!planes.some((q) => same(q, pl))) planes.push(pl);
  }
  if (planes.length < 4) throw new ScriptError(`${what}: os pontos precisam formar um volume (não podem estar todos num plano)`, null);
  const faces = planes.map((pl) => {
    const on = [];
    for (let i = 0; i < n; i++) if (Math.abs(dot(pl, pts[i]) - pl[3]) <= eps) on.push(i);
    const c = [0, 1, 2].map((a) => on.reduce((s, i) => s + pts[i][a], 0) / on.length);
    // base do plano: u qualquer perpendicular à normal, v = n x u (ângulo crescente = anti-horário visto de fora)
    const ref = Math.abs(pl[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0];
    let u = cross(pl, ref);
    u = u.map((v) => v / Math.hypot(...u));
    const v = cross(pl, u);
    return on.map((i) => [i, Math.atan2(dot(sub(pts[i], c), v), dot(sub(pts[i], c), u))]).sort((a, b) => a[1] - b[1]).map(([i]) => i);
  });
  return { pts, planes, faces };
}

// pontos de formas redondas com poucos lados (sides=): anéis e polos
export function ringPoints(r, y, sides, phase = 0) {
  const out = [];
  for (let i = 0; i < sides; i++) {
    const a = phase + (i / sides) * 2 * Math.PI;
    out.push([r * Math.cos(a), y, r * Math.sin(a)]);
  }
  return out;
}

export function lowSphere(r, sides) {
  const rings = Math.max(2, Math.round(sides / 2));
  const out = [[0, -r, 0], [0, r, 0]];
  for (let k = 1; k < rings; k++) {
    const t = -Math.PI / 2 + (k / rings) * Math.PI;
    // anéis alternados giram meio passo: faces em losango, como uma esfera low poly desenhada à mão
    out.push(...ringPoints(r * Math.cos(t), r * Math.sin(t), sides, k % 2 ? 0 : Math.PI / sides));
  }
  return out;
}

// caixa com as 12 arestas chanfradas a 45° (como box(bevel=)): cada canto vira um triângulo
export function chamferBoxPoints(h, c) {
  const out = [];
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
    out.push([sx * h[0], sy * (h[1] - c), sz * (h[2] - c)], [sx * (h[0] - c), sy * h[1], sz * (h[2] - c)], [sx * (h[0] - c), sy * (h[1] - c), sz * h[2]]);
  }
  return out;
}
