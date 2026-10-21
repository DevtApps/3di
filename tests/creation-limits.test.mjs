import test from 'node:test';
import assert from 'node:assert/strict';
import { runScript } from '../src/interp.js';
import { compileScene } from '../src/compiler.js';
import { partSession } from '../src/export.js';
import { packDataTexture } from '../src/data-texture.js';
import { nativeMesh } from '../src/nativemesh.js';

test('GPU records wrap across rows without losing data', () => {
  const values = Float32Array.from({ length: 20 * 11 * 4 }, (_, i) => i);
  const packed = packDataTexture(values, 11, 16);
  assert.ok(packed.width <= 16 && packed.height <= 16);
  assert.deepEqual(packed.pixels.subarray(0, values.length), values);
  assert.throws(() => packDataTexture(new Float32Array(257 * 4), 11, 16), /capacidade/);
});

test('scene compilation and repeat exceed former item ceilings', () => {
  const run = runScript('show([sphere(0.1).at(i, 0, 0) for i in range(16001)])');
  assert.equal(run.ok, true, run.error?.message);
  assert.ok(compileScene(run.scene).glsl.length);
  const coded = runScript('show([sphere(0.1).round(0.01).at(i, 0, 0) for i in range(2001)])');
  assert.equal(coded.ok, true, coded.error?.message);
  assert.ok(compileScene(coded.scene).glsl.length);
  const repeated = runScript('show(box(0.01).repeat(x=101, z=101, spacing=0.1))');
  assert.equal(repeated.ok, true, repeated.error?.message);
  assert.ok(compileScene(repeated.scene).glsl.length);
});

test('curved export detail grows beyond former 64 segment ceiling', async () => {
  const scene = runScript('show(sphere(1))').scene;
  const coarse = await partSession(scene, 256).build(0);
  const fine = await partSession(scene, 512).build(0);
  assert.ok(fine.triangles > coarse.triangles * 2);
  const box = runScript('show(box(1))').scene;
  assert.ok((await partSession(box, 2049).build(0)).triangles > 0);
  assert.throws(() => nativeMesh(scene.shapes[0], { maxTriangles: 1 }), /orçamento explícito/);
});
