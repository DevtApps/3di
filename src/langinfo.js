// Catálogo da linguagem para a IDE (autocomplete, hover, assinaturas) e para o MCP.
// As assinaturas vêm das próprias funções do interpretador, então nunca ficam desatualizadas;
// aqui só ficam as descrições.
import { Interpreter } from './interp.js';
import { Native } from './runtime.js';
import { METHODS, PROPS, COLORS, TEXTURES, SIDES } from './shapes.js';

const DOCS = {
  // primitivas
  box: 'Caixa centrada na origem: largura (x), altura (y), profundidade (z). `round` arredonda as quinas.',
  cube: 'Cubo de lado `size`.',
  sphere: 'Esfera de raio `r`.',
  cylinder: 'Cilindro em pé (eixo y), raio `r` e altura `h`.',
  cone: 'Cone em pé, raio da base `r`, altura `h`; `top > 0` faz um tronco de cone.',
  torus: 'Rosca deitada no plano xz.',
  capsule: 'Cápsula em pé; `h` é a altura total.',
  ellipsoid: 'Elipsoide com raios x, y, z.',
  pyramid: 'Pirâmide de base quadrada `w` e altura `h`.',
  prism: 'Prisma triangular (telhado de duas águas): triângulo de base `w` e altura `h`, estendido `d` em z.',
  plane: 'Chão infinito em y = 0.',
  segment: 'Cápsula ligando os pontos `a` e `b` (membros, canos, galhos).',
  polygon: 'Pilar de base poligonal regular: `sides` lados (3 a 64), circunraio `r`, altura `h`; `round` arredonda as quinas.',
  star: 'Estrela extrudada deitada: `points` pontas em `r`, vales em `inner` (padrão 0.45 r), espessura `h`.',
  wedge: 'Rampa: sobe de -x até +x; profundidade `d` em z.',
  extrude: 'Extruda um polígono qualquer: `points` = [(x, y), ...]. `axis="z"` (perfil de frente, `h` é a profundidade) ou `"y"` (perfil no chão, `h` é a altura); `round` arredonda as quinas.',
  lathe: 'Sólido de revolução em volta de y: `profile` = [(raio, altura), ...] de baixo para cima; `smooth` (1 a 8) suaviza o perfil. Vasos, colunas, taças.',
  hemisphere: 'Meia esfera (cúpula) de raio `r`.',
  tube: 'Cano: cilindro de raio `r` e altura `h`, oco com parede `thickness`.',
  implicit: 'Forma por fórmula: `f(x, y, z)` devolve um campo (negativo dentro, zero na superfície), recortado pela caixa `size`. Use sqrt, sin, abs, min, max, hypot, exp, log, step... e time. `lip` (0 a 1) encurta o passo do raio.',
  sign: 'Sinal de `x`: -1, 0 ou 1 (aceita fórmulas e time).',
  step: '`step(edge, x)`: 0 se x < edge, senão 1 (aceita fórmulas e time).',
  // combinar
  group: 'União de formas (aceita listas). `smooth` funde as formas suavemente.',
  union: 'União de formas (o mesmo que group).',
  subtract: 'Recorta as formas `cutters` de `base`. Faça o recorte atravessar a superfície.',
  intersect: 'Interseção: só o volume comum a todas as formas.',
  // geradores (src/lib)
  grass: 'Gera um canteiro de grama de `width` x `depth` m. `kind` é o tipo (lawn, meadow, tall, dry, tufts, wheat, clover) e `style` o desenho (lowpoly, stylized, realistic): qualquer combinação. `density` (1 normal), `height`, `color`/`tip` (base e ponta), `flowers`, `sway` (graus de balanço animado), `soil` (cor de terra embaixo) e `seed` (reprodutível).',
  plant: 'Gera uma planta pequena. `kind`: flower, daisy, lavender, fern, bush, cactus, mushroom; `style`: lowpoly, stylized, realistic. `height` (m), `color` (destaque: pétalas, chapéu, espigas, folhagem), `density` (1 uma planta; mais = touceira ou mais frondes/hastes) e `seed`.',
  tree: 'Gera uma árvore. `kind`: oak, pine, birch, palm, willow, dead, round, bonsai; `style`: lowpoly, stylized, realistic. `height` (m), `trunk` e `leaves` (cores) e `seed`.',
  person: 'Gera uma pessoa. `style`: lowpoly, stylized, realistic; `build`: slim, average, stocky, child, elder; `hair`: short, long, bald, ponytail, curly, bun; `outfit`: casual, suit, sport, dress, uniform; `pose`: stand, walk, sit (sem cadeira), arms_up. `height` (m; padrão por biotipo), `skin` (cor) e `seed` (pele, cabelo e roupa saem dele).',
  vehicle: 'Gera um veículo andando para +z, rodas no chão. `kind`: car, hatch, suv, pickup, van, bus, truck, tractor, bike, motorbike; `style`: lowpoly, stylized, realistic. `color` (carroceria), `length` (m), `wheels_angle` (graus; use time para as rodas girarem) e `seed`.',
  // cena
  show: 'Mostra as formas na cena. Chame no fim do script; aceita listas.',
  camera: 'Câmera inicial: posição `pos` olhando para `look` (padrão: centro da cena).',
  sun: 'Direção (e cor) da luz do sol.',
  sky: 'Cor do céu.',
  fog: 'Densidade da névoa.',
  // rig e animação
  skeleton: 'Cria um esqueleto. Use `esq.bone(...)` para criar ossos e `forma.bind(osso)` para prender partes.',
  animation: 'Duração e quadros por segundo da animação exportada para glTF. Escolha `duration` para o ciclo fechar.',
  time: 'Tempo em segundos (animação na GPU). Use em at/move, rotate, scale, glow e em rotate/move de ossos.',
  osc: 'Vai de `a` até `b` e volta, suavemente, a cada `period` segundos.',
  // matemática e Python
  print: 'Mostra valores no painel de status.',
  range: 'Sequência de números: range(n), range(a, b), range(a, b, passo).',
  linspace: '`n` números igualmente espaçados de `a` até `b` (inclusive).',
  len: 'Tamanho de uma lista, texto ou dict.',
  lerp: 'Interpolação linear entre `a` e `b` (t de 0 a 1).',
  mix: 'Mistura duas cores (nomes, "#rrggbb" ou tuplas) em sRGB; com números, é como lerp. t de 0 a 1.',
  hsv: 'Cor a partir de matiz (0 a 360), saturação e brilho (0 a 1): hsv(110, 0.7, 0.6) é um verde.',
  vary: 'Cor com variação aleatória (reprodutível com seed): vary("green", hue=15, sat=0.1, val=0.15).',
  clamp: 'Limita `x` ao intervalo [lo, hi].',
  smoothstep: 'Transição suave de 0 a 1 quando `x` vai de e0 a e1.',
  fract: 'Parte fracionária de `x`.',
  seed: 'Fixa a semente dos números aleatórios (cenas reproduzíveis).',
  random: 'Número aleatório entre 0 e 1.',
  uniform: 'Número aleatório entre `a` e `b`.',
  randint: 'Inteiro aleatório entre `a` e `b` (inclusive).',
  choice: 'Elemento aleatório de uma lista.',
  radians: 'Graus para radianos.',
  degrees: 'Radianos para graus.',
  // métodos de forma
  at: 'Desloca a forma (aceita time).',
  move: 'Desloca a forma (o mesmo que at).',
  place: 'Coloca a base (centro de baixo) da forma no ponto.',
  ground: 'Apoia a forma no chão (y = 0) sem mudar x/z.',
  on: 'Apoia em cima do alvo, centrada nele; x/z deslocam a partir do centro do alvo.',
  under: 'Coloca embaixo do alvo.',
  beside: 'Encosta ao lado do alvo (right, left, front, back), com as bases alinhadas.',
  rotate: 'Gira em graus em volta do próprio centro (ou do pivot). Aceita time.',
  scale: 'Escala (número ou (sx, sy, sz)) em volta do centro. Aceita time se for uniforme.',
  mirror: 'Duplica espelhando no plano x = 0 ("xz" gera 4 cópias). Não custa primitivas.',
  repeat: 'Grade de cópias centrada na forma. Não custa primitivas.',
  round: 'Arredonda (e engorda) a forma.',
  shell: 'Deixa a forma oca, com a espessura dada (aparece quando recortada).',
  twist: 'Torce em volta do eixo vertical, de baixo até em cima.',
  taper: 'Afunila: a seção vai de `bottom` (base) até `top` (topo) vezes o tamanho original, ao longo de `axis`.',
  bend: 'Curva a forma: a ponta se inclina `angle` graus para o lado + de `toward` (padrão x), com a base fixa em `pivot`.',
  shear: 'Inclina como um baralho: desloca x e z em metros por metro de altura.',
  polar: 'Repete `count` cópias em volta do eixo y (a forma deve ficar afastada do eixo). Não custa primitivas.',
  elongate: 'Estica a forma sem deformá-la, acrescentando esse comprimento no meio (esfera vira cápsula).',
  displace: 'Deforma a superfície com ruído (rochas, terreno).',
  color: 'Cor: nome ("red", "wood", "vermelho"...), "#rrggbb" ou (r, g, b).',
  material: 'Material: cor, rugosidade (0..1), metal (0..1) e brilho próprio (aceita time).',
  texture: 'Textura procedural: noise, wood, marble, stripes, checker, bricks, gradient (degradê da cor até color2 ao longo do eixo), mottle (manchas suaves) e relief (só relevo). bump=0.3 dá relevo (normal map), triplanar=True projeta nos 3 eixos.',
  name: 'Dá nome à peça (aparece no painel Peças e no MCP).',
  bind: 'Prende a forma (modelada na pose de repouso) a um osso.',
  // propriedades
  top: 'y do topo da caixa envolvente.', bottom: 'y da base.', left: 'x mínimo.', right: 'x máximo.',
  back: 'z mínimo.', front: 'z máximo.', width: 'Largura (x).', height: 'Altura (y).', depth: 'Profundidade (z).',
  size: '(largura, altura, profundidade).', center: 'Centro da caixa envolvente.', x: 'x do centro.', y: 'y do centro.', z: 'z do centro.',
};

