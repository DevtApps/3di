
// d: distância, c: cor, m: (rough, metal, glow), c2: 2ª cor da textura,
// tx: (tipo, tamanho, eixo (3 = triplanar), relevo) da textura, tp: posição no espaço da textura
// fc: facetas (low poly) e verniz: tamanho + 16 * variação de tom em % + 1024 * verniz em décimos
struct M { float d; vec3 c; vec3 m; vec3 c2; vec4 tx; vec3 tp; float fc; };
float hash31(vec3 p) { p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3)); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) {
  vec3 i = floor(x), f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
             mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
  float a = 0.5, s = 0.0;
  for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.02 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
  return s / 0.96875;
}

float patHash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float patG(vec3 p, vec3 bmin, vec3 bc, vec3 hf, int kind, vec2 sz, float gap, int ax, float vary) {
  vec3 q = abs(p - bc) / max(hf, vec3(1e-4));
  int n = q.x > q.y ? (q.x > q.z ? 0 : 2) : (q.y > q.z ? 1 : 2);
  vec3 r = p - bmin;
  int iu, iv;
  if (kind == 1) { iu = ax != n ? ax : (n == 1 ? 0 : 1); iv = 3 - n - iu; }
  else { iv = n == 1 ? 2 : 1; iu = 3 - n - iv; }
  float u = r[iu], v = r[iv];
  float H = sz.y, L = sz.x;
  float row = floor(v / H), fv = v / H - row;
  float shift = kind == 3 ? 0.5 * mod(row, 2.0) : patHash(vec2(row, 7.0));
  float uu = L > 0.0 ? u / L + shift : 0.5;
  float col = L > 0.0 ? floor(uu) : 0.0, fu = L > 0.0 ? uu - col : 0.5;
  float e = min(min(fv, 1.0 - fv) * H, L > 0.0 ? min(fu, 1.0 - fu) * L : 1e3);
  float soft = kind == 3 ? 0.25 * min(L, H) : 0.5 * gap;
  float groove = 1.0 - smoothstep(0.5 * gap, 0.5 * gap + soft, e);
  if (kind == 2) {
    // telhas: cada fileira é mais grossa embaixo (cobre a de baixo) e afina até o topo
    float slope = fv * (1.0 - smoothstep(1.0 - gap / H, 1.0, fv));
    float side = L > 0.0 ? 1.0 - smoothstep(0.5 * gap, gap, min(fu, 1.0 - fu) * L) : 0.0;
    groove = max(slope, side);
  }
  float h = vary * patHash(vec2(col, row) + 0.37);
  return groove + h * (1.0 - groove);
}

