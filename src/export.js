// Exportação da cena para glTF binário (.glb).
// - Cada forma mostrada vira uma malha (SDF -> surface nets); texturas procedurais são assadas em PNG.
// - Partes presas a ossos (.bind) viram malhas com skin (peso 1 no osso) na pose de repouso;
//   o esqueleto vira a hierarquia de juntas e as rotações/movimentos com `time` viram
//   uma animação amostrada (duration/fps de animation()).
// - Outras animações com `time` (fora de ossos) são exportadas paradas, em t = 0.
import { Shape, isFiniteBB, mulMV, mul3, size, unionBB } from './shapes.js';
import { resolveRig, collectBones } from './rig.js';
import { buildSceneFns, surfaceColor, texHeight } from './sdf.js';
import { meshSDF } from './mesh.js';
import { inv3 } from './compiler.js';
import { val0 } from './expr.js';
import { GltfBuilder, GL, mat4FromAffine, mat4Mul, mat4Translate, mat4Invert, eulerToQuat } from './gltf.js';

const PNG_SIGNATURE = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
const EXPORT_CHUNK_TRIANGLES = 8192;

function u32be(n) { return Uint8Array.of(n >>> 24, n >>> 16, n >>> 8, n); }
function pngChunk(type, data) {
  const typeBytes = new TextEncoder().encode(type);
  const body = new Uint8Array(typeBytes.length + data.length);
  body.set(typeBytes); body.set(data, typeBytes.length);
  let crc = 0xffffffff;
  for (const byte of body) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  crc = (crc ^ 0xffffffff) >>> 0;
  return [u32be(data.length), body, u32be(crc)];
}

async function encodePng(width, height, rgba) {
  const scanlines = new Uint8Array(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) scanlines.set(rgba.subarray(y * width * 4, (y + 1) * width * 4), y * (width * 4 + 1) + 1);
  if (typeof CompressionStream !== 'function') throw new Error('este ambiente não oferece compressão PNG (CompressionStream)');
  const stream = new Blob([scanlines]).stream().pipeThrough(new CompressionStream('deflate'));
  const compressed = new Uint8Array(await new Response(stream).arrayBuffer());
  const chunks = [PNG_SIGNATURE, ...pngChunk('IHDR', Uint8Array.from([...u32be(width), ...u32be(height), 8, 6, 0, 0, 0])), ...pngChunk('IDAT', compressed), ...pngChunk('IEND', new Uint8Array())];
  const png = new Uint8Array(chunks.reduce((sum, chunk) => sum + chunk.length, 0));
  let offset = 0;
  for (const chunk of chunks) { png.set(chunk, offset); offset += chunk.length; }
  return png;
}

const linearToSrgb = (x) => {
  const v = Math.max(0, Math.min(1, x));
  return Math.round(255 * (v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055));
};

const sub3 = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot3 = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross3 = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm3 = (a) => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };

