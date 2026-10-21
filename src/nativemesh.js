// Malha direta: transforma a árvore de formas em triângulos sem amostrar a distância numa grade.
//
// A conversão por amostragem (mesh.js) perde o que é mais fino que a célula (lâminas de grama, pontas,
// fios). Mas a maioria das cenas é feita de primitivas com geometria conhecida (caixa, cone, pirâmide,
// esfera, perfis...) só posicionadas e repetidas. Para essas, os triângulos saem exatos da primitiva:
// pontas são pontas, faces planas são planas, e nada some.
//
// Suporta: primitivas sem arredondamento, transformações, união simples, material/nome, repeat, mirror e
// polar (como cópias, quando a forma fica de um lado do eixo) e intersect com uma forma de recorte (as
// cópias cujo centro fica fora do recorte são descartadas, como o recorte dos canteiros de grama).
// Qualquer outra coisa (subtração, união suave, deformações, fórmulas, arredondamentos) devolve null e a
// peça é convertida por amostragem.
import { rotMatrix, mul3, mulMV } from './shapes.js';
import { inv3 } from './compiler.js';
import { val0 } from './expr.js';
import { buildDist } from './sdf.js';

const SHARP_COS = Math.cos((40 * Math.PI) / 180);

class Unsupported extends Error {}

// ---------- geometria local das primitivas ----------

// Malha acumulada: posições, normais e índices
function newMesh() { return { P: [], N: [], I: [] }; }
function addVertex(M, p, n) { M.P.push(p[0], p[1], p[2]); M.N.push(n[0], n[1], n[2]); return M.P.length / 3 - 1; }
function faceNormal(a, b, c) {
  const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
  const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
  const l = Math.hypot(...n) || 1;
  return n.map((x) => x / l);
}
// polígono plano (convexo) com normal da face; pts em ordem anti-horária vista de fora
function addFlat(M, pts) {
  const n = faceNormal(pts[0], pts[1], pts[2]);
  const ids = pts.map((p) => addVertex(M, p, n));
  for (let k = 1; k + 1 < ids.length; k++) M.I.push(ids[0], ids[k], ids[k + 1]);
}

// Sólido de revolução em volta de y a partir de um perfil (r, y) de baixo para cima (anti-horário no plano
// r-y). Normais suaves ao longo do perfil, separadas onde o perfil faz quina (mais de 40°).
function revolve(M, profile, seg) {
  const pts = profile.filter((p, i) => i === 0 || Math.hypot(p[0] - profile[i - 1][0], p[1] - profile[i - 1][1]) > 1e-12);
  const nSeg = pts.length - 1;
  if (nSeg < 1) return;
  // normal 2D de cada trecho: direção (dr, dy) girada -90° = (dy, -dr)
  const segN = [];
  for (let i = 0; i < nSeg; i++) {
    const dr = pts[i + 1][0] - pts[i][0], dy = pts[i + 1][1] - pts[i][1], l = Math.hypot(dr, dy) || 1;
    segN.push([dy / l, -dr / l]);
  }
  // normal em cada ponta de cada trecho: média com o vizinho se a curva for suave
  const endN = (i, end) => {
    const n = segN[i];
    const j = end ? i + 1 : i - 1;
    if (j < 0 || j >= nSeg) return n;
    const m = segN[j];
    if (n[0] * m[0] + n[1] * m[1] < SHARP_COS) return n;
    const s = [n[0] + m[0], n[1] + m[1]], l = Math.hypot(...s) || 1;
    return [s[0] / l, s[1] / l];
  };
  for (let i = 0; i < nSeg; i++) {
    const [r0, y0] = pts[i], [r1, y1] = pts[i + 1];
    const n0 = endN(i, false), n1 = endN(i, true);
    const ring0 = [], ring1 = [];
    for (let j = 0; j <= seg; j++) {
      const a = (j / seg) * 2 * Math.PI, c = Math.cos(a), s = Math.sin(a);
      ring0.push(addVertex(M, [r0 * c, y0, r0 * s], [n0[0] * c, n0[1], n0[0] * s]));
      ring1.push(addVertex(M, [r1 * c, y1, r1 * s], [n1[0] * c, n1[1], n1[0] * s]));
    }
    for (let j = 0; j < seg; j++) {
      const a = ring0[j], b = ring0[j + 1], c = ring1[j + 1], d = ring1[j];
      if (r0 > 1e-12) M.I.push(a, d, b);
      if (r1 > 1e-12) M.I.push(b, d, c);
    }
  }
}

