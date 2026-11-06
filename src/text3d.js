// Texto 3D: cada letra vira uma extrusão dos contornos da fonte (com furos), posicionada na linha.
// Letras repetidas compartilham a mesma função de distância no shader. O texto fica no plano x,y,
// virado para +z, com a base da primeira linha em y = 0 (align centraliza em x).
import { ScriptError } from './parser.js';
import { Shape, translate } from './shapes.js';
import sans from './fonts/sans.js';
import serif from './fonts/serif.js';
import mono from './fonts/mono.js';

export const FONTS = { sans, serif, mono };
const parsed = new Map();

// contornos de uma letra em unidades de "em" (1 = altura da fonte), com cache
function glyph(font, id, ch) {
  const key = `${id}:${ch}`;
  if (!parsed.has(key)) {
    const g = font.glyphs[ch] ?? font.glyphs['?'];
    parsed.set(key, g && { adv: g[0] / font.em, contours: g[1].map((s) => {
      const n = s.split(',').map(Number), out = [];
      for (let i = 0; i < n.length; i += 2) {
        const q = [n[i] / font.em, n[i + 1] / font.em], last = out.at(-1);
        // pontos repetidos dariam arestas de comprimento zero (distância NaN)
        if (!last || last[0] !== q[0] || last[1] !== q[1]) out.push(q);
      }
      while (out.length > 1 && out[0][0] === out.at(-1)[0] && out[0][1] === out.at(-1)[1]) out.pop();
      return out;
    }).filter((c) => c.length >= 3) });
  }
  return parsed.get(key);
}

// Mede e monta o texto: devolve [{ ch, x, y }] e o tamanho do bloco (em unidades de em)
export function layoutText(text, { font = 'sans', spacing = 0, line = 1.2, align = 'center' } = {}) {
  const f = FONTS[font];
  if (!f) throw new ScriptError(`text3d(): fonte '${font}' não existe; use ${Object.keys(FONTS).join(', ')}`, null);
  const lines = String(text).split('\n');
  const out = [];
  let width = 0;
  lines.forEach((ln, row) => {
    const items = [];
    let x = 0;
    [...ln].forEach((ch, i) => {
      const g = glyph(f, font, ch);
      if (!g) return;
      if (ch.trim()) items.push({ ch, x, y: -row * line });
      x += g.adv + spacing + (i + 1 < ln.length ? (f.kern[ch + ln[i + 1]] ?? 0) / f.em : 0);
    });
    const w = Math.max(0, x - spacing);
    const shift = align === 'center' ? -w / 2 : align === 'right' ? -w : 0;
    for (const it of items) it.x += shift;
    width = Math.max(width, w);
    out.push(...items);
  });
  return { items: out, width, height: lines.length * line, font: f };
}

export function text3d(a) {
  const text = String(a.text);
  if (!text.trim()) throw new ScriptError('text3d(): texto vazio', null);
  if ([...text].length > 200) throw new ScriptError('text3d(): no máximo 200 letras', null, 'textos longos pesam no shader; divida em vários text3d()');
  const size = a.size, depth = a.depth;
  if (!(size > 0) || !(depth > 0)) throw new ScriptError('text3d(): size e depth devem ser > 0', null);
  if (!['left', 'center', 'right'].includes(a.align)) throw new ScriptError('text3d(): align deve ser "left", "center" ou "right"', null);
  const { items, font } = layoutText(text, { font: a.font, spacing: a.spacing, line: a.line, align: a.align });
  const r = Math.min(Math.max(0, a.round), depth / 2);
  const shapes = items.map(({ ch, x, y }) => {
    const g = glyph(font, a.font, ch);
    const contours = g.contours.map((c) => c.map(([u, v]) => [u * size, v * size]));
    const pts = contours.flat();
    const sh = new Shape('extrude', { pts, contours, h: depth, axis: 'z', r }, []);
    return translate(sh, [x * size, y * size, 0]);
  });
  if (!shapes.length) throw new ScriptError('text3d(): nenhuma letra visível', null);
  return shapes.length === 1 ? shapes[0] : new Shape('union', { k: 0 }, shapes);
}
