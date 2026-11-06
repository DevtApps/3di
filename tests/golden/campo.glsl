
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

M mapAll(vec3 p, bool wantMat) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    M m1 = M(p.y, vec3(0.028426, 0.102242, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  if (cullVis(0) && sdBox(p - vec3(-1.65, 0.100901, -0.358908), vec3(0.56, 0.110901, 3.468908)) < u0.d) {
    vec3 q2 = p - vec3(-1.65, 0.0, -0.4);
    M u3 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q2 - vec3(0.0, 0.038671, 0.0), vec3(0.56, 0.048671, 3.306323)) < u3.d) {
      vec3 q4 = q2 - vec3(0.0, 0.038671, 0.0);
      vec3 q5 = q4 * mat3(0.891007, 0.0, 0.45399, 0.0, 1.0, 0.0, -0.45399, 0.0, 0.891007);
      vec3 id6 = clamp(round(q5 / vec3(0.110185, 1.0, 0.110185) + vec3(4.0, 0.0, 31.0)), vec3(0.0), vec3(8.0, 0.0, 62.0));
      vec3 q7 = q5 - vec3(0.110185, 1.0, 0.110185) * (id6 - vec3(4.0, 0.0, 31.0));
      vec3 q8 = q7 * mat3(0.970967, 0.0, 0.239214, 0.0, 1.0, 0.0, -0.239214, 0.0, 0.970967);
      vec3 q9 = q8 * mat3(1.0, 0.0, 0.0, 0.0, 0.939195, 0.343384, 0.0, -0.343384, 0.939195);
      vec3 q10 = q9 / vec3(1.0, 1.0, 0.16);
      M m11 = M(sdPyramid((q10 + vec3(0.0, 0.03825, 0.0)) / 0.1, 0.765) * 0.1, vec3(0.017389, 0.147319, 0.007194), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m12 = m11; m12.d = m11.d * 0.16;
      vec3 q13 = q2 - vec3(0.0, 1.0, 0.0);
      M m14 = M(sdBox(q13, vec3(0.55, 1.0, 3.5)), vec3(0.017389, 0.147319, 0.007194), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m15 = mI(m12, m14);
      u3 = mU(u3, m15);
    }
    if (sdBox(q2 - vec3(0.0, 0.046426, 0.029), vec3(0.56, 0.056426, 3.456816)) < u3.d) {
      vec3 q16 = q2 - vec3(0.017, 0.046426, 0.029);
      vec3 q17 = q16 * mat3(0.93358, 0.0, 0.358368, 0.0, 1.0, 0.0, -0.358368, 0.0, 0.93358);
      vec3 id18 = clamp(round(q17 / vec3(0.137077, 1.0, 0.137077) + vec3(3.5, 0.0, 25.0)), vec3(0.0), vec3(7.0, 0.0, 50.0));
      vec3 q19 = q17 - vec3(0.137077, 1.0, 0.137077) * (id18 - vec3(3.5, 0.0, 25.0));
      vec3 q20 = q19 * mat3(0.826611, 0.0, -0.562774, 0.0, 1.0, 0.0, 0.562774, 0.0, 0.826611);
      vec3 q21 = q20 * mat3(1.0, 0.0, 0.0, 0.0, 0.95938, 0.282119, 0.0, -0.282119, 0.95938);
      vec3 q22 = q21 / vec3(1.0, 1.0, 0.16);
      M m23 = M(sdPyramid((q22 + vec3(0.0, 0.045333, 0.0)) / 0.13, 0.697436) * 0.13, vec3(0.030402, 0.182595, 0.010023), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m24 = m23; m24.d = m23.d * 0.16;
      vec3 q25 = q2 - vec3(0.0, 1.0, 0.0);
      M m26 = M(sdBox(q25, vec3(0.55, 1.0, 3.5)), vec3(0.030402, 0.182595, 0.010023), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m27 = mI(m24, m26);
      u3 = mU(u3, m27);
    }
    if (sdBox(q2 - vec3(0.0, 0.053559, 0.055215), vec3(0.56, 0.063559, 3.454785)) < u3.d) {
      vec3 q28 = q2 - vec3(0.034, 0.053559, 0.058);
      vec3 q29 = q28 * mat3(0.965926, 0.0, 0.258819, 0.0, 1.0, 0.0, -0.258819, 0.0, 0.965926);
      vec3 id30 = clamp(round(q29 / vec3(0.168267, 1.0, 0.168267) + vec3(2.5, 0.0, 20.0)), vec3(0.0), vec3(5.0, 0.0, 40.0));
      vec3 q31 = q29 - vec3(0.168267, 1.0, 0.168267) * (id30 - vec3(2.5, 0.0, 20.0));
      vec3 q32 = q31 * mat3(-0.059923, 0.0, -0.998203, 0.0, 1.0, 0.0, 0.998203, 0.0, -0.059923);
      vec3 q33 = q32 * mat3(1.0, 0.0, 0.0, 0.0, 0.935555, 0.353182, 0.0, -0.353182, 0.935555);
      vec3 q34 = q33 / vec3(1.0, 1.0, 0.16);
      M m35 = M(sdPyramid((q34 + vec3(0.0, 0.052417, 0.0)) / 0.16, 0.655208) * 0.16, vec3(0.047818, 0.222361, 0.013412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m36 = m35; m36.d = m35.d * 0.16;
      vec3 q37 = q2 - vec3(0.0, 1.0, 0.0);
      M m38 = M(sdBox(q37, vec3(0.55, 1.0, 3.5)), vec3(0.047818, 0.222361, 0.013412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m39 = mI(m36, m38);
      u3 = mU(u3, m39);
    }
    if (sdBox(q2 - vec3(0.0, 0.05927, 0.049679), vec3(0.56, 0.06927, 3.460321)) < u3.d) {
      vec3 q40 = q2 - vec3(0.051, 0.05927, 0.087);
      vec3 q41 = q40 * mat3(0.987688, 0.0, 0.156434, 0.0, 1.0, 0.0, -0.156434, 0.0, 0.987688);
      vec3 id42 = clamp(round(q41 / vec3(0.111419, 1.0, 0.111419) + vec3(4.0, 0.0, 30.5)), vec3(0.0), vec3(8.0, 0.0, 61.0));
      vec3 q43 = q41 - vec3(0.111419, 1.0, 0.111419) * (id42 - vec3(4.0, 0.0, 30.5));
      vec3 q44 = q43 * mat3(-0.654134, 0.0, -0.756379, 0.0, 1.0, 0.0, 0.756379, 0.0, -0.654134);
      vec3 q45 = q44 * mat3(1.0, 0.0, 0.0, 0.0, 0.957248, 0.289269, 0.0, -0.289269, 0.957248);
      vec3 q46 = q45 / vec3(1.0, 1.0, 0.16);
      M m47 = M(sdPyramid((q46 + vec3(0.0, 0.0595, 0.0)) / 0.1, 1.19) * 0.1, vec3(0.069981, 0.266768, 0.017389), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m48 = m47; m48.d = m47.d * 0.16;
      vec3 q49 = q2 - vec3(0.0, 1.0, 0.0);
      M m50 = M(sdBox(q49, vec3(0.55, 1.0, 3.5)), vec3(0.069981, 0.266768, 0.017389), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m51 = mI(m48, m50);
      u3 = mU(u3, m51);
    }
    if (sdBox(q2 - vec3(0.0, 0.067154, 0.088574), vec3(0.56, 0.077154, 3.421426)) < u3.d) {
      vec3 q52 = q2 - vec3(0.068, 0.067154, 0.116);
      vec3 q53 = q52 * mat3(0.99863, 0.0, 0.052336, 0.0, 1.0, 0.0, -0.052336, 0.0, 0.99863);
      vec3 id54 = clamp(round(q53 / vec3(0.140897, 1.0, 0.140897) + vec3(3.0, 0.0, 24.0)), vec3(0.0), vec3(6.0, 0.0, 48.0));
      vec3 q55 = q53 - vec3(0.140897, 1.0, 0.140897) * (id54 - vec3(3.0, 0.0, 24.0));
      vec3 q56 = q55 * mat3(-0.986059, 0.0, 0.166394, 0.0, 1.0, 0.0, -0.166394, 0.0, -0.986059);
      vec3 q57 = q56 * mat3(1.0, 0.0, 0.0, 0.0, 0.971609, 0.236594, 0.0, -0.236594, 0.971609);
      vec3 q58 = q57 / vec3(1.0, 1.0, 0.16);
      M m59 = M(sdPyramid((q58 + vec3(0.0, 0.066583, 0.0)) / 0.13, 1.024359) * 0.13, vec3(0.097205, 0.315959, 0.021981), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m60 = m59; m60.d = m59.d * 0.16;
      vec3 q61 = q2 - vec3(0.0, 1.0, 0.0);
      M m62 = M(sdBox(q61, vec3(0.55, 1.0, 3.5)), vec3(0.097205, 0.315959, 0.021981), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m63 = mI(m60, m62);
      u3 = mU(u3, m63);
    }
    if (sdBox(q2 - vec3(0.0, 0.074677, 0.07932), vec3(0.56, 0.084677, 3.43068)) < u3.d) {
      vec3 q64 = q2 - vec3(0.085, 0.074677, 0.145);
      vec3 q65 = q64 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
      vec3 id66 = clamp(round(q65 / vec3(0.16146, 1.0, 0.16146) + vec3(2.5, 0.0, 21.0)), vec3(0.0), vec3(5.0, 0.0, 42.0));
      vec3 q67 = q65 - vec3(0.16146, 1.0, 0.16146) * (id66 - vec3(2.5, 0.0, 21.0));
      vec3 q68 = q67 * mat3(-0.737186, 0.0, 0.67569, 0.0, 1.0, 0.0, -0.67569, 0.0, -0.737186);
      vec3 q69 = q68 * mat3(1.0, 0.0, 0.0, 0.0, 0.975424, 0.220337, 0.0, -0.220337, 0.975424);
      vec3 q70 = q69 / vec3(1.0, 1.0, 0.16);
      M m71 = M(sdPyramid((q70 + vec3(0.0, 0.073667, 0.0)) / 0.16, 0.920833) * 0.16, vec3(0.129775, 0.370071, 0.027212), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m72 = m71; m72.d = m71.d * 0.16;
      vec3 q73 = q2 - vec3(0.0, 1.0, 0.0);
      M m74 = M(sdBox(q73, vec3(0.55, 1.0, 3.5)), vec3(0.129775, 0.370071, 0.027212), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m75 = mI(m72, m74);
      u3 = mU(u3, m75);
    }
    if (sdBox(q2 - vec3(0.0, 0.078619, 0.091844), vec3(0.56, 0.088619, 3.418156)) < u3.d) {
      vec3 q76 = q2 - vec3(0.102, 0.078619, 0.174);
      vec3 q77 = q76 * mat3(0.987688, 0.0, -0.156434, 0.0, 1.0, 0.0, 0.156434, 0.0, 0.987688);
      vec3 id78 = clamp(round(q77 / vec3(0.115184, 1.0, 0.115184) + vec3(4.0, 0.0, 29.5)), vec3(0.0), vec3(8.0, 0.0, 59.0));
      vec3 q79 = q77 - vec3(0.115184, 1.0, 0.115184) * (id78 - vec3(4.0, 0.0, 29.5));
      vec3 q80 = q79 * mat3(0.195978, 0.0, 0.980608, 0.0, 1.0, 0.0, -0.980608, 0.0, 0.195978);
      vec3 q81 = q80 * mat3(1.0, 0.0, 0.0, 0.0, 0.939734, 0.341906, 0.0, -0.341906, 0.939734);
      vec3 q82 = q81 / vec3(1.0, 1.0, 0.16);
      M m83 = M(sdPyramid((q82 + vec3(0.0, 0.08075, 0.0)) / 0.1, 1.615) * 0.1, vec3(0.167954, 0.429235, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m84 = m83; m84.d = m83.d * 0.16;
      vec3 q85 = q2 - vec3(0.0, 1.0, 0.0);
      M m86 = M(sdBox(q85, vec3(0.55, 1.0, 3.5)), vec3(0.167954, 0.429235, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m87 = mI(m84, m86);
      u3 = mU(u3, m87);
    }
    if (sdBox(q2 - vec3(0.0, 0.085684, 0.108529), vec3(0.56, 0.095684, 3.401471)) < u3.d) {
      vec3 q88 = q2 - vec3(0.119, 0.085684, 0.203);
      vec3 q89 = q88 * mat3(0.965926, 0.0, -0.258819, 0.0, 1.0, 0.0, 0.258819, 0.0, 0.965926);
      vec3 id90 = clamp(round(q89 / vec3(0.154712, 1.0, 0.154712) + vec3(3.0, 0.0, 22.0)), vec3(0.0), vec3(6.0, 0.0, 44.0));
      vec3 q91 = q89 - vec3(0.154712, 1.0, 0.154712) * (id90 - vec3(3.0, 0.0, 22.0));
      vec3 q92 = q91 * mat3(0.942018, 0.0, 0.335563, 0.0, 1.0, 0.0, -0.335563, 0.0, 0.942018);
      vec3 q93 = q92 * mat3(1.0, 0.0, 0.0, 0.0, 0.932877, 0.360196, 0.0, -0.360196, 0.932877);
      vec3 q94 = q93 / vec3(1.0, 1.0, 0.16);
      M m95 = M(sdPyramid((q94 + vec3(0.0, 0.087833, 0.0)) / 0.13, 1.351282) * 0.13, vec3(0.21199, 0.493578, 0.039682), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m96 = m95; m96.d = m95.d * 0.16;
      vec3 q97 = q2 - vec3(0.0, 1.0, 0.0);
      M m98 = M(sdBox(q97, vec3(0.55, 1.0, 3.5)), vec3(0.21199, 0.493578, 0.039682), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m99 = mI(m96, m98);
      u3 = mU(u3, m99);
    }
    if (sdBox(q2 - vec3(0.0, 0.095092, 0.179359), vec3(0.56, 0.105092, 3.330641)) < u3.d) {
      vec3 q100 = q2 - vec3(0.136, 0.095092, 0.232);
      vec3 q101 = q100 * mat3(0.93358, 0.0, -0.358368, 0.0, 1.0, 0.0, 0.358368, 0.0, 0.93358);
      vec3 id102 = clamp(round(q101 / vec3(0.1807, 1.0, 0.1807) + vec3(2.5, 0.0, 18.5)), vec3(0.0), vec3(5.0, 0.0, 37.0));
      vec3 q103 = q101 - vec3(0.1807, 1.0, 0.1807) * (id102 - vec3(2.5, 0.0, 18.5));
      vec3 q104 = q103 * mat3(0.92902, 0.0, -0.37003, 0.0, 1.0, 0.0, 0.37003, 0.0, 0.92902);
      vec3 q105 = q104 * mat3(1.0, 0.0, 0.0, 0.0, 0.968013, 0.250899, 0.0, -0.250899, 0.968013);
      vec3 q106 = q105 / vec3(1.0, 1.0, 0.16);
      M m107 = M(sdPyramid((q106 + vec3(0.0, 0.094917, 0.0)) / 0.16, 1.186458) * 0.16, vec3(0.262114, 0.563221, 0.046964), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m108 = m107; m108.d = m107.d * 0.16;
      vec3 q109 = q2 - vec3(0.0, 1.0, 0.0);
      M m110 = M(sdBox(q109, vec3(0.55, 1.0, 3.5)), vec3(0.262114, 0.563221, 0.046964), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m111 = mI(m108, m110);
      u3 = mU(u3, m111);
    }
    if (sdBox(q2 - vec3(0.0, 0.100901, 0.204224), vec3(0.56, 0.110901, 3.305776)) < u3.d) {
      vec3 q112 = q2 - vec3(0.153, 0.100901, 0.261);
      vec3 q113 = q112 * mat3(0.891007, 0.0, -0.45399, 0.0, 1.0, 0.0, 0.45399, 0.0, 0.891007);
      vec3 id114 = clamp(round(q113 / vec3(0.120484, 1.0, 0.120484) + vec3(4.0, 0.0, 28.5)), vec3(0.0), vec3(8.0, 0.0, 57.0));
      vec3 q115 = q113 - vec3(0.120484, 1.0, 0.120484) * (id114 - vec3(4.0, 0.0, 28.5));
      vec3 q116 = q115 * mat3(0.371948, 0.0, -0.928254, 0.0, 1.0, 0.0, 0.928254, 0.0, 0.371948);
      vec3 q117 = q116 * mat3(1.0, 0.0, 0.0, 0.0, 0.970235, 0.242167, 0.0, -0.242167, 0.970235);
      vec3 q118 = q117 / vec3(1.0, 1.0, 0.16);
      M m119 = M(sdPyramid((q118 + vec3(0.0, 0.102, 0.0)) / 0.1, 2.04) * 0.1, vec3(0.318547, 0.638283, 0.054972), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m120 = m119; m120.d = m119.d * 0.16;
      vec3 q121 = q2 - vec3(0.0, 1.0, 0.0);
      M m122 = M(sdBox(q121, vec3(0.55, 1.0, 3.5)), vec3(0.318547, 0.638283, 0.054972), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m123 = mI(m120, m122);
      u3 = mU(u3, m123);
    }
    u0 = mU(u0, u3);
  }
  if (cullVis(1) && sdBox(p - vec3(-0.55, 0.098797, -0.368387), vec3(0.56, 0.108797, 3.478387)) < u0.d) {
    vec3 q124 = p - vec3(-0.55, 0.0, -0.4);
    M u125 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q124 - vec3(0.0, 0.038894, 0.0), vec3(0.56, 0.048894, 3.317158)) < u125.d) {
      vec3 q126 = q124 - vec3(0.0, 0.038894, 0.0);
      vec3 q127 = q126 * mat3(0.891007, 0.0, 0.45399, 0.0, 1.0, 0.0, -0.45399, 0.0, 0.891007);
      vec3 id128 = clamp(round(q127 / vec3(0.108234, 1.0, 0.108234) + vec3(4.5, 0.0, 31.5)), vec3(0.0), vec3(9.0, 0.0, 63.0));
      vec3 q129 = q127 - vec3(0.108234, 1.0, 0.108234) * (id128 - vec3(4.5, 0.0, 31.5));
      vec3 q130 = q129 * mat3(0.984953, 0.0, -0.172823, 0.0, 1.0, 0.0, 0.172823, 0.0, 0.984953);
      vec3 q131 = q130 * mat3(1.0, 0.0, 0.0, 0.0, 0.954397, 0.298541, 0.0, -0.298541, 0.954397);
      vec3 q132 = q131 / vec3(1.0, 1.0, 0.16);
      M m133 = M(sdPyramid((q132 + vec3(0.0, 0.03825, 0.0)) / 0.1, 0.765) * 0.1, vec3(0.003936, 0.073239, 0.007194), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m134 = m133; m134.d = m133.d * 0.16;
      vec3 q135 = q124 - vec3(0.0, 1.0, 0.0);
      M m136 = M(sdBox(q135, vec3(0.55, 1.0, 3.5)), vec3(0.003936, 0.073239, 0.007194), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m137 = mI(m134, m136);
      u125 = mU(u125, m137);
    }
    if (sdBox(q124 - vec3(0.0, 0.046359, 0.029), vec3(0.56, 0.056359, 3.417003)) < u125.d) {
      vec3 q138 = q124 - vec3(0.017, 0.046359, 0.029);
      vec3 q139 = q138 * mat3(0.93358, 0.0, 0.358368, 0.0, 1.0, 0.0, -0.358368, 0.0, 0.93358);
      vec3 id140 = clamp(round(q139 / vec3(0.139124, 1.0, 0.139124) + vec3(3.0, 0.0, 24.5)), vec3(0.0), vec3(6.0, 0.0, 49.0));
      vec3 q141 = q139 - vec3(0.139124, 1.0, 0.139124) * (id140 - vec3(3.0, 0.0, 24.5));
      vec3 q142 = q141 * mat3(0.844812, 0.0, -0.535063, 0.0, 1.0, 0.0, 0.535063, 0.0, 0.844812);
      vec3 q143 = q142 * mat3(1.0, 0.0, 0.0, 0.0, 0.953405, 0.301692, 0.0, -0.301692, 0.953405);
      vec3 q144 = q143 / vec3(1.0, 1.0, 0.16);
      M m145 = M(sdPyramid((q144 + vec3(0.0, 0.045333, 0.0)) / 0.13, 0.697436) * 0.13, vec3(0.008698, 0.098508, 0.009681), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m146 = m145; m146.d = m145.d * 0.16;
      vec3 q147 = q124 - vec3(0.0, 1.0, 0.0);
      M m148 = M(sdBox(q147, vec3(0.55, 1.0, 3.5)), vec3(0.008698, 0.098508, 0.009681), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m149 = mI(m146, m148);
      u125 = mU(u125, m149);
    }
    if (sdBox(q124 - vec3(0.0, 0.053356, 0.031613), vec3(0.56, 0.063356, 3.478387)) < u125.d) {
      vec3 q150 = q124 - vec3(0.034, 0.053356, 0.058);
      vec3 q151 = q150 * mat3(0.965926, 0.0, 0.258819, 0.0, 1.0, 0.0, -0.258819, 0.0, 0.965926);
      vec3 id152 = clamp(round(q151 / vec3(0.166653, 1.0, 0.166653) + vec3(2.5, 0.0, 20.5)), vec3(0.0), vec3(5.0, 0.0, 41.0));
      vec3 q153 = q151 - vec3(0.166653, 1.0, 0.166653) * (id152 - vec3(2.5, 0.0, 20.5));
      vec3 q154 = q153 * mat3(0.029458, 0.0, -0.999566, 0.0, 1.0, 0.0, 0.999566, 0.0, 0.029458);
      vec3 q155 = q154 * mat3(1.0, 0.0, 0.0, 0.0, 0.925323, 0.379181, 0.0, -0.379181, 0.925323);
      vec3 q156 = q155 / vec3(1.0, 1.0, 0.16);
      M m157 = M(sdPyramid((q156 + vec3(0.0, 0.052417, 0.0)) / 0.16, 0.655208) * 0.16, vec3(0.015771, 0.128244, 0.012609), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m158 = m157; m158.d = m157.d * 0.16;
      vec3 q159 = q124 - vec3(0.0, 1.0, 0.0);
      M m160 = M(sdBox(q159, vec3(0.55, 1.0, 3.5)), vec3(0.015771, 0.128244, 0.012609), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m161 = mI(m158, m160);
      u125 = mU(u125, m161);
    }
    if (sdBox(q124 - vec3(0.0, 0.057864, 0.053961), vec3(0.56, 0.067864, 3.456039)) < u125.d) {
      vec3 q162 = q124 - vec3(0.051, 0.057864, 0.087);
      vec3 q163 = q162 * mat3(0.987688, 0.0, 0.156434, 0.0, 1.0, 0.0, -0.156434, 0.0, 0.987688);
      vec3 id164 = clamp(round(q163 / vec3(0.120876, 1.0, 0.120876) + vec3(4.0, 0.0, 28.0)), vec3(0.0), vec3(8.0, 0.0, 56.0));
      vec3 q165 = q163 - vec3(0.120876, 1.0, 0.120876) * (id164 - vec3(4.0, 0.0, 28.0));
      vec3 q166 = q165 * mat3(-0.857895, 0.0, -0.513825, 0.0, 1.0, 0.0, 0.513825, 0.0, -0.857895);
      vec3 q167 = q166 * mat3(1.0, 0.0, 0.0, 0.0, 0.919715, 0.392586, 0.0, -0.392586, 0.919715);
      vec3 q168 = q167 / vec3(1.0, 1.0, 0.16);
      M m169 = M(sdPyramid((q168 + vec3(0.0, 0.0595, 0.0)) / 0.1, 1.19) * 0.1, vec3(0.025396, 0.162647, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m170 = m169; m170.d = m169.d * 0.16;
      vec3 q171 = q124 - vec3(0.0, 1.0, 0.0);
      M m172 = M(sdBox(q171, vec3(0.55, 1.0, 3.5)), vec3(0.025396, 0.162647, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m173 = mI(m170, m172);
      u125 = mU(u125, m173);
    }
    if (sdBox(q124 - vec3(0.0, 0.066887, 0.081406), vec3(0.56, 0.076887, 3.428594)) < u125.d) {
      vec3 q174 = q124 - vec3(0.068, 0.066887, 0.116);
      vec3 q175 = q174 * mat3(0.99863, 0.0, 0.052336, 0.0, 1.0, 0.0, -0.052336, 0.0, 0.99863);
      vec3 id176 = clamp(round(q175 / vec3(0.144172, 1.0, 0.144172) + vec3(3.0, 0.0, 23.5)), vec3(0.0), vec3(6.0, 0.0, 47.0));
      vec3 q177 = q175 - vec3(0.144172, 1.0, 0.144172) * (id176 - vec3(3.0, 0.0, 23.5));
      vec3 q178 = q177 * mat3(-0.968407, 0.0, 0.249375, 0.0, 1.0, 0.0, -0.249375, 0.0, -0.968407);
      vec3 q179 = q178 * mat3(1.0, 0.0, 0.0, 0.0, 0.961798, 0.27376, 0.0, -0.27376, 0.961798);
      vec3 q180 = q179 / vec3(1.0, 1.0, 0.16);
      M m181 = M(sdPyramid((q180 + vec3(0.0, 0.066583, 0.0)) / 0.13, 1.024359) * 0.13, vec3(0.037785, 0.201907, 0.019863), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m182 = m181; m182.d = m181.d * 0.16;
      vec3 q183 = q124 - vec3(0.0, 1.0, 0.0);
      M m184 = M(sdBox(q183, vec3(0.55, 1.0, 3.5)), vec3(0.037785, 0.201907, 0.019863), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m185 = mI(m182, m184);
      u125 = mU(u125, m185);
    }
    if (sdBox(q124 - vec3(0.0, 0.07471, 0.086675), vec3(0.56, 0.08471, 3.423325)) < u125.d) {
      vec3 q186 = q124 - vec3(0.085, 0.07471, 0.145);
      vec3 q187 = q186 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
      vec3 id188 = clamp(round(q187 / vec3(0.164452, 1.0, 0.164452) + vec3(2.5, 0.0, 20.5)), vec3(0.0), vec3(5.0, 0.0, 41.0));
      vec3 q189 = q187 - vec3(0.164452, 1.0, 0.164452) * (id188 - vec3(2.5, 0.0, 20.5));
      vec3 q190 = q189 * mat3(-0.628809, 0.0, 0.77756, 0.0, 1.0, 0.0, -0.77756, 0.0, -0.628809);
      vec3 q191 = q190 * mat3(1.0, 0.0, 0.0, 0.0, 0.977561, 0.210653, 0.0, -0.210653, 0.977561);
      vec3 q192 = q191 / vec3(1.0, 1.0, 0.16);
      M m193 = M(sdPyramid((q192 + vec3(0.0, 0.073667, 0.0)) / 0.16, 0.920833) * 0.16, vec3(0.053129, 0.246201, 0.024225), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m194 = m193; m194.d = m193.d * 0.16;
      vec3 q195 = q124 - vec3(0.0, 1.0, 0.0);
      M m196 = M(sdBox(q195, vec3(0.55, 1.0, 3.5)), vec3(0.053129, 0.246201, 0.024225), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m197 = mI(m194, m196);
      u125 = mU(u125, m197);
    }
    if (sdBox(q124 - vec3(0.0, 0.078575, 0.086162), vec3(0.56, 0.088575, 3.423838)) < u125.d) {
      vec3 q198 = q124 - vec3(0.102, 0.078575, 0.174);
      vec3 q199 = q198 * mat3(0.987688, 0.0, -0.156434, 0.0, 1.0, 0.0, 0.156434, 0.0, 0.987688);
      vec3 id200 = clamp(round(q199 / vec3(0.106612, 1.0, 0.106612) + vec3(4.5, 0.0, 32.0)), vec3(0.0), vec3(9.0, 0.0, 64.0));
      vec3 q201 = q199 - vec3(0.106612, 1.0, 0.106612) * (id200 - vec3(4.5, 0.0, 32.0));
      vec3 q202 = q201 * mat3(-0.051583, 0.0, 0.998669, 0.0, 1.0, 0.0, -0.998669, 0.0, -0.051583);
      vec3 q203 = q202 * mat3(1.0, 0.0, 0.0, 0.0, 0.938987, 0.343951, 0.0, -0.343951, 0.938987);
      vec3 q204 = q203 / vec3(1.0, 1.0, 0.16);
      M m205 = M(sdPyramid((q204 + vec3(0.0, 0.08075, 0.0)) / 0.1, 1.615) * 0.1, vec3(0.071599, 0.2957, 0.029101), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m206 = m205; m206.d = m205.d * 0.16;
      vec3 q207 = q124 - vec3(0.0, 1.0, 0.0);
      M m208 = M(sdBox(q207, vec3(0.55, 1.0, 3.5)), vec3(0.071599, 0.2957, 0.029101), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m209 = mI(m206, m208);
      u125 = mU(u125, m209);
    }
    if (sdBox(q124 - vec3(0.0, 0.088294, 0.11775), vec3(0.56, 0.098294, 3.39225)) < u125.d) {
      vec3 q210 = q124 - vec3(0.119, 0.088294, 0.203);
      vec3 q211 = q210 * mat3(0.965926, 0.0, -0.258819, 0.0, 1.0, 0.0, 0.258819, 0.0, 0.965926);
      vec3 id212 = clamp(round(q211 / vec3(0.141729, 1.0, 0.141729) + vec3(3.0, 0.0, 24.0)), vec3(0.0), vec3(6.0, 0.0, 48.0));
      vec3 q213 = q211 - vec3(0.141729, 1.0, 0.141729) * (id212 - vec3(3.0, 0.0, 24.0));
      vec3 q214 = q213 * mat3(0.851263, 0.0, 0.52474, 0.0, 1.0, 0.0, -0.52474, 0.0, 0.851263);
      vec3 q215 = q214 * mat3(1.0, 0.0, 0.0, 0.0, 0.984451, 0.175659, 0.0, -0.175659, 0.984451);
      vec3 q216 = q215 / vec3(1.0, 1.0, 0.16);
      M m217 = M(sdPyramid((q216 + vec3(0.0, 0.087833, 0.0)) / 0.13, 1.351282) * 0.13, vec3(0.093357, 0.350564, 0.034506), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m218 = m217; m218.d = m217.d * 0.16;
      vec3 q219 = q124 - vec3(0.0, 1.0, 0.0);
      M m220 = M(sdBox(q219, vec3(0.55, 1.0, 3.5)), vec3(0.093357, 0.350564, 0.034506), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m221 = mI(m218, m220);
      u125 = mU(u125, m221);
    }
    if (sdBox(q124 - vec3(0.0, 0.092766, 0.171516), vec3(0.56, 0.102766, 3.338484)) < u125.d) {
      vec3 q222 = q124 - vec3(0.136, 0.092766, 0.232);
      vec3 q223 = q222 * mat3(0.93358, 0.0, -0.358368, 0.0, 1.0, 0.0, 0.358368, 0.0, 0.93358);
      vec3 id224 = clamp(round(q223 / vec3(0.187769, 1.0, 0.187769) + vec3(2.0, 0.0, 18.0)), vec3(0.0), vec3(4.0, 0.0, 36.0));
      vec3 q225 = q223 - vec3(0.187769, 1.0, 0.187769) * (id224 - vec3(2.0, 0.0, 18.0));
      vec3 q226 = q225 * mat3(0.945011, 0.0, -0.327039, 0.0, 1.0, 0.0, 0.327039, 0.0, 0.945011);
      vec3 q227 = q226 * mat3(1.0, 0.0, 0.0, 0.0, 0.92664, 0.37595, 0.0, -0.37595, 0.92664);
      vec3 q228 = q227 / vec3(1.0, 1.0, 0.16);
      M m229 = M(sdPyramid((q228 + vec3(0.0, 0.094917, 0.0)) / 0.16, 1.186458) * 0.16, vec3(0.11855, 0.410948, 0.040456), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m230 = m229; m230.d = m229.d * 0.16;
      vec3 q231 = q124 - vec3(0.0, 1.0, 0.0);
      M m232 = M(sdBox(q231, vec3(0.55, 1.0, 3.5)), vec3(0.11855, 0.410948, 0.040456), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m233 = mI(m230, m232);
      u125 = mU(u125, m233);
    }
    if (sdBox(q124 - vec3(0.0, 0.098797, 0.212326), vec3(0.56, 0.108797, 3.297674)) < u125.d) {
      vec3 q234 = q124 - vec3(0.153, 0.098797, 0.261);
      vec3 q235 = q234 * mat3(0.891007, 0.0, -0.45399, 0.0, 1.0, 0.0, 0.45399, 0.0, 0.891007);
      vec3 id236 = clamp(round(q235 / vec3(0.124838, 1.0, 0.124838) + vec3(3.5, 0.0, 27.5)), vec3(0.0), vec3(7.0, 0.0, 55.0));
      vec3 q237 = q235 - vec3(0.124838, 1.0, 0.124838) * (id236 - vec3(3.5, 0.0, 27.5));
      vec3 q238 = q237 * mat3(0.315825, 0.0, -0.948817, 0.0, 1.0, 0.0, 0.948817, 0.0, 0.315825);
      vec3 q239 = q238 * mat3(1.0, 0.0, 0.0, 0.0, 0.942356, 0.334611, 0.0, -0.334611, 0.942356);
      vec3 q240 = q239 / vec3(1.0, 1.0, 0.16);
      M m241 = M(sdPyramid((q240 + vec3(0.0, 0.102, 0.0)) / 0.1, 2.04) * 0.1, vec3(0.147319, 0.477, 0.046964), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m242 = m241; m242.d = m241.d * 0.16;
      vec3 q243 = q124 - vec3(0.0, 1.0, 0.0);
      M m244 = M(sdBox(q243, vec3(0.55, 1.0, 3.5)), vec3(0.147319, 0.477, 0.046964), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m245 = mI(m242, m244);
      u125 = mU(u125, m245);
    }
    u0 = mU(u0, u125);
  }
  if (cullVis(2) && sdBox(p - vec3(0.55, 0.09739, -0.361601), vec3(0.56, 0.10739, 3.471601)) < u0.d) {
    vec3 q246 = p - vec3(0.55, 0.0, -0.4);
    M u247 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q246 - vec3(0.0, 0.038837, 0.0), vec3(0.56, 0.048837, 3.295896)) < u247.d) {
      vec3 q248 = q246 - vec3(0.0, 0.038837, 0.0);
      vec3 q249 = q248 * mat3(0.891007, 0.0, 0.45399, 0.0, 1.0, 0.0, -0.45399, 0.0, 0.891007);
      vec3 id250 = clamp(round(q249 / vec3(0.104628, 1.0, 0.104628) + vec3(4.5, 0.0, 32.5)), vec3(0.0), vec3(9.0, 0.0, 65.0));
      vec3 q251 = q249 - vec3(0.104628, 1.0, 0.104628) * (id250 - vec3(4.5, 0.0, 32.5));
      vec3 q252 = q251 * mat3(0.999084, 0.0, -0.042802, 0.0, 1.0, 0.0, 0.042802, 0.0, 0.999084);
      vec3 q253 = q252 * mat3(1.0, 0.0, 0.0, 0.0, 0.950075, 0.312021, 0.0, -0.312021, 0.950075);
      vec3 q254 = q253 / vec3(1.0, 1.0, 0.16);
      M m255 = M(sdPyramid((q254 + vec3(0.0, 0.03825, 0.0)) / 0.1, 0.765) * 0.1, vec3(0.063724, 0.233022, 0.013412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m256 = m255; m256.d = m255.d * 0.16;
      vec3 q257 = q246 - vec3(0.0, 1.0, 0.0);
      M m258 = M(sdBox(q257, vec3(0.55, 1.0, 3.5)), vec3(0.063724, 0.233022, 0.013412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m259 = mI(m256, m258);
      u247 = mU(u247, m259);
    }
    if (sdBox(q246 - vec3(0.0, 0.046485, 0.029), vec3(0.56, 0.056485, 3.431202)) < u247.d) {
      vec3 q260 = q246 - vec3(0.017, 0.046485, 0.029);
      vec3 q261 = q260 * mat3(0.93358, 0.0, 0.358368, 0.0, 1.0, 0.0, -0.358368, 0.0, 0.93358);
      vec3 id262 = clamp(round(q261 / vec3(0.12423, 1.0, 0.12423) + vec3(3.5, 0.0, 27.5)), vec3(0.0), vec3(7.0, 0.0, 55.0));
      vec3 q263 = q261 - vec3(0.12423, 1.0, 0.12423) * (id262 - vec3(3.5, 0.0, 27.5));
      vec3 q264 = q263 * mat3(0.729341, 0.0, -0.684151, 0.0, 1.0, 0.0, 0.684151, 0.0, 0.729341);
      vec3 q265 = q264 * mat3(1.0, 0.0, 0.0, 0.0, 0.981651, 0.190687, 0.0, -0.190687, 0.981651);
      vec3 q266 = q265 / vec3(1.0, 1.0, 0.16);
      M m267 = M(sdPyramid((q266 + vec3(0.0, 0.045333, 0.0)) / 0.13, 0.697436) * 0.13, vec3(0.092094, 0.276219, 0.019863), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m268 = m267; m268.d = m267.d * 0.16;
      vec3 q269 = q246 - vec3(0.0, 1.0, 0.0);
      M m270 = M(sdBox(q269, vec3(0.55, 1.0, 3.5)), vec3(0.092094, 0.276219, 0.019863), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m271 = mI(m268, m270);
      u247 = mU(u247, m271);
    }
    if (sdBox(q246 - vec3(0.0, 0.053844, 0.038588), vec3(0.56, 0.063844, 3.471412)) < u247.d) {
      vec3 q272 = q246 - vec3(0.034, 0.053844, 0.058);
      vec3 q273 = q272 * mat3(0.965926, 0.0, 0.258819, 0.0, 1.0, 0.0, -0.258819, 0.0, 0.965926);
      vec3 id274 = clamp(round(q273 / vec3(0.173859, 1.0, 0.173859) + vec3(2.5, 0.0, 19.5)), vec3(0.0), vec3(5.0, 0.0, 39.0));
      vec3 q275 = q273 - vec3(0.173859, 1.0, 0.173859) * (id274 - vec3(2.5, 0.0, 19.5));
      vec3 q276 = q275 * mat3(-0.244556, 0.0, -0.969635, 0.0, 1.0, 0.0, 0.969635, 0.0, -0.244556);
      vec3 q277 = q276 * mat3(1.0, 0.0, 0.0, 0.0, 0.954068, 0.299591, 0.0, -0.299591, 0.954068);
      vec3 q278 = q277 / vec3(1.0, 1.0, 0.16);
      M m279 = M(sdPyramid((q278 + vec3(0.0, 0.052417, 0.0)) / 0.16, 0.655208) * 0.16, vec3(0.126724, 0.323759, 0.027833), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m280 = m279; m280.d = m279.d * 0.16;
      vec3 q281 = q246 - vec3(0.0, 1.0, 0.0);
      M m282 = M(sdBox(q281, vec3(0.55, 1.0, 3.5)), vec3(0.126724, 0.323759, 0.027833), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m283 = mI(m280, m282);
      u247 = mU(u247, m283);
    }
    if (sdBox(q246 - vec3(0.0, 0.059433, 0.038399), vec3(0.56, 0.069433, 3.471601)) < u247.d) {
      vec3 q284 = q246 - vec3(0.051, 0.059433, 0.087);
      vec3 q285 = q284 * mat3(0.987688, 0.0, 0.156434, 0.0, 1.0, 0.0, -0.156434, 0.0, 0.987688);
      vec3 id286 = clamp(round(q285 / vec3(0.110484, 1.0, 0.110484) + vec3(4.0, 0.0, 31.0)), vec3(0.0), vec3(8.0, 0.0, 62.0));
      vec3 q287 = q285 - vec3(0.110484, 1.0, 0.110484) * (id286 - vec3(4.0, 0.0, 31.0));
      vec3 q288 = q287 * mat3(-0.765135, 0.0, -0.64387, 0.0, 1.0, 0.0, 0.64387, 0.0, -0.765135);
      vec3 q289 = q288 * mat3(1.0, 0.0, 0.0, 0.0, 0.962304, 0.271975, 0.0, -0.271975, 0.962304);
      vec3 q290 = q289 / vec3(1.0, 1.0, 0.16);
      M m291 = M(sdPyramid((q290 + vec3(0.0, 0.0595, 0.0)) / 0.1, 1.19) * 0.1, vec3(0.167954, 0.375758, 0.037412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m292 = m291; m292.d = m291.d * 0.16;
      vec3 q293 = q246 - vec3(0.0, 1.0, 0.0);
      M m294 = M(sdBox(q293, vec3(0.55, 1.0, 3.5)), vec3(0.167954, 0.375758, 0.037412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m295 = mI(m292, m294);
      u247 = mU(u247, m295);
    }
    if (sdBox(q246 - vec3(0.0, 0.066722, 0.067813), vec3(0.56, 0.076722, 3.442187)) < u247.d) {
      vec3 q296 = q246 - vec3(0.068, 0.066722, 0.116);
      vec3 q297 = q296 * mat3(0.99863, 0.0, 0.052336, 0.0, 1.0, 0.0, -0.052336, 0.0, 0.99863);
      vec3 id298 = clamp(round(q297 / vec3(0.14245, 1.0, 0.14245) + vec3(3.0, 0.0, 24.0)), vec3(0.0), vec3(6.0, 0.0, 48.0));
      vec3 q299 = q297 - vec3(0.14245, 1.0, 0.14245) * (id298 - vec3(3.0, 0.0, 24.0));
      vec3 q300 = q299 * mat3(-0.984422, 0.0, 0.175821, 0.0, 1.0, 0.0, -0.175821, 0.0, -0.984422);
      vec3 q301 = q300 * mat3(1.0, 0.0, 0.0, 0.0, 0.956536, 0.291615, 0.0, -0.291615, 0.956536);
      vec3 q302 = q301 / vec3(1.0, 1.0, 0.16);
      M m303 = M(sdPyramid((q302 + vec3(0.0, 0.066583, 0.0)) / 0.13, 1.024359) * 0.13, vec3(0.216104, 0.432328, 0.04868), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m304 = m303; m304.d = m303.d * 0.16;
      vec3 q305 = q246 - vec3(0.0, 1.0, 0.0);
      M m306 = M(sdBox(q305, vec3(0.55, 1.0, 3.5)), vec3(0.216104, 0.432328, 0.04868), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m307 = mI(m304, m306);
      u247 = mU(u247, m307);
    }
    if (sdBox(q246 - vec3(0.0, 0.073395, 0.077946), vec3(0.56, 0.083395, 3.432054)) < u247.d) {
      vec3 q308 = q246 - vec3(0.085, 0.073395, 0.145);
      vec3 q309 = q308 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
      vec3 id310 = clamp(round(q309 / vec3(0.182583, 1.0, 0.182583) + vec3(2.5, 0.0, 18.5)), vec3(0.0), vec3(5.0, 0.0, 37.0));
      vec3 q311 = q309 - vec3(0.182583, 1.0, 0.182583) * (id310 - vec3(2.5, 0.0, 18.5));
      vec3 q312 = q311 * mat3(-0.412098, 0.0, 0.91114, 0.0, 1.0, 0.0, -0.91114, 0.0, -0.412098);
      vec3 q313 = q312 * mat3(1.0, 0.0, 0.0, 0.0, 0.934421, 0.356169, 0.0, -0.356169, 0.934421);
      vec3 q314 = q313 / vec3(1.0, 1.0, 0.16);
      M m315 = M(sdPyramid((q314 + vec3(0.0, 0.073667, 0.0)) / 0.16, 0.920833) * 0.16, vec3(0.27147, 0.493578, 0.061714), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m316 = m315; m316.d = m315.d * 0.16;
      vec3 q317 = q246 - vec3(0.0, 1.0, 0.0);
      M m318 = M(sdBox(q317, vec3(0.55, 1.0, 3.5)), vec3(0.27147, 0.493578, 0.061714), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m319 = mI(m316, m318);
      u247 = mU(u247, m319);
    }
    if (sdBox(q246 - vec3(0.0, 0.078855, 0.085265), vec3(0.56, 0.088855, 3.424735)) < u247.d) {
      vec3 q320 = q246 - vec3(0.102, 0.078855, 0.174);
      vec3 q321 = q320 * mat3(0.987688, 0.0, -0.156434, 0.0, 1.0, 0.0, 0.156434, 0.0, 0.987688);
      vec3 id322 = clamp(round(q321 / vec3(0.111979, 1.0, 0.111979) + vec3(4.0, 0.0, 30.5)), vec3(0.0), vec3(8.0, 0.0, 61.0));
      vec3 q323 = q321 - vec3(0.111979, 1.0, 0.111979) * (id322 - vec3(4.0, 0.0, 30.5));
      vec3 q324 = q323 * mat3(0.142088, 0.0, 0.989854, 0.0, 1.0, 0.0, -0.989854, 0.0, 0.142088);
      vec3 q325 = q324 * mat3(1.0, 0.0, 0.0, 0.0, 0.943775, 0.330587, 0.0, -0.330587, 0.943775);
      vec3 q326 = q325 / vec3(1.0, 1.0, 0.16);
      M m327 = M(sdPyramid((q326 + vec3(0.0, 0.08075, 0.0)) / 0.1, 1.615) * 0.1, vec3(0.334332, 0.559611, 0.076583), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m328 = m327; m328.d = m327.d * 0.16;
      vec3 q329 = q246 - vec3(0.0, 1.0, 0.0);
      M m330 = M(sdBox(q329, vec3(0.55, 1.0, 3.5)), vec3(0.334332, 0.559611, 0.076583), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m331 = mI(m328, m330);
      u247 = mU(u247, m331);
    }
    if (sdBox(q246 - vec3(0.0, 0.086217, 0.135227), vec3(0.56, 0.096217, 3.374773)) < u247.d) {
      vec3 q332 = q246 - vec3(0.119, 0.086217, 0.203);
      vec3 q333 = q332 * mat3(0.965926, 0.0, -0.258819, 0.0, 1.0, 0.0, 0.258819, 0.0, 0.965926);
      vec3 id334 = clamp(round(q333 / vec3(0.155591, 1.0, 0.155591) + vec3(3.0, 0.0, 21.5)), vec3(0.0), vec3(6.0, 0.0, 43.0));
      vec3 q335 = q333 - vec3(0.155591, 1.0, 0.155591) * (id334 - vec3(3.0, 0.0, 21.5));
      vec3 q336 = q335 * mat3(0.906275, 0.0, 0.42269, 0.0, 1.0, 0.0, -0.42269, 0.0, 0.906275);
      vec3 q337 = q336 * mat3(1.0, 0.0, 0.0, 0.0, 0.941791, 0.336198, 0.0, -0.336198, 0.941791);
      vec3 q338 = q337 / vec3(1.0, 1.0, 0.16);
      M m339 = M(sdPyramid((q338 + vec3(0.0, 0.087833, 0.0)) / 0.13, 1.351282) * 0.13, vec3(0.404955, 0.63053, 0.093357), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m340 = m339; m340.d = m339.d * 0.16;
      vec3 q341 = q246 - vec3(0.0, 1.0, 0.0);
      M m342 = M(sdBox(q341, vec3(0.55, 1.0, 3.5)), vec3(0.404955, 0.63053, 0.093357), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m343 = mI(m340, m342);
      u247 = mU(u247, m343);
    }
    if (sdBox(q246 - vec3(0.0, 0.094636, 0.152261), vec3(0.56, 0.104636, 3.357739)) < u247.d) {
      vec3 q344 = q246 - vec3(0.136, 0.094636, 0.232);
      vec3 q345 = q344 * mat3(0.93358, 0.0, -0.358368, 0.0, 1.0, 0.0, 0.358368, 0.0, 0.93358);
      vec3 id346 = clamp(round(q345 / vec3(0.183091, 1.0, 0.183091) + vec3(2.5, 0.0, 18.5)), vec3(0.0), vec3(5.0, 0.0, 37.0));
      vec3 q347 = q345 - vec3(0.183091, 1.0, 0.183091) * (id346 - vec3(2.5, 0.0, 18.5));
      vec3 q348 = q347 * mat3(0.86283, 0.0, -0.505494, 0.0, 1.0, 0.0, 0.505494, 0.0, 0.86283);
      vec3 q349 = q348 * mat3(1.0, 0.0, 0.0, 0.0, 0.95868, 0.284486, 0.0, -0.284486, 0.95868);
      vec3 q350 = q349 / vec3(1.0, 1.0, 0.16);
      M m351 = M(sdPyramid((q350 + vec3(0.0, 0.094917, 0.0)) / 0.16, 1.186458) * 0.16, vec3(0.483591, 0.706432, 0.112098), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m352 = m351; m352.d = m351.d * 0.16;
      vec3 q353 = q246 - vec3(0.0, 1.0, 0.0);
      M m354 = M(sdBox(q353, vec3(0.55, 1.0, 3.5)), vec3(0.483591, 0.706432, 0.112098), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m355 = mI(m352, m354);
      u247 = mU(u247, m355);
    }
    if (sdBox(q246 - vec3(0.0, 0.09739, 0.230927), vec3(0.56, 0.10739, 3.279073)) < u247.d) {
      vec3 q356 = q246 - vec3(0.153, 0.09739, 0.261);
      vec3 q357 = q356 * mat3(0.891007, 0.0, -0.45399, 0.0, 1.0, 0.0, 0.45399, 0.0, 0.891007);
      vec3 id358 = clamp(round(q357 / vec3(0.129887, 1.0, 0.129887) + vec3(3.5, 0.0, 26.0)), vec3(0.0), vec3(7.0, 0.0, 52.0));
      vec3 q359 = q357 - vec3(0.129887, 1.0, 0.129887) * (id358 - vec3(3.5, 0.0, 26.0));
      vec3 q360 = q359 * mat3(0.352193, 0.0, -0.935928, 0.0, 1.0, 0.0, 0.935928, 0.0, 0.352193);
      vec3 q361 = q360 * mat3(1.0, 0.0, 0.0, 0.0, 0.925008, 0.379948, 0.0, -0.379948, 0.925008);
      vec3 q362 = q361 / vec3(1.0, 1.0, 0.16);
      M m363 = M(sdPyramid((q362 + vec3(0.0, 0.102, 0.0)) / 0.1, 2.04) * 0.1, vec3(0.570482, 0.787412, 0.132868), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m364 = m363; m364.d = m363.d * 0.16;
      vec3 q365 = q246 - vec3(0.0, 1.0, 0.0);
      M m366 = M(sdBox(q365, vec3(0.55, 1.0, 3.5)), vec3(0.570482, 0.787412, 0.132868), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m367 = mI(m364, m366);
      u247 = mU(u247, m367);
    }
    u0 = mU(u0, u247);
  }
  if (cullVis(3) && sdBox(p - vec3(1.65, 0.098338, -0.349642), vec3(0.56, 0.108338, 3.459642)) < u0.d) {
    vec3 q368 = p - vec3(1.65, 0.0, -0.4);
    M u369 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q368 - vec3(0.0, 0.038728, 0.0), vec3(0.56, 0.048728, 3.323477)) < u369.d) {
      vec3 q370 = q368 - vec3(0.0, 0.038728, 0.0);
      vec3 q371 = q370 * mat3(0.891007, 0.0, 0.45399, 0.0, 1.0, 0.0, -0.45399, 0.0, 0.891007);
      vec3 id372 = clamp(round(q371 / vec3(0.109938, 1.0, 0.109938) + vec3(4.5, 0.0, 31.0)), vec3(0.0), vec3(9.0, 0.0, 62.0));
      vec3 q373 = q371 - vec3(0.109938, 1.0, 0.109938) * (id372 - vec3(4.5, 0.0, 31.0));
      vec3 q374 = q373 * mat3(0.972049, 0.0, -0.234776, 0.0, 1.0, 0.0, 0.234776, 0.0, 0.972049);
      vec3 q375 = q374 * mat3(1.0, 0.0, 0.0, 0.0, 0.94276, 0.333473, 0.0, -0.333473, 0.94276);
      vec3 q376 = q375 / vec3(1.0, 1.0, 0.16);
      M m377 = M(sdPyramid((q376 + vec3(0.0, 0.03825, 0.0)) / 0.1, 0.765) * 0.1, vec3(0.054972, 0.106539, 0.004896), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m378 = m377; m378.d = m377.d * 0.16;
      vec3 q379 = q368 - vec3(0.0, 1.0, 0.0);
      M m380 = M(sdBox(q379, vec3(0.55, 1.0, 3.5)), vec3(0.054972, 0.106539, 0.004896), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m381 = mI(m378, m380);
      u369 = mU(u369, m381);
    }
    if (sdBox(q368 - vec3(0.0, 0.046082, 0.029), vec3(0.56, 0.056082, 3.395244)) < u369.d) {
      vec3 q382 = q368 - vec3(0.017, 0.046082, 0.029);
      vec3 q383 = q382 * mat3(0.93358, 0.0, 0.358368, 0.0, 1.0, 0.0, -0.358368, 0.0, 0.93358);
      vec3 id384 = clamp(round(q383 / vec3(0.14084, 1.0, 0.14084) + vec3(3.0, 0.0, 24.0)), vec3(0.0), vec3(6.0, 0.0, 48.0));
      vec3 q385 = q383 - vec3(0.14084, 1.0, 0.14084) * (id384 - vec3(3.0, 0.0, 24.0));
      vec3 q386 = q385 * mat3(0.831889, 0.0, -0.554941, 0.0, 1.0, 0.0, 0.554941, 0.0, 0.831889);
      vec3 q387 = q386 * mat3(1.0, 0.0, 0.0, 0.0, 0.935368, 0.353677, 0.0, -0.353677, 0.935368);
      vec3 q388 = q387 / vec3(1.0, 1.0, 0.16);
      M m389 = M(sdPyramid((q388 + vec3(0.0, 0.045333, 0.0)) / 0.13, 0.697436) * 0.13, vec3(0.080015, 0.134431, 0.006913), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m390 = m389; m390.d = m389.d * 0.16;
      vec3 q391 = q368 - vec3(0.0, 1.0, 0.0);
      M m392 = M(sdBox(q391, vec3(0.55, 1.0, 3.5)), vec3(0.080015, 0.134431, 0.006913), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m393 = mI(m390, m392);
      u369 = mU(u369, m393);
    }
    if (sdBox(q368 - vec3(0.0, 0.053893, 0.055781), vec3(0.56, 0.063893, 3.454219)) < u369.d) {
      vec3 q394 = q368 - vec3(0.034, 0.053893, 0.058);
      vec3 q395 = q394 * mat3(0.965926, 0.0, 0.258819, 0.0, 1.0, 0.0, -0.258819, 0.0, 0.965926);
      vec3 id396 = clamp(round(q395 / vec3(0.168284, 1.0, 0.168284) + vec3(2.5, 0.0, 20.0)), vec3(0.0), vec3(5.0, 0.0, 40.0));
      vec3 q397 = q395 - vec3(0.168284, 1.0, 0.168284) * (id396 - vec3(2.5, 0.0, 20.0));
      vec3 q398 = q397 * mat3(-0.089377, 0.0, -0.995998, 0.0, 1.0, 0.0, 0.995998, 0.0, -0.089377);
      vec3 q399 = q398 * mat3(1.0, 0.0, 0.0, 0.0, 0.981872, 0.189543, 0.0, -0.189543, 0.981872);
      vec3 q400 = q399 / vec3(1.0, 1.0, 0.16);
      M m401 = M(sdPyramid((q400 + vec3(0.0, 0.052417, 0.0)) / 0.16, 0.655208) * 0.16, vec3(0.110693, 0.166174, 0.009347), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m402 = m401; m402.d = m401.d * 0.16;
      vec3 q403 = q368 - vec3(0.0, 1.0, 0.0);
      M m404 = M(sdBox(q403, vec3(0.55, 1.0, 3.5)), vec3(0.110693, 0.166174, 0.009347), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m405 = mI(m402, m404);
      u369 = mU(u369, m405);
    }
    if (sdBox(q368 - vec3(0.0, 0.058134, 0.050358), vec3(0.56, 0.068134, 3.459642)) < u369.d) {
      vec3 q406 = q368 - vec3(0.051, 0.058134, 0.087);
      vec3 q407 = q406 * mat3(0.987688, 0.0, 0.156434, 0.0, 1.0, 0.0, -0.156434, 0.0, 0.987688);
      vec3 id408 = clamp(round(q407 / vec3(0.116917, 1.0, 0.116917) + vec3(4.0, 0.0, 29.0)), vec3(0.0), vec3(8.0, 0.0, 58.0));
      vec3 q409 = q407 - vec3(0.116917, 1.0, 0.116917) * (id408 - vec3(4.0, 0.0, 29.0));
      vec3 q410 = q409 * mat3(-0.723507, 0.0, -0.690317, 0.0, 1.0, 0.0, 0.690317, 0.0, -0.723507);
      vec3 q411 = q410 * mat3(1.0, 0.0, 0.0, 0.0, 0.926416, 0.3765, 0.0, -0.3765, 0.926416);
      vec3 q412 = q411 / vec3(1.0, 1.0, 0.16);
      M m413 = M(sdPyramid((q412 + vec3(0.0, 0.0595, 0.0)) / 0.1, 1.19) * 0.1, vec3(0.147319, 0.201907, 0.012218), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m414 = m413; m414.d = m413.d * 0.16;
      vec3 q415 = q368 - vec3(0.0, 1.0, 0.0);
      M m416 = M(sdBox(q415, vec3(0.55, 1.0, 3.5)), vec3(0.147319, 0.201907, 0.012218), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m417 = mI(m414, m416);
      u369 = mU(u369, m417);
    }
    if (sdBox(q368 - vec3(0.0, 0.066618, 0.084328), vec3(0.56, 0.076618, 3.425672)) < u369.d) {
      vec3 q418 = q368 - vec3(0.068, 0.066618, 0.116);
      vec3 q419 = q418 * mat3(0.99863, 0.0, 0.052336, 0.0, 1.0, 0.0, -0.052336, 0.0, 0.99863);
      vec3 id420 = clamp(round(q419 / vec3(0.135673, 1.0, 0.135673) + vec3(3.5, 0.0, 25.0)), vec3(0.0), vec3(7.0, 0.0, 50.0));
      vec3 q421 = q419 - vec3(0.135673, 1.0, 0.135673) * (id420 - vec3(3.5, 0.0, 25.0));
      vec3 q422 = q421 * mat3(-0.999561, 0.0, 0.02963, 0.0, 1.0, 0.0, -0.02963, 0.0, -0.999561);
      vec3 q423 = q422 * mat3(1.0, 0.0, 0.0, 0.0, 0.953387, 0.30175, 0.0, -0.30175, 0.953387);
      vec3 q424 = q423 / vec3(1.0, 1.0, 0.16);
      M m425 = M(sdPyramid((q424 + vec3(0.0, 0.066583, 0.0)) / 0.13, 1.024359) * 0.13, vec3(0.190184, 0.241761, 0.015547), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m426 = m425; m426.d = m425.d * 0.16;
      vec3 q427 = q368 - vec3(0.0, 1.0, 0.0);
      M m428 = M(sdBox(q427, vec3(0.55, 1.0, 3.5)), vec3(0.190184, 0.241761, 0.015547), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m429 = mI(m426, m428);
      u369 = mU(u369, m429);
    }
    if (sdBox(q368 - vec3(0.0, 0.074271, 0.104734), vec3(0.56, 0.084271, 3.405266)) < u369.d) {
      vec3 q430 = q368 - vec3(0.085, 0.074271, 0.145);
      vec3 q431 = q430 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
      vec3 id432 = clamp(round(q431 / vec3(0.175184, 1.0, 0.175184) + vec3(2.5, 0.0, 19.0)), vec3(0.0), vec3(5.0, 0.0, 38.0));
      vec3 q433 = q431 - vec3(0.175184, 1.0, 0.175184) * (id432 - vec3(2.5, 0.0, 19.0));
      vec3 q434 = q433 * mat3(-0.551074, 0.0, 0.834457, 0.0, 1.0, 0.0, -0.834457, 0.0, -0.551074);
      vec3 q435 = q434 * mat3(1.0, 0.0, 0.0, 0.0, 0.958889, 0.283783, 0.0, -0.283783, 0.958889);
      vec3 q436 = q435 / vec3(1.0, 1.0, 0.16);
      M m437 = M(sdPyramid((q436 + vec3(0.0, 0.073667, 0.0)) / 0.16, 0.920833) * 0.16, vec3(0.239559, 0.285863, 0.019353), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m438 = m437; m438.d = m437.d * 0.16;
      vec3 q439 = q368 - vec3(0.0, 1.0, 0.0);
      M m440 = M(sdBox(q439, vec3(0.55, 1.0, 3.5)), vec3(0.239559, 0.285863, 0.019353), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m441 = mI(m438, m440);
      u369 = mU(u369, m441);
    }
    if (sdBox(q368 - vec3(0.0, 0.079243, 0.0846), vec3(0.56, 0.089243, 3.4254)) < u369.d) {
      vec3 q442 = q368 - vec3(0.102, 0.079243, 0.174);
      vec3 q443 = q442 * mat3(0.987688, 0.0, -0.156434, 0.0, 1.0, 0.0, 0.156434, 0.0, 0.987688);
      vec3 id444 = clamp(round(q443 / vec3(0.112027, 1.0, 0.112027) + vec3(4.0, 0.0, 30.5)), vec3(0.0), vec3(8.0, 0.0, 61.0));
      vec3 q445 = q443 - vec3(0.112027, 1.0, 0.112027) * (id444 - vec3(4.0, 0.0, 30.5));
      vec3 q446 = q445 * mat3(0.151834, 0.0, 0.988406, 0.0, 1.0, 0.0, -0.988406, 0.0, 0.151834);
      vec3 q447 = q446 * mat3(1.0, 0.0, 0.0, 0.0, 0.950572, 0.310504, 0.0, -0.310504, 0.950572);
      vec3 q448 = q447 / vec3(1.0, 1.0, 0.16);
      M m449 = M(sdPyramid((q448 + vec3(0.0, 0.08075, 0.0)) / 0.1, 1.615) * 0.1, vec3(0.2957, 0.334332, 0.023652), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m450 = m449; m450.d = m449.d * 0.16;
      vec3 q451 = q368 - vec3(0.0, 1.0, 0.0);
      M m452 = M(sdBox(q451, vec3(0.55, 1.0, 3.5)), vec3(0.2957, 0.334332, 0.023652), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m453 = mI(m450, m452);
      u369 = mU(u369, m453);
    }
    if (sdBox(q368 - vec3(0.0, 0.085881, 0.12554), vec3(0.56, 0.095881, 3.38446)) < u369.d) {
      vec3 q454 = q368 - vec3(0.119, 0.085881, 0.203);
      vec3 q455 = q454 * mat3(0.965926, 0.0, -0.258819, 0.0, 1.0, 0.0, 0.258819, 0.0, 0.965926);
      vec3 id456 = clamp(round(q455 / vec3(0.156034, 1.0, 0.156034) + vec3(3.0, 0.0, 21.5)), vec3(0.0), vec3(6.0, 0.0, 43.0));
      vec3 q457 = q455 - vec3(0.156034, 1.0, 0.156034) * (id456 - vec3(3.0, 0.0, 21.5));
      vec3 q458 = q457 * mat3(0.75688, 0.0, 0.653554, 0.0, 1.0, 0.0, -0.653554, 0.0, 0.75688);
      vec3 q459 = q458 * mat3(1.0, 0.0, 0.0, 0.0, 0.93614, 0.351628, 0.0, -0.351628, 0.93614);
      vec3 q460 = q459 / vec3(1.0, 1.0, 0.16);
      M m461 = M(sdPyramid((q460 + vec3(0.0, 0.087833, 0.0)) / 0.13, 1.351282) * 0.13, vec3(0.358849, 0.387284, 0.028463), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m462 = m461; m462.d = m461.d * 0.16;
      vec3 q463 = q368 - vec3(0.0, 1.0, 0.0);
      M m464 = M(sdBox(q463, vec3(0.55, 1.0, 3.5)), vec3(0.358849, 0.387284, 0.028463), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m465 = mI(m462, m464);
      u369 = mU(u369, m465);
    }
    if (sdBox(q368 - vec3(0.0, 0.092222, 0.196208), vec3(0.56, 0.102222, 3.313792)) < u369.d) {
      vec3 q466 = q368 - vec3(0.136, 0.092222, 0.232);
      vec3 q467 = q466 * mat3(0.93358, 0.0, -0.358368, 0.0, 1.0, 0.0, 0.358368, 0.0, 0.93358);
      vec3 id468 = clamp(round(q467 / vec3(0.18983, 1.0, 0.18983) + vec3(2.0, 0.0, 17.5)), vec3(0.0), vec3(4.0, 0.0, 35.0));
      vec3 q469 = q467 - vec3(0.18983, 1.0, 0.18983) * (id468 - vec3(2.0, 0.0, 17.5));
      vec3 q470 = q469 * mat3(0.937936, 0.0, -0.346809, 0.0, 1.0, 0.0, 0.346809, 0.0, 0.937936);
      vec3 q471 = q470 * mat3(1.0, 0.0, 0.0, 0.0, 0.918193, 0.396132, 0.0, -0.396132, 0.918193);
      vec3 q472 = q471 / vec3(1.0, 1.0, 0.16);
      M m473 = M(sdPyramid((q472 + vec3(0.0, 0.094917, 0.0)) / 0.16, 1.186458) * 0.16, vec3(0.429235, 0.44483, 0.033801), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m474 = m473; m474.d = m473.d * 0.16;
      vec3 q475 = q368 - vec3(0.0, 1.0, 0.0);
      M m476 = M(sdBox(q475, vec3(0.55, 1.0, 3.5)), vec3(0.429235, 0.44483, 0.033801), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m477 = mI(m474, m476);
      u369 = mU(u369, m477);
    }
    if (sdBox(q368 - vec3(0.0, 0.098338, 0.220762), vec3(0.56, 0.108338, 3.289238)) < u369.d) {
      vec3 q478 = q368 - vec3(0.153, 0.098338, 0.261);
      vec3 q479 = q478 * mat3(0.891007, 0.0, -0.45399, 0.0, 1.0, 0.0, 0.45399, 0.0, 0.891007);
      vec3 id480 = clamp(round(q479 / vec3(0.126293, 1.0, 0.126293) + vec3(3.5, 0.0, 27.0)), vec3(0.0), vec3(7.0, 0.0, 54.0));
      vec3 q481 = q479 - vec3(0.126293, 1.0, 0.126293) * (id480 - vec3(3.5, 0.0, 27.0));
      vec3 q482 = q481 * mat3(0.323927, 0.0, -0.946082, 0.0, 1.0, 0.0, 0.946082, 0.0, 0.323927);
      vec3 q483 = q482 * mat3(1.0, 0.0, 0.0, 0.0, 0.936616, 0.350359, 0.0, -0.350359, 0.936616);
      vec3 q484 = q483 / vec3(1.0, 1.0, 0.16);
      M m485 = M(sdPyramid((q484 + vec3(0.0, 0.102, 0.0)) / 0.1, 2.04) * 0.1, vec3(0.507079, 0.507079, 0.039682), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m486 = m485; m486.d = m485.d * 0.16;
      vec3 q487 = q368 - vec3(0.0, 1.0, 0.0);
      M m488 = M(sdBox(q487, vec3(0.55, 1.0, 3.5)), vec3(0.507079, 0.507079, 0.039682), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m489 = mI(m486, m488);
      u369 = mU(u369, m489);
    }
    u0 = mU(u0, u369);
  }
  return u0;
}
