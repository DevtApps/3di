
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

M mapAll(vec3 p, bool wantMat) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  if (sdBox(p - vec3(-0.108891, 0.691775, -0.01), vec3(0.408891, 0.704775, 0.36)) < u0.d) {
    vec3 q1 = p - vec3(0.0, 0.27, -0.06);
    M m2 = M(sdEllipsoid(q1, vec3(0.27, 0.25, 0.3)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    vec3 q3 = p - vec3(0.0, 0.52, 0.07);
    vec3 q4 = q3 * mat3(1.0, 0.0, 0.0, 0.0, 0.978148, -0.207912, 0.0, 0.207912, 0.978148);
    M m5 = M(sdEllipsoid(q4, vec3(0.19, 0.3, 0.19)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m6 = mUs(m2, m5, 0.035);
    vec3 q7 = p - vec3(0.0, 0.78, 0.1);
    M m8 = M(sdEllipsoid(q7, vec3(0.15, 0.16, 0.14)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m9 = mUs(m6, m8, 0.035);
    vec3 q10 = p - vec3(0.0, 0.99, 0.11);
    M m11 = M(sdEllipsoid(q10, vec3(0.27, 0.23, 0.22)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m12 = mUs(m9, m11, 0.035);
    vec3 q13 = p;
    q13.x = abs(q13.x);
    vec3 q14 = q13 - vec3(0.13, 0.9, 0.17);
    M m15 = M(sdEllipsoid(q14, vec3(0.1, 0.08, 0.09)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m16 = mUs(m12, m15, 0.035);
    vec3 q17 = p;
    q17.x = abs(q17.x);
    vec3 q18 = q17 - vec3(0.04, 0.885, 0.29);
    M m19 = M(sdEllipsoid(q18, vec3(0.055, 0.045, 0.05)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m20 = mUs(m16, m19, 0.035);
    vec3 q21 = p - vec3(0.0, 0.845, 0.26);
    M m22 = M(sdEllipsoid(q21, vec3(0.06, 0.035, 0.05)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m23 = mUs(m20, m22, 0.035);
    vec3 q24 = p - vec3(0.13, 1.171, 0.08);
    vec3 q25 = q24 * mat3(0.951057, -0.309017, 0.0, 0.30601, 0.941801, -0.139173, 0.043007, 0.132361, 0.990268);
    vec3 q26 = q25 / vec3(1.0, 1.0, 0.36);
    vec3 q27 = q26 - vec3(0.0, -0.091, 0.0);
    M m28 = M(sdRoundCone(q27, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.27, 0.0), 0.1, 0.012), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m29 = m28; m29.d = m28.d * 0.36;
    M m30 = mUs(m23, m29, 0.035);
    vec3 q31 = p - vec3(-0.13, 1.171, 0.08);
    vec3 q32 = q31 * mat3(0.951057, 0.309017, 0.0, -0.30601, 0.941801, -0.139173, -0.043007, 0.132361, 0.990268);
    vec3 q33 = q32 / vec3(1.0, 1.0, 0.36);
    vec3 q34 = q33 - vec3(0.0, -0.091, 0.0);
    M m35 = M(sdRoundCone(q34, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.27, 0.0), 0.1, 0.012), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m36 = m35; m36.d = m35.d * 0.36;
    M m37 = mUs(m30, m36, 0.035);
    M u38 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m39 = M(sdRoundCone(p, vec3(0.085, 0.6, 0.12), vec3(0.086481, 0.51963, 0.133704), 0.07, 0.066667), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u38 = mU(u38, m39);
    }
    {
      M m40 = M(sdRoundCone(p, vec3(0.086481, 0.51963, 0.133704), vec3(0.088519, 0.405926, 0.152963), 0.066667, 0.063333), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u38 = mU(u38, m40);
    }
    {
      M m41 = M(sdRoundCone(p, vec3(0.088519, 0.405926, 0.152963), vec3(0.09, 0.3, 0.17), 0.063333, 0.06), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u38 = mU(u38, m41);
    }
    {
      M m42 = M(sdRoundCone(p, vec3(0.09, 0.3, 0.17), vec3(0.09037, 0.20963, 0.182593), 0.06, 0.056667), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u38 = mU(u38, m42);
    }
    {
      M m43 = M(sdRoundCone(p, vec3(0.09037, 0.20963, 0.182593), vec3(0.090185, 0.127037, 0.192963), 0.056667, 0.053333), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u38 = mU(u38, m43);
    }
    {
      M m44 = M(sdRoundCone(p, vec3(0.090185, 0.127037, 0.192963), vec3(0.09, 0.07, 0.2), 0.053333, 0.05), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u38 = mU(u38, m44);
    }
    M m45 = mUs(m37, u38, 0.035);
    M u46 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m47 = M(sdRoundCone(p, vec3(-0.085, 0.6, 0.12), vec3(-0.086481, 0.51963, 0.133704), 0.07, 0.066667), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u46 = mU(u46, m47);
    }
    {
      M m48 = M(sdRoundCone(p, vec3(-0.086481, 0.51963, 0.133704), vec3(-0.088519, 0.405926, 0.152963), 0.066667, 0.063333), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u46 = mU(u46, m48);
    }
    {
      M m49 = M(sdRoundCone(p, vec3(-0.088519, 0.405926, 0.152963), vec3(-0.09, 0.3, 0.17), 0.063333, 0.06), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u46 = mU(u46, m49);
    }
    {
      M m50 = M(sdRoundCone(p, vec3(-0.09, 0.3, 0.17), vec3(-0.09037, 0.20963, 0.182593), 0.06, 0.056667), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u46 = mU(u46, m50);
    }
    {
      M m51 = M(sdRoundCone(p, vec3(-0.09037, 0.20963, 0.182593), vec3(-0.090185, 0.127037, 0.192963), 0.056667, 0.053333), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u46 = mU(u46, m51);
    }
    {
      M m52 = M(sdRoundCone(p, vec3(-0.090185, 0.127037, 0.192963), vec3(-0.09, 0.07, 0.2), 0.053333, 0.05), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      u46 = mU(u46, m52);
    }
    M m53 = mUs(m45, u46, 0.035);
    vec3 q54 = p;
    q54.x = abs(q54.x);
    vec3 q55 = q54 - vec3(0.09, 0.04, 0.24);
    M m56 = M(sdEllipsoid(q55, vec3(0.062, 0.04, 0.085)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m57 = mUs(m53, m56, 0.035);
    vec3 q58 = p;
    q58.x = abs(q58.x);
    vec3 q59 = q58 - vec3(0.17, 0.22, -0.02);
    vec3 q60 = q59 * mat3(1.0, 0.0, 0.0, 0.0, 0.984808, -0.173648, 0.0, 0.173648, 0.984808);
    M m61 = M(sdEllipsoid(q60, vec3(0.12, 0.17, 0.2)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m62 = mUs(m57, m61, 0.035);
    vec3 q63 = p;
    q63.x = abs(q63.x);
    vec3 q64 = q63 - vec3(0.2, 0.035, 0.11);
    M m65 = M(sdEllipsoid(q64, vec3(0.06, 0.038, 0.09)), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m66 = mUs(m62, m65, 0.035);
    M m67 = M(sdRoundCone(p, vec3(-0.12, 0.08, -0.3), vec3(-0.160078, 0.083203, -0.286562), 0.06, 0.06), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m68 = M(sdRoundCone(p, vec3(-0.160078, 0.083203, -0.286562), vec3(-0.218125, 0.086875, -0.2675), 0.06, 0.06), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m69 = mUs(m67, m68, 0.02);
    M m70 = M(sdRoundCone(p, vec3(-0.218125, 0.086875, -0.2675), vec3(-0.279609, 0.097109, -0.244687), 0.06, 0.06), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m71 = mUs(m69, m70, 0.02);
    M m72 = M(sdRoundCone(p, vec3(-0.279609, 0.097109, -0.244687), vec3(-0.33, 0.12, -0.22), 0.06, 0.06), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m73 = mUs(m71, m72, 0.02);
    M m74 = M(sdRoundCone(p, vec3(-0.33, 0.12, -0.22), vec3(-0.367578, 0.159609, -0.191875), 0.06, 0.0605), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m75 = mUs(m73, m74, 0.02);
    M m76 = M(sdRoundCone(p, vec3(-0.367578, 0.159609, -0.191875), vec3(-0.399375, 0.211875, -0.16), 0.0605, 0.061), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m77 = mUs(m75, m76, 0.02);
    M m78 = M(sdRoundCone(p, vec3(-0.399375, 0.211875, -0.16), vec3(-0.423984, 0.270703, -0.128125), 0.061, 0.0615), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m79 = mUs(m77, m78, 0.02);
    M m80 = M(sdRoundCone(p, vec3(-0.423984, 0.270703, -0.128125), vec3(-0.44, 0.33, -0.1), 0.0615, 0.062), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m81 = mUs(m79, m80, 0.02);
    M m82 = M(sdRoundCone(p, vec3(-0.44, 0.33, -0.1), vec3(-0.445781, 0.391797, -0.07625), 0.062, 0.062), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m83 = mUs(m81, m82, 0.02);
    M m84 = M(sdRoundCone(p, vec3(-0.445781, 0.391797, -0.07625), vec3(-0.4425, 0.458125, -0.055), 0.062, 0.062), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m85 = mUs(m83, m84, 0.02);
    M m86 = M(sdRoundCone(p, vec3(-0.4425, 0.458125, -0.055), vec3(-0.432969, 0.522891, -0.03625), 0.062, 0.062), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m87 = mUs(m85, m86, 0.02);
    M m88 = M(sdRoundCone(p, vec3(-0.432969, 0.522891, -0.03625), vec3(-0.42, 0.58, -0.02), 0.062, 0.062), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m89 = mUs(m87, m88, 0.02);
    M m90 = M(sdRoundCone(p, vec3(-0.42, 0.58, -0.02), vec3(-0.401719, 0.630547, -0.007187), 0.062, 0.0615), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m91 = mUs(m89, m90, 0.02);
    M m92 = M(sdRoundCone(p, vec3(-0.401719, 0.630547, -0.007187), vec3(-0.3775, 0.676875, 0.0025), 0.0615, 0.061), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m93 = mUs(m91, m92, 0.02);
    M m94 = M(sdRoundCone(p, vec3(-0.3775, 0.676875, 0.0025), vec3(-0.352031, 0.714766, 0.010938), 0.061, 0.0605), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m95 = mUs(m93, m94, 0.02);
    M m96 = M(sdRoundCone(p, vec3(-0.352031, 0.714766, 0.010938), vec3(-0.33, 0.74, 0.02), 0.0605, 0.06), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m97 = mUs(m95, m96, 0.02);
    M m98 = M(sdRoundCone(p, vec3(-0.33, 0.74, 0.02), vec3(-0.311484, 0.747188, 0.030937), 0.06, 0.0575), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m99 = mUs(m97, m98, 0.02);
    M m100 = M(sdRoundCone(p, vec3(-0.311484, 0.747188, 0.030937), vec3(-0.294375, 0.74, 0.0425), 0.0575, 0.055), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m101 = mUs(m99, m100, 0.02);
    M m102 = M(sdRoundCone(p, vec3(-0.294375, 0.74, 0.0425), vec3(-0.280078, 0.727812, 0.052812), 0.055, 0.0525), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m103 = mUs(m101, m102, 0.02);
    M m104 = M(sdRoundCone(p, vec3(-0.280078, 0.727812, 0.052812), vec3(-0.27, 0.72, 0.06), 0.0525, 0.05), vec3(0.686685, 0.181164, 0.023153), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
    M m105 = mUs(m103, m104, 0.02);
    M m106 = mUs(m66, m105, 0.035);
    if (m106.d < 0.08) {
      vec3 q108 = p - vec3(0.0, 0.87, 0.27);
      M m109 = M(sdEllipsoid(q108, vec3(0.13, 0.08, 0.1)), vec3(0.913099, 0.715694, 0.423268), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      float w107 = 1.0 - smoothstep(-0.02, 0.02001, m109.d);
      m106.c = mix(m106.c, m109.c, w107); m106.m = mix(m106.m, m109.m, w107);
      if (w107 > 0.5) { m106.c2 = m109.c2; m106.tx = m109.tx; m106.tp = m109.tp; m106.fc = m109.fc; }
    }
    if (m106.d < 0.08) {
      vec3 q111 = p - vec3(0.0, 0.96, 0.31);
      M m112 = M(sdEllipsoid(q111, vec3(0.05, 0.09, 0.05)), vec3(0.913099, 0.715694, 0.423268), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      float w110 = 1.0 - smoothstep(-0.02, 0.02001, m112.d);
      m106.c = mix(m106.c, m112.c, w110); m106.m = mix(m106.m, m112.m, w110);
      if (w110 > 0.5) { m106.c2 = m112.c2; m106.tx = m112.tx; m106.tp = m112.tp; m106.fc = m112.fc; }
    }
    if (m106.d < 0.08) {
      vec3 q114 = p - vec3(0.0, 0.55, 0.2);
      vec3 q115 = q114 * mat3(1.0, 0.0, 0.0, 0.0, 0.978148, -0.207912, 0.0, 0.207912, 0.978148);
      M m116 = M(sdEllipsoid(q115, vec3(0.12, 0.3, 0.12)), vec3(0.913099, 0.715694, 0.423268), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      float w113 = 1.0 - smoothstep(-0.02, 0.02001, m116.d);
      m106.c = mix(m106.c, m116.c, w113); m106.m = mix(m106.m, m116.m, w113);
      if (w113 > 0.5) { m106.c2 = m116.c2; m106.tx = m116.tx; m106.tp = m116.tp; m106.fc = m116.fc; }
    }
    if (m106.d < 0.08) {
      vec3 q118 = p - vec3(0.0, 0.03, 0.1);
      M m119 = M(sdBox(q118, vec3(0.4, 0.065, 0.4)), vec3(0.913099, 0.715694, 0.423268), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      float w117 = 1.0 - smoothstep(-0.02, 0.02001, m119.d);
      m106.c = mix(m106.c, m119.c, w117); m106.m = mix(m106.m, m119.m, w117);
      if (w117 > 0.5) { m106.c2 = m119.c2; m106.tx = m119.tx; m106.tp = m119.tp; m106.fc = m119.fc; }
    }
    if (m106.d < 0.08) {
      vec3 q121 = p - vec3(-0.29, 0.73, 0.05);
      M m122 = M(length(q121) - 0.1, vec3(0.913099, 0.715694, 0.423268), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      float w120 = 1.0 - smoothstep(-0.02, 0.02001, m122.d);
      m106.c = mix(m106.c, m122.c, w120); m106.m = mix(m106.m, m122.m, w120);
      if (w120 > 0.5) { m106.c2 = m122.c2; m106.tx = m122.tx; m106.tp = m122.tp; m106.fc = m122.fc; }
    }
    if (m106.d < 0.07) {
      vec3 q124 = p;
      q124.x = abs(q124.x);
      vec3 q125 = q124 - vec3(0.16, 1.17, 0.12);
      vec3 q126 = q125 * mat3(0.951057, -0.309017, 0.0, 0.309017, 0.951057, 0.0, 0.0, 0.0, 1.0);
      M m127 = M(sdEllipsoid(q126, vec3(0.06, 0.12, 0.05)), vec3(0.814847, 0.323143, 0.270498), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
      float w123 = 1.0 - smoothstep(-0.01, 0.01001, m127.d);
      m106.c = mix(m106.c, m127.c, w123); m106.m = mix(m106.m, m127.m, w123);
      if (w123 > 0.5) { m106.c2 = m127.c2; m106.tx = m127.tx; m106.tp = m127.tp; m106.fc = m127.fc; }
    }
    if (m106.d < 0.075) {
      M u129 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q130 = p - vec3(0.0, 1.1, 0.27);
        M m131 = M(sdEllipsoid(q130, vec3(0.02, 0.07, 0.05)), vec3(0.584078, 0.152926, 0.012983), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
        u129 = mU(u129, m131);
      }
      {
        vec3 q132 = p;
        q132.x = abs(q132.x);
        vec3 q133 = q132 - vec3(0.06, 1.09, 0.26);
        vec3 q134 = q133 * mat3(0.965926, -0.258819, 0.0, 0.258819, 0.965926, 0.0, 0.0, 0.0, 1.0);
        M m135 = M(sdEllipsoid(q134, vec3(0.02, 0.06, 0.05)), vec3(0.584078, 0.152926, 0.012983), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
        u129 = mU(u129, m135);
      }
      if (sdBox(p - vec3(0.0, 0.42, -0.25), vec3(0.31, 0.180646, 0.259241)) < u129.d) {
        M u136 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q137 = p - vec3(0.0, 0.31, -0.25);
          vec3 q138 = q137 * mat3(1.0, 0.0, 0.0, 0.0, 0.984808, 0.173648, 0.0, -0.173648, 0.984808);
          M m139 = M(sdBox(q138, vec3(0.3, 0.0175, 0.25)), vec3(0.584078, 0.152926, 0.012983), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
          u136 = mU(u136, m139);
        }
        {
          vec3 q140 = p - vec3(0.0, 0.42, -0.25);
          vec3 q141 = q140 * mat3(1.0, 0.0, 0.0, 0.0, 0.984808, 0.173648, 0.0, -0.173648, 0.984808);
          M m142 = M(sdBox(q141, vec3(0.3, 0.0175, 0.25)), vec3(0.584078, 0.152926, 0.012983), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
          u136 = mU(u136, m142);
        }
        {
          vec3 q143 = p - vec3(0.0, 0.53, -0.25);
          vec3 q144 = q143 * mat3(1.0, 0.0, 0.0, 0.0, 0.984808, 0.173648, 0.0, -0.173648, 0.984808);
          M m145 = M(sdBox(q144, vec3(0.3, 0.0175, 0.25)), vec3(0.584078, 0.152926, 0.012983), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 320.11);
          u136 = mU(u136, m145);
        }
        u129 = mU(u129, u136);
      }
      float w128 = 1.0 - smoothstep(-0.015, 0.01501, u129.d);
      m106.c = mix(m106.c, u129.c, w128); m106.m = mix(m106.m, u129.m, w128);
      if (w128 > 0.5) { m106.c2 = u129.c2; m106.tx = u129.tx; m106.tp = u129.tp; m106.fc = u129.fc; }
    }
    u0 = mU(u0, m106);
  }
  if (sdBox(p - vec3(0.1, 0.985, 0.2615), vec3(0.079, 0.079, 0.0805)) < u0.d) {
    vec3 q146 = p - vec3(0.1, 0.985, 0.27);
    M u147 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q148 = q146 - vec3(0.0, 0.0, -0.01);
      M m149 = M(length(q148) - 0.069, vec3(0.023153, 0.01033, 0.005182), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u147 = mU(u147, m149);
    }
    if (sdBox(q146 - vec3(0.0, 0.0, 0.0), vec3(0.072, 0.072, 0.072)) < u147.d) {
      M m150 = M(length(q146) - 0.062, vec3(0.212231, 0.450786, 0.042311), vec3(0.15, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      if (m150.d < 0.064) {
        vec3 q152 = q146 - vec3(0.0, 0.0, 0.05);
        M m153 = M(sdEllipsoid(q152, vec3(0.024, 0.05, 0.03)), vec3(0.005182, 0.005182, 0.005182), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        float w151 = 1.0 - smoothstep(-0.004, 0.00401, m153.d);
        m150.c = mix(m150.c, m153.c, w151); m150.m = mix(m150.m, m153.m, w151);
        if (w151 > 0.5) { m150.c2 = m153.c2; m150.tx = m153.tx; m150.tp = m153.tp; m150.fc = m153.fc; }
      }
      if (m150.d < 0.062) {
        vec3 q155 = q146 - vec3(0.014, 0.026, 0.053);
        M m156 = M(length(q155) - 0.014, vec3(0.887923, 0.887923, 0.887923), vec3(0.6, 0.0, 0.6), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        float w154 = 1.0 - smoothstep(-0.002, 0.00201, m156.d);
        m150.c = mix(m150.c, m156.c, w154); m150.m = mix(m150.m, m156.m, w154);
        if (w154 > 0.5) { m150.c2 = m156.c2; m150.tx = m156.tx; m150.tp = m156.tp; m150.fc = m156.fc; }
      }
      u147 = mU(u147, m150);
    }
    u0 = mU(u0, u147);
  }
  if (sdBox(p - vec3(-0.1, 0.985, 0.2615), vec3(0.079, 0.079, 0.0805)) < u0.d) {
    vec3 q157 = p - vec3(-0.1, 0.985, 0.27);
    M u158 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q159 = q157 - vec3(0.0, 0.0, -0.01);
      M m160 = M(length(q159) - 0.069, vec3(0.023153, 0.01033, 0.005182), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u158 = mU(u158, m160);
    }
    if (sdBox(q157 - vec3(0.0, 0.0, 0.0), vec3(0.072, 0.072, 0.072)) < u158.d) {
      M m161 = M(length(q157) - 0.062, vec3(0.212231, 0.450786, 0.042311), vec3(0.15, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      if (m161.d < 0.064) {
        vec3 q163 = q157 - vec3(0.0, 0.0, 0.05);
        M m164 = M(sdEllipsoid(q163, vec3(0.024, 0.05, 0.03)), vec3(0.005182, 0.005182, 0.005182), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        float w162 = 1.0 - smoothstep(-0.004, 0.00401, m164.d);
        m161.c = mix(m161.c, m164.c, w162); m161.m = mix(m161.m, m164.m, w162);
        if (w162 > 0.5) { m161.c2 = m164.c2; m161.tx = m164.tx; m161.tp = m164.tp; m161.fc = m164.fc; }
      }
      if (m161.d < 0.062) {
        vec3 q166 = q157 - vec3(0.014, 0.026, 0.053);
        M m167 = M(length(q166) - 0.014, vec3(0.887923, 0.887923, 0.887923), vec3(0.6, 0.0, 0.6), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        float w165 = 1.0 - smoothstep(-0.002, 0.00201, m167.d);
        m161.c = mix(m161.c, m167.c, w165); m161.m = mix(m161.m, m167.m, w165);
        if (w165 > 0.5) { m161.c2 = m167.c2; m161.tx = m167.tx; m161.tp = m167.tp; m161.fc = m167.fc; }
      }
      u158 = mU(u158, m161);
    }
    u0 = mU(u0, u158);
  }
  {
    vec3 q168 = p - vec3(0.0, 0.9055, 0.33);
    vec3 q169 = q168 / vec3(1.2, 1.0, 0.8);
    vec3 q170 = q169 - vec3(0.0, 0.0095, 0.0);
    M m171 = M(sdRoundCone(q170, vec3(0.0, 0.0, 0.0), vec3(0.0, -0.035, 0.0), 0.024, 0.008), vec3(0.814847, 0.323143, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 160.02);
    M m172 = m171; m172.d = m171.d * 0.8;
    u0 = mU(u0, m172);
  }
  {
    M u173 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q174 = p;
      q174.x = abs(q174.x);
      vec3 q175 = q174 - vec3(0.0175, 0.8625, 0.325);
      vec3 q176 = q175 * mat3(-0.393919, -0.919145, 0.0, 0.889001, -0.381, -0.254, 0.233463, -0.100056, 0.967204);
      M m177 = M(sdCapsule(q176, 0.004, 0.019685), vec3(0.194618, 0.068478, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u173 = mU(u173, m177);
    }
    {
      vec3 q178 = p - vec3(0.0, 0.8825, 0.3335);
      vec3 q179 = q178 * mat3(-1.0, 0.0, 0.0, 0.0, -0.989949, -0.141421, 0.0, -0.141421, 0.989949);
      M m180 = M(sdCapsule(q179, 0.004, 0.010607), vec3(0.194618, 0.068478, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u173 = mU(u173, m180);
    }
    u0 = mU(u0, u173);
  }
  if (sdBox(p - vec3(0.0, 0.849919, 0.27), vec3(0.344421, 0.063827, 0.044219)) < u0.d) {
    vec3 q181 = p;
    q181.x = abs(q181.x);
    M u182 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q183 = q181 - vec3(0.205, 0.8925, 0.27);
      vec3 q184 = q183 * mat3(0.059892, -0.998205, 0.0, 0.970737, 0.058244, -0.232977, 0.232559, 0.013954, 0.972482);
      M m185 = M(sdCapsule(q184, 0.0035, 0.128768), vec3(1.0, 0.921582, 0.806952), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u182 = mU(u182, m185);
    }
    {
      vec3 q186 = q181 - vec3(0.2, 0.86, 0.275);
      vec3 q187 = q186 * mat3(-0.124035, -0.992278, 0.0, 0.971732, -0.121466, -0.202444, 0.200881, -0.02511, 0.979294);
      M m188 = M(sdCapsule(q187, 0.0035, 0.123491), vec3(1.0, 0.921582, 0.806952), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u182 = mU(u182, m188);
    }
    {
      vec3 q189 = q181 - vec3(0.1825, 0.8325, 0.265);
      vec3 q190 = q189 * mat3(-0.28939, -0.957211, 0.0, 0.934341, -0.282475, -0.217289, 0.207991, -0.062881, 0.976107);
      M m191 = M(sdCapsule(q190, 0.003, 0.115054), vec3(1.0, 0.921582, 0.806952), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u182 = mU(u182, m191);
    }
    u0 = mU(u0, u182);
  }
  return u0;
}
