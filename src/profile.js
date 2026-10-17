// Perfis 2D (polígonos) para extrude, polygon, star, wedge e lathe: validação dos pontos,
// suavização, distância assinada exata (CPU) e a função GLSL equivalente (GPU).
import { ScriptError } from './parser.js';
import { num } from './runtime.js';

// lista de tuplas (x, y) -> [[x, y], ...]; remove pontos repetidos em sequência
export function parsePoints(v, what, { min = 3, max = 128 } = {}) {
  if (!Array.isArray(v) || v.some((p) => !Array.isArray(p) || p.length !== 2)) {
    throw new ScriptError(`${what} espera uma lista de pontos (x, y), por exemplo [(0, 0), (1, 0), (0.5, 1)]`, null);
  }
  const pts = [];
  v.forEach((p, i) => {
    const q = [num(p[0], `${what}[${i}][0]`), num(p[1], `${what}[${i}][1]`)];
    const last = pts[pts.length - 1];
    if (!last || Math.hypot(q[0] - last[0], q[1] - last[1]) > 1e-9) pts.push(q);
  });
  if (pts.length > 1 && Math.hypot(pts[0][0] - pts[pts.length - 1][0], pts[0][1] - pts[pts.length - 1][1]) < 1e-9) pts.pop();
  if (pts.length < min) throw new ScriptError(`${what} precisa de pelo menos ${min} pontos diferentes`, null);
  if (pts.length > max) throw new ScriptError(`${what} aceita no máximo ${max} pontos (recebeu ${pts.length})`, null, 'use menos pontos ou suavize com smooth=');
  return pts;
}

export function regularPolygon(sides, r) {
  return Array.from({ length: sides }, (_, i) => {
    const a = (i / sides) * 2 * Math.PI;
    return [r * Math.cos(a), r * Math.sin(a)];
  });
}

export function starPoints(n, r, inner) {
  const out = [];
  for (let i = 0; i < n * 2; i++) {
    const a = (i / (n * 2)) * 2 * Math.PI, rr = i % 2 ? inner : r;
    out.push([rr * Math.cos(a), rr * Math.sin(a)]);
  }
  return out;
}

// Catmull-Rom por uma polilinha aberta; n subdivisões por segmento (as pontas ficam onde estão)
export function smoothOpen(pts, n) {
  if (n < 1 || pts.length < 3) return pts;
  const out = [pts[0]];
  const P = (i) => pts[Math.max(0, Math.min(pts.length - 1, i))];
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
    for (let k = 1; k <= n; k++) {
      const t = k / n, t2 = t * t, t3 = t2 * t;
      out.push([0, 1].map((c) => 0.5 * (2 * p1[c] + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2 + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3)));
    }
  }
  return out;
}

// Perfil de revolução (r >= 0, de baixo para cima) -> polígono fechado e simétrico em volta do eixo,
// para a distância nunca "ver" uma aresta falsa sobre o eixo.
export function lathePolygon(profile) {
  const right = profile.map(([r, y]) => [Math.max(0, r), y]);
  const left = [...right].reverse().map(([r, y]) => [-r, y]);
  const all = [...right, ...left];
  const dedup = [];
  for (const p of all) {
    const last = dedup[dedup.length - 1];
    if (!last || Math.hypot(p[0] - last[0], p[1] - last[1]) > 1e-9) dedup.push(p);
  }
  while (dedup.length > 1 && Math.hypot(dedup[0][0] - dedup[dedup.length - 1][0], dedup[0][1] - dedup[dedup.length - 1][1]) < 1e-9) dedup.pop();
  return dedup;
}

export function boundsOf(pts) {
  const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
  return { minX: Math.min(...xs), maxX: Math.max(...xs), minY: Math.min(...ys), maxY: Math.max(...ys) };
}

// Distância assinada a um polígono (exata; negativa dentro). Mesma fórmula do shader.
export function polygonSDF(pts) {
  const n = pts.length;
  return (px, py) => {
    let d = (px - pts[0][0]) ** 2 + (py - pts[0][1]) ** 2;
    let s = 1;
    for (let i = 0, j = n - 1; i < n; j = i, i++) {
      const ex = pts[j][0] - pts[i][0], ey = pts[j][1] - pts[i][1];
      const wx = px - pts[i][0], wy = py - pts[i][1];
      const t = Math.max(0, Math.min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
      const bx = wx - ex * t, by = wy - ey * t;
      d = Math.min(d, bx * bx + by * by);
      const c1 = py >= pts[i][1], c2 = py < pts[j][1], c3 = ex * wy > ey * wx;
      if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
    }
    return s * Math.sqrt(d);
  };
}

// Função GLSL `float name(vec2 p)` com os pontos embutidos como constantes
export function polygonGlsl(name, pts) {
  const f = (x) => { const s = String(+x.toFixed(6)); return /[.e]/.test(s) ? s : `${s}.0`; };
  const n = pts.length;
  return `float ${name}(vec2 p) {
  const vec2 v[${n}] = vec2[${n}](${pts.map((q) => `vec2(${f(q[0])}, ${f(q[1])})`).join(', ')});
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = ${n - 1}; i < ${n}; j = i, i++) {
    vec2 e = v[j] - v[i];
    vec2 w = p - v[i];
    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(b, b));
    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
    if (all(c) || all(not(c))) s = -s;
  }
  return s * sqrt(d);
}`;
}

// Extrusão de uma distância 2D d2 com altura h (centrada em 0) e arredondamento r nas quinas
export function extrudeDist(d2, hz, half, r) {
  const wx = d2 + r, wy = Math.abs(hz) - (half - r);
  return Math.min(Math.max(wx, wy), 0) + Math.hypot(Math.max(wx, 0), Math.max(wy, 0)) - r;
}
