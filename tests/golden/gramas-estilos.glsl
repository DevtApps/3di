
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
    M m1 = M(p.y, vec3(0.026241, 0.017642, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  if (cullVis(0) && sdBox(p - vec3(-1.12, 0.093325, -0.56), vec3(0.51, 0.143325, 0.51)) < u0.d) {
    vec3 q2 = p - vec3(-1.12, 0.0, -0.56);
    M u3 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q2 - vec3(0.0, 0.113325, 0.0), vec3(0.51, 0.123325, 0.51)) < u3.d) {
      M u4 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q2 - vec3(0.0, 0.047094, 0.0), vec3(0.51, 0.057094, 0.51)) < u4.d) {
        vec3 q5 = q2 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q6 = q5 - vec3(-0.001864, 0.043402, 0.009947);
        vec3 id7 = clamp(round(q6 / vec3(0.148968, 1.0, 0.148968) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q8 = q6 - vec3(0.148968, 1.0, 0.148968) * (id7 - vec3(3.5, 0.0, 3.5));
        vec3 q9 = q8 - vec3(0.001864, -0.043402, -0.009947);
        vec3 q10 = q9 * mat3(0.982891, 0.0, 0.18419, 0.0, 1.0, 0.0, -0.18419, 0.0, 0.982891);
        vec3 q11 = q10 * mat3(1.0, 0.0, 0.0, 0.0, 0.973874, 0.22709, 0.0, -0.22709, 0.973874);
        vec3 q12 = q11 - vec3(0.0, 0.044566, 0.0);
        vec3 q13 = q12 / vec3(1.0, 1.0, 0.5);
        M m14 = M(sdPyramid((q13 + vec3(0.0, 0.044566, 0.0)) / 0.13007, 0.685263) * 0.13007, vec3(0.04145, 0.195228, 0.018532), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m15 = m14; m15.d = m14.d * 0.5;
        vec3 q16 = q2 - vec3(0.0, 2.0, 0.0);
        M m17 = M(sdBox(q16, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m18 = mI(m15, m17);
        u4 = mU(u4, m18);
      }
      if (sdBox(q2 - vec3(0.0, 0.064879, 0.0), vec3(0.51, 0.074879, 0.51)) < u4.d) {
        vec3 q19 = q2 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q20 = q19 - vec3(0.033982, 0.05833, 0.046435);
        vec3 id21 = clamp(round(q20 / vec3(0.182223, 1.0, 0.182223) + vec3(2.5, 0.0, 2.5)), vec3(0.0), vec3(5.0, 0.0, 5.0));
        vec3 q22 = q20 - vec3(0.182223, 1.0, 0.182223) * (id21 - vec3(2.5, 0.0, 2.5));
        vec3 q23 = q22 - vec3(-0.016982, -0.05833, -0.017435);
        vec3 q24 = q23 * mat3(0.716349, 0.0, -0.697742, 0.0, 1.0, 0.0, 0.697742, 0.0, 0.716349);
        vec3 q25 = q24 * mat3(1.0, 0.0, 0.0, 0.0, 0.922888, 0.385069, 0.0, -0.385069, 0.922888);
        vec3 q26 = q25 - vec3(0.0, 0.063204, 0.0);
        vec3 q27 = q26 / vec3(1.0, 1.0, 0.5);
        M m28 = M(sdPyramid((q27 + vec3(0.0, 0.063204, 0.0)) / 0.136039, 0.929212) * 0.136039, vec3(0.070882, 0.278702, 0.025932), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m29 = m28; m29.d = m28.d * 0.5;
        vec3 q30 = q2 - vec3(0.0, 2.0, 0.0);
        M m31 = M(sdBox(q30, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m32 = mI(m29, m31);
        u4 = mU(u4, m32);
      }
      if (sdBox(q2 - vec3(0.024567, 0.084979, 0.019376), vec3(0.485433, 0.094979, 0.490624)) < u4.d) {
        vec3 q33 = q2 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q34 = q33 - vec3(0.054342, 0.079335, 0.060991);
        vec3 id35 = clamp(round(q34 / vec3(0.204558, 1.0, 0.204558) + vec3(2.0, 0.0, 2.0)), vec3(0.0), vec3(4.0, 0.0, 4.0));
        vec3 q36 = q34 - vec3(0.204558, 1.0, 0.204558) * (id35 - vec3(2.0, 0.0, 2.0));
        vec3 q37 = q36 - vec3(-0.020342, -0.079335, -0.002991);
        vec3 q38 = q37 * mat3(0.14548, 0.0, -0.989361, 0.0, 1.0, 0.0, 0.989361, 0.0, 0.14548);
        vec3 q39 = q38 * mat3(1.0, 0.0, 0.0, 0.0, 0.968019, 0.250875, 0.0, -0.250875, 0.968019);
        vec3 q40 = q39 - vec3(0.0, 0.081956, 0.0);
        vec3 q41 = q40 / vec3(1.0, 1.0, 0.5);
        M m42 = M(sdPyramid((q41 + vec3(0.0, 0.081956, 0.0)) / 0.179951, 0.910874) * 0.179951, vec3(0.124448, 0.366409, 0.038609), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m43 = m42; m43.d = m42.d * 0.5;
        vec3 q44 = q2 - vec3(0.0, 2.0, 0.0);
        M m45 = M(sdBox(q44, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m46 = mI(m43, m45);
        u4 = mU(u4, m46);
      }
      if (sdBox(q2 - vec3(0.007097, 0.113325, 0.0029), vec3(0.502903, 0.123325, 0.5071)) < u4.d) {
        vec3 q47 = q2 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q48 = q47 - vec3(0.070072, 0.108808, 0.071064);
        vec3 id49 = clamp(round(q48 / vec3(0.215407, 1.0, 0.215407) + vec3(2.0, 0.0, 2.0)), vec3(0.0), vec3(4.0, 0.0, 4.0));
        vec3 q50 = q48 - vec3(0.215407, 1.0, 0.215407) * (id49 - vec3(2.0, 0.0, 2.0));
        vec3 q51 = q50 - vec3(-0.019072, -0.108808, 0.015936);
        vec3 q52 = q51 * mat3(-0.641199, 0.0, -0.767374, 0.0, 1.0, 0.0, 0.767374, 0.0, -0.641199);
        vec3 q53 = q52 * mat3(1.0, 0.0, 0.0, 0.0, 0.974891, 0.222684, 0.0, -0.222684, 0.974891);
        vec3 q54 = q53 - vec3(0.0, 0.111611, 0.0);
        vec3 q55 = q54 / vec3(1.0, 1.0, 0.5);
        M m56 = M(sdPyramid((q55 + vec3(0.0, 0.111611, 0.0)) / 0.162279, 1.37554) * 0.162279, vec3(0.231918, 0.507292, 0.063691), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m57 = m56; m57.d = m56.d * 0.5;
        vec3 q58 = q2 - vec3(0.0, 2.0, 0.0);
        M m59 = M(sdBox(q58, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m60 = mI(m57, m59);
        u4 = mU(u4, m60);
      }
      u3 = mU(u3, u4);
    }
    {
      vec3 q61 = q2 - vec3(0.0, -0.02, 0.0);
      M m62 = M(sdBox(q61, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u3 = mU(u3, m62);
    }
    u0 = mU(u0, u3);
  }
  if (cullVis(1) && sdBox(p - vec3(0.0, 0.085866, -0.56), vec3(0.51, 0.135866, 0.51)) < u0.d) {
    vec3 q63 = p - vec3(0.0, 0.0, -0.56);
    M u64 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q63 - vec3(0.0, 0.105866, 0.0), vec3(0.51, 0.115866, 0.51)) < u64.d) {
      M u65 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q63 - vec3(0.0, 0.046801, 0.0), vec3(0.51, 0.056801, 0.51)) < u65.d) {
        vec3 q66 = q63 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q67 = q66 - vec3(0.00357, 0.045748, 0.013871);
        vec3 id68 = clamp(round(q67 / vec3(0.099632, 1.0, 0.099632) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q69 = q67 - vec3(0.099632, 1.0, 0.099632) * (id68 - vec3(5.5, 0.0, 5.5));
        vec3 q70 = q69 - vec3(-0.00357, -0.045748, -0.013871);
        vec3 q71 = q70 * mat3(0.968446, 0.0, -0.249223, 0.0, 1.0, 0.0, 0.249223, 0.0, 0.968446);
        vec3 q72 = q71 * mat3(1.0, 0.0, 0.0, 0.0, 0.954322, 0.298779, 0.0, -0.298779, 0.954322);
        vec3 q73 = q72 - vec3(0.0, 0.047938, 0.0);
        vec3 q74 = q73 / vec3(1.0, 1.0, 0.16);
        M m75 = M(sdPyramid((q74 + vec3(0.0, 0.047938, 0.0)) / 0.088088, 1.088412) * 0.088088, vec3(0.013152, 0.11344, 0.012541), vec3(0.6, 0.0, 0.0), vec3(0.313988, 0.792768, 0.089811), vec4(7.0, 0.095708, 1.0, 0.0), (q70 - vec3(0.0, -0.002106, 0.0)), 0.0);
        M m76 = m75; m76.d = m75.d * 0.16;
        vec3 q77 = q63 - vec3(0.0, 2.0, 0.0);
        M m78 = M(sdBox(q77, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m79 = mI(m76, m78);
        u65 = mU(u65, m79);
      }
      if (sdBox(q63 - vec3(0.0, 0.053436, 0.0), vec3(0.51, 0.063436, 0.51)) < u65.d) {
        vec3 q80 = q63 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q81 = q80 - vec3(0.024737, 0.05254, 0.03698);
        vec3 id82 = clamp(round(q81 / vec3(0.109155, 1.0, 0.109155) + vec3(5.0, 0.0, 5.0)), vec3(0.0), vec3(10.0, 0.0, 10.0));
        vec3 q83 = q81 - vec3(0.109155, 1.0, 0.109155) * (id82 - vec3(5.0, 0.0, 5.0));
        vec3 q84 = q83 - vec3(-0.007737, -0.05254, -0.00798);
        vec3 q85 = q84 * mat3(0.717976, 0.0, -0.696067, 0.0, 1.0, 0.0, 0.696067, 0.0, 0.717976);
        vec3 q86 = q85 * mat3(1.0, 0.0, 0.0, 0.0, 0.978346, 0.206974, 0.0, -0.206974, 0.978346);
        vec3 q87 = q86 - vec3(0.0, 0.053703, 0.0);
        vec3 q88 = q87 / vec3(1.0, 1.0, 0.16);
        M m89 = M(sdPyramid((q88 + vec3(0.0, 0.053703, 0.0)) / 0.108211, 0.992558) * 0.108211, vec3(0.018136, 0.1012, 0.013033), vec3(0.6, 0.0, 0.0), vec3(0.3747, 0.722302, 0.085426), vec4(7.0, 0.108663, 1.0, 0.0), (q84 - vec3(0.0, -0.001792, 0.0)), 0.0);
        M m90 = m89; m90.d = m89.d * 0.16;
        vec3 q91 = q63 - vec3(0.0, 2.0, 0.0);
        M m92 = M(sdBox(q91, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m93 = mI(m90, m92);
        u65 = mU(u65, m93);
      }
      if (sdBox(q63 - vec3(0.0, 0.058685, 0.0), vec3(0.51, 0.068685, 0.51)) < u65.d) {
        vec3 q94 = q63 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q95 = q94 - vec3(0.044843, 0.05798, 0.057655);
        vec3 id96 = clamp(round(q95 / vec3(0.100878, 1.0, 0.100878) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q97 = q95 - vec3(0.100878, 1.0, 0.100878) * (id96 - vec3(5.5, 0.0, 5.5));
        vec3 q98 = q97 - vec3(-0.010843, -0.05798, 0.000345);
        vec3 q99 = q98 * mat3(-0.031785, 0.0, -0.999495, 0.0, 1.0, 0.0, 0.999495, 0.0, -0.031785);
        vec3 q100 = q99 * mat3(1.0, 0.0, 0.0, 0.0, 0.982941, 0.183921, 0.0, -0.183921, 0.982941);
        vec3 q101 = q100 - vec3(0.0, 0.058986, 0.0);
        vec3 q102 = q101 / vec3(1.0, 1.0, 0.16);
        M m103 = M(sdPyramid((q102 + vec3(0.0, 0.058986, 0.0)) / 0.095877, 1.230444) * 0.095877, vec3(0.007507, 0.083599, 0.005559), vec3(0.6, 0.0, 0.0), vec3(0.302569, 0.657537, 0.057741), vec4(7.0, 0.11878, 1.0, 0.0), (q98 - vec3(0.0, -0.001411, 0.0)), 0.0);
        M m104 = m103; m104.d = m103.d * 0.16;
        vec3 q105 = q63 - vec3(0.0, 2.0, 0.0);
        M m106 = M(sdBox(q105, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m107 = mI(m104, m106);
        u65 = mU(u65, m107);
      }
      if (sdBox(q63 - vec3(0.0, 0.06953, 0.0), vec3(0.51, 0.07953, 0.51)) < u65.d) {
        vec3 q108 = q63 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q109 = q108 - vec3(0.067164, 0.068211, 0.067991);
        vec3 id110 = clamp(round(q109 / vec3(0.119362, 1.0, 0.119362) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q111 = q109 - vec3(0.119362, 1.0, 0.119362) * (id110 - vec3(4.5, 0.0, 4.5));
        vec3 q112 = q111 - vec3(-0.016164, -0.068211, 0.019009);
        vec3 q113 = q112 * mat3(-0.761811, 0.0, -0.6478, 0.0, 1.0, 0.0, 0.6478, 0.0, -0.761811);
        vec3 q114 = q113 * mat3(1.0, 0.0, 0.0, 0.0, 0.939135, 0.343549, 0.0, -0.343549, 0.939135);
        vec3 q115 = q114 - vec3(0.0, 0.072632, 0.0);
        vec3 q116 = q115 / vec3(1.0, 1.0, 0.16);
        M m117 = M(sdPyramid((q116 + vec3(0.0, 0.072632, 0.0)) / 0.095958, 1.513842) * 0.095958, vec3(0.005155, 0.078925, 0.004138), vec3(0.6, 0.0, 0.0), vec3(0.25815, 0.595829, 0.091997), vec4(7.0, 0.141697, 1.0, 0.0), (q112 - vec3(0.0, -0.002637, 0.0)), 0.0);
        M m118 = m117; m118.d = m117.d * 0.16;
        vec3 q119 = q63 - vec3(0.0, 2.0, 0.0);
        M m120 = M(sdBox(q119, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m121 = mI(m118, m120);
        u65 = mU(u65, m121);
      }
      if (sdBox(q63 - vec3(0.0, 0.07432, 0.0), vec3(0.51, 0.08432, 0.51)) < u65.d) {
        vec3 q122 = q63 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q123 = q122 - vec3(0.06397, 0.073494, 0.100728);
        vec3 id124 = clamp(round(q123 / vec3(0.111303, 1.0, 0.111303) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q125 = q123 - vec3(0.111303, 1.0, 0.111303) * (id124 - vec3(4.5, 0.0, 4.5));
        vec3 q126 = q125 - vec3(0.00403, -0.073494, 0.015272);
        vec3 q127 = q126 * mat3(-0.966898, 0.0, 0.255161, 0.0, 1.0, 0.0, -0.255161, 0.0, -0.966898);
        vec3 q128 = q127 * mat3(1.0, 0.0, 0.0, 0.0, 0.977676, 0.210117, 0.0, -0.210117, 0.977676);
        vec3 q129 = q128 - vec3(0.0, 0.075172, 0.0);
        vec3 q130 = q129 / vec3(1.0, 1.0, 0.16);
        M m131 = M(sdPyramid((q130 + vec3(0.0, 0.075172, 0.0)) / 0.098292, 1.529557) * 0.098292, vec3(0.013634, 0.081037, 0.01124), vec3(0.6, 0.0, 0.0), vec3(0.371723, 0.752364, 0.068032), vec4(7.0, 0.150292, 1.0, 0.0), (q126 - vec3(0.0, -0.001652, 0.0)), 0.0);
        M m132 = m131; m132.d = m131.d * 0.16;
        vec3 q133 = q63 - vec3(0.0, 2.0, 0.0);
        M m134 = M(sdBox(q133, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m135 = mI(m132, m134);
        u65 = mU(u65, m135);
      }
      if (sdBox(q63 - vec3(0.0, 0.076492, 0.0), vec3(0.51, 0.086492, 0.51)) < u65.d) {
        vec3 q136 = q63 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q137 = q136 - vec3(0.063483, 0.074723, 0.12823);
        vec3 id138 = clamp(round(q137 / vec3(0.153035, 1.0, 0.153035) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q139 = q137 - vec3(0.153035, 1.0, 0.153035) * (id138 - vec3(3.0, 0.0, 3.0));
        vec3 q140 = q139 - vec3(0.021517, -0.074723, 0.01677);
        vec3 q141 = q140 * mat3(-0.614713, 0.0, 0.788751, 0.0, 1.0, 0.0, -0.788751, 0.0, -0.614713);
        vec3 q142 = q141 * mat3(1.0, 0.0, 0.0, 0.0, 0.939356, 0.342943, 0.0, -0.342943, 0.939356);
        vec3 q143 = q142 - vec3(0.0, 0.079547, 0.0);
        vec3 q144 = q143 / vec3(1.0, 1.0, 0.16);
        M m145 = M(sdPyramid((q144 + vec3(0.0, 0.079547, 0.0)) / 0.128935, 1.233914) * 0.128935, vec3(0.015674, 0.151342, 0.009769), vec3(0.6, 0.0, 0.0), vec3(0.250684, 0.768843, 0.063488), vec4(7.0, 0.156522, 1.0, 0.0), (q140 - vec3(0.0, -0.003537, 0.0)), 0.0);
        M m146 = m145; m146.d = m145.d * 0.16;
        vec3 q147 = q63 - vec3(0.0, 2.0, 0.0);
        M m148 = M(sdBox(q147, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m149 = mI(m146, m148);
        u65 = mU(u65, m149);
      }
      if (sdBox(q63 - vec3(0.0, 0.096512, 0.0), vec3(0.51, 0.106512, 0.51)) < u65.d) {
        vec3 q150 = q63 * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q151 = q150 - vec3(0.082395, 0.095493, 0.173378);
        vec3 id152 = clamp(round(q151 / vec3(0.133583, 1.0, 0.133583) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q153 = q151 - vec3(0.133583, 1.0, 0.133583) * (id152 - vec3(4.0, 0.0, 4.0));
        vec3 q154 = q153 - vec3(0.019605, -0.095493, 0.000622);
        vec3 q155 = q154 * mat3(-0.0317, 0.0, 0.999497, 0.0, 1.0, 0.0, -0.999497, 0.0, -0.0317);
        vec3 q156 = q155 * mat3(1.0, 0.0, 0.0, 0.0, 0.97955, 0.201202, 0.0, -0.201202, 0.97955);
        vec3 q157 = q156 - vec3(0.0, 0.097487, 0.0);
        vec3 q158 = q157 / vec3(1.0, 1.0, 0.16);
        M m159 = M(sdPyramid((q158 + vec3(0.0, 0.097487, 0.0)) / 0.126636, 1.539635) * 0.126636, vec3(0.016342, 0.142847, 0.014813), vec3(0.6, 0.0, 0.0), vec3(0.258096, 0.703565, 0.042176), vec4(7.0, 0.195063, 1.0, 0.0), (q154 - vec3(0.0, -0.002038, 0.0)), 0.0);
        M m160 = m159; m160.d = m159.d * 0.16;
        vec3 q161 = q63 - vec3(0.0, 2.0, 0.0);
        M m162 = M(sdBox(q161, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m163 = mI(m160, m162);
        u65 = mU(u65, m163);
      }
      if (sdBox(q63 - vec3(0.0, 0.08654, 0.0), vec3(0.51, 0.09654, 0.51)) < u65.d) {
        vec3 q164 = q63 * mat3(0.920505, 0.0, -0.390731, 0.0, 1.0, 0.0, 0.390731, 0.0, 0.920505);
        vec3 q165 = q164 - vec3(0.094588, 0.084706, 0.230072);
        vec3 id166 = clamp(round(q165 / vec3(0.152239, 1.0, 0.152239) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q167 = q165 - vec3(0.152239, 1.0, 0.152239) * (id166 - vec3(3.5, 0.0, 3.5));
        vec3 q168 = q167 - vec3(0.024412, -0.084706, -0.027072);
        vec3 q169 = q168 * mat3(0.74265, 0.0, 0.66968, 0.0, 1.0, 0.0, -0.66968, 0.0, 0.74265);
        vec3 q170 = q169 * mat3(1.0, 0.0, 0.0, 0.0, 0.918554, 0.395294, 0.0, -0.395294, 0.918554);
        vec3 q171 = q170 - vec3(0.0, 0.092217, 0.0);
        vec3 q172 = q171 / vec3(1.0, 1.0, 0.16);
        M m173 = M(sdPyramid((q172 + vec3(0.0, 0.092217, 0.0)) / 0.115995, 1.590017) * 0.115995, vec3(0.012444, 0.091824, 0.011976), vec3(0.6, 0.0, 0.0), vec3(0.304242, 0.596096, 0.071275), vec4(7.0, 0.176749, 1.0, 0.0), (q168 - vec3(0.0, -0.003668, 0.0)), 0.0);
        M m174 = m173; m174.d = m173.d * 0.16;
        vec3 q175 = q63 - vec3(0.0, 2.0, 0.0);
        M m176 = M(sdBox(q175, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m177 = mI(m174, m176);
        u65 = mU(u65, m177);
      }
      if (sdBox(q63 - vec3(0.0, 0.105866, 0.0), vec3(0.51, 0.115866, 0.51)) < u65.d) {
        vec3 q178 = q63 * mat3(0.882948, 0.0, -0.469472, 0.0, 1.0, 0.0, 0.469472, 0.0, 0.882948);
        vec3 q179 = q178 - vec3(0.137881, 0.104559, 0.264796);
        vec3 id180 = clamp(round(q179 / vec3(0.118131, 1.0, 0.118131) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q181 = q179 - vec3(0.118131, 1.0, 0.118131) * (id180 - vec3(4.5, 0.0, 4.5));
        vec3 q182 = q181 - vec3(-0.001881, -0.104559, -0.032796);
        vec3 q183 = q182 * mat3(0.998358, 0.0, -0.057274, 0.0, 1.0, 0.0, 0.057274, 0.0, 0.998358);
        vec3 q184 = q183 * mat3(1.0, 0.0, 0.0, 0.0, 0.954023, 0.299734, 0.0, -0.299734, 0.954023);
        vec3 q185 = q184 - vec3(0.0, 0.109598, 0.0);
        vec3 q186 = q185 / vec3(1.0, 1.0, 0.16);
        M m187 = M(sdPyramid((q186 + vec3(0.0, 0.109598, 0.0)) / 0.10905, 2.010045) * 0.10905, vec3(0.006076, 0.081722, 0.005103), vec3(0.6, 0.0, 0.0), vec3(0.389314, 0.761088, 0.098878), vec4(7.0, 0.214348, 1.0, 0.0), (q182 - vec3(0.0, -0.002615, 0.0)), 0.0);
        M m188 = m187; m188.d = m187.d * 0.16;
        vec3 q189 = q63 - vec3(0.0, 2.0, 0.0);
        M m190 = M(sdBox(q189, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m191 = mI(m188, m190);
        u65 = mU(u65, m191);
      }
      u64 = mU(u64, u65);
    }
    {
      vec3 q192 = q63 - vec3(0.0, -0.02, 0.0);
      M m193 = M(sdBox(q192, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u64 = mU(u64, m193);
    }
    u0 = mU(u0, u64);
  }
  if (cullVis(2) && sdBox(p - vec3(1.12, 0.08485, -0.56), vec3(0.51, 0.13485, 0.51)) < u0.d) {
    vec3 q194 = p - vec3(1.12, 0.0, -0.56);
    M u195 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q194 - vec3(0.0, 0.10485, 0.0), vec3(0.51, 0.11485, 0.51)) < u195.d) {
      M u196 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q194 - vec3(0.0, 0.046937, 0.0), vec3(0.51, 0.056937, 0.51)) < u196.d) {
        vec3 q197 = q194 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q198 = q197 - vec3(0.000118, 0.046644, 0.013776);
        vec3 id199 = clamp(round(q198 / vec3(0.050782, 1.0, 0.050782) + vec3(11.5, 0.0, 11.5)), vec3(0.0), vec3(23.0, 0.0, 23.0));
        vec3 q200 = q198 - vec3(0.050782, 1.0, 0.050782) * (id199 - vec3(11.5, 0.0, 11.5));
        vec3 q201 = q200 - vec3(-0.000118, -0.046644, -0.013776);
        vec3 q202 = q201 * mat3(0.999803, 0.0, -0.019872, 0.0, 1.0, 0.0, 0.019872, 0.0, 0.999803);
        M u203 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q204 = q202 * mat3(1.0, 0.0, 0.0, 0.0, 0.97032, 0.241823, 0.0, -0.241823, 0.97032);
          vec3 q205 = q204 - vec3(0.0, 0.02447, 0.0);
          vec3 q206 = q205 / vec3(1.0, 1.0, 0.1);
          M m207 = M(sdCone(q206, 0.02447, 0.024255, 0.012491), vec3(0.007787, 0.102103, 0.006872), vec3(0.6, 0.0, 0.0), vec3(0.182851, 0.465807, 0.026883), vec4(7.0, 0.094461, 1.0, 0.0), (q201 - vec3(0.0, -0.000587, 0.0)), 0.0);
          M m208 = m207; m208.d = m207.d * 0.1;
          u203 = mU(u203, m208);
        }
        {
          vec3 q209 = q202 - vec3(0.0, 0.047488, 0.011835);
          vec3 q210 = q209 * mat3(1.0, 0.0, 0.0, 0.0, 0.93794, 0.346797, 0.0, -0.346797, 0.93794);
          vec3 q211 = q210 - vec3(0.0, 0.02447, 0.0);
          vec3 q212 = q211 / vec3(1.0, 1.0, 0.1);
          M m213 = M(sdCone(q212, 0.02447, 0.013947, 0.00097), vec3(0.007787, 0.102103, 0.006872), vec3(0.6, 0.0, 0.0), vec3(0.182851, 0.465807, 0.026883), vec4(7.0, 0.094461, 1.0, 0.0), (q201 - vec3(0.0, -0.000587, 0.0)), 0.0);
          M m214 = m213; m214.d = m213.d * 0.1;
          u203 = mU(u203, m214);
        }
        vec3 q215 = q194 - vec3(0.0, 2.0, 0.0);
        M m216 = M(sdBox(q215, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m217 = mI(u203, m216);
        u196 = mU(u196, m217);
      }
      if (sdBox(q194 - vec3(0.0, 0.051301, 0.0), vec3(0.51, 0.061301, 0.51)) < u196.d) {
        vec3 q218 = q194 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q219 = q218 - vec3(0.029108, 0.050985, 0.034467);
        vec3 id220 = clamp(round(q219 / vec3(0.055109, 1.0, 0.055109) + vec3(10.5, 0.0, 10.5)), vec3(0.0), vec3(21.0, 0.0, 21.0));
        vec3 q221 = q219 - vec3(0.055109, 1.0, 0.055109) * (id220 - vec3(10.5, 0.0, 10.5));
        vec3 q222 = q221 - vec3(-0.012108, -0.050985, -0.005467);
        vec3 q223 = q222 * mat3(0.543908, 0.0, -0.839145, 0.0, 1.0, 0.0, 0.839145, 0.0, 0.543908);
        M u224 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q225 = q223 * mat3(1.0, 0.0, 0.0, 0.0, 0.961554, 0.274616, 0.0, -0.274616, 0.961554);
          vec3 q226 = q225 - vec3(0.0, 0.027131, 0.0);
          vec3 q227 = q226 / vec3(1.0, 1.0, 0.1);
          M m228 = M(sdCone(q227, 0.027131, 0.023033, 0.011862), vec3(0.025884, 0.134657, 0.021826), vec3(0.6, 0.0, 0.0), vec3(0.153107, 0.435026, 0.01457), vec4(7.0, 0.103234, 1.0, 0.0), (q222 - vec3(0.0, -0.000633, 0.0)), 0.0);
          M m229 = m228; m229.d = m228.d * 0.1;
          u224 = mU(u224, m229);
        }
        {
          vec3 q230 = q223 - vec3(0.0, 0.052175, 0.014901);
          vec3 q231 = q230 * mat3(1.0, 0.0, 0.0, 0.0, 0.919741, 0.392526, 0.0, -0.392526, 0.919741);
          vec3 q232 = q231 - vec3(0.0, 0.027131, 0.0);
          vec3 q233 = q232 / vec3(1.0, 1.0, 0.1);
          M m234 = M(sdCone(q233, 0.027131, 0.013244, 0.000921), vec3(0.025884, 0.134657, 0.021826), vec3(0.6, 0.0, 0.0), vec3(0.153107, 0.435026, 0.01457), vec4(7.0, 0.103234, 1.0, 0.0), (q222 - vec3(0.0, -0.000633, 0.0)), 0.0);
          M m235 = m234; m235.d = m234.d * 0.1;
          u224 = mU(u224, m235);
        }
        vec3 q236 = q194 - vec3(0.0, 2.0, 0.0);
        M m237 = M(sdBox(q236, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m238 = mI(u224, m237);
        u196 = mU(u196, m238);
      }
      if (sdBox(q194 - vec3(0.0, 0.058752, 0.0), vec3(0.51, 0.068752, 0.51)) < u196.d) {
        vec3 q239 = q194 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q240 = q239 - vec3(0.048141, 0.058531, 0.058565);
        vec3 id241 = clamp(round(q240 / vec3(0.046429, 1.0, 0.046429) + vec3(12.5, 0.0, 12.5)), vec3(0.0), vec3(25.0, 0.0, 25.0));
        vec3 q242 = q240 - vec3(0.046429, 1.0, 0.046429) * (id241 - vec3(12.5, 0.0, 12.5));
        vec3 q243 = q242 - vec3(-0.014141, -0.058531, -0.000565);
        vec3 q244 = q243 * mat3(0.091362, 0.0, -0.995818, 0.0, 1.0, 0.0, 0.995818, 0.0, 0.091362);
        M u245 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q246 = q244 * mat3(1.0, 0.0, 0.0, 0.0, 0.978895, 0.204365, 0.0, -0.204365, 0.978895);
          vec3 q247 = q246 - vec3(0.0, 0.030273, 0.0);
          vec3 q248 = q247 / vec3(1.0, 1.0, 0.1);
          M m249 = M(sdCone(q248, 0.030273, 0.021653, 0.011151), vec3(0.00713, 0.094135, 0.002841), vec3(0.6, 0.0, 0.0), vec3(0.152703, 0.517203, 0.015688), vec4(7.0, 0.117947, 1.0, 0.0), (q243 - vec3(0.0, -0.000443, 0.0)), 0.0);
          M m250 = m249; m250.d = m249.d * 0.1;
          u245 = mU(u245, m250);
        }
        {
          vec3 q251 = q244 - vec3(0.0, 0.059268, 0.012374);
          vec3 q252 = q251 * mat3(1.0, 0.0, 0.0, 0.0, 0.955799, 0.294022, 0.0, -0.294022, 0.955799);
          vec3 q253 = q252 - vec3(0.0, 0.030273, 0.0);
          vec3 q254 = q253 / vec3(1.0, 1.0, 0.1);
          M m255 = M(sdCone(q254, 0.030273, 0.012451, 0.000866), vec3(0.00713, 0.094135, 0.002841), vec3(0.6, 0.0, 0.0), vec3(0.152703, 0.517203, 0.015688), vec4(7.0, 0.117947, 1.0, 0.0), (q243 - vec3(0.0, -0.000443, 0.0)), 0.0);
          M m256 = m255; m256.d = m255.d * 0.1;
          u245 = mU(u245, m256);
        }
        vec3 q257 = q194 - vec3(0.0, 2.0, 0.0);
        M m258 = M(sdBox(q257, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m259 = mI(u245, m258);
        u196 = mU(u196, m259);
      }
      if (sdBox(q194 - vec3(0.0, 0.058654, 0.0), vec3(0.51, 0.068654, 0.51)) < u196.d) {
        vec3 q260 = q194 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q261 = q260 - vec3(0.055074, 0.058426, 0.079929);
        vec3 id262 = clamp(round(q261 / vec3(0.051512, 1.0, 0.051512) + vec3(11.0, 0.0, 11.0)), vec3(0.0), vec3(22.0, 0.0, 22.0));
        vec3 q263 = q261 - vec3(0.051512, 1.0, 0.051512) * (id262 - vec3(11.0, 0.0, 11.0));
        vec3 q264 = q263 - vec3(-0.004074, -0.058426, 0.007071);
        vec3 q265 = q264 * mat3(-0.78409, 0.0, -0.620647, 0.0, 1.0, 0.0, 0.620647, 0.0, -0.78409);
        M u266 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q267 = q265 * mat3(1.0, 0.0, 0.0, 0.0, 0.982493, 0.186299, 0.0, -0.186299, 0.982493);
          vec3 q268 = q267 - vec3(0.0, 0.030047, 0.0);
          vec3 q269 = q268 / vec3(1.0, 1.0, 0.1);
          M m270 = M(sdCone(q269, 0.030047, 0.024485, 0.01261), vec3(0.048084, 0.20087, 0.035248), vec3(0.6, 0.0, 0.0), vec3(0.46686, 0.91652, 0.22544), vec4(7.0, 0.117764, 1.0, 0.0), (q264 - vec3(0.0, -0.000456, 0.0)), 0.0);
          M m271 = m270; m271.d = m270.d * 0.1;
          u266 = mU(u266, m271);
        }
        {
          vec3 q272 = q265 - vec3(0.0, 0.059041, 0.011195);
          vec3 q273 = q272 * mat3(1.0, 0.0, 0.0, 0.0, 0.96331, 0.26839, 0.0, -0.26839, 0.96331);
          vec3 q274 = q273 - vec3(0.0, 0.030047, 0.0);
          vec3 q275 = q274 / vec3(1.0, 1.0, 0.1);
          M m276 = M(sdCone(q275, 0.030047, 0.014079, 0.000979), vec3(0.048084, 0.20087, 0.035248), vec3(0.6, 0.0, 0.0), vec3(0.46686, 0.91652, 0.22544), vec4(7.0, 0.117764, 1.0, 0.0), (q264 - vec3(0.0, -0.000456, 0.0)), 0.0);
          M m277 = m276; m277.d = m276.d * 0.1;
          u266 = mU(u266, m277);
        }
        vec3 q278 = q194 - vec3(0.0, 2.0, 0.0);
        M m279 = M(sdBox(q278, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m280 = mI(u266, m279);
        u196 = mU(u196, m280);
      }
      if (sdBox(q194 - vec3(0.0, 0.05568, 0.0), vec3(0.51, 0.06568, 0.51)) < u196.d) {
        vec3 q281 = q194 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q282 = q281 - vec3(0.068179, 0.055222, 0.095245);
        vec3 id283 = clamp(round(q282 / vec3(0.064264, 1.0, 0.064264) + vec3(8.5, 0.0, 8.5)), vec3(0.0), vec3(17.0, 0.0, 17.0));
        vec3 q284 = q282 - vec3(0.064264, 1.0, 0.064264) * (id283 - vec3(8.5, 0.0, 8.5));
        vec3 q285 = q284 - vec3(-0.000179, -0.055222, 0.020755);
        vec3 q286 = q285 * mat3(-0.999796, 0.0, -0.020196, 0.0, 1.0, 0.0, 0.020196, 0.0, -0.999796);
        M u287 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q288 = q286 * mat3(1.0, 0.0, 0.0, 0.0, 0.954327, 0.298766, 0.0, -0.298766, 0.954327);
          vec3 q289 = q288 - vec3(0.0, 0.029748, 0.0);
          vec3 q290 = q289 / vec3(1.0, 1.0, 0.1);
          M m291 = M(sdCone(q290, 0.029748, 0.030664, 0.015792), vec3(0.032567, 0.157179, 0.028731), vec3(0.6, 0.0, 0.0), vec3(0.172563, 0.617274, 0.029939), vec4(7.0, 0.112276, 1.0, 0.0), (q285 - vec3(0.0, -0.000916, 0.0)), 0.0);
          M m292 = m291; m292.d = m291.d * 0.1;
          u287 = mU(u287, m292);
        }
        {
          vec3 q293 = q286 - vec3(0.0, 0.056778, 0.017775);
          vec3 q294 = q293 * mat3(1.0, 0.0, 0.0, 0.0, 0.904782, 0.425875, 0.0, -0.425875, 0.904782);
          vec3 q295 = q294 - vec3(0.0, 0.029748, 0.0);
          vec3 q296 = q295 / vec3(1.0, 1.0, 0.1);
          M m297 = M(sdCone(q296, 0.029748, 0.017632, 0.001227), vec3(0.032567, 0.157179, 0.028731), vec3(0.6, 0.0, 0.0), vec3(0.172563, 0.617274, 0.029939), vec4(7.0, 0.112276, 1.0, 0.0), (q285 - vec3(0.0, -0.000916, 0.0)), 0.0);
          M m298 = m297; m298.d = m297.d * 0.1;
          u287 = mU(u287, m298);
        }
        vec3 q299 = q194 - vec3(0.0, 2.0, 0.0);
        M m300 = M(sdBox(q299, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m301 = mI(u287, m300);
        u196 = mU(u196, m301);
      }
      if (sdBox(q194 - vec3(0.0, 0.069145, 0.0), vec3(0.51, 0.079145, 0.51)) < u196.d) {
        vec3 q302 = q194 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q303 = q302 - vec3(0.057707, 0.068773, 0.138456);
        vec3 id304 = clamp(round(q303 / vec3(0.076658, 1.0, 0.076658) + vec3(7.0, 0.0, 7.0)), vec3(0.0), vec3(14.0, 0.0, 14.0));
        vec3 q305 = q303 - vec3(0.076658, 1.0, 0.076658) * (id304 - vec3(7.0, 0.0, 7.0));
        vec3 q306 = q305 - vec3(0.027293, -0.068773, 0.006544);
        vec3 q307 = q306 * mat3(-0.351827, 0.0, 0.936065, 0.0, 1.0, 0.0, -0.936065, 0.0, -0.351827);
        M u308 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q309 = q307 * mat3(1.0, 0.0, 0.0, 0.0, 0.939708, 0.341977, 0.0, -0.341977, 0.939708);
          vec3 q310 = q309 - vec3(0.0, 0.037943, 0.0);
          vec3 q311 = q310 / vec3(1.0, 1.0, 0.1);
          M m312 = M(sdCone(q311, 0.037943, 0.021742, 0.011197), vec3(0.008024, 0.106523, 0.006897), vec3(0.6, 0.0, 0.0), vec3(0.363146, 0.82984, 0.035955), vec4(7.0, 0.139033, 1.0, 0.0), (q306 - vec3(0.0, -0.000744, 0.0)), 0.0);
          M m313 = m312; m313.d = m312.d * 0.1;
          u308 = mU(u308, m313);
        }
        {
          vec3 q314 = q307 - vec3(0.0, 0.07131, 0.025951);
          vec3 q315 = q314 * mat3(1.0, 0.0, 0.0, 0.0, 0.874652, 0.484751, 0.0, -0.484751, 0.874652);
          vec3 q316 = q315 - vec3(0.0, 0.037943, 0.0);
          vec3 q317 = q316 / vec3(1.0, 1.0, 0.1);
          M m318 = M(sdCone(q317, 0.037943, 0.012502, 0.00087), vec3(0.008024, 0.106523, 0.006897), vec3(0.6, 0.0, 0.0), vec3(0.363146, 0.82984, 0.035955), vec4(7.0, 0.139033, 1.0, 0.0), (q306 - vec3(0.0, -0.000744, 0.0)), 0.0);
          M m319 = m318; m319.d = m318.d * 0.1;
          u308 = mU(u308, m319);
        }
        vec3 q320 = q194 - vec3(0.0, 2.0, 0.0);
        M m321 = M(sdBox(q320, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m322 = mI(u308, m321);
        u196 = mU(u196, m322);
      }
      if (sdBox(q194 - vec3(0.0, 0.066433, 0.0), vec3(0.51, 0.076433, 0.51)) < u196.d) {
        vec3 q323 = q194 * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q324 = q323 - vec3(0.073128, 0.065969, 0.183717);
        vec3 id325 = clamp(round(q324 / vec3(0.085352, 1.0, 0.085352) + vec3(6.5, 0.0, 6.5)), vec3(0.0), vec3(13.0, 0.0, 13.0));
        vec3 q326 = q324 - vec3(0.085352, 1.0, 0.085352) * (id325 - vec3(6.5, 0.0, 6.5));
        vec3 q327 = q326 - vec3(0.028872, -0.065969, -0.009717);
        vec3 q328 = q327 * mat3(0.420255, 0.0, 0.907406, 0.0, 1.0, 0.0, -0.907406, 0.0, 0.420255);
        M u329 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q330 = q328 * mat3(1.0, 0.0, 0.0, 0.0, 0.922968, 0.384877, 0.0, -0.384877, 0.922968);
          vec3 q331 = q330 - vec3(0.0, 0.037462, 0.0);
          vec3 q332 = q331 / vec3(1.0, 1.0, 0.1);
          M m333 = M(sdCone(q332, 0.037462, 0.024131, 0.012428), vec3(0.007299, 0.037721, 0.00584), vec3(0.6, 0.0, 0.0), vec3(0.245906, 0.613613, 0.093524), vec4(7.0, 0.133796, 1.0, 0.0), (q327 - vec3(0.0, -0.000929, 0.0)), 0.0);
          M m334 = m333; m334.d = m333.d * 0.1;
          u329 = mU(u329, m334);
        }
        {
          vec3 q335 = q328 - vec3(0.0, 0.069152, 0.028836);
          vec3 q336 = q335 * mat3(1.0, 0.0, 0.0, 0.0, 0.840355, 0.542036, 0.0, -0.542036, 0.840355);
          vec3 q337 = q336 - vec3(0.0, 0.037462, 0.0);
          vec3 q338 = q337 / vec3(1.0, 1.0, 0.1);
          M m339 = M(sdCone(q338, 0.037462, 0.013875, 0.000965), vec3(0.007299, 0.037721, 0.00584), vec3(0.6, 0.0, 0.0), vec3(0.245906, 0.613613, 0.093524), vec4(7.0, 0.133796, 1.0, 0.0), (q327 - vec3(0.0, -0.000929, 0.0)), 0.0);
          M m340 = m339; m340.d = m339.d * 0.1;
          u329 = mU(u329, m340);
        }
        vec3 q341 = q194 - vec3(0.0, 2.0, 0.0);
        M m342 = M(sdBox(q341, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m343 = mI(u329, m342);
        u196 = mU(u196, m343);
      }
      if (sdBox(q194 - vec3(0.0, 0.073884, 0.0), vec3(0.51, 0.083884, 0.51)) < u196.d) {
        vec3 q344 = q194 * mat3(0.920505, 0.0, -0.390731, 0.0, 1.0, 0.0, 0.390731, 0.0, 0.920505);
        vec3 q345 = q344 - vec3(0.103327, 0.073308, 0.23177);
        vec3 id346 = clamp(round(q345 / vec3(0.098203, 1.0, 0.098203) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q347 = q345 - vec3(0.098203, 1.0, 0.098203) * (id346 - vec3(5.5, 0.0, 5.5));
        vec3 q348 = q347 - vec3(0.015673, -0.073308, -0.02877);
        vec3 q349 = q348 * mat3(0.838236, 0.0, 0.545307, 0.0, 1.0, 0.0, -0.545307, 0.0, 0.838236);
        M u350 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q351 = q349 * mat3(1.0, 0.0, 0.0, 0.0, 0.921367, 0.388694, 0.0, -0.388694, 0.921367);
          vec3 q352 = q351 - vec3(0.0, 0.041752, 0.0);
          vec3 q353 = q352 / vec3(1.0, 1.0, 0.1);
          M m354 = M(sdCone(q353, 0.041752, 0.029625, 0.015257), vec3(0.013095, 0.125088, 0.00761), vec3(0.6, 0.0, 0.0), vec3(0.147479, 0.504953, 0.018214), vec4(7.0, 0.14892, 1.0, 0.0), (q348 - vec3(0.0, -0.001151, 0.0)), 0.0);
          M m355 = m354; m355.d = m354.d * 0.1;
          u350 = mU(u350, m355);
        }
        {
          vec3 q356 = q349 - vec3(0.0, 0.076937, 0.032457);
          vec3 q357 = q356 * mat3(1.0, 0.0, 0.0, 0.0, 0.837087, 0.54707, 0.0, -0.54707, 0.837087);
          vec3 q358 = q357 - vec3(0.0, 0.041752, 0.0);
          vec3 q359 = q358 / vec3(1.0, 1.0, 0.1);
          M m360 = M(sdCone(q359, 0.041752, 0.017034, 0.001185), vec3(0.013095, 0.125088, 0.00761), vec3(0.6, 0.0, 0.0), vec3(0.147479, 0.504953, 0.018214), vec4(7.0, 0.14892, 1.0, 0.0), (q348 - vec3(0.0, -0.001151, 0.0)), 0.0);
          M m361 = m360; m361.d = m360.d * 0.1;
          u350 = mU(u350, m361);
        }
        vec3 q362 = q194 - vec3(0.0, 2.0, 0.0);
        M m363 = M(sdBox(q362, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m364 = mI(u350, m363);
        u196 = mU(u196, m364);
      }
      if (sdBox(q194 - vec3(0.0, 0.074278, 0.0), vec3(0.51, 0.084278, 0.51)) < u196.d) {
        vec3 q365 = q194 * mat3(0.882948, 0.0, -0.469472, 0.0, 1.0, 0.0, 0.469472, 0.0, 0.882948);
        vec3 q366 = q365 - vec3(0.136382, 0.07391, 0.260375);
        vec3 id367 = clamp(round(q366 / vec3(0.065489, 1.0, 0.065489) + vec3(8.5, 0.0, 8.5)), vec3(0.0), vec3(17.0, 0.0, 17.0));
        vec3 q368 = q366 - vec3(0.065489, 1.0, 0.065489) * (id367 - vec3(8.5, 0.0, 8.5));
        vec3 q369 = q368 - vec3(-0.000382, -0.07391, -0.028375);
        vec3 q370 = q369 * mat3(0.999493, 0.0, -0.031836, 0.0, 1.0, 0.0, 0.031836, 0.0, 0.999493);
        M u371 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q372 = q370 * mat3(1.0, 0.0, 0.0, 0.0, 0.953604, 0.301064, 0.0, -0.301064, 0.953604);
          vec3 q373 = q372 - vec3(0.0, 0.039839, 0.0);
          vec3 q374 = q373 / vec3(1.0, 1.0, 0.1);
          M m375 = M(sdCone(q374, 0.039839, 0.024456, 0.012595), vec3(0.004973, 0.053764, 0.002938), vec3(0.6, 0.0, 0.0), vec3(0.245741, 0.604233, 0.079521), vec4(7.0, 0.149293, 1.0, 0.0), (q369 - vec3(0.0, -0.000736, 0.0)), 0.0);
          M m376 = m375; m376.d = m375.d * 0.1;
          u371 = mU(u371, m376);
        }
        {
          vec3 q377 = q370 - vec3(0.0, 0.075981, 0.023988);
          vec3 q378 = q377 * mat3(1.0, 0.0, 0.0, 0.0, 0.903289, 0.429033, 0.0, -0.429033, 0.903289);
          vec3 q379 = q378 - vec3(0.0, 0.039839, 0.0);
          vec3 q380 = q379 / vec3(1.0, 1.0, 0.1);
          M m381 = M(sdCone(q380, 0.039839, 0.014062, 0.000978), vec3(0.004973, 0.053764, 0.002938), vec3(0.6, 0.0, 0.0), vec3(0.245741, 0.604233, 0.079521), vec4(7.0, 0.149293, 1.0, 0.0), (q369 - vec3(0.0, -0.000736, 0.0)), 0.0);
          M m382 = m381; m382.d = m381.d * 0.1;
          u371 = mU(u371, m382);
        }
        vec3 q383 = q194 - vec3(0.0, 2.0, 0.0);
        M m384 = M(sdBox(q383, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m385 = mI(u371, m384);
        u196 = mU(u196, m385);
      }
      if (sdBox(q194 - vec3(0.0, 0.080869, 0.0), vec3(0.51, 0.090869, 0.51)) < u196.d) {
        vec3 q386 = q194 * mat3(0.838671, 0.0, -0.544639, 0.0, 1.0, 0.0, 0.544639, 0.0, 0.838671);
        vec3 q387 = q386 - vec3(0.180315, 0.080448, 0.263632);
        vec3 id388 = clamp(round(q387 / vec3(0.075575, 1.0, 0.075575) + vec3(7.5, 0.0, 7.5)), vec3(0.0), vec3(15.0, 0.0, 15.0));
        vec3 q389 = q387 - vec3(0.075575, 1.0, 0.075575) * (id388 - vec3(7.5, 0.0, 7.5));
        vec3 q390 = q389 - vec3(-0.027315, -0.080448, -0.002632);
        vec3 q391 = q390 * mat3(0.213283, 0.0, -0.976991, 0.0, 1.0, 0.0, 0.976991, 0.0, 0.213283);
        M u392 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q393 = q391 * mat3(1.0, 0.0, 0.0, 0.0, 0.958027, 0.286677, 0.0, -0.286677, 0.958027);
          vec3 q394 = q393 - vec3(0.0, 0.04305, 0.0);
          vec3 q395 = q394 / vec3(1.0, 1.0, 0.1);
          M m396 = M(sdCone(q395, 0.04305, 0.029391, 0.015136), vec3(0.032405, 0.142061, 0.024977), vec3(0.6, 0.0, 0.0), vec3(0.369767, 0.796801, 0.047931), vec4(7.0, 0.16258, 1.0, 0.0), (q390 - vec3(0.0, -0.000843, 0.0)), 0.0);
          M m397 = m396; m397.d = m396.d * 0.1;
          u392 = mU(u392, m397);
        }
        {
          vec3 q398 = q391 - vec3(0.0, 0.082486, 0.024683);
          vec3 q399 = q398 * mat3(1.0, 0.0, 0.0, 0.0, 0.912436, 0.409218, 0.0, -0.409218, 0.912436);
          vec3 q400 = q399 - vec3(0.0, 0.04305, 0.0);
          vec3 q401 = q400 / vec3(1.0, 1.0, 0.1);
          M m402 = M(sdCone(q401, 0.04305, 0.0169, 0.001176), vec3(0.032405, 0.142061, 0.024977), vec3(0.6, 0.0, 0.0), vec3(0.369767, 0.796801, 0.047931), vec4(7.0, 0.16258, 1.0, 0.0), (q390 - vec3(0.0, -0.000843, 0.0)), 0.0);
          M m403 = m402; m403.d = m402.d * 0.1;
          u392 = mU(u392, m403);
        }
        vec3 q404 = q194 - vec3(0.0, 2.0, 0.0);
        M m405 = M(sdBox(q404, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m406 = mI(u392, m405);
        u196 = mU(u196, m406);
      }
      if (sdBox(q194 - vec3(0.0, 0.09076, 0.0), vec3(0.51, 0.10076, 0.51)) < u196.d) {
        vec3 q407 = q194 * mat3(0.788011, 0.0, -0.615661, 0.0, 1.0, 0.0, 0.615661, 0.0, 0.788011);
        vec3 q408 = q407 - vec3(0.193943, 0.09046, 0.282719);
        vec3 id409 = clamp(round(q408 / vec3(0.074802, 1.0, 0.074802) + vec3(7.5, 0.0, 7.5)), vec3(0.0), vec3(15.0, 0.0, 15.0));
        vec3 q410 = q408 - vec3(0.074802, 1.0, 0.074802) * (id409 - vec3(7.5, 0.0, 7.5));
        vec3 q411 = q410 - vec3(-0.023943, -0.09046, 0.007281);
        vec3 q412 = q411 * mat3(-0.415404, 0.0, -0.909637, 0.0, 1.0, 0.0, 0.909637, 0.0, -0.415404);
        M u413 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q414 = q412 * mat3(1.0, 0.0, 0.0, 0.0, 0.967823, 0.251631, 0.0, -0.251631, 0.967823);
          vec3 q415 = q414 - vec3(0.0, 0.047624, 0.0);
          vec3 q416 = q415 / vec3(1.0, 1.0, 0.1);
          M m417 = M(sdCone(q416, 0.047624, 0.023875, 0.012296), vec3(0.030829, 0.147231, 0.021772), vec3(0.6, 0.0, 0.0), vec3(0.148477, 0.465804, 0.038844), vec4(7.0, 0.182122, 1.0, 0.0), (q411 - vec3(0.0, -0.000601, 0.0)), 0.0);
          M m418 = m417; m418.d = m417.d * 0.1;
          u413 = mU(u413, m418);
        }
        {
          vec3 q419 = q412 - vec3(0.0, 0.092183, 0.023967);
          vec3 q420 = q419 * mat3(1.0, 0.0, 0.0, 0.0, 0.93275, 0.360524, 0.0, -0.360524, 0.93275);
          vec3 q421 = q420 - vec3(0.0, 0.047624, 0.0);
          vec3 q422 = q421 / vec3(1.0, 1.0, 0.1);
          M m423 = M(sdCone(q422, 0.047624, 0.013728, 0.000955), vec3(0.030829, 0.147231, 0.021772), vec3(0.6, 0.0, 0.0), vec3(0.148477, 0.465804, 0.038844), vec4(7.0, 0.182122, 1.0, 0.0), (q411 - vec3(0.0, -0.000601, 0.0)), 0.0);
          M m424 = m423; m424.d = m423.d * 0.1;
          u413 = mU(u413, m424);
        }
        vec3 q425 = q194 - vec3(0.0, 2.0, 0.0);
        M m426 = M(sdBox(q425, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m427 = mI(u413, m426);
        u196 = mU(u196, m427);
      }
      if (sdBox(q194 - vec3(0.016044, 0.096335, 0.0), vec3(0.493956, 0.106335, 0.51)) < u196.d) {
        vec3 q428 = q194 * mat3(0.731354, 0.0, -0.681998, 0.0, 1.0, 0.0, 0.681998, 0.0, 0.731354);
        vec3 q429 = q428 - vec3(0.190141, 0.096061, 0.30155);
        vec3 id430 = clamp(round(q429 / vec3(0.067891, 1.0, 0.067891) + vec3(8.0, 0.0, 8.0)), vec3(0.0), vec3(16.0, 0.0, 16.0));
        vec3 q431 = q429 - vec3(0.067891, 1.0, 0.067891) * (id430 - vec3(8.0, 0.0, 8.0));
        vec3 q432 = q431 - vec3(-0.003141, -0.096061, 0.01745);
        vec3 q433 = q432 * mat3(-0.935719, 0.0, -0.352746, 0.0, 1.0, 0.0, 0.352746, 0.0, -0.935719);
        M u434 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q435 = q433 * mat3(1.0, 0.0, 0.0, 0.0, 0.983563, 0.180566, 0.0, -0.180566, 0.983563);
          vec3 q436 = q435 - vec3(0.0, 0.049308, 0.0);
          vec3 q437 = q436 / vec3(1.0, 1.0, 0.1);
          M m438 = M(sdCone(q437, 0.049308, 0.030399, 0.015655), vec3(0.012035, 0.172897, 0.007883), vec3(0.6, 0.0, 0.0), vec3(0.197335, 0.446759, 0.048344), vec4(7.0, 0.193219, 1.0, 0.0), (q432 - vec3(0.0, -0.000549, 0.0)), 0.0);
          M m439 = m438; m439.d = m438.d * 0.1;
          u434 = mU(u434, m439);
        }
        {
          vec3 q440 = q433 - vec3(0.0, 0.096996, 0.017807);
          vec3 q441 = q440 * mat3(1.0, 0.0, 0.0, 0.0, 0.965546, 0.260234, 0.0, -0.260234, 0.965546);
          vec3 q442 = q441 - vec3(0.0, 0.049308, 0.0);
          vec3 q443 = q442 / vec3(1.0, 1.0, 0.1);
          M m444 = M(sdCone(q443, 0.049308, 0.017479, 0.001216), vec3(0.012035, 0.172897, 0.007883), vec3(0.6, 0.0, 0.0), vec3(0.197335, 0.446759, 0.048344), vec4(7.0, 0.193219, 1.0, 0.0), (q432 - vec3(0.0, -0.000549, 0.0)), 0.0);
          M m445 = m444; m445.d = m444.d * 0.1;
          u434 = mU(u434, m445);
        }
        vec3 q446 = q194 - vec3(0.0, 2.0, 0.0);
        M m447 = M(sdBox(q446, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m448 = mI(u434, m447);
        u196 = mU(u196, m448);
      }
      if (sdBox(q194 - vec3(0.022715, 0.10485, 0.0), vec3(0.487285, 0.11485, 0.51)) < u196.d) {
        vec3 q449 = q194 * mat3(0.669131, 0.0, -0.743145, 0.0, 1.0, 0.0, 0.743145, 0.0, 0.669131);
        vec3 q450 = q449 - vec3(0.19559, 0.10456, 0.323803);
        vec3 id451 = clamp(round(q450 / vec3(0.078537, 1.0, 0.078537) + vec3(7.0, 0.0, 7.0)), vec3(0.0), vec3(14.0, 0.0, 14.0));
        vec3 q452 = q450 - vec3(0.078537, 1.0, 0.078537) * (id451 - vec3(7.0, 0.0, 7.0));
        vec3 q453 = q452 - vec3(0.00841, -0.10456, 0.024197);
        vec3 q454 = q453 * mat3(-0.895139, 0.0, 0.445786, 0.0, 1.0, 0.0, -0.445786, 0.0, -0.895139);
        M u455 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q456 = q454 * mat3(1.0, 0.0, 0.0, 0.0, 0.97368, 0.227921, 0.0, -0.227921, 0.97368);
          vec3 q457 = q456 - vec3(0.0, 0.054524, 0.0);
          vec3 q458 = q457 / vec3(1.0, 1.0, 0.1);
          M m459 = M(sdCone(q458, 0.054524, 0.025446, 0.013105), vec3(0.011441, 0.105912, 0.008087), vec3(0.6, 0.0, 0.0), vec3(0.459712, 0.870127, 0.153268), vec4(7.0, 0.21028, 1.0, 0.0), (q453 - vec3(0.0, -0.00058, 0.0)), 0.0);
          M m460 = m459; m460.d = m459.d * 0.1;
          u455 = mU(u455, m460);
        }
        {
          vec3 q461 = q454 - vec3(0.0, 0.106178, 0.024854);
          vec3 q462 = q461 * mat3(1.0, 0.0, 0.0, 0.0, 0.94493, 0.327273, 0.0, -0.327273, 0.94493);
          vec3 q463 = q462 - vec3(0.0, 0.054524, 0.0);
          vec3 q464 = q463 / vec3(1.0, 1.0, 0.1);
          M m465 = M(sdCone(q464, 0.054524, 0.014632, 0.001018), vec3(0.011441, 0.105912, 0.008087), vec3(0.6, 0.0, 0.0), vec3(0.459712, 0.870127, 0.153268), vec4(7.0, 0.21028, 1.0, 0.0), (q453 - vec3(0.0, -0.00058, 0.0)), 0.0);
          M m466 = m465; m466.d = m465.d * 0.1;
          u455 = mU(u455, m466);
        }
        vec3 q467 = q194 - vec3(0.0, 2.0, 0.0);
        M m468 = M(sdBox(q467, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m469 = mI(u455, m468);
        u196 = mU(u196, m469);
      }
      if (sdBox(q194 - vec3(0.050316, 0.104415, 0.0), vec3(0.459684, 0.114415, 0.51)) < u196.d) {
        vec3 q470 = q194 * mat3(0.601815, 0.0, -0.798636, 0.0, 1.0, 0.0, 0.798636, 0.0, 0.601815);
        vec3 q471 = q470 - vec3(0.19861, 0.104124, 0.36774);
        vec3 id472 = clamp(round(q471 / vec3(0.077876, 1.0, 0.077876) + vec3(7.0, 0.0, 7.0)), vec3(0.0), vec3(14.0, 0.0, 14.0));
        vec3 q473 = q471 - vec3(0.077876, 1.0, 0.077876) * (id472 - vec3(7.0, 0.0, 7.0));
        vec3 q474 = q473 - vec3(0.02239, -0.104124, 0.00926);
        vec3 q475 = q474 * mat3(-0.489812, 0.0, 0.871828, 0.0, 1.0, 0.0, -0.871828, 0.0, -0.489812);
        M u476 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q477 = q475 * mat3(1.0, 0.0, 0.0, 0.0, 0.974943, 0.222454, 0.0, -0.222454, 0.974943);
          vec3 q478 = q477 - vec3(0.0, 0.054187, 0.0);
          vec3 q479 = q478 / vec3(1.0, 1.0, 0.1);
          M m480 = M(sdCone(q479, 0.054187, 0.026182, 0.013484), vec3(0.005324, 0.056416, 0.003074), vec3(0.6, 0.0, 0.0), vec3(0.341259, 0.816945, 0.141449), vec4(7.0, 0.209413, 1.0, 0.0), (q474 - vec3(0.0, -0.000582, 0.0)), 0.0);
          M m481 = m480; m481.d = m480.d * 0.1;
          u476 = mU(u476, m481);
        }
        {
          vec3 q482 = q475 - vec3(0.0, 0.105659, 0.024108);
          vec3 q483 = q482 * mat3(1.0, 0.0, 0.0, 0.0, 0.947561, 0.319574, 0.0, -0.319574, 0.947561);
          vec3 q484 = q483 - vec3(0.0, 0.054187, 0.0);
          vec3 q485 = q484 / vec3(1.0, 1.0, 0.1);
          M m486 = M(sdCone(q485, 0.054187, 0.015055, 0.001047), vec3(0.005324, 0.056416, 0.003074), vec3(0.6, 0.0, 0.0), vec3(0.341259, 0.816945, 0.141449), vec4(7.0, 0.209413, 1.0, 0.0), (q474 - vec3(0.0, -0.000582, 0.0)), 0.0);
          M m487 = m486; m487.d = m486.d * 0.1;
          u476 = mU(u476, m487);
        }
        vec3 q488 = q194 - vec3(0.0, 2.0, 0.0);
        M m489 = M(sdBox(q488, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m490 = mI(u476, m489);
        u196 = mU(u196, m490);
      }
      u195 = mU(u195, u196);
    }
    {
      vec3 q491 = q194 - vec3(0.0, -0.02, 0.0);
      M m492 = M(sdBox(q491, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u195 = mU(u195, m492);
    }
    u0 = mU(u0, u195);
  }
  if (cullVis(3) && sdBox(p - vec3(-1.12, 0.143266, 0.56), vec3(0.51, 0.193266, 0.51)) < u0.d) {
    vec3 q493 = p - vec3(-1.12, 0.0, 0.56);
    M u494 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q493 - vec3(0.0, 0.163266, 0.0), vec3(0.51, 0.173266, 0.51)) < u494.d) {
      M u495 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q493 - vec3(0.0, 0.084393, 0.0), vec3(0.51, 0.094393, 0.51)) < u495.d) {
        vec3 q496 = q493 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q497 = q496 - vec3(-0.006229, 0.08138, 0.027522);
        vec3 id498 = clamp(round(q497 / vec3(0.109385, 1.0, 0.109385) + vec3(5.0, 0.0, 5.0)), vec3(0.0), vec3(10.0, 0.0, 10.0));
        vec3 q499 = q497 - vec3(0.109385, 1.0, 0.109385) * (id498 - vec3(5.0, 0.0, 5.0));
        vec3 q500 = q499 - vec3(0.006229, -0.08138, -0.027522);
        vec3 q501 = q500 * mat3(0.975334, 0.0, 0.220734, 0.0, 1.0, 0.0, -0.220734, 0.0, 0.975334);
        vec3 q502 = q501 * mat3(1.0, 0.0, 0.0, 0.0, 0.944813, 0.327611, 0.0, -0.327611, 0.944813);
        vec3 q503 = q502 - vec3(0.0, 0.086134, 0.0);
        vec3 q504 = q503 / vec3(1.0, 1.0, 0.5);
        M m505 = M(sdPyramid((q504 + vec3(0.0, 0.086134, 0.0)) / 0.073565, 2.34172) * 0.073565, vec3(0.250418, 0.18084, 0.041027), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m506 = m505; m506.d = m505.d * 0.5;
        vec3 q507 = q493 - vec3(0.0, 2.0, 0.0);
        M m508 = M(sdBox(q507, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m509 = mI(m506, m508);
        u495 = mU(u495, m509);
      }
      if (sdBox(q493 - vec3(0.0, 0.104434, 0.0), vec3(0.51, 0.114434, 0.51)) < u495.d) {
        vec3 q510 = q493 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q511 = q510 - vec3(0.049795, 0.100575, 0.060337);
        vec3 id512 = clamp(round(q511 / vec3(0.147901, 1.0, 0.147901) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q513 = q511 - vec3(0.147901, 1.0, 0.147901) * (id512 - vec3(3.5, 0.0, 3.5));
        vec3 q514 = q513 - vec3(-0.032795, -0.100575, -0.031337);
        vec3 q515 = q514 * mat3(0.690859, 0.0, -0.722989, 0.0, 1.0, 0.0, 0.722989, 0.0, 0.690859);
        vec3 q516 = q515 * mat3(1.0, 0.0, 0.0, 0.0, 0.911577, 0.411129, 0.0, -0.411129, 0.911577);
        vec3 q517 = q516 - vec3(0.0, 0.110331, 0.0);
        vec3 q518 = q517 / vec3(1.0, 1.0, 0.5);
        M m519 = M(sdPyramid((q518 + vec3(0.0, 0.110331, 0.0)) / 0.075092, 2.938537) * 0.075092, vec3(0.358365, 0.273669, 0.063568), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m520 = m519; m520.d = m519.d * 0.5;
        vec3 q521 = q493 - vec3(0.0, 2.0, 0.0);
        M m522 = M(sdBox(q521, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m523 = mI(m520, m522);
        u495 = mU(u495, m523);
      }
      if (sdBox(q493 - vec3(0.017564, 0.147778, 0.021212), vec3(0.492436, 0.157778, 0.488788)) < u495.d) {
        vec3 q524 = q493 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q525 = q524 - vec3(0.087499, 0.143315, 0.068062);
        vec3 id526 = clamp(round(q525 / vec3(0.17863, 1.0, 0.17863) + vec3(2.5, 0.0, 2.5)), vec3(0.0), vec3(5.0, 0.0, 5.0));
        vec3 q527 = q525 - vec3(0.17863, 1.0, 0.17863) * (id526 - vec3(2.5, 0.0, 2.5));
        vec3 q528 = q527 - vec3(-0.053499, -0.143315, -0.010062);
        vec3 q529 = q528 * mat3(0.18484, 0.0, -0.982769, 0.0, 1.0, 0.0, 0.982769, 0.0, 0.18484);
        vec3 q530 = q529 * mat3(1.0, 0.0, 0.0, 0.0, 0.934832, 0.35509, 0.0, -0.35509, 0.934832);
        vec3 q531 = q530 - vec3(0.0, 0.153306, 0.0);
        vec3 q532 = q531 / vec3(1.0, 1.0, 0.5);
        M m533 = M(sdPyramid((q532 + vec3(0.0, 0.153306, 0.0)) / 0.100529, 3.049988) * 0.100529, vec3(0.530595, 0.415118, 0.104958), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m534 = m533; m534.d = m533.d * 0.5;
        vec3 q535 = q493 - vec3(0.0, 2.0, 0.0);
        M m536 = M(sdBox(q535, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m537 = mI(m534, m536);
        u495 = mU(u495, m537);
      }
      if (sdBox(q493 - vec3(0.037771, 0.163266, 0.006443), vec3(0.472229, 0.173266, 0.503557)) < u495.d) {
        vec3 q538 = q493 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q539 = q538 - vec3(0.109421, 0.15888, 0.044487);
        vec3 id540 = clamp(round(q539 / vec3(0.205823, 1.0, 0.205823) + vec3(2.0, 0.0, 2.0)), vec3(0.0), vec3(4.0, 0.0, 4.0));
        vec3 q541 = q539 - vec3(0.205823, 1.0, 0.205823) * (id540 - vec3(2.0, 0.0, 2.0));
        vec3 q542 = q541 - vec3(-0.058421, -0.15888, 0.042513);
        vec3 q543 = q542 * mat3(-0.588395, 0.0, -0.808573, 0.0, 1.0, 0.0, 0.808573, 0.0, -0.588395);
        vec3 q544 = q543 * mat3(1.0, 0.0, 0.0, 0.0, 0.910294, 0.413962, 0.0, -0.413962, 0.910294);
        vec3 q545 = q544 - vec3(0.0, 0.174537, 0.0);
        vec3 q546 = q545 / vec3(1.0, 1.0, 0.5);
        M m547 = M(sdPyramid((q546 + vec3(0.0, 0.174537, 0.0)) / 0.084759, 4.118421) * 0.084759, vec3(0.697305, 0.510376, 0.131567), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m548 = m547; m548.d = m547.d * 0.5;
        vec3 q549 = q493 - vec3(0.0, 2.0, 0.0);
        M m550 = M(sdBox(q549, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m551 = mI(m548, m550);
        u495 = mU(u495, m551);
      }
      u494 = mU(u494, u495);
    }
    {
      vec3 q552 = q493 - vec3(0.0, -0.02, 0.0);
      M m553 = M(sdBox(q552, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u494 = mU(u494, m553);
    }
    u0 = mU(u0, u494);
  }
  if (cullVis(4) && sdBox(p - vec3(0.0, 0.152274, 0.56), vec3(0.51, 0.202274, 0.51)) < u0.d) {
    vec3 q554 = p - vec3(0.0, 0.0, 0.56);
    M u555 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q554 - vec3(0.0, 0.172274, 0.0), vec3(0.51, 0.182274, 0.51)) < u555.d) {
      M u556 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q554 - vec3(0.0, 0.087229, 0.0), vec3(0.51, 0.097229, 0.51)) < u556.d) {
        vec3 q557 = q554 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q558 = q557 - vec3(-0.004845, 0.086666, 0.021773);
        vec3 id559 = clamp(round(q558 / vec3(0.069449, 1.0, 0.069449) + vec3(8.0, 0.0, 8.0)), vec3(0.0), vec3(16.0, 0.0, 16.0));
        vec3 q560 = q558 - vec3(0.069449, 1.0, 0.069449) * (id559 - vec3(8.0, 0.0, 8.0));
        vec3 q561 = q560 - vec3(0.004845, -0.086666, -0.021773);
        vec3 q562 = q561 * mat3(0.976127, 0.0, 0.217202, 0.0, 1.0, 0.0, -0.217202, 0.0, 0.976127);
        vec3 q563 = q562 * mat3(1.0, 0.0, 0.0, 0.0, 0.968438, 0.249254, 0.0, -0.249254, 0.968438);
        vec3 q564 = q563 - vec3(0.0, 0.08949, 0.0);
        vec3 q565 = q564 / vec3(1.0, 1.0, 0.16);
        M m566 = M(sdPyramid((q565 + vec3(0.0, 0.08949, 0.0)) / 0.056535, 3.165823) * 0.056535, vec3(0.099335, 0.067071, 0.012978), vec3(0.6, 0.0, 0.0), vec3(0.853245, 0.695203, 0.162199), vec4(7.0, 0.175586, 1.0, 0.0), (q561 - vec3(0.0, -0.001127, 0.0)), 0.0);
        M m567 = m566; m567.d = m566.d * 0.16;
        vec3 q568 = q554 - vec3(0.0, 2.0, 0.0);
        M m569 = M(sdBox(q568, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m570 = mI(m567, m569);
        u556 = mU(u556, m570);
      }
      if (sdBox(q554 - vec3(0.0, 0.094325, 0.0), vec3(0.51, 0.104325, 0.51)) < u556.d) {
        vec3 q571 = q554 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q572 = q571 - vec3(0.053444, 0.093368, 0.051529);
        vec3 id573 = clamp(round(q572 / vec3(0.114554, 1.0, 0.114554) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q574 = q572 - vec3(0.114554, 1.0, 0.114554) * (id573 - vec3(4.5, 0.0, 4.5));
        vec3 q575 = q574 - vec3(-0.036444, -0.093368, -0.022529);
        vec3 q576 = q575 * mat3(0.525824, 0.0, -0.850593, 0.0, 1.0, 0.0, 0.850593, 0.0, 0.525824);
        vec3 q577 = q576 * mat3(1.0, 0.0, 0.0, 0.0, 0.908873, 0.417072, 0.0, -0.417072, 0.908873);
        vec3 q578 = q577 - vec3(0.0, 0.102729, 0.0);
        vec3 q579 = q578 / vec3(1.0, 1.0, 0.16);
        M m580 = M(sdPyramid((q579 + vec3(0.0, 0.102729, 0.0)) / 0.057365, 3.58156) * 0.057365, vec3(0.135098, 0.094011, 0.012921), vec3(0.6, 0.0, 0.0), vec3(0.935023, 0.658371, 0.15905), vec4(7.0, 0.190563, 1.0, 0.0), (q575 - vec3(0.0, -0.001914, 0.0)), 0.0);
        M m581 = m580; m581.d = m580.d * 0.16;
        vec3 q582 = q554 - vec3(0.0, 2.0, 0.0);
        M m583 = M(sdBox(q582, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m584 = mI(m581, m583);
        u556 = mU(u556, m584);
      }
      if (sdBox(q554 - vec3(0.0, 0.118625, 0.0), vec3(0.51, 0.128625, 0.51)) < u556.d) {
        vec3 q585 = q554 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q586 = q585 - vec3(0.06909, 0.117928, 0.050129);
        vec3 id587 = clamp(round(q586 / vec3(0.095855, 1.0, 0.095855) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q588 = q586 - vec3(0.095855, 1.0, 0.095855) * (id587 - vec3(5.5, 0.0, 5.5));
        vec3 q589 = q588 - vec3(-0.03509, -0.117928, 0.007871);
        vec3 q590 = q589 * mat3(-0.218871, 0.0, -0.975754, 0.0, 1.0, 0.0, 0.975754, 0.0, -0.218871);
        vec3 q591 = q590 * mat3(1.0, 0.0, 0.0, 0.0, 0.956513, 0.291689, 0.0, -0.291689, 0.956513);
        vec3 q592 = q591 - vec3(0.0, 0.12329, 0.0);
        vec3 q593 = q592 / vec3(1.0, 1.0, 0.16);
        M m594 = M(sdPyramid((q593 + vec3(0.0, 0.12329, 0.0)) / 0.059716, 4.129206) * 0.059716, vec3(0.147392, 0.096165, 0.013686), vec3(0.6, 0.0, 0.0), vec3(0.644781, 0.455595, 0.144022), vec4(7.0, 0.238643, 1.0, 0.0), (q589 - vec3(0.0, -0.001393, 0.0)), 0.0);
        M m595 = m594; m595.d = m594.d * 0.16;
        vec3 q596 = q554 - vec3(0.0, 2.0, 0.0);
        M m597 = M(sdBox(q596, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m598 = mI(m595, m597);
        u556 = mU(u556, m598);
      }
      if (sdBox(q554 - vec3(0.0, 0.116004, 0.0), vec3(0.51, 0.126004, 0.51)) < u556.d) {
        vec3 q599 = q554 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q600 = q599 - vec3(0.093268, 0.114958, 0.052942);
        vec3 id601 = clamp(round(q600 / vec3(0.135096, 1.0, 0.135096) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q602 = q600 - vec3(0.135096, 1.0, 0.135096) * (id601 - vec3(4.0, 0.0, 4.0));
        vec3 q603 = q602 - vec3(-0.042268, -0.114958, 0.034058);
        vec3 q604 = q603 * mat3(-0.627432, 0.0, -0.778671, 0.0, 1.0, 0.0, 0.778671, 0.0, -0.627432);
        vec3 q605 = q604 * mat3(1.0, 0.0, 0.0, 0.0, 0.904259, 0.426985, 0.0, -0.426985, 0.904259);
        vec3 q606 = q605 - vec3(0.0, 0.127129, 0.0);
        vec3 q607 = q606 / vec3(1.0, 1.0, 0.16);
        M m608 = M(sdPyramid((q607 + vec3(0.0, 0.127129, 0.0)) / 0.061295, 4.148072) * 0.061295, vec3(0.124915, 0.095621, 0.017254), vec3(0.6, 0.0, 0.0), vec3(0.831164, 0.649026, 0.2508), vec4(7.0, 0.234103, 1.0, 0.0), (q603 - vec3(0.0, -0.002094, 0.0)), 0.0);
        M m609 = m608; m609.d = m608.d * 0.16;
        vec3 q610 = q554 - vec3(0.0, 2.0, 0.0);
        M m611 = M(sdBox(q610, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m612 = mI(m609, m611);
        u556 = mU(u556, m612);
      }
      if (sdBox(q554 - vec3(0.0, 0.133277, 0.0), vec3(0.51, 0.143277, 0.51)) < u556.d) {
        vec3 q613 = q554 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q614 = q613 - vec3(0.056773, 0.132725, 0.087656);
        vec3 id615 = clamp(round(q614 / vec3(0.09188, 1.0, 0.09188) + vec3(6.0, 0.0, 6.0)), vec3(0.0), vec3(12.0, 0.0, 12.0));
        vec3 q616 = q614 - vec3(0.09188, 1.0, 0.09188) * (id615 - vec3(6.0, 0.0, 6.0));
        vec3 q617 = q616 - vec3(0.011227, -0.132725, 0.028344);
        vec3 q618 = q617 * mat3(-0.929726, 0.0, 0.368253, 0.0, 1.0, 0.0, -0.368253, 0.0, -0.929726);
        vec3 q619 = q618 * mat3(1.0, 0.0, 0.0, 0.0, 0.974619, 0.22387, 0.0, -0.22387, 0.974619);
        vec3 q620 = q619 - vec3(0.0, 0.136181, 0.0);
        vec3 q621 = q620 / vec3(1.0, 1.0, 0.16);
        M m622 = M(sdPyramid((q621 + vec3(0.0, 0.136181, 0.0)) / 0.061682, 4.415599) * 0.061682, vec3(0.127119, 0.093904, 0.010027), vec3(0.6, 0.0, 0.0), vec3(0.790873, 0.516908, 0.146082), vec4(7.0, 0.267659, 1.0, 0.0), (q617 - vec3(0.0, -0.001105, 0.0)), 0.0);
        M m623 = m622; m623.d = m622.d * 0.16;
        vec3 q624 = q554 - vec3(0.0, 2.0, 0.0);
        M m625 = M(sdBox(q624, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m626 = mI(m623, m625);
        u556 = mU(u556, m626);
      }
      if (sdBox(q554 - vec3(0.0, 0.126973, 0.0), vec3(0.51, 0.136973, 0.51)) < u556.d) {
        vec3 q627 = q554 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q628 = q627 - vec3(0.039864, 0.125678, 0.091444);
        vec3 id629 = clamp(round(q628 / vec3(0.163372, 1.0, 0.163372) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q630 = q628 - vec3(0.163372, 1.0, 0.163372) * (id629 - vec3(3.0, 0.0, 3.0));
        vec3 q631 = q630 - vec3(0.045136, -0.125678, 0.053556);
        vec3 q632 = q631 * mat3(-0.764654, 0.0, 0.644441, 0.0, 1.0, 0.0, -0.644441, 0.0, -0.764654);
        vec3 q633 = q632 * mat3(1.0, 0.0, 0.0, 0.0, 0.873511, 0.486804, 0.0, -0.486804, 0.873511);
        vec3 q634 = q633 - vec3(0.0, 0.143877, 0.0);
        vec3 q635 = q634 / vec3(1.0, 1.0, 0.16);
        M m636 = M(sdPyramid((q635 + vec3(0.0, 0.143877, 0.0)) / 0.066519, 4.325904) * 0.066519, vec3(0.16725, 0.112447, 0.012561), vec3(0.6, 0.0, 0.0), vec3(0.725983, 0.505599, 0.098397), vec4(7.0, 0.256537, 1.0, 0.0), (q631 - vec3(0.0, -0.002591, 0.0)), 0.0);
        M m637 = m636; m637.d = m636.d * 0.16;
        vec3 q638 = q554 - vec3(0.0, 2.0, 0.0);
        M m639 = M(sdBox(q638, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m640 = mI(m637, m639);
        u556 = mU(u556, m640);
      }
      if (sdBox(q554 - vec3(0.0, 0.172274, 0.0), vec3(0.51, 0.182274, 0.51)) < u556.d) {
        vec3 q641 = q554 * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q642 = q641 - vec3(0.04491, 0.171518, 0.192597);
        vec3 id643 = clamp(round(q642 / vec3(0.145713, 1.0, 0.145713) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q644 = q642 - vec3(0.145713, 1.0, 0.145713) * (id643 - vec3(3.5, 0.0, 3.5));
        vec3 q645 = q644 - vec3(0.05709, -0.171518, -0.018597);
        vec3 q646 = q645 * mat3(0.309724, 0.0, 0.950827, 0.0, 1.0, 0.0, -0.950827, 0.0, 0.309724);
        vec3 q647 = q646 * mat3(1.0, 0.0, 0.0, 0.0, 0.943839, 0.330407, 0.0, -0.330407, 0.943839);
        vec3 q648 = q647 - vec3(0.0, 0.181724, 0.0);
        vec3 q649 = q648 / vec3(1.0, 1.0, 0.16);
        M m650 = M(sdPyramid((q649 + vec3(0.0, 0.181724, 0.0)) / 0.057196, 6.354385) * 0.057196, vec3(0.144686, 0.095689, 0.022755), vec3(0.6, 0.0, 0.0), vec3(0.662147, 0.502629, 0.102959), vec4(7.0, 0.346061, 1.0, 0.0), (q645 - vec3(0.0, -0.001512, 0.0)), 0.0);
        M m651 = m650; m651.d = m650.d * 0.16;
        vec3 q652 = q554 - vec3(0.0, 2.0, 0.0);
        M m653 = M(sdBox(q652, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m654 = mI(m651, m653);
        u556 = mU(u556, m654);
      }
      if (sdBox(q554 - vec3(0.015005, 0.163039, 0.032964), vec3(0.494995, 0.173039, 0.477036)) < u556.d) {
        vec3 q655 = q554 * mat3(0.920505, 0.0, -0.390731, 0.0, 1.0, 0.0, 0.390731, 0.0, 0.920505);
        vec3 q656 = q655 - vec3(0.07648, 0.161785, 0.284369);
        vec3 id657 = clamp(round(q656 / vec3(0.208004, 1.0, 0.208004) + vec3(2.0, 0.0, 2.0)), vec3(0.0), vec3(4.0, 0.0, 4.0));
        vec3 q658 = q656 - vec3(0.208004, 1.0, 0.208004) * (id657 - vec3(2.0, 0.0, 2.0));
        vec3 q659 = q658 - vec3(0.04252, -0.161785, -0.081369);
        vec3 q660 = q659 * mat3(0.886289, 0.0, 0.463133, 0.0, 1.0, 0.0, -0.463133, 0.0, 0.886289);
        vec3 q661 = q660 * mat3(1.0, 0.0, 0.0, 0.0, 0.869721, 0.493544, 0.0, -0.493544, 0.869721);
        vec3 q662 = q661 - vec3(0.0, 0.186019, 0.0);
        vec3 q663 = q662 / vec3(1.0, 1.0, 0.16);
        M m664 = M(sdPyramid((q663 + vec3(0.0, 0.186019, 0.0)) / 0.063543, 5.854871) * 0.063543, vec3(0.177927, 0.116545, 0.016689), vec3(0.6, 0.0, 0.0), vec3(0.880813, 0.56788, 0.121023), vec4(7.0, 0.328587, 1.0, 0.0), (q659 - vec3(0.0, -0.002509, 0.0)), 0.0);
        M m665 = m664; m665.d = m664.d * 0.16;
        vec3 q666 = q554 - vec3(0.0, 2.0, 0.0);
        M m667 = M(sdBox(q666, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m668 = mI(m665, m667);
        u556 = mU(u556, m668);
      }
      u555 = mU(u555, u556);
    }
    {
      vec3 q669 = q554 - vec3(0.0, -0.02, 0.0);
      M m670 = M(sdBox(q669, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u555 = mU(u555, m670);
    }
    u0 = mU(u0, u555);
  }
  if (cullVis(5) && sdBox(p - vec3(1.12, 0.133434, 0.56), vec3(0.51, 0.183434, 0.51)) < u0.d) {
    vec3 q671 = p - vec3(1.12, 0.0, 0.56);
    M u672 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q671 - vec3(0.0, 0.153434, 0.0), vec3(0.51, 0.163434, 0.51)) < u672.d) {
      M u673 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q671 - vec3(0.0, 0.078152, 0.0), vec3(0.51, 0.088152, 0.51)) < u673.d) {
        vec3 q674 = q671 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q675 = q674 - vec3(0.000686, 0.077954, 0.032455);
        vec3 id676 = clamp(round(q675 / vec3(0.072848, 1.0, 0.072848) + vec3(7.5, 0.0, 7.5)), vec3(0.0), vec3(15.0, 0.0, 15.0));
        vec3 q677 = q675 - vec3(0.072848, 1.0, 0.072848) * (id676 - vec3(7.5, 0.0, 7.5));
        vec3 q678 = q677 - vec3(-0.000686, -0.077954, -0.032455);
        vec3 q679 = q678 * mat3(0.997921, 0.0, -0.064452, 0.0, 1.0, 0.0, 0.064452, 0.0, 0.997921);
        M u680 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q681 = q679 * mat3(1.0, 0.0, 0.0, 0.0, 0.968604, 0.24861, 0.0, -0.24861, 0.968604);
          vec3 q682 = q681 - vec3(0.0, 0.042816, 0.0);
          vec3 q683 = q682 / vec3(1.0, 1.0, 0.1);
          M m684 = M(sdCone(q683, 0.042816, 0.015938, 0.008208), vec3(0.195183, 0.12243, 0.018882), vec3(0.6, 0.0, 0.0), vec3(0.645373, 0.421328, 0.067488), vec4(7.0, 0.1567, 1.0, 0.0), (q678 - vec3(0.0, -0.000396, 0.0)), 0.0);
          M m685 = m684; m685.d = m684.d * 0.1;
          u680 = mU(u680, m685);
        }
        {
          vec3 q686 = q679 - vec3(0.0, 0.082943, 0.021289);
          vec3 q687 = q686 * mat3(1.0, 0.0, 0.0, 0.0, 0.85109, 0.52502, 0.0, -0.52502, 0.85109);
          vec3 q688 = q687 - vec3(0.0, 0.042816, 0.0);
          vec3 q689 = q688 / vec3(1.0, 1.0, 0.1);
          M m690 = M(sdCone(q689, 0.042816, 0.009164, 0.000638), vec3(0.195183, 0.12243, 0.018882), vec3(0.6, 0.0, 0.0), vec3(0.645373, 0.421328, 0.067488), vec4(7.0, 0.1567, 1.0, 0.0), (q678 - vec3(0.0, -0.000396, 0.0)), 0.0);
          M m691 = m690; m691.d = m690.d * 0.1;
          u680 = mU(u680, m691);
        }
        vec3 q692 = q671 - vec3(0.0, 2.0, 0.0);
        M m693 = M(sdBox(q692, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m694 = mI(u680, m693);
        u673 = mU(u673, m694);
      }
      if (sdBox(q671 - vec3(0.0, 0.075559, 0.0), vec3(0.51, 0.085559, 0.51)) < u673.d) {
        vec3 q695 = q671 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q696 = q695 - vec3(0.044468, 0.075249, 0.074916);
        vec3 id697 = clamp(round(q696 / vec3(0.115621, 1.0, 0.115621) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q698 = q696 - vec3(0.115621, 1.0, 0.115621) * (id697 - vec3(4.5, 0.0, 4.5));
        vec3 q699 = q698 - vec3(-0.027468, -0.075249, -0.045916);
        vec3 q700 = q699 * mat3(0.844191, 0.0, -0.536043, 0.0, 1.0, 0.0, 0.536043, 0.0, 0.844191);
        M u701 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q702 = q700 * mat3(1.0, 0.0, 0.0, 0.0, 0.919058, 0.394122, 0.0, -0.394122, 0.919058);
          vec3 q703 = q702 - vec3(0.0, 0.048599, 0.0);
          vec3 q704 = q703 / vec3(1.0, 1.0, 0.1);
          M m705 = M(sdCone(q704, 0.048599, 0.015761, 0.008117), vec3(0.24276, 0.176518, 0.039003), vec3(0.6, 0.0, 0.0), vec3(0.925095, 0.591857, 0.126068), vec4(7.0, 0.151739, 1.0, 0.0), (q699 - vec3(0.0, -0.000621, 0.0)), 0.0);
          M m706 = m705; m706.d = m705.d * 0.1;
          u701 = mU(u701, m706);
        }
        {
          vec3 q707 = q700 - vec3(0.0, 0.08933, 0.038308);
          vec3 q708 = q707 * mat3(1.0, 0.0, 0.0, 0.0, 0.628443, 0.777855, 0.0, -0.777855, 0.628443);
          vec3 q709 = q708 - vec3(0.0, 0.048599, 0.0);
          vec3 q710 = q709 / vec3(1.0, 1.0, 0.1);
          M m711 = M(sdCone(q710, 0.048599, 0.009063, 0.00063), vec3(0.24276, 0.176518, 0.039003), vec3(0.6, 0.0, 0.0), vec3(0.925095, 0.591857, 0.126068), vec4(7.0, 0.151739, 1.0, 0.0), (q699 - vec3(0.0, -0.000621, 0.0)), 0.0);
          M m712 = m711; m712.d = m711.d * 0.1;
          u701 = mU(u701, m712);
        }
        vec3 q713 = q671 - vec3(0.0, 2.0, 0.0);
        M m714 = M(sdBox(q713, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m715 = mI(u701, m714);
        u673 = mU(u673, m715);
      }
      if (sdBox(q671 - vec3(0.0, 0.070099, 0.0034), vec3(0.51, 0.080099, 0.5066)) < u673.d) {
        vec3 q716 = q671 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q717 = q716 - vec3(0.09477, 0.069841, 0.060571);
        vec3 id718 = clamp(round(q717 / vec3(0.130632, 1.0, 0.130632) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q719 = q717 - vec3(0.130632, 1.0, 0.130632) * (id718 - vec3(4.0, 0.0, 4.0));
        vec3 q720 = q719 - vec3(-0.06077, -0.069841, -0.002571);
        vec3 q721 = q720 * mat3(0.082832, 0.0, -0.996564, 0.0, 1.0, 0.0, 0.996564, 0.0, 0.082832);
        M u722 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q723 = q721 * mat3(1.0, 0.0, 0.0, 0.0, 0.899785, 0.436333, 0.0, -0.436333, 0.899785);
          vec3 q724 = q723 - vec3(0.0, 0.048292, 0.0);
          vec3 q725 = q724 / vec3(1.0, 1.0, 0.1);
          M m726 = M(sdCone(q725, 0.048292, 0.011792, 0.006073), vec3(0.137876, 0.101537, 0.031103), vec3(0.6, 0.0, 0.0), vec3(0.572571, 0.491285, 0.177892), vec4(7.0, 0.140712, 1.0, 0.0), (q720 - vec3(0.0, -0.000515, 0.0)), 0.0);
          M m727 = m726; m727.d = m726.d * 0.1;
          u722 = mU(u722, m727);
        }
        {
          vec3 q728 = q721 - vec3(0.0, 0.086905, 0.042143);
          vec3 q729 = q728 * mat3(1.0, 0.0, 0.0, 0.0, 0.545892, 0.837856, 0.0, -0.837856, 0.545892);
          vec3 q730 = q729 - vec3(0.0, 0.048292, 0.0);
          vec3 q731 = q730 / vec3(1.0, 1.0, 0.1);
          M m732 = M(sdCone(q731, 0.048292, 0.00678, 0.000472), vec3(0.137876, 0.101537, 0.031103), vec3(0.6, 0.0, 0.0), vec3(0.572571, 0.491285, 0.177892), vec4(7.0, 0.140712, 1.0, 0.0), (q720 - vec3(0.0, -0.000515, 0.0)), 0.0);
          M m733 = m732; m733.d = m732.d * 0.1;
          u722 = mU(u722, m733);
        }
        vec3 q734 = q671 - vec3(0.0, 2.0, 0.0);
        M m735 = M(sdBox(q734, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m736 = mI(u722, m735);
        u673 = mU(u673, m736);
      }
      if (sdBox(q671 - vec3(0.0, 0.102312, 0.0), vec3(0.51, 0.112312, 0.51)) < u673.d) {
        vec3 q737 = q671 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q738 = q737 - vec3(0.071697, 0.102103, 0.036892);
        vec3 id739 = clamp(round(q738 / vec3(0.118195, 1.0, 0.118195) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q740 = q738 - vec3(0.118195, 1.0, 0.118195) * (id739 - vec3(4.5, 0.0, 4.5));
        vec3 q741 = q740 - vec3(-0.020697, -0.102103, 0.050108);
        vec3 q742 = q741 * mat3(-0.910483, 0.0, -0.413547, 0.0, 1.0, 0.0, 0.413547, 0.0, -0.910483);
        M u743 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q744 = q742 * mat3(1.0, 0.0, 0.0, 0.0, 0.950238, 0.311526, 0.0, -0.311526, 0.950238);
          vec3 q745 = q744 - vec3(0.0, 0.059442, 0.0);
          vec3 q746 = q745 / vec3(1.0, 1.0, 0.1);
          M m747 = M(sdCone(q746, 0.059442, 0.013431, 0.006917), vec3(0.091361, 0.064017, 0.01478), vec3(0.6, 0.0, 0.0), vec3(1.0, 0.771708, 0.144067), vec4(7.0, 0.205043, 1.0, 0.0), (q741 - vec3(0.0, -0.000418, 0.0)), 0.0);
          M m748 = m747; m748.d = m747.d * 0.1;
          u743 = mU(u743, m748);
        }
        {
          vec3 q749 = q742 - vec3(0.0, 0.112969, 0.037036);
          vec3 q750 = q749 * mat3(1.0, 0.0, 0.0, 0.0, 0.766799, 0.641888, 0.0, -0.641888, 0.766799);
          vec3 q751 = q750 - vec3(0.0, 0.059442, 0.0);
          vec3 q752 = q751 / vec3(1.0, 1.0, 0.1);
          M m753 = M(sdCone(q752, 0.059442, 0.007723, 0.000537), vec3(0.091361, 0.064017, 0.01478), vec3(0.6, 0.0, 0.0), vec3(1.0, 0.771708, 0.144067), vec4(7.0, 0.205043, 1.0, 0.0), (q741 - vec3(0.0, -0.000418, 0.0)), 0.0);
          M m754 = m753; m754.d = m753.d * 0.1;
          u743 = mU(u743, m754);
        }
        vec3 q755 = q671 - vec3(0.0, 2.0, 0.0);
        M m756 = M(sdBox(q755, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m757 = mI(u743, m756);
        u673 = mU(u673, m757);
      }
      if (sdBox(q671 - vec3(0.0, 0.094456, 0.0), vec3(0.51, 0.104456, 0.51)) < u673.d) {
        vec3 q758 = q671 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q759 = q758 - vec3(0.069158, 0.094142, 0.046374);
        vec3 id760 = clamp(round(q759 / vec3(0.149548, 1.0, 0.149548) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q761 = q759 - vec3(0.149548, 1.0, 0.149548) * (id760 - vec3(3.5, 0.0, 3.5));
        vec3 q762 = q761 - vec3(-0.001158, -0.094142, 0.069626);
        vec3 q763 = q762 * mat3(-0.998797, 0.0, -0.049044, 0.0, 1.0, 0.0, 0.049044, 0.0, -0.998797);
        M u764 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q765 = q763 * mat3(1.0, 0.0, 0.0, 0.0, 0.92062, 0.39046, 0.0, -0.39046, 0.92062);
          vec3 q766 = q765 - vec3(0.0, 0.06048, 0.0);
          vec3 q767 = q766 / vec3(1.0, 1.0, 0.1);
          M m768 = M(sdCone(q767, 0.06048, 0.016115, 0.008299), vec3(0.108061, 0.078267, 0.012155), vec3(0.6, 0.0, 0.0), vec3(0.538713, 0.415174, 0.098643), vec4(7.0, 0.189542, 1.0, 0.0), (q762 - vec3(0.0, -0.000629, 0.0)), 0.0);
          M m769 = m768; m769.d = m768.d * 0.1;
          u764 = mU(u764, m769);
        }
        {
          vec3 q770 = q763 - vec3(0.0, 0.111359, 0.04723);
          vec3 q771 = q770 * mat3(1.0, 0.0, 0.0, 0.0, 0.635231, 0.772322, 0.0, -0.772322, 0.635231);
          vec3 q772 = q771 - vec3(0.0, 0.06048, 0.0);
          vec3 q773 = q772 / vec3(1.0, 1.0, 0.1);
          M m774 = M(sdCone(q773, 0.06048, 0.009266, 0.000645), vec3(0.108061, 0.078267, 0.012155), vec3(0.6, 0.0, 0.0), vec3(0.538713, 0.415174, 0.098643), vec4(7.0, 0.189542, 1.0, 0.0), (q762 - vec3(0.0, -0.000629, 0.0)), 0.0);
          M m775 = m774; m775.d = m774.d * 0.1;
          u764 = mU(u764, m775);
        }
        vec3 q776 = q671 - vec3(0.0, 2.0, 0.0);
        M m777 = M(sdBox(q776, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m778 = mI(u764, m777);
        u673 = mU(u673, m778);
      }
      if (sdBox(q671 - vec3(0.0, 0.124078, 0.0), vec3(0.51, 0.134078, 0.51)) < u673.d) {
        vec3 q779 = q671 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q780 = q779 - vec3(0.028213, 0.123879, 0.122126);
        vec3 id781 = clamp(round(q780 / vec3(0.131957, 1.0, 0.131957) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q782 = q780 - vec3(0.131957, 1.0, 0.131957) * (id781 - vec3(4.0, 0.0, 4.0));
        vec3 q783 = q782 - vec3(0.056787, -0.123879, 0.022874);
        vec3 q784 = q783 * mat3(-0.402937, 0.0, 0.915228, 0.0, 1.0, 0.0, -0.915228, 0.0, -0.402937);
        M u785 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q786 = q784 * mat3(1.0, 0.0, 0.0, 0.0, 0.956294, 0.292408, 0.0, -0.292408, 0.956294);
          vec3 q787 = q786 - vec3(0.0, 0.07074, 0.0);
          vec3 q788 = q787 / vec3(1.0, 1.0, 0.1);
          M m789 = M(sdCone(q788, 0.07074, 0.013566, 0.006986), vec3(0.225109, 0.161788, 0.044575), vec3(0.6, 0.0, 0.0), vec3(0.541274, 0.323412, 0.047336), vec4(7.0, 0.248552, 1.0, 0.0), (q783 - vec3(0.0, -0.000397, 0.0)), 0.0);
          M m790 = m789; m790.d = m789.d * 0.1;
          u785 = mU(u785, m790);
        }
        {
          vec3 q791 = q784 - vec3(0.0, 0.135296, 0.04137);
          vec3 q792 = q791 * mat3(1.0, 0.0, 0.0, 0.0, 0.794364, 0.607443, 0.0, -0.607443, 0.794364);
          vec3 q793 = q792 - vec3(0.0, 0.07074, 0.0);
          vec3 q794 = q793 / vec3(1.0, 1.0, 0.1);
          M m795 = M(sdCone(q794, 0.07074, 0.0078, 0.000543), vec3(0.225109, 0.161788, 0.044575), vec3(0.6, 0.0, 0.0), vec3(0.541274, 0.323412, 0.047336), vec4(7.0, 0.248552, 1.0, 0.0), (q783 - vec3(0.0, -0.000397, 0.0)), 0.0);
          M m796 = m795; m796.d = m795.d * 0.1;
          u785 = mU(u785, m796);
        }
        vec3 q797 = q671 - vec3(0.0, 2.0, 0.0);
        M m798 = M(sdBox(q797, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m799 = mI(u785, m798);
        u673 = mU(u673, m799);
      }
      if (sdBox(q671 - vec3(0.0, 0.120327, 0.0), vec3(0.51, 0.130327, 0.51)) < u673.d) {
        vec3 q800 = q671 * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q801 = q800 - vec3(0.047161, 0.120105, 0.18765);
        vec3 id802 = clamp(round(q801 / vec3(0.126643, 1.0, 0.126643) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q803 = q801 - vec3(0.126643, 1.0, 0.126643) * (id802 - vec3(4.0, 0.0, 4.0));
        vec3 q804 = q803 - vec3(0.054839, -0.120105, -0.01365);
        vec3 q805 = q804 * mat3(0.289412, 0.0, 0.957205, 0.0, 1.0, 0.0, -0.957205, 0.0, 0.289412);
        M u806 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q807 = q805 * mat3(1.0, 0.0, 0.0, 0.0, 0.959881, 0.280409, 0.0, -0.280409, 0.959881);
          vec3 q808 = q807 - vec3(0.0, 0.067805, 0.0);
          vec3 q809 = q808 / vec3(1.0, 1.0, 0.1);
          M m810 = M(sdCone(q809, 0.067805, 0.015859, 0.008168), vec3(0.198957, 0.142319, 0.045921), vec3(0.6, 0.0, 0.0), vec3(1.0, 0.776722, 0.300658), vec4(7.0, 0.241099, 1.0, 0.0), (q804 - vec3(0.0, -0.000445, 0.0)), 0.0);
          M m811 = m810; m811.d = m810.d * 0.1;
          u806 = mU(u806, m811);
        }
        {
          vec3 q812 = q805 - vec3(0.0, 0.130169, 0.038026);
          vec3 q813 = q812 * mat3(1.0, 0.0, 0.0, 0.0, 0.810796, 0.585328, 0.0, -0.585328, 0.810796);
          vec3 q814 = q813 - vec3(0.0, 0.067805, 0.0);
          vec3 q815 = q814 / vec3(1.0, 1.0, 0.1);
          M m816 = M(sdCone(q815, 0.067805, 0.009119, 0.000634), vec3(0.198957, 0.142319, 0.045921), vec3(0.6, 0.0, 0.0), vec3(1.0, 0.776722, 0.300658), vec4(7.0, 0.241099, 1.0, 0.0), (q804 - vec3(0.0, -0.000445, 0.0)), 0.0);
          M m817 = m816; m817.d = m816.d * 0.1;
          u806 = mU(u806, m817);
        }
        vec3 q818 = q671 - vec3(0.0, 2.0, 0.0);
        M m819 = M(sdBox(q818, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m820 = mI(u806, m819);
        u673 = mU(u673, m820);
      }
      if (sdBox(q671 - vec3(0.0, 0.089588, 0.0), vec3(0.51, 0.099588, 0.51)) < u673.d) {
        vec3 q821 = q671 * mat3(0.920505, 0.0, -0.390731, 0.0, 1.0, 0.0, 0.390731, 0.0, 0.920505);
        vec3 q822 = q821 - vec3(0.064766, 0.089206, 0.275257);
        vec3 id823 = clamp(round(q822 / vec3(0.172454, 1.0, 0.172454) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q824 = q822 - vec3(0.172454, 1.0, 0.172454) * (id823 - vec3(3.0, 0.0, 3.0));
        vec3 q825 = q824 - vec3(0.054234, -0.089206, -0.072257);
        vec3 q826 = q825 * mat3(0.793956, 0.0, 0.607976, 0.0, 1.0, 0.0, -0.607976, 0.0, 0.793956);
        M u827 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q828 = q826 * mat3(1.0, 0.0, 0.0, 0.0, 0.873963, 0.485992, 0.0, -0.485992, 0.873963);
          vec3 q829 = q828 - vec3(0.0, 0.067933, 0.0);
          vec3 q830 = q829 / vec3(1.0, 1.0, 0.1);
          M m831 = M(sdCone(q830, 0.067933, 0.015728, 0.0081), vec3(0.228736, 0.150632, 0.011465), vec3(0.6, 0.0, 0.0), vec3(0.912004, 0.611215, 0.082553), vec4(7.0, 0.179941, 1.0, 0.0), (q825 - vec3(0.0, -0.000764, 0.0)), 0.0);
          M m832 = m831; m832.d = m831.d * 0.1;
          u827 = mU(u827, m832);
        }
        {
          vec3 q833 = q826 - vec3(0.0, 0.118741, 0.06603);
          vec3 q834 = q833 * mat3(1.0, 0.0, 0.0, 0.0, 0.438835, 0.898568, 0.0, -0.898568, 0.438835);
          vec3 q835 = q834 - vec3(0.0, 0.067933, 0.0);
          vec3 q836 = q835 / vec3(1.0, 1.0, 0.1);
          M m837 = M(sdCone(q836, 0.067933, 0.009044, 0.000629), vec3(0.228736, 0.150632, 0.011465), vec3(0.6, 0.0, 0.0), vec3(0.912004, 0.611215, 0.082553), vec4(7.0, 0.179941, 1.0, 0.0), (q825 - vec3(0.0, -0.000764, 0.0)), 0.0);
          M m838 = m837; m838.d = m837.d * 0.1;
          u827 = mU(u827, m838);
        }
        vec3 q839 = q671 - vec3(0.0, 2.0, 0.0);
        M m840 = M(sdBox(q839, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m841 = mI(u827, m840);
        u673 = mU(u673, m841);
      }
      if (sdBox(q671 - vec3(0.020843, 0.142856, 0.0), vec3(0.489157, 0.152856, 0.51)) < u673.d) {
        vec3 q842 = q671 * mat3(0.882948, 0.0, -0.469472, 0.0, 1.0, 0.0, 0.469472, 0.0, 0.882948);
        vec3 q843 = q842 - vec3(0.153094, 0.142687, 0.295798);
        vec3 id844 = clamp(round(q843 / vec3(0.142478, 1.0, 0.142478) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q845 = q843 - vec3(0.142478, 1.0, 0.142478) * (id844 - vec3(3.5, 0.0, 3.5));
        vec3 q846 = q845 - vec3(-0.017094, -0.142687, -0.063798);
        vec3 q847 = q846 * mat3(0.956896, 0.0, -0.29043, 0.0, 1.0, 0.0, 0.29043, 0.0, 0.956896);
        M u848 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q849 = q847 * mat3(1.0, 0.0, 0.0, 0.0, 0.961832, 0.27364, 0.0, -0.27364, 0.961832);
          vec3 q850 = q849 - vec3(0.0, 0.08007, 0.0);
          vec3 q851 = q850 / vec3(1.0, 1.0, 0.1);
          M m852 = M(sdCone(q851, 0.08007, 0.012292, 0.00633), vec3(0.207204, 0.143847, 0.036713), vec3(0.6, 0.0, 0.0), vec3(0.695837, 0.526384, 0.264458), vec4(7.0, 0.286048, 1.0, 0.0), (q846 - vec3(0.0, -0.000336, 0.0)), 0.0);
          M m853 = m852; m853.d = m852.d * 0.1;
          u848 = mU(u848, m853);
        }
        {
          vec3 q854 = q847 - vec3(0.0, 0.154028, 0.043821);
          vec3 q855 = q854 * mat3(1.0, 0.0, 0.0, 0.0, 0.819771, 0.572692, 0.0, -0.572692, 0.819771);
          vec3 q856 = q855 - vec3(0.0, 0.08007, 0.0);
          vec3 q857 = q856 / vec3(1.0, 1.0, 0.1);
          M m858 = M(sdCone(q857, 0.08007, 0.007068, 0.000492), vec3(0.207204, 0.143847, 0.036713), vec3(0.6, 0.0, 0.0), vec3(0.695837, 0.526384, 0.264458), vec4(7.0, 0.286048, 1.0, 0.0), (q846 - vec3(0.0, -0.000336, 0.0)), 0.0);
          M m859 = m858; m859.d = m858.d * 0.1;
          u848 = mU(u848, m859);
        }
        vec3 q860 = q671 - vec3(0.0, 2.0, 0.0);
        M m861 = M(sdBox(q860, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m862 = mI(u848, m861);
        u673 = mU(u673, m862);
      }
      if (sdBox(q671 - vec3(0.054303, 0.153434, 0.0), vec3(0.455697, 0.163434, 0.51)) < u673.d) {
        vec3 q863 = q671 * mat3(0.838671, 0.0, -0.544639, 0.0, 1.0, 0.0, 0.544639, 0.0, 0.838671);
        vec3 q864 = q863 - vec3(0.217113, 0.153196, 0.312195);
        vec3 id865 = clamp(round(q864 / vec3(0.155651, 1.0, 0.155651) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q866 = q864 - vec3(0.155651, 1.0, 0.155651) * (id865 - vec3(3.0, 0.0, 3.0));
        vec3 q867 = q866 - vec3(-0.064113, -0.153196, -0.051195);
        vec3 q868 = q867 * mat3(0.630295, 0.0, -0.776356, 0.0, 1.0, 0.0, 0.776356, 0.0, 0.630295);
        M u869 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q870 = q868 * mat3(1.0, 0.0, 0.0, 0.0, 0.949696, 0.313175, 0.0, -0.313175, 0.949696);
          vec3 q871 = q870 - vec3(0.0, 0.089352, 0.0);
          vec3 q872 = q871 / vec3(1.0, 1.0, 0.1);
          M m873 = M(sdCone(q872, 0.089352, 0.015225, 0.007841), vec3(0.110088, 0.067593, 0.00532), vec3(0.6, 0.0, 0.0), vec3(0.582688, 0.427904, 0.084107), vec4(7.0, 0.307345, 1.0, 0.0), (q867 - vec3(0.0, -0.000477, 0.0)), 0.0);
          M m874 = m873; m874.d = m873.d * 0.1;
          u869 = mU(u869, m874);
        }
        {
          vec3 q875 = q868 - vec3(0.0, 0.169713, 0.055965);
          vec3 q876 = q875 * mat3(1.0, 0.0, 0.0, 0.0, 0.764343, 0.64481, 0.0, -0.64481, 0.764343);
          vec3 q877 = q876 - vec3(0.0, 0.089352, 0.0);
          vec3 q878 = q877 / vec3(1.0, 1.0, 0.1);
          M m879 = M(sdCone(q878, 0.089352, 0.008754, 0.000609), vec3(0.110088, 0.067593, 0.00532), vec3(0.6, 0.0, 0.0), vec3(0.582688, 0.427904, 0.084107), vec4(7.0, 0.307345, 1.0, 0.0), (q867 - vec3(0.0, -0.000477, 0.0)), 0.0);
          M m880 = m879; m880.d = m879.d * 0.1;
          u869 = mU(u869, m880);
        }
        vec3 q881 = q671 - vec3(0.0, 2.0, 0.0);
        M m882 = M(sdBox(q881, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m883 = mI(u869, m882);
        u673 = mU(u673, m883);
      }
      if (sdBox(q671 - vec3(0.077319, 0.149583, 0.0), vec3(0.432681, 0.159583, 0.51)) < u673.d) {
        vec3 q884 = q671 * mat3(0.788011, 0.0, -0.615661, 0.0, 1.0, 0.0, 0.615661, 0.0, 0.788011);
        vec3 q885 = q884 - vec3(0.273885, 0.149266, 0.278226);
        vec3 id886 = clamp(round(q885 / vec3(0.224359, 1.0, 0.224359) + vec3(2.0, 0.0, 2.0)), vec3(0.0), vec3(4.0, 0.0, 4.0));
        vec3 q887 = q885 - vec3(0.224359, 1.0, 0.224359) * (id886 - vec3(2.0, 0.0, 2.0));
        vec3 q888 = q887 - vec3(-0.103885, -0.149266, 0.011774);
        vec3 q889 = q888 * mat3(-0.145077, 0.0, -0.98942, 0.0, 1.0, 0.0, 0.98942, 0.0, -0.145077);
        M u890 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q891 = q889 * mat3(1.0, 0.0, 0.0, 0.0, 0.926434, 0.376458, 0.0, -0.376458, 0.926434);
          vec3 q892 = q891 - vec3(0.0, 0.094022, 0.0);
          vec3 q893 = q892 / vec3(1.0, 1.0, 0.1);
          M m894 = M(sdCone(q893, 0.094022, 0.016812, 0.008658), vec3(0.066788, 0.047864, 0.011202), vec3(0.6, 0.0, 0.0), vec3(0.687686, 0.441385, 0.069643), vec4(7.0, 0.299798, 1.0, 0.0), (q888 - vec3(0.0, -0.000633, 0.0)), 0.0);
          M m895 = m894; m895.d = m894.d * 0.1;
          u890 = mU(u890, m895);
        }
        {
          vec3 q896 = q889 - vec3(0.0, 0.174211, 0.070791);
          vec3 q897 = q896 * mat3(1.0, 0.0, 0.0, 0.0, 0.660634, 0.750708, 0.0, -0.750708, 0.660634);
          vec3 q898 = q897 - vec3(0.0, 0.094022, 0.0);
          vec3 q899 = q898 / vec3(1.0, 1.0, 0.1);
          M m900 = M(sdCone(q899, 0.094022, 0.009667, 0.000672), vec3(0.066788, 0.047864, 0.011202), vec3(0.6, 0.0, 0.0), vec3(0.687686, 0.441385, 0.069643), vec4(7.0, 0.299798, 1.0, 0.0), (q888 - vec3(0.0, -0.000633, 0.0)), 0.0);
          M m901 = m900; m901.d = m900.d * 0.1;
          u890 = mU(u890, m901);
        }
        vec3 q902 = q671 - vec3(0.0, 2.0, 0.0);
        M m903 = M(sdBox(q902, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m904 = mI(u890, m903);
        u673 = mU(u673, m904);
      }
      if (sdBox(q671 - vec3(0.025995, 0.141245, 0.0), vec3(0.484005, 0.151245, 0.51)) < u673.d) {
        vec3 q905 = q671 * mat3(0.731354, 0.0, -0.681998, 0.0, 1.0, 0.0, 0.681998, 0.0, 0.731354);
        vec3 q906 = q905 - vec3(0.257793, 0.140979, 0.216302);
        vec3 id907 = clamp(round(q906 / vec3(0.229718, 1.0, 0.229718) + vec3(2.0, 0.0, 2.0)), vec3(0.0), vec3(4.0, 0.0, 4.0));
        vec3 q908 = q906 - vec3(0.229718, 1.0, 0.229718) * (id907 - vec3(2.0, 0.0, 2.0));
        vec3 q909 = q908 - vec3(-0.070793, -0.140979, 0.102698);
        vec3 q910 = q909 * mat3(-0.819349, 0.0, -0.573295, 0.0, 1.0, 0.0, 0.573295, 0.0, -0.819349);
        M u911 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q912 = q910 * mat3(1.0, 0.0, 0.0, 0.0, 0.896266, 0.443516, 0.0, -0.443516, 0.896266);
          vec3 q913 = q912 - vec3(0.0, 0.098753, 0.0);
          vec3 q914 = q913 / vec3(1.0, 1.0, 0.1);
          M m915 = M(sdCone(q914, 0.098753, 0.011974, 0.006166), vec3(0.090143, 0.06077, 0.006416), vec3(0.6, 0.0, 0.0), vec3(0.715693, 0.584143, 0.264921), vec4(7.0, 0.28302, 1.0, 0.0), (q909 - vec3(0.0, -0.000531, 0.0)), 0.0);
          M m916 = m915; m916.d = m915.d * 0.1;
          u911 = mU(u911, m916);
        }
        {
          vec3 q917 = q910 - vec3(0.0, 0.177018, 0.087597);
          vec3 q918 = q917 * mat3(1.0, 0.0, 0.0, 0.0, 0.531065, 0.847331, 0.0, -0.847331, 0.531065);
          vec3 q919 = q918 - vec3(0.0, 0.098753, 0.0);
          vec3 q920 = q919 / vec3(1.0, 1.0, 0.1);
          M m921 = M(sdCone(q920, 0.098753, 0.006885, 0.000479), vec3(0.090143, 0.06077, 0.006416), vec3(0.6, 0.0, 0.0), vec3(0.715693, 0.584143, 0.264921), vec4(7.0, 0.28302, 1.0, 0.0), (q909 - vec3(0.0, -0.000531, 0.0)), 0.0);
          M m922 = m921; m922.d = m921.d * 0.1;
          u911 = mU(u911, m922);
        }
        vec3 q923 = q671 - vec3(0.0, 2.0, 0.0);
        M m924 = M(sdBox(q923, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m925 = mI(u911, m924);
        u673 = mU(u673, m925);
      }
      u672 = mU(u672, u673);
    }
    {
      vec3 q926 = q671 - vec3(0.0, -0.02, 0.0);
      M m927 = M(sdBox(q926, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u672 = mU(u672, m927);
    }
    u0 = mU(u0, u672);
  }
  return u0;
}