mat3 rotEuler(vec3 deg) {
  vec3 r = radians(deg);
  float cx = cos(r.x), sx = sin(r.x), cy = cos(r.y), sy = sin(r.y), cz = cos(r.z), sz = sin(r.z);
  mat3 Rx = mat3(1.0, 0.0, 0.0, 0.0, cx, sx, 0.0, -sx, cx);
  mat3 Ry = mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy);
  mat3 Rz = mat3(cz, sz, 0.0, -sz, cz, 0.0, 0.0, 0.0, 1.0);
  return Rz * Ry * Rx;
}
vec3 axisY(vec3 p, float axis) { return axis < 0.5 ? p.yxz : (axis < 1.5 ? p : p.xzy); }
// Padrões planares (listras, xadrez, tijolos) em coordenadas 2D g: x = fator de mistura (ou
// argamassa), y = variação por tijolo. Servem tanto à projeção normal quanto à triplanar.
vec2 planar(int k, vec2 g, float s) {
  if (k == 4) return vec2(step(0.5, fract(g.y / s)), 0.0);
  if (k == 5) return vec2(mod(floor(g.x / s + 0.5) + floor(g.y / s + 0.5), 2.0), 0.0);
  // tijolos: comprimento s, altura 0.4 s, fiadas desencontradas
  float bh = s * 0.4;
  float row = floor(g.y / bh + 0.02);
  float u = g.x / s + 0.5 * mod(row, 2.0);
  vec2 c = vec2(fract(u) * s, fract(g.y / bh + 0.02) * bh);
  float mortar = min(s, bh) * 0.08;
  return vec2(1.0 - step(mortar, c.x) * step(mortar, c.y), hash31(vec3(floor(u), row, 3.0)));
}
// fator de mistura entre as duas cores (x) e variação por tijolo (y) da textura k no ponto p
vec2 texField(vec3 p, int k, float s, float axis, vec3 n) {
  vec3 q = axisY(p, axis);
  if (k == 1) return vec2(smoothstep(0.3, 0.75, fbm(p / s)), 0.0);
  if (k == 2) {
    // madeira: anéis em volta do eixo, deformados por ruído, mais veios finos
    float r = length(q.xz + (vec2(fbm(q * vec3(1.0, 0.08, 1.0) / s), fbm(q * vec3(1.0, 0.08, 1.0) / s + 7.0)) - 0.5) * s * 3.0) / s;
    float ring = pow(fract(r), 4.0);
    float grain = fbm(q * vec3(25.0, 1.0, 25.0) / s);
    return vec2(clamp(ring * 0.75 + (grain - 0.5) * 0.5 + 0.1, 0.0, 1.0), 0.0);
  }
  if (k == 3) {
    // mármore: veios finos ao longo de uma senoide turbulenta
    float nz = fbm(p / s);
    float v = abs(sin((p.x + p.y * 0.6 + p.z * 0.3) / s * 1.4 + nz * 7.0));
    float vein = 1.0 - smoothstep(0.0, 0.14, v);
    float soft = smoothstep(0.4, 0.9, fbm(p / s * 2.3 + 3.0));
    return vec2(clamp(vein * 0.9 + soft * 0.2, 0.0, 1.0), 0.0);
  }
  if (k == 4 || k == 5 || k == 6) {
    if (axis > 2.5) {
      // triplanar: projeta nos 3 planos e mistura pelo peso da normal (faces x, y e z)
      vec3 w = pow(abs(n), vec3(6.0));
      w /= (w.x + w.y + w.z + 1e-6);
      vec2 f = vec2(0.0);
      if (w.x > 0.02) f += planar(k, p.zy, s) * w.x;
      if (w.y > 0.02) f += planar(k, p.xz, s) * w.y;
      if (w.z > 0.02) f += planar(k, p.xy, s) * w.z;
      return f;
    }
    if (k == 4) return planar(4, vec2(0.0, q.y), s);
    if (k == 5) return vec2(mod(floor(p.x / s + 0.5) + floor(p.y / s + 0.5) + floor(p.z / s + 0.5), 2.0), 0.0);
    return planar(6, vec2(p.x + p.z, p.y), s);
  }
  if (k == 7) return vec2(clamp(q.y / s, 0.0, 1.0), 0.0);           // degradê ao longo do eixo
  if (k == 8) return vec2(fbm(p / s), 0.0);                          // manchas suaves
  if (k == 9) return vec2(fbm(p / s), 0.0);                          // relevo puro (c2 = c1)
  return vec2(0.0);
}
vec3 texColor(vec3 p, vec3 c1, vec3 c2, vec4 tx, vec3 n) {
  int k = int(tx.x + 0.5);
  vec2 f = texField(p, k, tx.y, tx.z, n);
  if (k == 6) {
    vec3 brick = c1 * (0.75 + 0.4 * f.y) * (0.85 + 0.3 * vnoise(p * 40.0 / tx.y));
    return mix(brick, c2, f.x);
  }
  return mix(c1, c2, f.x);
}
// altura da textura (0..1) para o relevo (bump): tijolos e veios ficam rebaixados
float texHeight(vec3 p, vec4 tx, vec3 n) {
  int k = int(tx.x + 0.5);
  if (k == 0 || tx.w <= 0.0 || k == 7) return 0.0;
  vec2 f = texField(p, k, tx.y, tx.z, n);
  if (k == 6) return 1.0 - f.x + 0.12 * f.y;
  if (k == 3) return 1.0 - f.x;
  return f.x;
}
// Relevo em espaço de tela (Mikkelsen): usa as derivadas da altura e da posição, então não
// depende da orientação do sistema de coordenadas da textura.
vec3 bumpNormal(vec3 n, float amp, float dhx, float dhy, vec3 dpx, vec3 dpy, float px) {
  vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
  float det = dot(dpx, r1);
  if (abs(det) < 1e-14 || length(dpx) > 12.0 * px || length(dpy) > 12.0 * px) return n;
  vec3 g = sign(det) * (dhx * r1 + dhy * r2);
  return normalize(abs(det) * n - amp * g);
}
// extrusão de uma distância 2D d2: altura total 2*hh centrada em 0, quinas arredondadas por r
float sdExt(float d2, float hz, float hh, float r) {
  vec2 w = vec2(d2 + r, abs(hz) - (hh - r));
  return min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - r;
}
float sdBox(vec3 p, vec3 b) { vec3 q = abs(p) - b; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0); }
// caixa com arestas chanfradas a 45° (c = largura do chanfro); r arredonda o resultado
float sdCBox(vec3 p, vec3 b, float c) {
  vec3 q = abs(p) - b;
  float d = length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
  float e = max(max(q.x + q.y, q.y + q.z), q.z + q.x) + c;
  return max(d, e * 0.70710678);
}
float sdCyl(vec3 p, float r, float h) { vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h); return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)); }
float sdCone(vec3 p, float h, float r1, float r2) {
  vec2 q = vec2(length(p.xz), p.y);
  vec2 k1 = vec2(r2, h); vec2 k2 = vec2(r2 - r1, 2.0 * h);
  vec2 ca = vec2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
  vec2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
  float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
  return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}