const CATEGORY = {
  box: 'primitiva', cube: 'primitiva', sphere: 'primitiva', cylinder: 'primitiva', cone: 'primitiva', torus: 'primitiva',
  capsule: 'primitiva', ellipsoid: 'primitiva', pyramid: 'primitiva', prism: 'primitiva', plane: 'primitiva', segment: 'primitiva',
  group: 'combinar', union: 'combinar', subtract: 'combinar', intersect: 'combinar',
  show: 'cena', camera: 'cena', sun: 'cena', sky: 'cena', fog: 'cena',
  skeleton: 'rig', animation: 'animação', time: 'animação', osc: 'animação',
  polygon: 'primitiva', star: 'primitiva', wedge: 'primitiva', extrude: 'primitiva', lathe: 'primitiva', hemisphere: 'primitiva', tube: 'primitiva', implicit: 'primitiva',
  grass: 'gerador', plant: 'gerador', tree: 'gerador', person: 'gerador', vehicle: 'gerador',
};

const HIDDEN = new Set(['isinstance']);

// membros de ossos e esqueletos (objetos do rig)
const RIG_MEMBERS = {
  skeleton: [
    { name: 'bone', signature: 'bone(name, head, tail=None, parent=None)', doc: 'Cria um osso; `head` é a junta onde ele gira.' },
    { name: 'get', signature: 'get(name)', doc: 'Osso pelo nome.' },
    { name: 'debug', signature: 'debug(color="yellow", r=None)', doc: 'Forma que desenha os ossos (acompanha a pose).' },
    { name: 'bones', signature: 'bones', doc: 'Lista de ossos.', property: true },
  ],
  bone: [
    { name: 'rotate', signature: 'rotate(x=0, y=0, z=0)', doc: 'Soma uma rotação (graus) em volta da cabeça do osso. Aceita time.' },
    { name: 'move', signature: 'move(x=0, y=0, z=0)', doc: 'Soma um deslocamento ao osso. Aceita time.' },
    { name: 'head', signature: 'head', doc: 'Posição da junta.', property: true },
    { name: 'tail', signature: 'tail', doc: 'Ponta do osso.', property: true },
    { name: 'parent', signature: 'parent', doc: 'Osso pai.', property: true },
    { name: 'length', signature: 'length', doc: 'Comprimento do osso.', property: true },
  ],
};

