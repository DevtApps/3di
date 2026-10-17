// Avaliador do SDF em JavaScript (espelho do GLSL gerado em compiler.js), usado para
// gerar malhas na exportação. Cada forma vira uma closure:
//   buildDist(s, t)(x, y, z) -> distância
//   buildMat(s, t)(x, y, z)  -> { d, c, rough, metal, glow } com a textura já aplicada
import { center } from './shapes.js';
import { isExpr, val0 } from './expr.js';
import { rotMatrix, texOffset } from './shapes.js';
import { splitScene, inv3 } from './compiler.js';
import { polygonSDF, extrudeDist } from './profile.js';

const at = (v, t) => (isExpr(v) ? v.eval(t) : v);
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const mix = (a, b, h) => a + (b - a) * h;
const fract = (x) => x - Math.floor(x);
const len3 = (x, y, z) => Math.sqrt(x * x + y * y + z * z);

// ---------- primitivas ----------

function sdBox(px, py, pz, bx, by, bz) {
  const qx = Math.abs(px) - bx, qy = Math.abs(py) - by, qz = Math.abs(pz) - bz;
  return len3(Math.max(qx, 0), Math.max(qy, 0), Math.max(qz, 0)) + Math.min(Math.max(qx, qy, qz), 0);
}
function sdCyl(px, py, pz, r, h) {
  const dx = Math.hypot(px, pz) - r, dy = Math.abs(py) - h;
  return Math.min(Math.max(dx, dy), 0) + Math.hypot(Math.max(dx, 0), Math.max(dy, 0));
}
function sdCone(px, py, pz, h, r1, r2) {
  const qx = Math.hypot(px, pz), qy = py;
  const k1x = r2, k1y = h, k2x = r2 - r1, k2y = 2 * h;
  const cax = qx - Math.min(qx, qy < 0 ? r1 : r2), cay = Math.abs(qy) - h;
  const tt = clamp(((k1x - qx) * k2x + (k1y - qy) * k2y) / (k2x * k2x + k2y * k2y), 0, 1);
  const cbx = qx - k1x + k2x * tt, cby = qy - k1y + k2y * tt;
  const s = cbx < 0 && cay < 0 ? -1 : 1;
  return s * Math.sqrt(Math.min(cax * cax + cay * cay, cbx * cbx + cby * cby));
}
function sdTorus(px, py, pz, R, r) { return Math.hypot(Math.hypot(px, pz) - R, py) - r; }
function sdCapsule(px, py, pz, r, a) { return len3(px, py - clamp(py, -a, a), pz) - r; }
function sdEllipsoid(px, py, pz, rx, ry, rz) {
  const k0 = len3(px / rx, py / ry, pz / rz), k1 = len3(px / (rx * rx), py / (ry * ry), pz / (rz * rz));
  return k1 > 0 ? (k0 * (k0 - 1)) / k1 : -Math.min(rx, ry, rz);
}
function sdPyramid(px, py, pz, h) {
  const m2 = h * h + 0.25;
  px = Math.abs(px); pz = Math.abs(pz);
  if (pz > px) [px, pz] = [pz, px];
  px -= 0.5; pz -= 0.5;
  const qx = pz, qy = h * py - 0.5 * px, qz = h * px + 0.5 * py;
  const s = Math.max(-qx, 0);
  const t = clamp((qy - 0.5 * pz) / (m2 + 0.25), 0, 1);
  const a = m2 * (qx + s) * (qx + s) + qy * qy;
  const b = m2 * (qx + 0.5 * t) * (qx + 0.5 * t) + (qy - m2 * t) * (qy - m2 * t);
  const d2 = Math.min(qy, -qx * m2 - qy * 0.5) > 0 ? 0 : Math.min(a, b);
  return Math.sqrt((d2 + qz * qz) / m2) * Math.sign(Math.max(qz, -py));
}
function sdTriIso(px, py, qx, qy) {
  px = Math.abs(px);
  const ta = clamp((px * qx + py * qy) / (qx * qx + qy * qy), 0, 1);
  const ax = px - qx * ta, ay = py - qy * ta;
  const tb = clamp(px / qx, 0, 1);
  const bx = px - qx * tb, by = py - qy;
  const s = -Math.sign(qy);
  const dx = Math.min(ax * ax + ay * ay, bx * bx + by * by);
  const dy = Math.min(s * (px * qy - py * qx), s * (py - qy));
  return -Math.sqrt(dx) * Math.sign(dy);
}
function sdPrism(px, py, pz, hw, h, hd) {
  const wx = sdTriIso(px, h * 0.5 - py, hw, h), wy = Math.abs(pz) - hd;
  return Math.min(Math.max(wx, wy), 0) + Math.hypot(Math.max(wx, 0), Math.max(wy, 0));
}
function smin(a, b, k) { const h = clamp(0.5 + (0.5 * (b - a)) / k, 0, 1); return mix(b, a, h) - k * h * (1 - h); }
function smax(a, b, k) { return -smin(-a, -b, k); }

