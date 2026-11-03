#!/usr/bin/env node
// Golden files para o port em C++ (docs/plano-cpp-sdl3.md, fase 0): para cada examples/*.3di grava
// tests/golden/<nome>.json com AST, árvore de formas, resumo da compilação, dados BVH/código (hash) e
// amostras de sdf(p) na CPU, e tests/golden/<nome>.glsl com o shader.
// Uso: node scripts/golden.mjs            (regrava)
//      node scripts/golden.mjs --check    (falha se algum arquivo mudaria)
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parse } from '../src/parser.js';
import { runScript } from '../src/interp.js';
import { compileScene } from '../src/compiler.js';
import { buildSceneFns } from '../src/sdf.js';
import { union } from '../src/shapes.js';

const root = new URL('..', import.meta.url).pathname;
const exDir = `${root}examples/`, outDir = `${root}tests/golden/`;
const check = process.argv.includes('--check');
const only = process.argv.slice(2).filter((a) => !a.startsWith('--'));

const round = (x) => (Number.isFinite(x) ? Number(x.toPrecision(9)) : String(x));
// serializa sem ciclos nem campos internos (_bb, _leaves, loc…); funções e expressões viram marcadores
function plain(v, seen = new Set()) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return round(v);
  if (typeof v === 'string' || typeof v === 'boolean') return v;
  if (typeof v === 'function') return '<fn>';
  if (ArrayBuffer.isView(v)) return { f32: v.length, sha: sha(v) };
  if (typeof v !== 'object') return String(v);
  if (seen.has(v)) return '<ciclo>';
  seen.add(v);
  let r;
  if (Array.isArray(v)) r = v.map((x) => plain(x, seen));
  else {
    r = {};
    const ctor = v.constructor?.name;
    if (ctor && ctor !== 'Object' && ctor !== 'Shape') r.$ = ctor;
    for (const k of Object.keys(v).sort()) if (!k.startsWith('_')) r[k] = plain(v[k], seen);
  }
  seen.delete(v);
  return r;
}
const sha = (a) => createHash('sha256').update(Buffer.from(a.buffer, a.byteOffset, a.byteLength)).digest('hex').slice(0, 16);

// árvore de formas como tabela de nós (subárvores compartilhadas aparecem uma vez): nodes[i] =
// [kind, props, ids dos filhos]; roots = ids das formas mostradas
function dag(shapes) {
  const ids = new Map(), nodes = [];
  const id = (s) => {
    if (ids.has(s)) return ids.get(s);
    const kids = s.children.map(id);
    ids.set(s, nodes.length);
    // osso: só o nome (o esqueleto inteiro se repetiria em cada parte presa a ele)
    const props = s.props.bone ? { ...s.props, bone: s.props.bone.name ?? '<osso>' } : s.props;
    nodes.push([s.kind, plain(props), kids]);
    return nodes.length - 1;
  };
  return { roots: shapes.map(id), nodes };
}

// pontos determinísticos dentro da caixa da cena (limitada para cenas com plane)
function samples(bb, n = 64) {
  const lo = bb.min.map((v) => Math.max(v, -60)), hi = bb.max.map((v) => Math.min(v, 60));
  let s = 12345;
  const rnd = () => ((s = (s * 1103515245 + 12345) % 2147483648) / 2147483648);
  return Array.from({ length: n }, () => lo.map((v, i) => v - 0.5 + rnd() * (hi[i] - v + 1)));
}

function golden(file) {
  const src = readFileSync(exDir + file, 'utf8');
  const res = runScript(src);
  const g = { file, ast: plain(parse(src)), logs: res.logs };
  if (!res.ok) return [{ ...g, error: res.error.toString() }, ''];
  const shapes = res.scene.shapes;
  g.shapes = dag(shapes);
  const out = compileScene(res.scene);
  g.compile = {
    leaves: out.leaves, codeLeaves: out.codeLeaves, instances: out.instances, codeGroups: out.codeGroups,
    hasPlane: out.hasPlane, animated: out.animated, bbox: plain(out.bbox), glslSha: createHash('sha256').update(out.glsl).digest('hex').slice(0, 16),
    data: plain(out.data ?? null),
  };
  const fns = buildSceneFns(union(shapes));
  g.sdf = samples(out.bbox).map((p) => [...p.map(round), round(fns.dist(...p))]);
  return [g, out.glsl];
}

if (!check) mkdirSync(outDir, { recursive: true });
let bad = 0;
for (const file of readdirSync(exDir).filter((f) => f.endsWith('.3di') && (!only.length || only.some((o) => f.includes(o)))).sort()) {
  const name = file.replace(/\.3di$/, '');
  const [g, glsl] = golden(file);
  const files = [[`${name}.json`, `{\n${Object.entries(g).map(([k, v]) => ` ${JSON.stringify(k)}: ${JSON.stringify(v)}`).join(',\n')}\n}\n`], [`${name}.glsl`, glsl]];
  for (const [f, text] of files) {
    if (check) {
      if (!existsSync(outDir + f) || readFileSync(outDir + f, 'utf8') !== text) { console.error(`difere: tests/golden/${f}`); bad++; }
    } else writeFileSync(outDir + f, text);
  }
  if (!check) console.log(`${name}: ${g.error ? `ERRO ${g.error}` : `${g.compile.leaves} primitivas, glsl ${glsl.length} bytes`}`);
}
// erros de sintaxe: o port precisa dar a mesma mensagem, linha e dica
const BAD = [
  'x = (1, 2', 'def f(:\n    pass', 'if x\n    y = 1', 'a = 1 b = 2', '  x = 1', 'x = "abc', 'f(a=1, 2)',
  'for i in range(3):\nx = 1', 'x = 1\n    y = 2', 'x +', '1 = x', 'a, *b, *c = l', 'x = [1, 2', 'f(x', 'x = 1 if y',
  'x = $', 'def f(x):\n  return x\n x = 1', 'print(f"{x")', 'x.1', 'y = (*a)', 'x = {1: }', 'lambda x x',
];
const errs = BAD.map((src) => { try { parse(src); return { src, ok: true }; } catch (e) { return { src, error: e.toString() }; } });
{
  const text = `${JSON.stringify(errs, null, 1)}\n`, f = '_parse-errors.json';
  if (check) { if (!existsSync(outDir + f) || readFileSync(outDir + f, 'utf8') !== text) { console.error(`difere: tests/golden/${f}`); bad++; } }
  else writeFileSync(outDir + f, text);
}
if (check) console.log(bad ? `${bad} arquivo(s) diferem` : 'golden ok');
process.exit(bad ? 1 : 0);
