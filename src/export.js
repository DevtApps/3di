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
const ATLAS_TILE = 10; // 8 texels de conteúdo + 1 texel de margem em cada lado

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
async function bakeTextureAtlas(positions, indices, sampleColor, heightAt = null, normals = null) {
  const triangleCount = indices.length / 3;
  const grid = Math.ceil(Math.sqrt(triangleCount));
  const width = 2 ** Math.ceil(Math.log2(grid * ATLAS_TILE));
  const uv = new Float32Array(triangleCount * 6);
  const rgba = new Uint8Array(width * width * 4);
  const nrgba = heightAt ? new Uint8Array(width * width * 4) : null;
  const sample = (x, y, z, n) => sampleColor(x, y, z, n).map(linearToSrgb);
  const coords = (corner, left, top) => {
    const x0 = (left + 1.5) / width, x1 = (left + 8.5) / width;
    // glTF tem a origem de V no topo da imagem (sem inversão): linha py = 8 é sy = 0, py = 1 é sy = 1
    const v0 = (top + 8.5) / width, v1 = (top + 1.5) / width;
    return corner === 0 ? [x0, v0] : corner === 1 ? [x1, v0] : [x0, v1];
  };

  for (let tri = 0; tri < triangleCount; tri++) {
    const tileX = (tri % grid) * ATLAS_TILE, tileY = Math.floor(tri / grid) * ATLAS_TILE;
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
    for (let py = 0; py < ATLAS_TILE; py++) for (let px = 0; px < ATLAS_TILE; px++) {
      const sx = Math.max(-0.15, Math.min(1.15, (px - 1) / 7));
      const sy = Math.max(-0.15, Math.min(1.15, 1 - (py - 1) / 7));
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

/**
 * Exporta a cena (resultado de runScript) para GLB.
 * opts.res: células na maior dimensão da cena (padrão 128); define o tamanho do voxel.
 * Devolve { glb: Uint8Array, stats }.
 */
export async function exportGLB(scene, { res = 128, onProgress = null } = {}) {
  if (!Number.isInteger(res) || res < 1 || res > 2048) throw new Error('res deve ser um inteiro entre 1 e 2048');
  const { duration = 4, fps = 30 } = scene.anim ?? {};
  if (!Number.isFinite(duration) || duration <= 0 || !Number.isFinite(fps) || fps <= 0 || duration * fps > 100000) {
    throw new Error('animação deve ter duration e fps positivos e no máximo 100000 amostras');
  }
  const t0 = Date.now();
  const warnings = [];
  const parts = splitParts(scene.shapes);
  const finite = parts.filter((p) => isFiniteBB(p.shape.bbox)).map((p) => p.shape.bbox);
  const sceneBB = finite.length ? unionBB(finite) : { min: [-1, 0, -1], max: [1, 1, 1] };
  const sceneMax = Math.max(...size(sceneBB), 0.01);
  // mesmo tamanho de voxel para a cena toda: res células na maior dimensão da cena
  const h = sceneMax / res;

  if (parts.some((p) => p.kind === 'static' && p.shape.animated)) {
    warnings.push('partes animadas com time fora de ossos foram exportadas paradas (t = 0)');
  }

  const g = new GltfBuilder();
  const J = g.json;
  const bones = collectBones(scene.shapes);
  const jointIndex = new Map(bones.map((b, i) => [b, i]));
  const skinParts = parts.filter((p) => p.kind === 'skin');
  let vertices = 0, triangles = 0;

  for (let pi = 0; pi < parts.length; pi++) {
    const p = parts[pi];
    onProgress?.(pi, parts.length);
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
    // voxel de cada eixo: o da cena (peças pequenas ganham pelo menos 12 células), mas no máximo
    // 1/2.5 da dimensão da parte nesse eixo, senão peças finas somem.
    // O chão recortado usa o voxel que cabe em res células.
    // cada peça ganha resolução própria: pelo menos 24 (ou res/4) células na sua maior dimensão, para peças
    // pequenas numa cena grande não virarem bolhas (antes herdavam a célula da cena inteira)
    const base = Math.min(h, Math.max(...dims) / Math.max(24, res * 0.25));
    // arredondamentos menores que a célula viram ondulações: a célula fica abaixo do menor raio da peça
    // (só contam os visíveis na escala da peça: um detalhe de 2 cm num boneco de 1,75 m não justifica
    // refinar o boneco inteiro, mas os 3 cm de borda de uma estrela de 1 m sim)
    const fillet = Math.min(Infinity, ...fillets(p.shape).filter((r) => r >= Math.max(...dims) / 60));
    const featureCell = Number.isFinite(fillet) ? Math.max(fillet * 0.6, Math.max(...dims) / 100) : Infinity;
    let cell = infinite ? dims.map(() => Math.max(...dims) / res) : dims.map((d) => Math.min(base, featureCell, Math.max(d, 1e-4) / 2.5));
    const cells = () => dims.reduce((n, d, i) => n * (Math.ceil(d / cell[i]) + 5), 1);
    while (cells() > 12e6) cell = cell.map((c) => c * 1.25);
    const { dist, mat: matFn } = buildSceneFns(p.shape);
    // Preserve the evaluated material at each mesh vertex. A textured SDF has
    // a procedural color in the preview; sampling only RGB loses its material
    // when the GLB is opened in a standard viewer. COLOR_0 is supported by
    // glTF, so bake the procedural texture into vertex colors.
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
    let mesh = meshSDF(dist, bb, { cell, colorAt });
    // peças finas espalhadas numa parte grande (postes...) passam entre os pontos da grade:
    // tenta de novo com voxel menor
    for (let tries = 0; !mesh && tries < 3; tries++) {
      cell = cell.map((c) => c / 2);
      if (cells() > 12e6) break;
      mesh = meshSDF(dist, bb, { cell, colorAt });
    }
    if (!mesh) { warnings.push(`parte ${p.name ?? pi} não tem superfície`); continue; }
    const nv = mesh.positions.length / 3;
    triangles += mesh.indices.length / 3;

    // material da parte: o do primeiro vértice (a cor de cada vértice vai em COLOR_0)
    const m0 = matFn(mesh.positions[0], mesh.positions[1], mesh.positions[2]);
    const glow = Math.min(1, Math.max(0, m0.glow));
    const materialProps = {
      name: p.name ?? `material${pi}`,
      pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: m0.metal, roughnessFactor: Math.max(0.03, m0.rough) },
      ...(glow > 0 ? { emissiveFactor: m0.c.map((c) => Math.min(1, c * glow * 2)) } : {}),
    };
    const primitives = [];
    if (textured) {
      vertices += mesh.indices.length;
      for (let first = 0; first < mesh.indices.length; first += EXPORT_CHUNK_TRIANGLES * 3) {
        const triangleIndices = mesh.indices.subarray(first, Math.min(first + EXPORT_CHUNK_TRIANGLES * 3, mesh.indices.length));
        const vertexCount = triangleIndices.length;
        const positions = new Float32Array(vertexCount * 3), normals = new Float32Array(vertexCount * 3);
        for (let i = 0; i < vertexCount; i++) {
          const source = triangleIndices[i] * 3;
          positions.set(mesh.positions.subarray(source, source + 3), i * 3);
          normals.set(mesh.normals.subarray(source, source + 3), i * 3);
        }
        const atlas = await bakeTextureAtlas(positions, Uint32Array.from({ length: vertexCount }, (_, i) => i), (x, y, z, n) => surfaceColor(matFn(x, y, z), n), bumped ? heightAt : null, normals);
        const imageView = g.bufferView(atlas.png);
        const image = g.add('images', { name: `${p.name ?? `material${pi}`}-${primitives.length}.png`, bufferView: imageView, mimeType: 'image/png' });
        const sampler = g.add('samplers', { magFilter: 9729, minFilter: 9729, wrapS: 33071, wrapT: 33071 });
        const texture = g.add('textures', { sampler, source: image });
        const extra = {};
        if (atlas.normalPng) {
          // normal map no mesmo atlas: o relevo (bump) da textura vai junto no GLB
          const nImage = g.add('images', { name: `${p.name ?? `material${pi}`}-${primitives.length}-normal.png`, bufferView: g.bufferView(atlas.normalPng), mimeType: 'image/png' });
          extra.normalTexture = { index: g.add('textures', { sampler, source: nImage }), texCoord: 0 };
        }
        const material = g.add('materials', { ...materialProps, ...extra, pbrMetallicRoughness: { ...materialProps.pbrMetallicRoughness, baseColorTexture: { index: texture, texCoord: 0 } } });
        const attributes = {
          POSITION: g.accessor(positions, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER, minmax: true }),
          NORMAL: g.accessor(normals, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
          TEXCOORD_0: g.accessor(atlas.uv, GL.FLOAT, 'VEC2', { target: GL.ARRAY_BUFFER }),
        };
        if (p.kind === 'skin') {
          const ji = jointIndex.get(p.bone), big = bones.length > 255;
          const joints = big ? new Uint16Array(vertexCount * 4) : new Uint8Array(vertexCount * 4);
          const weights = new Float32Array(vertexCount * 4);
          for (let v = 0; v < vertexCount; v++) { joints[v * 4] = ji; weights[v * 4] = 1; }
          attributes.JOINTS_0 = g.accessor(joints, big ? GL.USHORT : GL.UBYTE, 'VEC4', { target: GL.ARRAY_BUFFER });
          attributes.WEIGHTS_0 = g.accessor(weights, GL.FLOAT, 'VEC4', { target: GL.ARRAY_BUFFER });
        }
        const indices = g.accessor(vertexCount < 65536 ? Uint16Array.from({ length: vertexCount }, (_, i) => i) : Uint32Array.from({ length: vertexCount }, (_, i) => i), vertexCount < 65536 ? GL.USHORT : GL.UINT, 'SCALAR', { target: GL.ELEMENT_ARRAY_BUFFER });
        primitives.push({ attributes, indices, material });
      }
    } else {
      vertices += nv;
      const material = g.add('materials', materialProps);
      const attributes = {
        POSITION: g.accessor(mesh.positions, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER, minmax: true }),
        NORMAL: g.accessor(mesh.normals, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
        COLOR_0: g.accessor(mesh.colors, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
      };
      if (p.kind === 'skin') {
        const ji = jointIndex.get(p.bone), big = bones.length > 255;
        const joints = big ? new Uint16Array(nv * 4) : new Uint8Array(nv * 4);
        const weights = new Float32Array(nv * 4);
        for (let v = 0; v < nv; v++) { joints[v * 4] = ji; weights[v * 4] = 1; }
        attributes.JOINTS_0 = g.accessor(joints, big ? GL.USHORT : GL.UBYTE, 'VEC4', { target: GL.ARRAY_BUFFER });
        attributes.WEIGHTS_0 = g.accessor(weights, GL.FLOAT, 'VEC4', { target: GL.ARRAY_BUFFER });
      }
      const small = nv < 65536;
      const indices = g.accessor(small ? Uint16Array.from(mesh.indices) : mesh.indices, small ? GL.USHORT : GL.UINT, 'SCALAR', { target: GL.ELEMENT_ARRAY_BUFFER });
      primitives.push({ attributes, indices, material });
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
    stats: { parts: parts.length, vertices, triangles, bones: bones.length, animated, bytes: glb.byteLength, ms: Date.now() - t0, warnings },
  };
}