// ---------- ruído e texturas (mesmas fórmulas do shader) ----------

function hash31(x, y, z) {
  x = fract(x * 0.3183099 + 0.1) * 17; y = fract(y * 0.3183099 + 0.2) * 17; z = fract(z * 0.3183099 + 0.3) * 17;
  return fract(x * y * z * (x + y + z));
}
function vnoise(x, y, z) {
  const ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
  let fx = x - ix, fy = y - iy, fz = z - iz;
  fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy); fz = fz * fz * (3 - 2 * fz);
  const h = (a, b, c) => hash31(ix + a, iy + b, iz + c);
  return mix(mix(mix(h(0, 0, 0), h(1, 0, 0), fx), mix(h(0, 1, 0), h(1, 1, 0), fx), fy),
    mix(mix(h(0, 0, 1), h(1, 0, 1), fx), mix(h(0, 1, 1), h(1, 1, 1), fx), fy), fz);
}
export function fbm(x, y, z) {
  let a = 0.5, s = 0;
  for (let i = 0; i < 5; i++) {
    s += a * vnoise(x, y, z);
    x = x * 2.02 + 1.7; y = y * 2.02 + 9.2; z = z * 2.02 + 3.1;
    a *= 0.5;
  }
  return s / 0.96875;
}
const smoothstep = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };
const mix3 = (a, b, h) => [mix(a[0], b[0], h), mix(a[1], b[1], h), mix(a[2], b[2], h)];

// Mesmas fórmulas do shader: texField devolve [fator de mistura, variação por tijolo]
function planar(k, gx, gy, s) {
  if (k === 4) return [fract(gy / s) >= 0.5 ? 1 : 0, 0];
  if (k === 5) return [(((Math.floor(gx / s + 0.5) + Math.floor(gy / s + 0.5)) % 2) + 2) % 2, 0];
  const bh = s * 0.4;
  const row = Math.floor(gy / bh + 0.02);
  const u = gx / s + 0.5 * (((row % 2) + 2) % 2);
  const cx = fract(u) * s, cy = fract(gy / bh + 0.02) * bh;
  const mortar = Math.min(s, bh) * 0.08;
  return [cx >= mortar && cy >= mortar ? 0 : 1, hash31(Math.floor(u), row, 3)];
}

