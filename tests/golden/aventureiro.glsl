
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

float sdHull11(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.066519, -0.997785)) - 0.129712);
  d = max(d, dot(p, vec3(-0.986394, -0.164399, 0.0)) - 0.197279);
  d = max(d, dot(p, vec3(0.986394, -0.164399, 0.0)) - 0.197279);
  d = max(d, dot(p, vec3(0.0, -0.066519, 0.997785)) - 0.129712);
  d = max(d, dot(p, vec3(0.0, 0.5547, -0.83205)) - 0.291218);
  d = max(d, dot(p, vec3(-0.650791, 0.759257, 0.0)) - 0.390475);
  d = max(d, dot(p, vec3(0.650791, 0.759257, 0.0)) - 0.390475);
  d = max(d, dot(p, vec3(0.0, 0.5547, 0.83205)) - 0.291218);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.36);
  return d;
}
float sdHull14(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.03;
  d = max(d, dot(p, vec3(0.92388, 0.0, 0.382683)) - 0.092388);
  d = max(d, dot(p, vec3(0.92388, 0.0, -0.382683)) - 0.092388);
  d = max(d, dot(p, vec3(0.382683, 0.0, 0.92388)) - 0.092388);
  d = max(d, dot(p, vec3(-0.382683, 0.0, 0.92388)) - 0.092388);
  d = max(d, dot(p, vec3(-0.92388, 0.0, 0.382683)) - 0.092388);
  d = max(d, dot(p, vec3(-0.92388, 0.0, -0.382683)) - 0.092388);
  d = max(d, dot(p, vec3(-0.382683, 0.0, -0.92388)) - 0.092388);
  d = max(d, dot(p, vec3(0.382683, 0.0, -0.92388)) - 0.092388);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.03);
  return d;
}
float sdHull19(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.307692, 0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(-0.307692, 0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(0.307692, -0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(-0.307692, -0.230769, 0.923077)) - 0.018462);
  return d;
}
float sdHull26(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.913118, 0.152186, 0.378226)) - 0.200886);
  d = max(d, dot(p, vec3(0.913118, 0.152186, -0.378226)) - 0.200886);
  d = max(d, dot(p, vec3(0.378226, 0.152186, 0.913118)) - 0.200886);
  d = max(d, dot(p, vec3(-0.378226, 0.152186, 0.913118)) - 0.200886);
  d = max(d, dot(p, vec3(-0.913118, 0.152186, 0.378226)) - 0.200886);
  d = max(d, dot(p, vec3(-0.913118, 0.152186, -0.378226)) - 0.200886);
  d = max(d, dot(p, vec3(-0.378226, 0.152186, -0.913118)) - 0.200886);
  d = max(d, dot(p, vec3(0.378226, 0.152186, -0.913118)) - 0.200886);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull30(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.091526;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.091526);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.091526);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.091526);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.091526);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.091526);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.091526);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.091526);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.088289);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.088289);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.088289);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.088289);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.088289);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.088289);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.088289);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.088289);
  return d;
}
float sdHull39(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.091526;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.091526);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.091526);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.091526);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.091526);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.091526);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.091526);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.091526);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.091526);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.088289);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.088289);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.088289);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.088289);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.088289);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.088289);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.088289);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.088289);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.088289);
  return d;
}
float sdHull49(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.090536, -0.995893)) - 0.199179);
  d = max(d, dot(p, vec3(-0.995893, 0.090536, 0.0)) - 0.219097);
  d = max(d, dot(p, vec3(0.995893, 0.090536, 0.0)) - 0.219097);
  d = max(d, dot(p, vec3(0.0, 0.090536, 0.995893)) - 0.199179);
  d = max(d, dot(p, vec3(0.0, 0.624695, -0.780869)) - 0.277989);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.296985);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.296985);
  d = max(d, dot(p, vec3(0.0, 0.624695, 0.780869)) - 0.277989);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.32);
  return d;
}
float sdHull54(vec3 p) {
  float d = dot(p, vec3(0.894427, -0.447214, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(-0.894427, -0.447214, 0.0)) - 0.0);
  d = max(d, dot(p, vec3(0.97824, 0.115087, -0.172631)) - 0.024168);
  d = max(d, dot(p, vec3(-0.97824, 0.115087, -0.172631)) - 0.024168);
  d = max(d, dot(p, vec3(0.857143, 0.428571, 0.285714)) - 0.034286);
  d = max(d, dot(p, vec3(-0.857143, 0.428571, 0.285714)) - 0.034286);
  return d;
}
float sdHull63(vec3 p) {
  float d = dot(p, vec3(0.28206, -0.493606, 0.822676)) - 0.0;
  d = max(d, dot(p, vec3(0.28206, -0.493606, -0.822676)) - 0.0);
  d = max(d, dot(p, vec3(-0.28206, -0.493606, 0.822676)) - 0.0);
  d = max(d, dot(p, vec3(-0.28206, -0.493606, -0.822676)) - 0.0);
  d = max(d, dot(p, vec3(0.324322, 0.003378, 0.945941)) - 0.011419);
  d = max(d, dot(p, vec3(0.324322, 0.003378, -0.945941)) - 0.011419);
  d = max(d, dot(p, vec3(-0.324322, 0.003378, 0.945941)) - 0.011419);
  d = max(d, dot(p, vec3(-0.324322, 0.003378, -0.945941)) - 0.011419);
  d = max(d, dot(p, vec3(0.316225, 0.003953, 0.948676)) - 0.011463);
  d = max(d, dot(p, vec3(-0.316225, 0.003953, 0.948676)) - 0.011463);
  d = max(d, dot(p, vec3(0.316225, 0.003953, -0.948676)) - 0.011463);
  d = max(d, dot(p, vec3(-0.316225, 0.003953, -0.948676)) - 0.011463);
  d = max(d, dot(p, vec3(0.314027, 0.11776, 0.942082)) - 0.068301);
  d = max(d, dot(p, vec3(0.314027, 0.11776, -0.942082)) - 0.068301);
  d = max(d, dot(p, vec3(-0.314027, 0.11776, 0.942082)) - 0.068301);
  d = max(d, dot(p, vec3(-0.314027, 0.11776, -0.942082)) - 0.068301);
  return d;
}
float sdHull67(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.866025, 0.0, 0.5)) - 0.015588);
  d = max(d, dot(p, vec3(0.866025, 0.0, -0.5)) - 0.015588);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.015588);
  d = max(d, dot(p, vec3(-0.866025, 0.0, 0.5)) - 0.015588);
  d = max(d, dot(p, vec3(-0.866025, 0.0, -0.5)) - 0.015588);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.015588);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull70(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.023297;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.023297);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.023297);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.023297);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.023297);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.023297);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.023297);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.023297);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.023297);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.023297);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.023297);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.023297);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.022474);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.022474);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.022474);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.022474);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.022474);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.022474);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.022474);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.022474);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.022474);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.022474);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.022474);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.022474);
  return d;
}
float sdHull77(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.02;
  d = max(d, dot(p, vec3(0.92388, 0.0, 0.382683)) - 0.184776);
  d = max(d, dot(p, vec3(0.92388, 0.0, -0.382683)) - 0.184776);
  d = max(d, dot(p, vec3(0.382683, 0.0, 0.92388)) - 0.184776);
  d = max(d, dot(p, vec3(-0.382683, 0.0, 0.92388)) - 0.184776);
  d = max(d, dot(p, vec3(-0.92388, 0.0, 0.382683)) - 0.184776);
  d = max(d, dot(p, vec3(-0.92388, 0.0, -0.382683)) - 0.184776);
  d = max(d, dot(p, vec3(-0.382683, 0.0, -0.92388)) - 0.184776);
  d = max(d, dot(p, vec3(0.382683, 0.0, -0.92388)) - 0.184776);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.02);
  return d;
}
float sdHull81(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.015;
  d = max(d, dot(p, vec3(0.92388, 0.0, 0.382683)) - 0.198634);
  d = max(d, dot(p, vec3(0.92388, 0.0, -0.382683)) - 0.198634);
  d = max(d, dot(p, vec3(0.382683, 0.0, 0.92388)) - 0.198634);
  d = max(d, dot(p, vec3(-0.382683, 0.0, 0.92388)) - 0.198634);
  d = max(d, dot(p, vec3(-0.92388, 0.0, 0.382683)) - 0.198634);
  d = max(d, dot(p, vec3(-0.92388, 0.0, -0.382683)) - 0.198634);
  d = max(d, dot(p, vec3(-0.382683, 0.0, -0.92388)) - 0.198634);
  d = max(d, dot(p, vec3(0.382683, 0.0, -0.92388)) - 0.198634);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.015);
  return d;
}
float sdHull84(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.049923;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.049923);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.049923);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.049923);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.049923);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.049923);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.049923);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.049923);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.049923);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.049923);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.049923);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.049923);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.048158);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.048158);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.048158);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.048158);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.048158);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.048158);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.048158);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.048158);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.048158);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.048158);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.048158);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.048158);
  return d;
}
float sdHull87(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.03;
  d = max(d, dot(p, vec3(0.951057, 0.0, 0.309017)) - 0.427975);
  d = max(d, dot(p, vec3(0.951057, 0.0, -0.309017)) - 0.427975);
  d = max(d, dot(p, vec3(0.587785, 0.0, 0.809017)) - 0.427975);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.427975);
  d = max(d, dot(p, vec3(-0.587785, 0.0, 0.809017)) - 0.427975);
  d = max(d, dot(p, vec3(-0.951057, 0.0, 0.309017)) - 0.427975);
  d = max(d, dot(p, vec3(-0.951057, 0.0, -0.309017)) - 0.427975);
  d = max(d, dot(p, vec3(-0.587785, 0.0, -0.809017)) - 0.427975);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.427975);
  d = max(d, dot(p, vec3(0.587785, 0.0, -0.809017)) - 0.427975);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.03);
  return d;
}