function arc(cx, cy, r, a0, a1, steps) {
  const out = [];
  for (let k = 0; k <= steps; k++) { const a = a0 + ((a1 - a0) * k) / steps; out.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]); }
  return out;
}

// triangulação de polígono simples (orelhas); devolve triângulos com índices do polígono, orientação anti-horária
function triangulate(poly) {
  const n = poly.length;
  let area = 0;
  for (let i = 0; i < n; i++) { const a = poly[i], b = poly[(i + 1) % n]; area += a[0] * b[1] - b[0] * a[1]; }
  const idx = [...Array(n).keys()];
  if (area < 0) idx.reverse();
  const tris = [];
  const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  const inside = (p, a, b, c) => cross(a, b, p) > 1e-14 && cross(b, c, p) > 1e-14 && cross(c, a, p) > 1e-14;
  let guard = 0;
  while (idx.length > 3 && guard++ < n * n) {
    let cut = false;
    for (let k = 0; k < idx.length; k++) {
      const i0 = idx[(k + idx.length - 1) % idx.length], i1 = idx[k], i2 = idx[(k + 1) % idx.length];
      const a = poly[i0], b = poly[i1], c = poly[i2];
      if (cross(a, b, c) <= 1e-14) continue;
      if (idx.some((j) => j !== i0 && j !== i1 && j !== i2 && inside(poly[j], a, b, c))) continue;
      tris.push([i0, i1, i2]);
      idx.splice(k, 1);
      cut = true;
      break;
    }
    if (!cut) break;
  }
  if (idx.length === 3) tris.push([idx[0], idx[1], idx[2]]);
  return tris;
}

// Caixa arredondada: uma grade em cada face, com cada ponto projetado na superfície (núcleo da caixa
// encolhido em r + uma casca de raio r). As amostras se concentram nos arredondamentos.
function roundedBox(h, r, seg) {
  const M = newMesh();
  const q = Math.max(3, Math.ceil(seg / 8));
  const samples = (e) => {
    const inner = Math.max(0, e - r), out = [];
    for (let k = q; k >= 1; k--) out.push(-(inner + r * Math.sin((k / q) * Math.PI / 2)));
    out.push(-inner);
    if (inner > 1e-9) out.push(inner);
    for (let k = 1; k <= q; k++) out.push(inner + r * Math.sin((k / q) * Math.PI / 2));
    return out;
  };
  const S = h.map(samples);
  const core = h.map((e) => Math.max(0, e - r));
  const place = (p) => {
    const c = p.map((v, i) => Math.max(-core[i], Math.min(core[i], v)));
    const d = p.map((v, i) => v - c[i]);
    const l = Math.hypot(...d) || 1;
    const n = d.map((v) => v / l);
    return { pos: c.map((v, i) => v + n[i] * r), n };
  };
  // cada face: eixo fixo a com sinal sg, eixos (u, v) escolhidos para a normal apontar para fora
  for (const [a, u, v] of [[0, 1, 2], [1, 2, 0], [2, 0, 1]]) for (const sg of [1, -1]) {
    const ids = [];
    for (let i = 0; i < S[u].length; i++) {
      ids.push([]);
      for (let j = 0; j < S[v].length; j++) {
        const p = [0, 0, 0];
        p[a] = sg * h[a]; p[u] = S[u][i]; p[v] = S[v][j];
        const { pos, n } = place(p);
        ids[i].push(addVertex(M, pos, n));
      }
    }
    for (let i = 0; i + 1 < S[u].length; i++) for (let j = 0; j + 1 < S[v].length; j++) {
      const A = ids[i][j], B = ids[i + 1][j], C = ids[i + 1][j + 1], D = ids[i][j + 1];
      if (sg > 0) M.I.push(A, B, C, A, C, D); else M.I.push(A, C, B, A, D, C);
    }
  }
  return M;
}