float sdTorus(vec3 p, float R, float r) { vec2 q = vec2(length(p.xz) - R, p.y); return length(q) - r; }
float sdCapsule(vec3 p, float r, float a) { p.y -= clamp(p.y, -a, a); return length(p) - r; }
float sdEllipsoid(vec3 p, vec3 r) { float k0 = length(p / r); float k1 = length(p / (r * r)); return k1 > 0.0 ? k0 * (k0 - 1.0) / k1 : -min(r.x, min(r.y, r.z)); }
float sdPyramid(vec3 p, float h) {
  float m2 = h * h + 0.25;
  p.xz = abs(p.xz); p.xz = (p.z > p.x) ? p.zx : p.xz; p.xz -= 0.5;
  vec3 q = vec3(p.z, h * p.y - 0.5 * p.x, h * p.x + 0.5 * p.y);
  float s = max(-q.x, 0.0);
  float t = clamp((q.y - 0.5 * p.z) / (m2 + 0.25), 0.0, 1.0);
  float a = m2 * (q.x + s) * (q.x + s) + q.y * q.y;
  float b = m2 * (q.x + 0.5 * t) * (q.x + 0.5 * t) + (q.y - m2 * t) * (q.y - m2 * t);
  float d2 = min(q.y, -q.x * m2 - q.y * 0.5) > 0.0 ? 0.0 : min(a, b);
  return sqrt((d2 + q.z * q.z) / m2) * sign(max(q.z, -p.y));
}
float sdTriIso(vec2 p, vec2 q) {
  p.x = abs(p.x);
  vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
  vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
  float s = -sign(q.y);
  vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
  return -sqrt(d.x) * sign(d.y);
}
float sdPrism(vec3 p, float hw, float h, float hd) {
  vec2 w = vec2(sdTriIso(vec2(p.x, h * 0.5 - p.y), vec2(hw, h)), abs(p.z) - hd);
  return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}
