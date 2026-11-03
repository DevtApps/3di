
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

float sdHull21(vec3 p) {
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
float sdHull30(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.307692, 0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(-0.307692, 0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(0.307692, -0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(-0.307692, -0.230769, 0.923077)) - 0.018462);
  return d;
}
float sdHull33(vec3 p) {
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
float sdHull37(vec3 p) {
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
float sdHull46(vec3 p) {
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
float sdHull59(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.073331, -0.997308)) - 0.199462);
  d = max(d, dot(p, vec3(-0.996745, 0.080619, 0.0)) - 0.219284);
  d = max(d, dot(p, vec3(0.996745, 0.080619, 0.0)) - 0.219284);
  d = max(d, dot(p, vec3(0.0, 0.073331, 0.997308)) - 0.199462);
  d = max(d, dot(p, vec3(0.0, 0.615644, -0.788024)) - 0.278961);
  d = max(d, dot(p, vec3(-0.726698, 0.686957, 0.0)) - 0.296566);
  d = max(d, dot(p, vec3(0.726698, 0.686957, 0.0)) - 0.296566);
  d = max(d, dot(p, vec3(0.0, 0.615644, 0.788024)) - 0.278961);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.32);
  return d;
}
float sdHull64(vec3 p) {
  float d = dot(p, vec3(0.894427, -0.447214, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(-0.894427, -0.447214, 0.0)) - 0.0);
  d = max(d, dot(p, vec3(0.97824, 0.115087, -0.172631)) - 0.024168);
  d = max(d, dot(p, vec3(-0.97824, 0.115087, -0.172631)) - 0.024168);
  d = max(d, dot(p, vec3(0.857143, 0.428571, 0.285714)) - 0.034286);
  d = max(d, dot(p, vec3(-0.857143, 0.428571, 0.285714)) - 0.034286);
  return d;
}
float sdHull70(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.324322, 0.003405, 0.94594)) - 0.011351);
  d = max(d, dot(p, vec3(0.324322, 0.003405, -0.94594)) - 0.011351);
  d = max(d, dot(p, vec3(-0.324322, 0.003405, 0.94594)) - 0.011351);
  d = max(d, dot(p, vec3(-0.324322, 0.003405, -0.94594)) - 0.011351);
  d = max(d, dot(p, vec3(0.307093, 0.004568, 0.951669)) - 0.01142);
  d = max(d, dot(p, vec3(-0.307093, 0.004568, 0.951669)) - 0.01142);
  d = max(d, dot(p, vec3(0.307093, 0.004568, -0.951669)) - 0.01142);
  d = max(d, dot(p, vec3(-0.307093, 0.004568, -0.951669)) - 0.01142);
  d = max(d, dot(p, vec3(0.305113, 0.113464, 0.945533)) - 0.065809);
  d = max(d, dot(p, vec3(0.305113, 0.113464, -0.945533)) - 0.065809);
  d = max(d, dot(p, vec3(-0.305113, 0.113464, 0.945533)) - 0.065809);
  d = max(d, dot(p, vec3(-0.305113, 0.113464, -0.945533)) - 0.065809);
  return d;
}
float sdHull74(vec3 p) {
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
float sdHull77(vec3 p) {
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
float sdHull83(vec3 p) {
  float d = dot(p, vec3(0.0, 1.0, 0.0)) - 0.22;
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.0);
  d = max(d, dot(p, vec3(-0.997785, -0.066519, 0.0)) - 0.184923);
  d = max(d, dot(p, vec3(0.997785, -0.066519, 0.0)) - 0.184923);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.04);
  d = max(d, dot(p, vec3(-0.773957, -0.633238, 0.0)) - 0.189971);
  d = max(d, dot(p, vec3(0.773957, -0.633238, 0.0)) - 0.189971);
  return d;
}
float sdHull86(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.379747, 0.265823, 0.886076)) - 0.026582);
  d = max(d, dot(p, vec3(-0.379747, 0.265823, 0.886076)) - 0.026582);
  d = max(d, dot(p, vec3(0.379747, -0.265823, 0.886076)) - 0.026582);
  d = max(d, dot(p, vec3(-0.379747, -0.265823, 0.886076)) - 0.026582);
  return d;
}
float sdHull108(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.066519, -0.997785)) - 0.129712);
  d = max(d, dot(p, vec3(-0.981205, -0.19297, 0.0)) - 0.231564);
  d = max(d, dot(p, vec3(0.981205, -0.19297, 0.0)) - 0.231564);
  d = max(d, dot(p, vec3(0.0, -0.066519, 0.997785)) - 0.129712);
  d = max(d, dot(p, vec3(0.0, 0.5547, -0.83205)) - 0.291218);
  d = max(d, dot(p, vec3(-0.587706, 0.809075, 0.0)) - 0.416096);
  d = max(d, dot(p, vec3(0.587706, 0.809075, 0.0)) - 0.416096);
  d = max(d, dot(p, vec3(0.0, 0.5547, 0.83205)) - 0.291218);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.36);
  return d;
}
float sdHull115(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.891367, 0.262953, 0.369216)) - 0.247176);
  d = max(d, dot(p, vec3(0.891367, 0.262953, -0.369216)) - 0.247176);
  d = max(d, dot(p, vec3(0.369216, 0.262953, 0.891367)) - 0.247176);
  d = max(d, dot(p, vec3(-0.369216, 0.262953, 0.891367)) - 0.247176);
  d = max(d, dot(p, vec3(-0.891367, 0.262953, 0.369216)) - 0.247176);
  d = max(d, dot(p, vec3(-0.891367, 0.262953, -0.369216)) - 0.247176);
  d = max(d, dot(p, vec3(-0.369216, 0.262953, -0.891367)) - 0.247176);
  d = max(d, dot(p, vec3(0.369216, 0.262953, -0.891367)) - 0.247176);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull118(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.514496, 0.857493)) - 0.0);
  d = max(d, dot(p, vec3(-0.394055, 0.472866, 0.78811)) - 0.047287);
  d = max(d, dot(p, vec3(0.394055, 0.472866, 0.78811)) - 0.047287);
  return d;
}
float sdHull122(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.108;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.108);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.108);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.108);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.108);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.108);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.108);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.108);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.108);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.108);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.108);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.108);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.104181);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.104181);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.104181);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.104181);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.104181);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.104181);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.104181);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.104181);
  return d;
}
float sdHull131(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.108;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.108);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.108);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.108);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.108);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.108);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.108);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.108);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.108);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.108);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.108);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.108);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.104181);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.104181);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.104181);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.104181);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.104181);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.104181);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.104181);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.104181);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.104181);
  return d;
}
float sdHull144(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.123236, -0.992377)) - 0.188552);
  d = max(d, dot(p, vec3(-0.990712, 0.13598, 0.0)) - 0.208049);
  d = max(d, dot(p, vec3(0.990712, 0.13598, 0.0)) - 0.208049);
  d = max(d, dot(p, vec3(0.0, 0.123236, 0.992377)) - 0.188552);
  d = max(d, dot(p, vec3(0.0, 0.79697, -0.604019)) - 0.203132);
  d = max(d, dot(p, vec3(-0.529008, 0.848617, 0.0)) - 0.206075);
  d = max(d, dot(p, vec3(0.529008, 0.848617, 0.0)) - 0.206075);
  d = max(d, dot(p, vec3(0.0, 0.79697, 0.604019)) - 0.203132);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.18);
  return d;
}
float sdHull148(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.11;
  d = max(d, dot(p, vec3(0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, 0.981175)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, -0.981175)) - 0.021243);
  return d;
}
float sdHull152(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.11;
  d = max(d, dot(p, vec3(0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, 0.981175)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, -0.981175)) - 0.021243);
  return d;
}
float sdHull155(vec3 p) {
  float d = dot(p, vec3(0.0, -0.124035, -0.992278)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.780869, 0.624695)) - 0.0);
  d = max(d, dot(p, vec3(-0.383914, -0.22395, 0.895799)) - 0.053748);
  d = max(d, dot(p, vec3(0.383914, -0.22395, 0.895799)) - 0.053748);
  return d;
}
float sdHull161(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.3;
  d = max(d, dot(p, vec3(0.866025, 0.0, 0.5)) - 0.017321);
  d = max(d, dot(p, vec3(0.866025, 0.0, -0.5)) - 0.017321);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.017321);
  d = max(d, dot(p, vec3(-0.866025, 0.0, 0.5)) - 0.017321);
  d = max(d, dot(p, vec3(-0.866025, 0.0, -0.5)) - 0.017321);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.017321);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.3);
  return d;
}
float sdHull164(vec3 p) {
  float d = dot(p, vec3(-1.0, 0.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.049938, 0.0, 0.998752)) - 0.011985);
  d = max(d, dot(p, vec3(-0.298275, -0.95448, 0.0)) - 0.066814);
  d = max(d, dot(p, vec3(-0.298275, 0.95448, 0.0)) - 0.066814);
  d = max(d, dot(p, vec3(0.049938, 0.0, -0.998752)) - 0.011985);
  d = max(d, dot(p, vec3(0.132164, 0.0, 0.991228)) - 0.025111);
  d = max(d, dot(p, vec3(0.970143, -0.242536, 0.0)) - 0.184327);
  d = max(d, dot(p, vec3(0.970143, 0.242536, 0.0)) - 0.184327);
  d = max(d, dot(p, vec3(0.132164, 0.0, -0.991228)) - 0.025111);
  return d;
}
float sdHull171(vec3 p) {
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
float sdHull175(vec3 p) {
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
float sdHull178(vec3 p) {
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
float sdHull197(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.066519, -0.997785)) - 0.129712);
  d = max(d, dot(p, vec3(-0.987696, -0.156385, 0.0)) - 0.187662);
  d = max(d, dot(p, vec3(0.987696, -0.156385, 0.0)) - 0.187662);
  d = max(d, dot(p, vec3(0.0, -0.066519, 0.997785)) - 0.129712);
  d = max(d, dot(p, vec3(0.0, 0.5547, -0.83205)) - 0.291218);
  d = max(d, dot(p, vec3(-0.669889, 0.742461, 0.0)) - 0.381837);
  d = max(d, dot(p, vec3(0.669889, 0.742461, 0.0)) - 0.381837);
  d = max(d, dot(p, vec3(0.0, 0.5547, 0.83205)) - 0.291218);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.36);
  return d;
}
float sdHull204(vec3 p) {
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
float sdHull208(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.086949;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.086949);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.086949);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.086949);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.086949);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.086949);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.086949);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.086949);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.083875);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.083875);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.083875);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.083875);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.083875);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.083875);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.083875);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.083875);
  return d;
}
float sdHull217(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.086949;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.086949);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.086949);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.086949);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.086949);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.086949);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.086949);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.086949);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.086949);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.083875);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.083875);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.083875);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.083875);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.083875);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.083875);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.083875);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.083875);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.083875);
  return d;
}
float sdHull230(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.316228, -0.948683)) - 0.189737);
  d = max(d, dot(p, vec3(-0.995037, 0.099504, 0.0)) - 0.218908);
  d = max(d, dot(p, vec3(-0.322226, 0.079389, -0.943328)) - 0.259555);
  d = max(d, dot(p, vec3(0.995037, 0.099504, 0.0)) - 0.218908);
  d = max(d, dot(p, vec3(0.322226, 0.079389, -0.943328)) - 0.259555);
  d = max(d, dot(p, vec3(0.0, 0.049938, 0.998752)) - 0.19975);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.282843);
  d = max(d, dot(p, vec3(-0.181083, 0.679061, -0.711397)) - 0.307194);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.282843);
  d = max(d, dot(p, vec3(0.181083, 0.679061, -0.711397)) - 0.307194);
  d = max(d, dot(p, vec3(0.0, 0.573462, 0.819232)) - 0.270347);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.3);
  d = max(d, dot(p, vec3(0.0, 0.759257, -0.650791)) - 0.305872);
  return d;
}
float sdHull240(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.338713, 0.006351, 0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(0.338713, 0.006351, -0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(-0.338713, 0.006351, 0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(-0.338713, 0.006351, -0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(0.320892, 0.008524, 0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(-0.320892, 0.008524, 0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(0.320892, 0.008524, -0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(-0.320892, 0.008524, -0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(0.31796, 0.135133, 0.938424)) - 0.033783);
  d = max(d, dot(p, vec3(0.31796, 0.135133, -0.938424)) - 0.033783);
  d = max(d, dot(p, vec3(-0.31796, 0.135133, 0.938424)) - 0.033783);
  d = max(d, dot(p, vec3(-0.31796, 0.135133, -0.938424)) - 0.033783);
  return d;
}
float sdHull244(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.04;
  d = max(d, dot(p, vec3(0.866025, 0.0, 0.5)) - 0.012124);
  d = max(d, dot(p, vec3(0.866025, 0.0, -0.5)) - 0.012124);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.012124);
  d = max(d, dot(p, vec3(-0.866025, 0.0, 0.5)) - 0.012124);
  d = max(d, dot(p, vec3(-0.866025, 0.0, -0.5)) - 0.012124);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.012124);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.04);
  return d;
}
float sdHull250(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.338713, 0.006351, 0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(0.338713, 0.006351, -0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(-0.338713, 0.006351, 0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(-0.338713, 0.006351, -0.940868)) - 0.008468);
  d = max(d, dot(p, vec3(0.320892, 0.008524, 0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(-0.320892, 0.008524, 0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(0.320892, 0.008524, -0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(-0.320892, 0.008524, -0.947077)) - 0.008524);
  d = max(d, dot(p, vec3(0.31796, 0.135133, 0.938424)) - 0.033783);
  d = max(d, dot(p, vec3(0.31796, 0.135133, -0.938424)) - 0.033783);
  d = max(d, dot(p, vec3(-0.31796, 0.135133, 0.938424)) - 0.033783);
  d = max(d, dot(p, vec3(-0.31796, 0.135133, -0.938424)) - 0.033783);
  return d;
}
float sdHull254(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.04;
  d = max(d, dot(p, vec3(0.866025, 0.0, 0.5)) - 0.012124);
  d = max(d, dot(p, vec3(0.866025, 0.0, -0.5)) - 0.012124);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.012124);
  d = max(d, dot(p, vec3(-0.866025, 0.0, 0.5)) - 0.012124);
  d = max(d, dot(p, vec3(-0.866025, 0.0, -0.5)) - 0.012124);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.012124);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.04);
  return d;
}
float sdHull276(vec3 p) {
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
float sdHull283(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.18;
  d = max(d, dot(p, vec3(0.894881, 0.248578, 0.370672)) - 0.22372);
  d = max(d, dot(p, vec3(0.894881, 0.248578, -0.370672)) - 0.22372);
  d = max(d, dot(p, vec3(0.370672, 0.248578, 0.894881)) - 0.22372);
  d = max(d, dot(p, vec3(-0.370672, 0.248578, 0.894881)) - 0.22372);
  d = max(d, dot(p, vec3(-0.894881, 0.248578, 0.370672)) - 0.22372);
  d = max(d, dot(p, vec3(-0.894881, 0.248578, -0.370672)) - 0.22372);
  d = max(d, dot(p, vec3(-0.370672, 0.248578, -0.894881)) - 0.22372);
  d = max(d, dot(p, vec3(0.370672, 0.248578, -0.894881)) - 0.22372);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.18);
  return d;
}
float sdHull289(vec3 p) {
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
float sdHull298(vec3 p) {
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
float sdHull311(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.015;
  d = max(d, dot(p, vec3(0.951057, 0.0, 0.309017)) - 0.285317);
  d = max(d, dot(p, vec3(0.951057, 0.0, -0.309017)) - 0.285317);
  d = max(d, dot(p, vec3(0.587785, 0.0, 0.809017)) - 0.285317);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.285317);
  d = max(d, dot(p, vec3(-0.587785, 0.0, 0.809017)) - 0.285317);
  d = max(d, dot(p, vec3(-0.951057, 0.0, 0.309017)) - 0.285317);
  d = max(d, dot(p, vec3(-0.951057, 0.0, -0.309017)) - 0.285317);
  d = max(d, dot(p, vec3(-0.587785, 0.0, -0.809017)) - 0.285317);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.285317);
  d = max(d, dot(p, vec3(0.587785, 0.0, -0.809017)) - 0.285317);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.015);
  return d;
}
float sdHull316(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.21;
  d = max(d, dot(p, vec3(0.865353, 0.350262, 0.358441)) - 0.073555);
  d = max(d, dot(p, vec3(0.865353, 0.350262, -0.358441)) - 0.073555);
  d = max(d, dot(p, vec3(0.358441, 0.350262, 0.865353)) - 0.073555);
  d = max(d, dot(p, vec3(-0.358441, 0.350262, 0.865353)) - 0.073555);
  d = max(d, dot(p, vec3(-0.865353, 0.350262, 0.358441)) - 0.073555);
  d = max(d, dot(p, vec3(-0.865353, 0.350262, -0.358441)) - 0.073555);
  d = max(d, dot(p, vec3(-0.358441, 0.350262, -0.865353)) - 0.073555);
  d = max(d, dot(p, vec3(0.358441, 0.350262, -0.865353)) - 0.073555);
  return d;
}
float sdHull319(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.02;
  d = max(d, dot(p, vec3(0.92388, 0.0, 0.382683)) - 0.166298);
  d = max(d, dot(p, vec3(0.92388, 0.0, -0.382683)) - 0.166298);
  d = max(d, dot(p, vec3(0.382683, 0.0, 0.92388)) - 0.166298);
  d = max(d, dot(p, vec3(-0.382683, 0.0, 0.92388)) - 0.166298);
  d = max(d, dot(p, vec3(-0.92388, 0.0, 0.382683)) - 0.166298);
  d = max(d, dot(p, vec3(-0.92388, 0.0, -0.382683)) - 0.166298);
  d = max(d, dot(p, vec3(-0.382683, 0.0, -0.92388)) - 0.166298);
  d = max(d, dot(p, vec3(0.382683, 0.0, -0.92388)) - 0.166298);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.02);
  return d;
}
float sdHull322(vec3 p) {
  float d = dot(p, vec3(0.0, -0.196116, -0.980581)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.928477, 0.371391)) - 0.0);
  d = max(d, dot(p, vec3(-0.36541, -0.051634, 0.929413)) - 0.047503);
  d = max(d, dot(p, vec3(0.36541, -0.051634, 0.929413)) - 0.047503);
  return d;
}
float sdHull328(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.55;
  d = max(d, dot(p, vec3(0.866025, 0.0, 0.5)) - 0.019053);
  d = max(d, dot(p, vec3(0.866025, 0.0, -0.5)) - 0.019053);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.019053);
  d = max(d, dot(p, vec3(-0.866025, 0.0, 0.5)) - 0.019053);
  d = max(d, dot(p, vec3(-0.866025, 0.0, -0.5)) - 0.019053);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.019053);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.55);
  return d;
}
float sdHull332(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.846415, 0.211604, 0.488678)) - 0.029625);
  d = max(d, dot(p, vec3(0.846415, 0.211604, -0.488678)) - 0.029625);
  d = max(d, dot(p, vec3(0.0, 0.211604, 0.977356)) - 0.029625);
  d = max(d, dot(p, vec3(-0.846415, 0.211604, 0.488678)) - 0.029625);
  d = max(d, dot(p, vec3(-0.846415, 0.211604, -0.488678)) - 0.029625);
  d = max(d, dot(p, vec3(0.0, 0.211604, -0.977356)) - 0.029625);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull335(vec3 p) {
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
float sdHull365(vec3 p) {
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
float sdHull372(vec3 p) {
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
float sdHull376(vec3 p) {
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
float sdHull385(vec3 p) {
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
float sdHull398(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.196116, -0.980581)) - 0.18631);
  d = max(d, dot(p, vec3(-0.980581, 0.196116, 0.0)) - 0.205922);
  d = max(d, dot(p, vec3(0.980581, 0.196116, 0.0)) - 0.205922);
  d = max(d, dot(p, vec3(0.0, 0.196116, 0.980581)) - 0.18631);
  d = max(d, dot(p, vec3(0.0, 0.447214, -0.894427)) - 0.196774);
  d = max(d, dot(p, vec3(-0.465746, 0.884918, 0.0)) - 0.176984);
  d = max(d, dot(p, vec3(0.465746, 0.884918, 0.0)) - 0.176984);
  d = max(d, dot(p, vec3(0.0, 0.759257, 0.650791)) - 0.18656);
  d = max(d, dot(p, vec3(-0.23777, 0.955654, 0.173755)) - 0.17028);
  d = max(d, dot(p, vec3(0.23777, 0.955654, 0.173755)) - 0.17028);
  return d;
}
float sdHull402(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.9327, -0.103633, 0.345444)) - 0.0);
  d = max(d, dot(p, vec3(-0.9327, -0.103633, 0.345444)) - 0.0);
  d = max(d, dot(p, vec3(0.0, 0.351123, 0.936329)) - 0.063202);
  return d;
}
float sdHull435(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.17;
  d = max(d, dot(p, vec3(0.865745, -0.025463, 0.499838)) - 0.056273);
  d = max(d, dot(p, vec3(0.865745, -0.025463, -0.499838)) - 0.056273);
  d = max(d, dot(p, vec3(0.0, -0.025463, 0.999676)) - 0.056273);
  d = max(d, dot(p, vec3(-0.865745, -0.025463, 0.499838)) - 0.056273);
  d = max(d, dot(p, vec3(-0.865745, -0.025463, -0.499838)) - 0.056273);
  d = max(d, dot(p, vec3(0.0, -0.025463, -0.999676)) - 0.056273);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.17);
  return d;
}
float sdHull438(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.015;
  d = max(d, dot(p, vec3(0.866025, 0.0, 0.5)) - 0.062354);
  d = max(d, dot(p, vec3(0.866025, 0.0, -0.5)) - 0.062354);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.062354);
  d = max(d, dot(p, vec3(-0.866025, 0.0, 0.5)) - 0.062354);
  d = max(d, dot(p, vec3(-0.866025, 0.0, -0.5)) - 0.062354);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.062354);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.015);
  return d;
}
float sdHull443(vec3 p) {
  float d = dot(p, vec3(0.988936, -0.14834, 0.0)) - -0.024723;
  d = max(d, dot(p, vec3(-0.988936, -0.14834, 0.0)) - -0.064281);
  d = max(d, dot(p, vec3(0.973009, 0.072976, -0.218927)) - 0.043542);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, -0.218927)) - 0.004622);
  d = max(d, dot(p, vec3(0.973009, 0.072976, 0.218927)) - 0.047921);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, 0.218927)) - 0.009);
  return d;
}
float sdHull448(vec3 p) {
  float d = dot(p, vec3(0.988936, -0.14834, 0.0)) - -0.064281;
  d = max(d, dot(p, vec3(-0.988936, -0.14834, 0.0)) - -0.024723);
  d = max(d, dot(p, vec3(0.973009, 0.072976, -0.218927)) - 0.002433);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, -0.218927)) - 0.041353);
  d = max(d, dot(p, vec3(0.973009, 0.072976, 0.218927)) - 0.01119);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, 0.218927)) - 0.05011);
  return d;
}
float sdHull453(vec3 p) {
  float d = dot(p, vec3(0.988936, -0.14834, 0.0)) - -0.044502;
  d = max(d, dot(p, vec3(-0.988936, -0.14834, 0.0)) - -0.044502);
  d = max(d, dot(p, vec3(0.973009, 0.072976, -0.218927)) - 0.03065);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, -0.218927)) - 0.03065);
  d = max(d, dot(p, vec3(0.973009, 0.072976, 0.218927)) - 0.021893);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, 0.218927)) - 0.021893);
  return d;
}
float sdHull457(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.04;
  d = max(d, dot(p, vec3(0.965926, 0.0, 0.258819)) - 3.090963);
  d = max(d, dot(p, vec3(0.965926, 0.0, -0.258819)) - 3.090963);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 3.090963);
  d = max(d, dot(p, vec3(0.258819, 0.0, 0.965926)) - 3.090963);
  d = max(d, dot(p, vec3(-0.258819, 0.0, 0.965926)) - 3.090963);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 3.090963);
  d = max(d, dot(p, vec3(-0.965926, 0.0, 0.258819)) - 3.090963);
  d = max(d, dot(p, vec3(-0.965926, 0.0, -0.258819)) - 3.090963);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 3.090963);
  d = max(d, dot(p, vec3(-0.258819, 0.0, -0.965926)) - 3.090963);
  d = max(d, dot(p, vec3(0.258819, 0.0, -0.965926)) - 3.090963);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 3.090963);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.04);
  return d;
}