// Atlas de cor (e, se heightAt existir, de normais): um bloco por triângulo.
// sampleColor(x, y, z, n) recebe a normal da face (para a projeção triplanar);
// heightAt(x, y, z, n) devolve { h, amp, e } do relevo: altura 0..1, amplitude (m) e passo de derivação (m).
async function bakeTextureAtlas(positions, indices, sampleColor, heightAt = null, normals = null, content = 8) {
  // bloco de cada triângulo: content x content texels de conteúdo + 1 de margem em cada lado
  const TILE = content + 2;
  const triangleCount = indices.length / 3;
  const grid = Math.ceil(Math.sqrt(triangleCount));
  const width = 2 ** Math.ceil(Math.log2(grid * TILE));
  const uv = new Float32Array(triangleCount * 6);
  const rgba = new Uint8Array(width * width * 4);
  const nrgba = heightAt ? new Uint8Array(width * width * 4) : null;
  const sample = (x, y, z, n) => sampleColor(x, y, z, n).map(linearToSrgb);
  const coords = (corner, left, top) => {
    const x0 = (left + 1.5) / width, x1 = (left + content + 0.5) / width;
    // glTF tem a origem de V no topo da imagem (sem inversão): linha py = content é sy = 0, py = 1 é sy = 1
    const v0 = (top + content + 0.5) / width, v1 = (top + 1.5) / width;
    return corner === 0 ? [x0, v0] : corner === 1 ? [x1, v0] : [x0, v1];
  };

  for (let tri = 0; tri < triangleCount; tri++) {
    const tileX = (tri % grid) * TILE, tileY = Math.floor(tri / grid) * TILE;
    const points = [0, 1, 2].map((corner) => {
      const v = indices[tri * 3 + corner] * 3;
      return [positions[v], positions[v + 1], positions[v + 2]];
    });
    for (let corner = 0; corner < 3; corner++) uv.set(coords(corner, tileX, tileY), (tri * 3 + corner) * 2);
    // normal da face, orientada como as normais de vértice da malha
    let nf = norm3(cross3(sub3(points[1], points[0]), sub3(points[2], points[0])));
    if (normals) {
      const a = indices[tri * 3] * 3;
      if (dot3(nf, [normals[a], normals[a + 1], normals[a + 2]]) < 0) nf = nf.map((c) => -c);
    }
    // quadro tangente como o dos visualizadores glTF: T no sentido de +u, B no de -v (sy crescente)
    const T = norm3(sub3(points[1], points[0]));
    const e2 = sub3(points[2], points[0]);
    const B = norm3(sub3(e2, T.map((c) => c * dot3(e2, T))));
    // Bake a private UV chart per triangle. This preserves the exact 3D
    // procedural coordinates, including noise that changes through depth.
    for (let py = 0; py < TILE; py++) for (let px = 0; px < TILE; px++) {
      const sx = Math.max(-0.15, Math.min(1.15, (px - 1) / (content - 1)));
      const sy = Math.max(-0.15, Math.min(1.15, 1 - (py - 1) / (content - 1)));
      const weights = [1 - sx - sy, sx, sy];
      const point = [0, 1, 2].map((axis) => points.reduce((sum, p, i) => sum + p[axis] * weights[i], 0));
      const color = sample(...point, nf);
      const at = ((tileY + py) * width + tileX + px) * 4;
      rgba[at] = color[0]; rgba[at + 1] = color[1]; rgba[at + 2] = color[2]; rgba[at + 3] = 255;
      if (nrgba) {
        const h0 = heightAt(...point, nf);
        let nx = 0, ny = 0;
        if (h0.amp > 0) {
          const e = h0.e;
          const gT = (heightAt(...point.map((c, k) => c + T[k] * e), nf).h - h0.h) / e;
          const gB = (heightAt(...point.map((c, k) => c + B[k] * e), nf).h - h0.h) / e;
          // inclinação da superfície: n' ~ N - amp * grad(h); limitada para não virar uma parede
          nx = Math.max(-4, Math.min(4, -h0.amp * gT));
          ny = Math.max(-4, Math.min(4, -h0.amp * gB));
        }
        const nl = Math.hypot(nx, ny, 1);
        nrgba[at] = Math.round(((nx / nl) * 0.5 + 0.5) * 255);
        nrgba[at + 1] = Math.round(((ny / nl) * 0.5 + 0.5) * 255);
        nrgba[at + 2] = Math.round(((1 / nl) * 0.5 + 0.5) * 255);
        nrgba[at + 3] = 255;
      }
    }
  }
  return { uv, png: await encodePng(width, width, rgba), normalPng: nrgba ? await encodePng(width, width, nrgba) : null };
}

// Menor tamanho de padrão das texturas de uma forma (Infinity se não tiver textura), corrigido pelas escalas.
const TEX_SIZE_DEFAULT = { 1: 0.25, 2: 0.06, 3: 0.3, 4: 0.1, 5: 0.25, 6: 0.25, 7: 1, 8: 0.3, 9: 0.1 };
function smallestTexture(s, k = 1) {
  let m = Infinity;
  if (s.kind === 'material' && s.props.tex) {
    const t = s.props.tex;
    // o degradê é suave: o tamanho dele é a extensão inteira; os outros padrões têm detalhe de `size`
    m = (t.size ?? TEX_SIZE_DEFAULT[t.kind] ?? 0.25) * k * (t.kind === 7 ? 0.5 : 1);
  }
  const kk = s.kind === 'scale' ? k * Math.min(...s.props.s.map((v) => Math.abs(val0(v)))) : k;
  for (const c of s.children) m = Math.min(m, smallestTexture(c, kk));
  return m;
}