// cone arredondado de a (raio r1) até b (raio r2): membros, caudas e orelhas que afinam
float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
  vec3 ba = b - a; float l2 = dot(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1.0 / l2;
  vec3 pa = p - a; float y = dot(pa, ba), z = y - l2;
  vec3 xv = pa * l2 - ba * y; float x2 = dot(xv, xv), y2 = y * y * l2, z2 = z * z * l2;
  float k = sign(rr) * rr * rr * x2;
  if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
  if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
  return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
M mU(M a, M b) { if (a.d < b.d) return a; return b; }
M mUs(M a, M b, float k) {
  float h = clamp(0.5 + 0.5 * (b.d - a.d) / k, 0.0, 1.0);
  M r = b; if (h > 0.5) r = a;
  r.d = mix(b.d, a.d, h) - k * h * (1.0 - h); r.c = mix(b.c, a.c, h); r.m = mix(b.m, a.m, h); r.c2 = mix(b.c2, a.c2, h);
  return r;
}
// Junção entre duas formas (merge): perfil 0 = filete redondo, 1 = chanfro, 2 = sulco (emenda
// afundada ao longo da linha de contato). cm: 0 = cores nítidas (cada forma mantém a sua),
// 1 = cores misturadas no filete. sw > 0 pinta a emenda com sc numa faixa de largura ~r.
M mMerge(M a, M b, float r, int prof, int cm, vec3 sc, float sw) {
  M m = b; if (a.d < b.d) m = a;
  float h = clamp(0.5 + 0.5 * (b.d - a.d) / r, 0.0, 1.0);
  if (prof == 0) m.d = mix(b.d, a.d, h) - r * h * (1.0 - h);
  else if (prof == 1) m.d = min(min(a.d, b.d), (a.d + b.d - r) * 0.70710678);
  else m.d = max(min(a.d, b.d), r * 0.5 - length(vec2(a.d, b.d)));
  if (cm == 1) { m.c = mix(b.c, a.c, h); m.m = mix(b.m, a.m, h); }
  if (sw > 0.0) m.c = mix(m.c, sc, 1.0 - smoothstep(sw * 0.5, sw, length(vec2(a.d, b.d))));
  return m;
}
M mS(M a, M b) { a.d = max(a.d, -b.d); return a; }
M mSs(M a, M b, float k) { a.d = smax(a.d, -b.d, k); return a; }
M mI(M a, M b) { a.d = max(a.d, b.d); return a; }
M mIs(M a, M b, float k) { a.d = smax(a.d, b.d, k); return a; }

uniform highp sampler2D uVis;
bool cullVis(int i) {
  int w = textureSize(uVis, 0).x;
  return texelFetch(uVis, ivec2(i % w, i / w), 0).r > 0.5;
}

uniform highp sampler2D uInst;
uniform highp sampler2D uBvh;
vec4 instFetch(int col, int row) {
  int index = row * 11 + col;
  int width = textureSize(uInst, 0).x;
  return texelFetch(uInst, ivec2(index % width, index / width), 0);
}
vec4 bvhFetch(int col, int row) {
  int index = row * 2 + col;
  int width = textureSize(uBvh, 0).x;
  return texelFetch(uBvh, ivec2(index % width, index / width), 0);
}
float instD(vec3 p, int i) {
  vec4 a = instFetch(0, i);
  vec4 b = instFetch(1, i);
  vec4 r0 = instFetch(2, i);
  vec4 r1 = instFetch(3, i);
  vec4 r2 = instFetch(4, i);
  vec3 q = vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w);
  int t = int(a.x);
  float d;
  if (t == 1) d = sdBox(q, a.yzw) - b.x;
  else if (t == 2) d = length(q) - a.y;
  else if (t == 3) d = sdCyl(q, a.y, a.z) - a.w;
  else if (t == 4) d = sdCone(q, a.y, a.z, a.w);
  else if (t == 5) d = sdTorus(q, a.y, a.z);
  else if (t == 6) d = sdCapsule(q, a.y, a.z);
  else if (t == 7) d = sdEllipsoid(q, a.yzw);
  else if (t == 8) d = sdPyramid((q + vec3(0.0, a.z * 0.5, 0.0)) / a.y, a.z / a.y) * a.y;
  else d = sdPrism(q, a.y, a.z, a.w);
  return d * b.y;
}
float boxDist(vec3 p, int ni) {
  vec3 mn = bvhFetch(0, ni).xyz;
  vec3 mx = bvhFetch(1, ni).xyz;
  return sdBox(p - (mn + mx) * 0.5, (mx - mn) * 0.5);
}
// Percorre a BVH a partir da melhor distância já conhecida; devolve a nova melhor e o índice atingido.
float bvhD(vec3 p, float best, out int hit) {
  hit = -1;
  int stack[40];
  int sp = 0;
  int ni = 0;
  if (boxDist(p, 0) >= best) return best;
  while (true) {
    vec4 a = bvhFetch(0, ni);
    int cnt = int(bvhFetch(1, ni).w);
    if (cnt > 0) {
      int st = int(a.w);
      for (int k = 0; k < cnt; k++) {
        if (!cullVis(21 + st + k)) continue;
        float d = instD(p, st + k);
        if (d < best) { best = d; hit = st + k; }
      }
    } else {
      int l = ni + 1, r = int(a.w);
      float dl = boxDist(p, l), dr = boxDist(p, r);
      int nearN = dl < dr ? l : r, farN = dl < dr ? r : l;
      float dn = min(dl, dr), df = max(dl, dr);
      if (df < best && sp < 40) stack[sp++] = farN;
      if (dn < best) { ni = nearN; continue; }
    }
    // desempilha o próximo nó que ainda pode conter algo mais perto
    bool found = false;
    while (sp > 0) {
      int c = stack[--sp];
      if (boxDist(p, c) < best) { ni = c; found = true; break; }
    }
    if (!found) break;
  }
  return best;
}

