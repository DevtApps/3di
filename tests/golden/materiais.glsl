
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
  {
    M m1 = M(p.y, vec3(0.814847, 0.775822, 0.701102), vec3(0.25, 0.0, 0.0), vec3(0.024158, 0.024158, 0.027321), vec4(5.0, 0.6, 1.0, 0.0), p, 0.0);
    u0 = mU(u0, m1);
  }
  if (sdBox(p - vec3(0.0, 1.5, -2.2), vec3(3.01, 1.51, 0.185)) < u0.d) {
    vec3 q2 = p - vec3(0.0, 1.5, -2.2);
    M m3 = M(sdBox(q2, vec3(3.0, 1.5, 0.175)), vec3(0.391572, 0.08022, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.69, 0.65, 0.58), vec4(6.0, 0.28, 1.0, 0.0), p, 0.0);
    vec3 q4 = p - vec3(1.6, 1.45, -2.2);
    M u5 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m6 = M(sdBox(q4, vec3(0.6, 0.65, 0.5)), vec3(0.391572, 0.08022, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.69, 0.65, 0.58), vec4(6.0, 0.28, 1.0, 0.0), p, 0.0);
      u5 = mU(u5, m6);
    }
    {
      vec3 q7 = q4 - vec3(0.0, 0.65, 0.0);
      vec3 q8 = q7 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m9 = M(sdCyl(q8, 0.6, 0.5), vec3(0.391572, 0.08022, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.69, 0.65, 0.58), vec4(6.0, 0.28, 1.0, 0.0), p, 0.0);
      u5 = mU(u5, m9);
    }
    M m10 = mS(m3, u5);
    u0 = mU(u0, m10);
  }
  {
    vec3 q11 = p - vec3(-0.6, 0.0, -0.6);
    M u12 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q13 = q11 - vec3(0.0, 0.75, 0.0);
      M m14 = M(sdBox(q13, vec3(0.79, 0.02, 0.39)) - 0.01, vec3(0.434154, 0.194618, 0.059511), vec3(0.45, 0.0, 0.0), vec3(0.217077, 0.097309, 0.029756), vec4(2.0, 0.06, 0.0, 0.0), q11, 0.0);
      u12 = mU(u12, m14);
    }
    {
      vec3 q15 = q11;
      q15.x = abs(q15.x);
      q15.z = abs(q15.z);
      vec3 q16 = q15 - vec3(0.7, 0.36, 0.32);
      M m17 = M(sdBox(q16, vec3(0.035, 0.36, 0.035)), vec3(0.434154, 0.194618, 0.059511), vec3(0.45, 0.0, 0.0), vec3(0.217077, 0.097309, 0.029756), vec4(2.0, 0.06, 0.0, 0.0), q11, 0.0);
      u12 = mU(u12, m17);
    }
    u0 = mU(u0, u12);
  }
  {
    vec3 q18 = p - vec3(-1.0, 0.96, -0.6);
    M m19 = M(length(q18) - 0.18, vec3(0.904661, 0.879622, 0.822786), vec3(0.15, 0.0, 0.0), vec3(0.068478, 0.076185, 0.095307), vec4(3.0, 0.3, 1.0, 0.0), q18, 0.0);
    u0 = mU(u0, m19);
  }
  {
    vec3 q20 = p - vec3(-0.25, 0.94, -0.6);
    M m21 = M(sdCyl(q20, 0.1, 0.14) - 0.02, vec3(0.028426, 0.205079, 0.262251), vec3(0.6, 0.0, 0.0), vec3(0.887923, 0.806952, 0.62396), vec4(4.0, 0.04, 1.0, 0.0), q20, 0.0);
    vec3 q22 = q20 - vec3(0.0, 0.06, 0.0);
    M m23 = M(sdCyl(q22, 0.1, 0.2), vec3(0.028426, 0.205079, 0.262251), vec3(0.6, 0.0, 0.0), vec3(0.887923, 0.806952, 0.62396), vec4(4.0, 0.04, 1.0, 0.0), q20, 0.0);
    M m24 = mS(m21, m23);
    u0 = mU(u0, m24);
  }
  if (sdBox(p - vec3(-2.3, 1.26, -1.3), vec3(0.31, 1.27, 0.31)) < u0.d) {
    vec3 q25 = p - vec3(-2.3, 0.0, -1.3);
    M u26 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q27 = q25 - vec3(0.0, 1.2, 0.0);
      M m28 = M(sdCyl(q27, 0.22, 1.2), vec3(0.887923, 0.887923, 0.887923), vec3(0.2, 0.0, 0.0), vec3(0.221981, 0.221981, 0.221981), vec4(3.0, 0.4, 1.0, 0.0), q25, 0.0);
      u26 = mU(u26, m28);
    }
    {
      vec3 q29 = q25 - vec3(0.0, 0.06, 0.0);
      M m30 = M(sdBox(q29, vec3(0.3, 0.06, 0.3)), vec3(0.887923, 0.887923, 0.887923), vec3(0.2, 0.0, 0.0), vec3(0.221981, 0.221981, 0.221981), vec4(3.0, 0.4, 1.0, 0.0), q25, 0.0);
      u26 = mU(u26, m30);
    }
    {
      vec3 q31 = q25 - vec3(0.0, 2.46, 0.0);
      M m32 = M(sdBox(q31, vec3(0.3, 0.06, 0.3)), vec3(0.887923, 0.887923, 0.887923), vec3(0.2, 0.0, 0.0), vec3(0.221981, 0.221981, 0.221981), vec4(3.0, 0.4, 1.0, 0.0), q25, 0.0);
      u26 = mU(u26, m32);
    }
    u0 = mU(u0, u26);
  }
  if (sdBox(p - vec3(1.800825, 0.42525, 0.646), vec3(1.000575, 0.43525, 0.834)) < u0.d) {
    M u33 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(p - vec3(1.6, 0.42525, 0.6), vec3(0.79975, 0.43525, 0.6175)) < u33.d) {
      vec3 q34 = p - vec3(1.6, 0.42525, 0.6);
      vec3 q35 = q34 / vec3(1.3, 0.7, 1.0);
      M m36 = M(length(q35) - 0.45, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.161572, 0.152494, 0.135249), vec4(1.0, 0.27, 1.0, 0.0), q34, 0.0);
      M m37 = m36; m37.d = (m36.d + 0.1575 * (fbm(q35 / 0.315) * 2.0 - 1.0)) * 0.444444;
      M m38 = m37; m38.d = m37.d * 0.7;
      u33 = mU(u33, m38);
    }
    if (sdBox(p - vec3(2.3, 0.2646, 0.2), vec3(0.5014, 0.2746, 0.388)) < u33.d) {
      vec3 q39 = p - vec3(2.3, 0.2646, 0.2);
      vec3 q40 = q39 / vec3(1.3, 0.7, 1.0);
      M m41 = M(length(q40) - 0.28, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.161572, 0.152494, 0.135249), vec4(1.0, 0.168, 1.0, 0.0), q39, 0.0);
      M m42 = m41; m42.d = (m41.d + 0.098 * (fbm(q40 / 0.196) * 2.0 - 1.0)) * 0.444444;
      M m43 = m42; m43.d = m42.d * 0.7;
      u33 = mU(u33, m43);
    }
    if (sdBox(p - vec3(1.2, 0.189, 1.2), vec3(0.361, 0.199, 0.28)) < u33.d) {
      vec3 q44 = p - vec3(1.2, 0.189, 1.2);
      vec3 q45 = q44 / vec3(1.3, 0.7, 1.0);
      M m46 = M(length(q45) - 0.2, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.161572, 0.152494, 0.135249), vec4(1.0, 0.12, 1.0, 0.0), q44, 0.0);
      M m47 = m46; m47.d = (m46.d + 0.07 * (fbm(q45 / 0.14) * 2.0 - 1.0)) * 0.444444;
      M m48 = m47; m48.d = m47.d * 0.7;
      u33 = mU(u33, m48);
    }
    u0 = mU(u0, u33);
  }
  return u0;
}