function texField(p, k, s, axis, n) {
  // eixo principal vira y (como axisY no shader)
  const q = axis < 0.5 ? [p[1], p[0], p[2]] : axis < 1.5 ? p : [p[0], p[2], p[1]];
  if (k === 1) return [smoothstep(0.3, 0.75, fbm(p[0] / s, p[1] / s, p[2] / s)), 0];
  if (k === 2) {
    const nx = fbm(q[0] / s, (q[1] * 0.08) / s, q[2] / s) - 0.5;
    const nz = fbm(q[0] / s + 7, (q[1] * 0.08) / s + 7, q[2] / s + 7) - 0.5;
    const r = Math.hypot(q[0] + nx * s * 3, q[2] + nz * s * 3) / s;
    const ring = fract(r) ** 4;
    const grain = fbm((q[0] * 25) / s, q[1] / s, (q[2] * 25) / s);
    return [clamp(ring * 0.75 + (grain - 0.5) * 0.5 + 0.1, 0, 1), 0];
  }
  if (k === 3) {
    const nz = fbm(p[0] / s, p[1] / s, p[2] / s);
    const v = Math.abs(Math.sin(((p[0] + p[1] * 0.6 + p[2] * 0.3) / s) * 1.4 + nz * 7));
    const vein = 1 - smoothstep(0, 0.14, v);
    const soft = smoothstep(0.4, 0.9, fbm((p[0] / s) * 2.3 + 3, (p[1] / s) * 2.3 + 3, (p[2] / s) * 2.3 + 3));
    return [clamp(vein * 0.9 + soft * 0.2, 0, 1), 0];
  }
  if (k === 4 || k === 5 || k === 6) {
    if (axis > 2.5) {
      // triplanar: sem normal conhecida, cai na projeção do plano y
      const nn = n ?? [0, 1, 0];
      const w = nn.map((c) => Math.abs(c) ** 6);
      const sum = w[0] + w[1] + w[2] + 1e-6;
      const f = [0, 0];
      const add = (r, wt) => { f[0] += r[0] * wt / sum; f[1] += r[1] * wt / sum; };
      if (w[0] / sum > 0.02) add(planar(k, p[2], p[1], s), w[0]);
      if (w[1] / sum > 0.02) add(planar(k, p[0], p[2], s), w[1]);
      if (w[2] / sum > 0.02) add(planar(k, p[0], p[1], s), w[2]);
      return f;
    }
    if (k === 4) return planar(4, 0, q[1], s);
    if (k === 5) {
      const c = p.map((v) => Math.floor(v / s + 0.5));
      return [(((c[0] + c[1] + c[2]) % 2) + 2) % 2, 0];
    }
    return planar(6, p[0] + p[2], p[1], s);
  }
  if (k === 7) return [clamp(q[1] / s, 0, 1), 0];
  if (k === 8 || k === 9) return [fbm(p[0] / s, p[1] / s, p[2] / s), 0];
  return [0, 0];
}

function texColor(p, c1, c2, tx, n) {
  const [k, s, axis] = tx;
  const f = texField(p, k, s, axis, n);
  if (k === 6) {
    const v = (0.75 + 0.4 * f[1]) * (0.85 + 0.3 * vnoise((p[0] * 40) / s, (p[1] * 40) / s, (p[2] * 40) / s));
    return mix3(c1.map((x) => x * v), c2, f[0]);
  }
  return mix3(c1, c2, f[0]);
}

// altura da textura (0..1) para o relevo; igual ao shader
export function texHeight(p, tx, n) {
  const [k, s, axis, bump] = tx;
  if (k === 0 || !(bump > 0) || k === 7) return 0;
  const f = texField(p, k, s, axis, n);
  if (k === 6) return 1 - f[0] + 0.12 * f[1];
  if (k === 3) return 1 - f[0];
  return f[0];
}

// mesmos valores padrão do compilador
const DEFAULT = { color: [0.6, 0.6, 0.62], rough: 0.6, metal: 0, glow: 0, tex: null };
const TEX_SIZE = { 1: 0.25, 2: 0.06, 3: 0.3, 4: 0.1, 5: 0.25, 6: 0.25, 7: 1, 8: 0.3, 9: 0.1 };
function texC2(tex, color) {
  if (tex.c2) return tex.c2;
  const k = tex.kind;
  if (k === 9) return color;
  if (k === 8) return color.map((c) => c * 0.55);
  if (k === 7) return color.map((c) => Math.min(1, c * 1.6 + 0.04));
  return k === 6 ? [0.69, 0.65, 0.58] : color.map((c) => c * (k === 3 ? 0.25 : k === 5 || k === 4 ? 0.35 : 0.5));
}

// ---------- construção das closures ----------

