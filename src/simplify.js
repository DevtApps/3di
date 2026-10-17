// Simplificação de malha por colapso de arestas com erro quádrico (Garland & Heckbert, 1997).
//
// Cada vértice acumula os planos das faces em volta (uma quádrica 4x4). Colapsar uma aresta num
// ponto custa a soma das distâncias ao quadrado desse ponto a esses planos: em regiões planas custa
// zero, em quinas e curvas custa muito. As arestas mais baratas são colapsadas primeiro, até o custo
// passar da tolerância (em metros). Resultado: faces planas viram poucos triângulos grandes, e
// quinas e curvas mantêm os detalhes.
//
// Proteções: não colapsa se alguma face vizinha virar do avesso, se a malha deixar de ser variedade
// (condição de ligação), ou se o vértice estiver numa borda aberta (a borda do chão recortado).

// min-heap de arestas por custo
class Heap {
  constructor() { this.cost = []; this.data = []; }
  get size() { return this.cost.length; }
  push(c, d) {
    const { cost, data } = this;
    let i = cost.length;
    cost.push(c); data.push(d);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (cost[p] <= c) break;
      cost[i] = cost[p]; data[i] = data[p];
      i = p;
    }
    cost[i] = c; data[i] = d;
  }
  pop() {
    const { cost, data } = this;
    const top = data[0], last = cost.length - 1;
    const c = cost[last], d = data[last];
    cost.pop(); data.pop();
    if (last > 0) {
      let i = 0;
      for (;;) {
        let l = 2 * i + 1;
        if (l >= last) break;
        if (l + 1 < last && cost[l + 1] < cost[l]) l++;
        if (cost[l] >= c) break;
        cost[i] = cost[l]; data[i] = data[l];
        i = l;
      }
      cost[i] = c; data[i] = d;
    }
    return top;
  }
  peekCost() { return this.cost[0]; }
}

/**
 * positions: Float32Array (3 por vértice), indices: Uint32Array (3 por triângulo), malha soldada.
 * tolerance: desvio máximo aproximado da superfície, em metros.
 * maxEdge: comprimento máximo de aresta (opcional), para não esticar triângulos que levam textura.
 * Devolve { positions, indices } novos (vértices sem uso são removidos).
 */
const MAX_VALENCE = 20; // vértice com mais vizinhos que isso vira leque de triângulos finos (e deixa tudo lento)

