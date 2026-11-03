
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

uniform highp sampler2D uCode;
vec4 codeFetch(int col, int row) {
  int index = row * 5 + col;
  int width = textureSize(uCode, 0).x;
  return texelFetch(uCode, ivec2(index % width, index / width), 0);
}
M ci0(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    M m1 = M(sdRoundCone(p, vec3(0.0, 0.0, 0.0), vec3(0.0, -0.041481, 0.006667), 0.09, 0.101667), vec3(0.391572, 0.144128, 0.031896), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 240.09);
    u0 = mU(u0, m1);
  }
  {
    M m2 = M(sdRoundCone(p, vec3(0.0, -0.041481, 0.006667), vec3(0.0, -0.100741, 0.015556), 0.101667, 0.113333), vec3(0.391572, 0.144128, 0.031896), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 240.09);
    u0 = mU(u0, m2);
  }
  {
    M m3 = M(sdRoundCone(p, vec3(0.0, -0.100741, 0.015556), vec3(0.0, -0.16, 0.02), 0.113333, 0.125), vec3(0.391572, 0.144128, 0.031896), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 240.09);
    u0 = mU(u0, m3);
  }
  {
    M m4 = M(sdRoundCone(p, vec3(0.0, -0.16, 0.02), vec3(0.0, -0.219259, 0.015556), 0.125, 0.115), vec3(0.391572, 0.144128, 0.031896), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 240.09);
    u0 = mU(u0, m4);
  }
  {
    M m5 = M(sdRoundCone(p, vec3(0.0, -0.219259, 0.015556), vec3(0.0, -0.278519, 0.006667), 0.115, 0.105), vec3(0.391572, 0.144128, 0.031896), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 240.09);
    u0 = mU(u0, m5);
  }
  {
    M m6 = M(sdRoundCone(p, vec3(0.0, -0.278519, 0.006667), vec3(0.0, -0.32, 0.0), 0.105, 0.095), vec3(0.391572, 0.144128, 0.031896), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 240.09);
    u0 = mU(u0, m6);
  }
  return u0;
}