// Raios de arredondamento de uma forma: .round(), box(round=), cylinder(round=), extrude/polygon/star(round=),
// corrigidos pelas escalas no caminho.
function fillets(s, k = 1, out = []) {
  const P = s.props;
  if ((s.kind === 'box' || s.kind === 'extrude' || s.kind === 'round') && P.r > 0) out.push(P.r * k);
  if (s.kind === 'cylinder' && P.round > 0) out.push(P.round * k);
  const kk = s.kind === 'scale' ? k * Math.min(...P.s.map((v) => Math.abs(val0(v)))) : k;
  for (const c of s.children) fillets(c, kk, out);
  return out;
}

const IDENT = [1, 0, 0, 0, 1, 0, 0, 0, 1];
const isIdent = (m, t) => m.every((v, i) => Math.abs(v - IDENT[i]) < 1e-12) && t.every((v) => Math.abs(v) < 1e-12);
const hasBound = (s) => (s._hasBound ??= s.kind === 'bound' || s.children.some(hasBound));

const mergeMat = (mat, P) => {
  const out = { ...mat };
  for (const k of ['color', 'rough', 'metal', 'glow', 'tex']) if (P[k] !== null && P[k] !== undefined) out[k] = P[k];
  return out;
};

// reaplica transformação e material acumulados (como os resíduos do compilador)
function wrap(s, m, t, ds, mat) {
  let node = s;
  if (Object.keys(mat).length) node = new Shape('material', { color: null, rough: null, metal: null, glow: null, tex: null, ...mat }, [node]);
  if (!isIdent(m, t)) node = new Shape('affine', { m, t, minv: inv3(m), ds }, [node]);
  return node;
}

// Separa a cena em partes: estáticas (malha comum) e presas a ossos (malha com skin).
function splitParts(shapes) {
  const parts = [];
  const visit = (s, m, t, ds, mat, name) => {
    const c0 = s.children[0];
    if (!hasBound(s)) { parts.push({ kind: 'static', shape: wrap(s, m, t, ds, mat), name }); return; }
    switch (s.kind) {
      case 'bound':
        parts.push({ kind: 'skin', bone: s.props.bone, shape: wrap(resolveRig([c0])[0], m, t, ds, mat), outer: { m, t }, name: name ? `${name}/${s.props.bone.name}` : s.props.bone.name });
        return;
      case 'translate': {
        const mv = mulMV(m, s.props.v.map(val0));
        visit(c0, m, t.map((v, i) => v + mv[i]), ds, mat, name);
        return;
      }
      case 'rotate': visit(c0, mul3(m, s.props.m), t, ds, mat, name); return;
      case 'scale': {
        const S = s.props.s.map(val0);
        visit(c0, mul3(m, [S[0], 0, 0, 0, S[1], 0, 0, 0, S[2]]), t, ds * Math.min(...S), mat, name);
        return;
      }
      case 'material': visit(c0, m, t, ds, mergeMat(mat, s.props), name); return;
      case 'label': visit(c0, m, t, ds, mat, s.props.name); return;
      // união (mesmo suave) entre partes de ossos diferentes: cada parte vira sua malha
      case 'union': s.children.forEach((c) => visit(c, m, t, ds, mat, name)); return;
    }
    // outra operação envolvendo ossos: exporta parada, na pose de t = 0
    parts.push({ kind: 'static', shape: wrap(resolveRig([s])[0], m, t, ds, mat), name, posed: true });
  };
  shapes.forEach((s) => visit(s, IDENT, [0, 0, 0], 1, {}, null));
  return parts;
}

// Contexto compartilhado por todas as peças (precisa ser igual em qualquer worker).
function sceneContext(parts, res) {
  const finite = parts.filter((p) => isFiniteBB(p.shape.bbox)).map((p) => p.shape.bbox);
  const sceneBB = finite.length ? unionBB(finite) : { min: [-1, 0, -1], max: [1, 1, 1] };
  const sceneMax = Math.max(...size(sceneBB), 0.01);
  return { res, sceneBB, sceneMax };
}

