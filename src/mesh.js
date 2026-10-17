// SDF -> malha de triângulos com "surface nets".
// Para não avaliar a grade inteira, primeiro uma grade grossa (passo K) descobre onde está a
// superfície; só as células grossas perto dela são avaliadas na resolução fina.

const K = 4;

// 12 arestas do cubo, como pares de cantos (canto = x + 2y + 4z)
const EDGES = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
const CORNER = [0, 1, 2, 3, 4, 5, 6, 7].map((c) => [c & 1, (c >> 1) & 1, (c >> 2) & 1]);

/**
 * dist(x, y, z) -> distância; bbox = { min, max }.
 * cell = [hx, hy, hz] tamanho da célula em cada eixo (células finas só no eixo em que a peça é fina);
 * sem cell, usa res células cúbicas na maior dimensão.
 * colorAt(x, y, z) -> [r, g, b] linear (opcional).
 * Devolve { positions, normals, colors, indices } (typed arrays) ou null se não houver superfície.
 */
export function meshSDF(dist, bbox, { res = 128, cell = null, colorAt = null } = {}) {
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

  // passo 3: um vértice por célula que a superfície atravessa (média dos cruzamentos nas arestas)
  const cellVert = new Int32Array(nx * ny * nz).fill(-1);
  const P = [];
  const v8 = new Float32Array(8);
  for (let k = 0; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
    let mask = 0;
    for (let c = 0; c < 8; c++) {
      v8[c] = vals[idx(i + CORNER[c][0], j + CORNER[c][1], k + CORNER[c][2])];
      if (v8[c] < 0) mask |= 1 << c;
    }
    if (mask === 0 || mask === 255) continue;
    let sx = 0, sy = 0, sz = 0, n = 0;
    for (const [a, b] of EDGES) {
      if ((v8[a] < 0) === (v8[b] < 0)) continue;
      const t = v8[a] / (v8[a] - v8[b]);
      sx += CORNER[a][0] + t * (CORNER[b][0] - CORNER[a][0]);
      sy += CORNER[a][1] + t * (CORNER[b][1] - CORNER[a][1]);
      sz += CORNER[a][2] + t * (CORNER[b][2] - CORNER[a][2]);
      n++;
    }
    cellVert[idx(i, j, k)] = P.length / 3;
    P.push(origin[0] + (i + sx / n) * hx, origin[1] + (j + sy / n) * hy, origin[2] + (k + sz / n) * hz);
  }
  if (!P.length) return null;

  // passo 4: um quadrado para cada aresta da grade que cruza a superfície
  const I = [];
  const quad = (a, b, c, d, flip) => {
    if (a < 0 || b < 0 || c < 0 || d < 0) return;
    if (flip) I.push(a, c, b, a, d, c);
    else I.push(a, b, c, a, c, d);
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

  // passo 5: projeta cada vértice na superfície e calcula normal (gradiente) e cor
  const nv = P.length / 3;
  const positions = new Float32Array(P);
  const normals = new Float32Array(nv * 3);
  const colors = colorAt ? new Float32Array(nv * 3) : null;
  const e = Math.min(hx, hy, hz) * 0.5;
  const hmax = Math.max(hx, hy, hz);
  const grad = (x, y, z) => {
    const gx = dist(x + e, y, z) - dist(x - e, y, z);
    const gy = dist(x, y + e, z) - dist(x, y - e, z);
    const gz = dist(x, y, z + e) - dist(x, y, z - e);
    const l = Math.hypot(gx, gy, gz) || 1;
    return [gx / l, gy / l, gz / l];
  };
  for (let v = 0; v < nv; v++) {
    let x = positions[v * 3], y = positions[v * 3 + 1], z = positions[v * 3 + 2];
    let n = grad(x, y, z);
    const d = dist(x, y, z);
    if (Math.abs(d) < hmax) { x -= n[0] * d; y -= n[1] * d; z -= n[2] * d; n = grad(x, y, z); }
    positions.set([x, y, z], v * 3);
    normals.set(n, v * 3);
    if (colors) colors.set(colorAt(x, y, z), v * 3);
  }
  return { positions, normals, colors, indices: new Uint32Array(I) };
}
