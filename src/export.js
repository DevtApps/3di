// Exportação da cena para glTF binário (.glb).
// - Cada forma mostrada vira uma malha (SDF -> surface nets), com cor por vértice.
// - Partes presas a ossos (.bind) viram malhas com skin (peso 1 no osso) na pose de repouso;
//   o esqueleto vira a hierarquia de juntas e as rotações/movimentos com `time` viram
//   uma animação amostrada (duration/fps de animation()).
// - Outras animações com `time` (fora de ossos) são exportadas paradas, em t = 0.
import { Shape, isFiniteBB, mulMV, mul3, size, unionBB } from './shapes.js';
import { resolveRig, collectBones } from './rig.js';
import { buildSceneFns, surfaceColor } from './sdf.js';
import { meshSDF } from './mesh.js';
import { inv3 } from './compiler.js';
import { val0 } from './expr.js';
import { GltfBuilder, GL, mat4FromAffine, mat4Mul, mat4Translate, mat4Invert, eulerToQuat } from './gltf.js';

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
export function exportGLB(scene, { res = 128, onProgress = null } = {}) {
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

  parts.forEach((p, pi) => {
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
    const base = Math.min(h, Math.max(...dims) / 12);
    let cell = infinite ? dims.map(() => Math.max(...dims) / res) : dims.map((d) => Math.min(base, Math.max(d, 1e-4) / 2.5));
    const cells = () => dims.reduce((n, d, i) => n * (Math.ceil(d / cell[i]) + 5), 1);
    while (cells() > 12e6) cell = cell.map((c) => c * 1.25);
    const { dist, mat: matFn } = buildSceneFns(p.shape);
    const colorAt = (x, y, z) => surfaceColor(matFn(x, y, z));
    let mesh = meshSDF(dist, bb, { cell, colorAt });
    // peças finas espalhadas numa parte grande (postes...) passam entre os pontos da grade:
    // tenta de novo com voxel menor
    for (let tries = 0; !mesh && tries < 3; tries++) {
      cell = cell.map((c) => c / 2);
      if (cells() > 12e6) break;
      mesh = meshSDF(dist, bb, { cell, colorAt });
    }
    if (!mesh) { warnings.push(`parte ${p.name ?? pi} não tem superfície`); return; }
    const nv = mesh.positions.length / 3;
    vertices += nv;
    triangles += mesh.indices.length / 3;

    // material da parte: o do primeiro vértice (a cor de cada vértice vai em COLOR_0)
    const m0 = matFn(mesh.positions[0], mesh.positions[1], mesh.positions[2]);
    const glow = Math.min(1, Math.max(0, m0.glow));
    const material = g.add('materials', {
      name: p.name ?? `material${pi}`,
      pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: m0.metal, roughnessFactor: Math.max(0.03, m0.rough) },
      ...(glow > 0 ? { emissiveFactor: m0.c.map((c) => Math.min(1, c * glow * 2)) } : {}),
    });

    const attributes = {
      POSITION: g.accessor(mesh.positions, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER, minmax: true }),
      NORMAL: g.accessor(mesh.normals, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
      COLOR_0: g.accessor(mesh.colors, GL.FLOAT, 'VEC3', { target: GL.ARRAY_BUFFER }),
    };
    if (p.kind === 'skin') {
      const ji = jointIndex.get(p.bone);
      const big = bones.length > 255;
      const joints = big ? new Uint16Array(nv * 4) : new Uint8Array(nv * 4);
      const weights = new Float32Array(nv * 4);
      for (let v = 0; v < nv; v++) { joints[v * 4] = ji; weights[v * 4] = 1; }
      attributes.JOINTS_0 = g.accessor(joints, big ? GL.USHORT : GL.UBYTE, 'VEC4', { target: GL.ARRAY_BUFFER });
      attributes.WEIGHTS_0 = g.accessor(weights, GL.FLOAT, 'VEC4', { target: GL.ARRAY_BUFFER });
    }
    const small = nv < 65536;
    const indices = g.accessor(small ? Uint16Array.from(mesh.indices) : mesh.indices, small ? GL.USHORT : GL.UINT, 'SCALAR', { target: GL.ELEMENT_ARRAY_BUFFER });
    const meshIndex = g.add('meshes', { name: p.name ?? `parte${pi}`, primitives: [{ attributes, indices, material }] });
    const node = { name: p.name ?? `parte${pi}`, mesh: meshIndex };
    if (p.kind === 'skin') node.skin = 0;
    J.scenes[0].nodes.push(g.add('nodes', node));
  });

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
