
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
    M m1 = M(p.y, vec3(0.693872, 0.64448, 0.545724), vec3(0.6, 0.0, 0.0), vec3(0.48515, 0.434154, 0.351533), vec4(5.0, 0.5, 1.0, 0.0), p, 0.0);
    u0 = mU(u0, m1);
  }
  {
    vec3 q2 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q3 = q2 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q4 = q3 - vec3(0.0, -0.95, 0.0);
    vec3 q5 = q4 - vec3(0.0, 0.97, 0.0);
    M m6 = M(sdEllipsoid(q5, vec3(0.17, 0.11, 0.11)), vec3(0.028426, 0.07036, 0.201556), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q7 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q8 = q7 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q9 = q8 - vec3(0.0, 0.07, 0.0);
    vec3 q10 = q9 * rotEuler(vec3(0.0, (sin((uTime * 5.0)) * 6.0), 0.0));
    vec3 q11 = q10 - vec3(0.0, -1.02, 0.0);
    vec3 q12 = q11 - vec3(0.0, 1.22, 0.0);
    M m13 = M(sdEllipsoid(q12, vec3(0.2, 0.27, 0.13)), vec3(0.745404, 0.0865, 0.046665), vec3(0.6, 0.0, 0.0), vec3(0.896269, 0.799103, 0.651406), vec4(4.0, 0.06, 1.0, 0.0), q11, 0.0);
    M m14 = mUs(m6, m13, 0.025);
    vec3 q15 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q16 = q15 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q17 = q16 - vec3(0.0, 0.07, 0.0);
    vec3 q18 = q17 * rotEuler(vec3(0.0, (sin((uTime * 5.0)) * 6.0), 0.0));
    vec3 q19 = q18 - vec3(0.0, 0.43, 0.0);
    vec3 q20 = q19 * rotEuler(vec3(0.0, ((-sin((uTime * 5.0))) * 4.0), 0.0));
    vec3 q21 = q20 - vec3(0.0, -1.45, 0.0);
    M u22 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q21 - vec3(0.0, 1.5425, 0.011), vec3(0.14, 0.1975, 0.151)) < u22.d) {
      M u23 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q24 = q21 - vec3(0.0, 1.45, 0.0);
        vec3 q25 = q24 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m26 = M(sdCapsule(q25, 0.045, 0.05), vec3(0.806952, 0.48515, 0.304987), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u23 = mU(u23, m26);
      }
      {
        vec3 q27 = q21 - vec3(0.0, 1.6, 0.0);
        M m28 = M(length(q27) - 0.13, vec3(0.806952, 0.48515, 0.304987), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u23 = mU(u23, m28);
      }
      {
        vec3 q29 = q21 - vec3(0.0, 1.59, 0.13);
        M m30 = M(length(q29) - 0.022, vec3(0.806952, 0.48515, 0.304987), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u23 = mU(u23, m30);
      }
      u22 = mU(u22, u23);
    }
    {
      vec3 q31 = q21;
      q31.x = abs(q31.x);
      vec3 q32 = q31 - vec3(0.045, 1.63, 0.115);
      M m33 = M(length(q32) - 0.018, vec3(0.011612, 0.011612, 0.011612), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u22 = mU(u22, m33);
    }
    {
      vec3 q34 = q21 - vec3(0.0, 1.62, -0.01);
      M m35 = M(length(q34) - 0.138, vec3(0.043735, 0.017642, 0.008023), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      vec3 q36 = q21 - vec3(0.0, 1.47, 0.12);
      M m37 = M(sdBox(q36, vec3(0.2, 0.2, 0.2)), vec3(0.043735, 0.017642, 0.008023), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m38 = mS(m35, m37);
      u22 = mU(u22, m38);
    }
    M m39 = mUs(m14, u22, 0.025);
    vec3 q40 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q41 = q40 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q42 = q41 - vec3(0.0, 0.07, 0.0);
    vec3 q43 = q42 * rotEuler(vec3(0.0, (sin((uTime * 5.0)) * 6.0), 0.0));
    vec3 q44 = q43 - vec3(0.21, 0.36, 0.0);
    vec3 q45 = q44 * rotEuler(vec3((sin((uTime * 5.0)) * 25.0), 0.0, 8.0));
    vec3 q46 = q45 - vec3(-0.21, -1.38, 0.0);
    vec3 q47 = q46 - vec3(0.23, 1.25, 0.0);
    vec3 q48 = q47 * mat3(-0.988372, -0.152057, 0.0, 0.152057, -0.988372, 0.0, 0.0, 0.0, 1.0);
    M m49 = M(sdCapsule(q48, 0.052, 0.131529), vec3(0.745404, 0.0865, 0.046665), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m50 = mUs(m39, m49, 0.025);
    vec3 q51 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q52 = q51 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q53 = q52 - vec3(0.0, 0.07, 0.0);
    vec3 q54 = q53 * rotEuler(vec3(0.0, (sin((uTime * 5.0)) * 6.0), 0.0));
    vec3 q55 = q54 - vec3(0.21, 0.36, 0.0);
    vec3 q56 = q55 * rotEuler(vec3((sin((uTime * 5.0)) * 25.0), 0.0, 8.0));
    vec3 q57 = q56 - vec3(0.04, -0.26, 0.0);
    vec3 q58 = q57 * mat3(1.0, 0.0, 0.0, 0.0, 0.906308, -0.422618, 0.0, 0.422618, 0.906308);
    vec3 q59 = q58 - vec3(-0.25, -1.12, 0.0);
    M u60 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q61 = q59 - vec3(0.255, 1.0, 0.0);
      vec3 q62 = q61 * mat3(-0.999133, -0.041631, 0.0, 0.041631, -0.999133, 0.0, 0.0, 0.0, 1.0);
      M m63 = M(sdCapsule(q62, 0.042, 0.120104), vec3(0.806952, 0.48515, 0.304987), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m63);
    }
    {
      vec3 q64 = q59 - vec3(0.265, 0.84, 0.0);
      M m65 = M(length(q64) - 0.05, vec3(0.806952, 0.48515, 0.304987), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m65);
    }
    M m66 = mUs(m50, u60, 0.025);
    vec3 q67 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q68 = q67 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q69 = q68 - vec3(0.1, -0.02, 0.0);
    vec3 q70 = q69 * rotEuler(vec3(((-sin((uTime * 5.0))) * 28.0), 0.0, 0.0));
    vec3 q71 = q70 - vec3(-0.1, -0.93, 0.0);
    vec3 q72 = q71 - vec3(0.1, 0.715, 0.0);
    vec3 q73 = q72 * mat3(-1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0);
    M m74 = M(sdCapsule(q73, 0.068, 0.215), vec3(0.028426, 0.07036, 0.201556), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m75 = mUs(m66, m74, 0.025);
    vec3 q76 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q77 = q76 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q78 = q77 - vec3(0.1, -0.02, 0.0);
    vec3 q79 = q78 * rotEuler(vec3(((-sin((uTime * 5.0))) * 28.0), 0.0, 0.0));
    vec3 q80 = q79 - vec3(0.0, -0.43, 0.0);
    vec3 q81 = q80 * rotEuler(vec3((5.0 + (50.0 * clamp(cos((uTime * 5.0)), 0.0, 1.0))), 0.0, 0.0));
    vec3 q82 = q81 - vec3(-0.1, -0.5, 0.0);
    vec3 q83 = q82 - vec3(0.1, 0.3, 0.0);
    vec3 q84 = q83 * mat3(-1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0);
    M m85 = M(sdCapsule(q84, 0.056, 0.2), vec3(0.028426, 0.07036, 0.201556), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m86 = mUs(m75, m85, 0.025);
    vec3 q87 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q88 = q87 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q89 = q88 - vec3(0.1, -0.02, 0.0);
    vec3 q90 = q89 * rotEuler(vec3(((-sin((uTime * 5.0))) * 28.0), 0.0, 0.0));
    vec3 q91 = q90 - vec3(0.0, -0.43, 0.0);
    vec3 q92 = q91 * rotEuler(vec3((5.0 + (50.0 * clamp(cos((uTime * 5.0)), 0.0, 1.0))), 0.0, 0.0));
    vec3 q93 = q92 - vec3(-0.1, -0.5, 0.0);
    vec3 q94 = q93 - vec3(0.1, 0.04, 0.04);
    M m95 = M(sdBox(q94, vec3(0.015, 0.005, 0.085)) - 0.035, vec3(0.042311, 0.023153, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m96 = mUs(m86, m95, 0.025);
    vec3 q97 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q98 = q97 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q99 = q98 - vec3(0.0, 0.07, 0.0);
    vec3 q100 = q99 * rotEuler(vec3(0.0, (sin((uTime * 5.0)) * 6.0), 0.0));
    vec3 q101 = q100 - vec3(-0.21, 0.36, 0.0);
    vec3 q102 = q101 * rotEuler(vec3((sin(((uTime * 5.0) + 3.141593)) * 25.0), 0.0, -8.0));
    vec3 q103 = q102 - vec3(0.21, -1.38, 0.0);
    vec3 q104 = q103 - vec3(-0.23, 1.25, 0.0);
    vec3 q105 = q104 * mat3(-0.988372, 0.152057, 0.0, -0.152057, -0.988372, 0.0, 0.0, 0.0, 1.0);
    M m106 = M(sdCapsule(q105, 0.052, 0.131529), vec3(0.745404, 0.0865, 0.046665), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m107 = mUs(m96, m106, 0.025);
    vec3 q108 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q109 = q108 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q110 = q109 - vec3(0.0, 0.07, 0.0);
    vec3 q111 = q110 * rotEuler(vec3(0.0, (sin((uTime * 5.0)) * 6.0), 0.0));
    vec3 q112 = q111 - vec3(-0.21, 0.36, 0.0);
    vec3 q113 = q112 * rotEuler(vec3((sin(((uTime * 5.0) + 3.141593)) * 25.0), 0.0, -8.0));
    vec3 q114 = q113 - vec3(-0.04, -0.26, 0.0);
    vec3 q115 = q114 * mat3(1.0, 0.0, 0.0, 0.0, 0.906308, -0.422618, 0.0, 0.422618, 0.906308);
    vec3 q116 = q115 - vec3(0.25, -1.12, 0.0);
    M u117 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q118 = q116 - vec3(-0.255, 1.0, 0.0);
      vec3 q119 = q118 * mat3(-0.999133, 0.041631, 0.0, -0.041631, -0.999133, 0.0, 0.0, 0.0, 1.0);
      M m120 = M(sdCapsule(q119, 0.042, 0.120104), vec3(0.806952, 0.48515, 0.304987), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u117 = mU(u117, m120);
    }
    {
      vec3 q121 = q116 - vec3(-0.265, 0.84, 0.0);
      M m122 = M(length(q121) - 0.05, vec3(0.806952, 0.48515, 0.304987), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u117 = mU(u117, m122);
    }
    M m123 = mUs(m107, u117, 0.025);
    vec3 q124 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q125 = q124 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q126 = q125 - vec3(-0.1, -0.02, 0.0);
    vec3 q127 = q126 * rotEuler(vec3(((-sin(((uTime * 5.0) + 3.141593))) * 28.0), 0.0, 0.0));
    vec3 q128 = q127 - vec3(0.1, -0.93, 0.0);
    vec3 q129 = q128 - vec3(-0.1, 0.715, 0.0);
    vec3 q130 = q129 * mat3(-1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0);
    M m131 = M(sdCapsule(q130, 0.068, 0.215), vec3(0.028426, 0.07036, 0.201556), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m132 = mUs(m123, m131, 0.025);
    vec3 q133 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q134 = q133 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q135 = q134 - vec3(-0.1, -0.02, 0.0);
    vec3 q136 = q135 * rotEuler(vec3(((-sin(((uTime * 5.0) + 3.141593))) * 28.0), 0.0, 0.0));
    vec3 q137 = q136 - vec3(0.0, -0.43, 0.0);
    vec3 q138 = q137 * rotEuler(vec3((5.0 + (50.0 * clamp(cos(((uTime * 5.0) + 3.141593)), 0.0, 1.0))), 0.0, 0.0));
    vec3 q139 = q138 - vec3(0.1, -0.5, 0.0);
    vec3 q140 = q139 - vec3(-0.1, 0.3, 0.0);
    vec3 q141 = q140 * mat3(-1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 1.0);
    M m142 = M(sdCapsule(q141, 0.056, 0.2), vec3(0.028426, 0.07036, 0.201556), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m143 = mUs(m132, m142, 0.025);
    vec3 q144 = p - vec3(((cos((uTime * 0.5)) * 1.6) - 1.6), ((abs(cos((uTime * 5.0))) * 0.025) + 0.95), (sin((uTime * 0.5)) * 1.6));
    vec3 q145 = q144 * rotEuler(vec3(0.0, (((-(uTime * 0.5)) * 180.0) / 3.141593), 0.0));
    vec3 q146 = q145 - vec3(-0.1, -0.02, 0.0);
    vec3 q147 = q146 * rotEuler(vec3(((-sin(((uTime * 5.0) + 3.141593))) * 28.0), 0.0, 0.0));
    vec3 q148 = q147 - vec3(0.0, -0.43, 0.0);
    vec3 q149 = q148 * rotEuler(vec3((5.0 + (50.0 * clamp(cos(((uTime * 5.0) + 3.141593)), 0.0, 1.0))), 0.0, 0.0));
    vec3 q150 = q149 - vec3(0.1, -0.5, 0.0);
    vec3 q151 = q150 - vec3(-0.1, 0.04, 0.04);
    M m152 = M(sdBox(q151, vec3(0.015, 0.005, 0.085)) - 0.035, vec3(0.042311, 0.023153, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m153 = mUs(m143, m152, 0.025);
    u0 = mU(u0, m153);
  }
  return u0;
}