// transformação de ponto (x, y, z) -> filho; devolve [fn(x,y,z)->[x,y,z], fator de distância]
function pointMap(s, t) {
  const P = s.props;
  switch (s.kind) {
    case 'translate': {
      const v = P.v.map((x) => at(x, t));
      return [(x, y, z) => [x - v[0], y - v[1], z - v[2]], 1];
    }
    case 'rotate': {
      const m = P.angles ? rotMatrix(...P.angles.map((a) => at(a, t))) : P.m;
      // p * R  (= R^T p), como no shader
      return [(x, y, z) => [m[0] * x + m[3] * y + m[6] * z, m[1] * x + m[4] * y + m[7] * z, m[2] * x + m[5] * y + m[8] * z], 1];
    }
    case 'scale': {
      const sv = P.s.map((x) => at(x, t));
      return [(x, y, z) => [x / sv[0], y / sv[1], z / sv[2]], Math.min(...sv)];
    }
    case 'affine': {
      const mi = P.minv, tv = P.t;
      return [(x, y, z) => {
        const a = x - tv[0], b = y - tv[1], c = z - tv[2];
        return [mi[0] * a + mi[1] * b + mi[2] * c, mi[3] * a + mi[4] * b + mi[5] * c, mi[6] * a + mi[7] * b + mi[8] * c];
      }, P.ds];
    }
    case 'mirror': {
      const c = center(s.children[0].bbox);
      const sg = c.map((v) => (v < 0 ? -1 : 1));
      const ax = P.axes;
      return [(x, y, z) => [ax[0] ? sg[0] * Math.abs(x) : x, ax[1] ? sg[1] * Math.abs(y) : y, ax[2] ? sg[2] * Math.abs(z) : z], 1];
    }
    case 'repeat': {
      const sp = P.s.map((v, i) => (P.n[i] > 1 ? v : 1));
      const h = P.n.map((n) => (n - 1) / 2);
      const rep = (v, i) => v - sp[i] * (clamp(Math.round(v / sp[i] + h[i]), 0, P.n[i] - 1) - h[i]);
      return [(x, y, z) => [rep(x, 0), rep(y, 1), rep(z, 2)], 1];
    }
    case 'taper': {
      const { axis, top, bottom, lo, hi } = P;
      const b = s.children[0].bbox;
      const R = Math.max(...[0, 1, 2].filter((i) => i !== axis).map((i) => Math.max(Math.abs(b.min[i]), Math.abs(b.max[i])))) * Math.SQRT2;
      const smin = Math.min(top, bottom), slope = Math.abs(top - bottom) / Math.max(1e-6, hi - lo);
      return [(x, y, z) => {
        const c = [x, y, z];
        const t = clamp((c[axis] - lo) / Math.max(1e-6, hi - lo), 0, 1);
        const sc = mix(bottom, top, t);
        return c.map((v, i) => (i === axis ? v : v / sc));
      }, smin / Math.sqrt(1 + ((slope * R) / smin) ** 2)];
    }
    case 'bend': {
      const { k, axis, toward, pivot } = P;
      const b = s.children[0].bbox;
      const R = Math.hypot(Math.max(Math.abs(b.min[axis] - pivot), Math.abs(b.max[axis] - pivot)), Math.max(Math.abs(b.min[toward]), Math.abs(b.max[toward])));
      return [(x, y, z) => {
        const c = [x, y, z];
        const u = c[axis] - pivot, v = c[toward];
        const co = Math.cos(k * u), sn = Math.sin(k * u);
        const out = [x, y, z];
        out[axis] = co * u - sn * v + pivot;
        out[toward] = sn * u + co * v;
        return out;
      }, 1 / Math.sqrt(1 + (k * R) ** 2)];
    }
    case 'shear': {
      const { sx, sz, y0 } = P;
      return [(x, y, z) => [x - sx * (y - y0), y, z - sz * (y - y0)], 1 / Math.sqrt(1 + sx * sx + sz * sz)];
    }
    case 'polar': {
      const sec = (2 * Math.PI) / P.n;
      return [(x, y, z) => {
        const r = Math.hypot(x, z);
        const a = ((((Math.atan2(z, x) + 0.5 * sec) % sec) + sec) % sec) - 0.5 * sec;
        return [r * Math.cos(a), y, r * Math.sin(a)];
      }, 1];
    }
    case 'elongate': {
      const [hx, hy, hz] = P.h;
      return [(x, y, z) => [x - clamp(x, -hx, hx), y - clamp(y, -hy, hy), z - clamp(z, -hz, hz)], 1];
    }
    case 'twist': {
      const b = s.children[0].bbox;
      const R = Math.max(Math.abs(b.min[0]), Math.abs(b.max[0]), Math.abs(b.min[2]), Math.abs(b.max[2])) * Math.SQRT2;
      return [(x, y, z) => {
        const c = Math.cos(P.k * y), sn = Math.sin(P.k * y);
        return [c * x - sn * z, y, sn * x + c * z];
      }, 1 / Math.sqrt(1 + (P.k * R) ** 2)];
    }
  }
  return null;
}

