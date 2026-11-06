
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
    M m1 = M(p.y, vec3(0.158961, 0.254152, 0.068478), vec3(0.6, 0.0, 0.0), vec3(0.07948, 0.127076, 0.034239), vec4(1.0, 0.6, 1.0, 0.0), p, 0.0);
    u0 = mU(u0, m1);
  }
  if (cullVis(0) && sdBox(p - vec3(0.0, 2.294039, 0.0), vec3(5.31, 2.315961, 2.81)) < u0.d) {
    vec3 q2 = p - vec3(0.0, 0.0, 0.0);
    vec3 q3 = q2 - vec3(0.0, 0.0, 0.0);
    vec3 q4 = q3 - vec3(0.0, 0.0, 0.0);
    M u5 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q4 - vec3(0.0, 1.2, 0.0), vec3(5.01, 1.21, 2.26)) < u5.d) {
      M u6 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q4 - vec3(0.0, 0.25, 0.0), vec3(5.01, 0.26, 2.26)) < u6.d) {
        vec3 q7 = q4 - vec3(0.0, 0.25, 0.0);
        M m8 = M(sdBox(q7, vec3(5.0, 0.25, 2.25)), vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m9 = m8; m9.d = (m8.d + 0.02 * patG(q4, vec3(-5.0, 0.0, -2.25), vec3(0.0, 0.25, 0.0), vec3(5.0, 0.25, 2.25), 3, vec2(0.45, 0.25), 0.015, 1, 0.4)) * 0.272727;
        u6 = mU(u6, m9);
      }
      if (sdBox(q4 - vec3(0.0, 1.45, 0.0), vec3(5.01, 0.96, 2.21)) < u6.d) {
        vec3 q10 = q4 - vec3(0.0, 1.45, 0.0);
        M m11 = M(sdBox(q10, vec3(5.0, 0.95, 2.2)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m12 = m11; m12.d = (m11.d + 0.012 * patG(q4, vec3(-5.0, 0.5, -2.2), vec3(0.0, 1.45, 0.0), vec3(5.0, 0.95, 2.2), 1, vec2(1.6, 0.3), 0.008, 1, 0.25)) * 0.25;
        u6 = mU(u6, m12);
      }
      u5 = mU(u5, u6);
    }
    if (sdBox(q4 - vec3(0.0, 1.194039, 2.375), vec3(5.01, 1.215961, 0.195)) < u5.d) {
      M u13 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q4 - vec3(0.008189, 0.25, 2.375), vec3(4.982406, 0.271923, 0.140961)) < u13.d) {
        M u14 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q15 = q4 - vec3(-4.656786, 0.25, 2.375);
          vec3 q16 = q15 / vec3(0.95117, 0.95117, 0.95117);
          M m17 = M(sdBox(q16, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m18 = m17; m18.d = m17.d * 0.95117;
          u14 = mU(u14, m18);
        }
        {
          vec3 q19 = q4 - vec3(-3.940357, 0.25, 2.375);
          vec3 q20 = q19 / vec3(0.956196, 0.956196, 0.956196);
          M m21 = M(sdBox(q20, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m22 = m21; m22.d = m21.d * 0.956196;
          u14 = mU(u14, m22);
        }
        {
          vec3 q23 = q4 - vec3(-3.223929, 0.25, 2.375);
          vec3 q24 = q23 / vec3(1.047691, 1.047691, 1.047691);
          M m25 = M(sdBox(q24, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m26 = m25; m26.d = m25.d * 1.047691;
          u14 = mU(u14, m26);
        }
        {
          vec3 q27 = q4 - vec3(-2.5075, 0.25, 2.375);
          vec3 q28 = q27 / vec3(1.019903, 1.019903, 1.019903);
          M m29 = M(sdBox(q28, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m30 = m29; m30.d = m29.d * 1.019903;
          u14 = mU(u14, m30);
        }
        {
          vec3 q31 = q4 - vec3(-1.791071, 0.25, 2.375);
          vec3 q32 = q31 / vec3(1.002145, 1.002145, 1.002145);
          M m33 = M(sdBox(q32, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m34 = m33; m34.d = m33.d * 1.002145;
          u14 = mU(u14, m34);
        }
        {
          vec3 q35 = q4 - vec3(-1.074643, 0.25, 2.375);
          vec3 q36 = q35 / vec3(0.990552, 0.990552, 0.990552);
          M m37 = M(sdBox(q36, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m38 = m37; m38.d = m37.d * 0.990552;
          u14 = mU(u14, m38);
        }
        {
          vec3 q39 = q4 - vec3(-0.358214, 0.25, 2.375);
          vec3 q40 = q39 / vec3(0.996623, 0.996623, 0.996623);
          M m41 = M(sdBox(q40, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m42 = m41; m42.d = m41.d * 0.996623;
          u14 = mU(u14, m42);
        }
        {
          vec3 q43 = q4 - vec3(0.358214, 0.25, 2.375);
          vec3 q44 = q43 / vec3(0.973993, 0.973993, 0.973993);
          M m45 = M(sdBox(q44, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m46 = m45; m46.d = m45.d * 0.973993;
          u14 = mU(u14, m46);
        }
        {
          vec3 q47 = q4 - vec3(1.074643, 0.25, 2.375);
          vec3 q48 = q47 / vec3(1.005333, 1.005333, 1.005333);
          M m49 = M(sdBox(q48, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m50 = m49; m50.d = m49.d * 1.005333;
          u14 = mU(u14, m50);
        }
        {
          vec3 q51 = q4 - vec3(1.791071, 0.25, 2.375);
          vec3 q52 = q51 / vec3(1.022982, 1.022982, 1.022982);
          M m53 = M(sdBox(q52, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m54 = m53; m54.d = m53.d * 1.022982;
          u14 = mU(u14, m54);
        }
        {
          vec3 q55 = q4 - vec3(2.5075, 0.25, 2.375);
          vec3 q56 = q55 / vec3(0.975782, 0.975782, 0.975782);
          M m57 = M(sdBox(q56, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m58 = m57; m58.d = m57.d * 0.975782;
          u14 = mU(u14, m58);
        }
        {
          vec3 q59 = q4 - vec3(3.223929, 0.25, 2.375);
          vec3 q60 = q59 / vec3(0.965595, 0.965595, 0.965595);
          M m61 = M(sdBox(q60, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m62 = m61; m62.d = m61.d * 0.965595;
          u14 = mU(u14, m62);
        }
        {
          vec3 q63 = q4 - vec3(3.940357, 0.25, 2.375);
          vec3 q64 = q63 / vec3(1.026409, 1.026409, 1.026409);
          M m65 = M(sdBox(q64, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m66 = m65; m66.d = m65.d * 1.026409;
          u14 = mU(u14, m66);
        }
        {
          vec3 q67 = q4 - vec3(4.656786, 0.25, 2.375);
          vec3 q68 = q67 / vec3(1.00184, 1.00184, 1.00184);
          M m69 = M(sdBox(q68, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m70 = m69; m70.d = m69.d * 1.00184;
          u14 = mU(u14, m70);
        }
        u13 = mU(u13, u14);
      }
      if (sdBox(q4 - vec3(-3.7, 1.34, 2.375), vec3(1.31, 0.85, 0.135)) < u13.d) {
        M u71 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q72 = q4 - vec3(-4.844062, 1.34, 2.375);
          M m73 = M(sdCBox(q72, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.157587, 0.073745, 0.029075), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m73);
        }
        {
          vec3 q74 = q4 - vec3(-4.517188, 1.34, 2.375);
          M m75 = M(sdCBox(q74, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.167083, 0.078493, 0.030648), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m75);
        }
        {
          vec3 q76 = q4 - vec3(-4.190313, 1.34, 2.375);
          M m77 = M(sdCBox(q76, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.16289, 0.076395, 0.029954), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m77);
        }
        {
          vec3 q78 = q4 - vec3(-3.863437, 1.34, 2.375);
          M m79 = M(sdCBox(q78, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.17667, 0.083297, 0.032229), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m79);
        }
        {
          vec3 q80 = q4 - vec3(-3.536562, 1.34, 2.375);
          M m81 = M(sdCBox(q80, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.163062, 0.076481, 0.029983), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m81);
        }
        {
          vec3 q82 = q4 - vec3(-3.209688, 1.34, 2.375);
          M m83 = M(sdCBox(q82, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.203676, 0.09688, 0.03666), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m83);
        }
        {
          vec3 q84 = q4 - vec3(-2.882813, 1.34, 2.375);
          M m85 = M(sdCBox(q84, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.160355, 0.075128, 0.029534), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m85);
        }
        {
          vec3 q86 = q4 - vec3(-2.555937, 1.34, 2.375);
          M m87 = M(sdCBox(q86, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.197376, 0.093705, 0.03563), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u71 = mU(u71, m87);
        }
        u13 = mU(u13, u71);
      }
      {
        M u88 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q89 = q4 - vec3(-2.20375, 0.91, 2.375);
          M m90 = M(sdCBox(q89, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.15724, 0.073572, 0.029018), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u88 = mU(u88, m90);
        }
        {
          vec3 q91 = q4 - vec3(-1.79625, 0.91, 2.375);
          M m92 = M(sdCBox(q91, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.15468, 0.072293, 0.028593), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u88 = mU(u88, m92);
        }
        u13 = mU(u13, u88);
      }
      {
        M u93 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q94 = q4 - vec3(-2.20375, 1.975, 2.375);
          M m95 = M(sdCBox(q94, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.155274, 0.07259, 0.028692), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u93 = mU(u93, m95);
        }
        {
          vec3 q96 = q4 - vec3(-1.79625, 1.975, 2.375);
          M m97 = M(sdCBox(q96, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.162762, 0.076331, 0.029933), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u93 = mU(u93, m97);
        }
        u13 = mU(u13, u93);
      }
      {
        vec3 q98 = q4 - vec3(-2.0, 1.545, 2.375);
        M m99 = M(sdBox(q98, vec3(0.36, 0.225, 0.155)), vec3(0.01096, 0.013702, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m99);
      }
      {
        vec3 q100 = q4 - vec3(-2.0, 1.745, 2.375);
        M m101 = M(sdBox(q100, vec3(0.45, 0.025, 0.185)), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m101);
      }
      if (sdBox(q4 - vec3(-1.15, 1.34, 2.375), vec3(0.46, 0.85, 0.135)) < u13.d) {
        M u102 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q103 = q4 - vec3(-1.455, 1.34, 2.375);
          M m104 = M(sdCBox(q103, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.17744, 0.083683, 0.032356), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u102 = mU(u102, m104);
        }
        {
          vec3 q105 = q4 - vec3(-1.15, 1.34, 2.375);
          M m106 = M(sdCBox(q105, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.19023, 0.090109, 0.034458), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u102 = mU(u102, m106);
        }
        {
          vec3 q107 = q4 - vec3(-0.845, 1.34, 2.375);
          M m108 = M(sdCBox(q107, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.150968, 0.070442, 0.027977), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u102 = mU(u102, m108);
        }
        u13 = mU(u13, u102);
      }
      {
        vec3 q109 = q4 - vec3(0.0, 1.175, 2.375);
        M m110 = M(sdCBox(q109, vec3(0.64, 0.655, 0.145), 0.02), vec3(0.068478, 0.029557, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m110);
      }
      {
        vec3 q111 = q4 - vec3(0.0, 2.14, 2.375);
        M m112 = M(sdBox(q111, vec3(0.78, 0.04, 0.165)), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m112);
      }
      {
        vec3 q113 = q4 - vec3(0.0, 0.905, 2.375);
        M m114 = M(sdBox(q113, vec3(0.5, 0.025, 0.175)), vec3(0.023153, 0.023153, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m114);
      }
      {
        vec3 q115 = q4 - vec3(0.0, 1.175, 2.375);
        M m116 = M(sdBox(q115, vec3(0.5, 0.025, 0.175)), vec3(0.023153, 0.023153, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m116);
      }
      {
        vec3 q117 = q4 - vec3(0.0, 1.445, 2.375);
        M m118 = M(sdBox(q117, vec3(0.5, 0.025, 0.175)), vec3(0.023153, 0.023153, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m118);
      }
      if (sdBox(q4 - vec3(1.15, 1.34, 2.375), vec3(0.46, 0.85, 0.135)) < u13.d) {
        M u119 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q120 = q4 - vec3(0.845, 1.34, 2.375);
          M m121 = M(sdCBox(q120, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.199575, 0.094813, 0.035989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u119 = mU(u119, m121);
        }
        {
          vec3 q122 = q4 - vec3(1.15, 1.34, 2.375);
          M m123 = M(sdCBox(q122, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.17778, 0.083854, 0.032412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u119 = mU(u119, m123);
        }
        {
          vec3 q124 = q4 - vec3(1.455, 1.34, 2.375);
          M m125 = M(sdCBox(q124, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.181788, 0.085866, 0.033072), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u119 = mU(u119, m125);
        }
        u13 = mU(u13, u119);
      }
      {
        M u126 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q127 = q4 - vec3(1.79625, 0.91, 2.375);
          M m128 = M(sdCBox(q127, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.18528, 0.08762, 0.033646), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u126 = mU(u126, m128);
        }
        {
          vec3 q129 = q4 - vec3(2.20375, 0.91, 2.375);
          M m130 = M(sdCBox(q129, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.202918, 0.096498, 0.036536), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u126 = mU(u126, m130);
        }
        u13 = mU(u13, u126);
      }
      {
        M u131 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q132 = q4 - vec3(1.79625, 1.975, 2.375);
          M m133 = M(sdCBox(q132, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.181952, 0.085948, 0.033099), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u131 = mU(u131, m133);
        }
        {
          vec3 q134 = q4 - vec3(2.20375, 1.975, 2.375);
          M m135 = M(sdCBox(q134, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.200093, 0.095074, 0.036074), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u131 = mU(u131, m135);
        }
        u13 = mU(u13, u131);
      }
      {
        vec3 q136 = q4 - vec3(2.0, 1.545, 2.375);
        M m137 = M(sdBox(q136, vec3(0.36, 0.225, 0.155)), vec3(0.01096, 0.013702, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m137);
      }
      {
        vec3 q138 = q4 - vec3(2.0, 1.745, 2.375);
        M m139 = M(sdBox(q138, vec3(0.45, 0.025, 0.185)), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m139);
      }
      if (sdBox(q4 - vec3(3.7, 1.34, 2.375), vec3(1.31, 0.85, 0.135)) < u13.d) {
        M u140 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q141 = q4 - vec3(2.555937, 1.34, 2.375);
          M m142 = M(sdCBox(q141, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.194265, 0.092139, 0.03512), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m142);
        }
        {
          vec3 q143 = q4 - vec3(2.882813, 1.34, 2.375);
          M m144 = M(sdCBox(q143, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.149134, 0.069528, 0.027672), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m144);
        }
        {
          vec3 q145 = q4 - vec3(3.209687, 1.34, 2.375);
          M m146 = M(sdCBox(q145, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.156376, 0.07314, 0.028875), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m146);
        }
        {
          vec3 q147 = q4 - vec3(3.536562, 1.34, 2.375);
          M m148 = M(sdCBox(q147, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.166463, 0.078183, 0.030545), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m148);
        }
        {
          vec3 q149 = q4 - vec3(3.863437, 1.34, 2.375);
          M m150 = M(sdCBox(q149, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.170345, 0.080127, 0.031186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m150);
        }
        {
          vec3 q151 = q4 - vec3(4.190312, 1.34, 2.375);
          M m152 = M(sdCBox(q151, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.148088, 0.069007, 0.027498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m152);
        }
        {
          vec3 q153 = q4 - vec3(4.517188, 1.34, 2.375);
          M m154 = M(sdCBox(q153, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.151694, 0.070804, 0.028097), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m154);
        }
        {
          vec3 q155 = q4 - vec3(4.844062, 1.34, 2.375);
          M m156 = M(sdCBox(q155, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.190605, 0.090297, 0.03452), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u140 = mU(u140, m156);
        }
        u13 = mU(u13, u140);
      }
      {
        vec3 q157 = q4 - vec3(0.0, 2.29, 2.375);
        M m158 = M(sdCBox(q157, vec3(5.0, 0.11, 0.125), 0.03), vec3(0.068478, 0.029557, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u13 = mU(u13, m158);
      }
      u5 = mU(u5, u13);
    }
    if (sdBox(q4 - vec3(0.0, 1.194039, 0.0), vec3(5.01, 1.215961, 2.57)) < u5.d) {
      vec3 q159 = q4;
      q159.z = abs(q159.z);
      M u160 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      if (sdBox(q159 - vec3(0.008189, 0.25, 2.375), vec3(4.982406, 0.271923, 0.140961)) < u160.d) {
        M u161 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q162 = q159 - vec3(-4.656786, 0.25, 2.375);
          vec3 q163 = q162 / vec3(0.95117, 0.95117, 0.95117);
          M m164 = M(sdBox(q163, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m165 = m164; m165.d = m164.d * 0.95117;
          u161 = mU(u161, m165);
        }
        {
          vec3 q166 = q159 - vec3(-3.940357, 0.25, 2.375);
          vec3 q167 = q166 / vec3(0.956196, 0.956196, 0.956196);
          M m168 = M(sdBox(q167, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m169 = m168; m169.d = m168.d * 0.956196;
          u161 = mU(u161, m169);
        }
        {
          vec3 q170 = q159 - vec3(-3.223929, 0.25, 2.375);
          vec3 q171 = q170 / vec3(1.047691, 1.047691, 1.047691);
          M m172 = M(sdBox(q171, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m173 = m172; m173.d = m172.d * 1.047691;
          u161 = mU(u161, m173);
        }
        {
          vec3 q174 = q159 - vec3(-2.5075, 0.25, 2.375);
          vec3 q175 = q174 / vec3(1.019903, 1.019903, 1.019903);
          M m176 = M(sdBox(q175, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m177 = m176; m177.d = m176.d * 1.019903;
          u161 = mU(u161, m177);
        }
        {
          vec3 q178 = q159 - vec3(-1.791071, 0.25, 2.375);
          vec3 q179 = q178 / vec3(1.002145, 1.002145, 1.002145);
          M m180 = M(sdBox(q179, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m181 = m180; m181.d = m180.d * 1.002145;
          u161 = mU(u161, m181);
        }
        {
          vec3 q182 = q159 - vec3(-1.074643, 0.25, 2.375);
          vec3 q183 = q182 / vec3(0.990552, 0.990552, 0.990552);
          M m184 = M(sdBox(q183, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m185 = m184; m185.d = m184.d * 0.990552;
          u161 = mU(u161, m185);
        }
        {
          vec3 q186 = q159 - vec3(-0.358214, 0.25, 2.375);
          vec3 q187 = q186 / vec3(0.996623, 0.996623, 0.996623);
          M m188 = M(sdBox(q187, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m189 = m188; m189.d = m188.d * 0.996623;
          u161 = mU(u161, m189);
        }
        {
          vec3 q190 = q159 - vec3(0.358214, 0.25, 2.375);
          vec3 q191 = q190 / vec3(0.973993, 0.973993, 0.973993);
          M m192 = M(sdBox(q191, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m193 = m192; m193.d = m192.d * 0.973993;
          u161 = mU(u161, m193);
        }
        {
          vec3 q194 = q159 - vec3(1.074643, 0.25, 2.375);
          vec3 q195 = q194 / vec3(1.005333, 1.005333, 1.005333);
          M m196 = M(sdBox(q195, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m197 = m196; m197.d = m196.d * 1.005333;
          u161 = mU(u161, m197);
        }
        {
          vec3 q198 = q159 - vec3(1.791071, 0.25, 2.375);
          vec3 q199 = q198 / vec3(1.022982, 1.022982, 1.022982);
          M m200 = M(sdBox(q199, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m201 = m200; m201.d = m200.d * 1.022982;
          u161 = mU(u161, m201);
        }
        {
          vec3 q202 = q159 - vec3(2.5075, 0.25, 2.375);
          vec3 q203 = q202 / vec3(0.975782, 0.975782, 0.975782);
          M m204 = M(sdBox(q203, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m205 = m204; m205.d = m204.d * 0.975782;
          u161 = mU(u161, m205);
        }
        {
          vec3 q206 = q159 - vec3(3.223929, 0.25, 2.375);
          vec3 q207 = q206 / vec3(0.965595, 0.965595, 0.965595);
          M m208 = M(sdBox(q207, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m209 = m208; m209.d = m208.d * 0.965595;
          u161 = mU(u161, m209);
        }
        {
          vec3 q210 = q159 - vec3(3.940357, 0.25, 2.375);
          vec3 q211 = q210 / vec3(1.026409, 1.026409, 1.026409);
          M m212 = M(sdBox(q211, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m213 = m212; m213.d = m212.d * 1.026409;
          u161 = mU(u161, m213);
        }
        {
          vec3 q214 = q159 - vec3(4.656786, 0.25, 2.375);
          vec3 q215 = q214 / vec3(1.00184, 1.00184, 1.00184);
          M m216 = M(sdBox(q215, vec3(0.273214, 0.2, 0.075)) - 0.05, vec3(0.323143, 0.304987, 0.270498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          M m217 = m216; m217.d = m216.d * 1.00184;
          u161 = mU(u161, m217);
        }
        u160 = mU(u160, u161);
      }
      if (sdBox(q159 - vec3(-3.7, 1.34, 2.375), vec3(1.31, 0.85, 0.135)) < u160.d) {
        M u218 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q219 = q159 - vec3(-4.844062, 1.34, 2.375);
          M m220 = M(sdCBox(q219, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.157587, 0.073745, 0.029075), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m220);
        }
        {
          vec3 q221 = q159 - vec3(-4.517188, 1.34, 2.375);
          M m222 = M(sdCBox(q221, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.167083, 0.078493, 0.030648), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m222);
        }
        {
          vec3 q223 = q159 - vec3(-4.190313, 1.34, 2.375);
          M m224 = M(sdCBox(q223, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.16289, 0.076395, 0.029954), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m224);
        }
        {
          vec3 q225 = q159 - vec3(-3.863437, 1.34, 2.375);
          M m226 = M(sdCBox(q225, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.17667, 0.083297, 0.032229), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m226);
        }
        {
          vec3 q227 = q159 - vec3(-3.536562, 1.34, 2.375);
          M m228 = M(sdCBox(q227, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.163062, 0.076481, 0.029983), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m228);
        }
        {
          vec3 q229 = q159 - vec3(-3.209688, 1.34, 2.375);
          M m230 = M(sdCBox(q229, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.203676, 0.09688, 0.03666), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m230);
        }
        {
          vec3 q231 = q159 - vec3(-2.882813, 1.34, 2.375);
          M m232 = M(sdCBox(q231, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.160355, 0.075128, 0.029534), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m232);
        }
        {
          vec3 q233 = q159 - vec3(-2.555937, 1.34, 2.375);
          M m234 = M(sdCBox(q233, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.197376, 0.093705, 0.03563), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u218 = mU(u218, m234);
        }
        u160 = mU(u160, u218);
      }
      {
        M u235 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q236 = q159 - vec3(-2.20375, 0.91, 2.375);
          M m237 = M(sdCBox(q236, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.15724, 0.073572, 0.029018), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u235 = mU(u235, m237);
        }
        {
          vec3 q238 = q159 - vec3(-1.79625, 0.91, 2.375);
          M m239 = M(sdCBox(q238, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.15468, 0.072293, 0.028593), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u235 = mU(u235, m239);
        }
        u160 = mU(u160, u235);
      }
      {
        M u240 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q241 = q159 - vec3(-2.20375, 1.975, 2.375);
          M m242 = M(sdCBox(q241, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.155274, 0.07259, 0.028692), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u240 = mU(u240, m242);
        }
        {
          vec3 q243 = q159 - vec3(-1.79625, 1.975, 2.375);
          M m244 = M(sdCBox(q243, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.162762, 0.076331, 0.029933), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u240 = mU(u240, m244);
        }
        u160 = mU(u160, u240);
      }
      {
        vec3 q245 = q159 - vec3(-2.0, 1.545, 2.375);
        M m246 = M(sdBox(q245, vec3(0.36, 0.225, 0.155)), vec3(0.01096, 0.013702, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m246);
      }
      {
        vec3 q247 = q159 - vec3(-2.0, 1.745, 2.375);
        M m248 = M(sdBox(q247, vec3(0.45, 0.025, 0.185)), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m248);
      }
      if (sdBox(q159 - vec3(-1.15, 1.34, 2.375), vec3(0.46, 0.85, 0.135)) < u160.d) {
        M u249 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q250 = q159 - vec3(-1.455, 1.34, 2.375);
          M m251 = M(sdCBox(q250, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.17744, 0.083683, 0.032356), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u249 = mU(u249, m251);
        }
        {
          vec3 q252 = q159 - vec3(-1.15, 1.34, 2.375);
          M m253 = M(sdCBox(q252, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.19023, 0.090109, 0.034458), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u249 = mU(u249, m253);
        }
        {
          vec3 q254 = q159 - vec3(-0.845, 1.34, 2.375);
          M m255 = M(sdCBox(q254, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.150968, 0.070442, 0.027977), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u249 = mU(u249, m255);
        }
        u160 = mU(u160, u249);
      }
      {
        vec3 q256 = q159 - vec3(0.0, 1.175, 2.375);
        M m257 = M(sdCBox(q256, vec3(0.64, 0.655, 0.145), 0.02), vec3(0.068478, 0.029557, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m257);
      }
      {
        vec3 q258 = q159 - vec3(0.0, 2.14, 2.375);
        M m259 = M(sdBox(q258, vec3(0.78, 0.04, 0.165)), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m259);
      }
      {
        vec3 q260 = q159 - vec3(0.0, 0.905, 2.375);
        M m261 = M(sdBox(q260, vec3(0.5, 0.025, 0.175)), vec3(0.023153, 0.023153, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m261);
      }
      {
        vec3 q262 = q159 - vec3(0.0, 1.175, 2.375);
        M m263 = M(sdBox(q262, vec3(0.5, 0.025, 0.175)), vec3(0.023153, 0.023153, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m263);
      }
      {
        vec3 q264 = q159 - vec3(0.0, 1.445, 2.375);
        M m265 = M(sdBox(q264, vec3(0.5, 0.025, 0.175)), vec3(0.023153, 0.023153, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m265);
      }
      if (sdBox(q159 - vec3(1.15, 1.34, 2.375), vec3(0.46, 0.85, 0.135)) < u160.d) {
        M u266 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q267 = q159 - vec3(0.845, 1.34, 2.375);
          M m268 = M(sdCBox(q267, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.199575, 0.094813, 0.035989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u266 = mU(u266, m268);
        }
        {
          vec3 q269 = q159 - vec3(1.15, 1.34, 2.375);
          M m270 = M(sdCBox(q269, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.17778, 0.083854, 0.032412), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u266 = mU(u266, m270);
        }
        {
          vec3 q271 = q159 - vec3(1.455, 1.34, 2.375);
          M m272 = M(sdCBox(q271, vec3(0.145, 0.84, 0.125), 0.012), vec3(0.181788, 0.085866, 0.033072), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u266 = mU(u266, m272);
        }
        u160 = mU(u160, u266);
      }
      {
        M u273 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q274 = q159 - vec3(1.79625, 0.91, 2.375);
          M m275 = M(sdCBox(q274, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.18528, 0.08762, 0.033646), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u273 = mU(u273, m275);
        }
        {
          vec3 q276 = q159 - vec3(2.20375, 0.91, 2.375);
          M m277 = M(sdCBox(q276, vec3(0.19625, 0.41, 0.125), 0.012), vec3(0.202918, 0.096498, 0.036536), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u273 = mU(u273, m277);
        }
        u160 = mU(u160, u273);
      }
      {
        M u278 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q279 = q159 - vec3(1.79625, 1.975, 2.375);
          M m280 = M(sdCBox(q279, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.181952, 0.085948, 0.033099), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u278 = mU(u278, m280);
        }
        {
          vec3 q281 = q159 - vec3(2.20375, 1.975, 2.375);
          M m282 = M(sdCBox(q281, vec3(0.19625, 0.205, 0.125), 0.012), vec3(0.200093, 0.095074, 0.036074), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u278 = mU(u278, m282);
        }
        u160 = mU(u160, u278);
      }
      {
        vec3 q283 = q159 - vec3(2.0, 1.545, 2.375);
        M m284 = M(sdBox(q283, vec3(0.36, 0.225, 0.155)), vec3(0.01096, 0.013702, 0.017642), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m284);
      }
      {
        vec3 q285 = q159 - vec3(2.0, 1.745, 2.375);
        M m286 = M(sdBox(q285, vec3(0.45, 0.025, 0.185)), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m286);
      }
      if (sdBox(q159 - vec3(3.7, 1.34, 2.375), vec3(1.31, 0.85, 0.135)) < u160.d) {
        M u287 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
        {
          vec3 q288 = q159 - vec3(2.555937, 1.34, 2.375);
          M m289 = M(sdCBox(q288, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.194265, 0.092139, 0.03512), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m289);
        }
        {
          vec3 q290 = q159 - vec3(2.882813, 1.34, 2.375);
          M m291 = M(sdCBox(q290, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.149134, 0.069528, 0.027672), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m291);
        }
        {
          vec3 q292 = q159 - vec3(3.209687, 1.34, 2.375);
          M m293 = M(sdCBox(q292, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.156376, 0.07314, 0.028875), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m293);
        }
        {
          vec3 q294 = q159 - vec3(3.536562, 1.34, 2.375);
          M m295 = M(sdCBox(q294, vec3(0.155938, 0.84, 0.125), 0.012), vec3(0.166463, 0.078183, 0.030545), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m295);
        }
        {
          vec3 q296 = q159 - vec3(3.863437, 1.34, 2.375);
          M m297 = M(sdCBox(q296, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.170345, 0.080127, 0.031186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m297);
        }
        {
          vec3 q298 = q159 - vec3(4.190312, 1.34, 2.375);
          M m299 = M(sdCBox(q298, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.148088, 0.069007, 0.027498), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m299);
        }
        {
          vec3 q300 = q159 - vec3(4.517188, 1.34, 2.375);
          M m301 = M(sdCBox(q300, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.151694, 0.070804, 0.028097), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m301);
        }
        {
          vec3 q302 = q159 - vec3(4.844062, 1.34, 2.375);
          M m303 = M(sdCBox(q302, vec3(0.155937, 0.84, 0.125), 0.012), vec3(0.190605, 0.090297, 0.03452), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
          u287 = mU(u287, m303);
        }
        u160 = mU(u160, u287);
      }
      {
        vec3 q304 = q159 - vec3(0.0, 2.29, 2.375);
        M m305 = M(sdCBox(q304, vec3(5.0, 0.11, 0.125), 0.03), vec3(0.068478, 0.029557, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u160 = mU(u160, m305);
      }
      u5 = mU(u5, u160);
    }
    if (sdBox(q4 - vec3(0.0, 3.5, 0.0), vec3(5.31, 1.11, 2.81)) < u5.d) {
      vec3 q306 = q4 - vec3(0.0, 3.5, 0.0);
      vec3 q307 = q306 * mat3(0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0);
      M m308 = M(sdPrism(q307, 2.8, 2.2, 5.3), vec3(0.147027, 0.084376, 0.036889), vec3(0.6, 0.0, 0.0), vec3(0.068478, 0.039546, 0.019382), vec4(8.0, 1.5, 1.0, 0.0), q4, 0.0);
      M m309 = m308; m309.d = (m308.d + 0.04 * patG(q4, vec3(-5.3, 2.4, -2.8), vec3(0.0, 3.5, 0.0), vec3(5.3, 1.1, 2.8), 2, vec2(0.32, 0.22), 0.01, 1, 0.3)) * 0.111111;
      u5 = mU(u5, m309);
    }
    u0 = mU(u0, u5);
  }
  if (cullVis(1)) {
    vec3 q310 = p - vec3(0.0, 4.55, 0.0);
    vec3 q311 = q310 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
    M m312 = M(sdCyl(q311, 0.12, 5.5), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m312);
  }
  if (cullVis(2)) {
    vec3 q313 = p;
    q313.x = abs(q313.x);
    vec3 q314 = q313 - vec3(5.35, 4.5, 0.0);
    M u315 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m316 = M(sdRoundCone(q314, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.8, 0.45), 0.06, 0.03), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u315 = mU(u315, m316);
    }
    {
      M m317 = M(sdRoundCone(q314, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.8, -0.45), 0.06, 0.03), vec3(0.046665, 0.023153, 0.01033), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u315 = mU(u315, m317);
    }
    u0 = mU(u0, u315);
  }
  if (cullVis(3)) {
    vec3 q318 = p - vec3(-1.15, 1.34, 2.545);
    M u319 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q320 = q318 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m321 = M(sdCyl(q320, 0.32, 0.025), vec3(0.262251, 0.028426, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u319 = mU(u319, m321);
    }
    {
      vec3 q322 = q318 - vec3(0.0, 0.0, 0.095);
      M m323 = M(length(q322) - 0.07, vec3(0.323143, 0.323143, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u319 = mU(u319, m323);
    }
    u0 = mU(u0, u319);
  }
  if (cullVis(4)) {
    vec3 q324 = p - vec3(1.15, 1.34, 2.545);
    M u325 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q326 = q324 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m327 = M(sdCyl(q326, 0.32, 0.025), vec3(0.028426, 0.078187, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u325 = mU(u325, m327);
    }
    {
      vec3 q328 = q324 - vec3(0.0, 0.0, 0.095);
      M m329 = M(length(q328) - 0.07, vec3(0.323143, 0.323143, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u325 = mU(u325, m329);
    }
    u0 = mU(u0, u325);
  }
  if (cullVis(5)) {
    vec3 q330 = p - vec3(-1.6, 0.225, 2.85);
    M m331 = M(sdBox(q330, vec3(0.7, 0.225, 0.2)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m331);
  }
  return u0;
}