M mapAll(vec3 p, bool wantMat) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  if (sdBox(p - vec3(-0.032466, 0.665, 0.009738), vec3(0.437729, 0.675, 0.249738)) < u0.d) {
    M u1 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q2 = p - vec3(0.09, 0.24, 0.0);
      M m3 = M(sdCBox(q2, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m3);
    }
    {
      vec3 q4 = p - vec3(0.09, 0.065, 0.02);
      M m5 = M(sdCBox(q4, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m5);
    }
    {
      vec3 q6 = p - vec3(-0.09, 0.24, 0.0);
      M m7 = M(sdCBox(q6, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m7);
    }
    {
      vec3 q8 = p - vec3(-0.09, 0.065, 0.02);
      M m9 = M(sdCBox(q8, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m9);
    }
    {
      vec3 q10 = p - vec3(0.0, 0.4, 0.0);
      M m12 = M(sdHull11(q10), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m12);
    }
    {
      vec3 q13 = p - vec3(0.0, 0.78, 0.0);
      M m15 = M(sdHull14(q13), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m15);
    }
    {
      vec3 q16 = p - vec3(0.0, 0.58, 0.15);
      M m17 = M(sdCBox(q16, vec3(0.15, 0.14, 0.01), 0.01), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m17);
    }
    {
      vec3 q18 = p - vec3(0.0, 0.6, 0.165);
      M m20 = M(sdHull19(q18), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m20);
    }
    {
      vec3 q21 = p - vec3(0.0, 0.39, 0.0);
      M m22 = M(sdCBox(q21, vec3(0.21, 0.03, 0.14), 0.015), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m22);
    }
    {
      vec3 q23 = p - vec3(0.0, 0.39, 0.145);
      M m24 = M(sdCBox(q23, vec3(0.035, 0.03, 0.01), 0.01), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m24);
    }
    {
      vec3 q25 = p - vec3(0.0, 0.32, 0.0);
      M m27 = M(sdHull26(q25), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m27);
    }
    {
      vec3 q28 = p - vec3(0.3, 0.72, 0.0);
      vec3 q29 = q28 / vec3(1.0, 0.75, 1.0);
      M m31 = M(sdHull30(q29), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m32 = m31; m32.d = m31.d * 0.75;
      u1 = mU(u1, m32);
    }
    {
      vec3 q33 = p - vec3(0.3, 0.55, 0.0);
      M m34 = M(sdCBox(q33, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m34);
    }
    {
      vec3 q35 = p - vec3(0.3, 0.385, 0.0);
      M m36 = M(sdCBox(q35, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m36);
    }
    {
      vec3 q37 = p - vec3(-0.3, 0.72, 0.0);
      vec3 q38 = q37 / vec3(1.0, 0.75, 1.0);
      M m40 = M(sdHull39(q38), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m41 = m40; m41.d = m40.d * 0.75;
      u1 = mU(u1, m41);
    }
    {
      vec3 q42 = p - vec3(-0.3, 0.55, 0.0);
      M m43 = M(sdCBox(q42, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m43);
    }
    {
      vec3 q44 = p - vec3(-0.3, 0.385, 0.0);
      M m45 = M(sdCBox(q44, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m45);
    }
    {
      vec3 q46 = p - vec3(0.0, 0.95, 0.0);
      M m47 = M(sdCBox(q46, vec3(0.19, 0.17, 0.17), 0.07), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m47);
    }
    {
      vec3 q48 = p - vec3(0.0, 0.9, 0.0);
      M m50 = M(sdHull49(q48), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m50);
    }
    {
      vec3 q51 = p - vec3(0.0, 0.98, 0.205);
      M m52 = M(sdBox(q51, vec3(0.15, 0.025, 0.015)), vec3(0.014444, 0.017642, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m52);
    }
    {
      vec3 q53 = p - vec3(0.0, 1.21, 0.0);
      M m55 = M(sdHull54(q53), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m55);
    }
    {
      vec3 q56 = p;
      q56.x = abs(q56.x);
      vec3 q57 = q56 - vec3(0.07, 0.86, 0.172);
      M m58 = M(sdBox(q57, vec3(0.02, 0.025, 0.01)), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u1 = mU(u1, m58);
    }
    if (sdBox(p - vec3(0.3, 0.546405, 0.064245), vec3(0.1, 0.365295, 0.154092)) < u1.d) {
      vec3 q59 = p - vec3(0.3, 0.5485, 0.07);
      vec3 q60 = q59 * mat3(1.0, 0.0, 0.0, 0.0, 0.939693, 0.34202, 0.0, -0.34202, 0.939693);
      vec3 q61 = q60 - vec3(0.0, -0.2085, 0.0);
      M u62 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m64 = M(sdHull63(q61), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u62 = mU(u62, m64);
      }
      {
        M m65 = M(sdCBox(q61, vec3(0.09, 0.0175, 0.025), 0.012), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u62 = mU(u62, m65);
      }
      {
        vec3 q66 = q61 - vec3(0.0, -0.06, 0.0);
        M m68 = M(sdHull67(q66), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u62 = mU(u62, m68);
      }
      {
        vec3 q69 = q61 - vec3(0.0, -0.135, 0.0);
        M m71 = M(sdHull70(q69), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u62 = mU(u62, m71);
      }
      u1 = mU(u1, u62);
    }
    if (sdBox(p - vec3(-0.390257, 0.45, 0.035138), vec3(0.079938, 0.225, 0.224338)) < u1.d) {
      vec3 q72 = p - vec3(-0.4, 0.45, 0.04);
      vec3 q73 = q72 * mat3(0.173648, 0.0, 0.984808, 0.0, 1.0, 0.0, -0.984808, 0.0, 0.173648);
      vec3 q74 = q73 - vec3(0.0, 0.0, -0.02);
      M u75 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q76 = q74 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
        M m78 = M(sdHull77(q76), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u75 = mU(u75, m78);
      }
      {
        vec3 q79 = q74 - vec3(0.0, 0.0, -0.008);
        vec3 q80 = q79 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
        M m82 = M(sdHull81(q80), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u75 = mU(u75, m82);
      }
      {
        vec3 q83 = q74 - vec3(0.0, 0.0, 0.02);
        M m85 = M(sdHull84(q83), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u75 = mU(u75, m85);
      }
      u1 = mU(u1, u75);
    }
    u0 = mU(u0, u1);
  }
  {
    vec3 q86 = p - vec3(0.0, -0.03, 0.0);
    M m88 = M(sdHull87(q86), vec3(0.158961, 0.254152, 0.068478), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m88);
  }
  return u0;
}