function primDist(s) {
  const P = s.props;
  switch (s.kind) {
    case 'box': { const h = P.size.map((x) => x / 2 - P.r); return (x, y, z) => sdBox(x, y, z, h[0], h[1], h[2]) - P.r; }
    case 'sphere': return (x, y, z) => len3(x, y, z) - P.r;
    case 'cylinder': return (x, y, z) => sdCyl(x, y, z, P.r - P.round, P.h / 2 - P.round) - P.round;
    case 'cone': return (x, y, z) => sdCone(x, y, z, P.h / 2, P.r, P.top);
    case 'torus': return (x, y, z) => sdTorus(x, y, z, P.R, P.r);
    case 'capsule': return (x, y, z) => sdCapsule(x, y, z, P.r, P.h / 2 - P.r);
    case 'ellipsoid': return (x, y, z) => sdEllipsoid(x, y, z, ...P.radii);
    case 'pyramid': return (x, y, z) => sdPyramid(x / P.w, (y + P.h / 2) / P.w, z / P.w, P.h / P.w) * P.w;
    case 'prism': return (x, y, z) => sdPrism(x, y, z, P.w / 2, P.h, P.d / 2);
    case 'plane': return (x, y) => y;
    case 'extrude': {
      const poly = polygonSDF(P.pts), half = P.h / 2;
      return P.axis === 'z' ? (x, y, z) => extrudeDist(poly(x, y), z, half, P.r) : (x, y, z) => extrudeDist(poly(x, z), y, half, P.r);
    }
    case 'implicit': {
      const f = P.f.compile(), [hx, hy, hz] = P.half, k = P.lip;
      return (x, y, z, t) => Math.max(f(x, y, z, 0) * k, sdBox(x, y, z, hx, hy, hz));
    }
    case 'lathe': {
      const poly = polygonSDF(P.pts);
      return (x, y, z) => poly(Math.hypot(x, z), y);
    }
  }
  return null;
}

function bboxDist(b) {
  const c = center(b), h = b.max.map((v, i) => (v - b.min[i]) / 2 + 0.01);
  return (x, y, z) => sdBox(x - c[0], y - c[1], z - c[2], h[0], h[1], h[2]);
}

// Transformações sem alocar arrays: esta função roda milhões de vezes na exportação.
function transformDist(s, t, c) {
  const P = s.props;
  switch (s.kind) {
    case 'translate': {
      const [a, b, d] = P.v.map((x) => at(x, t));
      return (x, y, z) => c(x - a, y - b, z - d);
    }
    case 'rotate': {
      const m = P.angles ? rotMatrix(...P.angles.map((a) => at(a, t))) : P.m;
      const [m0, m1, m2, m3, m4, m5, m6, m7, m8] = m;
      return (x, y, z) => c(m0 * x + m3 * y + m6 * z, m1 * x + m4 * y + m7 * z, m2 * x + m5 * y + m8 * z);
    }
    case 'scale': {
      const [a, b, d] = P.s.map((x) => at(x, t));
      const k = Math.min(a, b, d);
      return (x, y, z) => c(x / a, y / b, z / d) * k;
    }
    case 'affine': {
      const [i0, i1, i2, i3, i4, i5, i6, i7, i8] = P.minv;
      const [tx, ty, tz] = P.t;
      const k = P.ds;
      return (x, y, z) => {
        const a = x - tx, b = y - ty, d = z - tz;
        return c(i0 * a + i1 * b + i2 * d, i3 * a + i4 * b + i5 * d, i6 * a + i7 * b + i8 * d) * k;
      };
    }
  }
  const pm = pointMap(s, t);
  if (!pm) return null;
  const [map, k] = pm;
  return (x, y, z) => { const q = map(x, y, z); return c(q[0], q[1], q[2]) * k; };
}

