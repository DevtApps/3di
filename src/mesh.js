// SDF -> malha de triângulos com "dual contouring".
// Para não avaliar a grade inteira, primeiro uma grade grossa (passo K) descobre onde está a
// superfície; só as células grossas perto dela são avaliadas na resolução fina.
//
// Cada célula atravessada pela superfície ganha um vértice. Em vez da média dos cruzamentos nas
// arestas (surface nets, que arredonda e serrilha as quinas), o vértice é o ponto que melhor
// satisfaz os planos tangentes de todos os cruzamentos (posição + normal): uma QEF resolvida com
// pseudoinversa. Assim quinas e cantos vivos saem exatos e superfícies lisas continuam lisas.
// Nas arestas vivas a normal é separada (cada face com a sua), para o sombreamento não "derreter".

import { simplifyMesh } from './simplify.js';

const K = 4;
const SHARP_COS = Math.cos((40 * Math.PI) / 180); // acima de 40° entre faces, a aresta é viva

const CORNER = [0, 1, 2, 3, 4, 5, 6, 7].map((c) => [c & 1, (c >> 1) & 1, (c >> 2) & 1]);
// as 12 arestas de uma célula como (eixo, deslocamento do canto inicial)
const CELL_EDGES = [];
for (let axis = 0; axis < 3; axis++) {
  const [u, v] = [0, 1, 2].filter((a) => a !== axis);
  for (const du of [0, 1]) for (const dv of [0, 1]) {
    const o = [0, 0, 0];
    o[u] = du;
    o[v] = dv;
    CELL_EDGES.push({ axis, o });
  }
}

// autovalores/autovetores de uma matriz simétrica 3x3 (Jacobi). a = [xx, xy, xz, yy, yz, zz]
function eigenSym3(a) {
  const m = [[a[0], a[1], a[2]], [a[1], a[3], a[4]], [a[2], a[4], a[5]]];
  const V = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
  for (let sweep = 0; sweep < 12; sweep++) {
    const off = Math.abs(m[0][1]) + Math.abs(m[0][2]) + Math.abs(m[1][2]);
    if (off < 1e-12) break;
    for (const [p, q] of [[0, 1], [0, 2], [1, 2]]) {
      if (Math.abs(m[p][q]) < 1e-15) continue;
      const theta = (m[q][q] - m[p][p]) / (2 * m[p][q]);
      const t = Math.sign(theta || 1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1));
      const c = 1 / Math.sqrt(t * t + 1), s = t * c;
      for (let k = 0; k < 3; k++) {
        const mkp = m[k][p], mkq = m[k][q];
        m[k][p] = c * mkp - s * mkq;
        m[k][q] = s * mkp + c * mkq;
      }
      for (let k = 0; k < 3; k++) {
        const mpk = m[p][k], mqk = m[q][k];
        m[p][k] = c * mpk - s * mqk;
        m[q][k] = s * mpk + c * mqk;
      }
      for (let k = 0; k < 3; k++) {
        const vkp = V[k][p], vkq = V[k][q];
        V[k][p] = c * vkp - s * vkq;
        V[k][q] = s * vkp + c * vkq;
      }
    }
  }
  return { values: [m[0][0], m[1][1], m[2][2]], vectors: [0, 1, 2].map((j) => [V[0][j], V[1][j], V[2][j]]) };
}

/**
 * dist(x, y, z) -> distância; bbox = { min, max }.
 * cell = [hx, hy, hz] tamanho da célula em cada eixo; sem cell, usa res células cúbicas na maior dimensão.
 * colorAt(x, y, z) -> [r, g, b] linear (opcional).
 * simplify: true (padrão), false ou { tolerance, maxEdge } para a simplificação por erro quádrico.
 * Devolve { positions, normals, colors, indices } (typed arrays) ou null se não houver superfície.
 */