/**
 * Geometria de uma peça: só dados (arrays e PNGs), sem o glTF, para poder rodar em outro worker.
 * Devolve { name, kind, materialProps, chunks: [{ positions, normals, colors | uv, png, normalPng }], triangles, vertices }
 * ou { name, empty: true } se a peça não tem superfície.
 */
export async function partGeometry(p, pi, { res, sceneBB, sceneMax }) {
  let bb = p.shape.bbox;
  const infinite = !isFiniteBB(bb);
  if (infinite) {
    // chão infinito: recorta uma região em volta da cena
    const margin = Math.max(3, sceneMax * 0.25);
    bb = {
      min: [sceneBB.min[0] - margin, Math.max(bb.min[1], -0.25), sceneBB.min[2] - margin],
      max: [sceneBB.max[0] + margin, Math.min(bb.max[1], 0.25), sceneBB.max[2] + margin],
    };
  }
  const dims = size(bb);
  const partMax = Math.max(...dims);
  // Cada peça é malhada na própria resolução: res células na sua maior dimensão, independente do
  // tamanho da cena (uma pétala de 10 cm numa cena de 8 m não pode herdar a célula da cena).
  // Em eixos finos, pelo menos 6 camadas, para placas e lâminas não perderem a espessura.
  const base = partMax / res;
  // arredondamentos menores que a célula viram ondulações: a célula fica abaixo do menor raio visível
  // na escala da peça (um detalhe de 2 cm num boneco de 1,75 m não justifica refinar o boneco inteiro)
  const fillet = Math.min(Infinity, ...fillets(p.shape).filter((r) => r >= partMax / 60));
  const featureCell = Number.isFinite(fillet) ? Math.max(fillet * 0.6, partMax / 160) : Infinity;
  let cell = infinite ? dims.map(() => partMax / res) : dims.map((d) => Math.min(base, featureCell, Math.max(d, 1e-4) / 6));
  const cells = () => dims.reduce((n, d, i) => n * (Math.ceil(d / cell[i]) + 5), 1);
  while (cells() > 12e6) cell = cell.map((c) => c * 1.25);
  const { dist, mat: matFn } = buildSceneFns(p.shape);
  // A textured SDF has a procedural color in the preview; it is baked into a PNG atlas (textured)
  // or into vertex colors (COLOR_0) so standard viewers show it.
  let textured = false, bumped = false;
  const colorAt = (x, y, z) => {
    const r = matFn(x, y, z);
    if (r.tx) { textured = true; if (r.tx[3] > 0) bumped = true; }
    return surfaceColor(r);
  };
  // altura do relevo (0..1) com a amplitude e o passo de derivação (em metros) da textura
  const heightAt = (x, y, z, n) => {
    const r = matFn(x, y, z);
    if (!r.tx || !(r.tx[3] > 0) || !r.tp) return { h: 0, amp: 0, e: 1 };
    return { h: texHeight(r.tp, r.tx, n), amp: r.tx[3] * r.tx[1], e: r.tx[1] * 0.02 };
  };
  // peças com textura não podem ganhar triângulos maiores que o padrão (o atlas tem poucos texels
  // por triângulo); sem textura, a simplificação fica livre
  const texSize = smallestTexture(p.shape);
  const simplify = { tolerance: Math.min(...cell) * 0.35, maxEdge: Number.isFinite(texSize) ? texSize * 0.5 : Infinity };
  let mesh = meshSDF(dist, bb, { cell, colorAt, simplify });
  // peças finas espalhadas numa parte grande (postes...) passam entre os pontos da grade:
  // tenta de novo com voxel menor
  for (let tries = 0; !mesh && tries < 3; tries++) {
    cell = cell.map((c) => c / 2);
    if (cells() > 12e6) break;
    mesh = meshSDF(dist, bb, { cell, colorAt, simplify });
  }
  const name = p.name ?? `parte${pi}`;
  if (!mesh) return { name, empty: true };
  const quality = meshQuality(mesh, dist, cell, dims, infinite ? null : bb);

  // material da parte: o do primeiro vértice (a cor de cada vértice vai em COLOR_0 ou no atlas)
  const m0 = matFn(mesh.positions[0], mesh.positions[1], mesh.positions[2]);
  const glow = Math.min(1, Math.max(0, m0.glow));
  const materialProps = {
    name: p.name ?? `material${pi}`,
    pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: m0.metal, roughnessFactor: Math.max(0.03, m0.rough) },
    ...(glow > 0 ? { emissiveFactor: m0.c.map((c) => Math.min(1, c * glow * 2)) } : {}),
  };
  const triangles = mesh.indices.length / 3;
  if (!textured) {
    return { name, kind: p.kind, materialProps, quality, triangles, vertices: mesh.positions.length / 3, chunks: [{ positions: mesh.positions, normals: mesh.normals, colors: mesh.colors, indices: mesh.indices }] };
  }
  // Texels por triângulo: com malha fina os triângulos são pequenos, então menos texels mantêm a
  // mesma densidade de textura por metro (8x8 com ~6 mil triângulos, até 3x3 em malhas densas).
  const texelsPerTriangle = Math.max(3, Math.min(8, Math.round(8 * Math.sqrt(6000 / Math.max(1, triangles)))));
  const chunks = [];
  for (let first = 0; first < mesh.indices.length; first += EXPORT_CHUNK_TRIANGLES * 3) {
    const triangleIndices = mesh.indices.subarray(first, Math.min(first + EXPORT_CHUNK_TRIANGLES * 3, mesh.indices.length));
    const vertexCount = triangleIndices.length;
    const positions = new Float32Array(vertexCount * 3), normals = new Float32Array(vertexCount * 3);
    for (let i = 0; i < vertexCount; i++) {
      const source = triangleIndices[i] * 3;
      positions.set(mesh.positions.subarray(source, source + 3), i * 3);
      normals.set(mesh.normals.subarray(source, source + 3), i * 3);
    }
    const atlas = await bakeTextureAtlas(positions, Uint32Array.from({ length: vertexCount }, (_, i) => i), (x, y, z, n) => surfaceColor(matFn(x, y, z), n), bumped ? heightAt : null, normals, texelsPerTriangle);
    chunks.push({ positions, normals, uv: atlas.uv, png: atlas.png, normalPng: atlas.normalPng });
  }
  return { name, kind: p.kind, materialProps, quality, triangles, vertices: mesh.indices.length, chunks };
}