export function buildDist(s, t = 0) {
  const prim = primDist(s);
  if (prim) return prim;
  const P = s.props;
  const kids = s.children.map((c) => buildDist(c, t));
  const tf = kids.length === 1 ? transformDist(s, t, kids[0]) : null;
  if (tf) return tf;
  const c0 = kids[0];
  switch (s.kind) {
    case 'material': case 'label': case 'bound': return c0;
    case 'round': return (x, y, z) => c0(x, y, z) - P.r;
    case 'shell': return (x, y, z) => Math.abs(c0(x, y, z)) - P.t / 2;
    case 'displace': {
      const lip = 1 / (1 + (2.5 * P.amt) / P.size);
      return (x, y, z) => (c0(x, y, z) + P.amt * (fbm(x / P.size, y / P.size, z / P.size) * 2 - 1)) * lip;
    }
    case 'union': {
      if (P.k) return (x, y, z) => kids.reduce((a, f, i) => (i ? smin(a, f(x, y, z), P.k) : f(x, y, z)), 0);
      // pula filhos cuja caixa está mais longe que o melhor resultado (como no shader)
      const bounds = s.children.map((c) => (c.leaves >= 3 && c.bbox.max.every((v) => v < 5e3) && c.bbox.min.every((v) => v > -5e3) ? bboxDist(c.bbox) : null));
      return (x, y, z) => {
        let best = 1e10;
        for (let i = 0; i < kids.length; i++) {
          if (bounds[i] && bounds[i](x, y, z) >= best) continue;
          const d = kids[i](x, y, z);
          if (d < best) best = d;
        }
        return best;
      };
    }
    case 'subtract': {
      const [a, b] = kids;
      return P.k ? (x, y, z) => smax(a(x, y, z), -b(x, y, z), P.k) : (x, y, z) => Math.max(a(x, y, z), -b(x, y, z));
    }
    case 'intersect':
      return (x, y, z) => kids.reduce((acc, f, i) => {
        const d = f(x, y, z);
        return i === 0 ? d : P.k ? smax(acc, d, P.k) : Math.max(acc, d);
      }, 0);
  }
  throw new Error(`sdf: tipo desconhecido ${s.kind}`);
}

// Versão com material: devolve { d, c, rough, metal, glow, c2, tx, tp } (tp = ponto da textura).
export function buildMat(s, t = 0, mat = {}) {
  const P = s.props;
  const prim = primDist(s);
  if (prim) {
    const full = { ...DEFAULT };
    for (const k of Object.keys(DEFAULT)) if (mat[k] !== null && mat[k] !== undefined) full[k] = mat[k];
    const glow = at(full.glow, t);
    const tex = full.tex;
    const tx = tex ? [tex.kind, tex.size ?? TEX_SIZE[tex.kind], tex.axis, tex.bump ?? 0] : null;
    const c2 = tex ? texC2(tex, full.color) : null;
    return (x, y, z, tp) => ({ d: prim(x, y, z), c: full.color, rough: full.rough, metal: full.metal, glow, c2, tx, tp });
  }
  if (s.kind === 'material') {
    const merged = { ...mat };
    for (const k of Object.keys(DEFAULT)) if (P[k] !== null && P[k] !== undefined) merged[k] = P[k];
    const c = buildMat(s.children[0], t, merged);
    // Match compiler.js: texture coordinates are fixed at the node where the
    // material is applied, then transformed by child transforms as needed.
    const off = texOffset(P.tex);
    return P.tex ? (x, y, z, tp) => {
      const q = tp ?? [x, y, z];
      return c(x, y, z, off ? [q[0] - off[0], q[1] - off[1], q[2] - off[2]] : q);
    } : c;
  }
  const kids = s.children.map((c) => buildMat(c, t, mat));
  const pm = pointMap(s, t);
  const withD = (r, d) => ({ ...r, d });
  if (pm) {
    const [map, k] = pm;
    const c = kids[0];
    return (x, y, z, tp) => {
      const q = map(x, y, z);
      const r = c(q[0], q[1], q[2], tp ?? q);
      return k === 1 ? r : withD(r, r.d * k);
    };
  }
  const c0 = kids[0];
  const pick = (a, b) => (a.d < b.d ? a : b);
  const blend = (a, b, k) => {
    const h = clamp(0.5 + (0.5 * (b.d - a.d)) / k, 0, 1);
    const r = h > 0.5 ? a : b;
    return { ...r, d: mix(b.d, a.d, h) - k * h * (1 - h), c: mix3(b.c, a.c, h) };
  };
  switch (s.kind) {
    case 'label': case 'bound': return c0;
    case 'round': return (x, y, z, tp) => { const r = c0(x, y, z, tp); return withD(r, r.d - P.r); };
    case 'shell': return (x, y, z, tp) => { const r = c0(x, y, z, tp); return withD(r, Math.abs(r.d) - P.t / 2); };
    case 'displace': {
      const lip = 1 / (1 + (2.5 * P.amt) / P.size);
      return (x, y, z, tp) => {
        const r = c0(x, y, z, tp);
        return withD(r, (r.d + P.amt * (fbm(x / P.size, y / P.size, z / P.size) * 2 - 1)) * lip);
      };
    }
    case 'union':
      return (x, y, z, tp) => kids.reduce((a, f, i) => {
        const r = f(x, y, z, tp);
        return i === 0 ? r : P.k ? blend(a, r, P.k) : pick(a, r);
      }, null);
    case 'subtract': {
      const [a, b] = kids;
      return (x, y, z, tp) => {
        const ra = a(x, y, z, tp), db = b(x, y, z, tp).d;
        return withD(ra, P.k ? smax(ra.d, -db, P.k) : Math.max(ra.d, -db));
      };
    }
    case 'intersect':
      return (x, y, z, tp) => kids.reduce((acc, f, i) => {
        const r = f(x, y, z, tp);
        return i === 0 ? r : withD(acc, P.k ? smax(acc.d, r.d, P.k) : Math.max(acc.d, r.d));
      }, null);
  }
  throw new Error(`sdf: tipo desconhecido ${s.kind}`);
}