function primitive(s, seg) {
  const P = s.props, M = newMesh();
  switch (s.kind) {
    case 'box': {
      if (P.r > 1e-9) return roundedBox(P.size.map((v) => v / 2), P.r, seg);
      const [x, y, z] = P.size.map((v) => v / 2);
      const c = (sx, sy, sz) => [sx * x, sy * y, sz * z];
      addFlat(M, [c(1, -1, -1), c(1, 1, -1), c(1, 1, 1), c(1, -1, 1)]);
      addFlat(M, [c(-1, -1, 1), c(-1, 1, 1), c(-1, 1, -1), c(-1, -1, -1)]);
      addFlat(M, [c(-1, 1, -1), c(-1, 1, 1), c(1, 1, 1), c(1, 1, -1)]);
      addFlat(M, [c(-1, -1, 1), c(-1, -1, -1), c(1, -1, -1), c(1, -1, 1)]);
      addFlat(M, [c(-1, -1, 1), c(1, -1, 1), c(1, 1, 1), c(-1, 1, 1)]);
      addFlat(M, [c(1, -1, -1), c(-1, -1, -1), c(-1, 1, -1), c(1, 1, -1)]);
      return M;
    }
    case 'pyramid': {
      const w = P.w / 2, y0 = -P.h / 2, apex = [0, P.h / 2, 0];
      const b = [[-w, y0, -w], [w, y0, -w], [w, y0, w], [-w, y0, w]];
      for (let k = 0; k < 4; k++) addFlat(M, [b[(k + 1) % 4], b[k], apex]);
      addFlat(M, [b[0], b[1], b[2], b[3]]);
      return M;
    }
    case 'prism': {
      const w = P.w / 2, h = P.h / 2, d = P.d / 2;
      const f = [[-w, -h, d], [w, -h, d], [0, h, d]], k = [[-w, -h, -d], [w, -h, -d], [0, h, -d]];
      addFlat(M, f);
      addFlat(M, [k[0], k[2], k[1]]);
      addFlat(M, [k[0], k[1], f[1], f[0]]);
      addFlat(M, [f[1], k[1], k[2], f[2]]);
      addFlat(M, [k[0], f[0], f[2], k[2]]);
      return M;
    }
    case 'sphere': revolve(M, arc(0, 0, P.r, -Math.PI / 2, Math.PI / 2, Math.ceil(seg / 2)), seg); return M;
    case 'ellipsoid': {
      // esfera unitária; a escala dos raios vai na transformação (as normais são corrigidas lá)
      revolve(M, arc(0, 0, 1, -Math.PI / 2, Math.PI / 2, Math.ceil(seg / 2)), seg);
      M.scale = P.radii;
      return M;
    }
    case 'cylinder': {
      const h = P.h / 2, rr = Math.min(P.round, P.r, h);
      if (rr > 1e-9) {
        // perfil com um quarto de círculo em cada quina
        const q = Math.max(3, Math.ceil(seg / 8));
        revolve(M, [[0, -h], ...arc(P.r - rr, -h + rr, rr, -Math.PI / 2, 0, q), ...arc(P.r - rr, h - rr, rr, 0, Math.PI / 2, q), [0, h]], seg);
      } else revolve(M, [[0, -h], [P.r, -h], [P.r, h], [0, h]], seg);
      return M;
    }
    case 'cone': {
      const h = P.h / 2;
      revolve(M, [[0, -h], [P.r, -h], [P.top, h], ...(P.top > 1e-9 ? [[0, h]] : [])], seg);
      return M;
    }
    case 'capsule': {
      const a = P.h / 2 - P.r, q = Math.ceil(seg / 4);
      revolve(M, [...arc(0, -a, P.r, -Math.PI / 2, 0, q), ...arc(0, a, P.r, 0, Math.PI / 2, q)], seg);
      return M;
    }
    case 'torus': {
      const ns = seg, nt = Math.max(8, Math.ceil(seg / 2));
      const id = [];
      for (let i = 0; i <= ns; i++) {
        const u = (i / ns) * 2 * Math.PI, cu = Math.cos(u), su = Math.sin(u);
        id.push([]);
        for (let j = 0; j <= nt; j++) {
          const v = (j / nt) * 2 * Math.PI, cv = Math.cos(v), sv = Math.sin(v);
          id[i].push(addVertex(M, [(P.R + P.r * cv) * cu, P.r * sv, (P.R + P.r * cv) * su], [cv * cu, sv, cv * su]));
        }
      }
      for (let i = 0; i < ns; i++) for (let j = 0; j < nt; j++) M.I.push(id[i][j], id[i][j + 1], id[i + 1][j], id[i + 1][j], id[i][j + 1], id[i + 1][j + 1]);
      return M;
    }
    case 'extrude': {
      if (P.r > 1e-9) throw new Unsupported('extrude arredondado');
      const h = P.h / 2;
      // perfil (u, v) -> 3D: eixo z: (u, v, ±h); eixo y: (u, ±h, v)
      const at = (q, side) => (P.axis === 'z' ? [q[0], q[1], side * h] : [q[0], side * h, q[1]]);
      const poly = P.pts;
      let area = 0;
      for (let i = 0; i < poly.length; i++) { const a = poly[i], b = poly[(i + 1) % poly.length]; area += a[0] * b[1] - b[0] * a[1]; }
      const ccw = area > 0 ? poly : [...poly].reverse();
      // no eixo y, (u, v) vira (x, z): a orientação vista de cima se inverte
      const flip = P.axis === 'y';
      const tris = triangulate(ccw);
      for (const [a, b, c] of tris) {
        const top = [at(ccw[a], 1), at(ccw[b], 1), at(ccw[c], 1)], bot = [at(ccw[a], -1), at(ccw[c], -1), at(ccw[b], -1)];
        addFlat(M, flip ? [top[0], top[2], top[1]] : top);
        addFlat(M, flip ? [bot[0], bot[2], bot[1]] : bot);
      }
      for (let i = 0; i < ccw.length; i++) {
        const a = ccw[i], b = ccw[(i + 1) % ccw.length];
        const quad = [at(a, -1), at(b, -1), at(b, 1), at(a, 1)];
        addFlat(M, flip ? [quad[0], quad[3], quad[2], quad[1]] : quad);
      }
      return M;
    }
    case 'lathe': {
      if (!P.profile) throw new Unsupported('lathe sem perfil');
      const prof = P.profile;
      const full = [...(prof[0][0] > 1e-9 ? [[0, prof[0][1]]] : []), ...prof, ...(prof.at(-1)[0] > 1e-9 ? [[0, prof.at(-1)[1]]] : [])];
      revolve(M, full, seg);
      return M;
    }
  }
  throw new Unsupported(s.kind);
}