// Relatório de qualidade de uma malha em relação à forma de origem (a distância assinada):
// desvio dos vértices (devem estar na superfície) e, nas faces, o desvio dos centros dos triângulos.
// Os valores são em metros; `cell` é o tamanho da célula usada, para dar escala ao desvio.
function meshQuality(mesh, dist, cell, dims, bbox = null) {
  const P = mesh.positions, I = mesh.indices;
  const nv = P.length / 3, nt = I.length / 3;
  const stride = Math.max(1, Math.floor(nv / 4000));
  let max = 0, sum = 0, n = 0;
  for (let v = 0; v < nv; v += stride) {
    const d = Math.abs(dist(P[v * 3], P[v * 3 + 1], P[v * 3 + 2]));
    if (d > max) max = d;
    sum += d;
    n++;
  }
  // centros de triângulos: pegam faces simplificadas que se afastaram da superfície entre os vértices
  const ts = Math.max(1, Math.floor(nt / 4000));
  let faceMax = 0;
  for (let t = 0; t < nt; t += ts) {
    const a = I[t * 3] * 3, b = I[t * 3 + 1] * 3, c = I[t * 3 + 2] * 3;
    const d = Math.abs(dist((P[a] + P[b] + P[c]) / 3, (P[a + 1] + P[b + 1] + P[c + 1]) / 3, (P[a + 2] + P[b + 2] + P[c + 2]) / 3));
    if (d > faceMax) faceMax = d;
  }
  const cellMin = Math.min(...cell);

  // Cobertura: peças mais finas que a célula somem na conversão e os vértices que sobram continuam "certos".
  // Compara o volume da malha (soma de tetraedros) com o volume da forma, estimado por pontos aleatórios.
  let volumeRatio = null, reason = null;
  if (bbox) {
    let vm = 0;
    for (let t = 0; t < nt; t++) {
      const a = I[t * 3] * 3, b = I[t * 3 + 1] * 3, c = I[t * 3 + 2] * 3;
      vm += P[a] * (P[b + 1] * P[c + 2] - P[b + 2] * P[c + 1]) - P[a + 1] * (P[b] * P[c + 2] - P[b + 2] * P[c]) + P[a + 2] * (P[b] * P[c + 1] - P[b + 1] * P[c]);
    }
    vm = Math.abs(vm / 6);
    const ext = bbox.max.map((v, i) => v - bbox.min[i]);
    let seed = 123456789, inside = 0;
    const rnd = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
    const N = 24000;
    for (let i = 0; i < N; i++) if (dist(bbox.min[0] + rnd() * ext[0], bbox.min[1] + rnd() * ext[1], bbox.min[2] + rnd() * ext[2]) < 0) inside++;
    // poucos pontos dentro = estimativa ruidosa: não conclui nada
    if (inside >= 150) volumeRatio = vm / ((inside / N) * ext[0] * ext[1] * ext[2]);
  }
  const rank = { ok: 0, 'atenção': 1, ruim: 2 };
  let status = Math.max(max, faceMax) <= cellMin * 0.6 ? 'ok' : Math.max(max, faceMax) <= cellMin ? 'atenção' : 'ruim';
  if (status !== 'ok') reason = 'desvio';
  if (volumeRatio !== null) {
    const lost = 1 - volumeRatio;
    const vs = lost > 0.3 ? 'ruim' : lost > 0.12 ? 'atenção' : 'ok';
    if (rank[vs] > rank[status]) { status = vs; reason = 'volume'; }
  }
  return { maxError: max, meanError: n ? sum / n : 0, faceError: faceMax, cell: cellMin, size: Math.max(...dims), volumeRatio, status, reason };
}