// cor final (linear) com a textura aplicada
export function surfaceColor(r, n) {
  if (!r.tx || !r.tp) return r.c;
  return texColor(r.tp, r.c, r.c2, r.tx, n);
}

export { val0 };

// ---------- BVH na CPU (mesma ideia do shader) ----------
// Primitivas simples viram instâncias com transformação inversa pré-calculada, numa árvore
// de caixas; só o que é complexo (booleanas, smooth, mirror...) continua como closures.

const IDENT3 = [1, 0, 0, 0, 1, 0, 0, 0, 1];

function boxDistArr(mn, mx, x, y, z) {
  return sdBox(x - (mn[0] + mx[0]) / 2, y - (mn[1] + mx[1]) / 2, z - (mn[2] + mx[2]) / 2,
    (mx[0] - mn[0]) / 2 + 0.005, (mx[1] - mn[1]) / 2 + 0.005, (mx[2] - mn[2]) / 2 + 0.005);
}

function makeInstance(it) {
  const mi = inv3(it.m);
  const [i0, i1, i2, i3, i4, i5, i6, i7, i8] = mi;
  const [tx, ty, tz] = it.t;
  const prim = primDist(it.s), ds = it.ds;
  const local = (x, y, z) => {
    const a = x - tx, b = y - ty, c = z - tz;
    return [i0 * a + i1 * b + i2 * c, i3 * a + i4 * b + i5 * c, i6 * a + i7 * b + i8 * c];
  };
  const d = (x, y, z) => {
    const a = x - tx, b = y - ty, c = z - tz;
    return prim(i0 * a + i1 * b + i2 * c, i3 * a + i4 * b + i5 * c, i6 * a + i7 * b + i8 * c) * ds;
  };
  // caixa da instância no mundo
  const corners = [];
  const bb = it.s.bbox;
  for (let k = 0; k < 8; k++) {
    const p = [k & 1 ? bb.max[0] : bb.min[0], k & 2 ? bb.max[1] : bb.min[1], k & 4 ? bb.max[2] : bb.min[2]];
    corners.push([0, 1, 2].map((r) => it.m[r * 3] * p[0] + it.m[r * 3 + 1] * p[1] + it.m[r * 3 + 2] * p[2] + it.t[r]));
  }
  const min = [0, 1, 2].map((i) => Math.min(...corners.map((c) => c[i])));
  const max = [0, 1, 2].map((i) => Math.max(...corners.map((c) => c[i])));
  // material: o mesmo que o compilador grava na textura de instâncias
  const { texFrame, ...matProps } = it.mat;
  const full = { ...DEFAULT };
  for (const k of Object.keys(DEFAULT)) if (matProps[k] !== null && matProps[k] !== undefined) full[k] = matProps[k];
  const tex = full.tex;
  const tf = texFrame ?? { m: IDENT3, t: [0, 0, 0] };
  const ti = inv3(tf.m);
  const texPoint = (x, y, z) => {
    const a = x - tf.t[0], b = y - tf.t[1], c = z - tf.t[2];
    return [ti[0] * a + ti[1] * b + ti[2] * c, ti[3] * a + ti[4] * b + ti[5] * c, ti[6] * a + ti[7] * b + ti[8] * c];
  };
  const mat = (x, y, z, dd) => ({
    d: dd, c: full.color, rough: full.rough, metal: full.metal, glow: at(full.glow, 0),
    c2: tex ? texC2(tex, full.color) : null, tx: tex ? [tex.kind, tex.size ?? TEX_SIZE[tex.kind], tex.axis, tex.bump ?? 0] : null,
    tp: tex ? texPoint(x, y, z) : null,
  });
  return { d, mat, min, max, c: min.map((v, i) => (v + max[i]) / 2), local };
}