export function simplifyMesh(positions, indices, tolerance, { maxEdge = Infinity } = {}) {
  const nv = positions.length / 3, nt = indices.length / 3;
  if (nt < 8 || !(tolerance > 0)) return { positions, indices };
  const P = Float64Array.from(positions);
  const F = Int32Array.from(indices);
  const faceAlive = new Uint8Array(nt).fill(1);
  const Q = new Float64Array(nv * 10);
  const version = new Int32Array(nv);
  const dead = new Uint8Array(nv);
  const locked = new Uint8Array(nv);

  // faces de cada vértice
  const adj = Array.from({ length: nv }, () => []);
  for (let t = 0; t < nt; t++) for (let k = 0; k < 3; k++) adj[F[t * 3 + k]].push(t);

  const faceNormal = (t, out) => {
    const a = F[t * 3] * 3, b = F[t * 3 + 1] * 3, c = F[t * 3 + 2] * 3;
    const ux = P[b] - P[a], uy = P[b + 1] - P[a + 1], uz = P[b + 2] - P[a + 2];
    const vx = P[c] - P[a], vy = P[c + 1] - P[a + 1], vz = P[c + 2] - P[a + 2];
    out[0] = uy * vz - uz * vy; out[1] = uz * vx - ux * vz; out[2] = ux * vy - uy * vx;
    return Math.hypot(out[0], out[1], out[2]);
  };

  // quádricas dos planos das faces (sem peso por área: o custo fica em metros ao quadrado)
  const n = [0, 0, 0];
  for (let t = 0; t < nt; t++) {
    const len = faceNormal(t, n);
    if (len < 1e-18) continue;
    const a = n[0] / len, b = n[1] / len, c = n[2] / len;
    const v0 = F[t * 3] * 3;
    const d = -(a * P[v0] + b * P[v0 + 1] + c * P[v0 + 2]);
    const q = [a * a, a * b, a * c, a * d, b * b, b * c, b * d, c * c, c * d, d * d];
    for (let k = 0; k < 3; k++) {
      const o = F[t * 3 + k] * 10;
      for (let j = 0; j < 10; j++) Q[o + j] += q[j];
    }
  }

  // bordas abertas (aresta com uma face só): os vértices dela ficam travados
  const edgeCount = new Map();
  const key = (a, b) => (a < b ? a * nv + b : b * nv + a);
  for (let t = 0; t < nt; t++) for (let k = 0; k < 3; k++) {
    const a = F[t * 3 + k], b = F[t * 3 + ((k + 1) % 3)];
    const kk = key(a, b);
    edgeCount.set(kk, (edgeCount.get(kk) ?? 0) + 1);
  }
  for (const [kk, c] of edgeCount) if (c !== 2) { locked[Math.floor(kk / nv)] = 1; locked[kk % nv] = 1; }

  const qcost = (q, x, y, z) =>
    q[0] * x * x + 2 * q[1] * x * y + 2 * q[2] * x * z + 2 * q[3] * x +
    q[4] * y * y + 2 * q[5] * y * z + 2 * q[6] * y + q[7] * z * z + 2 * q[8] * z + q[9];

  const qsum = new Float64Array(10);
  const best = new Float64Array(3);
  // melhor ponto para colapsar a aresta (a, b) em `best`; devolve o custo
  const plan = (a, b) => {
    for (let j = 0; j < 10; j++) qsum[j] = Q[a * 10 + j] + Q[b * 10 + j];
    const q = qsum;
    const ax = P[a * 3], ay = P[a * 3 + 1], az = P[a * 3 + 2];
    const bx = P[b * 3], by = P[b * 3 + 1], bz = P[b * 3 + 2];
    const mx = (ax + bx) / 2, my = (ay + by) / 2, mz = (az + bz) / 2;
    let bc = qcost(q, mx, my, mz); best[0] = mx; best[1] = my; best[2] = mz;
    const ca = qcost(q, ax, ay, az);
    if (ca < bc) { bc = ca; best[0] = ax; best[1] = ay; best[2] = az; }
    const cb = qcost(q, bx, by, bz);
    if (cb < bc) { bc = cb; best[0] = bx; best[1] = by; best[2] = bz; }
    // mínimo da quádrica (sistema 3x3), aceito só perto da aresta (senão um sistema quase singular joga o ponto longe)
    const m00 = q[0], m01 = q[1], m02 = q[2], m11 = q[4], m12 = q[5], m22 = q[7];
    const c0 = m11 * m22 - m12 * m12, c1 = m01 * m22 - m12 * m02, c2 = m01 * m12 - m11 * m02;
    const det = m00 * c0 - m01 * c1 + m02 * c2;
    if (Math.abs(det) > 1e-12) {
      const r0 = -q[3], r1 = -q[6], r2 = -q[8];
      const x = (r0 * c0 - m01 * (r1 * m22 - m12 * r2) + m02 * (r1 * m12 - m11 * r2)) / det;
      const y = (m00 * (r1 * m22 - m12 * r2) - r0 * c1 + m02 * (m01 * r2 - r1 * m02)) / det;
      const z = (m00 * (m11 * r2 - r1 * m12) - m01 * (m01 * r2 - r1 * m02) + r0 * c2) / det;
      const elen2 = (bx - ax) ** 2 + (by - ay) ** 2 + (bz - az) ** 2;
      if ((x - mx) ** 2 + (y - my) ** 2 + (z - mz) ** 2 < elen2) {
        const cx = qcost(q, x, y, z);
        if (cx < bc) { bc = cx; best[0] = x; best[1] = y; best[2] = z; }
      }
    }
    return Math.max(0, bc);
  };

  const heap = new Heap();
  const pushEdge = (a, b) => {
    if (locked[a] || locked[b]) return;
    const cost = plan(a, b);
    heap.push(cost, { a, b, va: version[a], vb: version[b], x: best[0], y: best[1], z: best[2] });
  };
  for (const kk of edgeCount.keys()) pushEdge(Math.floor(kk / nv), kk % nv);

  const tol2 = tolerance * tolerance;
  // carimbos para marcar vizinhos sem criar conjuntos
  const markA = new Int32Array(nv), markB = new Int32Array(nv);
  let stamp = 0;
  // normal da face t com os vértices a e b trocados pelo ponto (x, y, z); devolve o comprimento
  const normalMoved = (t, a, b, x, y, z, out) => {
    const v0 = F[t * 3], v1 = F[t * 3 + 1], v2 = F[t * 3 + 2];
    const m0 = v0 === a || v0 === b, m1 = v1 === a || v1 === b, m2 = v2 === a || v2 === b;
    const x0 = m0 ? x : P[v0 * 3], y0 = m0 ? y : P[v0 * 3 + 1], z0 = m0 ? z : P[v0 * 3 + 2];
    const x1 = m1 ? x : P[v1 * 3], y1 = m1 ? y : P[v1 * 3 + 1], z1 = m1 ? z : P[v1 * 3 + 2];
    const x2 = m2 ? x : P[v2 * 3], y2 = m2 ? y : P[v2 * 3 + 1], z2 = m2 ? z : P[v2 * 3 + 2];
    const ux = x1 - x0, uy = y1 - y0, uz = z1 - z0, vx = x2 - x0, vy = y2 - y0, vz = z2 - z0;
    out[0] = uy * vz - uz * vy; out[1] = uz * vx - ux * vz; out[2] = ux * vy - uy * vx;
    return Math.hypot(out[0], out[1], out[2]);
  };
  const before = [0, 0, 0], after = [0, 0, 0];
  // vizinhos de a e b juntos (sem repetir, sem a e b)
  const markN = new Int32Array(nv);
  let stampN = 0;
  const neighborsOf = function* (a, b) {
    stampN++;
    for (const v of [a, b]) for (const t of adj[v]) {
      if (!faceAlive[t]) continue;
      for (let k = 0; k < 3; k++) {
        const w = F[t * 3 + k];
        if (w !== a && w !== b && markN[w] !== stampN) { markN[w] = stampN; yield w; }
      }
    }
  };

  while (heap.size && heap.peekCost() <= tol2) {
    const e = heap.pop();
    const { a, b } = e;
    if (dead[a] || dead[b] || version[a] !== e.va || version[b] !== e.vb) continue;
    // condição de ligação: a e b só podem ter em comum os dois vizinhos da aresta
    stamp++;
    let connected = false;
    for (const t of adj[a]) {
      if (!faceAlive[t]) continue;
      for (let k = 0; k < 3; k++) { const w = F[t * 3 + k]; markA[w] = stamp; if (w === b) connected = true; }
    }
    if (!connected) continue;
    let common = 0;
    for (const t of adj[b]) {
      if (!faceAlive[t]) continue;
      for (let k = 0; k < 3; k++) {
        const w = F[t * 3 + k];
        if (w !== a && w !== b && markA[w] === stamp && markB[w] !== stamp) { markB[w] = stamp; common++; }
      }
    }
    if (common !== 2) continue;
    // valência e comprimento das arestas novas (do ponto do colapso até cada vizinho)
    let valence = 0, tooLong = false;
    const ex = e.x, ey = e.y, ez = e.z;
    const maxEdge2 = maxEdge * maxEdge;
    for (const w of neighborsOf(a, b)) {
      valence++;
      if (maxEdge2 !== Infinity && (P[w * 3] - ex) ** 2 + (P[w * 3 + 1] - ey) ** 2 + (P[w * 3 + 2] - ez) ** 2 > maxEdge2) { tooLong = true; break; }
    }
    if (tooLong || valence > MAX_VALENCE) continue;
    // nenhuma face pode virar do avesso (nem ficar degenerada) com a mudança
    let ok = true;
    for (const v of [a, b]) {
      for (const t of adj[v]) {
        if (!faceAlive[t]) continue;
        const fa = F[t * 3], fb = F[t * 3 + 1], fc = F[t * 3 + 2];
        if ((fa === a || fb === a || fc === a) && (fa === b || fb === b || fc === b)) continue; // some
        const l0 = faceNormal(t, before);
        const l1 = normalMoved(t, a, b, e.x, e.y, e.z, after);
        if (l1 < l0 * 1e-3 || (before[0] * after[0] + before[1] * after[1] + before[2] * after[2]) < 0.3 * l0 * l1) { ok = false; break; }
      }
      if (!ok) break;
    }
    if (!ok) continue;
    // colapsa b em a
    P[a * 3] = e.x; P[a * 3 + 1] = e.y; P[a * 3 + 2] = e.z;
    for (let j = 0; j < 10; j++) Q[a * 10 + j] += Q[b * 10 + j];
    const keep = [];
    for (const t of adj[a]) if (faceAlive[t]) keep.push(t);
    for (const t of adj[b]) {
      if (!faceAlive[t]) continue;
      let hasA = false;
      for (let k = 0; k < 3; k++) if (F[t * 3 + k] === a) hasA = true;
      if (hasA) { faceAlive[t] = 0; continue; }
      for (let k = 0; k < 3; k++) if (F[t * 3 + k] === b) F[t * 3 + k] = a;
      keep.push(t);
    }
    adj[a] = keep.filter((t) => faceAlive[t]);
    adj[b] = [];
    dead[b] = 1;
    version[a]++;
    stamp++;
    for (const t of adj[a]) for (let k = 0; k < 3; k++) {
      const w = F[t * 3 + k];
      if (w !== a && markA[w] !== stamp) { markA[w] = stamp; pushEdge(a, w); }
    }
  }

  // compacta: só vértices usados por faces vivas
  const remap = new Int32Array(nv).fill(-1);
  const outP = [], outI = [];
  for (let t = 0; t < nt; t++) {
    if (!faceAlive[t]) continue;
    for (let k = 0; k < 3; k++) {
      const v = F[t * 3 + k];
      if (remap[v] < 0) { remap[v] = outP.length / 3; outP.push(P[v * 3], P[v * 3 + 1], P[v * 3 + 2]); }
      outI.push(remap[v]);
    }
  }
  return { positions: new Float32Array(outP), indices: new Uint32Array(outI) };
}
