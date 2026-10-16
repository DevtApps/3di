// Rig: esqueleto de ossos e partes presas a eles (rígidas, peso 1).
// Cada osso gira em volta da própria cabeça (head) e herda a pose do pai.
// No render, as partes são transformadas e depois combinadas no SDF, então as juntas
// se fundem naturalmente; na exportação glTF viram malhas com skin.
import { ScriptError } from './parser.js';
import { Native, num, numT, vec3, tuple, didYouMean, fmtNum } from './runtime.js';
import { isExpr, sym } from './expr.js';
import { Shape, translate, rotMatrix, aroundPivot, union, segmentShape, parseColor } from './shapes.js';
import { val0 } from './expr.js';

export class Bone {
  constructor(skel, name, head, tail, parent) {
    Object.assign(this, { skel, name, head, tailSpec: tail, parent });
    this.angles = [0, 0, 0];
    this.offset = [0, 0, 0];
    this.children = [];
    this.isBone = true;
    if (parent) parent.children.push(this);
  }

  get tail() {
    if (this.tailSpec) return this.tailSpec;
    if (this.children.length) return this.children[0].head;
    // sem filhos nem tail: continua na direção do pai, com 1/3 do tamanho dele
    if (this.parent) {
      const d = this.head.map((v, i) => v - this.parent.head[i]);
      const len = Math.hypot(...d) || 1;
      return this.head.map((v, i) => v + (d[i] / len) * Math.max(0.05, len / 3));
    }
    return [this.head[0], this.head[1] + 0.1, this.head[2]];
  }

  get animated() { return [...this.angles, ...this.offset].some(isExpr); }

  // ângulos (graus) e deslocamento no instante t
  anglesAt(t) { return this.angles.map((a) => (isExpr(a) ? a.eval(t) : a)); }
  offsetAt(t) { return this.offset.map((a) => (isExpr(a) ? a.eval(t) : a)); }

  describe() { return `<osso ${this.name} em (${this.head.map(fmtNum).join(', ')})>`; }

  attr3di(name) {
    const N = (n, params, fn) => new Native(n, params, fn);
    switch (name) {
      case 'name': return this.name;
      case 'head': return tuple([...this.head]);
      case 'tail': return tuple([...this.tail]);
      case 'parent': return this.parent ?? null;
      case 'length': return Math.hypot(...this.tail.map((v, i) => v - this.head[i]));
      case 'rotate': return N('rotate', ['x=0', 'y=0', 'z=0'], (a) => {
        // soma à rotação atual (graus, aceita time); gira em volta da cabeça do osso
        const v = Array.isArray(a.x) ? vec3(a.x, 'rotate') : [a.x, a.y, a.z];
        v.forEach((x, i) => { this.angles[i] = sym('+', this.angles[i], numT(x, `rotate ${'xyz'[i]}`)); });
        return this;
      });
      case 'move': return N('move', ['x=0', 'y=0', 'z=0'], (a) => {
        const v = Array.isArray(a.x) ? vec3(a.x, 'move') : [a.x, a.y, a.z];
        v.forEach((x, i) => { this.offset[i] = sym('+', this.offset[i], numT(x, `move ${'xyz'[i]}`)); });
        return this;
      });
    }
    throw new ScriptError(`osso não tem o atributo '${name}'`, null,
      didYouMean(name, ['name', 'head', 'tail', 'parent', 'length', 'rotate', 'move']) ?? 'use rotate(x, y, z) ou move(x, y, z)');
  }
}

export class Skeleton {
  constructor(name) {
    this.name = name;
    this.bones = [];
  }

  find(name) { return this.bones.find((b) => b.name === name); }

  describe() { return `<esqueleto ${this.name} com ${this.bones.length} ossos>`; }

