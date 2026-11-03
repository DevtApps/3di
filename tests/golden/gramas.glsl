
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
    M m1 = M(p.y, vec3(0.026241, 0.017642, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  if (sdBox(p - vec3(-3.36, 0.043695, 0.0), vec3(0.51, 0.093695, 0.51)) < u0.d) {
    vec3 q2 = p - vec3(-3.36, 0.0, 0.0);
    M u3 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q2 - vec3(0.0, 0.063695, 0.0), vec3(0.51, 0.073695, 0.51)) < u3.d) {
      M u4 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q2 - vec3(0.0, 0.02621, 0.0), vec3(0.51, 0.03621, 0.51)) < u4.d) {
        vec3 q5 = q2 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q6 = q5 - vec3(-0.000729, 0.025915, 0.003888);
        vec3 id7 = clamp(round(q6 / vec3(0.052965, 1.0, 0.052965) + vec3(11.0, 0.0, 11.0)), vec3(0.0), vec3(22.0, 0.0, 22.0));
        vec3 q8 = q6 - vec3(0.052965, 1.0, 0.052965) * (id7 - vec3(11.0, 0.0, 11.0));
        vec3 q9 = q8 - vec3(0.000729, -0.025915, -0.003888);
        vec3 q10 = q9 * mat3(0.982891, 0.0, 0.18419, 0.0, 1.0, 0.0, -0.18419, 0.0, 0.982891);
        vec3 q11 = q10 * mat3(1.0, 0.0, 0.0, 0.0, 0.988549, 0.150903, 0.0, -0.150903, 0.988549);
        vec3 q12 = q11 - vec3(0.0, 0.026215, 0.0);
        vec3 q13 = q12 / vec3(1.0, 1.0, 0.16);
        M m14 = M(sdPyramid((q13 + vec3(0.0, 0.026215, 0.0)) / 0.048883, 1.072585) * 0.048883, vec3(0.008899, 0.090188, 0.010667), vec3(0.6, 0.0, 0.0), vec3(0.208068, 0.653587, 0.059358), vec4(7.0, 0.053011, 1.0, 0.0), (q9 - vec3(0.0, -0.00059, 0.0)), 0.0);
        M m15 = m14; m15.d = m14.d * 0.16;
        vec3 q16 = q2 - vec3(0.0, 2.0, 0.0);
        M m17 = M(sdBox(q16, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m18 = mI(m15, m17);
        u4 = mU(u4, m18);
      }
      if (sdBox(q2 - vec3(0.0, 0.03012, 0.0), vec3(0.51, 0.04012, 0.51)) < u4.d) {
        vec3 q19 = q2 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q20 = q19 - vec3(0.023236, 0.029528, 0.035403);
        vec3 id21 = clamp(round(q20 / vec3(0.056742, 1.0, 0.056742) + vec3(10.0, 0.0, 10.0)), vec3(0.0), vec3(20.0, 0.0, 20.0));
        vec3 q22 = q20 - vec3(0.056742, 1.0, 0.056742) * (id21 - vec3(10.0, 0.0, 10.0));
        vec3 q23 = q22 - vec3(-0.006236, -0.029528, -0.006403);
        vec3 q24 = q23 * mat3(0.716349, 0.0, -0.697742, 0.0, 1.0, 0.0, 0.697742, 0.0, 0.716349);
        vec3 q25 = q24 * mat3(1.0, 0.0, 0.0, 0.0, 0.957112, 0.28972, 0.0, -0.28972, 0.957112);
        vec3 q26 = q25 - vec3(0.0, 0.030851, 0.0);
        vec3 q27 = q26 / vec3(1.0, 1.0, 0.16);
        M m28 = M(sdPyramid((q27 + vec3(0.0, 0.030851, 0.0)) / 0.051126, 1.206858) * 0.051126, vec3(0.008922, 0.108187, 0.012477), vec3(0.6, 0.0, 0.0), vec3(0.164037, 0.530477, 0.042896), vec4(7.0, 0.061425, 1.0, 0.0), (q23 - vec3(0.0, -0.001185, 0.0)), 0.0);
        M m29 = m28; m29.d = m28.d * 0.16;
        vec3 q30 = q2 - vec3(0.0, 2.0, 0.0);
        M m31 = M(sdBox(q30, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m32 = mI(m29, m31);
        u4 = mU(u4, m32);
      }
      if (sdBox(q2 - vec3(0.0, 0.035501, 0.0), vec3(0.51, 0.045501, 0.51)) < u4.d) {
        vec3 q33 = q2 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q34 = q33 - vec3(0.040039, 0.035037, 0.058888);
        vec3 id35 = clamp(round(q34 / vec3(0.073045, 1.0, 0.073045) + vec3(7.5, 0.0, 7.5)), vec3(0.0), vec3(15.0, 0.0, 15.0));
        vec3 q36 = q34 - vec3(0.073045, 1.0, 0.073045) * (id35 - vec3(7.5, 0.0, 7.5));
        vec3 q37 = q36 - vec3(-0.006039, -0.035037, -0.000888);
        vec3 q38 = q37 * mat3(0.14548, 0.0, -0.989361, 0.0, 1.0, 0.0, 0.989361, 0.0, 0.14548);
        vec3 q39 = q38 * mat3(1.0, 0.0, 0.0, 0.0, 0.985163, 0.171624, 0.0, -0.171624, 0.985163);
        vec3 q40 = q39 - vec3(0.0, 0.035564, 0.0);
        vec3 q41 = q40 / vec3(1.0, 1.0, 0.16);
        M m42 = M(sdPyramid((q41 + vec3(0.0, 0.035564, 0.0)) / 0.067629, 1.051758) * 0.067629, vec3(0.005565, 0.084609, 0.008488), vec3(0.6, 0.0, 0.0), vec3(0.190853, 0.524514, 0.054971), vec4(7.0, 0.071931, 1.0, 0.0), (q37 - vec3(0.0, -0.000929, 0.0)), 0.0);
        M m43 = m42; m43.d = m42.d * 0.16;
        vec3 q44 = q2 - vec3(0.0, 2.0, 0.0);
        M m45 = M(sdBox(q44, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m46 = mI(m43, m45);
        u4 = mU(u4, m46);
      }
      if (sdBox(q2 - vec3(0.0, 0.044518, 0.0), vec3(0.51, 0.054518, 0.51)) < u4.d) {
        vec3 q47 = q2 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q48 = q47 - vec3(0.056038, 0.044159, 0.08279);
        vec3 id49 = clamp(round(q48 / vec3(0.063865, 1.0, 0.063865) + vec3(9.0, 0.0, 9.0)), vec3(0.0), vec3(18.0, 0.0, 18.0));
        vec3 q50 = q48 - vec3(0.063865, 1.0, 0.063865) * (id49 - vec3(9.0, 0.0, 9.0));
        vec3 q51 = q50 - vec3(-0.005038, -0.044159, 0.00421);
        vec3 q52 = q51 * mat3(-0.641199, 0.0, -0.767374, 0.0, 1.0, 0.0, 0.767374, 0.0, -0.641199);
        vec3 q53 = q52 * mat3(1.0, 0.0, 0.0, 0.0, 0.989126, 0.147071, 0.0, -0.147071, 0.989126);
        vec3 q54 = q53 - vec3(0.0, 0.044644, 0.0);
        vec3 q55 = q54 / vec3(1.0, 1.0, 0.16);
        M m56 = M(sdPyramid((q55 + vec3(0.0, 0.044644, 0.0)) / 0.060987, 1.464053) * 0.060987, vec3(0.009668, 0.068161, 0.010559), vec3(0.6, 0.0, 0.0), vec3(0.247514, 0.586741, 0.07402), vec4(7.0, 0.089753, 1.0, 0.0), (q51 - vec3(0.0, -0.000718, 0.0)), 0.0);
        M m57 = m56; m57.d = m56.d * 0.16;
        vec3 q58 = q2 - vec3(0.0, 2.0, 0.0);
        M m59 = M(sdBox(q58, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m60 = mI(m57, m59);
        u4 = mU(u4, m60);
      }
      if (sdBox(q2 - vec3(0.0, 0.049932, 0.0), vec3(0.51, 0.059932, 0.51)) < u4.d) {
        vec3 q61 = q2 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q62 = q61 - vec3(0.065352, 0.049454, 0.106076);
        vec3 id63 = clamp(round(q62 / vec3(0.067113, 1.0, 0.067113) + vec3(8.5, 0.0, 8.5)), vec3(0.0), vec3(17.0, 0.0, 17.0));
        vec3 q64 = q62 - vec3(0.067113, 1.0, 0.067113) * (id63 - vec3(8.5, 0.0, 8.5));
        vec3 q65 = q64 - vec3(0.002648, -0.049454, 0.009924);
        vec3 q66 = q65 * mat3(-0.966192, 0.0, 0.257822, 0.0, 1.0, 0.0, -0.257822, 0.0, -0.966192);
        vec3 q67 = q66 * mat3(1.0, 0.0, 0.0, 0.0, 0.979106, 0.203353, 0.0, -0.203353, 0.979106);
        vec3 q68 = q67 - vec3(0.0, 0.050509, 0.0);
        vec3 q69 = q68 / vec3(1.0, 1.0, 0.16);
        M m70 = M(sdPyramid((q69 + vec3(0.0, 0.050509, 0.0)) / 0.058848, 1.716584) * 0.058848, vec3(0.005066, 0.081765, 0.007689), vec3(0.6, 0.0, 0.0), vec3(0.209641, 0.603794, 0.060251), vec4(7.0, 0.100822, 1.0, 0.0), (q65 - vec3(0.0, -0.000957, 0.0)), 0.0);
        M m71 = m70; m71.d = m70.d * 0.16;
        vec3 q72 = q2 - vec3(0.0, 2.0, 0.0);
        M m73 = M(sdBox(q72, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m74 = mI(m71, m73);
        u4 = mU(u4, m74);
      }
      if (sdBox(q2 - vec3(0.0, 0.049441, 0.0), vec3(0.51, 0.059441, 0.51)) < u4.d) {
        vec3 q75 = q2 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q76 = q75 - vec3(0.080776, 0.049163, 0.141657);
        vec3 id77 = clamp(round(q76 / vec3(0.065503, 1.0, 0.065503) + vec3(8.5, 0.0, 8.5)), vec3(0.0), vec3(17.0, 0.0, 17.0));
        vec3 q78 = q76 - vec3(0.065503, 1.0, 0.065503) * (id77 - vec3(8.5, 0.0, 8.5));
        vec3 q79 = q78 - vec3(0.004224, -0.049163, 0.003343);
        vec3 q80 = q79 * mat3(-0.620577, 0.0, 0.784146, 0.0, 1.0, 0.0, -0.784146, 0.0, -0.620577);
        vec3 q81 = q80 * mat3(1.0, 0.0, 0.0, 0.0, 0.994052, 0.108908, 0.0, -0.108908, 0.994052);
        vec3 q82 = q81 - vec3(0.0, 0.049457, 0.0);
        vec3 q83 = q82 / vec3(1.0, 1.0, 0.16);
        M m84 = M(sdPyramid((q83 + vec3(0.0, 0.049457, 0.0)) / 0.06377, 1.551119) * 0.06377, vec3(0.008782, 0.07932, 0.012861), vec3(0.6, 0.0, 0.0), vec3(0.259484, 0.542553, 0.082149), vec4(7.0, 0.099437, 1.0, 0.0), (q79 - vec3(0.0, -0.000556, 0.0)), 0.0);
        M m85 = m84; m85.d = m84.d * 0.16;
        vec3 q86 = q2 - vec3(0.0, 2.0, 0.0);
        M m87 = M(sdBox(q86, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m88 = mI(m85, m87);
        u4 = mU(u4, m88);
      }
      if (sdBox(q2 - vec3(0.0, 0.051422, 0.0), vec3(0.51, 0.061422, 0.51)) < u4.d) {
        vec3 q89 = q2 * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q90 = q89 - vec3(0.092983, 0.05096, 0.174595);
        vec3 id91 = clamp(round(q90 / vec3(0.070635, 1.0, 0.070635) + vec3(8.0, 0.0, 8.0)), vec3(0.0), vec3(16.0, 0.0, 16.0));
        vec3 q92 = q90 - vec3(0.070635, 1.0, 0.070635) * (id91 - vec3(8.0, 0.0, 8.0));
        vec3 q93 = q92 - vec3(0.009017, -0.05096, -0.000595);
        vec3 q94 = q93 * mat3(0.06588, 0.0, 0.997828, 0.0, 1.0, 0.0, -0.997828, 0.0, 0.06588);
        vec3 q95 = q94 * mat3(1.0, 0.0, 0.0, 0.0, 0.984639, 0.174604, 0.0, -0.174604, 0.984639);
        vec3 q96 = q95 - vec3(0.0, 0.051755, 0.0);
        vec3 q97 = q96 / vec3(1.0, 1.0, 0.16);
        M m98 = M(sdPyramid((q97 + vec3(0.0, 0.051755, 0.0)) / 0.066185, 1.563954) * 0.066185, vec3(0.005392, 0.077651, 0.00905), vec3(0.6, 0.0, 0.0), vec3(0.193493, 0.56392, 0.079363), vec4(7.0, 0.103769, 1.0, 0.0), (q93 - vec3(0.0, -0.000924, 0.0)), 0.0);
        M m99 = m98; m99.d = m98.d * 0.16;
        vec3 q100 = q2 - vec3(0.0, 2.0, 0.0);
        M m101 = M(sdBox(q100, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m102 = mI(m99, m101);
        u4 = mU(u4, m102);
      }
      if (sdBox(q2 - vec3(0.0, 0.063695, 0.0), vec3(0.51, 0.073695, 0.51)) < u4.d) {
        vec3 q103 = q2 * mat3(0.920505, 0.0, -0.390731, 0.0, 1.0, 0.0, 0.390731, 0.0, 0.920505);
        vec3 q104 = q103 - vec3(0.10716, 0.062976, 0.215639);
        vec3 id105 = clamp(round(q104 / vec3(0.083508, 1.0, 0.083508) + vec3(6.5, 0.0, 6.5)), vec3(0.0), vec3(13.0, 0.0, 13.0));
        vec3 q106 = q104 - vec3(0.083508, 1.0, 0.083508) * (id105 - vec3(6.5, 0.0, 6.5));
        vec3 q107 = q106 - vec3(0.01184, -0.062976, -0.012639);
        vec3 q108 = q107 * mat3(0.729818, 0.0, 0.683642, 0.0, 1.0, 0.0, -0.683642, 0.0, 0.729818);
        vec3 q109 = q108 * mat3(1.0, 0.0, 0.0, 0.0, 0.964206, 0.265154, 0.0, -0.265154, 0.964206);
        vec3 q110 = q109 - vec3(0.0, 0.065314, 0.0);
        vec3 q111 = q110 / vec3(1.0, 1.0, 0.16);
        M m112 = M(sdPyramid((q111 + vec3(0.0, 0.065314, 0.0)) / 0.067782, 1.927192) * 0.067782, vec3(0.008107, 0.069236, 0.008549), vec3(0.6, 0.0, 0.0), vec3(0.267004, 0.711335, 0.03882), vec4(7.0, 0.128828, 1.0, 0.0), (q107 - vec3(0.0, -0.001438, 0.0)), 0.0);
        M m113 = m112; m113.d = m112.d * 0.16;
        vec3 q114 = q2 - vec3(0.0, 2.0, 0.0);
        M m115 = M(sdBox(q114, vec3(0.5, 2.0, 0.5)), vec3(0.024979, 0.142978, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m116 = mI(m113, m115);
        u4 = mU(u4, m116);
      }
      u3 = mU(u3, u4);
    }
    {
      vec3 q117 = q2 - vec3(0.0, -0.02, 0.0);
      M m118 = M(sdBox(q117, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u3 = mU(u3, m118);
    }
    u0 = mU(u0, u3);
  }
  if (sdBox(p - vec3(-2.24, 0.085866, 0.0), vec3(0.51, 0.135866, 0.51)) < u0.d) {
    vec3 q119 = p - vec3(-2.24, 0.0, 0.0);
    M u120 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q119 - vec3(0.0, 0.105866, 0.0), vec3(0.51, 0.115866, 0.51)) < u120.d) {
      M u121 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q119 - vec3(0.0, 0.046801, 0.0), vec3(0.51, 0.056801, 0.51)) < u121.d) {
        vec3 q122 = q119 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q123 = q122 - vec3(0.00357, 0.045748, 0.013871);
        vec3 id124 = clamp(round(q123 / vec3(0.099632, 1.0, 0.099632) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q125 = q123 - vec3(0.099632, 1.0, 0.099632) * (id124 - vec3(5.5, 0.0, 5.5));
        vec3 q126 = q125 - vec3(-0.00357, -0.045748, -0.013871);
        vec3 q127 = q126 * mat3(0.968446, 0.0, -0.249223, 0.0, 1.0, 0.0, 0.249223, 0.0, 0.968446);
        vec3 q128 = q127 * mat3(1.0, 0.0, 0.0, 0.0, 0.954322, 0.298779, 0.0, -0.298779, 0.954322);
        vec3 q129 = q128 - vec3(0.0, 0.047938, 0.0);
        vec3 q130 = q129 / vec3(1.0, 1.0, 0.16);
        M m131 = M(sdPyramid((q130 + vec3(0.0, 0.047938, 0.0)) / 0.088088, 1.088412) * 0.088088, vec3(0.013152, 0.11344, 0.012541), vec3(0.6, 0.0, 0.0), vec3(0.313988, 0.792768, 0.089811), vec4(7.0, 0.095708, 1.0, 0.0), (q126 - vec3(0.0, -0.002106, 0.0)), 0.0);
        M m132 = m131; m132.d = m131.d * 0.16;
        vec3 q133 = q119 - vec3(0.0, 2.0, 0.0);
        M m134 = M(sdBox(q133, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m135 = mI(m132, m134);
        u121 = mU(u121, m135);
      }
      if (sdBox(q119 - vec3(0.0, 0.053436, 0.0), vec3(0.51, 0.063436, 0.51)) < u121.d) {
        vec3 q136 = q119 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q137 = q136 - vec3(0.024737, 0.05254, 0.03698);
        vec3 id138 = clamp(round(q137 / vec3(0.109155, 1.0, 0.109155) + vec3(5.0, 0.0, 5.0)), vec3(0.0), vec3(10.0, 0.0, 10.0));
        vec3 q139 = q137 - vec3(0.109155, 1.0, 0.109155) * (id138 - vec3(5.0, 0.0, 5.0));
        vec3 q140 = q139 - vec3(-0.007737, -0.05254, -0.00798);
        vec3 q141 = q140 * mat3(0.717976, 0.0, -0.696067, 0.0, 1.0, 0.0, 0.696067, 0.0, 0.717976);
        vec3 q142 = q141 * mat3(1.0, 0.0, 0.0, 0.0, 0.978346, 0.206974, 0.0, -0.206974, 0.978346);
        vec3 q143 = q142 - vec3(0.0, 0.053703, 0.0);
        vec3 q144 = q143 / vec3(1.0, 1.0, 0.16);
        M m145 = M(sdPyramid((q144 + vec3(0.0, 0.053703, 0.0)) / 0.108211, 0.992558) * 0.108211, vec3(0.018136, 0.1012, 0.013033), vec3(0.6, 0.0, 0.0), vec3(0.3747, 0.722302, 0.085426), vec4(7.0, 0.108663, 1.0, 0.0), (q140 - vec3(0.0, -0.001792, 0.0)), 0.0);
        M m146 = m145; m146.d = m145.d * 0.16;
        vec3 q147 = q119 - vec3(0.0, 2.0, 0.0);
        M m148 = M(sdBox(q147, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m149 = mI(m146, m148);
        u121 = mU(u121, m149);
      }
      if (sdBox(q119 - vec3(0.0, 0.058685, 0.0), vec3(0.51, 0.068685, 0.51)) < u121.d) {
        vec3 q150 = q119 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q151 = q150 - vec3(0.044843, 0.05798, 0.057655);
        vec3 id152 = clamp(round(q151 / vec3(0.100878, 1.0, 0.100878) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q153 = q151 - vec3(0.100878, 1.0, 0.100878) * (id152 - vec3(5.5, 0.0, 5.5));
        vec3 q154 = q153 - vec3(-0.010843, -0.05798, 0.000345);
        vec3 q155 = q154 * mat3(-0.031785, 0.0, -0.999495, 0.0, 1.0, 0.0, 0.999495, 0.0, -0.031785);
        vec3 q156 = q155 * mat3(1.0, 0.0, 0.0, 0.0, 0.982941, 0.183921, 0.0, -0.183921, 0.982941);
        vec3 q157 = q156 - vec3(0.0, 0.058986, 0.0);
        vec3 q158 = q157 / vec3(1.0, 1.0, 0.16);
        M m159 = M(sdPyramid((q158 + vec3(0.0, 0.058986, 0.0)) / 0.095877, 1.230444) * 0.095877, vec3(0.007507, 0.083599, 0.005559), vec3(0.6, 0.0, 0.0), vec3(0.302569, 0.657537, 0.057741), vec4(7.0, 0.11878, 1.0, 0.0), (q154 - vec3(0.0, -0.001411, 0.0)), 0.0);
        M m160 = m159; m160.d = m159.d * 0.16;
        vec3 q161 = q119 - vec3(0.0, 2.0, 0.0);
        M m162 = M(sdBox(q161, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m163 = mI(m160, m162);
        u121 = mU(u121, m163);
      }
      if (sdBox(q119 - vec3(0.0, 0.06953, 0.0), vec3(0.51, 0.07953, 0.51)) < u121.d) {
        vec3 q164 = q119 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q165 = q164 - vec3(0.067164, 0.068211, 0.067991);
        vec3 id166 = clamp(round(q165 / vec3(0.119362, 1.0, 0.119362) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q167 = q165 - vec3(0.119362, 1.0, 0.119362) * (id166 - vec3(4.5, 0.0, 4.5));
        vec3 q168 = q167 - vec3(-0.016164, -0.068211, 0.019009);
        vec3 q169 = q168 * mat3(-0.761811, 0.0, -0.6478, 0.0, 1.0, 0.0, 0.6478, 0.0, -0.761811);
        vec3 q170 = q169 * mat3(1.0, 0.0, 0.0, 0.0, 0.939135, 0.343549, 0.0, -0.343549, 0.939135);
        vec3 q171 = q170 - vec3(0.0, 0.072632, 0.0);
        vec3 q172 = q171 / vec3(1.0, 1.0, 0.16);
        M m173 = M(sdPyramid((q172 + vec3(0.0, 0.072632, 0.0)) / 0.095958, 1.513842) * 0.095958, vec3(0.005155, 0.078925, 0.004138), vec3(0.6, 0.0, 0.0), vec3(0.25815, 0.595829, 0.091997), vec4(7.0, 0.141697, 1.0, 0.0), (q168 - vec3(0.0, -0.002637, 0.0)), 0.0);
        M m174 = m173; m174.d = m173.d * 0.16;
        vec3 q175 = q119 - vec3(0.0, 2.0, 0.0);
        M m176 = M(sdBox(q175, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m177 = mI(m174, m176);
        u121 = mU(u121, m177);
      }
      if (sdBox(q119 - vec3(0.0, 0.07432, 0.0), vec3(0.51, 0.08432, 0.51)) < u121.d) {
        vec3 q178 = q119 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q179 = q178 - vec3(0.06397, 0.073494, 0.100728);
        vec3 id180 = clamp(round(q179 / vec3(0.111303, 1.0, 0.111303) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q181 = q179 - vec3(0.111303, 1.0, 0.111303) * (id180 - vec3(4.5, 0.0, 4.5));
        vec3 q182 = q181 - vec3(0.00403, -0.073494, 0.015272);
        vec3 q183 = q182 * mat3(-0.966898, 0.0, 0.255161, 0.0, 1.0, 0.0, -0.255161, 0.0, -0.966898);
        vec3 q184 = q183 * mat3(1.0, 0.0, 0.0, 0.0, 0.977676, 0.210117, 0.0, -0.210117, 0.977676);
        vec3 q185 = q184 - vec3(0.0, 0.075172, 0.0);
        vec3 q186 = q185 / vec3(1.0, 1.0, 0.16);
        M m187 = M(sdPyramid((q186 + vec3(0.0, 0.075172, 0.0)) / 0.098292, 1.529557) * 0.098292, vec3(0.013634, 0.081037, 0.01124), vec3(0.6, 0.0, 0.0), vec3(0.371723, 0.752364, 0.068032), vec4(7.0, 0.150292, 1.0, 0.0), (q182 - vec3(0.0, -0.001652, 0.0)), 0.0);
        M m188 = m187; m188.d = m187.d * 0.16;
        vec3 q189 = q119 - vec3(0.0, 2.0, 0.0);
        M m190 = M(sdBox(q189, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m191 = mI(m188, m190);
        u121 = mU(u121, m191);
      }
      if (sdBox(q119 - vec3(0.0, 0.076492, 0.0), vec3(0.51, 0.086492, 0.51)) < u121.d) {
        vec3 q192 = q119 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q193 = q192 - vec3(0.063483, 0.074723, 0.12823);
        vec3 id194 = clamp(round(q193 / vec3(0.153035, 1.0, 0.153035) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q195 = q193 - vec3(0.153035, 1.0, 0.153035) * (id194 - vec3(3.0, 0.0, 3.0));
        vec3 q196 = q195 - vec3(0.021517, -0.074723, 0.01677);
        vec3 q197 = q196 * mat3(-0.614713, 0.0, 0.788751, 0.0, 1.0, 0.0, -0.788751, 0.0, -0.614713);
        vec3 q198 = q197 * mat3(1.0, 0.0, 0.0, 0.0, 0.939356, 0.342943, 0.0, -0.342943, 0.939356);
        vec3 q199 = q198 - vec3(0.0, 0.079547, 0.0);
        vec3 q200 = q199 / vec3(1.0, 1.0, 0.16);
        M m201 = M(sdPyramid((q200 + vec3(0.0, 0.079547, 0.0)) / 0.128935, 1.233914) * 0.128935, vec3(0.015674, 0.151342, 0.009769), vec3(0.6, 0.0, 0.0), vec3(0.250684, 0.768843, 0.063488), vec4(7.0, 0.156522, 1.0, 0.0), (q196 - vec3(0.0, -0.003537, 0.0)), 0.0);
        M m202 = m201; m202.d = m201.d * 0.16;
        vec3 q203 = q119 - vec3(0.0, 2.0, 0.0);
        M m204 = M(sdBox(q203, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m205 = mI(m202, m204);
        u121 = mU(u121, m205);
      }
      if (sdBox(q119 - vec3(0.0, 0.096512, 0.0), vec3(0.51, 0.106512, 0.51)) < u121.d) {
        vec3 q206 = q119 * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q207 = q206 - vec3(0.082395, 0.095493, 0.173378);
        vec3 id208 = clamp(round(q207 / vec3(0.133583, 1.0, 0.133583) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q209 = q207 - vec3(0.133583, 1.0, 0.133583) * (id208 - vec3(4.0, 0.0, 4.0));
        vec3 q210 = q209 - vec3(0.019605, -0.095493, 0.000622);
        vec3 q211 = q210 * mat3(-0.0317, 0.0, 0.999497, 0.0, 1.0, 0.0, -0.999497, 0.0, -0.0317);
        vec3 q212 = q211 * mat3(1.0, 0.0, 0.0, 0.0, 0.97955, 0.201202, 0.0, -0.201202, 0.97955);
        vec3 q213 = q212 - vec3(0.0, 0.097487, 0.0);
        vec3 q214 = q213 / vec3(1.0, 1.0, 0.16);
        M m215 = M(sdPyramid((q214 + vec3(0.0, 0.097487, 0.0)) / 0.126636, 1.539635) * 0.126636, vec3(0.016342, 0.142847, 0.014813), vec3(0.6, 0.0, 0.0), vec3(0.258096, 0.703565, 0.042176), vec4(7.0, 0.195063, 1.0, 0.0), (q210 - vec3(0.0, -0.002038, 0.0)), 0.0);
        M m216 = m215; m216.d = m215.d * 0.16;
        vec3 q217 = q119 - vec3(0.0, 2.0, 0.0);
        M m218 = M(sdBox(q217, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m219 = mI(m216, m218);
        u121 = mU(u121, m219);
      }
      if (sdBox(q119 - vec3(0.0, 0.08654, 0.0), vec3(0.51, 0.09654, 0.51)) < u121.d) {
        vec3 q220 = q119 * mat3(0.920505, 0.0, -0.390731, 0.0, 1.0, 0.0, 0.390731, 0.0, 0.920505);
        vec3 q221 = q220 - vec3(0.094588, 0.084706, 0.230072);
        vec3 id222 = clamp(round(q221 / vec3(0.152239, 1.0, 0.152239) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q223 = q221 - vec3(0.152239, 1.0, 0.152239) * (id222 - vec3(3.5, 0.0, 3.5));
        vec3 q224 = q223 - vec3(0.024412, -0.084706, -0.027072);
        vec3 q225 = q224 * mat3(0.74265, 0.0, 0.66968, 0.0, 1.0, 0.0, -0.66968, 0.0, 0.74265);
        vec3 q226 = q225 * mat3(1.0, 0.0, 0.0, 0.0, 0.918554, 0.395294, 0.0, -0.395294, 0.918554);
        vec3 q227 = q226 - vec3(0.0, 0.092217, 0.0);
        vec3 q228 = q227 / vec3(1.0, 1.0, 0.16);
        M m229 = M(sdPyramid((q228 + vec3(0.0, 0.092217, 0.0)) / 0.115995, 1.590017) * 0.115995, vec3(0.012444, 0.091824, 0.011976), vec3(0.6, 0.0, 0.0), vec3(0.304242, 0.596096, 0.071275), vec4(7.0, 0.176749, 1.0, 0.0), (q224 - vec3(0.0, -0.003668, 0.0)), 0.0);
        M m230 = m229; m230.d = m229.d * 0.16;
        vec3 q231 = q119 - vec3(0.0, 2.0, 0.0);
        M m232 = M(sdBox(q231, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m233 = mI(m230, m232);
        u121 = mU(u121, m233);
      }
      if (sdBox(q119 - vec3(0.0, 0.105866, 0.0), vec3(0.51, 0.115866, 0.51)) < u121.d) {
        vec3 q234 = q119 * mat3(0.882948, 0.0, -0.469472, 0.0, 1.0, 0.0, 0.469472, 0.0, 0.882948);
        vec3 q235 = q234 - vec3(0.137881, 0.104559, 0.264796);
        vec3 id236 = clamp(round(q235 / vec3(0.118131, 1.0, 0.118131) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q237 = q235 - vec3(0.118131, 1.0, 0.118131) * (id236 - vec3(4.5, 0.0, 4.5));
        vec3 q238 = q237 - vec3(-0.001881, -0.104559, -0.032796);
        vec3 q239 = q238 * mat3(0.998358, 0.0, -0.057274, 0.0, 1.0, 0.0, 0.057274, 0.0, 0.998358);
        vec3 q240 = q239 * mat3(1.0, 0.0, 0.0, 0.0, 0.954023, 0.299734, 0.0, -0.299734, 0.954023);
        vec3 q241 = q240 - vec3(0.0, 0.109598, 0.0);
        vec3 q242 = q241 / vec3(1.0, 1.0, 0.16);
        M m243 = M(sdPyramid((q242 + vec3(0.0, 0.109598, 0.0)) / 0.10905, 2.010045) * 0.10905, vec3(0.006076, 0.081722, 0.005103), vec3(0.6, 0.0, 0.0), vec3(0.389314, 0.761088, 0.098878), vec4(7.0, 0.214348, 1.0, 0.0), (q238 - vec3(0.0, -0.002615, 0.0)), 0.0);
        M m244 = m243; m244.d = m243.d * 0.16;
        vec3 q245 = q119 - vec3(0.0, 2.0, 0.0);
        M m246 = M(sdBox(q245, vec3(0.5, 2.0, 0.5)), vec3(0.034091, 0.168269, 0.015996), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m247 = mI(m244, m246);
        u121 = mU(u121, m247);
      }
      u120 = mU(u120, u121);
    }
    {
      vec3 q248 = q119 - vec3(0.0, -0.02, 0.0);
      M m249 = M(sdBox(q248, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u120 = mU(u120, m249);
    }
    u0 = mU(u0, u120);
  }
  if (sdBox(p - vec3(-1.12, 0.285544, 0.0), vec3(0.51, 0.335544, 0.51)) < u0.d) {
    vec3 q250 = p - vec3(-1.12, 0.0, 0.0);
    M u251 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q250 - vec3(0.0, 0.305544, 0.0), vec3(0.51, 0.315544, 0.51)) < u251.d) {
      M u252 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q250 - vec3(0.0, 0.142875, 0.0), vec3(0.51, 0.152875, 0.51)) < u252.d) {
        vec3 q253 = q250 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q254 = q253 - vec3(0.000405, 0.142492, 0.020373);
        vec3 id255 = clamp(round(q254 / vec3(0.071374, 1.0, 0.071374) + vec3(8.0, 0.0, 8.0)), vec3(0.0), vec3(16.0, 0.0, 16.0));
        vec3 q256 = q254 - vec3(0.071374, 1.0, 0.071374) * (id255 - vec3(8.0, 0.0, 8.0));
        vec3 q257 = q256 - vec3(-0.000405, -0.142492, -0.020373);
        vec3 q258 = q257 * mat3(0.999803, 0.0, -0.019872, 0.0, 1.0, 0.0, 0.019872, 0.0, 0.999803);
        vec3 q259 = q258 * mat3(1.0, 0.0, 0.0, 0.0, 0.989929, 0.141562, 0.0, -0.141562, 0.989929);
        vec3 q260 = q259 - vec3(0.0, 0.143942, 0.0);
        vec3 q261 = q260 / vec3(1.0, 1.0, 0.16);
        M m262 = M(sdPyramid((q261 + vec3(0.0, 0.143942, 0.0)) / 0.06762, 4.257379) * 0.06762, vec3(0.018722, 0.09077, 0.007899), vec3(0.6, 0.0, 0.0), vec3(0.379489, 0.486628, 0.047349), vec4(7.0, 0.286516, 1.0, 0.0), (q257 - vec3(0.0, -0.000766, 0.0)), 0.0);
        M m263 = m262; m263.d = m262.d * 0.16;
        vec3 q264 = q250 - vec3(0.0, 2.0, 0.0);
        M m265 = M(sdBox(q264, vec3(0.5, 2.0, 0.5)), vec3(0.059856, 0.15055, 0.016643), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m266 = mI(m263, m265);
        u252 = mU(u252, m266);
      }
      if (sdBox(q250 - vec3(0.0, 0.174125, 0.0), vec3(0.51, 0.184125, 0.51)) < u252.d) {
        vec3 q267 = q250 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q268 = q267 - vec3(0.041826, 0.173694, 0.045092);
        vec3 id269 = clamp(round(q268 / vec3(0.096801, 1.0, 0.096801) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q270 = q268 - vec3(0.096801, 1.0, 0.096801) * (id269 - vec3(5.5, 0.0, 5.5));
        vec3 q271 = q270 - vec3(-0.024826, -0.173694, -0.016092);
        vec3 q272 = q271 * mat3(0.543908, 0.0, -0.839145, 0.0, 1.0, 0.0, 0.839145, 0.0, 0.543908);
        vec3 q273 = q272 * mat3(1.0, 0.0, 0.0, 0.0, 0.985802, 0.167913, 0.0, -0.167913, 0.985802);
        vec3 q274 = q273 - vec3(0.0, 0.176196, 0.0);
        vec3 q275 = q274 / vec3(1.0, 1.0, 0.16);
        M m276 = M(sdPyramid((q275 + vec3(0.0, 0.176196, 0.0)) / 0.064213, 5.487877) * 0.064213, vec3(0.031284, 0.107088, 0.014893), vec3(0.6, 0.0, 0.0), vec3(0.359181, 0.468927, 0.036266), vec4(7.0, 0.349113, 1.0, 0.0), (q271 - vec3(0.0, -0.000863, 0.0)), 0.0);
        M m277 = m276; m277.d = m276.d * 0.16;
        vec3 q278 = q250 - vec3(0.0, 2.0, 0.0);
        M m279 = M(sdBox(q278, vec3(0.5, 2.0, 0.5)), vec3(0.059856, 0.15055, 0.016643), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m280 = mI(m277, m279);
        u252 = mU(u252, m280);
      }
      if (sdBox(q250 - vec3(0.0, 0.21104, 0.0), vec3(0.51, 0.22104, 0.51)) < u252.d) {
        vec3 q281 = q250 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q282 = q281 - vec3(0.057573, 0.21077, 0.060163);
        vec3 id283 = clamp(round(q282 / vec3(0.067929, 1.0, 0.067929) + vec3(8.0, 0.0, 8.0)), vec3(0.0), vec3(16.0, 0.0, 16.0));
        vec3 q284 = q282 - vec3(0.067929, 1.0, 0.067929) * (id283 - vec3(8.0, 0.0, 8.0));
        vec3 q285 = q284 - vec3(-0.023573, -0.21077, -0.002163);
        vec3 q286 = q285 * mat3(0.091362, 0.0, -0.995818, 0.0, 1.0, 0.0, 0.995818, 0.0, 0.091362);
        vec3 q287 = q286 * mat3(1.0, 0.0, 0.0, 0.0, 0.993752, 0.111612, 0.0, -0.111612, 0.993752);
        vec3 q288 = q287 - vec3(0.0, 0.212095, 0.0);
        vec3 q289 = q288 / vec3(1.0, 1.0, 0.16);
        M m290 = M(sdPyramid((q289 + vec3(0.0, 0.212095, 0.0)) / 0.060366, 7.026948) * 0.060366, vec3(0.021482, 0.086596, 0.005239), vec3(0.6, 0.0, 0.0), vec3(0.357577, 0.515513, 0.038471), vec4(7.0, 0.422618, 1.0, 0.0), (q285 - vec3(0.0, -0.000539, 0.0)), 0.0);
        M m291 = m290; m291.d = m290.d * 0.16;
        vec3 q292 = q250 - vec3(0.0, 2.0, 0.0);
        M m293 = M(sdBox(q292, vec3(0.5, 2.0, 0.5)), vec3(0.059856, 0.15055, 0.016643), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m294 = mI(m291, m293);
        u252 = mU(u252, m294);
      }
      if (sdBox(q250 - vec3(0.0, 0.222765, 0.0), vec3(0.51, 0.232765, 0.51)) < u252.d) {
        vec3 q295 = q250 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q296 = q295 - vec3(0.064489, 0.222499, 0.069959);
        vec3 id297 = clamp(round(q296 / vec3(0.090738, 1.0, 0.090738) + vec3(6.0, 0.0, 6.0)), vec3(0.0), vec3(12.0, 0.0, 12.0));
        vec3 q298 = q296 - vec3(0.090738, 1.0, 0.090738) * (id297 - vec3(6.0, 0.0, 6.0));
        vec3 q299 = q298 - vec3(-0.013489, -0.222499, 0.017041);
        vec3 q300 = q299 * mat3(-0.78409, 0.0, -0.620647, 0.0, 1.0, 0.0, 0.620647, 0.0, -0.78409);
        vec3 q301 = q300 * mat3(1.0, 0.0, 0.0, 0.0, 0.995263, 0.097218, 0.0, -0.097218, 0.995263);
        vec3 q302 = q301 - vec3(0.0, 0.223558, 0.0);
        vec3 q303 = q302 / vec3(1.0, 1.0, 0.16);
        M m304 = M(sdPyramid((q303 + vec3(0.0, 0.223558, 0.0)) / 0.068261, 6.550059) * 0.068261, vec3(0.047072, 0.137813, 0.019815), vec3(0.6, 0.0, 0.0), vec3(0.53109, 0.720612, 0.148994), vec4(7.0, 0.446061, 1.0, 0.0), (q299 - vec3(0.0, -0.000531, 0.0)), 0.0);
        M m305 = m304; m305.d = m304.d * 0.16;
        vec3 q306 = q250 - vec3(0.0, 2.0, 0.0);
        M m307 = M(sdBox(q306, vec3(0.5, 2.0, 0.5)), vec3(0.059856, 0.15055, 0.016643), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m308 = mI(m305, m307);
        u252 = mU(u252, m308);
      }
      if (sdBox(q250 - vec3(0.0, 0.228959, 0.0), vec3(0.51, 0.238959, 0.51)) < u252.d) {
        vec3 q309 = q250 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q310 = q309 - vec3(0.06888, 0.228318, 0.072449);
        vec3 id311 = clamp(round(q310 / vec3(0.106351, 1.0, 0.106351) + vec3(5.0, 0.0, 5.0)), vec3(0.0), vec3(10.0, 0.0, 10.0));
        vec3 q312 = q310 - vec3(0.106351, 1.0, 0.106351) * (id311 - vec3(5.0, 0.0, 5.0));
        vec3 q313 = q312 - vec3(-0.00088, -0.228318, 0.043551);
        vec3 q314 = q313 * mat3(-0.999796, 0.0, -0.020196, 0.0, 1.0, 0.0, 0.020196, 0.0, -0.999796);
        vec3 q315 = q314 * mat3(1.0, 0.0, 0.0, 0.0, 0.982283, 0.187404, 0.0, -0.187404, 0.982283);
        vec3 q316 = q315 - vec3(0.0, 0.232436, 0.0);
        vec3 q317 = q316 / vec3(1.0, 1.0, 0.16);
        M m318 = M(sdPyramid((q317 + vec3(0.0, 0.232436, 0.0)) / 0.085487, 5.437903) * 0.085487, vec3(0.034667, 0.117843, 0.017511), vec3(0.6, 0.0, 0.0), vec3(0.363879, 0.569732, 0.051481), vec4(7.0, 0.4592, 1.0, 0.0), (q313 - vec3(0.0, -0.001282, 0.0)), 0.0);
        M m319 = m318; m319.d = m318.d * 0.16;
        vec3 q320 = q250 - vec3(0.0, 2.0, 0.0);
        M m321 = M(sdBox(q320, vec3(0.5, 2.0, 0.5)), vec3(0.059856, 0.15055, 0.016643), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m322 = mI(m319, m321);
        u252 = mU(u252, m322);
      }
      if (sdBox(q250 - vec3(0.0, 0.301568, 0.0), vec3(0.51, 0.311568, 0.51)) < u252.d) {
        vec3 q323 = q250 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q324 = q323 - vec3(0.020696, 0.301029, 0.120831);
        vec3 id325 = clamp(round(q324 / vec3(0.165136, 1.0, 0.165136) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q326 = q324 - vec3(0.165136, 1.0, 0.165136) * (id325 - vec3(3.0, 0.0, 3.0));
        vec3 q327 = q326 - vec3(0.064304, -0.301029, 0.024169);
        vec3 q328 = q327 * mat3(-0.351827, 0.0, 0.936065, 0.0, 1.0, 0.0, -0.936065, 0.0, -0.351827);
        vec3 q329 = q328 * mat3(1.0, 0.0, 0.0, 0.0, 0.974936, 0.222486, 0.0, -0.222486, 0.974936);
        vec3 q330 = q329 - vec3(0.0, 0.308768, 0.0);
        vec3 q331 = q330 / vec3(1.0, 1.0, 0.16);
        M m332 = M(sdPyramid((q331 + vec3(0.0, 0.308768, 0.0)) / 0.060614, 10.188046) * 0.060614, vec3(0.019273, 0.093051, 0.007941), vec3(0.6, 0.0, 0.0), vec3(0.584824, 0.678292, 0.05845), vec4(7.0, 0.604215, 1.0, 0.0), (q327 - vec3(0.0, -0.001079, 0.0)), 0.0);
        M m333 = m332; m333.d = m332.d * 0.16;
        vec3 q334 = q250 - vec3(0.0, 2.0, 0.0);
        M m335 = M(sdBox(q334, vec3(0.5, 2.0, 0.5)), vec3(0.059856, 0.15055, 0.016643), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m336 = mI(m333, m335);
        u252 = mU(u252, m336);
      }
      if (sdBox(q250 - vec3(0.0, 0.305544, 0.0), vec3(0.51, 0.315544, 0.51)) < u252.d) {
        vec3 q337 = q250 * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q338 = q337 - vec3(0.02825, 0.304851, 0.208157);
        vec3 id339 = clamp(round(q338 / vec3(0.19262, 1.0, 0.19262) + vec3(2.5, 0.0, 2.5)), vec3(0.0), vec3(5.0, 0.0, 5.0));
        vec3 q340 = q338 - vec3(0.19262, 1.0, 0.19262) * (id339 - vec3(2.5, 0.0, 2.5));
        vec3 q341 = q340 - vec3(0.07375, -0.304851, -0.034157);
        vec3 q342 = q341 * mat3(0.420255, 0.0, 0.907406, 0.0, 1.0, 0.0, -0.907406, 0.0, 0.420255);
        vec3 q343 = q342 * mat3(1.0, 0.0, 0.0, 0.0, 0.966249, 0.257611, 0.0, -0.257611, 0.966249);
        vec3 q344 = q343 - vec3(0.0, 0.315499, 0.0);
        vec3 q345 = q344 / vec3(1.0, 1.0, 0.16);
        M m346 = M(sdPyramid((q345 + vec3(0.0, 0.315499, 0.0)) / 0.067275, 9.379376) * 0.067275, vec3(0.015995, 0.053429, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.385594, 0.567789, 0.089595), vec4(7.0, 0.612474, 1.0, 0.0), (q341 - vec3(0.0, -0.001386, 0.0)), 0.0);
        M m347 = m346; m347.d = m346.d * 0.16;
        vec3 q348 = q250 - vec3(0.0, 2.0, 0.0);
        M m349 = M(sdBox(q348, vec3(0.5, 2.0, 0.5)), vec3(0.059856, 0.15055, 0.016643), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m350 = mI(m347, m349);
        u252 = mU(u252, m350);
      }
      u251 = mU(u251, u252);
    }
    {
      vec3 q351 = q250 - vec3(0.0, -0.02, 0.0);
      M m352 = M(sdBox(q351, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u251 = mU(u251, m352);
    }
    u0 = mU(u0, u251);
  }
  if (sdBox(p - vec3(0.0, 0.15401, 0.0), vec3(0.51, 0.20401, 0.51)) < u0.d) {
    M u353 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(p - vec3(0.0, 0.17401, 0.0), vec3(0.51, 0.18401, 0.51)) < u353.d) {
      M u354 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(p - vec3(0.0, 0.082032, 0.0), vec3(0.51, 0.092032, 0.51)) < u354.d) {
        vec3 q355 = p * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q356 = q355 - vec3(-0.006229, 0.08138, 0.027522);
        vec3 id357 = clamp(round(q356 / vec3(0.076301, 1.0, 0.076301) + vec3(7.0, 0.0, 7.0)), vec3(0.0), vec3(14.0, 0.0, 14.0));
        vec3 q358 = q356 - vec3(0.076301, 1.0, 0.076301) * (id357 - vec3(7.0, 0.0, 7.0));
        vec3 q359 = q358 - vec3(0.006229, -0.08138, -0.027522);
        vec3 q360 = q359 * mat3(0.975334, 0.0, 0.220734, 0.0, 1.0, 0.0, -0.220734, 0.0, 0.975334);
        vec3 q361 = q360 * mat3(1.0, 0.0, 0.0, 0.0, 0.944813, 0.327611, 0.0, -0.327611, 0.944813);
        vec3 q362 = q361 - vec3(0.0, 0.086134, 0.0);
        vec3 q363 = q362 / vec3(1.0, 1.0, 0.16);
        M m364 = M(sdPyramid((q363 + vec3(0.0, 0.086134, 0.0)) / 0.049764, 3.461673) * 0.049764, vec3(0.142573, 0.107167, 0.017823), vec3(0.6, 0.0, 0.0), vec3(0.808105, 0.561732, 0.208836), vec4(7.0, 0.165369, 1.0, 0.0), (q359 - vec3(0.0, -0.001304, 0.0)), 0.0);
        M m365 = m364; m365.d = m364.d * 0.16;
        vec3 q366 = p - vec3(0.0, 2.0, 0.0);
        M m367 = M(sdBox(q366, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m368 = mI(m365, m367);
        u354 = mU(u354, m368);
      }
      if (sdBox(p - vec3(0.0, 0.084291, 0.0), vec3(0.51, 0.094291, 0.51)) < u354.d) {
        vec3 q369 = p * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q370 = q369 - vec3(0.044213, 0.083456, 0.055003);
        vec3 id371 = clamp(round(q370 / vec3(0.098671, 1.0, 0.098671) + vec3(5.5, 0.0, 5.5)), vec3(0.0), vec3(11.0, 0.0, 11.0));
        vec3 q372 = q370 - vec3(0.098671, 1.0, 0.098671) * (id371 - vec3(5.5, 0.0, 5.5));
        vec3 q373 = q372 - vec3(-0.027213, -0.083456, -0.026003);
        vec3 q374 = q373 * mat3(0.690859, 0.0, -0.722989, 0.0, 1.0, 0.0, 0.722989, 0.0, 0.690859);
        vec3 q375 = q374 * mat3(1.0, 0.0, 0.0, 0.0, 0.911577, 0.411129, 0.0, -0.411129, 0.911577);
        vec3 q376 = q375 - vec3(0.0, 0.091551, 0.0);
        vec3 q377 = q376 / vec3(1.0, 1.0, 0.16);
        M m378 = M(sdPyramid((q377 + vec3(0.0, 0.091551, 0.0)) / 0.050798, 3.604533) * 0.050798, vec3(0.124253, 0.090895, 0.010362), vec3(0.6, 0.0, 0.0), vec3(0.847062, 0.664634, 0.214369), vec4(7.0, 0.170253, 1.0, 0.0), (q373 - vec3(0.0, -0.001671, 0.0)), 0.0);
        M m379 = m378; m379.d = m378.d * 0.16;
        vec3 q380 = p - vec3(0.0, 2.0, 0.0);
        M m381 = M(sdBox(q380, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m382 = mI(m379, m381);
        u354 = mU(u354, m382);
      }
      if (sdBox(p - vec3(0.0, 0.10669, 0.0), vec3(0.51, 0.11669, 0.51)) < u354.d) {
        vec3 q383 = p * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q384 = q383 - vec3(0.073467, 0.105725, 0.065423);
        vec3 id385 = clamp(round(q384 / vec3(0.10556, 1.0, 0.10556) + vec3(5.0, 0.0, 5.0)), vec3(0.0), vec3(10.0, 0.0, 10.0));
        vec3 q386 = q384 - vec3(0.10556, 1.0, 0.10556) * (id385 - vec3(5.0, 0.0, 5.0));
        vec3 q387 = q386 - vec3(-0.039467, -0.105725, -0.007423);
        vec3 q388 = q387 * mat3(0.18484, 0.0, -0.982769, 0.0, 1.0, 0.0, 0.982769, 0.0, 0.18484);
        vec3 q389 = q388 * mat3(1.0, 0.0, 0.0, 0.0, 0.934832, 0.35509, 0.0, -0.35509, 0.934832);
        vec3 q390 = q389 - vec3(0.0, 0.113095, 0.0);
        vec3 q391 = q390 / vec3(1.0, 1.0, 0.16);
        M m392 = M(sdPyramid((q391 + vec3(0.0, 0.113095, 0.0)) / 0.068005, 3.326074) * 0.068005, vec3(0.200934, 0.156178, 0.028145), vec3(0.6, 0.0, 0.0), vec3(0.861186, 0.678692, 0.195078), vec4(7.0, 0.215313, 1.0, 0.0), (q387 - vec3(0.0, -0.001932, 0.0)), 0.0);
        M m393 = m392; m393.d = m392.d * 0.16;
        vec3 q394 = p - vec3(0.0, 2.0, 0.0);
        M m395 = M(sdBox(q394, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m396 = mI(m393, m395);
        u354 = mU(u354, m396);
      }
      if (sdBox(p - vec3(0.003255, 0.108988, 0.0), vec3(0.506745, 0.118988, 0.51)) < u354.d) {
        vec3 q397 = p * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q398 = q397 - vec3(0.090726, 0.108039, 0.058091);
        vec3 id399 = clamp(round(q398 / vec3(0.12474, 1.0, 0.12474) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q400 = q398 - vec3(0.12474, 1.0, 0.12474) * (id399 - vec3(4.0, 0.0, 4.0));
        vec3 q401 = q400 - vec3(-0.039726, -0.108039, 0.028909);
        vec3 q402 = q401 * mat3(-0.588395, 0.0, -0.808573, 0.0, 1.0, 0.0, 0.808573, 0.0, -0.588395);
        vec3 q403 = q402 * mat3(1.0, 0.0, 0.0, 0.0, 0.910294, 0.413962, 0.0, -0.413962, 0.910294);
        vec3 q404 = q403 - vec3(0.0, 0.118685, 0.0);
        vec3 q405 = q404 / vec3(1.0, 1.0, 0.16);
        M m406 = M(sdPyramid((q405 + vec3(0.0, 0.118685, 0.0)) / 0.057337, 4.139909) * 0.057337, vec3(0.190568, 0.120839, 0.022715), vec3(0.6, 0.0, 0.0), vec3(0.885275, 0.648446, 0.158929), vec4(7.0, 0.219875, 1.0, 0.0), (q401 - vec3(0.0, -0.001899, 0.0)), 0.0);
        M m407 = m406; m407.d = m406.d * 0.16;
        vec3 q408 = p - vec3(0.0, 2.0, 0.0);
        M m409 = M(sdBox(q408, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m410 = mI(m407, m409);
        u354 = mU(u354, m410);
      }
      if (sdBox(p - vec3(0.0, 0.142529, 0.0), vec3(0.51, 0.152529, 0.51)) < u354.d) {
        vec3 q411 = p * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q412 = q411 - vec3(0.065915, 0.142036, 0.087389);
        vec3 id413 = clamp(round(q412 / vec3(0.074345, 1.0, 0.074345) + vec3(7.5, 0.0, 7.5)), vec3(0.0), vec3(15.0, 0.0, 15.0));
        vec3 q414 = q412 - vec3(0.074345, 1.0, 0.074345) * (id413 - vec3(7.5, 0.0, 7.5));
        vec3 q415 = q414 - vec3(0.002085, -0.142036, 0.028611);
        vec3 q416 = q415 * mat3(-0.997354, 0.0, 0.072696, 0.0, 1.0, 0.0, -0.072696, 0.0, -0.997354);
        vec3 q417 = q416 * mat3(1.0, 0.0, 0.0, 0.0, 0.980208, 0.197972, 0.0, -0.197972, 0.980208);
        vec3 q418 = q417 - vec3(0.0, 0.144904, 0.0);
        vec3 q419 = q418 / vec3(1.0, 1.0, 0.16);
        M m420 = M(sdPyramid((q419 + vec3(0.0, 0.144904, 0.0)) / 0.062256, 4.655131) * 0.062256, vec3(0.134108, 0.092408, 0.011518), vec3(0.6, 0.0, 0.0), vec3(0.813991, 0.588707, 0.17331), vec4(7.0, 0.286045, 1.0, 0.0), (q415 - vec3(0.0, -0.000986, 0.0)), 0.0);
        M m421 = m420; m421.d = m420.d * 0.16;
        vec3 q422 = p - vec3(0.0, 2.0, 0.0);
        M m423 = M(sdBox(q422, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m424 = mI(m421, m423);
        u354 = mU(u354, m424);
      }
      if (sdBox(p - vec3(0.0, 0.153736, 0.0), vec3(0.51, 0.163736, 0.51)) < u354.d) {
        vec3 q425 = p * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q426 = q425 - vec3(0.033807, 0.152652, 0.103793);
        vec3 id427 = clamp(round(q426 / vec3(0.159346, 1.0, 0.159346) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q428 = q426 - vec3(0.159346, 1.0, 0.159346) * (id427 - vec3(3.0, 0.0, 3.0));
        vec3 q429 = q428 - vec3(0.051193, -0.152652, 0.041207);
        vec3 q430 = q429 * mat3(-0.62703, 0.0, 0.778995, 0.0, 1.0, 0.0, -0.778995, 0.0, -0.62703);
        vec3 q431 = q430 * mat3(1.0, 0.0, 0.0, 0.0, 0.918501, 0.395418, 0.0, -0.395418, 0.918501);
        vec3 q432 = q431 - vec3(0.0, 0.166197, 0.0);
        vec3 q433 = q432 / vec3(1.0, 1.0, 0.16);
        M m434 = M(sdPyramid((q433 + vec3(0.0, 0.166197, 0.0)) / 0.06855, 4.848899) * 0.06855, vec3(0.140197, 0.101589, 0.01396), vec3(0.6, 0.0, 0.0), vec3(0.860497, 0.687478, 0.127772), vec4(7.0, 0.30964, 1.0, 0.0), (q429 - vec3(0.0, -0.002168, 0.0)), 0.0);
        M m435 = m434; m435.d = m434.d * 0.16;
        vec3 q436 = p - vec3(0.0, 2.0, 0.0);
        M m437 = M(sdBox(q436, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m438 = mI(m435, m437);
        u354 = mU(u354, m438);
      }
      if (sdBox(p - vec3(0.0, 0.162684, 0.0), vec3(0.51, 0.172684, 0.51)) < u354.d) {
        vec3 q439 = p * mat3(0.951057, 0.0, -0.309017, 0.0, 1.0, 0.0, 0.309017, 0.0, 0.951057);
        vec3 q440 = q439 - vec3(0.025679, 0.161474, 0.172277);
        vec3 id441 = clamp(round(q440 / vec3(0.171055, 1.0, 0.171055) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q442 = q440 - vec3(0.171055, 1.0, 0.171055) * (id441 - vec3(3.0, 0.0, 3.0));
        vec3 q443 = q442 - vec3(0.076321, -0.161474, 0.001723);
        vec3 q444 = q443 * mat3(-0.022571, 0.0, 0.999745, 0.0, 1.0, 0.0, -0.999745, 0.0, -0.022571);
        vec3 q445 = q444 * mat3(1.0, 0.0, 0.0, 0.0, 0.904057, 0.427411, 0.0, -0.427411, 0.904057);
        vec3 q446 = q445 - vec3(0.0, 0.178611, 0.0);
        vec3 q447 = q446 / vec3(1.0, 1.0, 0.16);
        M m448 = M(sdPyramid((q447 + vec3(0.0, 0.178611, 0.0)) / 0.070785, 5.046559) * 0.070785, vec3(0.190905, 0.12157, 0.021366), vec3(0.6, 0.0, 0.0), vec3(0.726228, 0.506272, 0.149876), vec4(7.0, 0.327789, 1.0, 0.0), (q443 - vec3(0.0, -0.00242, 0.0)), 0.0);
        M m449 = m448; m449.d = m448.d * 0.16;
        vec3 q450 = p - vec3(0.0, 2.0, 0.0);
        M m451 = M(sdBox(q450, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m452 = mI(m449, m451);
        u354 = mU(u354, m452);
      }
      if (sdBox(p - vec3(0.0, 0.17401, 0.0), vec3(0.51, 0.18401, 0.51)) < u354.d) {
        vec3 q453 = p * mat3(0.920505, 0.0, -0.390731, 0.0, 1.0, 0.0, 0.390731, 0.0, 0.920505);
        vec3 q454 = q453 - vec3(0.080496, 0.173105, 0.259515);
        vec3 id455 = clamp(round(q454 / vec3(0.161481, 1.0, 0.161481) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q456 = q454 - vec3(0.161481, 1.0, 0.161481) * (id455 - vec3(3.0, 0.0, 3.0));
        vec3 q457 = q456 - vec3(0.038504, -0.173105, -0.056515);
        vec3 q458 = q457 * mat3(0.826425, 0.0, 0.563047, 0.0, 1.0, 0.0, -0.563047, 0.0, 0.826425);
        vec3 q459 = q458 * mat3(1.0, 0.0, 0.0, 0.0, 0.930055, 0.36742, 0.0, -0.36742, 0.930055);
        vec3 q460 = q459 - vec3(0.0, 0.186123, 0.0);
        vec3 q461 = q460 / vec3(1.0, 1.0, 0.16);
        M m462 = M(sdPyramid((q461 + vec3(0.0, 0.186123, 0.0)) / 0.06157, 6.04587) * 0.06157, vec3(0.203196, 0.156137, 0.032391), vec3(0.6, 0.0, 0.0), vec3(0.879748, 0.646398, 0.148129), vec4(7.0, 0.34983, 1.0, 0.0), (q457 - vec3(0.0, -0.00181, 0.0)), 0.0);
        M m463 = m462; m463.d = m462.d * 0.16;
        vec3 q464 = p - vec3(0.0, 2.0, 0.0);
        M m465 = M(sdBox(q464, vec3(0.5, 2.0, 0.5)), vec3(0.226215, 0.162029, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m466 = mI(m463, m465);
        u354 = mU(u354, m466);
      }
      u353 = mU(u353, u354);
    }
    {
      vec3 q467 = p - vec3(0.0, -0.02, 0.0);
      M m468 = M(sdBox(q467, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u353 = mU(u353, m468);
    }
    u0 = mU(u0, u353);
  }
  if (sdBox(p - vec3(1.12, 0.156756, 0.0), vec3(0.51, 0.206756, 0.51)) < u0.d) {
    vec3 q469 = p - vec3(1.12, 0.0, 0.0);
    M u470 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q469 - vec3(0.0, 0.176756, 0.0), vec3(0.51, 0.186756, 0.51)) < u470.d) {
      M u471 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q469 - vec3(0.0, 0.091356, 0.0), vec3(0.51, 0.101356, 0.51)) < u471.d) {
        vec3 q472 = q469 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q473 = q472 - vec3(0.008392, 0.090026, 0.008631);
        vec3 id474 = clamp(round(q473 / vec3(0.169885, 1.0, 0.169885) + vec3(3.0, 0.0, 3.0)), vec3(0.0), vec3(6.0, 0.0, 6.0));
        vec3 q475 = q473 - vec3(0.169885, 1.0, 0.169885) * (id474 - vec3(3.0, 0.0, 3.0));
        vec3 q476 = q475 - vec3(-0.008392, -0.090026, -0.008631);
        M u477 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q478 = q476 * mat3(0.958629, 0.0, -0.28466, 0.0, 1.0, 0.0, 0.28466, 0.0, 0.958629);
          vec3 q479 = q478 * mat3(1.0, 0.0, 0.0, 0.0, 0.928084, 0.372371, 0.0, -0.372371, 0.928084);
          vec3 q480 = q479 - vec3(0.0, 0.092539, 0.0);
          vec3 q481 = q480 / vec3(1.0, 1.0, 0.16);
          M m482 = M(sdPyramid((q481 + vec3(0.0, 0.092539, 0.0)) / 0.061316, 3.018412) * 0.061316, vec3(0.007604, 0.052472, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.21825, 0.678014, 0.055058), vec4(7.0, 0.185371, 1.0, 0.0), (q476 - vec3(0.0, -0.002659, 0.0)), 0.0);
          M m483 = m482; m483.d = m482.d * 0.16;
          u477 = mU(u477, m483);
        }
        {
          vec3 q484 = q476 * mat3(0.629207, 0.0, -0.777238, 0.0, 1.0, 0.0, 0.777238, 0.0, 0.629207);
          vec3 q485 = q484 * mat3(1.0, 0.0, 0.0, 0.0, 0.954868, 0.297031, 0.0, -0.297031, 0.954868);
          vec3 q486 = q485 - vec3(0.0, 0.081828, 0.0);
          vec3 q487 = q486 / vec3(1.0, 1.0, 0.16);
          M m488 = M(sdPyramid((q487 + vec3(0.0, 0.081828, 0.0)) / 0.071894, 2.276355) * 0.071894, vec3(0.007604, 0.052472, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.21825, 0.678014, 0.055058), vec4(7.0, 0.185371, 1.0, 0.0), (q476 - vec3(0.0, -0.002659, 0.0)), 0.0);
          M m489 = m488; m489.d = m488.d * 0.16;
          u477 = mU(u477, m489);
        }
        {
          vec3 q490 = q476 * mat3(-0.201014, 0.0, -0.979588, 0.0, 1.0, 0.0, 0.979588, 0.0, -0.201014);
          vec3 q491 = q490 * mat3(1.0, 0.0, 0.0, 0.0, 0.902548, 0.43059, 0.0, -0.43059, 0.902548);
          vec3 q492 = q491 - vec3(0.0, 0.091097, 0.0);
          vec3 q493 = q492 / vec3(1.0, 1.0, 0.16);
          M m494 = M(sdPyramid((q493 + vec3(0.0, 0.091097, 0.0)) / 0.077191, 2.360306) * 0.077191, vec3(0.007604, 0.052472, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.21825, 0.678014, 0.055058), vec4(7.0, 0.185371, 1.0, 0.0), (q476 - vec3(0.0, -0.002659, 0.0)), 0.0);
          M m495 = m494; m495.d = m494.d * 0.16;
          u477 = mU(u477, m495);
        }
        {
          vec3 q496 = q476 * mat3(-0.967634, 0.0, -0.252358, 0.0, 1.0, 0.0, 0.252358, 0.0, -0.967634);
          vec3 q497 = q496 * mat3(1.0, 0.0, 0.0, 0.0, 0.965783, 0.25935, 0.0, -0.25935, 0.965783);
          vec3 q498 = q497 - vec3(0.0, 0.073738, 0.0);
          vec3 q499 = q498 / vec3(1.0, 1.0, 0.16);
          M m500 = M(sdPyramid((q499 + vec3(0.0, 0.073738, 0.0)) / 0.073159, 2.015822) * 0.073159, vec3(0.007604, 0.052472, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.21825, 0.678014, 0.055058), vec4(7.0, 0.185371, 1.0, 0.0), (q476 - vec3(0.0, -0.002659, 0.0)), 0.0);
          M m501 = m500; m501.d = m500.d * 0.16;
          u477 = mU(u477, m501);
        }
        {
          vec3 q502 = q476 * mat3(-0.997324, 0.0, 0.073111, 0.0, 1.0, 0.0, -0.073111, 0.0, -0.997324);
          vec3 q503 = q502 * mat3(1.0, 0.0, 0.0, 0.0, 0.952223, 0.305403, 0.0, -0.305403, 0.952223);
          vec3 q504 = q503 - vec3(0.0, 0.081775, 0.0);
          vec3 q505 = q504 / vec3(1.0, 1.0, 0.16);
          M m506 = M(sdPyramid((q505 + vec3(0.0, 0.081775, 0.0)) / 0.060574, 2.700012) * 0.060574, vec3(0.007604, 0.052472, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.21825, 0.678014, 0.055058), vec4(7.0, 0.185371, 1.0, 0.0), (q476 - vec3(0.0, -0.002659, 0.0)), 0.0);
          M m507 = m506; m507.d = m506.d * 0.16;
          u477 = mU(u477, m507);
        }
        {
          vec3 q508 = q476 * mat3(-0.509959, 0.0, 0.860199, 0.0, 1.0, 0.0, -0.860199, 0.0, -0.509959);
          vec3 q509 = q508 * mat3(1.0, 0.0, 0.0, 0.0, 0.925052, 0.37984, 0.0, -0.37984, 0.925052);
          vec3 q510 = q509 - vec3(0.0, 0.07989, 0.0);
          vec3 q511 = q510 / vec3(1.0, 1.0, 0.16);
          M m512 = M(sdPyramid((q511 + vec3(0.0, 0.07989, 0.0)) / 0.066147, 2.415545) * 0.066147, vec3(0.007604, 0.052472, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.21825, 0.678014, 0.055058), vec4(7.0, 0.185371, 1.0, 0.0), (q476 - vec3(0.0, -0.002659, 0.0)), 0.0);
          M m513 = m512; m513.d = m512.d * 0.16;
          u477 = mU(u477, m513);
        }
        {
          vec3 q514 = q476 * mat3(0.651404, 0.0, 0.758731, 0.0, 1.0, 0.0, -0.758731, 0.0, 0.651404);
          vec3 q515 = q514 * mat3(1.0, 0.0, 0.0, 0.0, 0.961632, 0.274342, 0.0, -0.274342, 0.961632);
          vec3 q516 = q515 - vec3(0.0, 0.09429, 0.0);
          vec3 q517 = q516 / vec3(1.0, 1.0, 0.16);
          M m518 = M(sdPyramid((q517 + vec3(0.0, 0.09429, 0.0)) / 0.062308, 3.026586) * 0.062308, vec3(0.007604, 0.052472, 0.007206), vec3(0.6, 0.0, 0.0), vec3(0.21825, 0.678014, 0.055058), vec4(7.0, 0.185371, 1.0, 0.0), (q476 - vec3(0.0, -0.002659, 0.0)), 0.0);
          M m519 = m518; m519.d = m518.d * 0.16;
          u477 = mU(u477, m519);
        }
        vec3 q520 = q469 - vec3(0.0, 2.0, 0.0);
        M m521 = M(sdBox(q520, vec3(0.5, 2.0, 0.5)), vec3(0.03048, 0.147027, 0.017138), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m522 = mI(u477, m521);
        u471 = mU(u471, m522);
      }
      if (sdBox(q469 - vec3(0.0, 0.135614, 0.0), vec3(0.51, 0.145614, 0.51)) < u471.d) {
        vec3 q523 = q469 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q524 = q523 - vec3(0.029777, 0.134257, 0.025745);
        vec3 id525 = clamp(round(q524 / vec3(0.220971, 1.0, 0.220971) + vec3(2.0, 0.0, 2.0)), vec3(0.0), vec3(4.0, 0.0, 4.0));
        vec3 q526 = q524 - vec3(0.220971, 1.0, 0.220971) * (id525 - vec3(2.0, 0.0, 2.0));
        vec3 q527 = q526 - vec3(-0.012777, -0.134257, 0.003255);
        M u528 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q529 = q527 * mat3(0.979034, 0.0, -0.203695, 0.0, 1.0, 0.0, 0.203695, 0.0, 0.979034);
          vec3 q530 = q529 * mat3(1.0, 0.0, 0.0, 0.0, 0.975163, 0.221486, 0.0, -0.221486, 0.975163);
          vec3 q531 = q530 - vec3(0.0, 0.120591, 0.0);
          vec3 q532 = q531 / vec3(1.0, 1.0, 0.16);
          M m533 = M(sdPyramid((q532 + vec3(0.0, 0.120591, 0.0)) / 0.072662, 3.319228) * 0.072662, vec3(0.009132, 0.117956, 0.007926), vec3(0.6, 0.0, 0.0), vec3(0.200686, 0.540701, 0.062225), vec4(7.0, 0.273944, 1.0, 0.0), (q527 - vec3(0.0, -0.002715, 0.0)), 0.0);
          M m534 = m533; m534.d = m533.d * 0.16;
          u528 = mU(u528, m534);
        }
        {
          vec3 q535 = q527 * mat3(0.354276, 0.0, -0.935141, 0.0, 1.0, 0.0, 0.935141, 0.0, 0.354276);
          vec3 q536 = q535 * mat3(1.0, 0.0, 0.0, 0.0, 0.943923, 0.330166, 0.0, -0.330166, 0.943923);
          vec3 q537 = q536 - vec3(0.0, 0.138929, 0.0);
          vec3 q538 = q537 / vec3(1.0, 1.0, 0.16);
          M m539 = M(sdPyramid((q538 + vec3(0.0, 0.138929, 0.0)) / 0.05703, 4.872168) * 0.05703, vec3(0.009132, 0.117956, 0.007926), vec3(0.6, 0.0, 0.0), vec3(0.200686, 0.540701, 0.062225), vec4(7.0, 0.273944, 1.0, 0.0), (q527 - vec3(0.0, -0.002715, 0.0)), 0.0);
          M m540 = m539; m540.d = m539.d * 0.16;
          u528 = mU(u528, m540);
        }
        {
          vec3 q541 = q527 * mat3(-0.062414, 0.0, -0.99805, 0.0, 1.0, 0.0, 0.99805, 0.0, -0.062414);
          vec3 q542 = q541 * mat3(1.0, 0.0, 0.0, 0.0, 0.890013, 0.455935, 0.0, -0.455935, 0.890013);
          vec3 q543 = q542 - vec3(0.0, 0.122405, 0.0);
          vec3 q544 = q543 / vec3(1.0, 1.0, 0.16);
          M m545 = M(sdPyramid((q544 + vec3(0.0, 0.122405, 0.0)) / 0.074445, 3.288454) * 0.074445, vec3(0.009132, 0.117956, 0.007926), vec3(0.6, 0.0, 0.0), vec3(0.200686, 0.540701, 0.062225), vec4(7.0, 0.273944, 1.0, 0.0), (q527 - vec3(0.0, -0.002715, 0.0)), 0.0);
          M m546 = m545; m546.d = m545.d * 0.16;
          u528 = mU(u528, m546);
        }
        {
          vec3 q547 = q527 * mat3(-0.957058, 0.0, -0.289898, 0.0, 1.0, 0.0, 0.289898, 0.0, -0.957058);
          vec3 q548 = q547 * mat3(1.0, 0.0, 0.0, 0.0, 0.945445, 0.325782, 0.0, -0.325782, 0.945445);
          vec3 q549 = q548 - vec3(0.0, 0.127283, 0.0);
          vec3 q550 = q549 / vec3(1.0, 1.0, 0.16);
          M m551 = M(sdPyramid((q550 + vec3(0.0, 0.127283, 0.0)) / 0.068336, 3.725194) * 0.068336, vec3(0.009132, 0.117956, 0.007926), vec3(0.6, 0.0, 0.0), vec3(0.200686, 0.540701, 0.062225), vec4(7.0, 0.273944, 1.0, 0.0), (q527 - vec3(0.0, -0.002715, 0.0)), 0.0);
          M m552 = m551; m552.d = m551.d * 0.16;
          u528 = mU(u528, m552);
        }
        {
          vec3 q553 = q527 * mat3(-0.784036, 0.0, 0.620716, 0.0, 1.0, 0.0, -0.620716, 0.0, -0.784036);
          vec3 q554 = q553 * mat3(1.0, 0.0, 0.0, 0.0, 0.941823, 0.33611, 0.0, -0.33611, 0.941823);
          vec3 q555 = q554 - vec3(0.0, 0.080371, 0.0);
          vec3 q556 = q555 / vec3(1.0, 1.0, 0.16);
          M m557 = M(sdPyramid((q556 + vec3(0.0, 0.080371, 0.0)) / 0.064473, 2.493174) * 0.064473, vec3(0.009132, 0.117956, 0.007926), vec3(0.6, 0.0, 0.0), vec3(0.200686, 0.540701, 0.062225), vec4(7.0, 0.273944, 1.0, 0.0), (q527 - vec3(0.0, -0.002715, 0.0)), 0.0);
          M m558 = m557; m558.d = m557.d * 0.16;
          u528 = mU(u528, m558);
        }
        {
          vec3 q559 = q527 * mat3(-0.118336, 0.0, 0.992974, 0.0, 1.0, 0.0, -0.992974, 0.0, -0.118336);
          vec3 q560 = q559 * mat3(1.0, 0.0, 0.0, 0.0, 0.945815, 0.324705, 0.0, -0.324705, 0.945815);
          vec3 q561 = q560 - vec3(0.0, 0.132608, 0.0);
          vec3 q562 = q561 / vec3(1.0, 1.0, 0.16);
          M m563 = M(sdPyramid((q562 + vec3(0.0, 0.132608, 0.0)) / 0.059176, 4.4818) * 0.059176, vec3(0.009132, 0.117956, 0.007926), vec3(0.6, 0.0, 0.0), vec3(0.200686, 0.540701, 0.062225), vec4(7.0, 0.273944, 1.0, 0.0), (q527 - vec3(0.0, -0.002715, 0.0)), 0.0);
          M m564 = m563; m564.d = m563.d * 0.16;
          u528 = mU(u528, m564);
        }
        {
          vec3 q565 = q527 * mat3(0.740257, 0.0, 0.672324, 0.0, 1.0, 0.0, -0.672324, 0.0, 0.740257);
          vec3 q566 = q565 * mat3(1.0, 0.0, 0.0, 0.0, 0.960605, 0.277916, 0.0, -0.277916, 0.960605);
          vec3 q567 = q566 - vec3(0.0, 0.140293, 0.0);
          vec3 q568 = q567 / vec3(1.0, 1.0, 0.16);
          M m569 = M(sdPyramid((q568 + vec3(0.0, 0.140293, 0.0)) / 0.076298, 3.677491) * 0.076298, vec3(0.009132, 0.117956, 0.007926), vec3(0.6, 0.0, 0.0), vec3(0.200686, 0.540701, 0.062225), vec4(7.0, 0.273944, 1.0, 0.0), (q527 - vec3(0.0, -0.002715, 0.0)), 0.0);
          M m570 = m569; m570.d = m569.d * 0.16;
          u528 = mU(u528, m570);
        }
        vec3 q571 = q469 - vec3(0.0, 2.0, 0.0);
        M m572 = M(sdBox(q571, vec3(0.5, 2.0, 0.5)), vec3(0.03048, 0.147027, 0.017138), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m573 = mI(u528, m572);
        u471 = mU(u471, m573);
      }
      if (sdBox(q469 - vec3(0.049547, 0.176756, 0.008186), vec3(0.460453, 0.186756, 0.469644)) < u471.d) {
        vec3 q574 = q469 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q575 = q574 - vec3(0.074319, 0.174661, 0.005596);
        vec3 id576 = clamp(round(q575 / vec3(0.468789, 1.0, 0.468789) + vec3(0.5, 0.0, 0.5)), vec3(0.0), vec3(1.0, 0.0, 1.0));
        vec3 q577 = q575 - vec3(0.468789, 1.0, 0.468789) * (id576 - vec3(0.5, 0.0, 0.5));
        vec3 q578 = q577 - vec3(-0.040319, -0.174661, 0.052404);
        M u579 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q580 = q578 * mat3(0.956372, 0.0, 0.292153, 0.0, 1.0, 0.0, -0.292153, 0.0, 0.956372);
          vec3 q581 = q580 * mat3(1.0, 0.0, 0.0, 0.0, 0.939019, 0.343866, 0.0, -0.343866, 0.939019);
          vec3 q582 = q581 - vec3(0.0, 0.140453, 0.0);
          vec3 q583 = q582 / vec3(1.0, 1.0, 0.16);
          M m584 = M(sdPyramid((q583 + vec3(0.0, 0.140453, 0.0)) / 0.052639, 5.336414) * 0.052639, vec3(0.006273, 0.074728, 0.005607), vec3(0.6, 0.0, 0.0), vec3(0.17268, 0.612396, 0.032685), vec4(7.0, 0.357703, 1.0, 0.0), (q578 - vec3(0.0, -0.004191, 0.0)), 0.0);
          M m585 = m584; m585.d = m584.d * 0.16;
          u579 = mU(u579, m585);
        }
        {
          vec3 q586 = q578 * mat3(0.331514, 0.0, -0.94345, 0.0, 1.0, 0.0, 0.94345, 0.0, 0.331514);
          vec3 q587 = q586 * mat3(1.0, 0.0, 0.0, 0.0, 0.722595, 0.691271, 0.0, -0.691271, 0.722595);
          vec3 q588 = q587 - vec3(0.0, 0.194642, 0.0);
          vec3 q589 = q588 / vec3(1.0, 1.0, 0.16);
          M m590 = M(sdPyramid((q589 + vec3(0.0, 0.194642, 0.0)) / 0.053633, 7.258243) * 0.053633, vec3(0.006273, 0.074728, 0.005607), vec3(0.6, 0.0, 0.0), vec3(0.17268, 0.612396, 0.032685), vec4(7.0, 0.357703, 1.0, 0.0), (q578 - vec3(0.0, -0.004191, 0.0)), 0.0);
          M m591 = m590; m591.d = m590.d * 0.16;
          u579 = mU(u579, m591);
        }
        {
          vec3 q592 = q578 * mat3(-0.347619, 0.0, -0.937636, 0.0, 1.0, 0.0, 0.937636, 0.0, -0.347619);
          vec3 q593 = q592 * mat3(1.0, 0.0, 0.0, 0.0, 0.866066, 0.49993, 0.0, -0.49993, 0.866066);
          vec3 q594 = q593 - vec3(0.0, 0.195886, 0.0);
          vec3 q595 = q594 / vec3(1.0, 1.0, 0.16);
          M m596 = M(sdPyramid((q595 + vec3(0.0, 0.195886, 0.0)) / 0.060168, 6.511282) * 0.060168, vec3(0.006273, 0.074728, 0.005607), vec3(0.6, 0.0, 0.0), vec3(0.17268, 0.612396, 0.032685), vec4(7.0, 0.357703, 1.0, 0.0), (q578 - vec3(0.0, -0.004191, 0.0)), 0.0);
          M m597 = m596; m597.d = m596.d * 0.16;
          u579 = mU(u579, m597);
        }
        {
          vec3 q598 = q578 * mat3(-0.963188, 0.0, -0.268829, 0.0, 1.0, 0.0, 0.268829, 0.0, -0.963188);
          vec3 q599 = q598 * mat3(1.0, 0.0, 0.0, 0.0, 0.80315, 0.595777, 0.0, -0.595777, 0.80315);
          vec3 q600 = q599 - vec3(0.0, 0.218379, 0.0);
          vec3 q601 = q600 / vec3(1.0, 1.0, 0.16);
          M m602 = M(sdPyramid((q601 + vec3(0.0, 0.218379, 0.0)) / 0.057294, 7.623092) * 0.057294, vec3(0.006273, 0.074728, 0.005607), vec3(0.6, 0.0, 0.0), vec3(0.17268, 0.612396, 0.032685), vec4(7.0, 0.357703, 1.0, 0.0), (q578 - vec3(0.0, -0.004191, 0.0)), 0.0);
          M m603 = m602; m603.d = m602.d * 0.16;
          u579 = mU(u579, m603);
        }
        {
          vec3 q604 = q578 * mat3(-0.81886, 0.0, 0.573993, 0.0, 1.0, 0.0, -0.573993, 0.0, -0.81886);
          vec3 q605 = q604 * mat3(1.0, 0.0, 0.0, 0.0, 0.711225, 0.702965, 0.0, -0.702965, 0.711225);
          vec3 q606 = q605 - vec3(0.0, 0.188362, 0.0);
          vec3 q607 = q606 / vec3(1.0, 1.0, 0.16);
          M m608 = M(sdPyramid((q607 + vec3(0.0, 0.188362, 0.0)) / 0.074519, 5.055377) * 0.074519, vec3(0.006273, 0.074728, 0.005607), vec3(0.6, 0.0, 0.0), vec3(0.17268, 0.612396, 0.032685), vec4(7.0, 0.357703, 1.0, 0.0), (q578 - vec3(0.0, -0.004191, 0.0)), 0.0);
          M m609 = m608; m609.d = m608.d * 0.16;
          u579 = mU(u579, m609);
        }
        {
          vec3 q610 = q578 * mat3(-0.472974, 0.0, 0.881077, 0.0, 1.0, 0.0, -0.881077, 0.0, -0.472974);
          vec3 q611 = q610 * mat3(1.0, 0.0, 0.0, 0.0, 0.73962, 0.673024, 0.0, -0.673024, 0.73962);
          vec3 q612 = q611 - vec3(0.0, 0.139275, 0.0);
          vec3 q613 = q612 / vec3(1.0, 1.0, 0.16);
          M m614 = M(sdPyramid((q613 + vec3(0.0, 0.139275, 0.0)) / 0.068895, 4.043094) * 0.068895, vec3(0.006273, 0.074728, 0.005607), vec3(0.6, 0.0, 0.0), vec3(0.17268, 0.612396, 0.032685), vec4(7.0, 0.357703, 1.0, 0.0), (q578 - vec3(0.0, -0.004191, 0.0)), 0.0);
          M m615 = m614; m615.d = m614.d * 0.16;
          u579 = mU(u579, m615);
        }
        {
          vec3 q616 = q578 * mat3(0.870765, 0.0, 0.491699, 0.0, 1.0, 0.0, -0.491699, 0.0, 0.870765);
          vec3 q617 = q616 * mat3(1.0, 0.0, 0.0, 0.0, 0.867639, 0.497195, 0.0, -0.497195, 0.867639);
          vec3 q618 = q617 - vec3(0.0, 0.156292, 0.0);
          vec3 q619 = q618 / vec3(1.0, 1.0, 0.16);
          M m620 = M(sdPyramid((q619 + vec3(0.0, 0.156292, 0.0)) / 0.070975, 4.404145) * 0.070975, vec3(0.006273, 0.074728, 0.005607), vec3(0.6, 0.0, 0.0), vec3(0.17268, 0.612396, 0.032685), vec4(7.0, 0.357703, 1.0, 0.0), (q578 - vec3(0.0, -0.004191, 0.0)), 0.0);
          M m621 = m620; m621.d = m620.d * 0.16;
          u579 = mU(u579, m621);
        }
        vec3 q622 = q469 - vec3(0.0, 2.0, 0.0);
        M m623 = M(sdBox(q622, vec3(0.5, 2.0, 0.5)), vec3(0.03048, 0.147027, 0.017138), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m624 = mI(u579, m623);
        u471 = mU(u471, m624);
      }
      u470 = mU(u470, u471);
    }
    {
      vec3 q625 = q469 - vec3(0.0, -0.02, 0.0);
      M m626 = M(sdBox(q625, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u470 = mU(u470, m626);
    }
    u0 = mU(u0, u470);
  }
  if (sdBox(p - vec3(2.24, 0.373324, 0.0), vec3(0.51, 0.423324, 0.51)) < u0.d) {
    vec3 q627 = p - vec3(2.24, 0.0, 0.0);
    M u628 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q627 - vec3(0.0, 0.393324, 0.0), vec3(0.51, 0.403324, 0.51)) < u628.d) {
      M u629 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q627 - vec3(0.0, 0.207613, 0.0), vec3(0.51, 0.217613, 0.51)) < u629.d) {
        vec3 q630 = q627 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q631 = q630 - vec3(0.001326, 0.206958, 0.014954);
        vec3 id632 = clamp(round(q631 / vec3(0.075197, 1.0, 0.075197) + vec3(7.5, 0.0, 7.5)), vec3(0.0), vec3(15.0, 0.0, 15.0));
        vec3 q633 = q631 - vec3(0.075197, 1.0, 0.075197) * (id632 - vec3(7.5, 0.0, 7.5));
        vec3 q634 = q633 - vec3(-0.001326, -0.206958, -0.014954);
        M u635 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q636 = q634 * mat3(0.997921, 0.0, -0.064452, 0.0, 1.0, 0.0, 0.064452, 0.0, 0.997921);
          vec3 q637 = q636 * mat3(1.0, 0.0, 0.0, 0.0, 0.99785, 0.065544, 0.0, -0.065544, 0.99785);
          vec3 q638 = q637 - vec3(0.0, 0.156991, 0.0);
          vec3 q639 = q638 / vec3(1.0, 1.0, 1.0);
          M m640 = M(sdPyramid((q639 + vec3(0.0, 0.156991, 0.0)) / 0.039989, 7.851722) * 0.039989, vec3(0.226891, 0.151246, 0.023831), vec3(0.6, 0.0, 0.0), vec3(0.722765, 0.449042, 0.057455), vec4(7.0, 0.315927, 1.0, 0.0), (q634 - vec3(0.0, -0.001311, 0.0)), 0.0);
          M m641 = m640; m641.d = m640.d * 1.0;
          u635 = mU(u635, m641);
        }
        {
          vec3 q642 = q634 - vec3(0.001326, 0.343306, 0.020537);
          vec3 q643 = q642 * mat3(0.997921, 0.0, -0.064452, 0.006752, 0.994498, 0.104536, 0.064097, -0.104754, 0.99243);
          M m644 = M(sdEllipsoid(q643, vec3(0.022, 0.07, 0.022)), vec3(0.603827, 0.318547, 0.027212), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u635 = mU(u635, m644);
        }
        vec3 q645 = q627 - vec3(0.0, 2.0, 0.0);
        M m646 = M(sdBox(q645, vec3(0.5, 2.0, 0.5)), vec3(0.278894, 0.200157, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m647 = mI(u635, m646);
        u629 = mU(u629, m647);
      }
      if (sdBox(q627 - vec3(0.0, 0.260336, 0.0), vec3(0.51, 0.270336, 0.51)) < u629.d) {
        vec3 q648 = q627 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q649 = q648 - vec3(0.036558, 0.259082, 0.058918);
        vec3 id650 = clamp(round(q649 / vec3(0.118714, 1.0, 0.118714) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q651 = q649 - vec3(0.118714, 1.0, 0.118714) * (id650 - vec3(4.5, 0.0, 4.5));
        vec3 q652 = q651 - vec3(-0.019558, -0.259082, -0.029918);
        M u653 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q654 = q652 * mat3(0.844191, 0.0, -0.536043, 0.0, 1.0, 0.0, 0.536043, 0.0, 0.844191);
          vec3 q655 = q654 * mat3(1.0, 0.0, 0.0, 0.0, 0.991929, 0.126796, 0.0, -0.126796, 0.991929);
          vec3 q656 = q655 - vec3(0.0, 0.210535, 0.0);
          vec3 q657 = q656 / vec3(1.0, 1.0, 1.0);
          M m658 = M(sdPyramid((q657 + vec3(0.0, 0.210535, 0.0)) / 0.039545, 10.647724) * 0.039545, vec3(0.254872, 0.190413, 0.035709), vec3(0.6, 0.0, 0.0), vec3(0.8806, 0.524383, 0.082753), vec4(7.0, 0.422685, 1.0, 0.0), (q652 - vec3(0.0, -0.002507, 0.0)), 0.0);
          M m659 = m658; m659.d = m658.d * 1.0;
          u653 = mU(u653, m659);
        }
        {
          vec3 q660 = q652 - vec3(0.028619, 0.447671, 0.045071);
          vec3 q661 = q660 * mat3(0.844191, 0.0, -0.536043, 0.108292, 0.979381, 0.170544, 0.52499, -0.202021, 0.826785);
          M m662 = M(sdEllipsoid(q661, vec3(0.022, 0.07, 0.022)), vec3(0.669351, 0.373619, 0.041436), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u653 = mU(u653, m662);
        }
        vec3 q663 = q627 - vec3(0.0, 2.0, 0.0);
        M m664 = M(sdBox(q663, vec3(0.5, 2.0, 0.5)), vec3(0.278894, 0.200157, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m665 = mI(u653, m664);
        u629 = mU(u629, m665);
      }
      if (sdBox(q627 - vec3(0.0, 0.284403, 0.004635), vec3(0.51, 0.294403, 0.505365)) < u629.d) {
        vec3 q666 = q627 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q667 = q666 - vec3(0.079774, 0.283329, 0.06366);
        vec3 id668 = clamp(round(q667 / vec3(0.128099, 1.0, 0.128099) + vec3(4.0, 0.0, 4.0)), vec3(0.0), vec3(8.0, 0.0, 8.0));
        vec3 q669 = q667 - vec3(0.128099, 1.0, 0.128099) * (id668 - vec3(4.0, 0.0, 4.0));
        vec3 q670 = q669 - vec3(-0.045774, -0.283329, -0.00566);
        M u671 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q672 = q670 * mat3(0.082832, 0.0, -0.996564, 0.0, 1.0, 0.0, 0.996564, 0.0, 0.082832);
          vec3 q673 = q672 * mat3(1.0, 0.0, 0.0, 0.0, 0.989404, 0.145186, 0.0, -0.145186, 0.989404);
          vec3 q674 = q673 - vec3(0.0, 0.235302, 0.0);
          vec3 q675 = q674 / vec3(1.0, 1.0, 1.0);
          M m676 = M(sdPyramid((q675 + vec3(0.0, 0.235302, 0.0)) / 0.029587, 15.905533) * 0.029587, vec3(0.190452, 0.140223, 0.032715), vec3(0.6, 0.0, 0.0), vec3(0.678849, 0.542525, 0.112698), vec4(7.0, 0.469914, 1.0, 0.0), (q670 - vec3(0.0, -0.002148, 0.0)), 0.0);
          M m677 = m676; m677.d = m676.d * 1.0;
          u671 = mU(u671, m677);
        }
        {
          vec3 q678 = q670 - vec3(0.06809, 0.495618, 0.00566);
          vec3 q679 = q678 * mat3(0.082832, 0.0, -0.996564, 0.230222, 0.97295, 0.019136, 0.969606, -0.231016, 0.080592);
          M m680 = M(sdEllipsoid(q679, vec3(0.022, 0.07, 0.022)), vec3(0.738845, 0.43388, 0.059254), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u671 = mU(u671, m680);
        }
        vec3 q681 = q627 - vec3(0.0, 2.0, 0.0);
        M m682 = M(sdBox(q681, vec3(0.5, 2.0, 0.5)), vec3(0.278894, 0.200157, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m683 = mI(u671, m682);
        u629 = mU(u629, m683);
      }
      if (sdBox(q627 - vec3(0.0, 0.366137, 0.0), vec3(0.51, 0.376137, 0.51)) < u629.d) {
        vec3 q684 = q627 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q685 = q684 - vec3(0.068484, 0.365364, 0.052603);
        vec3 id686 = clamp(round(q685 / vec3(0.117815, 1.0, 0.117815) + vec3(4.5, 0.0, 4.5)), vec3(0.0), vec3(9.0, 0.0, 9.0));
        vec3 q687 = q685 - vec3(0.117815, 1.0, 0.117815) * (id686 - vec3(4.5, 0.0, 4.5));
        vec3 q688 = q687 - vec3(-0.017484, -0.365364, 0.034397);
        M u689 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q690 = q688 * mat3(-0.910483, 0.0, -0.413547, 0.0, 1.0, 0.0, 0.413547, 0.0, -0.910483);
          vec3 q691 = q690 * mat3(1.0, 0.0, 0.0, 0.0, 0.995788, 0.091684, 0.0, -0.091684, 0.995788);
          vec3 q692 = q691 - vec3(0.0, 0.316236, 0.0);
          vec3 q693 = q692 / vec3(1.0, 1.0, 1.0);
          M m694 = M(sdPyramid((q693 + vec3(0.0, 0.316236, 0.0)) / 0.0337, 18.767726) * 0.0337, vec3(0.157331, 0.112816, 0.021736), vec3(0.6, 0.0, 0.0), vec3(0.934011, 0.686515, 0.090821), vec4(7.0, 0.632897, 1.0, 0.0), (q688 - vec3(0.0, -0.001545, 0.0)), 0.0);
          M m695 = m694; m695.d = m694.d * 1.0;
          u689 = mU(u689, m695);
        }
        {
          vec3 q696 = q688 - vec3(0.023981, 0.659807, -0.052797);
          vec3 q697 = q696 * mat3(-0.910483, 0.0, -0.413547, 0.060532, 0.989229, -0.13327, 0.409093, -0.146373, -0.900676);
          M m698 = M(sdEllipsoid(q697, vec3(0.022, 0.07, 0.022)), vec3(0.812375, 0.499458, 0.080887), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u689 = mU(u689, m698);
        }
        vec3 q699 = q627 - vec3(0.0, 2.0, 0.0);
        M m700 = M(sdBox(q699, vec3(0.5, 2.0, 0.5)), vec3(0.278894, 0.200157, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m701 = mI(u689, m700);
        u629 = mU(u629, m701);
      }
      if (sdBox(q627 - vec3(0.0, 0.393324, 0.0), vec3(0.51, 0.403324, 0.51)) < u629.d) {
        vec3 q702 = q627 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q703 = q702 - vec3(0.071385, 0.392058, 0.065142);
        vec3 id704 = clamp(round(q703 / vec3(0.149518, 1.0, 0.149518) + vec3(3.5, 0.0, 3.5)), vec3(0.0), vec3(7.0, 0.0, 7.0));
        vec3 q705 = q703 - vec3(0.149518, 1.0, 0.149518) * (id704 - vec3(3.5, 0.0, 3.5));
        vec3 q706 = q705 - vec3(-0.003385, -0.392058, 0.050858);
        M u707 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q708 = q706 * mat3(-0.998797, 0.0, -0.049044, 0.0, 1.0, 0.0, 0.049044, 0.0, -0.998797);
          vec3 q709 = q708 * mat3(1.0, 0.0, 0.0, 0.0, 0.992129, 0.125216, 0.0, -0.125216, 0.992129);
          vec3 q710 = q709 - vec3(0.0, 0.344544, 0.0);
          vec3 q711 = q710 / vec3(1.0, 1.0, 1.0);
          M m712 = M(sdPyramid((q711 + vec3(0.0, 0.344544, 0.0)) / 0.040435, 17.041905) * 0.040435, vec3(0.169722, 0.128747, 0.019051), vec3(0.6, 0.0, 0.0), vec3(0.657897, 0.476255, 0.075348), vec4(7.0, 0.688728, 1.0, 0.0), (q706 - vec3(0.0, -0.002532, 0.0)), 0.0);
          M m713 = m712; m713.d = m712.d * 1.0;
          u707 = mU(u707, m713);
        }
        {
          vec3 q714 = q706 - vec3(0.004232, 0.713665, -0.086181);
          vec3 q715 = q714 * mat3(-0.998797, 0.0, -0.049044, 0.009785, 0.979893, -0.199285, 0.048057, -0.199525, -0.978714);
          M m716 = M(sdEllipsoid(q715, vec3(0.022, 0.07, 0.022)), vec3(0.890005, 0.570482, 0.106539), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u707 = mU(u707, m716);
        }
        vec3 q717 = q627 - vec3(0.0, 2.0, 0.0);
        M m718 = M(sdBox(q717, vec3(0.5, 2.0, 0.5)), vec3(0.278894, 0.200157, 0.033843), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m719 = mI(u707, m718);
        u629 = mU(u629, m719);
      }
      u628 = mU(u628, u629);
    }
    {
      vec3 q720 = q627 - vec3(0.0, -0.02, 0.0);
      M m721 = M(sdBox(q720, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u628 = mU(u628, m721);
    }
    u0 = mU(u0, u628);
  }
  if (sdBox(p - vec3(3.36, 0.068005, 0.0), vec3(0.51, 0.118005, 0.51)) < u0.d) {
    vec3 q722 = p - vec3(3.36, 0.0, 0.0);
    M u723 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q722 - vec3(0.0, 0.086005, 0.0), vec3(0.51, 0.100005, 0.51)) < u723.d) {
      M u724 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q722 - vec3(0.0, 0.019309, 0.0), vec3(0.51, 0.029309, 0.51)) < u724.d) {
        vec3 q725 = q722 * mat3(0.978148, 0.0, 0.207912, 0.0, 1.0, 0.0, -0.207912, 0.0, 0.978148);
        vec3 q726 = q725 - vec3(-0.000657, 0.018881, 0.00418);
        vec3 id727 = clamp(round(q726 / vec3(0.052869, 1.0, 0.052869) + vec3(11.0, 0.0, 11.0)), vec3(0.0), vec3(22.0, 0.0, 22.0));
        vec3 q728 = q726 - vec3(0.052869, 1.0, 0.052869) * (id727 - vec3(11.0, 0.0, 11.0));
        vec3 q729 = q728 - vec3(0.000657, -0.018881, -0.00418);
        vec3 q730 = q729 * mat3(0.987865, 0.0, 0.155316, 0.0, 1.0, 0.0, -0.155316, 0.0, 0.987865);
        vec3 q731 = q730 * mat3(1.0, 0.0, 0.0, 0.0, 0.975796, 0.218683, 0.0, -0.218683, 0.975796);
        vec3 q732 = q731 - vec3(0.0, 0.019349, 0.0);
        vec3 q733 = q732 / vec3(1.0, 1.0, 0.16);
        M m734 = M(sdPyramid((q733 + vec3(0.0, 0.019349, 0.0)) / 0.048929, 0.790908) * 0.048929, vec3(0.010424, 0.060871, 0.014331), vec3(0.6, 0.0, 0.0), vec3(0.079634, 0.497943, 0.066036), vec4(7.0, 0.039474, 1.0, 0.0), (q729 - vec3(0.0, -0.000856, 0.0)), 0.0);
        M m735 = m734; m735.d = m734.d * 0.16;
        vec3 q736 = q722 - vec3(0.0, 2.0, 0.0);
        M m737 = M(sdBox(q736, vec3(0.5, 2.0, 0.5)), vec3(0.024158, 0.161413, 0.02776), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m738 = mI(m735, m737);
        u724 = mU(u724, m738);
      }
      if (sdBox(q722 - vec3(0.0, 0.026342, 0.0), vec3(0.51, 0.036342, 0.51)) < u724.d) {
        vec3 q739 = q722 * mat3(0.992546, 0.0, 0.121869, 0.0, 1.0, 0.0, -0.121869, 0.0, 0.992546);
        vec3 q740 = q739 - vec3(0.018572, 0.026092, 0.031371);
        vec3 id741 = clamp(round(q740 / vec3(0.058537, 1.0, 0.058537) + vec3(9.5, 0.0, 9.5)), vec3(0.0), vec3(19.0, 0.0, 19.0));
        vec3 q742 = q740 - vec3(0.058537, 1.0, 0.058537) * (id741 - vec3(9.5, 0.0, 9.5));
        vec3 q743 = q742 - vec3(-0.001572, -0.026092, -0.002371);
        vec3 q744 = q743 * mat3(0.83344, 0.0, -0.552609, 0.0, 1.0, 0.0, 0.552609, 0.0, 0.83344);
        vec3 q745 = q744 * mat3(1.0, 0.0, 0.0, 0.0, 0.994107, 0.108407, 0.0, -0.108407, 0.994107);
        vec3 q746 = q745 - vec3(0.0, 0.026246, 0.0);
        vec3 q747 = q746 / vec3(1.0, 1.0, 0.16);
        M m748 = M(sdPyramid((q747 + vec3(0.0, 0.026246, 0.0)) / 0.057678, 0.910094) * 0.057678, vec3(0.008091, 0.115334, 0.013572), vec3(0.6, 0.0, 0.0), vec3(0.148449, 0.49532, 0.110856), vec4(7.0, 0.053183, 1.0, 0.0), (q743 - vec3(0.0, -0.0005, 0.0)), 0.0);
        M m749 = m748; m749.d = m748.d * 0.16;
        vec3 q750 = q722 - vec3(0.0, 2.0, 0.0);
        M m751 = M(sdBox(q750, vec3(0.5, 2.0, 0.5)), vec3(0.024158, 0.161413, 0.02776), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m752 = mI(m749, m751);
        u724 = mU(u724, m752);
      }
      if (sdBox(q722 - vec3(0.0, 0.031945, 0.0), vec3(0.51, 0.041945, 0.51)) < u724.d) {
        vec3 q753 = q722 * mat3(0.999391, 0.0, 0.034899, 0.0, 1.0, 0.0, -0.034899, 0.0, 0.999391);
        vec3 q754 = q753 - vec3(0.038599, 0.031518, 0.056563);
        vec3 id755 = clamp(round(q754 / vec3(0.076548, 1.0, 0.076548) + vec3(7.0, 0.0, 7.0)), vec3(0.0), vec3(14.0, 0.0, 14.0));
        vec3 q756 = q754 - vec3(0.076548, 1.0, 0.076548) * (id755 - vec3(7.0, 0.0, 7.0));
        vec3 q757 = q756 - vec3(-0.004599, -0.031518, 0.001437);
        vec3 q758 = q757 * mat3(-0.298147, 0.0, -0.95452, 0.0, 1.0, 0.0, 0.95452, 0.0, -0.298147);
        vec3 q759 = q758 * mat3(1.0, 0.0, 0.0, 0.0, 0.988517, 0.15111, 0.0, -0.15111, 0.988517);
        vec3 q760 = q759 - vec3(0.0, 0.031885, 0.0);
        vec3 q761 = q760 / vec3(1.0, 1.0, 0.16);
        M m762 = M(sdPyramid((q761 + vec3(0.0, 0.031885, 0.0)) / 0.070613, 0.90308) * 0.070613, vec3(0.006439, 0.122396, 0.014812), vec3(0.6, 0.0, 0.0), vec3(0.10753, 0.694795, 0.090172), vec4(7.0, 0.064744, 1.0, 0.0), (q757 - vec3(0.0, -0.000854, 0.0)), 0.0);
        M m763 = m762; m763.d = m762.d * 0.16;
        vec3 q764 = q722 - vec3(0.0, 2.0, 0.0);
        M m765 = M(sdBox(q764, vec3(0.5, 2.0, 0.5)), vec3(0.024158, 0.161413, 0.02776), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m766 = mI(m763, m765);
        u724 = mU(u724, m766);
      }
      if (sdBox(q722 - vec3(0.0, 0.032066, 0.0), vec3(0.51, 0.042066, 0.51)) < u724.d) {
        vec3 q767 = q722 * mat3(0.99863, 0.0, -0.052336, 0.0, 1.0, 0.0, 0.052336, 0.0, 0.99863);
        vec3 q768 = q767 - vec3(0.054187, 0.031721, 0.08384);
        vec3 id769 = clamp(round(q768 / vec3(0.0592, 1.0, 0.0592) + vec3(9.5, 0.0, 9.5)), vec3(0.0), vec3(19.0, 0.0, 19.0));
        vec3 q770 = q768 - vec3(0.0592, 1.0, 0.0592) * (id769 - vec3(9.5, 0.0, 9.5));
        vec3 q771 = q770 - vec3(-0.003187, -0.031721, 0.00316);
        vec3 q772 = q771 * mat3(-0.704068, 0.0, -0.710132, 0.0, 1.0, 0.0, 0.710132, 0.0, -0.704068);
        vec3 q773 = q772 * mat3(1.0, 0.0, 0.0, 0.0, 0.990137, 0.140105, 0.0, -0.140105, 0.990137);
        vec3 q774 = q773 - vec3(0.0, 0.032037, 0.0);
        vec3 q775 = q774 / vec3(1.0, 1.0, 0.16);
        M m776 = M(sdPyramid((q775 + vec3(0.0, 0.032037, 0.0)) / 0.061585, 1.040427) * 0.061585, vec3(0.006594, 0.09333, 0.009709), vec3(0.6, 0.0, 0.0), vec3(0.171539, 0.677603, 0.12804), vec4(7.0, 0.064823, 1.0, 0.0), (q771 - vec3(0.0, -0.00069, 0.0)), 0.0);
        M m777 = m776; m777.d = m776.d * 0.16;
        vec3 q778 = q722 - vec3(0.0, 2.0, 0.0);
        M m779 = M(sdBox(q778, vec3(0.5, 2.0, 0.5)), vec3(0.024158, 0.161413, 0.02776), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m780 = mI(m777, m779);
        u724 = mU(u724, m780);
      }
      if (sdBox(q722 - vec3(0.0, 0.039, 0.0), vec3(0.51, 0.049, 0.51)) < u724.d) {
        vec3 q781 = q722 * mat3(0.990268, 0.0, -0.139173, 0.0, 1.0, 0.0, 0.139173, 0.0, 0.990268);
        vec3 q782 = q781 - vec3(0.066416, 0.038373, 0.107187);
        vec3 id783 = clamp(round(q782 / vec3(0.075912, 1.0, 0.075912) + vec3(7.5, 0.0, 7.5)), vec3(0.0), vec3(15.0, 0.0, 15.0));
        vec3 q784 = q782 - vec3(0.075912, 1.0, 0.075912) * (id783 - vec3(7.5, 0.0, 7.5));
        vec3 q785 = q784 - vec3(0.001584, -0.038373, 0.008813);
        vec3 q786 = q785 * mat3(-0.984221, 0.0, 0.176943, 0.0, 1.0, 0.0, -0.176943, 0.0, -0.984221);
        vec3 q787 = q786 * mat3(1.0, 0.0, 0.0, 0.0, 0.973836, 0.227253, 0.0, -0.227253, 0.973836);
        vec3 q788 = q787 - vec3(0.0, 0.039404, 0.0);
        vec3 q789 = q788 / vec3(1.0, 1.0, 0.16);
        M m790 = M(sdPyramid((q789 + vec3(0.0, 0.039404, 0.0)) / 0.06901, 1.14197) * 0.06901, vec3(0.008254, 0.134697, 0.013), vec3(0.6, 0.0, 0.0), vec3(0.175494, 0.535598, 0.118012), vec4(7.0, 0.079255, 1.0, 0.0), (q785 - vec3(0.0, -0.001255, 0.0)), 0.0);
        M m791 = m790; m791.d = m790.d * 0.16;
        vec3 q792 = q722 - vec3(0.0, 2.0, 0.0);
        M m793 = M(sdBox(q792, vec3(0.5, 2.0, 0.5)), vec3(0.024158, 0.161413, 0.02776), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m794 = mI(m791, m793);
        u724 = mU(u724, m794);
      }
      if (sdBox(q722 - vec3(0.0, 0.044857, 0.0), vec3(0.51, 0.054857, 0.51)) < u724.d) {
        vec3 q795 = q722 * mat3(0.97437, 0.0, -0.224951, 0.0, 1.0, 0.0, 0.224951, 0.0, 0.97437);
        vec3 q796 = q795 - vec3(0.079508, 0.044538, 0.140186);
        vec3 id797 = clamp(round(q796 / vec3(0.053971, 1.0, 0.053971) + vec3(10.5, 0.0, 10.5)), vec3(0.0), vec3(21.0, 0.0, 21.0));
        vec3 q798 = q796 - vec3(0.053971, 1.0, 0.053971) * (id797 - vec3(10.5, 0.0, 10.5));
        vec3 q799 = q798 - vec3(0.005492, -0.044538, 0.004814);
        vec3 q800 = q799 * mat3(-0.659212, 0.0, 0.751957, 0.0, 1.0, 0.0, -0.751957, 0.0, -0.659212);
        vec3 q801 = q800 * mat3(1.0, 0.0, 0.0, 0.0, 0.986821, 0.161814, 0.0, -0.161814, 0.986821);
        vec3 q802 = q801 - vec3(0.0, 0.045132, 0.0);
        vec3 q803 = q802 / vec3(1.0, 1.0, 0.16);
        M m804 = M(sdPyramid((q803 + vec3(0.0, 0.045132, 0.0)) / 0.049374, 1.828183) * 0.049374, vec3(0.010572, 0.080959, 0.013983), vec3(0.6, 0.0, 0.0), vec3(0.199798, 0.535198, 0.153196), vec4(7.0, 0.090354, 1.0, 0.0), (q799 - vec3(0.0, -0.000639, 0.0)), 0.0);
        M m805 = m804; m805.d = m804.d * 0.16;
        vec3 q806 = q722 - vec3(0.0, 2.0, 0.0);
        M m807 = M(sdBox(q806, vec3(0.5, 2.0, 0.5)), vec3(0.024158, 0.161413, 0.02776), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m808 = mI(m805, m807);
        u724 = mU(u724, m808);
      }
      if (sdBox(q722 - vec3(0.000043, 0.073748, -0.038479), vec3(0.043146, 0.087748, 0.043146)) < u724.d) {
        vec3 q809 = q722 - vec3(0.000043, 0.073748, -0.038479);
        vec3 id810 = clamp(round(q809 / vec3(1.0, 1.0, 1.0) + vec3(0.0, 0.0, 0.0)), vec3(0.0), vec3(0.0, 0.0, 0.0));
        vec3 q811 = q809 - vec3(1.0, 1.0, 1.0) * (id810 - vec3(0.0, 0.0, 0.0));
        vec3 q812 = q811 - vec3(0.0, -0.073748, 0.0);
        M u813 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q814 = q812 - vec3(0.0, 0.056748, 0.0);
          vec3 q815 = q814 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
          M m816 = M(sdCapsule(q815, 0.004, 0.056748), vec3(0.033719, 0.19703, 0.035094), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u813 = mU(u813, m816);
        }
        {
          vec3 q817 = q812 - vec3(0.0, 0.113497, 0.0);
          M m818 = M(length(q817) - 0.033146, vec3(1.0, 1.0, 0.890005), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u813 = mU(u813, m818);
        }
        {
          vec3 q819 = q812 - vec3(0.0, 0.139497, 0.0);
          M m820 = M(length(q819) - 0.012, vec3(1.0, 0.638283, 0.019607), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u813 = mU(u813, m820);
        }
        u724 = mU(u724, u813);
      }
      if (sdBox(q722 - vec3(-0.044474, 0.082279, -0.005674), vec3(0.037688, 0.096279, 0.037688)) < u724.d) {
        vec3 q821 = q722 - vec3(-0.044474, 0.082279, -0.005674);
        vec3 id822 = clamp(round(q821 / vec3(1.0, 1.0, 1.0) + vec3(0.0, 0.0, 0.0)), vec3(0.0), vec3(0.0, 0.0, 0.0));
        vec3 q823 = q821 - vec3(1.0, 1.0, 1.0) * (id822 - vec3(0.0, 0.0, 0.0));
        vec3 q824 = q823 - vec3(0.0, -0.082279, 0.0);
        M u825 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q826 = q824 - vec3(0.0, 0.065279, 0.0);
          vec3 q827 = q826 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
          M m828 = M(sdCapsule(q827, 0.004, 0.065279), vec3(0.033719, 0.19703, 0.035094), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u825 = mU(u825, m828);
        }
        {
          vec3 q829 = q824 - vec3(0.0, 0.130557, 0.0);
          M m830 = M(length(q829) - 0.027688, vec3(1.0, 0.692071, 0.033105), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u825 = mU(u825, m830);
        }
        {
          vec3 q831 = q824 - vec3(0.0, 0.156557, 0.0);
          M m832 = M(length(q831) - 0.012, vec3(1.0, 0.638283, 0.019607), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u825 = mU(u825, m832);
        }
        u724 = mU(u724, u825);
      }
      if (sdBox(q722 - vec3(-0.021065, 0.086005, 0.042657), vec3(0.035535, 0.100005, 0.035535)) < u724.d) {
        vec3 q833 = q722 - vec3(-0.021065, 0.086005, 0.042657);
        vec3 id834 = clamp(round(q833 / vec3(1.0, 1.0, 1.0) + vec3(0.0, 0.0, 0.0)), vec3(0.0), vec3(0.0, 0.0, 0.0));
        vec3 q835 = q833 - vec3(1.0, 1.0, 1.0) * (id834 - vec3(0.0, 0.0, 0.0));
        vec3 q836 = q835 - vec3(0.0, -0.086005, 0.0);
        M u837 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q838 = q836 - vec3(0.0, 0.069005, 0.0);
          vec3 q839 = q838 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
          M m840 = M(sdCapsule(q839, 0.004, 0.069005), vec3(0.033719, 0.19703, 0.035094), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u837 = mU(u837, m840);
        }
        {
          vec3 q841 = q836 - vec3(0.0, 0.138011, 0.0);
          M m842 = M(length(q841) - 0.025535, vec3(0.638283, 0.214041, 0.890005), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u837 = mU(u837, m842);
        }
        {
          vec3 q843 = q836 - vec3(0.0, 0.164011, 0.0);
          M m844 = M(length(q843) - 0.012, vec3(1.0, 0.638283, 0.019607), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u837 = mU(u837, m844);
        }
        u724 = mU(u724, u837);
      }
      u723 = mU(u723, u724);
    }
    {
      vec3 q845 = q722 - vec3(0.0, -0.02, 0.0);
      M m846 = M(sdBox(q845, vec3(0.5, 0.02, 0.5)), vec3(0.068478, 0.042311, 0.021219), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u723 = mU(u723, m846);
    }
    u0 = mU(u0, u723);
  }
  return u0;
}
