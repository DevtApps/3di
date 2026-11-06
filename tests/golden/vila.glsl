
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
        if (!cullVis(24 + st + k)) continue;
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

uniform highp sampler2D uCode;
vec4 codeFetch(int col, int row) {
  int index = row * 5 + col;
  int width = textureSize(uCode, 0).x;
  return texelFetch(uCode, ivec2(index % width, index / width), 0);
}
M ci0(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  if (sdBox(p - vec3(0.0, 0.225, 0.0), vec3(4.26, 0.235, 2.31)) < u0.d) {
    vec3 q1 = p - vec3(0.0, 0.225, 0.0);
    M m2 = M(sdBox(q1, vec3(4.25, 0.225, 2.3)), vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m3 = m2; m3.d = (m2.d + 0.02 * patG(p, vec3(-4.25, 0.0, -2.3), vec3(0.0, 0.225, 0.0), vec3(4.25, 0.225, 2.3), 3, vec2(0.5, 0.22), 0.015, 1, 0.4)) * 0.272727;
    u0 = mU(u0, m3);
  }
  if (sdBox(p - vec3(0.0, 1.5, 0.0), vec3(4.18, 1.06, 2.23)) < u0.d) {
    vec3 q4 = p - vec3(0.0, 1.5, 0.0);
    M m5 = M(sdBox(q4, vec3(4.17, 1.05, 2.22)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m6 = m5; m6.d = (m5.d + 0.012 * patG(p, vec3(-4.17, 0.45, -2.22), vec3(0.0, 1.5, 0.0), vec3(4.17, 1.05, 2.22), 1, vec2(1.7, 0.28), 0.008, 1, 0.25)) * 0.25;
    u0 = mU(u0, m6);
  }
  {
    vec3 q7 = p - vec3(-4.15, 1.55, -2.2);
    M m8 = M(sdCyl(q7, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m8);
  }
  {
    vec3 q9 = p - vec3(-4.15, 1.55, 2.2);
    M m10 = M(sdCyl(q9, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m10);
  }
  {
    vec3 q11 = p - vec3(4.15, 1.55, -2.2);
    M m12 = M(sdCyl(q11, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m12);
  }
  {
    vec3 q13 = p - vec3(4.15, 1.55, 2.2);
    M m14 = M(sdCyl(q13, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m14);
  }
  if (sdBox(p - vec3(0.0, 3.771, 0.0), vec3(4.71, 1.231, 2.81)) < u0.d) {
    vec3 q15 = p - vec3(0.0, 3.771, 0.0);
    vec3 q16 = q15 * mat3(0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0);
    M m17 = M(sdPrism(q16, 2.8, 2.442, 4.7), vec3(0.104616, 0.057805, 0.029557), vec3(0.6, 0.0, 0.0), vec3(0.048172, 0.026241, 0.011612), vec4(8.0, 1.5, 1.0, 0.0), p, 0.0);
    M m18 = m17; m18.d = (m17.d + 0.04 * patG(p, vec3(-4.7, 2.55, -2.8), vec3(0.0, 3.771, 0.0), vec3(4.7, 1.221, 2.8), 2, vec2(0.32, 0.22), 0.01, 1, 0.3)) * 0.111111;
    u0 = mU(u0, m18);
  }
  {
    vec3 q19 = p - vec3(0.0, 4.972, 0.0);
    vec3 q20 = q19 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
    M m21 = M(sdCyl(q20, 0.1, 4.8), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m21);
  }
  {
    vec3 q22 = p - vec3(-4.7, 5.287, -0.21);
    vec3 q23 = q22 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, -0.488603, 0.0, 0.488603, 0.872506);
    M m24 = M(sdCapsule(q23, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m24);
  }
  {
    vec3 q25 = p - vec3(-4.7, 5.287, 0.21);
    vec3 q26 = q25 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, 0.488603, 0.0, -0.488603, 0.872506);
    M m27 = M(sdCapsule(q26, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m27);
  }
  {
    vec3 q28 = p - vec3(4.7, 5.287, -0.21);
    vec3 q29 = q28 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, -0.488603, 0.0, 0.488603, 0.872506);
    M m30 = M(sdCapsule(q29, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m30);
  }
  {
    vec3 q31 = p - vec3(4.7, 5.287, 0.21);
    vec3 q32 = q31 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, 0.488603, 0.0, -0.488603, 0.872506);
    M m33 = M(sdCapsule(q32, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m33);
  }
  return u0;
}
M ci1(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    vec3 q1 = p - vec3(0.0, 0.9, 0.0);
    M m2 = M(sdBox(q1, vec3(0.5, 0.9, 0.06)), vec3(0.042311, 0.019382, 0.008023), vec3(0.6, 0.0, 0.0), vec3(0.021156, 0.009691, 0.004012), vec4(2.0, 0.12, 1.0, 0.0), p, 0.0);
    u0 = mU(u0, m2);
  }
  {
    vec3 q3 = p - vec3(0.0, 1.925, 0.0);
    M m4 = M(sdBox(q3, vec3(0.5, 0.125, 0.06)), vec3(0.024158, 0.011612, 0.005182), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m4);
  }
  {
    vec3 q5 = p;
    q5.y = abs(q5.y);
    vec3 q6 = q5 - vec3(0.0, 0.54, 0.07);
    M m7 = M(sdBox(q6, vec3(0.4, 0.03, 0.015)), vec3(0.023153, 0.023153, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m7);
  }
  return u0;
}
M ci2(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  if (sdBox(p - vec3(0.0, 0.225, 0.0), vec3(4.01, 0.235, 2.21)) < u0.d) {
    vec3 q1 = p - vec3(0.0, 0.225, 0.0);
    M m2 = M(sdBox(q1, vec3(4.0, 0.225, 2.2)), vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m3 = m2; m3.d = (m2.d + 0.02 * patG(p, vec3(-4.0, 0.0, -2.2), vec3(0.0, 0.225, 0.0), vec3(4.0, 0.225, 2.2), 3, vec2(0.5, 0.22), 0.015, 1, 0.4)) * 0.272727;
    u0 = mU(u0, m3);
  }
  if (sdBox(p - vec3(0.0, 1.5, 0.0), vec3(3.93, 1.06, 2.13)) < u0.d) {
    vec3 q4 = p - vec3(0.0, 1.5, 0.0);
    M m5 = M(sdBox(q4, vec3(3.92, 1.05, 2.12)), vec3(0.130136, 0.059511, 0.022174), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m6 = m5; m6.d = (m5.d + 0.012 * patG(p, vec3(-3.92, 0.45, -2.12), vec3(0.0, 1.5, 0.0), vec3(3.92, 1.05, 2.12), 1, vec2(1.7, 0.28), 0.008, 1, 0.25)) * 0.25;
    u0 = mU(u0, m6);
  }
  {
    vec3 q7 = p - vec3(-3.9, 1.55, -2.1);
    M m8 = M(sdCyl(q7, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m8);
  }
  {
    vec3 q9 = p - vec3(-3.9, 1.55, 2.1);
    M m10 = M(sdCyl(q9, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m10);
  }
  {
    vec3 q11 = p - vec3(3.9, 1.55, -2.1);
    M m12 = M(sdCyl(q11, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m12);
  }
  {
    vec3 q13 = p - vec3(3.9, 1.55, 2.1);
    M m14 = M(sdCyl(q13, 0.12, 1.1), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m14);
  }
  if (sdBox(p - vec3(0.0, 3.759, 0.0), vec3(4.46, 1.219, 2.71)) < u0.d) {
    vec3 q15 = p - vec3(0.0, 3.759, 0.0);
    vec3 q16 = q15 * mat3(0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0);
    M m17 = M(sdPrism(q16, 2.7, 2.418, 4.45), vec3(0.114435, 0.174647, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.072272, 0.111932, 0.031896), vec4(1.0, 0.6, 1.0, 0.0), p, 0.0);
    M m18 = m17; m18.d = (m17.d + 0.05 * patG(p, vec3(-4.45, 2.55, -2.7), vec3(0.0, 3.759, 0.0), vec3(4.45, 1.209, 2.7), 2, vec2(0.5, 0.3), 0.01, 1, 0.6)) * 0.090909;
    u0 = mU(u0, m18);
  }
  {
    vec3 q19 = p - vec3(0.0, 4.948, 0.0);
    vec3 q20 = q19 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
    M m21 = M(sdCyl(q20, 0.1, 4.55), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m21);
  }
  {
    vec3 q22 = p - vec3(-4.45, 5.263, -0.21);
    vec3 q23 = q22 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, -0.488603, 0.0, 0.488603, 0.872506);
    M m24 = M(sdCapsule(q23, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m24);
  }
  {
    vec3 q25 = p - vec3(-4.45, 5.263, 0.21);
    vec3 q26 = q25 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, 0.488603, 0.0, -0.488603, 0.872506);
    M m27 = M(sdCapsule(q26, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m27);
  }
  {
    vec3 q28 = p - vec3(4.45, 5.263, -0.21);
    vec3 q29 = q28 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, -0.488603, 0.0, 0.488603, 0.872506);
    M m30 = M(sdCapsule(q29, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m30);
  }
  {
    vec3 q31 = p - vec3(4.45, 5.263, 0.21);
    vec3 q32 = q31 * mat3(1.0, 0.0, 0.0, 0.0, 0.872506, 0.488603, 0.0, -0.488603, 0.872506);
    M m33 = M(sdCapsule(q32, 0.05, 0.429796), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m33);
  }
  return u0;
}

M codeM(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    M m1 = M(p.y, vec3(0.025187, 0.061246, 0.084376), vec3(0.12, 0.25, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  if (cullVis(0) && sdBox(p - vec3(0.0, 0.48, -9.0), vec3(0.933959, 0.17, 0.933959)) < u0.d) {
    vec3 q2 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.4, -9.0));
    float sec3 = 0.571199, rr5 = length(q2.xz);
    float an4 = mod(atan(q2.z, q2.x) + 0.5 * sec3, sec3) - 0.5 * sec3;
    vec3 q6 = vec3(rr5 * cos(an4), q2.y, rr5 * sin(an4));
    vec3 q7 = q6 - vec3(0.75, 0.08, 0.0);
    M m8 = M(length(q7) - 0.16, vec3(0.155926, 0.144128, 0.124772), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m8);
  }
  if (cullVis(1) && sdBox(p - vec3(0.0, 0.625, -26.0), vec3(8.01, 0.235, 3.51)) < u0.d) {
    vec3 q9 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.4, -26.0));
    vec3 q10 = q9 - vec3(0.0, 0.225, 0.0);
    M m11 = M(sdBox(q10, vec3(8.0, 0.225, 3.5)), vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m12 = m11; m12.d = (m11.d + 0.02 * patG(q9, vec3(-8.0, 0.0, -3.5), vec3(0.0, 0.225, 0.0), vec3(8.0, 0.225, 3.5), 3, vec2(0.5, 0.22), 0.015, 1, 0.4)) * 0.272727;
    u0 = mU(u0, m12);
  }
  if (cullVis(2) && sdBox(p - vec3(0.0, 2.25, -26.0), vec3(7.93, 1.41, 3.43)) < u0.d) {
    vec3 q13 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.4, -26.0));
    vec3 q14 = q13 - vec3(0.0, 1.85, 0.0);
    M m15 = M(sdBox(q14, vec3(7.92, 1.4, 3.42)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m16 = m15; m16.d = (m15.d + 0.012 * patG(q13, vec3(-7.92, 0.45, -3.42), vec3(0.0, 1.85, 0.0), vec3(7.92, 1.4, 3.42), 1, vec2(1.7, 0.28), 0.008, 1, 0.25)) * 0.25;
    u0 = mU(u0, m16);
  }
  if (cullVis(3) && sdBox(p - vec3(0.0, 5.33, -26.0), vec3(8.46, 1.69, 4.01)) < u0.d) {
    vec3 q17 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.4, -26.0));
    vec3 q18 = q17 - vec3(0.0, 4.93, 0.0);
    vec3 q19 = q18 * mat3(0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0);
    M m20 = M(sdPrism(q19, 4.0, 3.36, 8.45), vec3(0.104616, 0.057805, 0.029557), vec3(0.6, 0.0, 0.0), vec3(0.048172, 0.026241, 0.011612), vec4(8.0, 1.5, 1.0, 0.0), q17, 0.0);
    M m21 = m20; m21.d = (m20.d + 0.04 * patG(q17, vec3(-8.45, 3.25, -4.0), vec3(0.0, 4.93, 0.0), vec3(8.45, 1.68, 4.0), 2, vec2(0.32, 0.22), 0.01, 1, 0.3)) * 0.111111;
    u0 = mU(u0, m21);
  }
  if (cullVis(4) && sdBox(p - vec3(0.0, 1.925, -23.850397), vec3(25.210794, 1.535, 13.360397)) < u0.d) {
    vec3 q22 = p - vec3(0.0, 0.4, -12.0);
    float sec23 = 0.024544, rr25 = length(q22.xz);
    float an24 = mod(atan(q22.z, q22.x) + 0.5 * sec23, sec23) - 0.5 * sec23;
    vec3 q26 = vec3(rr25 * cos(an24), q22.y, rr25 * sin(an24));
    vec3 q27 = q26 - vec3(25.0, 0.0, 0.0);
    M u28 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q29 = q27 - vec3(0.0, 1.3, 0.0);
      M m30 = M(sdCyl(q29, 0.2, 1.3), vec3(0.102242, 0.061246, 0.029557), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u28 = mU(u28, m30);
    }
    {
      vec3 q31 = q27 - vec3(0.0, 2.825, 0.0);
      M m32 = M(sdCone(q31, 0.225, 0.2, 0.0), vec3(0.102242, 0.061246, 0.029557), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u28 = mU(u28, m32);
    }
    vec3 q33 = p - vec3(0.0, 5.0, -28.5);
    M m34 = M(sdBox(q33, vec3(35.0, 5.0, 18.0)), vec3(0.6, 0.6, 0.62), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m35 = mI(u28, m34);
    vec3 q36 = p - vec3(0.0, 3.0, -37.0);
    M m37 = M(sdBox(q36, vec3(2.0, 3.0, 2.0)), vec3(0.6, 0.6, 0.62), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m38 = mS(m35, m37);
    u0 = mU(u0, m38);
  }
  if (cullVis(5)) {
    vec3 q39 = p;
    q39.x = abs(q39.x);
    vec3 q40 = q39 - vec3(2.4, 2.6, -37.0);
    M m41 = M(sdBox(q40, vec3(0.5, 2.2, 0.5)), vec3(0.076185, 0.035601, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.038093, 0.017801, 0.007222), vec4(2.0, 0.06, 1.0, 0.0), q40, 0.0);
    u0 = mU(u0, m41);
  }
  if (cullVis(6) && sdBox(p - vec3(13.014035, 0.55, 11.981709), vec3(2.771015, 1.05, 6.165128)) < u0.d) {
    vec3 q42 = mat3(0.258819, 0.0, -0.965926, 0.0, 1.0, 0.0, 0.965926, 0.0, 0.258819) * (p - vec3(13.014035, 0.55, 11.981709));
    M m43 = M(sdEllipsoid(q42, vec3(6.0, 1.0, 1.2)), vec3(0.068478, 0.03434, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q44 = q42 - vec3(0.0, 1.0, 0.0);
    M m45 = M(sdBox(q44, vec3(6.5, 1.0, 1.7)), vec3(0.068478, 0.03434, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m46 = mS(m43, m45);
    M m47 = m46; m47.d = abs(m46.d) - 0.04;
    M m48 = m47; m48.d = (m47.d + 0.012 * patG(q42, vec3(-6.04, -1.04, -1.24), vec3(0.0, 0.0, 0.0), vec3(6.04, 1.04, 1.24), 1, vec2(0.0, 0.16), 0.008, 0, 0.3)) * 0.25;
    u0 = mU(u0, m48);
  }
  if (cullVis(7) && sdBox(p - vec3(13.014035, 0.57, 11.981709), vec3(2.30707, 0.31, 4.768266)) < u0.d) {
    vec3 q49 = mat3(0.258819, 0.0, -0.965926, 0.0, 1.0, 0.0, 0.965926, 0.0, 0.258819) * (p - vec3(13.014035, 0.55, 11.981709));
    vec3 q50 = q49;
    q50.z = abs(q50.z);
    M u51 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q52 = q50 - vec3(-4.32, 0.02, 0.864);
      vec3 q53 = q52 * mat3(0.998248, 0.0, 0.059167, 0.0, 1.0, 0.0, -0.059167, 0.0, 0.998248);
      vec3 q54 = q53 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m55 = M(sdCyl(q54, 0.3, 0.02), vec3(0.262251, 0.028426, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m55);
    }
    {
      vec3 q56 = q50 - vec3(-3.240538, 0.02, 0.939958);
      vec3 q57 = q56 * mat3(0.996989, 0.0, 0.07754, 0.0, 1.0, 0.0, -0.07754, 0.0, 0.996989);
      vec3 q58 = q57 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m59 = M(sdCyl(q58, 0.3, 0.02), vec3(0.028426, 0.078187, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m59);
    }
    {
      vec3 q60 = q50 - vec3(-2.161652, 0.02, 1.023878);
      vec3 q61 = q60 * mat3(0.997266, 0.0, 0.073894, 0.0, 1.0, 0.0, -0.073894, 0.0, 0.997266);
      vec3 q62 = q61 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m63 = M(sdCyl(q62, 0.3, 0.02), vec3(0.584078, 0.361307, 0.020289), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m63);
    }
    {
      vec3 q64 = q50 - vec3(-1.081677, 0.02, 1.091919);
      vec3 q65 = q64 * mat3(0.99884, 0.0, 0.04815, 0.0, 1.0, 0.0, -0.04815, 0.0, 0.99884);
      vec3 q66 = q65 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m67 = M(sdCyl(q66, 0.3, 0.02), vec3(0.806952, 0.745404, 0.603827), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m67);
    }
    {
      vec3 q68 = q50 - vec3(0.0, 0.02, 1.12);
      vec3 q69 = q68 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
      vec3 q70 = q69 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m71 = M(sdCyl(q70, 0.3, 0.02), vec3(0.046665, 0.111932, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m71);
    }
    {
      vec3 q72 = q50 - vec3(1.081677, 0.02, 1.091919);
      vec3 q73 = q72 * mat3(0.99884, 0.0, -0.04815, 0.0, 1.0, 0.0, 0.04815, 0.0, 0.99884);
      vec3 q74 = q73 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m75 = M(sdCyl(q74, 0.3, 0.02), vec3(0.262251, 0.028426, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m75);
    }
    {
      vec3 q76 = q50 - vec3(2.161652, 0.02, 1.023878);
      vec3 q77 = q76 * mat3(0.997266, 0.0, -0.073894, 0.0, 1.0, 0.0, 0.073894, 0.0, 0.997266);
      vec3 q78 = q77 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m79 = M(sdCyl(q78, 0.3, 0.02), vec3(0.028426, 0.078187, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m79);
    }
    {
      vec3 q80 = q50 - vec3(3.240538, 0.02, 0.939958);
      vec3 q81 = q80 * mat3(0.996989, 0.0, -0.07754, 0.0, 1.0, 0.0, 0.07754, 0.0, 0.996989);
      vec3 q82 = q81 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m83 = M(sdCyl(q82, 0.3, 0.02), vec3(0.584078, 0.361307, 0.020289), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m83);
    }
    {
      vec3 q84 = q50 - vec3(4.32, 0.02, 0.864);
      vec3 q85 = q84 * mat3(0.998248, 0.0, -0.059167, 0.0, 1.0, 0.0, 0.059167, 0.0, 0.998248);
      vec3 q86 = q85 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m87 = M(sdCyl(q86, 0.3, 0.02), vec3(0.806952, 0.745404, 0.603827), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u51 = mU(u51, m87);
    }
    u0 = mU(u0, u51);
  }
  if (cullVis(8) && sdBox(p - vec3(13.014035, 0.17, 11.981709), vec3(3.777668, 0.450588, 5.001325)) < u0.d) {
    vec3 q88 = mat3(0.258819, 0.0, -0.965926, 0.0, 1.0, 0.0, 0.965926, 0.0, 0.258819) * (p - vec3(13.014035, 0.55, 11.981709));
    vec3 q89 = q88;
    q89.z = abs(q89.z);
    M u90 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q91 = q89 - vec3(-4.32, 0.02, 0.914);
      vec3 q92 = q91 * mat3(0.998248, 0.0, 0.059167, 0.0, 1.0, 0.0, -0.059167, 0.0, 0.998248);
      vec3 q93 = q92 - vec3(0.0, -0.4, 0.75);
      vec3 q94 = q93 * mat3(-1.0, 0.0, 0.0, 0.0, -0.470588, 0.882353, 0.0, 0.882353, 0.470588);
      M m95 = M(sdCapsule(q94, 0.03, 0.85), vec3(0.194618, 0.107023, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u90 = mU(u90, m95);
    }
    {
      vec3 q96 = q89 - vec3(-2.880932, 0.02, 1.018223);
      vec3 q97 = q96 * mat3(0.996893, 0.0, 0.078767, 0.0, 1.0, 0.0, -0.078767, 0.0, 0.996893);
      vec3 q98 = q97 - vec3(0.0, -0.4, 0.75);
      vec3 q99 = q98 * mat3(-1.0, 0.0, 0.0, 0.0, -0.470588, 0.882353, 0.0, 0.882353, 0.470588);
      M m100 = M(sdCapsule(q99, 0.03, 0.85), vec3(0.194618, 0.107023, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u90 = mU(u90, m100);
    }
    {
      vec3 q101 = q89 - vec3(-1.441867, 0.02, 1.122482);
      vec3 q102 = q101 * mat3(0.998246, 0.0, 0.059206, 0.0, 1.0, 0.0, -0.059206, 0.0, 0.998246);
      vec3 q103 = q102 - vec3(0.0, -0.4, 0.75);
      vec3 q104 = q103 * mat3(-1.0, 0.0, 0.0, 0.0, -0.470588, 0.882353, 0.0, 0.882353, 0.470588);
      M m105 = M(sdCapsule(q104, 0.03, 0.85), vec3(0.194618, 0.107023, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u90 = mU(u90, m105);
    }
    {
      vec3 q106 = q89 - vec3(0.0, 0.02, 1.17);
      vec3 q107 = q106 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
      vec3 q108 = q107 - vec3(0.0, -0.4, 0.75);
      vec3 q109 = q108 * mat3(-1.0, 0.0, 0.0, 0.0, -0.470588, 0.882353, 0.0, 0.882353, 0.470588);
      M m110 = M(sdCapsule(q109, 0.03, 0.85), vec3(0.194618, 0.107023, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u90 = mU(u90, m110);
    }
    {
      vec3 q111 = q89 - vec3(1.441867, 0.02, 1.122482);
      vec3 q112 = q111 * mat3(0.998246, 0.0, -0.059206, 0.0, 1.0, 0.0, 0.059206, 0.0, 0.998246);
      vec3 q113 = q112 - vec3(0.0, -0.4, 0.75);
      vec3 q114 = q113 * mat3(-1.0, 0.0, 0.0, 0.0, -0.470588, 0.882353, 0.0, 0.882353, 0.470588);
      M m115 = M(sdCapsule(q114, 0.03, 0.85), vec3(0.194618, 0.107023, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u90 = mU(u90, m115);
    }
    {
      vec3 q116 = q89 - vec3(2.880932, 0.02, 1.018223);
      vec3 q117 = q116 * mat3(0.996893, 0.0, -0.078767, 0.0, 1.0, 0.0, 0.078767, 0.0, 0.996893);
      vec3 q118 = q117 - vec3(0.0, -0.4, 0.75);
      vec3 q119 = q118 * mat3(-1.0, 0.0, 0.0, 0.0, -0.470588, 0.882353, 0.0, 0.882353, 0.470588);
      M m120 = M(sdCapsule(q119, 0.03, 0.85), vec3(0.194618, 0.107023, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u90 = mU(u90, m120);
    }
    {
      vec3 q121 = q89 - vec3(4.32, 0.02, 0.914);
      vec3 q122 = q121 * mat3(0.998248, 0.0, -0.059167, 0.0, 1.0, 0.0, 0.059167, 0.0, 0.998248);
      vec3 q123 = q122 - vec3(0.0, -0.4, 0.75);
      vec3 q124 = q123 * mat3(-1.0, 0.0, 0.0, 0.0, -0.470588, 0.882353, 0.0, 0.882353, 0.470588);
      M m125 = M(sdCapsule(q124, 0.03, 0.85), vec3(0.194618, 0.107023, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u90 = mU(u90, m125);
    }
    u0 = mU(u0, u90);
  }
  if (cullVis(9) && sdBox(p - vec3(0.0, 5.5, -32.622511), vec3(45.255022, 5.11, 24.632511)) < u0.d) {
    vec3 q126 = p - vec3(0.0, 0.4, -12.0);
    M u127 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q126 - vec3(0.0, 3.825, 0.0), vec3(31.340895, 3.835, 31.340895)) < u127.d) {
      float sec128 = 0.169816, rr130 = length(q126.xz);
      float an129 = mod(atan(q126.z, q126.x) + 0.5 * sec128, sec128) - 0.5 * sec128;
      vec3 q131 = vec3(rr130 * cos(an129), q126.y, rr130 * sin(an129));
      vec3 q132 = q131 - vec3(29.0, 0.0, 0.0);
      M u133 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q134 = q132 - vec3(0.0, 1.125, 0.0);
        M m135 = M(sdCyl(q134, 0.18, 1.125), vec3(0.068478, 0.03434, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u133 = mU(u133, m135);
      }
      if (sdBox(q132 - vec3(0.0, 4.575, 0.0), vec3(2.26, 3.085, 2.26)) < u133.d) {
        M u136 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q137 = q132 - vec3(0.0, 3.075, 0.0);
          M m138 = M(sdCone(q137, 1.575, 2.25, 0.0), vec3(0.03434, 0.08022, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u136 = mU(u136, m138);
        }
        {
          vec3 q139 = q132 - vec3(0.0, 4.575, 0.0);
          M m140 = M(sdCone(q139, 1.575, 1.725, 0.0), vec3(0.03434, 0.08022, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u136 = mU(u136, m140);
        }
        {
          vec3 q141 = q132 - vec3(0.0, 6.075, 0.0);
          M m142 = M(sdCone(q141, 1.575, 1.2, 0.0), vec3(0.03434, 0.08022, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u136 = mU(u136, m142);
        }
        u133 = mU(u133, u136);
      }
      u127 = mU(u127, u133);
    }
    if (sdBox(q126 - vec3(0.0, 3.06, 0.0), vec3(35.058242, 3.07, 35.058242)) < u127.d) {
      vec3 q143 = q126 - vec3(0.0, 3.06, 0.0);
      vec3 q144 = q143 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
      vec3 q145 = q144 - vec3(0.0, -3.06, 0.0);
      float sec146 = 0.153248, rr148 = length(q145.xz);
      float an147 = mod(atan(q145.z, q145.x) + 0.5 * sec146, sec146) - 0.5 * sec146;
      vec3 q149 = vec3(rr148 * cos(an147), q145.y, rr148 * sin(an147));
      vec3 q150 = q149 - vec3(31.5, 0.0, 0.0);
      M u151 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q152 = q150 - vec3(0.0, 0.9, 0.0);
        M m153 = M(sdCyl(q152, 0.18, 0.9), vec3(0.068478, 0.03434, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u151 = mU(u151, m153);
      }
      if (sdBox(q150 - vec3(0.0, 3.66, 0.0), vec3(1.81, 2.47, 1.81)) < u151.d) {
        M u154 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q155 = q150 - vec3(0.0, 2.46, 0.0);
          M m156 = M(sdCone(q155, 1.26, 1.8, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u154 = mU(u154, m156);
        }
        {
          vec3 q157 = q150 - vec3(0.0, 3.66, 0.0);
          M m158 = M(sdCone(q157, 1.26, 1.38, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u154 = mU(u154, m158);
        }
        {
          vec3 q159 = q150 - vec3(0.0, 4.86, 0.0);
          M m160 = M(sdCone(q159, 1.26, 0.96, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u154 = mU(u154, m160);
        }
        u151 = mU(u151, u154);
      }
      u127 = mU(u127, u151);
    }
    if (sdBox(q126 - vec3(0.0, 4.845, 0.0), vec3(37.924882, 4.855, 37.924882)) < u127.d) {
      vec3 q161 = q126 - vec3(0.0, 4.845, 0.0);
      vec3 q162 = q161 * mat3(0.999657, 0.0, -0.026177, 0.0, 1.0, 0.0, 0.026177, 0.0, 0.999657);
      vec3 q163 = q162 - vec3(0.0, -4.845, 0.0);
      float sec164 = 0.146121, rr166 = length(q163.xz);
      float an165 = mod(atan(q163.z, q163.x) + 0.5 * sec164, sec164) - 0.5 * sec164;
      vec3 q167 = vec3(rr166 * cos(an165), q163.y, rr166 * sin(an165));
      vec3 q168 = q167 - vec3(34.0, 0.0, 0.0);
      M u169 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q170 = q168 - vec3(0.0, 1.425, 0.0);
        M m171 = M(sdCyl(q170, 0.18, 1.425), vec3(0.068478, 0.03434, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u169 = mU(u169, m171);
      }
      if (sdBox(q168 - vec3(0.0, 5.795, 0.0), vec3(2.86, 3.905, 2.86)) < u169.d) {
        M u172 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q173 = q168 - vec3(0.0, 3.895, 0.0);
          M m174 = M(sdCone(q173, 1.995, 2.85, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u172 = mU(u172, m174);
        }
        {
          vec3 q175 = q168 - vec3(0.0, 5.795, 0.0);
          M m176 = M(sdCone(q175, 1.995, 2.185, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u172 = mU(u172, m176);
        }
        {
          vec3 q177 = q168 - vec3(0.0, 7.695, 0.0);
          M m178 = M(sdCone(q177, 1.995, 1.52, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u172 = mU(u172, m178);
        }
        u169 = mU(u169, u172);
      }
      u127 = mU(u127, u169);
    }
    if (sdBox(q126 - vec3(0.0, 4.08, 0.0), vec3(42.140374, 4.09, 42.140374)) < u127.d) {
      vec3 q179 = q126 - vec3(0.0, 4.08, 0.0);
      vec3 q180 = q179 * mat3(0.997564, 0.0, -0.069756, 0.0, 1.0, 0.0, 0.069756, 0.0, 0.997564);
      vec3 q181 = q180 - vec3(0.0, -4.08, 0.0);
      float sec182 = 0.133685, rr184 = length(q181.xz);
      float an183 = mod(atan(q181.z, q181.x) + 0.5 * sec182, sec182) - 0.5 * sec182;
      vec3 q185 = vec3(rr184 * cos(an183), q181.y, rr184 * sin(an183));
      vec3 q186 = q185 - vec3(37.0, 0.0, 0.0);
      M u187 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q188 = q186 - vec3(0.0, 1.2, 0.0);
        M m189 = M(sdCyl(q188, 0.18, 1.2), vec3(0.068478, 0.03434, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m189);
      }
      if (sdBox(q186 - vec3(0.0, 4.88, 0.0), vec3(2.41, 3.29, 2.41)) < u187.d) {
        M u190 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q191 = q186 - vec3(0.0, 3.28, 0.0);
          M m192 = M(sdCone(q191, 1.68, 2.4, 0.0), vec3(0.022174, 0.056128, 0.028426), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u190 = mU(u190, m192);
        }
        {
          vec3 q193 = q186 - vec3(0.0, 4.88, 0.0);
          M m194 = M(sdCone(q193, 1.68, 1.84, 0.0), vec3(0.022174, 0.056128, 0.028426), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u190 = mU(u190, m194);
        }
        {
          vec3 q195 = q186 - vec3(0.0, 6.48, 0.0);
          M m196 = M(sdCone(q195, 1.68, 1.28, 0.0), vec3(0.022174, 0.056128, 0.028426), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u190 = mU(u190, m196);
        }
        u187 = mU(u187, u190);
      }
      u127 = mU(u127, u187);
    }
    if (sdBox(q126 - vec3(0.0, 5.1, 0.0), vec3(45.255022, 5.11, 45.255022)) < u127.d) {
      vec3 q197 = q126 - vec3(0.0, 5.1, 0.0);
      vec3 q198 = q197 * mat3(0.999263, 0.0, -0.038388, 0.0, 1.0, 0.0, 0.038388, 0.0, 0.999263);
      vec3 q199 = q198 - vec3(0.0, -5.1, 0.0);
      float sec200 = 0.118551, rr202 = length(q199.xz);
      float an201 = mod(atan(q199.z, q199.x) + 0.5 * sec200, sec200) - 0.5 * sec200;
      vec3 q203 = vec3(rr202 * cos(an201), q199.y, rr202 * sin(an201));
      vec3 q204 = q203 - vec3(40.5, 0.0, 0.0);
      M u205 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q206 = q204 - vec3(0.0, 1.5, 0.0);
        M m207 = M(sdCyl(q206, 0.18, 1.5), vec3(0.068478, 0.03434, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u205 = mU(u205, m207);
      }
      if (sdBox(q204 - vec3(0.0, 6.1, 0.0), vec3(3.01, 4.11, 3.01)) < u205.d) {
        M u208 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q209 = q204 - vec3(0.0, 4.1, 0.0);
          M m210 = M(sdCone(q209, 2.1, 3.0, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u208 = mU(u208, m210);
        }
        {
          vec3 q211 = q204 - vec3(0.0, 6.1, 0.0);
          M m212 = M(sdCone(q211, 2.1, 2.3, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u208 = mU(u208, m212);
        }
        {
          vec3 q213 = q204 - vec3(0.0, 8.1, 0.0);
          M m214 = M(sdCone(q213, 2.1, 1.6, 0.0), vec3(0.027321, 0.068478, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u208 = mU(u208, m214);
        }
        u205 = mU(u205, u208);
      }
      u127 = mU(u127, u205);
    }
    vec3 q215 = p - vec3(0.0, 15.0, -33.0);
    M m216 = M(sdBox(q215, vec3(50.0, 15.0, 25.0)), vec3(0.6, 0.6, 0.62), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m217 = mI(u127, m216);
    u0 = mU(u0, m217);
  }
  if (cullVis(10) && sdBox(p - vec3(4.5, 0.8, -1.5), vec3(1.08, 0.41, 0.33)) < u0.d) {
    vec3 q218 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.5, 0.8, -1.5));
    vec3 id219 = clamp(round(q218 / vec3(0.75, 1.0, 1.0) + vec3(1.0, 0.0, 0.0)), vec3(0.0), vec3(2.0, 0.0, 0.0));
    vec3 q220 = q218 - vec3(0.75, 1.0, 1.0) * (id219 - vec3(1.0, 0.0, 0.0));
    M m221 = M(sdCyl(q220, 0.28, 0.36) - 0.04, vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.073514, 0.034239, 0.01366), vec4(2.0, 0.1, 1.0, 0.0), q220, 0.0);
    u0 = mU(u0, m221);
  }
  int mk222 = 0;
  if (cullVis(11) && sdBox(p - vec3(14.185913, 3.265028, -3.268519), vec3(4.404226, 2.875028, 5.509381)) < u0.d) mk222 |= 1;
  if (cullVis(12) && sdBox(p - vec3(9.83465, 3.265028, -20.72048), vec3(5.486819, 2.875028, 5.240305)) < u0.d) mk222 |= 2;
  if (cullVis(13) && sdBox(p - vec3(-14.845525, 3.265028, -12.701405), vec3(3.888053, 2.875028, 5.344801)) < u0.d) mk222 |= 4;
  for (int b = uZero, bits = mk222; bits != 0; b++, bits = int(uint(bits) >> 1u)) {
    if ((bits & 1) == 0) continue;
    int i = 0 + b;
    vec4 bc = codeFetch(3, i);
    if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= u0.d) continue;
    vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);
    M ri = ci0(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));
    ri.d *= bc.w;
    u0 = mU(u0, ri);
  }
  int mk223 = 0;
  if (cullVis(14) && sdBox(p - vec3(12.051072, 2.16, -4.131051), vec3(0.264524, 1.32, 0.500751)) < u0.d) mk223 |= 1;
  if (cullVis(15) && sdBox(p - vec3(12.708448, 2.16, -12.168572), vec3(0.201307, 1.32, 0.512687)) < u0.d) mk223 |= 2;
  if (cullVis(16) && sdBox(p - vec3(8.354632, 2.16, -18.956663), vec3(0.439624, 1.32, 0.386932)) < u0.d) mk223 |= 4;
  if (cullVis(17) && sdBox(p - vec3(-8.418911, 2.16, -19.033267), vec3(0.439624, 1.32, 0.386932)) < u0.d) mk223 |= 8;
  if (cullVis(18) && sdBox(p - vec3(-12.611419, 2.16, -12.14438), vec3(0.201307, 1.32, 0.512687)) < u0.d) mk223 |= 16;
  if (cullVis(19) && sdBox(p - vec3(-12.143791, 2.16, -4.09359), vec3(0.264524, 1.32, 0.500751)) < u0.d) mk223 |= 32;
  if (cullVis(20) && sdBox(p - vec3(0.0, 2.16, -22.4975), vec3(0.51, 1.32, 0.0825)) < u0.d) mk223 |= 64;
  for (int b = uZero, bits = mk223; bits != 0; b++, bits = int(uint(bits) >> 1u)) {
    if ((bits & 1) == 0) continue;
    int i = 3 + b;
    vec4 bc = codeFetch(3, i);
    if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= u0.d) continue;
    vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);
    M ri = ci1(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));
    ri.d *= bc.w;
    u0 = mU(u0, ri);
  }
  int mk224 = 0;
  if (cullVis(21) && sdBox(p - vec3(14.845525, 3.253028, -12.701405), vec3(3.730543, 2.863028, 5.078035)) < u0.d) mk224 |= 1;
  if (cullVis(22) && sdBox(p - vec3(-9.83465, 3.253028, -20.72048), vec3(5.231029, 2.863028, 5.003004)) < u0.d) mk224 |= 2;
  if (cullVis(23) && sdBox(p - vec3(-14.185913, 3.253028, -3.268519), vec3(4.217856, 2.863028, 5.240124)) < u0.d) mk224 |= 4;
  for (int b = uZero, bits = mk224; bits != 0; b++, bits = int(uint(bits) >> 1u)) {
    if ((bits & 1) == 0) continue;
    int i = 10 + b;
    vec4 bc = codeFetch(3, i);
    if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= u0.d) continue;
    vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);
    M ri = ci2(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));
    ri.d *= bc.w;
    u0 = mU(u0, ri);
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