M mapAll(vec3 p, bool wantMat) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  if (sdBox(p - vec3(-2.27119, 0.665, -0.04107), vec3(0.467956, 0.675, 0.31828)) < u0.d) {
    vec3 q1 = p - vec3(-2.292369, 0.665, 0.0);
    vec3 q2 = q1 * mat3(0.895712, 0.0, -0.444635, 0.0, 1.0, 0.0, 0.444635, 0.0, 0.895712);
    vec3 q3 = q2 - vec3(0.092369, -0.665, 0.0);
    M u4 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q3 - vec3(0.0, 0.665, 0.0), vec3(0.405263, 0.675, 0.24)) < u4.d) {
      vec3 q5 = q3 - vec3(0.0, 0.0, 0.0);
      vec3 q6 = q5 - vec3(0.0, 0.0, 0.0);
      vec3 q7 = q6 - vec3(0.0, 0.0, 0.0);
      vec3 q8 = q7 - vec3(0.0, 0.0, 0.0);
      vec3 q9 = q8 - vec3(0.0, 0.0, 0.0);
      vec3 q10 = q9 - vec3(0.0, 0.0, 0.0);
      M u11 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q12 = q10 - vec3(0.09, 0.24, 0.0);
        M m13 = M(sdCBox(q12, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m13);
      }
      {
        vec3 q14 = q10 - vec3(0.09, 0.065, 0.02);
        M m15 = M(sdCBox(q14, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m15);
      }
      {
        vec3 q16 = q10 - vec3(-0.09, 0.24, 0.0);
        M m17 = M(sdCBox(q16, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m17);
      }
      {
        vec3 q18 = q10 - vec3(-0.09, 0.065, 0.02);
        M m19 = M(sdCBox(q18, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m19);
      }
      {
        vec3 q20 = q10 - vec3(0.0, 0.4, 0.0);
        M m22 = M(sdHull21(q20), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m22);
      }
      {
        vec3 q23 = q10 - vec3(0.0, 0.39, 0.0);
        M m24 = M(sdCBox(q23, vec3(0.21, 0.03, 0.14), 0.015), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m24);
      }
      {
        vec3 q25 = q10 - vec3(0.0, 0.39, 0.145);
        M m26 = M(sdCBox(q25, vec3(0.035, 0.03, 0.01), 0.01), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m26);
      }
      {
        vec3 q27 = q10 - vec3(0.0, 0.58, 0.15);
        M m28 = M(sdCBox(q27, vec3(0.15, 0.14, 0.01), 0.01), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m28);
      }
      {
        vec3 q29 = q10 - vec3(0.0, 0.6, 0.165);
        M m31 = M(sdHull30(q29), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m31);
      }
      {
        vec3 q32 = q10 - vec3(0.0, 0.32, 0.0);
        M m34 = M(sdHull33(q32), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m34);
      }
      {
        vec3 q35 = q10 - vec3(0.3, 0.72, 0.0);
        vec3 q36 = q35 / vec3(1.0, 0.75, 1.0);
        M m38 = M(sdHull37(q36), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m39 = m38; m39.d = m38.d * 0.75;
        u11 = mU(u11, m39);
      }
      {
        vec3 q40 = q10 - vec3(0.3, 0.55, 0.0);
        M m41 = M(sdCBox(q40, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m41);
      }
      {
        vec3 q42 = q10 - vec3(0.3, 0.385, 0.0);
        M m43 = M(sdCBox(q42, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m43);
      }
      {
        vec3 q44 = q10 - vec3(-0.3, 0.72, 0.0);
        vec3 q45 = q44 / vec3(1.0, 0.75, 1.0);
        M m47 = M(sdHull46(q45), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m48 = m47; m48.d = m47.d * 0.75;
        u11 = mU(u11, m48);
      }
      {
        vec3 q49 = q10 - vec3(-0.3, 0.55, 0.0);
        M m50 = M(sdCBox(q49, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m50);
      }
      {
        vec3 q51 = q10 - vec3(-0.3, 0.385, 0.0);
        M m52 = M(sdCBox(q51, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m52);
      }
      {
        vec3 q53 = q10 - vec3(0.0, 0.95, 0.0);
        M m54 = M(sdCBox(q53, vec3(0.19, 0.17, 0.17), 0.07), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m54);
      }
      {
        vec3 q55 = q10;
        q55.x = abs(q55.x);
        vec3 q56 = q55 - vec3(0.07, 0.86, 0.172);
        M m57 = M(sdBox(q56, vec3(0.02, 0.025, 0.01)), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m57);
      }
      {
        vec3 q58 = q10 - vec3(0.0, 0.9, 0.0);
        M m60 = M(sdHull59(q58), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m60);
      }
      {
        vec3 q61 = q10 - vec3(0.0, 0.98, 0.205);
        M m62 = M(sdBox(q61, vec3(0.15, 0.025, 0.015)), vec3(0.014444, 0.017642, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m62);
      }
      {
        vec3 q63 = q10 - vec3(0.0, 1.21, 0.0);
        M m65 = M(sdHull64(q63), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m65);
      }
      u4 = mU(u4, u11);
    }
    if (sdBox(q3 - vec3(0.3, 0.6085, 0.04), vec3(0.1, 0.3865, 0.035)) < u4.d) {
      vec3 q66 = q3 - vec3(0.3, 0.33, 0.04);
      vec3 q67 = q66 - vec3(0.0, 0.0, 0.0);
      M u68 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q69 = q67 - vec3(0.0, 0.075, 0.0);
        M m71 = M(sdHull70(q69), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u68 = mU(u68, m71);
      }
      {
        vec3 q72 = q67 - vec3(0.0, 0.06, 0.0);
        M m73 = M(sdCBox(q72, vec3(0.09, 0.0175, 0.025), 0.012), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u68 = mU(u68, m73);
      }
      {
        M m75 = M(sdHull74(q67), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u68 = mU(u68, m75);
      }
      {
        vec3 q76 = q67 - vec3(0.0, -0.07, 0.0);
        M m78 = M(sdHull77(q76), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u68 = mU(u68, m78);
      }
      u4 = mU(u4, u68);
    }
    {
      vec3 q79 = q3 - vec3(-0.36, 0.42, 0.0);
      vec3 q80 = q79 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      vec3 q81 = q80 - vec3(0.0, 0.0, 0.0);
      M u82 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m84 = M(sdHull83(q81), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u82 = mU(u82, m84);
      }
      {
        vec3 q85 = q81 - vec3(0.0, 0.0, 0.04);
        M m87 = M(sdHull86(q85), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u82 = mU(u82, m87);
      }
      u4 = mU(u4, u82);
    }
    u0 = mU(u0, u4);
  }
  if (sdBox(p - vec3(-1.139589, 0.592026, -0.009796), vec3(0.599692, 0.602026, 0.364569)) < u0.d) {
    vec3 q88 = p - vec3(-1.1429, 0.592026, 0.0);
    vec3 q89 = q88 * mat3(0.973579, 0.0, -0.228351, 0.0, 1.0, 0.0, 0.228351, 0.0, 0.973579);
    vec3 q90 = q89 - vec3(0.0429, -0.592026, 0.0);
    M u91 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q90 - vec3(0.0, 0.592026, 0.0), vec3(0.47641, 0.602026, 0.305)) < u91.d) {
      vec3 q92 = q90 - vec3(0.0, 0.0, 0.0);
      vec3 q93 = q92 - vec3(0.0, 0.0, 0.0);
      vec3 q94 = q93 - vec3(0.0, 0.0, 0.0);
      vec3 q95 = q94 - vec3(0.0, 0.0, 0.0);
      vec3 q96 = q95 - vec3(0.0, 0.0, 0.0);
      vec3 q97 = q96 - vec3(0.0, 0.0, 0.0);
      M u98 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q99 = q97 - vec3(0.1062, 0.24, 0.0);
        M m100 = M(sdCBox(q99, vec3(0.0885, 0.12, 0.085), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m100);
      }
      {
        vec3 q101 = q97 - vec3(0.1062, 0.065, 0.02);
        M m102 = M(sdCBox(q101, vec3(0.1062, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m102);
      }
      {
        vec3 q103 = q97 - vec3(-0.1062, 0.24, 0.0);
        M m104 = M(sdCBox(q103, vec3(0.0885, 0.12, 0.085), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m104);
      }
      {
        vec3 q105 = q97 - vec3(-0.1062, 0.065, 0.02);
        M m106 = M(sdCBox(q105, vec3(0.1062, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m106);
      }
      {
        vec3 q107 = q97 - vec3(0.0, 0.4, 0.0);
        M m109 = M(sdHull108(q107), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m109);
      }
      {
        vec3 q110 = q97 - vec3(0.0, 0.39, 0.0);
        M m111 = M(sdCBox(q110, vec3(0.2478, 0.03, 0.14), 0.015), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m111);
      }
      {
        vec3 q112 = q97 - vec3(0.0, 0.39, 0.145);
        M m113 = M(sdCBox(q112, vec3(0.035, 0.03, 0.01), 0.01), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m113);
      }
      {
        vec3 q114 = q97 - vec3(0.0, 0.32, 0.0);
        M m116 = M(sdHull115(q114), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m116);
      }
      {
        vec3 q117 = q97 - vec3(0.0, 0.55, 0.14);
        M m119 = M(sdHull118(q117), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m119);
      }
      {
        vec3 q120 = q97 - vec3(0.354, 0.72, 0.0);
        vec3 q121 = q120 / vec3(1.0, 0.75, 1.0);
        M m123 = M(sdHull122(q121), vec3(0.584078, 0.456411, 0.274677), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m124 = m123; m124.d = m123.d * 0.75;
        u98 = mU(u98, m124);
      }
      {
        vec3 q125 = q97 - vec3(0.354, 0.55, 0.0);
        M m126 = M(sdCBox(q125, vec3(0.0649, 0.13, 0.06), 0.025), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m126);
      }
      {
        vec3 q127 = q97 - vec3(0.354, 0.385, 0.0);
        M m128 = M(sdCBox(q127, vec3(0.0767, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m128);
      }
      {
        vec3 q129 = q97 - vec3(-0.354, 0.72, 0.0);
        vec3 q130 = q129 / vec3(1.0, 0.75, 1.0);
        M m132 = M(sdHull131(q130), vec3(0.584078, 0.456411, 0.274677), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m133 = m132; m133.d = m132.d * 0.75;
        u98 = mU(u98, m133);
      }
      {
        vec3 q134 = q97 - vec3(-0.354, 0.55, 0.0);
        M m135 = M(sdCBox(q134, vec3(0.0649, 0.13, 0.06), 0.025), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m135);
      }
      {
        vec3 q136 = q97 - vec3(-0.354, 0.385, 0.0);
        M m137 = M(sdCBox(q136, vec3(0.0767, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m137);
      }
      {
        vec3 q138 = q97 - vec3(0.0, 0.95, 0.0);
        M m139 = M(sdCBox(q138, vec3(0.19, 0.17, 0.17), 0.07), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m139);
      }
      {
        vec3 q140 = q97;
        q140.x = abs(q140.x);
        vec3 q141 = q140 - vec3(0.07, 0.86, 0.172);
        M m142 = M(sdBox(q141, vec3(0.02, 0.025, 0.01)), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m142);
      }
      {
        vec3 q143 = q97 - vec3(0.0, 0.95, 0.0);
        M m145 = M(sdHull144(q143), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m145);
      }
      {
        vec3 q146 = q97 - vec3(0.27, 1.08, 0.0);
        vec3 q147 = q146 * mat3(0.573576, -0.819152, 0.0, 0.819152, 0.573576, 0.0, 0.0, 0.0, 1.0);
        M m149 = M(sdHull148(q147), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m149);
      }
      {
        vec3 q150 = q97 - vec3(-0.27, 1.08, 0.0);
        vec3 q151 = q150 * mat3(0.573576, 0.819152, 0.0, -0.819152, 0.573576, 0.0, 0.0, 0.0, 1.0);
        M m153 = M(sdHull152(q151), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m153);
      }
      {
        vec3 q154 = q97 - vec3(0.0, 0.74, 0.17);
        M m156 = M(sdHull155(q154), vec3(0.024158, 0.012286, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u98 = mU(u98, m156);
      }
      u91 = mU(u91, u98);
    }
    {
      vec3 q157 = q90 - vec3(0.354, 0.33, 0.04);
      vec3 q158 = q157 - vec3(0.0, 0.0, 0.0);
      M u159 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q160 = q158 - vec3(0.0, 0.22, 0.0);
        M m162 = M(sdHull161(q160), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u159 = mU(u159, m162);
      }
      {
        vec3 q163 = q158 - vec3(0.01, 0.43, 0.0);
        M m165 = M(sdHull164(q163), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u159 = mU(u159, m165);
      }
      u91 = mU(u91, u159);
    }
    if (sdBox(q90 - vec3(-0.4248, 0.42, 0.02), vec3(0.225, 0.225, 0.061962)) < u91.d) {
      vec3 q166 = q90 - vec3(-0.4248, 0.42, 0.0);
      vec3 q167 = q166 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      vec3 q168 = q167 - vec3(0.0, 0.0, 0.0);
      M u169 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q170 = q168 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
        M m172 = M(sdHull171(q170), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u169 = mU(u169, m172);
      }
      {
        vec3 q173 = q168 - vec3(0.0, 0.0, -0.008);
        vec3 q174 = q173 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
        M m176 = M(sdHull175(q174), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u169 = mU(u169, m176);
      }
      {
        vec3 q177 = q168 - vec3(0.0, 0.0, 0.02);
        M m179 = M(sdHull178(q177), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u169 = mU(u169, m179);
      }
      u91 = mU(u91, u169);
    }
    u0 = mU(u0, u91);
  }
  if (sdBox(p - vec3(0.0, 0.6, -0.0125), vec3(0.3855, 0.61, 0.2525)) < u0.d) {
    M u180 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(p - vec3(0.0, 0.6, -0.0125), vec3(0.3855, 0.61, 0.2525)) < u180.d) {
      vec3 q181 = p - vec3(0.0, 0.0, 0.0);
      vec3 q182 = q181 - vec3(0.0, 0.0, 0.0);
      vec3 q183 = q182 - vec3(0.0, 0.0, 0.0);
      vec3 q184 = q183 - vec3(0.0, 0.0, 0.0);
      vec3 q185 = q184 - vec3(0.0, 0.0, 0.0);
      vec3 q186 = q185 - vec3(0.0, 0.0, 0.0);
      M u187 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q188 = q186 - vec3(0.0855, 0.24, 0.0);
        M m189 = M(sdCBox(q188, vec3(0.07125, 0.12, 0.085), 0.03), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m189);
      }
      {
        vec3 q190 = q186 - vec3(0.0855, 0.065, 0.02);
        M m191 = M(sdCBox(q190, vec3(0.0855, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m191);
      }
      {
        vec3 q192 = q186 - vec3(-0.0855, 0.24, 0.0);
        M m193 = M(sdCBox(q192, vec3(0.07125, 0.12, 0.085), 0.03), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m193);
      }
      {
        vec3 q194 = q186 - vec3(-0.0855, 0.065, 0.02);
        M m195 = M(sdCBox(q194, vec3(0.0855, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m195);
      }
      {
        vec3 q196 = q186 - vec3(0.0, 0.4, 0.0);
        M m198 = M(sdHull197(q196), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m198);
      }
      {
        vec3 q199 = q186 - vec3(0.0, 0.39, 0.0);
        M m200 = M(sdCBox(q199, vec3(0.1995, 0.03, 0.14), 0.015), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m200);
      }
      {
        vec3 q201 = q186 - vec3(0.0, 0.39, 0.145);
        M m202 = M(sdCBox(q201, vec3(0.035, 0.03, 0.01), 0.01), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m202);
      }
      {
        vec3 q203 = q186 - vec3(0.0, 0.32, 0.0);
        M m205 = M(sdHull204(q203), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m205);
      }
      {
        vec3 q206 = q186 - vec3(0.285, 0.72, 0.0);
        vec3 q207 = q206 / vec3(1.0, 0.75, 1.0);
        M m209 = M(sdHull208(q207), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m210 = m209; m210.d = m209.d * 0.75;
        u187 = mU(u187, m210);
      }
      {
        vec3 q211 = q186 - vec3(0.285, 0.55, 0.0);
        M m212 = M(sdCBox(q211, vec3(0.05225, 0.13, 0.06), 0.025), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m212);
      }
      {
        vec3 q213 = q186 - vec3(0.285, 0.385, 0.0);
        M m214 = M(sdCBox(q213, vec3(0.06175, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m214);
      }
      {
        vec3 q215 = q186 - vec3(-0.285, 0.72, 0.0);
        vec3 q216 = q215 / vec3(1.0, 0.75, 1.0);
        M m218 = M(sdHull217(q216), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m219 = m218; m219.d = m218.d * 0.75;
        u187 = mU(u187, m219);
      }
      {
        vec3 q220 = q186 - vec3(-0.285, 0.55, 0.0);
        M m221 = M(sdCBox(q220, vec3(0.05225, 0.13, 0.06), 0.025), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m221);
      }
      {
        vec3 q222 = q186 - vec3(-0.285, 0.385, 0.0);
        M m223 = M(sdCBox(q222, vec3(0.06175, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m223);
      }
      {
        vec3 q224 = q186 - vec3(0.0, 0.95, 0.0);
        M m225 = M(sdCBox(q224, vec3(0.19, 0.17, 0.17), 0.07), vec3(0.391572, 0.158961, 0.06301), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m225);
      }
      {
        vec3 q226 = q186;
        q226.x = abs(q226.x);
        vec3 q227 = q226 - vec3(0.07, 0.86, 0.172);
        M m228 = M(sdBox(q227, vec3(0.02, 0.025, 0.01)), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m228);
      }
      {
        vec3 q229 = q186 - vec3(0.0, 0.9, 0.005);
        M m231 = M(sdHull230(q229), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m231);
      }
      {
        vec3 q232 = q186 - vec3(0.0, 0.97, 0.18);
        M m233 = M(sdBox(q232, vec3(0.16, 0.035, 0.015)), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m233);
      }
      {
        vec3 q234 = q186 - vec3(0.0, 0.71, 0.155);
        M m235 = M(sdCBox(q234, vec3(0.18, 0.05, 0.025), 0.02), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u187 = mU(u187, m235);
      }
      u180 = mU(u180, u187);
    }
    if (sdBox(p - vec3(0.285, 0.4625, 0.04), vec3(0.06, 0.1825, 0.0275)) < u180.d) {
      vec3 q236 = p - vec3(0.285, 0.33, 0.04);
      vec3 q237 = q236 - vec3(0.0, 0.0, 0.0);
      M u238 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q239 = q237 - vec3(0.0, 0.055, 0.0);
        M m241 = M(sdHull240(q239), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u238 = mU(u238, m241);
      }
      {
        vec3 q242 = q237 - vec3(0.0, 0.045, 0.0);
        M m243 = M(sdCBox(q242, vec3(0.05, 0.0125, 0.0175), 0.008), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u238 = mU(u238, m243);
      }
      {
        M m245 = M(sdHull244(q237), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u238 = mU(u238, m245);
      }
      u180 = mU(u180, u238);
    }
    if (sdBox(p - vec3(-0.285, 0.4625, 0.04), vec3(0.06, 0.1825, 0.0275)) < u180.d) {
      vec3 q246 = p - vec3(-0.285, 0.33, 0.04);
      vec3 q247 = q246 - vec3(0.0, 0.0, 0.0);
      M u248 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q249 = q247 - vec3(0.0, 0.055, 0.0);
        M m251 = M(sdHull250(q249), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u248 = mU(u248, m251);
      }
      {
        vec3 q252 = q247 - vec3(0.0, 0.045, 0.0);
        M m253 = M(sdCBox(q252, vec3(0.05, 0.0125, 0.0175), 0.008), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u248 = mU(u248, m253);
      }
      {
        M m255 = M(sdHull254(q247), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u248 = mU(u248, m255);
      }
      u180 = mU(u180, u248);
    }
    u0 = mU(u0, u180);
  }
  if (sdBox(p - vec3(1.1, 0.698083, 0.0), vec3(0.416573, 0.708083, 0.370579)) < u0.d) {
    vec3 q256 = p - vec3(1.1, 0.698083, 0.0);
    vec3 q257 = q256 * mat3(0.973579, 0.0, 0.228351, 0.0, 1.0, 0.0, -0.228351, 0.0, 0.973579);
    vec3 q258 = q257 - vec3(0.0, -0.698083, 0.0);
    M u259 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q258 - vec3(0.0, 0.698083, 0.0), vec3(0.405263, 0.708083, 0.31)) < u259.d) {
      vec3 q260 = q258 - vec3(0.0, 0.0, 0.0);
      vec3 q261 = q260 - vec3(0.0, 0.0, 0.0);
      vec3 q262 = q261 - vec3(0.0, 0.0, 0.0);
      vec3 q263 = q262 - vec3(0.0, 0.0, 0.0);
      vec3 q264 = q263 - vec3(0.0, 0.0, 0.0);
      vec3 q265 = q264 - vec3(0.0, 0.0, 0.0);
      M u266 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q267 = q265 - vec3(0.09, 0.24, 0.0);
        M m268 = M(sdCBox(q267, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m268);
      }
      {
        vec3 q269 = q265 - vec3(0.09, 0.065, 0.02);
        M m270 = M(sdCBox(q269, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m270);
      }
      {
        vec3 q271 = q265 - vec3(-0.09, 0.24, 0.0);
        M m272 = M(sdCBox(q271, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m272);
      }
      {
        vec3 q273 = q265 - vec3(-0.09, 0.065, 0.02);
        M m274 = M(sdCBox(q273, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m274);
      }
      {
        vec3 q275 = q265 - vec3(0.0, 0.4, 0.0);
        M m277 = M(sdHull276(q275), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m277);
      }
      {
        vec3 q278 = q265 - vec3(0.0, 0.39, 0.0);
        M m279 = M(sdCBox(q278, vec3(0.21, 0.03, 0.14), 0.015), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m279);
      }
      {
        vec3 q280 = q265 - vec3(0.0, 0.39, 0.145);
        M m281 = M(sdCBox(q280, vec3(0.035, 0.03, 0.01), 0.01), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m281);
      }
      {
        vec3 q282 = q265 - vec3(0.0, 0.2, 0.0);
        M m284 = M(sdHull283(q282), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m284);
      }
      {
        vec3 q285 = q265 - vec3(0.0, 0.57, 0.15);
        M m286 = M(sdCBox(q285, vec3(0.04, 0.15, 0.01), 0.01), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m286);
      }
      {
        vec3 q287 = q265 - vec3(0.3, 0.72, 0.0);
        vec3 q288 = q287 / vec3(1.0, 0.75, 1.0);
        M m290 = M(sdHull289(q288), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m291 = m290; m291.d = m290.d * 0.75;
        u266 = mU(u266, m291);
      }
      {
        vec3 q292 = q265 - vec3(0.3, 0.55, 0.0);
        M m293 = M(sdCBox(q292, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m293);
      }
      {
        vec3 q294 = q265 - vec3(0.3, 0.385, 0.0);
        M m295 = M(sdCBox(q294, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m295);
      }
      {
        vec3 q296 = q265 - vec3(-0.3, 0.72, 0.0);
        vec3 q297 = q296 / vec3(1.0, 0.75, 1.0);
        M m299 = M(sdHull298(q297), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m300 = m299; m300.d = m299.d * 0.75;
        u266 = mU(u266, m300);
      }
      {
        vec3 q301 = q265 - vec3(-0.3, 0.55, 0.0);
        M m302 = M(sdCBox(q301, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m302);
      }
      {
        vec3 q303 = q265 - vec3(-0.3, 0.385, 0.0);
        M m304 = M(sdCBox(q303, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m304);
      }
      {
        vec3 q305 = q265 - vec3(0.0, 0.95, 0.0);
        M m306 = M(sdCBox(q305, vec3(0.19, 0.17, 0.17), 0.07), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m306);
      }
      {
        vec3 q307 = q265;
        q307.x = abs(q307.x);
        vec3 q308 = q307 - vec3(0.07, 0.86, 0.172);
        M m309 = M(sdBox(q308, vec3(0.02, 0.025, 0.01)), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m309);
      }
      {
        vec3 q310 = q265 - vec3(0.0, 0.935, 0.0);
        M m312 = M(sdHull311(q310), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m312);
      }
      {
        vec3 q313 = q265 - vec3(0.0, 0.95, -0.02);
        vec3 q314 = q313 * mat3(1.0, 0.0, 0.0, 0.0, 0.978148, -0.207912, 0.0, 0.207912, 0.978148);
        vec3 q315 = q314 - vec3(0.0, 0.21, 0.0);
        M m317 = M(sdHull316(q315), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m317);
      }
      {
        vec3 q318 = q265 - vec3(0.0, 0.95, 0.0);
        M m320 = M(sdHull319(q318), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m320);
      }
      {
        vec3 q321 = q265 - vec3(0.0, 0.73, 0.17);
        M m323 = M(sdHull322(q321), vec3(0.806952, 0.775822, 0.701102), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u266 = mU(u266, m323);
      }
      u259 = mU(u259, u266);
    }
    if (sdBox(q258 - vec3(0.3, 0.655, 0.04), vec3(0.061962, 0.635, 0.061962)) < u259.d) {
      vec3 q324 = q258 - vec3(0.3, 0.33, 0.04);
      vec3 q325 = q324 - vec3(0.0, 0.0, 0.0);
      M u326 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q327 = q325 - vec3(0.0, 0.25, 0.0);
        M m329 = M(sdHull328(q327), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u326 = mU(u326, m329);
      }
      {
        vec3 q330 = q325 - vec3(0.0, 0.82, 0.0);
        vec3 q331 = q330 * mat3(1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, -1.0);
        M m333 = M(sdHull332(q331), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u326 = mU(u326, m333);
      }
      {
        vec3 q334 = q325 - vec3(0.0, 0.89, 0.0);
        M m336 = M(sdHull335(q334), vec3(0.102242, 0.637597, 0.791298), vec3(0.6, 0.0, 0.8), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u326 = mU(u326, m336);
      }
      u259 = mU(u259, u326);
    }
    if (sdBox(q258 - vec3(-0.2985, 0.33, 0.043), vec3(0.0915, 0.12, 0.038)) < u259.d) {
      vec3 q337 = q258 - vec3(-0.3, 0.33, 0.04);
      vec3 q338 = q337 - vec3(0.0, 0.0, 0.0);
      M u339 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m340 = M(sdCBox(q338, vec3(0.08, 0.11, 0.025), 0.01), vec3(0.254152, 0.042311, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u339 = mU(u339, m340);
      }
      {
        vec3 q341 = q338 - vec3(0.008, 0.0, 0.0);
        M m342 = M(sdBox(q341, vec3(0.075, 0.1, 0.02)), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u339 = mU(u339, m342);
      }
      {
        vec3 q343 = q338 - vec3(0.0, 0.03, 0.026);
        M m344 = M(sdCBox(q343, vec3(0.025, 0.025, 0.005), 0.005), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u339 = mU(u339, m344);
      }
      u259 = mU(u259, u339);
    }
    u0 = mU(u0, u259);
  }
  if (sdBox(p - vec3(2.2, 0.561604, 0.0), vec3(0.406399, 0.619984, 0.31828)) < u0.d) {
    vec3 q345 = p - vec3(2.2, 0.561604, 0.0);
    vec3 q346 = q345 * mat3(0.895712, 0.0, 0.444635, 0.0, 1.0, 0.0, -0.444635, 0.0, 0.895712);
    vec3 q347 = q346 - vec3(0.0, -0.561604, 0.0);
    M u348 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q347 - vec3(0.0, 0.585794, 0.0), vec3(0.405263, 0.595794, 0.24)) < u348.d) {
      vec3 q349 = q347 - vec3(0.0, 0.0, 0.0);
      vec3 q350 = q349 - vec3(0.0, 0.0, 0.0);
      vec3 q351 = q350 - vec3(0.0, 0.0, 0.0);
      vec3 q352 = q351 - vec3(0.0, 0.0, 0.0);
      vec3 q353 = q352 - vec3(0.0, 0.0, 0.0);
      vec3 q354 = q353 - vec3(0.0, 0.0, 0.0);
      M u355 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q356 = q354 - vec3(0.09, 0.24, 0.0);
        M m357 = M(sdCBox(q356, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m357);
      }
      {
        vec3 q358 = q354 - vec3(0.09, 0.065, 0.02);
        M m359 = M(sdCBox(q358, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m359);
      }
      {
        vec3 q360 = q354 - vec3(-0.09, 0.24, 0.0);
        M m361 = M(sdCBox(q360, vec3(0.075, 0.12, 0.085), 0.03), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m361);
      }
      {
        vec3 q362 = q354 - vec3(-0.09, 0.065, 0.02);
        M m363 = M(sdCBox(q362, vec3(0.09, 0.065, 0.12), 0.035), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m363);
      }
      {
        vec3 q364 = q354 - vec3(0.0, 0.4, 0.0);
        M m366 = M(sdHull365(q364), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m366);
      }
      {
        vec3 q367 = q354 - vec3(0.0, 0.39, 0.0);
        M m368 = M(sdCBox(q367, vec3(0.21, 0.03, 0.14), 0.015), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m368);
      }
      {
        vec3 q369 = q354 - vec3(0.0, 0.39, 0.145);
        M m370 = M(sdCBox(q369, vec3(0.035, 0.03, 0.01), 0.01), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m370);
      }
      {
        vec3 q371 = q354 - vec3(0.0, 0.32, 0.0);
        M m373 = M(sdHull372(q371), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m373);
      }
      {
        vec3 q374 = q354 - vec3(0.3, 0.72, 0.0);
        vec3 q375 = q374 / vec3(1.0, 0.75, 1.0);
        M m377 = M(sdHull376(q375), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m378 = m377; m378.d = m377.d * 0.75;
        u355 = mU(u355, m378);
      }
      {
        vec3 q379 = q354 - vec3(0.3, 0.55, 0.0);
        M m380 = M(sdCBox(q379, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m380);
      }
      {
        vec3 q381 = q354 - vec3(0.3, 0.385, 0.0);
        M m382 = M(sdCBox(q381, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m382);
      }
      {
        vec3 q383 = q354 - vec3(-0.3, 0.72, 0.0);
        vec3 q384 = q383 / vec3(1.0, 0.75, 1.0);
        M m386 = M(sdHull385(q384), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m387 = m386; m387.d = m386.d * 0.75;
        u355 = mU(u355, m387);
      }
      {
        vec3 q388 = q354 - vec3(-0.3, 0.55, 0.0);
        M m389 = M(sdCBox(q388, vec3(0.055, 0.13, 0.06), 0.025), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m389);
      }
      {
        vec3 q390 = q354 - vec3(-0.3, 0.385, 0.0);
        M m391 = M(sdCBox(q390, vec3(0.065, 0.055, 0.065), 0.03), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m391);
      }
      {
        vec3 q392 = q354 - vec3(0.0, 0.95, 0.0);
        M m393 = M(sdCBox(q392, vec3(0.19, 0.17, 0.17), 0.07), vec3(0.155926, 0.059511, 0.022174), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m393);
      }
      {
        vec3 q394 = q354;
        q394.x = abs(q394.x);
        vec3 q395 = q394 - vec3(0.07, 0.86, 0.172);
        M m396 = M(sdBox(q395, vec3(0.02, 0.025, 0.01)), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m396);
      }
      {
        vec3 q397 = q354 - vec3(0.0, 0.92, 0.0);
        M m399 = M(sdHull398(q397), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m399);
      }
      {
        vec3 q400 = q354 - vec3(0.14, 1.0, -0.05);
        vec3 q401 = q400 * mat3(0.906308, -0.422618, 0.0, 0.422618, 0.906308, 0.0, 0.0, 0.0, 1.0);
        M m403 = M(sdHull402(q401), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m403);
      }
      {
        vec3 q404 = q354 - vec3(0.0, 0.53, -0.17);
        M m405 = M(sdCBox(q404, vec3(0.21, 0.25, 0.015), 0.01), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u355 = mU(u355, m405);
      }
      u348 = mU(u348, u355);
    }
    if (sdBox(q347 - vec3(-0.3, 0.33, -0.010125), vec3(0.03, 0.388381, 0.080125)) < u348.d) {
      vec3 q406 = q347 - vec3(-0.3, 0.33, -0.02);
      vec3 q407 = q406 - vec3(0.0, 0.0, 0.0);
      M u408 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q409 = q407 - vec3(0.0, -0.312111, -0.012311);
        vec3 q410 = q409 * mat3(1.0, 0.0, 0.0, 0.0, 0.862437, 0.506164, 0.0, -0.506164, 0.862437);
        M m411 = M(sdCapsule(q410, 0.016, 0.051449), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m411);
      }
      {
        vec3 q412 = q407 - vec3(0.0, -0.205571, 0.030883);
        vec3 q413 = q412 * mat3(1.0, 0.0, 0.0, 0.0, 0.963984, 0.265961, 0.0, -0.265961, 0.963984);
        M m414 = M(sdCapsule(q413, 0.016, 0.064492), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m414);
      }
      {
        vec3 q415 = q407 - vec3(0.0, -0.071701, 0.054017);
        vec3 q416 = q415 * mat3(1.0, 0.0, 0.0, 0.0, 0.996537, 0.083148, 0.0, -0.083148, 0.996537);
        M m417 = M(sdCapsule(q416, 0.016, 0.07195), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m417);
      }
      {
        vec3 q418 = q407 - vec3(0.0, 0.071701, 0.054017);
        vec3 q419 = q418 * mat3(1.0, 0.0, 0.0, 0.0, 0.996537, -0.083148, 0.0, 0.083148, 0.996537);
        M m420 = M(sdCapsule(q419, 0.016, 0.07195), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m420);
      }
      {
        vec3 q421 = q407 - vec3(0.0, 0.205571, 0.030883);
        vec3 q422 = q421 * mat3(1.0, 0.0, 0.0, 0.0, 0.963984, -0.265961, 0.0, 0.265961, 0.963984);
        M m423 = M(sdCapsule(q422, 0.016, 0.064492), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m423);
      }
      {
        vec3 q424 = q407 - vec3(0.0, 0.312111, -0.012311);
        vec3 q425 = q424 * mat3(1.0, 0.0, 0.0, 0.0, 0.862437, -0.506164, 0.0, 0.506164, 0.862437);
        M m426 = M(sdCapsule(q425, 0.016, 0.051449), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m426);
      }
      {
        vec3 q427 = q407 - vec3(0.0, 0.0, -0.038353);
        vec3 q428 = q427 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m429 = M(sdCapsule(q428, 0.004, 0.356483), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m429);
      }
      {
        vec3 q430 = q407 - vec3(0.0, 0.0, 0.06);
        M m431 = M(sdCBox(q430, vec3(0.02, 0.045, 0.02), 0.01), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u408 = mU(u408, m431);
      }
      u348 = mU(u348, u408);
    }
    if (sdBox(q347 - vec3(0.0, 0.645, -0.095), vec3(0.082, 0.275, 0.072354)) < u348.d) {
      vec3 q432 = q347 - vec3(0.0, 0.55, -0.095);
      vec3 q433 = q432 - vec3(0.0, 0.0, 0.0);
      M u434 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m436 = M(sdHull435(q433), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m436);
      }
      {
        vec3 q437 = q433 - vec3(0.0, 0.15, 0.0);
        M m439 = M(sdHull438(q437), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m439);
      }
      {
        vec3 q440 = q433 - vec3(0.02, 0.225, 0.01);
        vec3 q441 = q440 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m442 = M(sdCapsule(q441, 0.005, 0.075), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m442);
      }
      {
        M m444 = M(sdHull443(q433), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m444);
      }
      {
        vec3 q445 = q433 - vec3(-0.02, 0.225, 0.02);
        vec3 q446 = q445 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m447 = M(sdCapsule(q446, 0.005, 0.075), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m447);
      }
      {
        M m449 = M(sdHull448(q433), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m449);
      }
      {
        vec3 q450 = q433 - vec3(0.0, 0.225, -0.02);
        vec3 q451 = q450 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m452 = M(sdCapsule(q451, 0.005, 0.075), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m452);
      }
      {
        M m454 = M(sdHull453(q433), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u434 = mU(u434, m454);
      }
      u348 = mU(u348, u434);
    }
    u0 = mU(u0, u348);
  }
  {
    vec3 q455 = p - vec3(0.0, -0.04, 0.0);
    vec3 q456 = q455 / vec3(1.0, 1.0, 0.4);
    M m458 = M(sdHull457(q456), vec3(0.158961, 0.254152, 0.068478), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m459 = m458; m459.d = m458.d * 0.4;
    u0 = mU(u0, m459);
  }
  return u0;
}