// Buffers de uma geometria (para transferir entre workers sem copiar)
export function geometryTransfer(geom) {
  const out = [];
  for (const c of geom.chunks ?? []) for (const k of ['positions', 'normals', 'colors', 'uv', 'png', 'normalPng', 'indices']) if (c[k]?.buffer) out.push(c[k].buffer);
  return [...new Set(out)];
}

/**
 * Sessão para um worker de peças: roda o script uma vez e malha peças sob demanda.
 * Os workers rodam o mesmo script (determinístico, inclusive com seed), então a lista de peças e o
 * contexto da cena são idênticos aos do processo principal.
 */
export function partSession(scene, res) {
  const parts = splitParts(scene.shapes);
  const ctx = sceneContext(parts, res);
  return { count: parts.length, build: (i) => partGeometry(parts[i], i, ctx) };
}

/**
 * Exporta a cena (resultado de runScript) para GLB.
 * opts.res: células na maior dimensão de cada peça (padrão 128).
 * opts.runParts(n, onDone): opcional; malha as n peças em paralelo (workers) e devolve as geometrias em ordem.
 * Devolve { glb: Uint8Array, stats }.
 */
export async function exportGLB(scene, { res = 128, onProgress = null, runParts = null } = {}) {
  if (!Number.isInteger(res) || res < 1 || res > 2048) throw new Error('res deve ser um inteiro entre 1 e 2048');
  const { duration = 4, fps = 30 } = scene.anim ?? {};
  if (!Number.isFinite(duration) || duration <= 0 || !Number.isFinite(fps) || fps <= 0 || duration * fps > 100000) {
    throw new Error('animação deve ter duration e fps positivos e no máximo 100000 amostras');
  }
  const t0 = Date.now();
  const warnings = [];
  const parts = splitParts(scene.shapes);
  const ctx = sceneContext(parts, res);

  if (parts.some((p) => p.kind === 'static' && p.shape.animated)) {
    warnings.push('partes animadas com time fora de ossos foram exportadas paradas (t = 0)');
  }

  // geometria das peças: em paralelo quando há workers, senão aqui mesmo
  let geoms = null;
  if (runParts && parts.length > 1) {
    try { geoms = await runParts(parts.length, onProgress); } catch (e) { warnings.push(`malha em paralelo falhou (${e.message}); usando um núcleo`); geoms = null; }
  }
  if (!geoms) {
    geoms = [];
    for (let pi = 0; pi < parts.length; pi++) {
      onProgress?.(pi, parts.length);
      geoms.push(await partGeometry(parts[pi], pi, ctx));
    }
  }

  const g = new GltfBuilder();
  const J = g.json;
  const bones = collectBones(scene.shapes);
  const jointIndex = new Map(bones.map((b, i) => [b, i]));
  const skinParts = parts.filter((p) => p.kind === 'skin');
  let vertices = 0, triangles = 0;
  const partReports = [];

  for (let pi = 0; pi < parts.length; pi++) {
    const p = parts[pi];
    const geom = geoms[pi];
    if (geom.empty) { warnings.push(`parte ${p.name ?? pi} não tem superfície`); partReports.push({ name: geom.name, empty: true }); continue; }
    partReports.push({ name: geom.name, kind: geom.kind, triangles: geom.triangles, textured: !!geom.chunks[0]?.uv, ...geom.quality });
    triangles += geom.triangles;
    vertices += geom.vertices;
    const skinAttrs = (n) => {
      if (p.kind !== 'skin') return {};
      const ji = jointIndex.get(p.bone), big = bones.length > 255;
      const joints = big ? new Uint16Array(n * 4) : new Uint8Array(n * 4);
      const weights = new Float32Array(n * 4);
      for (let v = 0; v < n; v++) { joints[v * 4] = ji; weights[v * 4] = 1; }
      return {
        JOINTS_0: g.accessor(joints, big ? GL.USHORT : GL.UBYTE, 'VEC4', { target: GL.ARRAY_BUFFER }),
        WEIGHTS_0: g.accessor(weights, GL.FLOAT, 'VEC4', { target: GL.ARRAY_BUFFER }),
      };
    };
    const primitives = [];
    const materialProps = geom.materialProps;
    for (const chunk of geom.chunks) {
      if (chunk.uv) {
        const vertexCount = chunk.positions.length / 3;
        const image = g.add('images', { name: `${p.name ?? `material${pi}`}-${primitives.length}.png`, bufferView: g.bufferView(chunk.png), mimeType: 'image/png' });
        const sampler = g.add('samplers', { magFilter: 9729, minFilter: 9729, wrapS: 33071, wrapT: 33071 });
        const texture = g.add('textures', { sampler, source: image });
        const extra = {};
        if (chunk.normalPng) {
          // normal map no mesmo atlas: o relevo (bump) da textura vai junto no GLB
          const nImage = g.add('images', { name: `${p.name ?? `material${pi}`}-${primitives.length}-normal.png`, bufferView: g.bufferView(chunk.normalPng), mimeType: 'image/png' });
          extra.normalTexture = { index: g.add('textures', { sampler, source: nImage }), texCoord: 0 };
        }
        const material = g.add('materials', { ...materialProps, ...extra, pbrMetallicRoughness: { ...materialProps.pbrMetallicRoughness, baseColorTexture: { index: texture, texCoord: 0 } } });
        const attributes = {
          POSITION: g.accessor(chunk.positions, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER, minmax: true }),
          NORMAL: g.accessor(chunk.normals, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
          TEXCOORD_0: g.accessor(chunk.uv, GL.FLOAT, 'VEC2', { target: GL.ARRAY_BUFFER }),
          ...skinAttrs(vertexCount),
        };
        const indices = g.accessor(vertexCount < 65536 ? Uint16Array.from({ length: vertexCount }, (_, i) => i) : Uint32Array.from({ length: vertexCount }, (_, i) => i), vertexCount < 65536 ? GL.USHORT : GL.UINT, 'SCALAR', { target: GL.ELEMENT_ARRAY_BUFFER });
        primitives.push({ attributes, indices, material });
      } else {
        const nv = chunk.positions.length / 3;
        const material = g.add('materials', materialProps);
        const attributes = {
          POSITION: g.accessor(chunk.positions, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER, minmax: true }),
          NORMAL: g.accessor(chunk.normals, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
          COLOR_0: g.accessor(chunk.colors, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
          ...skinAttrs(nv),
        };
        const small = nv < 65536;
        const indices = g.accessor(small ? Uint16Array.from(chunk.indices) : chunk.indices, small ? GL.USHORT : GL.UINT, 'SCALAR', { target: GL.ELEMENT_ARRAY_BUFFER });
        primitives.push({ attributes, indices, material });
      }
    }
    const meshIndex = g.add('meshes', { name: p.name ?? `parte${pi}`, primitives });
    const node = { name: p.name ?? `parte${pi}`, mesh: meshIndex };
    if (p.kind === 'skin') node.skin = 0;
    J.scenes[0].nodes.push(g.add('nodes', node));
  }

  // ---- esqueleto: juntas na pose de repouso (sem rotação), filhas do nó "armature"
  let animated = false;
  if (bones.length && skinParts.length) {
    const outer = skinParts[0].outer;
    if (skinParts.some((p) => p.outer.m.some((v, i) => Math.abs(v - outer.m[i]) > 1e-9) || p.outer.t.some((v, i) => Math.abs(v - outer.t[i]) > 1e-9))) {
      warnings.push('partes do mesmo esqueleto com transformações externas diferentes: usando a da primeira');
    }
    const outer4 = mat4FromAffine(outer.m, outer.t);
    const armature = { name: bones[0].skel.name, children: [] };
    if (!isIdent(outer.m, outer.t)) armature.matrix = outer4;
    const armatureIndex = g.add('nodes', armature);
    J.scenes[0].nodes.push(armatureIndex);

    const base = (b) => (b.parent ? b.head.map((v, i) => v - b.parent.head[i]) : [...b.head]);
    const nodeOf = new Map();
    for (const b of bones) {
      const n = { name: b.name, translation: base(b).map((v, i) => v + val0(b.offset[i])) };
      const ang = b.angles.map(val0);
      if (ang.some((a) => a !== 0)) n.rotation = eulerToQuat(...ang);
      const ni = g.add('nodes', n);
      nodeOf.set(b, ni);
      if (b.parent) (J.nodes[nodeOf.get(b.parent)].children ??= []).push(ni);
      else armature.children.push(ni);
    }
    const ibm = new Float32Array(bones.length * 16);
    bones.forEach((b, i) => ibm.set(mat4Invert(mat4Mul(outer4, mat4Translate(b.head))), i * 16));
    g.add('skins', {
      name: bones[0].skel.name,
      joints: bones.map((b) => nodeOf.get(b)),
      skeleton: armatureIndex,
      inverseBindMatrices: g.accessor(ibm, GL.FLOAT, 'MAT4'),
    });

    // ---- animação: amostra as rotações e movimentos que dependem de time
    const animBones = bones.filter((b) => b.animated);
    if (animBones.length) {
      animated = true;
      const { duration = 4, fps = 30 } = scene.anim ?? {};
      const n = Math.max(2, Math.round(duration * fps) + 1);
      const times = Float32Array.from({ length: n }, (_, i) => (i * duration) / (n - 1));
      const input = g.accessor(times, GL.FLOAT, 'SCALAR', { minmax: true });
      const samplers = [], channels = [];
      for (const b of animBones) {
        if (b.angles.some((a) => typeof a !== 'number')) {
          const q = new Float32Array(n * 4);
          let prev = null;
          times.forEach((tt, i) => {
            let r = eulerToQuat(...b.anglesAt(tt));
            // mantém o sinal contínuo para a interpolação não dar a volta longa
            if (prev && r[0] * prev[0] + r[1] * prev[1] + r[2] * prev[2] + r[3] * prev[3] < 0) r = r.map((v) => -v);
            q.set(r, i * 4);
            prev = r;
          });
          samplers.push({ input, output: g.accessor(q, GL.FLOAT, 'VEC4'), interpolation: 'LINEAR' });
          channels.push({ sampler: samplers.length - 1, target: { node: nodeOf.get(b), path: 'rotation' } });
        }
        if (b.offset.some((a) => typeof a !== 'number')) {
          const tr = new Float32Array(n * 3);
          const bt = base(b);
          times.forEach((tt, i) => tr.set(b.offsetAt(tt).map((v, k) => v + bt[k]), i * 3));
          samplers.push({ input, output: g.accessor(tr, GL.FLOAT, 'VEC3'), interpolation: 'LINEAR' });
          channels.push({ sampler: samplers.length - 1, target: { node: nodeOf.get(b), path: 'translation' } });
        }
      }
      g.add('animations', { name: 'anim', samplers, channels });
    }
  }

  const glb = g.toGLB();
  return {
    glb,
    stats: { parts: parts.length, partReports, vertices, triangles, bones: bones.length, animated, bytes: glb.byteLength, ms: Date.now() - t0, warnings },
  };
}
