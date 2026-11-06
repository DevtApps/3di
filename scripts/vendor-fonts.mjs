// Extrai os contornos das letras (Latin-1) de fontes livres para módulos JS em src/fonts/, usados pelo
// text3d(): cada letra vira polilinhas em unidades da fonte (curvas já achatadas). Assim o texto 3D
// funciona igual no navegador, no worker e no export, sem ler TTF em tempo de execução.
// Fontes: DejaVu (licença Bitstream Vera / domínio público, permite redistribuir; ver src/fonts/LICENSE).
// Os arquivos gerados são versionados: rode de novo só ao trocar as fontes ou o achatamento.
import opentype from 'opentype.js';
import { writeFileSync, copyFileSync } from 'node:fs';

const DIR = '/usr/share/fonts/truetype/dejavu';
const FONTS = { sans: 'DejaVuSans-Bold.ttf', serif: 'DejaVuSerif-Bold.ttf', mono: 'DejaVuSansMono-Bold.ttf' };
const CHARS = [...Array.from({ length: 95 }, (_, i) => String.fromCharCode(32 + i)), ...Array.from({ length: 96 }, (_, i) => String.fromCharCode(160 + i)), '–', '—', '‘', '’', '“', '”', '•', '…', '€'];

// achata uma curva em segmentos conforme o tamanho (em unidades da fonte)
const STEP = 90;
function flatten(cmds) {
  const out = [];
  let cur = null, x = 0, y = 0;
  const push = (px, py) => { cur.push([Math.round(px), Math.round(py)]); x = px; y = py; };
  for (const c of cmds) {
    if (c.type === 'M') { cur = []; out.push(cur); push(c.x, c.y); }
    else if (c.type === 'L') push(c.x, c.y);
    else if (c.type === 'Q') {
      const n = Math.max(1, Math.min(8, Math.ceil(Math.hypot(c.x - x, c.y - y) / STEP)));
      const x0 = x, y0 = y;
      for (let i = 1; i <= n; i++) { const t = i / n, u = 1 - t; push(u * u * x0 + 2 * u * t * c.x1 + t * t * c.x, u * u * y0 + 2 * u * t * c.y1 + t * t * c.y); }
    } else if (c.type === 'C') {
      const n = Math.max(1, Math.min(10, Math.ceil(Math.hypot(c.x - x, c.y - y) / STEP)));
      const x0 = x, y0 = y;
      for (let i = 1; i <= n; i++) {
        const t = i / n, u = 1 - t;
        push(u ** 3 * x0 + 3 * u * u * t * c.x1 + 3 * u * t * t * c.x2 + t ** 3 * c.x, u ** 3 * y0 + 3 * u * u * t * c.y1 + 3 * u * t * t * c.y2 + t ** 3 * c.y);
      }
    }
  }
  // tira o ponto final repetido (contorno fechado)
  return out.map((p) => (p.length > 1 && p[0][0] === p.at(-1)[0] && p[0][1] === p.at(-1)[1] ? p.slice(0, -1) : p)).filter((p) => p.length >= 3);
}

for (const [id, file] of Object.entries(FONTS)) {
  const font = opentype.loadSync(`${DIR}/${file}`);
  const glyphs = {};
  for (const ch of CHARS) {
    const g = font.charToGlyph(ch);
    if (!g || (g.index === 0 && ch !== ' ')) continue;
    // opentype desenha com y para baixo: o caminho em (0, 0) com tamanho = unitsPerEm dá unidades da fonte invertidas
    const cmds = g.getPath(0, 0, font.unitsPerEm).commands.map((c) => ({ ...c, y: -c.y, y1: -c.y1, y2: -c.y2 }));
    glyphs[ch] = [Math.round(g.advanceWidth), flatten(cmds).map((c) => c.flat().join(','))];
  }
  const kern = {};
  for (const a of CHARS) for (const b of CHARS) {
    if (!glyphs[a] || !glyphs[b] || a === ' ' || b === ' ') continue;
    const k = font.getKerningValue(font.charToGlyph(a), font.charToGlyph(b));
    if (k) kern[a + b] = k;
  }
  const data = { name: font.names.fullName.en, em: font.unitsPerEm, ascender: font.ascender, descender: font.descender, glyphs, kern };
  writeFileSync(`src/fonts/${id}.js`, `// ${data.name}: contornos gerados por scripts/vendor-fonts.mjs (não editar à mão)\nexport default ${JSON.stringify(data)};\n`);
  console.log(`src/fonts/${id}.js: ${Object.keys(glyphs).length} letras, ${Object.keys(kern).length} pares de kerning`);
}
copyFileSync('/usr/share/doc/fonts-dejavu-core/copyright', 'src/fonts/LICENSE');