let cache = null;

export function languageCatalog() {
  if (cache) return cache;
  const functions = [];
  const constants = [];
  for (const [name, v] of new Interpreter().globals.vars) {
    if (HIDDEN.has(name)) continue;
    if (v instanceof Native) {
      const category = CATEGORY[name] ?? 'python';
      functions.push({ name, signature: v.signature(), params: v.params.map((p) => p.name), star: v.star, doc: DOCS[name] ?? (category === 'python' ? 'Função do Python.' : ''), category });
    } else {
      constants.push({ name, doc: DOCS[name] ?? (typeof v === 'number' ? `constante ${v.toFixed(5)}` : ''), category: CATEGORY[name] ?? 'python' });
    }
  }
  const methods = Object.entries(METHODS).map(([name, [params]]) => {
    const n = new Native(name, params, () => null);
    return { name, signature: n.signature(), params: n.params.map((p) => p.name), star: n.star, doc: DOCS[name] ?? '' };
  });
  const properties = Object.keys(PROPS).map((name) => ({ name, doc: DOCS[name] ?? '' }));
  cache = {
    keywords: ['def', 'return', 'for', 'in', 'if', 'elif', 'else', 'while', 'and', 'or', 'not', 'True', 'False', 'None', 'pass', 'break', 'continue', 'lambda', 'is'],
    functions,
    constants,
    methods,
    properties,
    rig: RIG_MEMBERS,
    colors: Object.keys(COLORS),
    textures: Object.keys(TEXTURES),
    sides: Object.keys(SIDES),
  };
  return cache;
}