// ---------- árvore -> instâncias ----------

const IDENT = [1, 0, 0, 0, 1, 0, 0, 0, 1];
const det3 = (m) => m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6]);

/**
 * Coleta { s (primitiva), m, t } de toda a árvore, ou lança Unsupported.
 * limit: orçamento opcional de instâncias; excedê-lo produz erro explícito.
 */
function collect(shape, limit) {
  const out = [];
  const visit = (s, m, t) => {
    if (out.length > limit) throw new Error('A malha direta excedeu o orçamento explícito de instâncias; a qualidade não foi reduzida.');
    const P = s.props, c0 = s.children[0];
    switch (s.kind) {
      case 'translate': { const v = P.v.map(val0); const mv = mulMV(m, v); return visit(c0, m, t.map((x, i) => x + mv[i])); }
      case 'rotate': return visit(c0, mul3(m, P.angles ? rotMatrix(...P.angles.map(val0)) : P.m), t);
      case 'scale': { const k = P.s.map(val0); return visit(c0, mul3(m, [k[0], 0, 0, 0, k[1], 0, 0, 0, k[2]]), t); }
      case 'affine': { const mv = mulMV(m, P.t); return visit(c0, mul3(m, P.m), t.map((x, i) => x + mv[i])); }
      case 'paint': if (P.relief) throw new Unsupported('paint com relevo'); return visit(c0, m, t);
      case 'material': case 'label': case 'bound': return visit(c0, m, t);
      case 'union':
        if (P.k) throw new Unsupported('união suave');
        for (const c of s.children) visit(c, m, t);
        return;
      case 'repeat': {
        const sp = P.s.map((x, i) => (P.n[i] > 1 ? x : 1)), h = P.n.map((n) => (n - 1) / 2);
        for (let i = 0; i < P.n[0]; i++) for (let j = 0; j < P.n[1]; j++) for (let k = 0; k < P.n[2]; k++) {
          const off = mulMV(m, [(i - h[0]) * sp[0], (j - h[1]) * sp[1], (k - h[2]) * sp[2]]);
          visit(c0, m, t.map((x, q) => x + off[q]));
        }
        return;
      }
      case 'mirror': {
        // o espelho dobra o espaço: equivale a cópias só se a forma estiver toda de um lado de cada eixo
        const b = c0.bbox;
        P.axes.forEach((on, a) => { if (on && b.min[a] < -1e-6 && b.max[a] > 1e-6) throw new Unsupported('mirror cruzando o eixo'); });
        const flips = [[1, 1, 1]];
        P.axes.forEach((on, a) => { if (on) for (const f of [...flips]) { const g = [...f]; g[a] = -1; flips.push(g); } });
        for (const f of flips) visit(c0, mul3(m, [f[0], 0, 0, 0, f[1], 0, 0, 0, f[2]]), t);
        return;
      }
      case 'polar': {
        // cópias em volta de y; a forma precisa caber num setor (como no shader)
        const b = c0.bbox, sec = (2 * Math.PI) / P.n;
        const angs = [[b.min[0], b.min[2]], [b.max[0], b.min[2]], [b.min[0], b.max[2]], [b.max[0], b.max[2]]].map(([x, z]) => Math.atan2(z, x));
        if (b.min[0] <= 0 || Math.max(...angs.map(Math.abs)) > sec / 2 + 1e-6) throw new Unsupported('polar fora do setor');
        for (let k = 0; k < P.n; k++) visit(c0, mul3(m, rotMatrix(0, (-k * 360) / P.n, 0)), t);
        return;
      }
      case 'intersect': {
        // recorte: mantém as cópias do primeiro filho cujo centro fica dentro dos demais (canteiros de grama)
        if (P.k) throw new Unsupported('interseção suave');
        const start = out.length;
        visit(c0, m, t);
        const clips = s.children.slice(1).map((c) => buildDist(c));
        const mi = inv3(m);
        const kept = out.splice(start).filter((it) => {
          const b = it.s.bbox;
          const cl = [0, 1, 2].map((i) => (b.min[i] + b.max[i]) / 2);
          const w = mulMV(it.m, cl).map((x, i) => x + it.t[i]);
          const local = mulMV(mi, w.map((x, i) => x - t[i]));
          return clips.every((d) => d(local[0], local[1], local[2]) <= 0);
        });
        out.push(...kept);
        return;
      }
    }
    if (s.children.length) throw new Unsupported(s.kind);
    out.push({ s, m, t });
  };
  visit(shape, IDENT, [0, 0, 0]);
  if (out.length > limit) throw new Error('A malha direta excedeu o orçamento explícito de instâncias; a qualidade não foi reduzida.');
  return out;
}

