
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

float sdPoly44(vec2 p) {
  const vec2 v[5] = vec2[5](vec2(0.0, 0.045), vec2(-0.09, 0.045), vec2(-0.12, 0.0), vec2(-0.09, -0.045), vec2(0.0, -0.045));
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = 4; i < 5; j = i, i++) {
    vec2 e = v[j] - v[i];
    vec2 w = p - v[i];
    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(b, b));
    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
    if (all(c) || all(not(c))) s = -s;
  }
  return s * sqrt(d);
}
float sdPoly47(vec2 p) {
  const vec2 v[5] = vec2[5](vec2(0.0, 0.045), vec2(0.09, 0.045), vec2(0.12, 0.0), vec2(0.09, -0.045), vec2(0.0, -0.045));
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = 4; i < 5; j = i, i++) {
    vec2 e = v[j] - v[i];
    vec2 w = p - v[i];
    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(b, b));
    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
    if (all(c) || all(not(c))) s = -s;
  }
  return s * sqrt(d);
}

M mapAll(vec3 p, bool wantMat) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  if (sdBox(p - vec3(0.0, 1.38, 0.0), vec3(0.37, 0.41, 0.32)) < u0.d) {
    vec3 q1 = p - vec3(0.0, 1.38, 0.0);
    M m2 = M(sdBox(q1, vec3(0.1, 0.14, 0.05)) - 0.26, vec3(0.904661, 0.904661, 0.887923), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    if (m2.d < 0.065) {
      vec3 q4 = p;
      q4.x = abs(q4.x);
      vec3 q5 = q4 - vec3(0.12, 1.46, 0.29);
      M m6 = M(sdEllipsoid(q5, vec3(0.045, 0.075, 0.2)), vec3(0.006049, 0.006049, 0.006049), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w3 = 1.0 - smoothstep(-0.005, 0.00501, m6.d);
      m2.c = mix(m2.c, m6.c, w3); m2.m = mix(m2.m, m6.m, w3);
      if (w3 > 0.5) { m2.c2 = m6.c2; m2.tx = m6.tx; m2.tp = m6.tp; m2.fc = m6.fc; }
    }
    if (m2.d < 0.065) {
      vec3 q8 = p - vec3(0.0, 1.32, 0.29);
      vec3 q9 = q8 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m10 = M(sdTorus(q9, 0.12, 0.022), vec3(0.006049, 0.006049, 0.006049), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      vec3 q11 = q8 - vec3(0.0, -0.1, 0.0);
      M m12 = M(sdBox(q11, vec3(0.2, 0.1, 0.2)), vec3(0.006049, 0.006049, 0.006049), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m13 = mI(m10, m12);
      float w7 = 1.0 - smoothstep(-0.005, 0.00501, m13.d);
      m2.c = mix(m2.c, m13.c, w7); m2.m = mix(m2.m, m13.m, w7);
      if (w7 > 0.5) { m2.c2 = m13.c2; m2.tx = m13.tx; m2.tp = m13.tp; m2.fc = m13.fc; }
    }
    u0 = mU(u0, m2);
  }
  if (sdBox(p - vec3(0.0, 0.75596, 0.0), vec3(0.35626, 0.32404, 0.23626)) < u0.d) {
    vec3 q14 = p - vec3(0.0, 0.86, 0.0);
    M m15 = M(sdCBox(q14, vec3(0.28, 0.11, 0.16), 0.03) - 0.04, vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    vec3 q16 = p - vec3(0.0, 0.67, 0.0);
    M m17 = M(sdCBox(q16, vec3(0.22, 0.07, 0.14), 0.02) - 0.03, vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m18 = mMerge(m15, m17, 0.05, 0, 0, vec3(0.0, 0.0, 0.0), 0.0);
    if (m18.d < 0.063) {
      vec3 q20 = p - vec3(2.0, 0.0, 0.0);
      M m21 = M(sdBox(q20, vec3(2.0, 2.0, 2.0)), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w19 = 1.0 - smoothstep(-0.003, 0.00301, m21.d);
      m18.c = mix(m18.c, m21.c, w19); m18.m = mix(m18.m, m21.m, w19);
      if (w19 > 0.5) { m18.c2 = m21.c2; m18.tx = m21.tx; m18.tp = m21.tp; m18.fc = m21.fc; }
    }
    if (m18.d < 0.081) {
      M m23 = M(sdBox(p, vec3(0.006, 1.0, 1.0)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w22 = 1.0 - smoothstep(-0.009, 0.00901, m23.d);
      m18.d -= -0.006 * w22;
      m18.c = mix(m18.c, m23.c, w22); m18.m = mix(m18.m, m23.m, w22);
      if (w22 > 0.5) { m18.c2 = m23.c2; m18.tx = m23.tx; m18.tp = m23.tp; m18.fc = m23.fc; }
    }
    if (m18.d < 0.109) {
      vec3 q25 = p - vec3(0.0, 0.84, 0.0);
      M m26 = M(sdBox(q25, vec3(1.0, 0.055, 1.0)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w24 = 1.0 - smoothstep(-0.021, 0.02101, m26.d);
      m18.d -= 0.014 * w24;
      m18.c = mix(m18.c, m26.c, w24); m18.m = mix(m18.m, m26.m, w24);
      if (w24 > 0.5) { m18.c2 = m26.c2; m18.tx = m26.tx; m18.tp = m26.tp; m18.fc = m26.fc; }
    }
    if (m18.d < 0.102) {
      vec3 q28 = p - vec3(0.0, 0.64, 0.0);
      M m29 = M(sdBox(q28, vec3(1.0, 0.0325, 1.0)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w27 = 1.0 - smoothstep(-0.018, 0.01801, m29.d);
      m18.d -= 0.012 * w27;
      m18.c = mix(m18.c, m29.c, w27); m18.m = mix(m18.m, m29.m, w27);
      if (w27 > 0.5) { m18.c2 = m29.c2; m18.tx = m29.tx; m18.tp = m29.tp; m18.fc = m29.fc; }
    }
    vec3 q30 = p - vec3(0.0, 0.53, 0.0);
    M m31 = M(sdCBox(q30, vec3(0.2, 0.05, 0.13), 0.01) - 0.03, vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    if (m31.d < 0.063) {
      vec3 q33 = p - vec3(2.0, 0.0, 0.0);
      M m34 = M(sdBox(q33, vec3(2.0, 2.0, 2.0)), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w32 = 1.0 - smoothstep(-0.003, 0.00301, m34.d);
      m31.c = mix(m31.c, m34.c, w32); m31.m = mix(m31.m, m34.m, w32);
      if (w32 > 0.5) { m31.c2 = m34.c2; m31.tx = m34.tx; m31.tp = m34.tp; m31.fc = m34.fc; }
    }
    if (m31.d < 0.088) {
      vec3 q36 = p - vec3(0.0, 0.53, 0.0);
      M m37 = M(sdBox(q36, vec3(0.03, 0.2, 0.35)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w35 = 1.0 - smoothstep(-0.012, 0.01201, m37.d);
      m31.d -= 0.008 * w35;
      m31.c = mix(m31.c, m37.c, w35); m31.m = mix(m31.m, m37.m, w35);
      if (w35 > 0.5) { m31.c2 = m37.c2; m31.tx = m37.tx; m31.tp = m37.tp; m31.fc = m37.fc; }
    }
    M m38 = mMerge(m18, m31, 0.03, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
    vec3 q39 = p - vec3(0.0, 1.0, 0.0);
    M m40 = M(sdCyl(q39, 0.1, 0.07), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m41 = mMerge(m38, m40, 0.03, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
    u0 = mU(u0, m41);
  }
  if (sdBox(p - vec3(0.0, 0.84, 0.215), vec3(0.13, 0.055, 0.025)) < u0.d) {
    M u42 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(p - vec3(-0.06, 0.84, 0.215), vec3(0.07, 0.055, 0.025)) < u42.d) {
      vec3 q43 = p - vec3(0.0, 0.84, 0.215);
      M m45 = M(sdExt(sdPoly44(q43.xy), q43.z, 0.015, 0.0), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      u42 = mU(u42, m45);
    }
    if (sdBox(p - vec3(0.06, 0.84, 0.215), vec3(0.07, 0.055, 0.025)) < u42.d) {
      vec3 q46 = p - vec3(0.0, 0.84, 0.215);
      M m48 = M(sdExt(sdPoly47(q46.xy), q46.z, 0.015, 0.0), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      u42 = mU(u42, m48);
    }
    u0 = mU(u0, u42);
  }
  {
    vec3 q49 = p - vec3(-0.17, 0.95, 0.2);
    M m50 = M(sdBox(q49, vec3(0.032, 0.012, 0.002)) - 0.008, vec3(0.904661, 0.904661, 0.887923), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    u0 = mU(u0, m50);
  }
  if (sdBox(p - vec3(-0.385716, 0.732342, 0.02044), vec3(0.169016, 0.350958, 0.16756)) < u0.d) {
    vec3 q51 = p - vec3(-0.38, 0.92, 0.0);
    vec3 q52 = q51 * mat3(0.990268, 0.139173, 0.0, -0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
    M u53 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q52 - vec3(-0.0185, -0.1285, 0.0035), vec3(0.16562, 0.27562, 0.15062)) < u53.d) {
      M m54 = M(length(q52) - 0.125, vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m55 = M(sdRoundCone(q52, vec3(0.0, -0.02, 0.0), vec3(-0.023125, -0.086875, 0.008125), 0.1, 0.0955), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m56 = M(sdRoundCone(q52, vec3(-0.023125, -0.086875, 0.008125), vec3(-0.05, -0.17, 0.02), 0.0955, 0.091), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m57 = mUs(m55, m56, 0.02);
      M m58 = M(sdRoundCone(q52, vec3(-0.05, -0.17, 0.02), vec3(-0.068125, -0.244375, 0.03625), 0.091, 0.0865), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m59 = mUs(m57, m58, 0.02);
      M m60 = M(sdRoundCone(q52, vec3(-0.068125, -0.244375, 0.03625), vec3(-0.08, -0.3, 0.05), 0.0865, 0.082), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m61 = mUs(m59, m60, 0.02);
      M m62 = mMerge(m54, m61, 0.02, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
      if (m62.d < 0.102) {
        vec3 q64 = q52 - vec3(-0.08, -0.28, 0.05);
        M m65 = M(sdBox(q64, vec3(0.15, 0.025, 0.15)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
        float w63 = 1.0 - smoothstep(-0.018, 0.01801, m65.d);
        m62.d -= 0.012 * w63;
        m62.c = mix(m62.c, m65.c, w63); m62.m = mix(m62.m, m65.m, w63);
        if (w63 > 0.5) { m62.c2 = m65.c2; m62.tx = m65.tx; m62.tp = m65.tp; m62.fc = m65.fc; }
      }
      u53 = mU(u53, m62);
    }
    {
      vec3 q66 = q52 - vec3(-0.09, -0.39, 0.06);
      M m67 = M(length(q66) - 0.115, vec3(0.904661, 0.904661, 0.887923), vec3(0.45, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      vec3 q68 = q52 - vec3(-0.03, -0.36, 0.14);
      M m69 = M(sdEllipsoid(q68, vec3(0.038, 0.056, 0.038)), vec3(0.904661, 0.904661, 0.887923), vec3(0.45, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m70 = mMerge(m67, m69, 0.02, 0, 0, vec3(0.0, 0.0, 0.0), 0.0);
      u53 = mU(u53, m70);
    }
    u0 = mU(u0, u53);
  }
  if (sdBox(p - vec3(0.385716, 0.732342, 0.02044), vec3(0.169016, 0.350958, 0.16756)) < u0.d) {
    vec3 q71 = p - vec3(0.38, 0.92, 0.0);
    vec3 q72 = q71 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
    M u73 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q72 - vec3(0.0185, -0.1285, 0.0035), vec3(0.16562, 0.27562, 0.15062)) < u73.d) {
      M m74 = M(length(q72) - 0.125, vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m75 = M(sdRoundCone(q72, vec3(0.0, -0.02, 0.0), vec3(0.023125, -0.086875, 0.008125), 0.1, 0.0955), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m76 = M(sdRoundCone(q72, vec3(0.023125, -0.086875, 0.008125), vec3(0.05, -0.17, 0.02), 0.0955, 0.091), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m77 = mUs(m75, m76, 0.02);
      M m78 = M(sdRoundCone(q72, vec3(0.05, -0.17, 0.02), vec3(0.068125, -0.244375, 0.03625), 0.091, 0.0865), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m79 = mUs(m77, m78, 0.02);
      M m80 = M(sdRoundCone(q72, vec3(0.068125, -0.244375, 0.03625), vec3(0.08, -0.3, 0.05), 0.0865, 0.082), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m81 = mUs(m79, m80, 0.02);
      M m82 = mMerge(m74, m81, 0.02, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
      if (m82.d < 0.102) {
        vec3 q84 = q72 - vec3(0.08, -0.28, 0.05);
        M m85 = M(sdBox(q84, vec3(0.15, 0.025, 0.15)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
        float w83 = 1.0 - smoothstep(-0.018, 0.01801, m85.d);
        m82.d -= 0.012 * w83;
        m82.c = mix(m82.c, m85.c, w83); m82.m = mix(m82.m, m85.m, w83);
        if (w83 > 0.5) { m82.c2 = m85.c2; m82.tx = m85.tx; m82.tp = m85.tp; m82.fc = m85.fc; }
      }
      u73 = mU(u73, m82);
    }
    {
      vec3 q86 = q72 - vec3(0.09, -0.39, 0.06);
      M m87 = M(length(q86) - 0.115, vec3(0.904661, 0.904661, 0.887923), vec3(0.45, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      vec3 q88 = q72 - vec3(0.03, -0.36, 0.14);
      M m89 = M(sdEllipsoid(q88, vec3(0.038, 0.056, 0.038)), vec3(0.904661, 0.904661, 0.887923), vec3(0.45, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      M m90 = mMerge(m87, m89, 0.02, 0, 0, vec3(0.0, 0.0, 0.0), 0.0);
      u73 = mU(u73, m90);
    }
    u0 = mU(u0, u73);
  }
  if (sdBox(p - vec3(-0.13197, 0.29553, 0.04), vec3(0.14313, 0.31563, 0.1801)) < u0.d) {
    vec3 q91 = p - vec3(-0.12, 0.48, 0.0);
    M m92 = M(sdRoundCone(q91, vec3(0.0, 0.0, 0.0), vec3(-0.004375, -0.075, 0.005625), 0.105, 0.10125), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m93 = M(sdRoundCone(q91, vec3(-0.004375, -0.075, 0.005625), vec3(-0.01, -0.17, 0.01), 0.10125, 0.0975), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m94 = mUs(m92, m93, 0.02);
    M m95 = M(sdRoundCone(q91, vec3(-0.01, -0.17, 0.01), vec3(-0.015625, -0.260625, 0.005625), 0.0975, 0.09375), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m96 = mUs(m94, m95, 0.02);
    M m97 = M(sdRoundCone(q91, vec3(-0.015625, -0.260625, 0.005625), vec3(-0.02, -0.33, 0.0), 0.09375, 0.09), vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m98 = mUs(m96, m97, 0.02);
    if (m98.d < 0.116) {
      vec3 q100 = q91 - vec3(-0.01, -0.17, 0.095);
      M m101 = M(sdEllipsoid(q100, vec3(0.065, 0.055, 0.06)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w99 = 1.0 - smoothstep(-0.024, 0.02401, m101.d);
      m98.d -= 0.016 * w99;
      m98.c = mix(m98.c, m101.c, w99); m98.m = mix(m98.m, m101.m, w99);
      if (w99 > 0.5) { m98.c2 = m101.c2; m98.tx = m101.tx; m98.tp = m101.tp; m98.fc = m101.fc; }
    }
    vec3 q102 = q91 - vec3(-0.02, -0.4, 0.04);
    M m103 = M(sdCBox(q102, vec3(0.075, 0.04, 0.12), 0.005) - 0.04, vec3(0.028426, 0.212231, 0.672443), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    if (m103.d < 0.095) {
      vec3 q105 = q91 - vec3(-0.02, -0.465, 0.04);
      M m106 = M(sdBox(q105, vec3(0.2, 0.025, 0.25)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w104 = 1.0 - smoothstep(-0.015, 0.01501, m106.d);
      m103.d -= 0.01 * w104;
      m103.c = mix(m103.c, m106.c, w104); m103.m = mix(m103.m, m106.m, w104);
      if (w104 > 0.5) { m103.c2 = m106.c2; m103.tx = m106.tx; m103.tp = m106.tp; m103.fc = m106.fc; }
    }
    M m107 = mMerge(m98, m103, 0.02, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
    u0 = mU(u0, m107);
  }
  if (sdBox(p - vec3(0.13197, 0.29553, 0.04), vec3(0.14313, 0.31563, 0.1801)) < u0.d) {
    vec3 q108 = p - vec3(0.12, 0.48, 0.0);
    M m109 = M(sdRoundCone(q108, vec3(0.0, 0.0, 0.0), vec3(0.004375, -0.075, 0.005625), 0.105, 0.10125), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m110 = M(sdRoundCone(q108, vec3(0.004375, -0.075, 0.005625), vec3(0.01, -0.17, 0.01), 0.10125, 0.0975), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m111 = mUs(m109, m110, 0.02);
    M m112 = M(sdRoundCone(q108, vec3(0.01, -0.17, 0.01), vec3(0.015625, -0.260625, 0.005625), 0.0975, 0.09375), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m113 = mUs(m111, m112, 0.02);
    M m114 = M(sdRoundCone(q108, vec3(0.015625, -0.260625, 0.005625), vec3(0.02, -0.33, 0.0), 0.09375, 0.09), vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    M m115 = mUs(m113, m114, 0.02);
    if (m115.d < 0.116) {
      vec3 q117 = q108 - vec3(0.01, -0.17, 0.095);
      M m118 = M(sdEllipsoid(q117, vec3(0.065, 0.055, 0.06)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w116 = 1.0 - smoothstep(-0.024, 0.02401, m118.d);
      m115.d -= 0.016 * w116;
      m115.c = mix(m115.c, m118.c, w116); m115.m = mix(m115.m, m118.m, w116);
      if (w116 > 0.5) { m115.c2 = m118.c2; m115.tx = m118.tx; m115.tp = m118.tp; m115.fc = m118.fc; }
    }
    vec3 q119 = q108 - vec3(0.02, -0.4, 0.04);
    M m120 = M(sdCBox(q119, vec3(0.075, 0.04, 0.12), 0.005) - 0.04, vec3(0.806952, 0.066626, 0.028426), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
    if (m120.d < 0.095) {
      vec3 q122 = q108 - vec3(0.02, -0.465, 0.04);
      M m123 = M(sdBox(q122, vec3(0.2, 0.025, 0.25)), vec3(0.025187, 0.030713, 0.043735), vec3(0.42, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 6144.0);
      float w121 = 1.0 - smoothstep(-0.015, 0.01501, m123.d);
      m120.d -= 0.01 * w121;
      m120.c = mix(m120.c, m123.c, w121); m120.m = mix(m120.m, m123.m, w121);
      if (w121 > 0.5) { m120.c2 = m123.c2; m120.tx = m123.tx; m120.tp = m123.tp; m120.fc = m123.fc; }
    }
    M m124 = mMerge(m115, m120, 0.02, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
    u0 = mU(u0, m124);
  }
  return u0;
}
