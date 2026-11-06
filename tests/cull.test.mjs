// Auto cull: o que a câmera vê (e o que faz sombra dentro da vista) continua; o resto é pulado.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cullMask } from '../src/cull.js';
import { executeSceneTask } from '../src/scene-task.js';

const box = (cx, cy, cz, h = 0.5) => [cx - h, cy - h, cz - h, cx + h, cy + h, cz + h];
const run = (boxes, view, aspect = 16 / 9) => {
  const mask = new Uint8Array(boxes.length).fill(1);
  cullMask(Float32Array.from(boxes.flat()), boxes.length, view, aspect, mask);
  return [...mask];
};
// câmera em z = 8 olhando para a origem; sol de cima e um pouco de lado
const cam = { eye: [0, 1, 8], target: [0, 1, 0], fov: 40, sun: [0.6, 1, 0.4] };

test('caixa na frente fica; atrás da câmera e fora dos lados saem', () => {
  const m = run([box(0, 1, 0), box(0, 1, 14), box(40, 1, 0), box(0, 30, 0)], { ...cam, sun: [0, 1, 0] });
  // a 4ª está acima do quadro, mas o sol a pino joga a sombra dela no chão visível: fica
  assert.deepEqual(m, [1, 0, 0, 1]);
});

test('peça fora da vista cuja sombra cai na vista continua (sombra)', () => {
  // sol baixo vindo de +x: a sombra de uma torre à direita, fora do quadro, se estende para -x até a vista
  const torre = [11, 0, -1, 12, 8, 1];
  assert.deepEqual(run([torre], { ...cam, sun: [1, 0.35, 0] }), [1]);
  // com o sol do outro lado, a sombra vai para longe da vista: sai
  assert.deepEqual(run([torre], { ...cam, sun: [-1, 0.35, 0] }), [0]);
});

test('margem nas bordas mantém peças que tocam o quadro', () => {
  // caixa logo além da borda lateral (dentro da margem) continua
  const t = Math.tan((40 * Math.PI) / 360) * (16 / 9) * 8;
  assert.deepEqual(run([box(t + 0.6, 1, 0)], { ...cam, sun: [0, 1, 0] }), [1]);
});

test('o compilador marca as unidades de cull e o GLSL as consulta', () => {
  const code = 'show(plane(), sphere(0.5).displace(0.05).at(3, 0.5, 0), box(1).at(-3, 0.5, 0), sphere(0.3).at(0, keys((0, 0), (1, 1)), 0))';
  const { out } = executeSceneTask({ code });
  // o plano é infinito e fica de fora; a esfera animada entra com a caixa cobrindo o movimento todo
  assert.equal(out.data.cullCount, 3);
  assert.equal(out.data.cull.length, 18);
  for (const i of [0, 1, 2]) assert.match(out.glsl, new RegExp(`cullVis\\(${i}\\)`));
  const [x0, y0, z0, x1, y1, z1] = out.data.cull.slice(12);
  assert.ok(y0 <= -0.3 && y1 >= 1.3, `caixa ${y0}..${y1} cobre y de -0.3 a 1.3`);
  assert.ok(x0 <= -0.3 && x1 >= 0.3 && z0 <= -0.3 && z1 >= 0.3);
  assert.ok(y1 - y0 < 2, 'a folga não incha a caixa');
  assert.match(out.glsl, /uniform highp sampler2D uVis/);
});

test('peça animada sem duração (tempo sem fim) fica de fora do cull', () => {
  const { out } = executeSceneTask({ code: 'show(box(1).at(-3, 0.5, 0), sphere(0.3).at(sin(time) * 2, 0.5, 0))' });
  assert.equal(out.data.cullCount, 1);
});

test('rotação animada: a caixa acompanha a peça girando', () => {
  const code = 'timeline(4)\nshow(box(1).at(0, 5, -20), box(4, 0.2, 0.2).at(2, 0, 0).rotate(y=time * 90))';
  const { out } = executeSceneTask({ code });
  assert.equal(out.data.cullCount, 2);
  const [x0, , z0, x1, , z1] = out.data.cull.slice(6);
  // gira 360° em 4 s em volta do próprio centro (2, 0, 0): as pontas passam a ±2 dele em x e em z
  assert.ok(x0 <= 0 && x1 >= 4 && z0 <= -2 && z1 >= 2, `${x0} ${x1} ${z0} ${z1}`);
});