// Texto curto da linguagem para a IA (ferramenta describe_language do MCP).
export function languageSummary() {
  const c = languageCatalog();
  const fn = (cat) => c.functions.filter((f) => f.category === cat).map((f) => `  ${f.signature}  # ${f.doc}`).join('\n');
  return [
    '3DI: subconjunto de Python que descreve cenas 3D. Metros; y para cima; +z é a frente. Formas nascem centradas na origem e são imutáveis (métodos devolvem formas novas). Termine com show(...).',
    `Primitivas:\n${fn('primitiva')}`,
    `Combinar:\n${fn('combinar')}\n  a + b (união), a - b (subtração), a & b (interseção)`,
    `Métodos de forma:\n${c.methods.map((m) => `  .${m.signature}  # ${m.doc}`).join('\n')}`,
    `Propriedades de forma: ${c.properties.map((p) => p.name).join(', ')}`,
    `Geradores (cada um aceita style="lowpoly"|"stylized"|"realistic" e seed=):\n${fn('gerador')}`,
    `Cena:\n${fn('cena')}`,
    `Rig:\n${fn('rig')}\n${c.rig.skeleton.map((m) => `  esq.${m.signature}  # ${m.doc}`).join('\n')}\n${c.rig.bone.map((m) => `  osso.${m.signature}  # ${m.doc}`).join('\n')}`,
    `Animação:\n${fn('animação')}\n  time  # ${DOCS.time}`,
    `Cores: ${c.colors.filter((n) => /^[a-z]+$/.test(n)).join(', ')}, "#rrggbb" ou (r, g, b)`,
    `Texturas: ${['noise', 'wood', 'marble', 'stripes', 'checker', 'bricks', 'gradient', 'mottle', 'relief'].join(', ')} (parâmetros: color2, size, axis, bump, triplanar, range)`,
    `Python: def, for, while, if/elif/else, listas, compreensões, tuplas, dicts, lambda, f-strings, * no desempacotamento. Funções: ${c.functions.filter((f) => f.category === 'python').map((f) => f.name).join(', ')}.`,
    'Dicas: prefira layout semântico (on, beside, place, mirror) a contas de coordenadas; mirror/repeat não custam primitivas; recortes devem atravessar a superfície; dê .name() às peças para conferir medidas.',
  ].join('\n\n');
}
