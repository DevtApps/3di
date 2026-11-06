
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

float sdPoly3(vec2 p) {
  const vec2 v[7] = vec2[7](vec2(0.0, 0.0), vec2(0.7, 0.0), vec2(0.7, 0.35), vec2(1.0, 0.35), vec2(0.35, 1.0), vec2(-0.3, 0.35), vec2(0.0, 0.35));
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = 6; i < 7; j = i, i++) {
    vec2 e = v[j] - v[i];
    vec2 w = p - v[i];
    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(b, b));
    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
    if (all(c) || all(not(c))) s = -s;
  }
  return s * sqrt(d);
}
float sdPoly6(vec2 p) {
  const vec2 v[6] = vec2[6](vec2(0.5, 0.0), vec2(0.25, 0.433013), vec2(-0.25, 0.433013), vec2(-0.5, 0.0), vec2(-0.25, -0.433013), vec2(0.25, -0.433013));
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = 5; i < 6; j = i, i++) {
    vec2 e = v[j] - v[i];
    vec2 w = p - v[i];
    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(b, b));
    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
    if (all(c) || all(not(c))) s = -s;
  }
  return s * sqrt(d);
}
float sdPoly9(vec2 p) {
  const vec2 v[10] = vec2[10](vec2(0.5, 0.0), vec2(0.177984, 0.129313), vec2(0.154508, 0.475528), vec2(-0.067984, 0.209232), vec2(-0.404508, 0.293893), vec2(-0.22, 0.0), vec2(-0.404508, -0.293893), vec2(-0.067984, -0.209232), vec2(0.154508, -0.475528), vec2(0.177984, -0.129313));
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = 9; i < 10; j = i, i++) {
    vec2 e = v[j] - v[i];
    vec2 w = p - v[i];
    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(b, b));
    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
    if (all(c) || all(not(c))) s = -s;
  }
  return s * sqrt(d);
}
float sdPoly12(vec2 p) {
  const vec2 v[3] = vec2[3](vec2(-0.5, -0.3), vec2(0.5, -0.3), vec2(0.5, 0.3));
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = 2; i < 3; j = i, i++) {
    vec2 e = v[j] - v[i];
    vec2 w = p - v[i];
    vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(b, b));
    bvec3 c = bvec3(p.y >= v[i].y, p.y < v[j].y, e.x * w.y > e.y * w.x);
    if (all(c) || all(not(c))) s = -s;
  }
  return s * sqrt(d);
}
float sdPoly15(vec2 p) {
  const vec2 v[56] = vec2[56](vec2(0.0, 0.0), vec2(0.06875, -0.005859), vec2(0.16875, -0.015625), vec2(0.271875, -0.017578), vec2(0.35, 0.0), vec2(0.398438, 0.042578), vec2(0.43125, 0.103125), vec2(0.448437, 0.174609), vec2(0.45, 0.25), vec2(0.429375, 0.332813), vec2(0.38875, 0.425), vec2(0.34125, 0.517188), vec2(0.3, 0.6), vec2(0.263203, 0.671875), vec2(0.225625, 0.7375), vec2(0.195234, 0.796875), vec2(0.18, 0.85), vec2(0.189219, 0.896875), vec2(0.21625, 0.9375), vec2(0.245156, 0.971875), vec2(0.26, 1.0), vec2(0.258125, 1.020703), vec2(0.2475, 1.034375), vec2(0.228125, 1.043359), vec2(0.2, 1.05), vec2(0.155156, 1.053516), vec2(0.09625, 1.053125), vec2(0.039219, 1.051172), vec2(0.0, 1.05), vec2(-0.039219, 1.051172), vec2(-0.09625, 1.053125), vec2(-0.155156, 1.053516), vec2(-0.2, 1.05), vec2(-0.228125, 1.043359), vec2(-0.2475, 1.034375), vec2(-0.258125, 1.020703), vec2(-0.26, 1.0), vec2(-0.245156, 0.971875), vec2(-0.21625, 0.9375), vec2(-0.189219, 0.896875), vec2(-0.18, 0.85), vec2(-0.195234, 0.796875), vec2(-0.225625, 0.7375), vec2(-0.263203, 0.671875), vec2(-0.3, 0.6), vec2(-0.34125, 0.517188), vec2(-0.38875, 0.425), vec2(-0.429375, 0.332813), vec2(-0.45, 0.25), vec2(-0.448437, 0.174609), vec2(-0.43125, 0.103125), vec2(-0.398438, 0.042578), vec2(-0.35, 0.0), vec2(-0.271875, -0.017578), vec2(-0.16875, -0.015625), vec2(-0.06875, -0.005859));
  float d = dot(p - v[0], p - v[0]);
  float s = 1.0;
  for (int i = 0, j = 55; i < 56; j = i, i++) {
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
  {
    M m1 = M(p.y, vec3(0.791298, 0.760525, 0.686685), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  if (cullVis(0) && sdBox(p - vec3(-3.0, 0.5, -2.2), vec3(0.66, 0.51, 0.135)) < u0.d) {
    vec3 q2 = p - vec3(-3.35, 0.0, -2.2);
    M m4 = M(sdExt(sdPoly3(q2.xy), q2.z, 0.125, 0.0), vec3(0.693872, 0.0865, 0.078187), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m4);
  }
  if (cullVis(1) && sdBox(p - vec3(-1.8, 0.25, -2.2), vec3(0.51, 0.26, 0.443013)) < u0.d) {
    vec3 q5 = p - vec3(-1.8, 0.25, -2.2);
    M m7 = M(sdExt(sdPoly6(q5.xz), q5.y, 0.25, 0.0), vec3(0.104616, 0.266356, 0.863157), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m7);
  }
  if (cullVis(2) && sdBox(p - vec3(-0.6, 0.1, -2.2), vec3(0.462254, 0.11, 0.485528)) < u0.d) {
    vec3 q8 = p - vec3(-0.647746, 0.1, -2.2);
    M m10 = M(sdExt(sdPoly9(q8.xz), q8.y, 0.1, 0.03), vec3(0.871367, 0.527115, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m10);
  }
  if (cullVis(3) && sdBox(p - vec3(0.6, 0.3, -2.2), vec3(0.51, 0.31, 0.41)) < u0.d) {
    vec3 q11 = p - vec3(0.6, 0.3, -2.2);
    M m13 = M(sdExt(sdPoly12(q11.xy), q11.z, 0.4, 0.0), vec3(0.198069, 0.520996, 0.198069), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m13);
  }
  if (cullVis(4) && sdBox(p - vec3(1.8, 0.535547, -2.2), vec3(0.46, 0.545547, 0.46)) < u0.d) {
    vec3 q14 = p - vec3(1.8, 0.017578, -2.2);
    M m16 = M(sdPoly15(vec2(length(q14.xz), q14.y)), vec3(0.068478, 0.278894, 0.47932), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m16);
  }
  if (cullVis(5)) {
    vec3 q17 = p - vec3(3.0, 0.25, -2.2);
    vec3 q18 = q17 - vec3(0.0, -0.25, 0.0);
    M m19 = M(length(q18) - 0.5, vec3(0.47932, 0.198069, 0.630757), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q20 = q18 - vec3(0.0, 0.25, 0.0);
    M m21 = M(sdBox(q20, vec3(0.505, 0.25, 0.505)), vec3(0.47932, 0.198069, 0.630757), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m22 = mI(m19, m21);
    u0 = mU(u0, m22);
  }
  if (cullVis(6)) {
    vec3 q23 = p - vec3(4.1, 0.4, -2.2);
    M m24 = M(sdCyl(q23, 0.4, 0.4), vec3(0.246201, 0.246201, 0.246201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m25 = M(sdCyl(q23, 0.32, 0.41), vec3(0.246201, 0.246201, 0.246201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m26 = mS(m24, m25);
    u0 = mU(u0, m26);
  }
  if (cullVis(7) && sdBox(p - vec3(-3.0, 0.7, 1.9), vec3(0.26, 0.71, 0.26)) < u0.d) {
    vec3 q27 = p - vec3(-3.0, 0.7, 1.9);
    float tp28 = clamp((q27.y - -0.7) / 1.4, 0.0, 1.0);
    float sc29 = mix(1.0, 0.45, tp28);
    vec3 q30 = vec3(q27.x / sc29, q27.y, q27.z / sc29);
    M m31 = M(sdCyl(q30, 0.25, 0.7), vec3(0.584078, 0.371238, 0.144128), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m32 = m31; m32.d = m31.d * 0.429984;
    u0 = mU(u0, m32);
  }
  if (cullVis(8) && sdBox(p - vec3(-1.8, 1.823992, 1.9), vec3(1.273992, 1.833992, 0.15)) < u0.d) {
    vec3 q33 = p - vec3(-1.8, 1.123992, 1.9);
    float c34 = cos(-0.997331 * (q33.y - 0.0)), s35 = sin(-0.997331 * (q33.y - 0.0));
    vec3 q36 = vec3(s35 * (q33.y - 0.0) + c34 * q33.x, c34 * (q33.y - 0.0) - s35 * q33.x + 0.0, q33.z);
    vec3 q37 = q36 - vec3(0.0, 0.7, 0.0);
    M m38 = M(sdCyl(q37, 0.14, 0.7), vec3(0.351533, 0.084376, 0.026241), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m39 = m38; m39.d = m38.d / sqrt(1.0 + 1.969047);
    u0 = mU(u0, m39);
  }
  if (cullVis(9)) {
    vec3 q40 = p - vec3(-0.9, 0.6, 1.9);
    vec3 q41 = vec3(q40.x - 0.5 * (q40.y - -0.6), q40.y, q40.z - 0.0 * (q40.y - -0.6));
    M m42 = M(sdBox(q41, vec3(0.25, 0.6, 0.1)), vec3(0.132868, 0.401978, 0.246201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m43 = m42; m43.d = m42.d / sqrt(1.25);
    u0 = mU(u0, m43);
  }
  if (cullVis(10) && sdBox(p - vec3(0.7, 0.05, 1.9), vec3(0.654127, 0.06, 0.654127)) < u0.d) {
    vec3 q44 = p - vec3(0.7, -0.05, 1.9);
    float sec45 = 0.785398, rr47 = length(q44.xz);
    float an46 = mod(atan(q44.z, q44.x) + 0.5 * sec45, sec45) - 0.5 * sec45;
    vec3 q48 = vec3(rr47 * cos(an46), q44.y, rr47 * sin(an46));
    vec3 q49 = q48 - vec3(0.45, 0.1, 0.0);
    M m50 = M(sdEllipsoid(q49, vec3(0.12, 0.05, 0.3)), vec3(0.806952, 0.194618, 0.351533), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m50);
  }
  if (cullVis(11)) {
    vec3 q51 = p - vec3(1.9, 0.75, 1.9);
    vec3 q52 = q51 - clamp(q51, -vec3(0.0, 0.45, 0.0), vec3(0.0, 0.45, 0.0));
    M m53 = M(length(q52) - 0.3, vec3(0.693872, 0.262251, 0.049707), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m53);
  }
  if (cullVis(12) && sdBox(p - vec3(3.1, 0.7, 1.9), vec3(0.434264, 0.71, 0.434264)) < u0.d) {
    vec3 q54 = p - vec3(3.1, 0.7, 1.9);
    float c55 = cos(0.747998 * q54.y), s56 = sin(0.747998 * q54.y);
    vec3 q57 = vec3(c55 * q54.x - s56 * q54.z, q54.y, s56 * q54.x + c55 * q54.z);
    float tp58 = clamp((q57.y - -0.7) / 1.4, 0.0, 1.0);
    float sc59 = mix(1.0, 0.5, tp58);
    vec3 q60 = vec3(q57.x / sc59, q57.y, q57.z / sc59);
    M m61 = M(sdBox(q60, vec3(0.3, 0.7, 0.3)), vec3(0.318547, 0.401978, 0.401978), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m62 = m61; m62.d = m61.d * 0.47851;
    M m63 = m62; m63.d = m62.d * 0.953155;
    u0 = mU(u0, m63);
  }
  return u0;
}