M mapAll(vec3 p, bool wantMat) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    vec3 q1 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.1, 0.93, 0.262));
    M m2 = M(length(q1) - 0.061, vec3(0.011612, 0.004391, 0.002428), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m2);
  }
  {
    vec3 q3 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.1, 0.93, 0.262));
    M m4 = M(length(q3) - 0.061, vec3(0.011612, 0.004391, 0.002428), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m4);
  }
  {
    vec3 q5 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.84, 0.37));
    M m6 = M(sdEllipsoid(q5, vec3(0.06, 0.042, 0.045)), vec3(0.025187, 0.01033, 0.006995), vec3(0.3, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 160.03);
    u0 = mU(u0, m6);
  }
  {
    vec3 q7 = mat3(1.0, 0.0, 0.0, 0.0, 0.882948, -0.469472, 0.0, 0.469472, 0.882948) * (p - vec3(0.0, 0.725, 0.33));
    M m8 = M(sdEllipsoid(q7, vec3(0.055, 0.018, 0.065)), vec3(0.783538, 0.254152, 0.287441), vec3(0.35, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m8);
  }
  {
    vec3 q9 = mat3(-1.0, 0.0, 0.0, 0.0, -0.986394, -0.164399, 0.0, -0.164399, 0.986394) * (p - vec3(0.0, 0.79, 0.3775));
    M m10 = M(sdCapsule(q9, 0.006, 0.015207), vec3(0.042311, 0.015996, 0.009134), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m10);
  }
  if (sdBox(p - vec3(0.0, 0.566066, -0.060625), vec3(0.34, 0.583934, 0.440625)) < u0.d) {
    vec3 q11 = p - vec3(0.0, 0.25, -0.08);
    M m12 = M(sdEllipsoid(q11, vec3(0.28, 0.24, 0.3)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    vec3 q13 = p - vec3(0.0, 0.47, 0.06);
    vec3 q14 = q13 * mat3(1.0, 0.0, 0.0, 0.0, 0.970296, -0.241922, 0.0, 0.241922, 0.970296);
    M m15 = M(sdEllipsoid(q14, vec3(0.23, 0.28, 0.21)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m16 = mUs(m12, m15, 0.04);
    vec3 q17 = p - vec3(0.0, 0.68, 0.08);
    M m18 = M(sdEllipsoid(q17, vec3(0.18, 0.15, 0.16)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m19 = mUs(m16, m18, 0.04);
    vec3 q20 = p - vec3(0.0, 0.9, 0.08);
    M m21 = M(sdEllipsoid(q20, vec3(0.27, 0.24, 0.23)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m22 = mUs(m19, m21, 0.04);
    vec3 q23 = p - vec3(0.0, 1.0, 0.12);
    M m24 = M(sdEllipsoid(q23, vec3(0.2, 0.12, 0.15)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m25 = mUs(m22, m24, 0.04);
    vec3 q26 = p - vec3(0.0, 0.8, 0.25);
    M m27 = M(sdEllipsoid(q26, vec3(0.14, 0.1, 0.12)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m28 = mUs(m25, m27, 0.04);
    vec3 q29 = p;
    q29.x = abs(q29.x);
    vec3 q30 = q29 - vec3(0.08, 0.78, 0.27);
    M m31 = M(sdEllipsoid(q30, vec3(0.075, 0.07, 0.07)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m32 = mUs(m28, m31, 0.04);
    M u33 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m34 = M(sdRoundCone(p, vec3(0.11, 0.5, 0.13), vec3(0.11, 0.442593, 0.140741), 0.08, 0.077), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u33 = mU(u33, m34);
    }
    {
      M m35 = M(sdRoundCone(p, vec3(0.11, 0.442593, 0.140741), vec3(0.11, 0.360741, 0.155926), 0.077, 0.074), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u33 = mU(u33, m35);
    }
    {
      M m36 = M(sdRoundCone(p, vec3(0.11, 0.360741, 0.155926), vec3(0.11, 0.28, 0.17), 0.074, 0.071), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u33 = mU(u33, m36);
    }
    {
      M m37 = M(sdRoundCone(p, vec3(0.11, 0.28, 0.17), vec3(0.11, 0.201481, 0.181852), 0.071, 0.068), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u33 = mU(u33, m37);
    }
    {
      M m38 = M(sdRoundCone(p, vec3(0.11, 0.201481, 0.181852), vec3(0.11, 0.124074, 0.192593), 0.068, 0.065), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u33 = mU(u33, m38);
    }
    {
      M m39 = M(sdRoundCone(p, vec3(0.11, 0.124074, 0.192593), vec3(0.11, 0.07, 0.2), 0.065, 0.062), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u33 = mU(u33, m39);
    }
    M m40 = mUs(m32, u33, 0.04);
    M u41 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m42 = M(sdRoundCone(p, vec3(-0.11, 0.5, 0.13), vec3(-0.11, 0.442593, 0.140741), 0.08, 0.077), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u41 = mU(u41, m42);
    }
    {
      M m43 = M(sdRoundCone(p, vec3(-0.11, 0.442593, 0.140741), vec3(-0.11, 0.360741, 0.155926), 0.077, 0.074), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u41 = mU(u41, m43);
    }
    {
      M m44 = M(sdRoundCone(p, vec3(-0.11, 0.360741, 0.155926), vec3(-0.11, 0.28, 0.17), 0.074, 0.071), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u41 = mU(u41, m44);
    }
    {
      M m45 = M(sdRoundCone(p, vec3(-0.11, 0.28, 0.17), vec3(-0.11, 0.201481, 0.181852), 0.071, 0.068), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u41 = mU(u41, m45);
    }
    {
      M m46 = M(sdRoundCone(p, vec3(-0.11, 0.201481, 0.181852), vec3(-0.11, 0.124074, 0.192593), 0.068, 0.065), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u41 = mU(u41, m46);
    }
    {
      M m47 = M(sdRoundCone(p, vec3(-0.11, 0.124074, 0.192593), vec3(-0.11, 0.07, 0.2), 0.065, 0.062), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u41 = mU(u41, m47);
    }
    M m48 = mUs(m40, u41, 0.04);
    vec3 q49 = p;
    q49.x = abs(q49.x);
    vec3 q50 = q49 - vec3(0.11, 0.045, 0.24);
    M m51 = M(sdEllipsoid(q50, vec3(0.075, 0.048, 0.095)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m52 = mUs(m48, m51, 0.04);
    vec3 q53 = p;
    q53.x = abs(q53.x);
    vec3 q54 = q53 - vec3(0.2, 0.2, -0.04);
    vec3 q55 = q54 * mat3(1.0, 0.0, 0.0, 0.0, 0.978148, -0.207912, 0.0, 0.207912, 0.978148);
    M m56 = M(sdEllipsoid(q55, vec3(0.13, 0.17, 0.2)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m57 = mUs(m52, m56, 0.04);
    vec3 q58 = p;
    q58.x = abs(q58.x);
    vec3 q59 = q58 - vec3(0.24, 0.04, 0.1);
    M m60 = M(sdEllipsoid(q59, vec3(0.07, 0.042, 0.095)), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m61 = mUs(m57, m60, 0.04);
    M u62 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m63 = M(sdRoundCone(p, vec3(0.0, 0.18, -0.36), vec3(0.0225, 0.192969, -0.375781), 0.055, 0.051875), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m63);
    }
    {
      M m64 = M(sdRoundCone(p, vec3(0.0225, 0.192969, -0.375781), vec3(0.055, 0.21125, -0.39875), 0.051875, 0.04875), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m64);
    }
    {
      M m65 = M(sdRoundCone(p, vec3(0.055, 0.21125, -0.39875), vec3(0.09, 0.233906, -0.422344), 0.04875, 0.045625), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m65);
    }
    {
      M m66 = M(sdRoundCone(p, vec3(0.09, 0.233906, -0.422344), vec3(0.12, 0.26, -0.44), 0.045625, 0.0425), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m66);
    }
    {
      M m67 = M(sdRoundCone(p, vec3(0.12, 0.26, -0.44), vec3(0.144687, 0.294063, -0.449688), 0.0425, 0.039375), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m67);
    }
    {
      M m68 = M(sdRoundCone(p, vec3(0.144687, 0.294063, -0.449688), vec3(0.1675, 0.335, -0.455), 0.039375, 0.03625), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m68);
    }
    {
      M m69 = M(sdRoundCone(p, vec3(0.1675, 0.335, -0.455), vec3(0.186563, 0.373437, -0.457812), 0.03625, 0.033125), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m69);
    }
    {
      M m70 = M(sdRoundCone(p, vec3(0.186563, 0.373437, -0.457812), vec3(0.2, 0.4, -0.46), 0.033125, 0.03), vec3(0.584078, 0.254152, 0.059511), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      u62 = mU(u62, m70);
    }
    M m71 = mUs(m61, u62, 0.04);
    vec3 q72 = p - vec3(0.0, 0.74, 0.33);
    vec3 q73 = q72 * mat3(1.0, 0.0, 0.0, 0.0, 0.984808, -0.173648, 0.0, 0.173648, 0.984808);
    M m74 = M(sdEllipsoid(q73, vec3(0.09, 0.04, 0.07)), vec3(0.6, 0.6, 0.62), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
    M m75 = mSs(m71, m74, 0.015);
    if (m75.d < 0.08) {
      vec3 q77 = p - vec3(0.0, 0.77, 0.27);
      M m78 = M(sdEllipsoid(q77, vec3(0.16, 0.11, 0.13)), vec3(0.930111, 0.760525, 0.496933), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      float w76 = 1.0 - smoothstep(-0.02, 0.02001, m78.d);
      m75.c = mix(m75.c, m78.c, w76); m75.m = mix(m75.m, m78.m, w76);
      if (w76 > 0.5) { m75.c2 = m78.c2; m75.tx = m78.tx; m75.tp = m78.tp; m75.fc = m78.fc; }
    }
    if (m75.d < 0.08) {
      vec3 q80 = p - vec3(0.0, 0.5, 0.2);
      vec3 q81 = q80 * mat3(1.0, 0.0, 0.0, 0.0, 0.970296, -0.241922, 0.0, 0.241922, 0.970296);
      M m82 = M(sdEllipsoid(q81, vec3(0.15, 0.3, 0.12)), vec3(0.930111, 0.760525, 0.496933), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      float w79 = 1.0 - smoothstep(-0.02, 0.02001, m82.d);
      m75.c = mix(m75.c, m82.c, w79); m75.m = mix(m75.m, m82.m, w79);
      if (w79 > 0.5) { m75.c2 = m82.c2; m75.tx = m82.tx; m75.tp = m82.tp; m75.fc = m82.fc; }
    }
    if (m75.d < 0.08) {
      vec3 q84 = p - vec3(0.0, 0.03, 0.1);
      M m85 = M(sdBox(q84, vec3(0.4, 0.06, 0.4)), vec3(0.930111, 0.760525, 0.496933), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      float w83 = 1.0 - smoothstep(-0.02, 0.02001, m85.d);
      m75.c = mix(m75.c, m85.c, w83); m75.m = mix(m75.m, m85.m, w83);
      if (w83 > 0.5) { m75.c2 = m85.c2; m75.tx = m85.tx; m75.tp = m85.tp; m75.fc = m85.fc; }
    }
    if (m75.d < 0.08) {
      vec3 q87 = p - vec3(0.2, 0.42, -0.46);
      M m88 = M(length(q87) - 0.06, vec3(0.930111, 0.760525, 0.496933), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      float w86 = 1.0 - smoothstep(-0.02, 0.02001, m88.d);
      m75.c = mix(m75.c, m88.c, w86); m75.m = mix(m75.m, m88.m, w86);
      if (w86 > 0.5) { m75.c2 = m88.c2; m75.tx = m88.tx; m75.tp = m88.tp; m75.fc = m88.fc; }
    }
    if (m75.d < 0.07) {
      vec3 q90 = p;
      q90.x = abs(q90.x);
      vec3 q91 = q90 - vec3(0.09, 1.015, 0.27);
      vec3 q92 = q91 * mat3(0.978148, 0.207912, 0.0, -0.207912, 0.978148, 0.0, 0.0, 0.0, 1.0);
      M m93 = M(sdEllipsoid(q92, vec3(0.05, 0.02, 0.04)), vec3(0.391572, 0.144128, 0.031896), vec3(0.8, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 288.1);
      float w89 = 1.0 - smoothstep(-0.01, 0.01001, m93.d);
      m75.c = mix(m75.c, m93.c, w89); m75.m = mix(m75.m, m93.m, w89);
      if (w89 > 0.5) { m75.c2 = m93.c2; m75.tx = m93.tx; m75.tp = m93.tp; m75.fc = m93.fc; }
    }
    u0 = mU(u0, m75);
  }
  if (sdBox(p - vec3(0.1, 0.93, 0.27), vec3(0.066, 0.066, 0.066)) < u0.d) {
    vec3 q94 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.1, 0.93, 0.27));
    M m95 = M(length(q94) - 0.056, vec3(0.155926, 0.043735, 0.011612), vec3(0.12, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    if (m95.d < 0.064) {
      vec3 q97 = q94 - vec3(0.0, 0.0, 0.04);
      M m98 = M(length(q97) - 0.027, vec3(0.006049, 0.002428, 0.001821), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w96 = 1.0 - smoothstep(-0.004, 0.00401, m98.d);
      m95.c = mix(m95.c, m98.c, w96); m95.m = mix(m95.m, m98.m, w96);
      if (w96 > 0.5) { m95.c2 = m98.c2; m95.tx = m98.tx; m95.tp = m98.tp; m95.fc = m98.fc; }
    }
    if (m95.d < 0.062) {
      vec3 q100 = q94 - vec3(0.015, 0.02, 0.048);
      M m101 = M(length(q100) - 0.014, vec3(0.887923, 0.887923, 0.887923), vec3(0.6, 0.0, 0.6), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w99 = 1.0 - smoothstep(-0.002, 0.00201, m101.d);
      m95.c = mix(m95.c, m101.c, w99); m95.m = mix(m95.m, m101.m, w99);
      if (w99 > 0.5) { m95.c2 = m101.c2; m95.tx = m101.tx; m95.tp = m101.tp; m95.fc = m101.fc; }
    }
    u0 = mU(u0, m95);
  }
  if (sdBox(p - vec3(-0.1, 0.93, 0.27), vec3(0.066, 0.066, 0.066)) < u0.d) {
    vec3 q102 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.1, 0.93, 0.27));
    M m103 = M(length(q102) - 0.056, vec3(0.155926, 0.043735, 0.011612), vec3(0.12, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    if (m103.d < 0.064) {
      vec3 q105 = q102 - vec3(0.0, 0.0, 0.04);
      M m106 = M(length(q105) - 0.027, vec3(0.006049, 0.002428, 0.001821), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w104 = 1.0 - smoothstep(-0.004, 0.00401, m106.d);
      m103.c = mix(m103.c, m106.c, w104); m103.m = mix(m103.m, m106.m, w104);
      if (w104 > 0.5) { m103.c2 = m106.c2; m103.tx = m106.tx; m103.tp = m106.tp; m103.fc = m106.fc; }
    }
    if (m103.d < 0.062) {
      vec3 q108 = q102 - vec3(0.015, 0.02, 0.048);
      M m109 = M(length(q108) - 0.014, vec3(0.887923, 0.887923, 0.887923), vec3(0.6, 0.0, 0.6), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w107 = 1.0 - smoothstep(-0.002, 0.00201, m109.d);
      m103.c = mix(m103.c, m109.c, w107); m103.m = mix(m103.m, m109.m, w107);
      if (w107 > 0.5) { m103.c2 = m109.c2; m103.tx = m109.tx; m103.tp = m109.tp; m103.fc = m109.fc; }
    }
    u0 = mU(u0, m103);
  }
  int mk110 = 0;
  if (sdBox(p - vec3(0.25, 0.8575, 0.12), vec3(0.177335, 0.291405, 0.182436)) < u0.d) mk110 |= 1;
  if (sdBox(p - vec3(-0.25, 0.8575, 0.12), vec3(0.177335, 0.291405, 0.182436)) < u0.d) mk110 |= 2;
  for (int b = uZero, bits = mk110; bits != 0; b++, bits = int(uint(bits) >> 1u)) {
    if ((bits & 1) == 0) continue;
    int i = 0 + b;
    vec4 bc = codeFetch(3, i);
    if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= u0.d) continue;
    vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);
    M ri = ci0(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));
    ri.d *= bc.w;
    u0 = mU(u0, ri);
  }
  return u0;
}