/**
 * Malha direta de uma forma: { positions, normals, indices } (Float32Array/Uint32Array) ou null se
 * alguma parte da árvore não tem tesselação direta. seg = segmentos nas formas redondas.
 * maxTriangles/maxInstances são orçamentos opcionais; não reduzem a qualidade silenciosamente.
 */
export function nativeMesh(shape, { seg = 32, maxTriangles = Infinity, maxInstances = Infinity } = {}) {
  let items;
  try { items = collect(shape, maxInstances); } catch (e) { if (e instanceof Unsupported) return null; throw e; }
  if (!items.length) return null;
  // tessela cada tipo/tamanho uma vez e reaproveita para as cópias
  const cache = new Map();
  const local = (s) => {
    const key = s;
    let g = cache.get(key);
    if (!g) {
      try { g = primitive(s, seg); } catch (e) { if (e instanceof Unsupported) return null; throw e; }
      cache.set(key, g);
    }
    return g;
  };
  let tris = 0;
  const geoms = [];
  for (const it of items) {
    const g = local(it.s);
    if (!g) return null;
    tris += g.I.length / 3;
    if (tris > maxTriangles) throw new Error('A malha direta excedeu o orçamento explícito de triângulos; a qualidade não foi reduzida.');
    geoms.push(g);
  }
  const nv = geoms.reduce((n, g) => n + g.P.length / 3, 0);
  const positions = new Float32Array(nv * 3), normals = new Float32Array(nv * 3), indices = new Uint32Array(tris * 3);
  let vo = 0, io = 0;
  items.forEach((it, k) => {
    const g = geoms[k];
    const m = g.scale ? mul3(it.m, [g.scale[0], 0, 0, 0, g.scale[1], 0, 0, 0, g.scale[2]]) : it.m;
    const mi = inv3(m);
    // normais: inversa transposta (escalas não uniformes) e orientação invertida se a matriz espelha
    const flip = det3(m) < 0;
    const base = vo;
    for (let v = 0; v < g.P.length; v += 3) {
      const p = mulMV(m, [g.P[v], g.P[v + 1], g.P[v + 2]]);
      positions[vo * 3] = p[0] + it.t[0]; positions[vo * 3 + 1] = p[1] + it.t[1]; positions[vo * 3 + 2] = p[2] + it.t[2];
      const n = [g.N[v], g.N[v + 1], g.N[v + 2]];
      const nn = [mi[0] * n[0] + mi[3] * n[1] + mi[6] * n[2], mi[1] * n[0] + mi[4] * n[1] + mi[7] * n[2], mi[2] * n[0] + mi[5] * n[1] + mi[8] * n[2]];
      const l = Math.hypot(...nn) || 1;
      normals[vo * 3] = nn[0] / l; normals[vo * 3 + 1] = nn[1] / l; normals[vo * 3 + 2] = nn[2] / l;
      vo++;
    }
    for (let i = 0; i < g.I.length; i += 3) {
      indices[io++] = base + g.I[i];
      indices[io++] = base + (flip ? g.I[i + 2] : g.I[i + 1]);
      indices[io++] = base + (flip ? g.I[i + 1] : g.I[i + 2]);
    }
  });
  return { positions, normals, indices, instances: items.length };
}
