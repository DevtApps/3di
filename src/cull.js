// Auto cull: quais peças a câmera vê. Uma peça conta como visível se a caixa dela (no mundo) cruza o
// frustum da câmera, ou se a "sombra" da caixa (a caixa arrastada na direção oposta ao sol até o
// chão) cruza: assim uma árvore fora da vista ainda projeta a sombra dela no chão visível.
// A margem cobre a oclusão ambiente e as sombras suaves perto das bordas da imagem.

const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const norm = (a) => { const l = Math.hypot(...a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };

// Planos do frustum (normais para dentro, passando pelo olho), igual à câmera do shader:
// uv = (2·frag − res) / min(res), FOV vertical em graus vale para o lado menor da imagem.
export function frustumPlanes({ eye, target, fov }, aspect) {
  const ww = norm(sub(target, eye));
  let uu = cross(ww, [0, 1, 0]);
  uu = Math.hypot(...uu) < 1e-4 ? [1, 0, 0] : norm(uu);
  const vv = cross(uu, ww);
  const t = Math.tan((fov * Math.PI) / 360);
  const tx = t * (aspect >= 1 ? aspect : 1), ty = t * (aspect >= 1 ? 1 : 1 / aspect);
  const n = (a, b, k) => norm([a[0] * k + b[0], a[1] * k + b[1], a[2] * k + b[2]]);
  const neg = (a) => [-a[0], -a[1], -a[2]];
  return [ww, n(ww, neg(uu), tx), n(ww, uu, tx), n(ww, neg(vv), ty), n(ww, vv, ty)];
}

// caixa [min..max] está fora de algum plano (com margem)?
function outside(planes, eye, mn, mx, margin) {
  for (const pl of planes) {
    // vértice da caixa mais adiante na direção da normal
    const px = pl[0] >= 0 ? mx[0] : mn[0], py = pl[1] >= 0 ? mx[1] : mn[1], pz = pl[2] >= 0 ? mx[2] : mn[2];
    if (pl[0] * (px - eye[0]) + pl[1] * (py - eye[1]) + pl[2] * (pz - eye[2]) < -margin) return true;
  }
  return false;
}

// boxes: Float32Array [minx, miny, minz, maxx, maxy, maxz] × count. Escreve 1/0 em mask e diz se mudou.
export function cullMask(boxes, count, view, aspect, mask) {
  const planes = frustumPlanes(view, aspect);
  const eye = view.eye;
  const dist = Math.hypot(...sub(view.target, eye));
  const margin = Math.max(0.25, dist * 0.04);
  // sombra: direção da luz para o chão; o "chão" é a base mais baixa entre as caixas
  const sun = norm(view.sun ?? [0.6, 1, 0.4]);
  let ground = Infinity;
  for (let i = 0; i < count; i++) ground = Math.min(ground, boxes[i * 6 + 1]);
  const sy = Math.max(sun[1], 0.12);
  let changed = false;
  const mn = [0, 0, 0], mx = [0, 0, 0];
  for (let i = 0; i < count; i++) {
    const o = i * 6;
    for (let k = 0; k < 3; k++) { mn[k] = boxes[o + k]; mx[k] = boxes[o + 3 + k]; }
    let v = !outside(planes, eye, mn, mx, margin);
    if (!v && sun[1] > 0) {
      // arrasta a caixa para longe do sol até o chão
      const len = Math.min((mx[1] - ground) / sy, 200);
      for (let k = 0; k < 3; k++) {
        const d = -sun[k] * len;
        if (d < 0) mn[k] += d; else mx[k] += d;
      }
      v = !outside(planes, eye, mn, mx, margin);
    }
    const m = v ? 1 : 0;
    if (mask[i] !== m) { mask[i] = m; changed = true; }
  }
  return changed;
}