  // forma com os ossos desenhados (presos a eles, então acompanham a pose)
  debugShape(color, r) {
    const parts = this.bones.map((b) => {
      const len = Math.hypot(...b.tail.map((v, i) => v - b.head[i]));
      const rr = r ?? Math.max(0.006, len * 0.06);
      const seg = segmentShape(b.head, b.tail, rr);
      const junta = translate(new Shape('sphere', { r: rr * 1.7 }), b.head);
      return new Shape('bound', { bone: b }, [union([seg, junta])]);
    });
    return new Shape('material', { color: parseColor(color), rough: 0.4, metal: null, glow: 0.3, tex: null }, [union(parts)]);
  }

  attr3di(name) {
    const N = (n, params, fn) => new Native(n, params, fn);
    switch (name) {
      case 'name': return this.name;
      case 'bones': return [...this.bones];
      case 'bone': return N('bone', ['name', 'head', 'tail=None', 'parent=None'], (a) => {
        const nm = String(a.name);
        if (this.find(nm)) throw new ScriptError(`já existe um osso '${nm}'`, null);
        let parent = a.parent;
        if (typeof parent === 'string') {
          const p = this.find(parent);
          if (!p) throw new ScriptError(`osso pai '${parent}' não existe`, null, didYouMean(parent, this.bones.map((b) => b.name)));
          parent = p;
        }
        if (parent !== null && !(parent instanceof Bone && parent.skel === this)) {
          throw new ScriptError('parent deve ser um osso deste esqueleto', null);
        }
        const b = new Bone(this, nm, vec3(a.head, 'head'), a.tail === null ? null : vec3(a.tail, 'tail'), parent);
        this.bones.push(b);
        return b;
      });
      case 'get': return N('get', ['name'], (a) => {
        const b = this.find(String(a.name));
        if (!b) throw new ScriptError(`osso '${a.name}' não existe`, null, didYouMean(String(a.name), this.bones.map((x) => x.name)));
        return b;
      });
      case 'debug': return N('debug', ['color="yellow"', 'r=None'], (a) => this.debugShape(a.color, a.r === null ? null : num(a.r, 'r')));
    }
    throw new ScriptError(`esqueleto não tem o atributo '${name}'`, null,
      didYouMean(name, ['name', 'bones', 'bone', 'get', 'debug']) ?? 'use bone(nome, head, parent=...)');
  }
}

export function rigBuiltins(scene) {
  return {
    skeleton: new Native('skeleton', ['name="rig"'], (a) => new Skeleton(String(a.name))),
    animation: new Native('animation', ['duration=4', 'fps=30'], (a) => {
      scene.anim = { duration: num(a.duration, 'duration'), fps: num(a.fps, 'fps') };
      return null;
    }),
  };
}

// gira em volta da cabeça do osso e aplica o deslocamento (valores podem depender de time)
function poseBone(node, b) {
  if (b.angles.some((a) => isExpr(a) || a !== 0)) {
    const m = rotMatrix(...b.angles.map(val0));
    const props = b.angles.some(isExpr) ? { m, angles: [...b.angles] } : { m };
    node = aroundPivot(node, b.head, (q) => new Shape('rotate', props, [q]));
  }
  return translate(node, b.offset);
}

const hasBound = (s) => (s._hasBound ??= s.kind === 'bound' || s.children.some(hasBound));

// Troca cada parte presa (bound) pela parte com a pose da cadeia de ossos aplicada.
export function resolveRig(shapes) {
  const res = (s) => {
    if (!hasBound(s)) return s;
    if (s.kind === 'bound') {
      let node = res(s.children[0]);
      for (let b = s.props.bone; b; b = b.parent) node = poseBone(node, b);
      return node;
    }
    return new Shape(s.kind, s.props, s.children.map(res));
  };
  return shapes.map(res);
}

// ossos usados na cena (com os ancestrais), na ordem: pais antes dos filhos
export function collectBones(shapes) {
  const set = new Set();
  const visit = (s) => {
    if (s.kind === 'bound') for (let b = s.props.bone; b; b = b.parent) set.add(b);
    s.children.forEach(visit);
  };
  shapes.forEach(visit);
  const out = [];
  const add = (b) => { if (out.includes(b)) return; if (b.parent) add(b.parent); out.push(b); };
  set.forEach(add);
  return out;
}