export function meshSDF(dist, bbox, { res = 128, cell = null, colorAt = null, simplify = true } = {}) {
  const ext = bbox.max.map((v, i) => v - bbox.min[i]);
  const H = cell ?? [0, 1, 2].map(() => Math.max(...ext) / res);
  if (H.length !== 3 || !H.every((v) => Number.isFinite(v) && v > 0) || !ext.every((v) => Number.isFinite(v) && v >= 0)) throw new Error('grade deve ter dimensões finitas e células positivas');
  const [hx, hy, hz] = H;
  const origin = bbox.min.map((v, i) => v - 2 * H[i]);
  const [nx, ny, nz] = ext.map((e, i) => Math.ceil(e / H[i]) + 5);
  if (nx * ny * nz > 40e6) throw new Error(`grade grande demais (${nx}x${ny}x${nz}); reduza a resolução`);
  const idx = (i, j, k) => i + nx * (j + ny * k);
  const pos = (i, j, k) => [origin[0] + i * hx, origin[1] + j * hy, origin[2] + k * hz];

  // passo 1: grade grossa
  const [cx, cy, cz] = [nx, ny, nz].map((n) => Math.ceil((n - 1) / K) + 1);
  const fi = (c, n) => Math.min(c * K, n - 1);
  const coarse = new Float32Array(cx * cy * cz);
  for (let k = 0; k < cz; k++) for (let j = 0; j < cy; j++) for (let i = 0; i < cx; i++) {
    const [x, y, z] = pos(fi(i, nx), fi(j, ny), fi(k, nz));
    coarse[i + cx * (j + cy * k)] = dist(x, y, z);
  }

  // passo 2: resolução fina só nas células grossas que podem conter superfície
  const vals = new Float32Array(nx * ny * nz).fill(NaN);
  const band = K * Math.hypot(hx, hy, hz) * 1.1;
  for (let k = 0; k < cz - 1; k++) for (let j = 0; j < cy - 1; j++) for (let i = 0; i < cx - 1; i++) {
    let minAbs = Infinity;
    for (let c = 0; c < 8; c++) {
      const v = coarse[(i + CORNER[c][0]) + cx * ((j + CORNER[c][1]) + cy * (k + CORNER[c][2]))];
      minAbs = Math.min(minAbs, Math.abs(v));
    }
    if (minAbs > band) continue;
    for (let kk = fi(k, nz); kk <= fi(k + 1, nz); kk++) for (let jj = fi(j, ny); jj <= fi(j + 1, ny); jj++) for (let ii = fi(i, nx); ii <= fi(i + 1, nx); ii++) {
      const id = idx(ii, jj, kk);
      if (Number.isNaN(vals[id])) { const [x, y, z] = pos(ii, jj, kk); vals[id] = dist(x, y, z); }
    }
  }
  // pontos não avaliados ficam longe da superfície: basta o sinal da célula grossa
  for (let k = 0; k < nz; k++) for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
    const id = idx(i, j, k);
    if (!Number.isNaN(vals[id])) continue;
    const c = coarse[Math.min(Math.floor(i / K), cx - 1) + cx * (Math.min(Math.floor(j / K), cy - 1) + cy * Math.min(Math.floor(k / K), cz - 1))];
    vals[id] = c < 0 ? -band : band;
  }

  // normal da superfície por diferenças centrais
  const e = Math.min(hx, hy, hz) * 0.05;
  const hmax = Math.max(hx, hy, hz);
  const grad = (x, y, z) => {
    const gx = dist(x + e, y, z) - dist(x - e, y, z);
    const gy = dist(x, y + e, z) - dist(x, y - e, z);
    const gz = dist(x, y, z + e) - dist(x, y, z - e);
    const l = Math.hypot(gx, gy, gz) || 1;
    return [gx / l, gy / l, gz / l];
  };

  // cruzamento numa aresta da grade (início em (i, j, k), ao longo de axis): posição refinada com um
  // passo de secante e normal; cada aresta é compartilhada por 4 células, então fica em cache
  const edgeCache = new Map();
  const crossing = (i, j, k, axis) => {
    const key = idx(i, j, k) * 3 + axis;
    const hit = edgeCache.get(key);
    if (hit) return hit;
    const step = [0, 0, 0];
    step[axis] = 1;
    const va = vals[idx(i, j, k)], vb = vals[idx(i + step[0], j + step[1], k + step[2])];
    const p0 = pos(i, j, k);
    let t = va / (va - vb);
    const at = (tt) => p0.map((v, a) => (a === axis ? v + tt * H[axis] : v));
    const dm = dist(...at(t));
    if (dm !== 0 && Number.isFinite(dm)) {
      // secante no subintervalo que ainda contém a troca de sinal
      t = (dm < 0) === (va < 0) ? t + (1 - t) * (dm / (dm - vb)) : t * (va / (va - dm));
    }
    const p = at(Math.min(1, Math.max(0, t)));
    const out = { p, n: grad(...p) };
    edgeCache.set(key, out);
    return out;
  };

  // passo 3: um vértice por célula atravessada, pela QEF dos planos tangentes
  const cellVert = new Int32Array(nx * ny * nz).fill(-1);
  const P = [];
  const rank1 = [];
  const v8 = new Float32Array(8);
  for (let k = 0; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
    let mask = 0;
    for (let c = 0; c < 8; c++) {
      v8[c] = vals[idx(i + CORNER[c][0], j + CORNER[c][1], k + CORNER[c][2])];
      if (v8[c] < 0) mask |= 1 << c;
    }
    if (mask === 0 || mask === 255) continue;
    const ata = [0, 0, 0, 0, 0, 0], atb = [0, 0, 0], mass = [0, 0, 0];
    const normalsHere = [];
    let m = 0;
    for (const { axis, o } of CELL_EDGES) {
      const a = idx(i + o[0], j + o[1], k + o[2]);
      const s = [0, 0, 0];
      s[axis] = 1;
      const b = idx(i + o[0] + s[0], j + o[1] + s[1], k + o[2] + s[2]);
      if ((vals[a] < 0) === (vals[b] < 0)) continue;
      const { p, n } = crossing(i + o[0], j + o[1], k + o[2], axis);
      const d = n[0] * p[0] + n[1] * p[1] + n[2] * p[2];
      ata[0] += n[0] * n[0]; ata[1] += n[0] * n[1]; ata[2] += n[0] * n[2];
      ata[3] += n[1] * n[1]; ata[4] += n[1] * n[2]; ata[5] += n[2] * n[2];
      atb[0] += n[0] * d; atb[1] += n[1] * d; atb[2] += n[2] * d;
      mass[0] += p[0]; mass[1] += p[1]; mass[2] += p[2];
      normalsHere.push(n);
      m++;
    }
    // Só é quina se as normais divergem de verdade (mais de 40°). Uma curva suave (arredondamento
    // menor que a célula) também dá várias direções, mas cruzar os planos tangentes poria o vértice
    // fora dela e criaria "costelas": nesse caso fica o ponto médio, projetado na superfície.
    let minDot = 1;
    for (let a = 0; a < normalsHere.length; a++) for (let b = a + 1; b < normalsHere.length; b++) {
      const na = normalsHere[a], nb = normalsHere[b];
      minDot = Math.min(minDot, na[0] * nb[0] + na[1] * nb[1] + na[2] * nb[2]);
    }
    const sharp = minDot < SHARP_COS;
    const c = mass.map((v) => v / m);
    // resolve em torno do ponto médio: x = c + pinv(AtA) (Atb - AtA c), descartando direções fracas
    const r = [
      atb[0] - (ata[0] * c[0] + ata[1] * c[1] + ata[2] * c[2]),
      atb[1] - (ata[1] * c[0] + ata[3] * c[1] + ata[4] * c[2]),
      atb[2] - (ata[2] * c[0] + ata[4] * c[1] + ata[5] * c[2]),
    ];
    const { values, vectors } = eigenSym3(ata);
    const lmax = Math.max(...values);
    let x = [...c];
    let rank = 0;
    if (sharp) for (let q = 0; q < 3; q++) {
      if (values[q] <= lmax * 0.1) continue;
      rank++;
      const v = vectors[q];
      const coef = (v[0] * r[0] + v[1] * r[1] + v[2] * r[2]) / values[q];
      x = x.map((xv, a) => xv + v[a] * coef);
    }
    // o vértice precisa ficar na célula (com uma pequena folga) e, sendo quina, sobre a superfície:
    // numa aresta de verdade o cruzamento dos planos é a própria aresta (distância ~0); numa curva
    // ele cai fora dela. Se falhar, a célula é tratada como lisa (ponto médio projetado).
    const lo = pos(i, j, k);
    const inside = x.every((v, a) => v >= lo[a] - H[a] * 0.25 && v <= lo[a] + H[a] * 1.25);
    if (rank >= 2 && (!inside || Math.abs(dist(x[0], x[1], x[2])) > Math.min(hx, hy, hz) * 0.08)) {
      x = [...c];
      rank = 1;
    } else if (!inside) {
      x = x.map((v, a) => Math.min(lo[a] + H[a], Math.max(lo[a], v)));
    }
    cellVert[idx(i, j, k)] = P.length / 3;
    P.push(x[0], x[1], x[2]);
    rank1.push(rank <= 1);
  }
  if (!P.length) return null;

  // passo 4: um quadrado para cada aresta da grade que cruza a superfície
  const Iraw = [];
  const quad = (a, b, c, d, flip) => {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    if (flip) Iraw.push(a, c, b, a, d, c);
    else Iraw.push(a, b, c, a, c, d);
  };
  const cv = (i, j, k) => cellVert[idx(i, j, k)];
  for (let k = 0; k < nz; k++) for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) {
    const v0 = vals[idx(i, j, k)] < 0;
    if (i < nx - 1 && j > 0 && k > 0 && j < ny - 1 && k < nz - 1 && v0 !== (vals[idx(i + 1, j, k)] < 0)) {
      quad(cv(i, j - 1, k - 1), cv(i, j, k - 1), cv(i, j, k), cv(i, j - 1, k), !v0);
    }
    if (j < ny - 1 && i > 0 && k > 0 && i < nx - 1 && k < nz - 1 && v0 !== (vals[idx(i, j + 1, k)] < 0)) {
      quad(cv(i - 1, j, k - 1), cv(i - 1, j, k), cv(i, j, k), cv(i, j, k - 1), !v0);
    }
    if (k < nz - 1 && i > 0 && j > 0 && i < nx - 1 && j < ny - 1 && v0 !== (vals[idx(i, j, k + 1)] < 0)) {
      quad(cv(i - 1, j - 1, k), cv(i, j - 1, k), cv(i, j, k), cv(i - 1, j, k), !v0);
    }
  }

  // passo 5: vértices de regiões lisas (posto 1) são projetados na superfície; os de quina ficam onde a QEF pôs
  const nv0 = P.length / 3;
  let base = new Float32Array(P);
  for (let v = 0; v < nv0; v++) {
    if (!rank1[v]) continue;
    let x = base[v * 3], y = base[v * 3 + 1], z = base[v * 3 + 2];
    const n = grad(x, y, z);
    const d = dist(x, y, z);
    if (Math.abs(d) < hmax) { x -= n[0] * d; y -= n[1] * d; z -= n[2] * d; }
    base.set([x, y, z], v * 3);
  }
  let I = new Uint32Array(Iraw);

  // passo 5b: simplifica onde os triângulos não mudam a forma (faces planas viram poucos triângulos
  // grandes); a tolerância é uma fração da célula, abaixo do que se enxerga
  if (simplify) {
    const opt = typeof simplify === 'object' ? simplify : {};
    ({ positions: base, indices: I } = simplifyMesh(base, I, opt.tolerance ?? Math.min(hx, hy, hz) * 0.15, { maxEdge: opt.maxEdge ?? Infinity }));
  }
  const nv = base.length / 3;
  const smoothN = new Float32Array(nv * 3);
  for (let v = 0; v < nv; v++) smoothN.set(grad(base[v * 3], base[v * 3 + 1], base[v * 3 + 2]), v * 3);

  // passo 6: normais. Cada triângulo tem a sua normal de face; num vértice, as faces são agrupadas
  // por semelhança (até 40°). Um grupo só: vértice liso, usa a normal do SDF. Mais de um: aresta viva,
  // o vértice é duplicado e cada cópia leva a média das faces do seu grupo.
  const nt = I.length / 3;
  const faceN = new Float32Array(nt * 3);
  for (let t = 0; t < nt; t++) {
    const a = I[t * 3] * 3, b = I[t * 3 + 1] * 3, c = I[t * 3 + 2] * 3;
    const ux = base[b] - base[a], uy = base[b + 1] - base[a + 1], uz = base[b + 2] - base[a + 2];
    const wx = base[c] - base[a], wy = base[c + 1] - base[a + 1], wz = base[c + 2] - base[a + 2];
    const fx = uy * wz - uz * wy, fy = uz * wx - ux * wz, fz = ux * wy - uy * wx;
    const l = Math.hypot(fx, fy, fz);
    if (l > 0) faceN.set([fx / l, fy / l, fz / l], t * 3);
  }
  // faces de cada vértice
  const count = new Int32Array(nv + 1);
  for (const v of I) count[v + 1]++;
  for (let v = 0; v < nv; v++) count[v + 1] += count[v];
  const fill = count.slice(0, nv);
  const incident = new Int32Array(I.length);
  for (let q = 0; q < I.length; q++) incident[fill[I[q]]++] = (q / 3) | 0;

  const outP = [], outN = [], remap = new Int32Array(I.length);
  const fn = (t) => [faceN[t * 3], faceN[t * 3 + 1], faceN[t * 3 + 2]];
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  for (let v = 0; v < nv; v++) {
    const groups = [], degenerate = [];
    for (let q = count[v]; q < count[v + 1]; q++) {
      const t = incident[q];
      const n = fn(t);
      if (n[0] === 0 && n[1] === 0 && n[2] === 0) { degenerate.push(t); continue; }
      let g = groups.find((gr) => dot(gr.ref, n) > SHARP_COS);
      if (!g) { g = { ref: n, sum: [0, 0, 0], faces: [] }; groups.push(g); }
      g.faces.push(t);
      g.sum[0] += n[0]; g.sum[1] += n[1]; g.sum[2] += n[2];
    }
    // triângulos degenerados (área zero) vão para o primeiro grupo
    if (!groups.length) groups.push({ ref: null, sum: [0, 0, 0], faces: [] });
    groups[0].faces.push(...degenerate);
    const sn = [smoothN[v * 3], smoothN[v * 3 + 1], smoothN[v * 3 + 2]];
    for (const g of groups) {
      const id = outP.length / 3;
      outP.push(base[v * 3], base[v * 3 + 1], base[v * 3 + 2]);
      let n = sn;
      if (groups.length > 1) {
        const l = Math.hypot(...g.sum) || 1;
        n = g.sum.map((c) => c / l);
      }
      outN.push(...n);
      for (const t of g.faces) for (let q = t * 3; q < t * 3 + 3; q++) if (I[q] === v) remap[q] = id;
    }
  }

  const positions = new Float32Array(outP);
  const normals = new Float32Array(outN);
  let colors = null;
  if (colorAt) {
    colors = new Float32Array(positions.length);
    for (let v = 0; v < positions.length / 3; v++) colors.set(colorAt(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2]), v * 3);
  }
  return { positions, normals, colors, indices: new Uint32Array(remap) };
}