function buildTree(items) {
  const min = [0, 1, 2].map((i) => Math.min(...items.map((x) => x.min[i])));
  const max = [0, 1, 2].map((i) => Math.max(...items.map((x) => x.max[i])));
  if (items.length <= 4) return { min, max, items };
  const cmin = [0, 1, 2].map((i) => Math.min(...items.map((x) => x.c[i])));
  const cmax = [0, 1, 2].map((i) => Math.max(...items.map((x) => x.c[i])));
  const ext = cmax.map((v, i) => v - cmin[i]);
  const axis = ext.indexOf(Math.max(...ext));
  const sorted = [...items].sort((a, b) => a.c[axis] - b.c[axis]);
  const mid = sorted.length >> 1;
  return { min, max, left: buildTree(sorted.slice(0, mid)), right: buildTree(sorted.slice(mid)) };
}

/**
 * Funções de distância e material para exportar uma forma.
 * Usa BVH quando há muitas primitivas simples (como no shader); senão, as closures diretas.
 */
export function buildSceneFns(shape) {
  const { instances, residual } = splitScene([shape]);
  if (instances.length < 16) {
    const mat = buildMat(shape);
    return {
      dist: buildDist(shape),
      // Primitive scenes use the direct evaluator. Pass the surface position
      // as the default texture frame, as the GLSL compiler does for a top-level
      // .texture() node.
      mat: (x, y, z) => mat(x, y, z, [x, y, z]),
    };
  }
  const inst = instances.map(makeInstance);
  const root = buildTree(inst);
  const resD = residual.map((r) => buildDist(r));
  const resM = residual.map((r) => buildMat(r));
  let hit = null;
  const trav = (n, x, y, z, best) => {
    if (n.items) {
      for (const it of n.items) {
        const d = it.d(x, y, z);
        if (d < best) { best = d; hit = it; }
      }
      return best;
    }
    const dl = boxDistArr(n.left.min, n.left.max, x, y, z), dr = boxDistArr(n.right.min, n.right.max, x, y, z);
    const [a, da, b, db] = dl < dr ? [n.left, dl, n.right, dr] : [n.right, dr, n.left, dl];
    if (da < best) best = trav(a, x, y, z, best);
    if (db < best) best = trav(b, x, y, z, best);
    return best;
  };
  const dist = (x, y, z) => {
    let best = 1e10;
    for (const f of resD) { const d = f(x, y, z); if (d < best) best = d; }
    if (boxDistArr(root.min, root.max, x, y, z) < best) best = trav(root, x, y, z, best);
    return best;
  };
  const mat = (x, y, z) => {
    let best = null;
    for (const f of resM) { const r = f(x, y, z); if (!best || r.d < best.d) best = r; }
    hit = null;
    const d = trav(root, x, y, z, best ? best.d : 1e10);
    return hit ? hit.mat(x, y, z, d) : best;
  };
  return { dist, mat };
}