M codeM(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    M m1 = M(p.y, vec3(0.158961, 0.274677, 0.068478), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  if (cullVis(0) && sdBox(p - vec3(6.851376, 3.099539, 6.692926), vec3(1.264984, 1.0857, 1.264984)) < u0.d) {
    vec3 q2 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.851376, 3.099539, 6.692926));
    vec3 q3 = q2 / vec3(1.0, 0.82, 1.0);
    M m4 = M(length(q3) - 0.996019, vec3(0.068073, 0.219024, 0.040012), vec3(0.6, 0.0, 0.0), vec3(0.399057, 0.670326, 0.16173), vec4(8.0, 0.896417, 1.0, 0.21), q2, 0.0);
    M m5 = m4; m5.d = m4.d * 0.82;
    M m6 = m5; m6.d = (m5.d + 0.258965 * (fbm(q2 / 0.747014) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m6);
  }
  if (cullVis(1) && sdBox(p - vec3(7.385544, 3.201872, 6.646352), vec3(0.70615, 0.6067, 0.70615)) < u0.d) {
    vec3 q7 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(7.385544, 3.201872, 6.646352));
    vec3 q8 = q7 / vec3(1.0, 0.82, 1.0);
    M m9 = M(length(q8) - 0.5525, vec3(0.016119, 0.162174, 0.009204), vec3(0.6, 0.0, 0.0), vec3(0.283233, 0.648921, 0.114174), vec4(8.0, 0.49725, 1.0, 0.21), q7, 0.0);
    M m10 = m9; m10.d = m9.d * 0.82;
    M m11 = m10; m11.d = (m10.d + 0.14365 * (fbm(q7 / 0.414375) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m11);
  }
  if (cullVis(2) && sdBox(p - vec3(6.46109, 2.828922, 7.748023), vec3(1.41264, 1.212263, 1.41264)) < u0.d) {
    vec3 q12 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.46109, 2.828922, 7.748023));
    vec3 q13 = q12 / vec3(1.0, 0.82, 1.0);
    M m14 = M(length(q13) - 1.113206, vec3(0.035306, 0.28222, 0.011742), vec3(0.6, 0.0, 0.0), vec3(0.163596, 0.415819, 0.033315), vec4(8.0, 1.001886, 1.0, 0.21), q12, 0.0);
    M m15 = m14; m15.d = m14.d * 0.82;
    M m16 = m15; m16.d = (m15.d + 0.289434 * (fbm(q12 / 0.834905) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m16);
  }
  if (cullVis(3) && sdBox(p - vec3(6.842474, 2.74607, 8.135747), vec3(0.70615, 0.6067, 0.70615)) < u0.d) {
    vec3 q17 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.842474, 2.74607, 8.135747));
    vec3 q18 = q17 / vec3(1.0, 0.82, 1.0);
    M m19 = M(length(q18) - 0.5525, vec3(0.035079, 0.099651, 0.028701), vec3(0.6, 0.0, 0.0), vec3(0.209175, 0.614263, 0.031846), vec4(8.0, 0.49725, 1.0, 0.21), q17, 0.0);
    M m20 = m19; m20.d = m19.d * 0.82;
    M m21 = m20; m21.d = (m20.d + 0.14365 * (fbm(q17 / 0.414375) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m21);
  }
  if (cullVis(4) && sdBox(p - vec3(5.168438, 2.691971, 7.633903), vec3(1.107807, 0.950978, 1.107807)) < u0.d) {
    vec3 q22 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(5.168438, 2.691971, 7.633903));
    vec3 q23 = q22 / vec3(1.0, 0.82, 1.0);
    M m24 = M(length(q23) - 0.871276, vec3(0.062439, 0.304367, 0.033205), vec3(0.6, 0.0, 0.0), vec3(0.254061, 0.563192, 0.073193), vec4(8.0, 0.784148, 1.0, 0.21), q22, 0.0);
    M m25 = m24; m25.d = m24.d * 0.82;
    M m26 = m25; m26.d = (m25.d + 0.226532 * (fbm(q22 / 0.653457) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m26);
  }
  if (cullVis(5) && sdBox(p - vec3(4.761286, 2.620709, 8.005567), vec3(0.70615, 0.6067, 0.70615)) < u0.d) {
    vec3 q27 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.761286, 2.620709, 8.005567));
    vec3 q28 = q27 / vec3(1.0, 0.82, 1.0);
    M m29 = M(length(q28) - 0.5525, vec3(0.024388, 0.25051, 0.013494), vec3(0.6, 0.0, 0.0), vec3(0.2684, 0.663117, 0.05289), vec4(8.0, 0.49725, 1.0, 0.21), q27, 0.0);
    M m30 = m29; m30.d = m29.d * 0.82;
    M m31 = m30; m31.d = (m30.d + 0.14365 * (fbm(q27 / 0.414375) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m31);
  }
  if (cullVis(6) && sdBox(p - vec3(4.550769, 2.627074, 6.768979), vec3(1.336952, 1.147387, 1.336952)) < u0.d) {
    vec3 q32 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.550769, 2.627074, 6.768979));
    vec3 q33 = q32 / vec3(1.0, 0.82, 1.0);
    M m34 = M(length(q33) - 1.053136, vec3(0.012547, 0.108136, 0.008973), vec3(0.6, 0.0, 0.0), vec3(0.387653, 0.751754, 0.08226), vec4(8.0, 0.947823, 1.0, 0.21), q32, 0.0);
    M m35 = m34; m35.d = m34.d * 0.82;
    M m36 = m35; m36.d = (m35.d + 0.273815 * (fbm(q32 / 0.789852) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m36);
  }
  if (cullVis(7) && sdBox(p - vec3(3.973995, 2.514782, 6.982405), vec3(0.70615, 0.6067, 0.70615)) < u0.d) {
    vec3 q37 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(3.973995, 2.514782, 6.982405));
    vec3 q38 = q37 / vec3(1.0, 0.82, 1.0);
    M m39 = M(length(q38) - 0.5525, vec3(0.051013, 0.195664, 0.034716), vec3(0.6, 0.0, 0.0), vec3(0.201967, 0.514935, 0.053971), vec4(8.0, 0.49725, 1.0, 0.21), q37, 0.0);
    M m40 = m39; m40.d = m39.d * 0.82;
    M m41 = m40; m41.d = (m40.d + 0.14365 * (fbm(q37 / 0.414375) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m41);
  }
  if (cullVis(8) && sdBox(p - vec3(5.591146, 3.081352, 5.718564), vec3(1.36475, 1.171214, 1.36475)) < u0.d) {
    vec3 q42 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(5.591146, 3.081352, 5.718564));
    vec3 q43 = q42 / vec3(1.0, 0.82, 1.0);
    M m44 = M(length(q43) - 1.075198, vec3(0.056757, 0.183055, 0.045881), vec3(0.6, 0.0, 0.0), vec3(0.322424, 0.70195, 0.055373), vec4(8.0, 0.967678, 1.0, 0.21), q42, 0.0);
    M m45 = m44; m45.d = m44.d * 0.82;
    M m46 = m45; m46.d = (m45.d + 0.279552 * (fbm(q42 / 0.806399) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m46);
  }
  if (cullVis(9) && sdBox(p - vec3(5.564315, 3.176177, 5.138133), vec3(0.70615, 0.6067, 0.70615)) < u0.d) {
    vec3 q47 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(5.564315, 3.176177, 5.138133));
    vec3 q48 = q47 / vec3(1.0, 0.82, 1.0);
    M m49 = M(length(q48) - 0.5525, vec3(0.019477, 0.352862, 0.011696), vec3(0.6, 0.0, 0.0), vec3(0.245734, 0.79967, 0.037159), vec4(8.0, 0.49725, 1.0, 0.21), q47, 0.0);
    M m50 = m49; m50.d = m49.d * 0.82;
    M m51 = m50; m51.d = (m50.d + 0.14365 * (fbm(q47 / 0.414375) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m51);
  }
  if (cullVis(10) && sdBox(p - vec3(6.625785, 2.811233, 6.024032), vec3(1.228783, 1.054671, 1.228783)) < u0.d) {
    vec3 q52 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.625785, 2.811233, 6.024032));
    vec3 q53 = q52 / vec3(1.0, 0.82, 1.0);
    M m54 = M(length(q53) - 0.967288, vec3(0.071279, 0.240813, 0.052531), vec3(0.6, 0.0, 0.0), vec3(0.359542, 0.760514, 0.13923), vec4(8.0, 0.870559, 1.0, 0.21), q52, 0.0);
    M m55 = m54; m55.d = m54.d * 0.82;
    M m56 = m55; m56.d = (m55.d + 0.251495 * (fbm(q52 / 0.725466) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m56);
  }
  if (cullVis(11) && sdBox(p - vec3(6.547646, 2.84908, 5.496778), vec3(0.70615, 0.6067, 0.70615)) < u0.d) {
    vec3 q57 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.547646, 2.84908, 5.496778));
    vec3 q58 = q57 / vec3(1.0, 0.82, 1.0);
    M m59 = M(length(q58) - 0.5525, vec3(0.054333, 0.185966, 0.04482), vec3(0.6, 0.0, 0.0), vec3(0.309018, 0.647987, 0.169422), vec4(8.0, 0.49725, 1.0, 0.21), q57, 0.0);
    M m60 = m59; m60.d = m59.d * 0.82;
    M m61 = m60; m61.d = (m60.d + 0.14365 * (fbm(q57 / 0.414375) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m61);
  }
  if (cullVis(12) && sdBox(p - vec3(5.903779, 2.65565, 6.72917), vec3(1.711, 1.468, 1.711)) < u0.d) {
    vec3 q62 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(5.903779, 2.65565, 6.72917));
    vec3 q63 = q62 / vec3(1.0, 0.82, 1.0);
    M m64 = M(length(q63) - 1.35, vec3(0.107768, 0.357539, 0.059616), vec3(0.6, 0.0, 0.0), vec3(0.182869, 0.359628, 0.078323), vec4(8.0, 1.215, 1.0, 0.21), q62, 0.0);
    M m65 = m64; m65.d = m64.d * 0.82;
    M m66 = m65; m66.d = (m65.d + 0.351 * (fbm(q62 / 1.0125) * 2.0 - 1.0)) * 0.535714;
    u0 = mU(u0, m66);
  }
  if (cullVis(13) && sdBox(p - vec3(6.0, 1.86, 0.0), vec3(1.5694, 1.0894, 1.5694)) < u0.d) {
    vec3 q67 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q68 = q67 - vec3(0.0, 1.86, 0.0);
    M m69 = M(sdCone(q68, 0.9, 1.38, 0.0), vec3(0.035112, 0.128744, 0.060927), vec3(0.6, 0.0, 0.0), vec3(0.052042, 0.203549, 0.077985), vec4(8.0, 0.966, 1.0, 0.21), q67, 0.0);
    M m70 = m69; m70.d = (m69.d + 0.1794 * (fbm(q67 / 0.69) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m70);
  }
  if (cullVis(14) && sdBox(p - vec3(6.0, 2.427857, 0.0), vec3(1.386727, 1.036242, 1.386727)) < u0.d) {
    vec3 q71 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q72 = q71 - vec3(0.0, 2.427857, 0.0);
    M m73 = M(sdCone(q72, 0.867857, 1.218343, 0.0), vec3(0.008776, 0.05611, 0.017941), vec3(0.6, 0.0, 0.0), vec3(0.030021, 0.144543, 0.045912), vec4(8.0, 0.85284, 1.0, 0.21), q71, 0.0);
    M m74 = m73; m74.d = (m73.d + 0.158385 * (fbm(q71 / 0.609171) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m74);
  }
  if (cullVis(15) && sdBox(p - vec3(6.0, 2.995714, 0.0), vec3(1.204055, 0.983083, 1.204055)) < u0.d) {
    vec3 q75 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q76 = q75 - vec3(0.0, 2.995714, 0.0);
    M m77 = M(sdCone(q76, 0.835714, 1.056686, 0.0), vec3(0.01284, 0.220931, 0.038232), vec3(0.6, 0.0, 0.0), vec3(0.034263, 0.264132, 0.062586), vec4(8.0, 0.73968, 1.0, 0.21), q75, 0.0);
    M m78 = m77; m78.d = (m77.d + 0.137369 * (fbm(q75 / 0.528343) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m78);
  }
  if (cullVis(16) && sdBox(p - vec3(6.0, 3.563571, 0.0), vec3(1.021382, 0.929925, 1.021382)) < u0.d) {
    vec3 q79 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q80 = q79 - vec3(0.0, 3.563571, 0.0);
    M m81 = M(sdCone(q80, 0.803571, 0.895029, 0.0), vec3(0.008713, 0.117428, 0.023619), vec3(0.6, 0.0, 0.0), vec3(0.02995, 0.1953, 0.051043), vec4(8.0, 0.62652, 1.0, 0.21), q79, 0.0);
    M m82 = m81; m82.d = (m81.d + 0.116354 * (fbm(q79 / 0.447514) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m82);
  }
  if (cullVis(17) && sdBox(p - vec3(6.0, 4.131429, 0.0), vec3(0.83871, 0.876767, 0.83871)) < u0.d) {
    vec3 q83 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q84 = q83 - vec3(0.0, 4.131429, 0.0);
    M m85 = M(sdCone(q84, 0.771429, 0.733371, 0.0), vec3(0.045865, 0.14202, 0.061939), vec3(0.6, 0.0, 0.0), vec3(0.059174, 0.212939, 0.078626), vec4(8.0, 0.51336, 1.0, 0.21), q83, 0.0);
    M m86 = m85; m86.d = (m85.d + 0.095338 * (fbm(q83 / 0.366686) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m86);
  }
  if (cullVis(18) && sdBox(p - vec3(6.0, 4.699286, 0.0), vec3(0.656037, 0.823609, 0.656037)) < u0.d) {
    vec3 q87 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q88 = q87 - vec3(0.0, 4.699286, 0.0);
    M m89 = M(sdCone(q88, 0.739286, 0.571714, 0.0), vec3(0.023499, 0.160918, 0.050695), vec3(0.6, 0.0, 0.0), vec3(0.043507, 0.225847, 0.071311), vec4(8.0, 0.4002, 1.0, 0.21), q87, 0.0);
    M m90 = m89; m90.d = (m89.d + 0.074323 * (fbm(q87 / 0.285857) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m90);
  }
  if (cullVis(19) && sdBox(p - vec3(6.0, 5.267143, 0.0), vec3(0.473365, 0.77045, 0.473365)) < u0.d) {
    vec3 q91 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q92 = q91 - vec3(0.0, 5.267143, 0.0);
    M m93 = M(sdCone(q92, 0.707143, 0.410057, 0.0), vec3(0.083222, 0.29957, 0.121356), vec3(0.6, 0.0, 0.0), vec3(0.080934, 0.310049, 0.112518), vec4(8.0, 0.28704, 1.0, 0.21), q91, 0.0);
    M m94 = m93; m94.d = (m93.d + 0.053307 * (fbm(q91 / 0.205029) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m94);
  }
  if (cullVis(20) && sdBox(p - vec3(6.0, 5.835, 0.0), vec3(0.290692, 0.717292, 0.290692)) < u0.d) {
    vec3 q95 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.0, 0.0, 0.0));
    vec3 q96 = q95 - vec3(0.0, 5.835, 0.0);
    M m97 = M(sdCone(q96, 0.675, 0.2484, 0.0), vec3(0.081049, 0.307617, 0.131034), vec3(0.6, 0.0, 0.0), vec3(0.079754, 0.314549, 0.117562), vec4(8.0, 0.17388, 1.0, 0.21), q95, 0.0);
    M m98 = m97; m98.d = (m97.d + 0.032292 * (fbm(q95 / 0.1242) * 2.0 - 1.0)) * 0.606061;
    u0 = mU(u0, m98);
  }
  return u0;
}
M mapAll(vec3 p, bool wantMat) {
  M r = codeM(p);
  int hit;
  r.d = bvhD(p, r.d, hit);
  if (hit >= 0 && wantMat) {
    vec4 bb = instFetch(1, hit);
    vec4 c = instFetch(5, hit);
    vec4 e = instFetch(6, hit);
    vec4 c2 = instFetch(7, hit);
    vec4 t0 = instFetch(8, hit), t1 = instFetch(9, hit), t2 = instFetch(10, hit);
    vec3 tp = vec3(dot(t0.xyz, p) + t0.w, dot(t1.xyz, p) + t1.w, dot(t2.xyz, p) + t2.w);
    r = M(r.d, c.rgb, vec3(c.a, e.x, e.y), c2.rgb, vec4(e.z, e.w, c2.a, bb.z), tp, bb.w);
  }
  return r;
}
