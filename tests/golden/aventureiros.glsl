
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

float sdLoft12(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.929717, -0.052277, 0.364546)) - 0.138186), dot(p, vec3(0.929721, -0.078085, -0.359892)) - 0.12838), dot(p, vec3(0.930634, -0.053545, 0.362012)) - 0.137861), dot(p, vec3(0.930693, -0.079232, -0.357117)) - 0.12811), dot(p, vec3(0.401959, -0.032603, 0.915077)) - 0.10142), dot(p, vec3(0.404716, -0.033903, 0.913814)) - 0.101252), dot(p, vec3(-0.401959, -0.032603, 0.915077)) - 0.029068), dot(p, vec3(-0.929717, -0.052277, 0.364546)) - -0.029163), dot(p, vec3(-0.404716, -0.033903, 0.913814)) - 0.028403), dot(p, vec3(-0.929721, -0.078085, -0.359892)) - -0.03897), dot(p, vec3(-0.930634, -0.053545, 0.362012)) - -0.029653), dot(p, vec3(-0.930693, -0.079232, -0.357117)) - -0.039415), dot(p, vec3(-0.401961, -0.097708, -0.910429)) - 0.004328), dot(p, vec3(-0.404783, -0.09894, -0.909044)) - 0.003685), dot(p, vec3(0.401961, -0.097708, -0.910429)) - 0.076681), dot(p, vec3(0.404783, -0.09894, -0.909044)) - 0.076546), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.931378, -0.04035, 0.361811)) - 0.141145), dot(p, vec3(0.931329, -0.067967, -0.357781)) - 0.130912), dot(p, vec3(0.933963, -0.043833, 0.354672)) - 0.140687), dot(p, vec3(0.933963, -0.070946, -0.350257)) - 0.130656), dot(p, vec3(0.405182, -0.014038, 0.914128)) - 0.106142), dot(p, vec3(0.413045, -0.0176, 0.910541)) - 0.106168), dot(p, vec3(-0.405182, -0.014038, 0.914128)) - 0.033209), dot(p, vec3(-0.931378, -0.04035, 0.361811)) - -0.026503), dot(p, vec3(-0.413045, -0.0176, 0.910541)) - 0.03182), dot(p, vec3(-0.931329, -0.067967, -0.357781)) - -0.036728), dot(p, vec3(-0.933963, -0.043833, 0.354672)) - -0.027426), dot(p, vec3(-0.933963, -0.070946, -0.350257)) - -0.037458), dot(p, vec3(-0.405132, -0.084132, -0.910379)) - 0.00726), dot(p, vec3(-0.413046, -0.087426, -0.906504)) - 0.005969), dot(p, vec3(0.405132, -0.084132, -0.910379)) - 0.080183), dot(p, vec3(0.413046, -0.087426, -0.906504)) - 0.080317), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull15(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(0.0, -0.768783, -0.63951)) - 0.056166);
  d = max(d, dot(p, vec3(0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, -0.904876, 0.425675)) - 0.058669);
  d = max(d, dot(p, vec3(0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(-0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(-0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(0.0, 0.729865, -0.683591)) - 0.164036);
  d = max(d, dot(p, vec3(0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(-0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(-0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(-0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(-0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(-0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(-0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(-0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(-0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(0.0, 0.480799, 0.876831)) - 0.174464);
  d = max(d, dot(p, vec3(0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(-0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(-0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(-0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(-0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(-0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959305, 0.282373)) - 0.15796);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft17(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.929717, -0.052277, 0.364546)) - -0.029163), dot(p, vec3(0.929721, -0.078085, -0.359892)) - -0.03897), dot(p, vec3(0.930634, -0.053545, 0.362012)) - -0.029653), dot(p, vec3(0.930693, -0.079232, -0.357117)) - -0.039415), dot(p, vec3(0.401959, -0.032603, 0.915077)) - 0.029068), dot(p, vec3(0.404716, -0.033903, 0.913814)) - 0.028403), dot(p, vec3(-0.401959, -0.032603, 0.915077)) - 0.10142), dot(p, vec3(-0.929717, -0.052277, 0.364546)) - 0.138186), dot(p, vec3(-0.404716, -0.033903, 0.913814)) - 0.101252), dot(p, vec3(-0.929721, -0.078085, -0.359892)) - 0.12838), dot(p, vec3(-0.930634, -0.053545, 0.362012)) - 0.137861), dot(p, vec3(-0.930693, -0.079232, -0.357117)) - 0.12811), dot(p, vec3(-0.401961, -0.097708, -0.910429)) - 0.076681), dot(p, vec3(-0.404783, -0.09894, -0.909044)) - 0.076546), dot(p, vec3(0.401961, -0.097708, -0.910429)) - 0.004328), dot(p, vec3(0.404783, -0.09894, -0.909044)) - 0.003685), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.931378, -0.04035, 0.361811)) - -0.026503), dot(p, vec3(0.931329, -0.067967, -0.357781)) - -0.036728), dot(p, vec3(0.933963, -0.043833, 0.354672)) - -0.027426), dot(p, vec3(0.933963, -0.070946, -0.350257)) - -0.037458), dot(p, vec3(0.405182, -0.014038, 0.914128)) - 0.033209), dot(p, vec3(0.413045, -0.0176, 0.910541)) - 0.03182), dot(p, vec3(-0.405182, -0.014038, 0.914128)) - 0.106142), dot(p, vec3(-0.931378, -0.04035, 0.361811)) - 0.141145), dot(p, vec3(-0.413045, -0.0176, 0.910541)) - 0.106168), dot(p, vec3(-0.931329, -0.067967, -0.357781)) - 0.130912), dot(p, vec3(-0.933963, -0.043833, 0.354672)) - 0.140687), dot(p, vec3(-0.933963, -0.070946, -0.350257)) - 0.130656), dot(p, vec3(-0.405132, -0.084132, -0.910379)) - 0.080183), dot(p, vec3(-0.413046, -0.087426, -0.906504)) - 0.080317), dot(p, vec3(0.405132, -0.084132, -0.910379)) - 0.00726), dot(p, vec3(0.413046, -0.087426, -0.906504)) - 0.005969), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull20(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(0.0, -0.768783, -0.63951)) - 0.056166);
  d = max(d, dot(p, vec3(0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, -0.904876, 0.425675)) - 0.058669);
  d = max(d, dot(p, vec3(0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(-0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(-0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(0.0, 0.729865, -0.683591)) - 0.164036);
  d = max(d, dot(p, vec3(0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(-0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(-0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(-0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(-0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(-0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(-0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(-0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(-0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(0.0, 0.480799, 0.876831)) - 0.174464);
  d = max(d, dot(p, vec3(0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(-0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(-0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(-0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(-0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(-0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959305, 0.282373)) - 0.15796);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft22(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.34, dot(p, vec3(-0.894245, 0.141377, 0.424662)) - 0.217975), dot(p, vec3(-0.894245, 0.141377, -0.424662)) - 0.217975), dot(p, vec3(-0.898151, 0.149692, 0.413421)) - 0.221544), dot(p, vec3(-0.898151, 0.149692, -0.413421)) - 0.221544), dot(p, vec3(-0.443191, 0.093484, 0.891539)) - 0.168033), dot(p, vec3(-0.45384, 0.10454, 0.88493)) - 0.172924), dot(p, vec3(0.0, 0.079007, 0.996874)) - 0.150113), dot(p, vec3(0.443191, 0.093484, 0.891539)) - 0.168033), dot(p, vec3(0.894245, 0.141377, 0.424662)) - 0.217975), dot(p, vec3(0.45384, 0.10454, 0.88493)) - 0.172924), dot(p, vec3(0.894245, 0.141377, -0.424662)) - 0.217975), dot(p, vec3(0.898151, 0.149692, 0.413421)) - 0.221544), dot(p, vec3(0.898151, 0.149692, -0.413421)) - 0.221544), dot(p, vec3(0.443191, 0.093484, -0.891539)) - 0.168033), dot(p, vec3(0.45384, 0.10454, -0.88493)) - 0.172924), dot(p, vec3(0.0, 0.079007, -0.996874)) - 0.150113), dot(p, vec3(-0.443191, 0.093484, -0.891539)) - 0.168033), dot(p, vec3(-0.45384, 0.10454, -0.88493)) - 0.172924), dot(p, vec3(0.0, 1.0, 0.0)) - 0.46);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.46, dot(p, vec3(-0.852209, -0.34621, 0.392274)) - -0.014381), dot(p, vec3(-0.852209, -0.34621, -0.392274)) - -0.014381), dot(p, vec3(-0.442918, -0.240751, 0.863633)) - 0.011086), dot(p, vec3(-0.842999, -0.324356, 0.429121)) - -0.002996), dot(p, vec3(0.0, -0.175554, 0.98447)) - 0.0316), dot(p, vec3(-0.411347, -0.209813, 0.887002)) - 0.026326), dot(p, vec3(0.442918, -0.240751, 0.863633)) - 0.011086), dot(p, vec3(0.411347, -0.209813, 0.887002)) - 0.026326), dot(p, vec3(0.852209, -0.34621, 0.392274)) - -0.014381), dot(p, vec3(0.842999, -0.324356, 0.429121)) - -0.002996), dot(p, vec3(0.852209, -0.34621, -0.392274)) - -0.014381), dot(p, vec3(0.442918, -0.240751, -0.863633)) - 0.011086), dot(p, vec3(0.842999, -0.324356, -0.429121)) - -0.002996), dot(p, vec3(0.0, -0.175554, -0.98447)) - 0.0316), dot(p, vec3(0.411347, -0.209813, -0.887002)) - 0.026326), dot(p, vec3(-0.442918, -0.240751, -0.863633)) - 0.011086), dot(p, vec3(-0.411347, -0.209813, -0.887002)) - 0.026326), dot(p, vec3(-0.842999, -0.324356, -0.429121)) - -0.002996), dot(p, vec3(0.0, 1.0, 0.0)) - 0.62);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.62, dot(p, vec3(-0.772915, 0.497798, 0.393445)) - 0.49027), dot(p, vec3(-0.772915, 0.497798, -0.393445)) - 0.49027), dot(p, vec3(-0.774972, 0.506712, 0.377705)) - 0.49628), dot(p, vec3(-0.774972, 0.506712, -0.377705)) - 0.49628), dot(p, vec3(-0.388324, 0.384758, 0.837356)) - 0.386206), dot(p, vec3(-0.399875, 0.398161, 0.825571)) - 0.395672), dot(p, vec3(0.0, 0.34353, 0.939142)) - 0.346965), dot(p, vec3(0.388324, 0.384758, 0.837356)) - 0.386206), dot(p, vec3(0.772915, 0.497798, 0.393445)) - 0.49027), dot(p, vec3(0.399875, 0.398161, 0.825571)) - 0.395672), dot(p, vec3(0.772915, 0.497798, -0.393445)) - 0.49027), dot(p, vec3(0.774972, 0.506712, 0.377705)) - 0.49628), dot(p, vec3(0.774972, 0.506712, -0.377705)) - 0.49628), dot(p, vec3(0.388324, 0.384758, -0.837356)) - 0.386206), dot(p, vec3(0.399875, 0.398161, -0.825571)) - 0.395672), dot(p, vec3(0.0, 0.34353, -0.939142)) - 0.346965), dot(p, vec3(-0.388324, 0.384758, -0.837356)) - 0.386206), dot(p, vec3(-0.399875, 0.398161, -0.825571)) - 0.395672), dot(p, vec3(0.0, 1.0, 0.0)) - 0.75);
  r = min(r, d);
  return r;
}
float sdLoft24(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.39, dot(p, vec3(-0.902723, 0.073319, 0.423928)) - 0.195598), dot(p, vec3(-0.902723, 0.073319, -0.423928)) - 0.195598), dot(p, vec3(-0.903191, 0.075266, 0.422589)) - 0.196444), dot(p, vec3(-0.903191, 0.075266, -0.422589)) - 0.196444), dot(p, vec3(-0.44848, 0.053974, 0.892162)) - 0.155296), dot(p, vec3(-0.449736, 0.056517, 0.891372)) - 0.156416), dot(p, vec3(0.0, 0.047499, 0.998871)) - 0.140122), dot(p, vec3(0.44848, 0.053974, 0.892162)) - 0.155296), dot(p, vec3(0.902723, 0.073319, 0.423928)) - 0.195598), dot(p, vec3(0.449736, 0.056517, 0.891372)) - 0.156416), dot(p, vec3(0.902723, 0.073319, -0.423928)) - 0.195598), dot(p, vec3(0.903191, 0.075266, 0.422589)) - 0.196444), dot(p, vec3(0.903191, 0.075266, -0.422589)) - 0.196444), dot(p, vec3(0.44848, 0.053974, -0.892162)) - 0.155296), dot(p, vec3(0.449736, 0.056517, -0.891372)) - 0.156416), dot(p, vec3(0.0, 0.047499, -0.998871)) - 0.140122), dot(p, vec3(-0.44848, 0.053974, -0.892162)) - 0.155296), dot(p, vec3(-0.449736, 0.056517, -0.891372)) - 0.156416), dot(p, vec3(0.0, 1.0, 0.0)) - 0.45);
  r = min(r, d);
  return r;
}
float sdHull27(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.032332;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.032332);
  return d;
}
float sdHull30(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.152998;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.183848);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.10253);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.14);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.095459);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.13);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.152998);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.10253);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.095459);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.152998);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.183848);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.095459);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.13);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.152998);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.095459);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.152998);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.183848);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.10253);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.14);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.152998);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.10253);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.152998);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.183848);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.152998);
  return d;
}
float sdHull33(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.307692, 0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(-0.307692, 0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(0.307692, -0.230769, 0.923077)) - 0.018462);
  d = max(d, dot(p, vec3(-0.307692, -0.230769, 0.923077)) - 0.018462);
  return d;
}
float sdHull36(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.939329, 0.156555, 0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(0.939329, 0.156555, -0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(0.580537, 0.156555, 0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 0.156555, 0.987669)) - 0.197259);
  d = max(d, dot(p, vec3(-0.580537, 0.156555, 0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(-0.939329, 0.156555, 0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(-0.939329, 0.156555, -0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(-0.580537, 0.156555, -0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 0.156555, -0.987669)) - 0.197259);
  d = max(d, dot(p, vec3(0.580537, 0.156555, -0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull40(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.095811;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.094277);
  return d;
}
float sdLoft43(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.173494, 0.983135, -0.057831)) - 0.643086, dot(p, vec3(0.652424, 0.05028, -0.756185)) - 0.262095), dot(p, vec3(-0.061309, -0.089489, -0.994099)) - -0.021313), dot(p, vec3(0.254729, -0.081089, -0.963607)) - 0.071139), dot(p, vec3(0.985961, 0.149359, -0.07465)) - 0.418171), dot(p, vec3(0.857724, 0.051897, -0.511485)) - 0.321017), dot(p, vec3(0.743965, 0.149447, 0.651293)) - 0.355313), dot(p, vec3(0.962926, 0.114672, 0.244179)) - 0.392321), dot(p, vec3(0.068272, 0.050032, 0.996411)) - 0.110042), dot(p, vec3(0.508603, 0.069793, 0.858168)) - 0.242785), dot(p, vec3(-0.645336, -0.090385, 0.758532)) - -0.173789), dot(p, vec3(-0.234753, -0.055833, 0.97045)) - -0.038436), dot(p, vec3(-0.978939, -0.189079, 0.076986)) - -0.329611), dot(p, vec3(-0.832611, -0.187923, 0.521002)) - -0.286362), dot(p, vec3(-0.737068, -0.188519, -0.648993)) - -0.266332), dot(p, vec3(-0.940605, -0.250167, -0.229517)) - -0.358022), dot(p, vec3(-0.491403, -0.20618, -0.846175)) - -0.210431), dot(p, vec3(0.131519, -0.986394, 0.098639)) - -0.483662);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.131519, 0.986394, -0.098639)) - 0.483662, dot(p, vec3(0.864968, -0.031835, -0.500816)) - 0.27862), dot(p, vec3(0.262782, -0.148042, -0.95343)) - 0.037913), dot(p, vec3(0.661527, -0.139168, -0.736895)) - 0.163982), dot(p, vec3(0.965017, 0.08975, 0.246349)) - 0.379677), dot(p, vec3(0.997891, -0.010605, -0.064039)) - 0.3365), dot(p, vec3(0.500125, 0.146674, 0.853441)) - 0.281197), dot(p, vec3(0.753115, 0.078598, 0.653176)) - 0.320257), dot(p, vec3(-0.257763, 0.105226, 0.960461)) - 0.040467), dot(p, vec3(0.070773, 0.077167, 0.994503)) - 0.125217), dot(p, vec3(-0.862045, -0.010901, 0.506714)) - -0.200883), dot(p, vec3(-0.649456, -0.014563, 0.76026)) - -0.134572), dot(p, vec3(-0.960857, -0.134209, -0.242365)) - -0.302322), dot(p, vec3(-0.985695, -0.143871, 0.087783)) - -0.307342), dot(p, vec3(-0.493779, -0.191204, -0.848306)) - -0.203168), dot(p, vec3(-0.741079, -0.234436, -0.629159)) - -0.291688), dot(p, vec3(-0.05886, -0.232261, -0.970871)) - -0.096396), dot(p, vec3(0.07581, -0.985527, 0.15162)) - -0.366919);
  r = min(r, d);
  return r;
}
float sdHull46(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.049075;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.049075);
  return d;
}
float sdLoft48(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(0.569803, -0.683763, -0.455842)) - -0.11624, dot(p, vec3(0.760611, 0.417538, 0.497124)) - 0.391787), dot(p, vec3(0.228338, -0.309901, 0.922942)) - 0.035874), dot(p, vec3(0.487424, 0.781258, -0.389939)) - 0.382329), dot(p, vec3(-0.318036, 0.417538, -0.851184)) - 0.016958), dot(p, vec3(-0.850309, -0.309901, -0.425366)) - -0.338956), dot(p, vec3(-0.577122, -0.673621, 0.461697)) - -0.329497), dot(p, vec3(-0.569803, 0.683763, 0.455842)) - 0.160115);
  r = min(r, d);
  return r;
}
float sdHull52(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.095811;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.094277);
  return d;
}
float sdLoft55(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.173494, 0.983135, -0.057831)) - 0.643086, dot(p, vec3(-0.068272, 0.050032, 0.996411)) - 0.110042), dot(p, vec3(0.645336, -0.090385, 0.758532)) - -0.173789), dot(p, vec3(0.234753, -0.055833, 0.97045)) - -0.038436), dot(p, vec3(-0.743965, 0.149447, 0.651293)) - 0.355313), dot(p, vec3(-0.508603, 0.069793, 0.858168)) - 0.242785), dot(p, vec3(-0.985961, 0.149359, -0.07465)) - 0.418171), dot(p, vec3(-0.962926, 0.114672, 0.244179)) - 0.392321), dot(p, vec3(-0.652424, 0.05028, -0.756185)) - 0.262095), dot(p, vec3(-0.857724, 0.051897, -0.511485)) - 0.321017), dot(p, vec3(0.061309, -0.089489, -0.994099)) - -0.021313), dot(p, vec3(-0.254729, -0.081089, -0.963607)) - 0.071139), dot(p, vec3(0.737068, -0.188519, -0.648993)) - -0.266332), dot(p, vec3(0.491403, -0.20618, -0.846175)) - -0.210431), dot(p, vec3(0.978939, -0.189079, 0.076986)) - -0.329611), dot(p, vec3(0.940605, -0.250167, -0.229517)) - -0.358022), dot(p, vec3(0.832611, -0.187923, 0.521002)) - -0.286362), dot(p, vec3(-0.131519, -0.986394, 0.098639)) - -0.483662);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.131519, 0.986394, -0.098639)) - 0.483662, dot(p, vec3(0.257763, 0.105226, 0.960461)) - 0.040467), dot(p, vec3(0.862045, -0.010901, 0.506714)) - -0.200883), dot(p, vec3(0.649456, -0.014563, 0.76026)) - -0.134572), dot(p, vec3(-0.500125, 0.146674, 0.853441)) - 0.281197), dot(p, vec3(-0.070773, 0.077167, 0.994503)) - 0.125217), dot(p, vec3(-0.965017, 0.08975, 0.246349)) - 0.379677), dot(p, vec3(-0.753115, 0.078598, 0.653176)) - 0.320257), dot(p, vec3(-0.864968, -0.031835, -0.500816)) - 0.27862), dot(p, vec3(-0.997891, -0.010605, -0.064039)) - 0.3365), dot(p, vec3(-0.262782, -0.148042, -0.95343)) - 0.037913), dot(p, vec3(-0.661527, -0.139168, -0.736895)) - 0.163982), dot(p, vec3(0.493779, -0.191204, -0.848306)) - -0.203168), dot(p, vec3(0.05886, -0.232261, -0.970871)) - -0.096396), dot(p, vec3(0.960857, -0.134209, -0.242365)) - -0.302322), dot(p, vec3(0.741079, -0.234436, -0.629159)) - -0.291688), dot(p, vec3(0.985695, -0.143871, 0.087783)) - -0.307342), dot(p, vec3(-0.07581, -0.985527, 0.15162)) - -0.366919);
  r = min(r, d);
  return r;
}
float sdHull58(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.049075;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.049075);
  return d;
}
float sdLoft60(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(-0.569803, -0.683763, -0.455842)) - -0.11624, dot(p, vec3(0.318036, 0.417538, -0.851184)) - 0.016958), dot(p, vec3(0.850309, -0.309901, -0.425366)) - -0.338956), dot(p, vec3(-0.487424, 0.781258, -0.389939)) - 0.382329), dot(p, vec3(-0.760611, 0.417538, 0.497124)) - 0.391787), dot(p, vec3(-0.228338, -0.309901, 0.922942)) - 0.035874), dot(p, vec3(0.577122, -0.673621, 0.461697)) - -0.329497), dot(p, vec3(0.569803, 0.683763, 0.455842)) - 0.160115);
  r = min(r, d);
  return r;
}
float sdHull63(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.207846;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.207846);
  return d;
}
float sdHull68(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.033282;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.032105);
  return d;
}
float sdHull72(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.928477, 0.371391)) - 0.0);
  d = max(d, dot(p, vec3(-0.747392, 0.46979, 0.46979)) - 0.016443);
  d = max(d, dot(p, vec3(0.747392, 0.46979, 0.46979)) - 0.016443);
  return d;
}
float sdHull76(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.021651;
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.021651);
  return d;
}
float sdHull81(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.024249;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.024249);
  return d;
}
float sdHull84(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.020496;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.020496);
  return d;
}
float sdHull87(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.562805, -0.82659, 0.0)) - 0.11882);
  d = max(d, dot(p, vec3(0.0, -0.82224, -0.569141)) - 0.109234);
  d = max(d, dot(p, vec3(0.572673, -0.602129, -0.556315)) - 0.227675);
  d = max(d, dot(p, vec3(0.0, -0.82224, 0.569141)) - 0.109234);
  d = max(d, dot(p, vec3(0.572673, -0.602129, 0.556315)) - 0.227675);
  d = max(d, dot(p, vec3(-0.562805, -0.82659, 0.0)) - 0.11882);
  d = max(d, dot(p, vec3(-0.572673, -0.602129, 0.556315)) - 0.227675);
  d = max(d, dot(p, vec3(-0.572673, -0.602129, -0.556315)) - 0.227675);
  d = max(d, dot(p, vec3(0.0, 0.073331, -0.997308)) - 0.199462);
  d = max(d, dot(p, vec3(0.694586, 0.110806, -0.710826)) - 0.287818);
  d = max(d, dot(p, vec3(0.0, 0.298061, -0.954547)) - 0.239201);
  d = max(d, dot(p, vec3(0.674123, 0.28113, -0.683025)) - 0.314861);
  d = max(d, dot(p, vec3(0.695496, 0.110723, -0.709947)) - 0.287833);
  d = max(d, dot(p, vec3(-0.694586, 0.110806, -0.710826)) - 0.287818);
  d = max(d, dot(p, vec3(-0.695496, 0.110723, -0.709947)) - 0.287833);
  d = max(d, dot(p, vec3(-0.674123, 0.28113, -0.683025)) - 0.314861);
  d = max(d, dot(p, vec3(-0.996745, 0.080619, 0.0)) - 0.219284);
  d = max(d, dot(p, vec3(-0.936878, 0.349657, 0.0)) - 0.264038);
  d = max(d, dot(p, vec3(-0.695496, 0.110723, 0.709947)) - 0.287833);
  d = max(d, dot(p, vec3(-0.694586, 0.110806, 0.710826)) - 0.287818);
  d = max(d, dot(p, vec3(-0.674123, 0.28113, 0.683025)) - 0.314861);
  d = max(d, dot(p, vec3(-0.6841, 0.318368, 0.656239)) - 0.320109);
  d = max(d, dot(p, vec3(-0.6841, 0.318368, -0.656239)) - 0.320109);
  d = max(d, dot(p, vec3(0.996745, 0.080619, 0.0)) - 0.219284);
  d = max(d, dot(p, vec3(0.936878, 0.349657, 0.0)) - 0.264038);
  d = max(d, dot(p, vec3(0.6841, 0.318368, -0.656239)) - 0.320109);
  d = max(d, dot(p, vec3(0.695496, 0.110723, 0.709947)) - 0.287833);
  d = max(d, dot(p, vec3(0.694586, 0.110806, 0.710826)) - 0.287818);
  d = max(d, dot(p, vec3(0.674123, 0.28113, 0.683025)) - 0.314861);
  d = max(d, dot(p, vec3(0.6841, 0.318368, 0.656239)) - 0.320109);
  d = max(d, dot(p, vec3(0.0, 0.073331, 0.997308)) - 0.199462);
  d = max(d, dot(p, vec3(0.0, 0.298061, 0.954547)) - 0.239201);
  d = max(d, dot(p, vec3(0.0, 0.615644, -0.788024)) - 0.278961);
  d = max(d, dot(p, vec3(0.421604, 0.783231, -0.456945)) - 0.336257);
  d = max(d, dot(p, vec3(0.0, 0.927466, -0.373907)) - 0.332527);
  d = max(d, dot(p, vec3(0.359551, 0.847474, -0.390526)) - 0.343413);
  d = max(d, dot(p, vec3(0.441531, 0.782927, -0.438264)) - 0.3366);
  d = max(d, dot(p, vec3(-0.421604, 0.783231, -0.456945)) - 0.336257);
  d = max(d, dot(p, vec3(-0.441531, 0.782927, -0.438264)) - 0.3366);
  d = max(d, dot(p, vec3(-0.359551, 0.847474, -0.390526)) - 0.343413);
  d = max(d, dot(p, vec3(-0.726698, 0.686957, 0.0)) - 0.296566);
  d = max(d, dot(p, vec3(-0.348065, 0.937471, 0.0)) - 0.33377);
  d = max(d, dot(p, vec3(-0.441531, 0.782927, 0.438264)) - 0.3366);
  d = max(d, dot(p, vec3(-0.421604, 0.783231, 0.456945)) - 0.336257);
  d = max(d, dot(p, vec3(-0.359551, 0.847474, 0.390526)) - 0.343413);
  d = max(d, dot(p, vec3(0.726698, 0.686957, 0.0)) - 0.296566);
  d = max(d, dot(p, vec3(0.441531, 0.782927, 0.438264)) - 0.3366);
  d = max(d, dot(p, vec3(0.348065, 0.937471, 0.0)) - 0.33377);
  d = max(d, dot(p, vec3(0.421604, 0.783231, 0.456945)) - 0.336257);
  d = max(d, dot(p, vec3(0.359551, 0.847474, 0.390526)) - 0.343413);
  d = max(d, dot(p, vec3(0.0, 0.615644, 0.788024)) - 0.278961);
  d = max(d, dot(p, vec3(0.0, 0.927466, 0.373907)) - 0.332527);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.32);
  return d;
}
float sdHull92(vec3 p) {
  float d = dot(p, vec3(0.894427, -0.447214, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(-0.894427, -0.447214, 0.0)) - 0.0);
  d = max(d, dot(p, vec3(0.97824, 0.115087, -0.172631)) - 0.024168);
  d = max(d, dot(p, vec3(-0.97824, 0.115087, -0.172631)) - 0.024168);
  d = max(d, dot(p, vec3(0.857143, 0.428571, 0.285714)) - 0.034286);
  d = max(d, dot(p, vec3(-0.857143, 0.428571, 0.285714)) - 0.034286);
  return d;
}
float sdHull98(vec3 p) {
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
float sdHull102(vec3 p) {
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
float sdHull105(vec3 p) {
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
float sdHull111(vec3 p) {
  float d = dot(p, vec3(0.0, 1.0, 0.0)) - 0.22;
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.0);
  d = max(d, dot(p, vec3(-0.997785, -0.066519, 0.0)) - 0.184923);
  d = max(d, dot(p, vec3(0.997785, -0.066519, 0.0)) - 0.184923);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.04);
  d = max(d, dot(p, vec3(-0.773957, -0.633238, 0.0)) - 0.189971);
  d = max(d, dot(p, vec3(0.773957, -0.633238, 0.0)) - 0.189971);
  return d;
}
float sdHull114(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.379747, 0.265823, 0.886076)) - 0.026582);
  d = max(d, dot(p, vec3(-0.379747, 0.265823, 0.886076)) - 0.026582);
  d = max(d, dot(p, vec3(0.379747, -0.265823, 0.886076)) - 0.026582);
  d = max(d, dot(p, vec3(-0.379747, -0.265823, 0.886076)) - 0.026582);
  return d;
}
float sdLoft127(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.905923, -0.060109, 0.419156)) - 0.158887), dot(p, vec3(0.905928, -0.089783, -0.413805)) - 0.147612), dot(p, vec3(0.907105, -0.061585, 0.416374)) - 0.158563), dot(p, vec3(0.907181, -0.091132, -0.410753)) - 0.14735), dot(p, vec3(0.348673, -0.033372, 0.93665)) - 0.103811), dot(p, vec3(0.351181, -0.034713, 0.935664)) - 0.103673), dot(p, vec3(-0.348673, -0.033372, 0.93665)) - 0.029753), dot(p, vec3(-0.905923, -0.060109, 0.419156)) - -0.033531), dot(p, vec3(-0.351181, -0.034713, 0.935664)) - 0.029082), dot(p, vec3(-0.905928, -0.089783, -0.413805)) - -0.044807), dot(p, vec3(-0.907105, -0.061585, 0.416374)) - -0.034106), dot(p, vec3(-0.907181, -0.091132, -0.410753)) - -0.045335), dot(p, vec3(-0.348676, -0.100011, -0.931892)) - 0.00443), dot(p, vec3(-0.351241, -0.101307, -0.930788)) - 0.003773), dot(p, vec3(0.348676, -0.100011, -0.931892)) - 0.078489), dot(p, vec3(0.351241, -0.101307, -0.930788)) - 0.078377), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.908064, -0.046422, 0.416251)) - 0.162383), dot(p, vec3(0.908001, -0.078192, -0.411606)) - 0.150606), dot(p, vec3(0.911404, -0.050474, 0.408405)) - 0.162001), dot(p, vec3(0.911404, -0.081694, -0.403321)) - 0.15045), dot(p, vec3(0.351604, -0.014374, 0.936038)) - 0.108686), dot(p, vec3(0.358769, -0.018039, 0.933252)) - 0.108817), dot(p, vec3(-0.351604, -0.014374, 0.936038)) - 0.034005), dot(p, vec3(-0.908064, -0.046422, 0.416251)) - -0.03049), dot(p, vec3(-0.358769, -0.018039, 0.933252)) - 0.032614), dot(p, vec3(-0.908001, -0.078192, -0.411606)) - -0.042253), dot(p, vec3(-0.911404, -0.050474, 0.408405)) - -0.031581), dot(p, vec3(-0.911404, -0.081694, -0.403321)) - -0.043132), dot(p, vec3(-0.351559, -0.086148, -0.932194)) - 0.007434), dot(p, vec3(-0.35877, -0.089606, -0.929115)) - 0.006118), dot(p, vec3(0.351559, -0.086148, -0.932194)) - 0.082105), dot(p, vec3(0.35877, -0.089606, -0.929115)) - 0.082321), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull130(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.598297, -0.801275, 0.0)) - 0.057728);
  d = max(d, dot(p, vec3(0.0, -0.78218, -0.623052)) - 0.055183);
  d = max(d, dot(p, vec3(0.586606, -0.561243, -0.583866)) - 0.108313);
  d = max(d, dot(p, vec3(0.691953, -0.721915, -0.006262)) - 0.06732);
  d = max(d, dot(p, vec3(0.0, -0.916382, 0.400305)) - 0.05547);
  d = max(d, dot(p, vec3(0.583461, -0.647113, 0.490732)) - 0.124297);
  d = max(d, dot(p, vec3(-0.598297, -0.801275, 0.0)) - 0.057728);
  d = max(d, dot(p, vec3(-0.583461, -0.647113, 0.490732)) - 0.124297);
  d = max(d, dot(p, vec3(-0.586606, -0.561243, -0.583866)) - 0.108313);
  d = max(d, dot(p, vec3(-0.691953, -0.721915, -0.006262)) - 0.06732);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.701658, 0.101024, -0.705316)) - 0.136924);
  d = max(d, dot(p, vec3(0.0, 0.729808, -0.683652)) - 0.164669);
  d = max(d, dot(p, vec3(0.563133, 0.603373, -0.564644)) - 0.183274);
  d = max(d, dot(p, vec3(0.702997, 0.100792, -0.704014)) - 0.136918);
  d = max(d, dot(p, vec3(-0.701658, 0.101024, -0.705316)) - 0.136924);
  d = max(d, dot(p, vec3(-0.702997, 0.100792, -0.704014)) - 0.136918);
  d = max(d, dot(p, vec3(-0.563133, 0.603373, -0.564644)) - 0.183274);
  d = max(d, dot(p, vec3(-0.997503, 0.070623, 0.0)) - 0.105935);
  d = max(d, dot(p, vec3(-0.786818, 0.617067, 0.012108)) - 0.161604);
  d = max(d, dot(p, vec3(-0.994342, 0.097667, 0.041771)) - 0.111496);
  d = max(d, dot(p, vec3(-0.682036, 0.731199, 0.013236)) - 0.167492);
  d = max(d, dot(p, vec3(-0.597614, 0.801784, 0.0)) - 0.170335);
  d = max(d, dot(p, vec3(-0.639659, -0.527728, 0.558874)) - 0.140374);
  d = max(d, dot(p, vec3(-0.990679, 0.114015, 0.074533)) - 0.1157);
  d = max(d, dot(p, vec3(0.997503, 0.070623, 0.0)) - 0.105935);
  d = max(d, dot(p, vec3(0.786818, 0.617067, 0.012108)) - 0.161604);
  d = max(d, dot(p, vec3(0.682036, 0.731199, 0.013236)) - 0.167492);
  d = max(d, dot(p, vec3(0.597614, 0.801784, 0.0)) - 0.170335);
  d = max(d, dot(p, vec3(0.994342, 0.097667, 0.041771)) - 0.111496);
  d = max(d, dot(p, vec3(0.639659, -0.527728, 0.558874)) - 0.140374);
  d = max(d, dot(p, vec3(0.990679, 0.114015, 0.074533)) - 0.1157);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.41077, 0.010876, 0.911674)) - 0.175274);
  d = max(d, dot(p, vec3(0.0, 0.487933, 0.872881)) - 0.174886);
  d = max(d, dot(p, vec3(0.57918, 0.128976, 0.804932)) - 0.179);
  d = max(d, dot(p, vec3(0.491448, 0.379213, 0.784013)) - 0.187828);
  d = max(d, dot(p, vec3(-0.41077, 0.010876, 0.911674)) - 0.175274);
  d = max(d, dot(p, vec3(-0.57918, 0.128976, 0.804932)) - 0.179);
  d = max(d, dot(p, vec3(-0.491448, 0.379213, 0.784013)) - 0.187828);
  d = max(d, dot(p, vec3(-0.942427, 0.218578, 0.25309)) - 0.138049);
  d = max(d, dot(p, vec3(-0.501639, 0.657344, 0.562368)) - 0.178342);
  d = max(d, dot(p, vec3(-0.395918, 0.875703, 0.276393)) - 0.178549);
  d = max(d, dot(p, vec3(-0.267053, 0.774412, 0.573558)) - 0.172932);
  d = max(d, dot(p, vec3(0.942427, 0.218578, 0.25309)) - 0.138049);
  d = max(d, dot(p, vec3(0.501639, 0.657344, 0.562368)) - 0.178342);
  d = max(d, dot(p, vec3(0.395918, 0.875703, 0.276393)) - 0.178549);
  d = max(d, dot(p, vec3(0.267053, 0.774412, 0.573558)) - 0.172932);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.960004, 0.279986)) - 0.158207);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft132(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.905923, -0.060109, 0.419156)) - -0.033531), dot(p, vec3(0.905928, -0.089783, -0.413805)) - -0.044807), dot(p, vec3(0.907105, -0.061585, 0.416374)) - -0.034106), dot(p, vec3(0.907181, -0.091132, -0.410753)) - -0.045335), dot(p, vec3(0.348673, -0.033372, 0.93665)) - 0.029753), dot(p, vec3(0.351181, -0.034713, 0.935664)) - 0.029082), dot(p, vec3(-0.348673, -0.033372, 0.93665)) - 0.103811), dot(p, vec3(-0.905923, -0.060109, 0.419156)) - 0.158887), dot(p, vec3(-0.351181, -0.034713, 0.935664)) - 0.103673), dot(p, vec3(-0.905928, -0.089783, -0.413805)) - 0.147612), dot(p, vec3(-0.907105, -0.061585, 0.416374)) - 0.158563), dot(p, vec3(-0.907181, -0.091132, -0.410753)) - 0.14735), dot(p, vec3(-0.348676, -0.100011, -0.931892)) - 0.078489), dot(p, vec3(-0.351241, -0.101307, -0.930788)) - 0.078377), dot(p, vec3(0.348676, -0.100011, -0.931892)) - 0.00443), dot(p, vec3(0.351241, -0.101307, -0.930788)) - 0.003773), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.908064, -0.046422, 0.416251)) - -0.03049), dot(p, vec3(0.908001, -0.078192, -0.411606)) - -0.042253), dot(p, vec3(0.911404, -0.050474, 0.408405)) - -0.031581), dot(p, vec3(0.911404, -0.081694, -0.403321)) - -0.043132), dot(p, vec3(0.351604, -0.014374, 0.936038)) - 0.034005), dot(p, vec3(0.358769, -0.018039, 0.933252)) - 0.032614), dot(p, vec3(-0.351604, -0.014374, 0.936038)) - 0.108686), dot(p, vec3(-0.908064, -0.046422, 0.416251)) - 0.162383), dot(p, vec3(-0.358769, -0.018039, 0.933252)) - 0.108817), dot(p, vec3(-0.908001, -0.078192, -0.411606)) - 0.150606), dot(p, vec3(-0.911404, -0.050474, 0.408405)) - 0.162001), dot(p, vec3(-0.911404, -0.081694, -0.403321)) - 0.15045), dot(p, vec3(-0.351559, -0.086148, -0.932194)) - 0.082105), dot(p, vec3(-0.35877, -0.089606, -0.929115)) - 0.082321), dot(p, vec3(0.351559, -0.086148, -0.932194)) - 0.007434), dot(p, vec3(0.35877, -0.089606, -0.929115)) - 0.006118), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull135(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.598297, -0.801275, 0.0)) - 0.057728);
  d = max(d, dot(p, vec3(0.0, -0.78218, -0.623052)) - 0.055183);
  d = max(d, dot(p, vec3(0.586606, -0.561243, -0.583866)) - 0.108313);
  d = max(d, dot(p, vec3(0.691953, -0.721915, -0.006262)) - 0.06732);
  d = max(d, dot(p, vec3(0.0, -0.916382, 0.400305)) - 0.05547);
  d = max(d, dot(p, vec3(0.583461, -0.647113, 0.490732)) - 0.124297);
  d = max(d, dot(p, vec3(-0.598297, -0.801275, 0.0)) - 0.057728);
  d = max(d, dot(p, vec3(-0.583461, -0.647113, 0.490732)) - 0.124297);
  d = max(d, dot(p, vec3(-0.586606, -0.561243, -0.583866)) - 0.108313);
  d = max(d, dot(p, vec3(-0.691953, -0.721915, -0.006262)) - 0.06732);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.701658, 0.101024, -0.705316)) - 0.136924);
  d = max(d, dot(p, vec3(0.0, 0.729808, -0.683652)) - 0.164669);
  d = max(d, dot(p, vec3(0.563133, 0.603373, -0.564644)) - 0.183274);
  d = max(d, dot(p, vec3(0.702997, 0.100792, -0.704014)) - 0.136918);
  d = max(d, dot(p, vec3(-0.701658, 0.101024, -0.705316)) - 0.136924);
  d = max(d, dot(p, vec3(-0.702997, 0.100792, -0.704014)) - 0.136918);
  d = max(d, dot(p, vec3(-0.563133, 0.603373, -0.564644)) - 0.183274);
  d = max(d, dot(p, vec3(-0.997503, 0.070623, 0.0)) - 0.105935);
  d = max(d, dot(p, vec3(-0.786818, 0.617067, 0.012108)) - 0.161604);
  d = max(d, dot(p, vec3(-0.994342, 0.097667, 0.041771)) - 0.111496);
  d = max(d, dot(p, vec3(-0.682036, 0.731199, 0.013236)) - 0.167492);
  d = max(d, dot(p, vec3(-0.597614, 0.801784, 0.0)) - 0.170335);
  d = max(d, dot(p, vec3(-0.639659, -0.527728, 0.558874)) - 0.140374);
  d = max(d, dot(p, vec3(-0.990679, 0.114015, 0.074533)) - 0.1157);
  d = max(d, dot(p, vec3(0.997503, 0.070623, 0.0)) - 0.105935);
  d = max(d, dot(p, vec3(0.786818, 0.617067, 0.012108)) - 0.161604);
  d = max(d, dot(p, vec3(0.682036, 0.731199, 0.013236)) - 0.167492);
  d = max(d, dot(p, vec3(0.597614, 0.801784, 0.0)) - 0.170335);
  d = max(d, dot(p, vec3(0.994342, 0.097667, 0.041771)) - 0.111496);
  d = max(d, dot(p, vec3(0.639659, -0.527728, 0.558874)) - 0.140374);
  d = max(d, dot(p, vec3(0.990679, 0.114015, 0.074533)) - 0.1157);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.41077, 0.010876, 0.911674)) - 0.175274);
  d = max(d, dot(p, vec3(0.0, 0.487933, 0.872881)) - 0.174886);
  d = max(d, dot(p, vec3(0.57918, 0.128976, 0.804932)) - 0.179);
  d = max(d, dot(p, vec3(0.491448, 0.379213, 0.784013)) - 0.187828);
  d = max(d, dot(p, vec3(-0.41077, 0.010876, 0.911674)) - 0.175274);
  d = max(d, dot(p, vec3(-0.57918, 0.128976, 0.804932)) - 0.179);
  d = max(d, dot(p, vec3(-0.491448, 0.379213, 0.784013)) - 0.187828);
  d = max(d, dot(p, vec3(-0.942427, 0.218578, 0.25309)) - 0.138049);
  d = max(d, dot(p, vec3(-0.501639, 0.657344, 0.562368)) - 0.178342);
  d = max(d, dot(p, vec3(-0.395918, 0.875703, 0.276393)) - 0.178549);
  d = max(d, dot(p, vec3(-0.267053, 0.774412, 0.573558)) - 0.172932);
  d = max(d, dot(p, vec3(0.942427, 0.218578, 0.25309)) - 0.138049);
  d = max(d, dot(p, vec3(0.501639, 0.657344, 0.562368)) - 0.178342);
  d = max(d, dot(p, vec3(0.395918, 0.875703, 0.276393)) - 0.178549);
  d = max(d, dot(p, vec3(0.267053, 0.774412, 0.573558)) - 0.172932);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.960004, 0.279986)) - 0.158207);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft137(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.34, dot(p, vec3(-0.861043, 0.160631, 0.482496)) - 0.247661), dot(p, vec3(-0.861043, 0.160631, -0.482496)) - 0.247661), dot(p, vec3(-0.865907, 0.170295, 0.470324)) - 0.252037), dot(p, vec3(-0.865907, 0.170295, -0.470324)) - 0.252037), dot(p, vec3(-0.386433, 0.096184, 0.917288)) - 0.172886), dot(p, vec3(-0.396283, 0.107713, 0.911788)) - 0.178172), dot(p, vec3(0.0, 0.079007, 0.996874)) - 0.150113), dot(p, vec3(0.386433, 0.096184, 0.917288)) - 0.172886), dot(p, vec3(0.861043, 0.160631, 0.482496)) - 0.247661), dot(p, vec3(0.396283, 0.107713, 0.911788)) - 0.178172), dot(p, vec3(0.861043, 0.160631, -0.482496)) - 0.247661), dot(p, vec3(0.865907, 0.170295, 0.470324)) - 0.252037), dot(p, vec3(0.865907, 0.170295, -0.470324)) - 0.252037), dot(p, vec3(0.386433, 0.096184, -0.917288)) - 0.172886), dot(p, vec3(0.396283, 0.107713, -0.911788)) - 0.178172), dot(p, vec3(0.0, 0.079007, -0.996874)) - 0.150113), dot(p, vec3(-0.386433, 0.096184, -0.917288)) - 0.172886), dot(p, vec3(-0.396283, 0.107713, -0.911788)) - 0.178172), dot(p, vec3(0.0, 1.0, 0.0)) - 0.46);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.46, dot(p, vec3(-0.809824, -0.388209, 0.439862)) - -0.016126), dot(p, vec3(-0.809824, -0.388209, -0.439862)) - -0.016126), dot(p, vec3(-0.386181, -0.247696, 0.888544)) - 0.011406), dot(p, vec3(-0.798866, -0.362703, 0.479854)) - -0.00335), dot(p, vec3(0.0, -0.175554, 0.98447)) - 0.0316), dot(p, vec3(-0.357221, -0.215001, 0.908938)) - 0.026977), dot(p, vec3(0.386181, -0.247696, 0.888544)) - 0.011406), dot(p, vec3(0.357221, -0.215001, 0.908938)) - 0.026977), dot(p, vec3(0.809824, -0.388209, 0.439862)) - -0.016126), dot(p, vec3(0.798866, -0.362703, 0.479854)) - -0.00335), dot(p, vec3(0.809824, -0.388209, -0.439862)) - -0.016126), dot(p, vec3(0.386181, -0.247696, -0.888544)) - 0.011406), dot(p, vec3(0.798866, -0.362703, -0.479854)) - -0.00335), dot(p, vec3(0.0, -0.175554, -0.98447)) - 0.0316), dot(p, vec3(0.357221, -0.215001, -0.908938)) - 0.026977), dot(p, vec3(-0.386181, -0.247696, -0.888544)) - 0.011406), dot(p, vec3(-0.357221, -0.215001, -0.908938)) - 0.026977), dot(p, vec3(-0.798866, -0.362703, -0.479854)) - -0.00335), dot(p, vec3(0.0, 1.0, 0.0)) - 0.62);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.62, dot(p, vec3(-0.718259, 0.545864, 0.431435)) - 0.537609), dot(p, vec3(-0.718259, 0.545864, -0.431435)) - 0.537609), dot(p, vec3(-0.720559, 0.555939, 0.414399)) - 0.544493), dot(p, vec3(-0.720559, 0.555939, -0.414399)) - 0.544493), dot(p, vec3(-0.336312, 0.393204, 0.855737)) - 0.394683), dot(p, vec3(-0.346781, 0.407447, 0.844826)) - 0.4049), dot(p, vec3(0.0, 0.34353, 0.939142)) - 0.346965), dot(p, vec3(0.336312, 0.393204, 0.855737)) - 0.394683), dot(p, vec3(0.718259, 0.545864, 0.431435)) - 0.537609), dot(p, vec3(0.346781, 0.407447, 0.844826)) - 0.4049), dot(p, vec3(0.718259, 0.545864, -0.431435)) - 0.537609), dot(p, vec3(0.720559, 0.555939, 0.414399)) - 0.544493), dot(p, vec3(0.720559, 0.555939, -0.414399)) - 0.544493), dot(p, vec3(0.336312, 0.393204, -0.855737)) - 0.394683), dot(p, vec3(0.346781, 0.407447, -0.844826)) - 0.4049), dot(p, vec3(0.0, 0.34353, -0.939142)) - 0.346965), dot(p, vec3(-0.336312, 0.393204, -0.855737)) - 0.394683), dot(p, vec3(-0.346781, 0.407447, -0.844826)) - 0.4049), dot(p, vec3(0.0, 1.0, 0.0)) - 0.75);
  r = min(r, d);
  return r;
}
float sdLoft139(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.39, dot(p, vec3(-0.871625, 0.083536, 0.483003)) - 0.222855), dot(p, vec3(-0.871625, 0.083536, -0.483003)) - 0.222855), dot(p, vec3(-0.872211, 0.085767, 0.481551)) - 0.223853), dot(p, vec3(-0.872211, 0.085767, -0.481551)) - 0.223853), dot(p, vec3(-0.39132, 0.055572, 0.918575)) - 0.159894), dot(p, vec3(-0.392482, 0.0582, 0.917916)) - 0.161075), dot(p, vec3(0.0, 0.047499, 0.998871)) - 0.140122), dot(p, vec3(0.39132, 0.055572, 0.918575)) - 0.159894), dot(p, vec3(0.871625, 0.083536, 0.483003)) - 0.222855), dot(p, vec3(0.392482, 0.0582, 0.917916)) - 0.161075), dot(p, vec3(0.871625, 0.083536, -0.483003)) - 0.222855), dot(p, vec3(0.872211, 0.085767, 0.481551)) - 0.223853), dot(p, vec3(0.872211, 0.085767, -0.481551)) - 0.223853), dot(p, vec3(0.39132, 0.055572, -0.918575)) - 0.159894), dot(p, vec3(0.392482, 0.0582, -0.917916)) - 0.161075), dot(p, vec3(0.0, 0.047499, -0.998871)) - 0.140122), dot(p, vec3(-0.39132, 0.055572, -0.918575)) - 0.159894), dot(p, vec3(-0.392482, 0.0582, -0.917916)) - 0.161075), dot(p, vec3(0.0, 1.0, 0.0)) - 0.45);
  r = min(r, d);
  return r;
}
float sdHull142(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.032332;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.032332);
  return d;
}
float sdHull145(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.9157, 0.270131, 0.297529)) - 0.243118);
  d = max(d, dot(p, vec3(0.9157, 0.270131, -0.297529)) - 0.243118);
  d = max(d, dot(p, vec3(0.565933, 0.270131, 0.778941)) - 0.243118);
  d = max(d, dot(p, vec3(0.0, 0.270131, 0.962823)) - 0.243118);
  d = max(d, dot(p, vec3(-0.565933, 0.270131, 0.778941)) - 0.243118);
  d = max(d, dot(p, vec3(-0.9157, 0.270131, 0.297529)) - 0.243118);
  d = max(d, dot(p, vec3(-0.9157, 0.270131, -0.297529)) - 0.243118);
  d = max(d, dot(p, vec3(-0.565933, 0.270131, -0.778941)) - 0.243118);
  d = max(d, dot(p, vec3(0.0, 0.270131, -0.962823)) - 0.243118);
  d = max(d, dot(p, vec3(0.565933, 0.270131, -0.778941)) - 0.243118);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull148(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.514496, 0.857493)) - 0.0);
  d = max(d, dot(p, vec3(-0.394055, 0.472866, 0.78811)) - 0.047287);
  d = max(d, dot(p, vec3(0.394055, 0.472866, 0.78811)) - 0.047287);
  return d;
}
float sdHull152(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.113057;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.111246);
  return d;
}
float sdLoft155(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.203525, 0.97738, -0.057493)) - 0.621725, dot(p, vec3(0.615901, 0.056953, -0.785762)) - 0.296396), dot(p, vec3(-0.103812, -0.104648, -0.989076)) - -0.037532), dot(p, vec3(0.182675, -0.099807, -0.978094)) - 0.058676), dot(p, vec3(0.977686, 0.171473, -0.121358)) - 0.487556), dot(p, vec3(0.815281, 0.055557, -0.576394)) - 0.361534), dot(p, vec3(0.769651, 0.171649, 0.614958)) - 0.423855), dot(p, vec3(0.97686, 0.132669, 0.167759)) - 0.465103), dot(p, vec3(0.113802, 0.056666, 0.991886)) - 0.142151), dot(p, vec3(0.572314, 0.085457, 0.81557)) - 0.307952), dot(p, vec3(-0.60568, -0.105951, 0.788623)) - -0.19242), dot(p, vec3(-0.156533, -0.057877, 0.985975)) - -0.016008), dot(p, vec3(-0.967511, -0.220206, 0.124222)) - -0.383407), dot(p, vec3(-0.781997, -0.212154, 0.586064)) - -0.315935), dot(p, vec3(-0.759708, -0.219367, -0.612146)) - -0.319064), dot(p, vec3(-0.945556, -0.288332, -0.150956)) - -0.419468), dot(p, vec3(-0.548125, -0.242202, -0.80056)) - -0.265236), dot(p, vec3(0.154669, -0.983063, 0.098306)) - -0.467113);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.154669, 0.983063, -0.098306)) - 0.467113, dot(p, vec3(0.825041, -0.03666, -0.563882)) - 0.315784), dot(p, vec3(0.191131, -0.157275, -0.968883)) - 0.030997), dot(p, vec3(0.609797, -0.153624, -0.777527)) - 0.182132), dot(p, vec3(0.981101, 0.089372, 0.171622)) - 0.443494), dot(p, vec3(0.991174, -0.019998, -0.131054)) - 0.389982), dot(p, vec3(0.564344, 0.148717, 0.812034)) - 0.338916), dot(p, vec3(0.796603, 0.07161, 0.600247)) - 0.379672), dot(p, vec3(-0.183692, 0.106514, 0.977196)) - 0.062194), dot(p, vec3(0.140387, 0.069008, 0.987689)) - 0.157942), dot(p, vec3(-0.820646, -0.013314, 0.571282)) - -0.223397), dot(p, vec3(-0.593064, -0.026487, 0.80472)) - -0.145391), dot(p, vec3(-0.975757, -0.141542, -0.166925)) - -0.351744), dot(p, vec3(-0.974186, -0.160508, 0.158742)) - -0.353296), dot(p, vec3(-0.555821, -0.201671, -0.806469)) - -0.246315), dot(p, vec3(-0.779852, -0.254214, -0.57202)) - -0.343902), dot(p, vec3(-0.123894, -0.25122, -0.959968)) - -0.122119), dot(p, vec3(0.089355, -0.984418, 0.151449)) - -0.357592);
  r = min(r, d);
  return r;
}
float sdHull158(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.054271;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.059);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.059);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.054271);
  return d;
}
float sdLoft160(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(0.633238, -0.643971, -0.429314)) - -0.054725, dot(p, vec3(0.703458, 0.429225, 0.566491)) - 0.418685), dot(p, vec3(0.171905, -0.333718, 0.926866)) - 0.02143), dot(p, vec3(0.484595, 0.810697, -0.328539)) - 0.418586), dot(p, vec3(-0.26582, 0.429225, -0.863195)) - 0.021232), dot(p, vec3(-0.797373, -0.333718, -0.50282)) - -0.376023), dot(p, vec3(-0.57851, -0.71519, 0.39221)) - -0.375924), dot(p, vec3(-0.633238, 0.643971, 0.429314)) - 0.101311);
  r = min(r, d);
  return r;
}
float sdHull164(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.113057;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.113057);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.113057);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.111246);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.109441);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.109441);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.111246);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.111246);
  return d;
}
float sdLoft167(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.203525, 0.97738, -0.057493)) - 0.621725, dot(p, vec3(-0.113802, 0.056666, 0.991886)) - 0.142151), dot(p, vec3(0.60568, -0.105951, 0.788623)) - -0.19242), dot(p, vec3(0.156533, -0.057877, 0.985975)) - -0.016008), dot(p, vec3(-0.769651, 0.171649, 0.614958)) - 0.423855), dot(p, vec3(-0.572314, 0.085457, 0.81557)) - 0.307952), dot(p, vec3(-0.977686, 0.171473, -0.121358)) - 0.487556), dot(p, vec3(-0.97686, 0.132669, 0.167759)) - 0.465103), dot(p, vec3(-0.615901, 0.056953, -0.785762)) - 0.296396), dot(p, vec3(-0.815281, 0.055557, -0.576394)) - 0.361534), dot(p, vec3(0.103812, -0.104648, -0.989076)) - -0.037532), dot(p, vec3(-0.182675, -0.099807, -0.978094)) - 0.058676), dot(p, vec3(0.759708, -0.219367, -0.612146)) - -0.319064), dot(p, vec3(0.548125, -0.242202, -0.80056)) - -0.265236), dot(p, vec3(0.967511, -0.220206, 0.124222)) - -0.383407), dot(p, vec3(0.945556, -0.288332, -0.150956)) - -0.419468), dot(p, vec3(0.781997, -0.212154, 0.586064)) - -0.315935), dot(p, vec3(-0.154669, -0.983063, 0.098306)) - -0.467113);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.154669, 0.983063, -0.098306)) - 0.467113, dot(p, vec3(0.183692, 0.106514, 0.977196)) - 0.062194), dot(p, vec3(0.820646, -0.013314, 0.571282)) - -0.223397), dot(p, vec3(0.593064, -0.026487, 0.80472)) - -0.145391), dot(p, vec3(-0.564344, 0.148717, 0.812034)) - 0.338916), dot(p, vec3(-0.140387, 0.069008, 0.987689)) - 0.157942), dot(p, vec3(-0.981101, 0.089372, 0.171622)) - 0.443494), dot(p, vec3(-0.796603, 0.07161, 0.600247)) - 0.379672), dot(p, vec3(-0.825041, -0.03666, -0.563882)) - 0.315784), dot(p, vec3(-0.991174, -0.019998, -0.131054)) - 0.389982), dot(p, vec3(-0.191131, -0.157275, -0.968883)) - 0.030997), dot(p, vec3(-0.609797, -0.153624, -0.777527)) - 0.182132), dot(p, vec3(0.555821, -0.201671, -0.806469)) - -0.246315), dot(p, vec3(0.123894, -0.25122, -0.959968)) - -0.122119), dot(p, vec3(0.975757, -0.141542, -0.166925)) - -0.351744), dot(p, vec3(0.779852, -0.254214, -0.57202)) - -0.343902), dot(p, vec3(0.974186, -0.160508, 0.158742)) - -0.353296), dot(p, vec3(-0.089355, -0.984418, 0.151449)) - -0.357592);
  r = min(r, d);
  return r;
}
float sdHull170(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.054271;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.059);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.059);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.052326);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.054271);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.055861);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.054271);
  return d;
}
float sdLoft172(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(-0.633238, -0.643971, -0.429314)) - -0.054725, dot(p, vec3(0.26582, 0.429225, -0.863195)) - 0.021232), dot(p, vec3(0.797373, -0.333718, -0.50282)) - -0.376023), dot(p, vec3(-0.484595, 0.810697, -0.328539)) - 0.418586), dot(p, vec3(-0.703458, 0.429225, 0.566491)) - 0.418685), dot(p, vec3(-0.171905, -0.333718, 0.926866)) - 0.02143), dot(p, vec3(0.57851, -0.71519, 0.39221)) - -0.375924), dot(p, vec3(0.633238, 0.643971, 0.429314)) - 0.101311);
  r = min(r, d);
  return r;
}
float sdHull175(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.207846;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.207846);
  return d;
}
float sdHull180(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.033282;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.032105);
  return d;
}
float sdHull184(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.928477, 0.371391)) - 0.0);
  d = max(d, dot(p, vec3(-0.747392, 0.46979, 0.46979)) - 0.016443);
  d = max(d, dot(p, vec3(0.747392, 0.46979, 0.46979)) - 0.016443);
  return d;
}
float sdHull188(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.021651;
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.021651);
  return d;
}
float sdHull193(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.024249;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.024249);
  return d;
}
float sdHull196(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.020496;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.020496);
  return d;
}
float sdHull199(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.401142, -0.916016, 0.0)) - 0.08067);
  d = max(d, dot(p, vec3(0.0, -0.915476, -0.402374)) - 0.073212);
  d = max(d, dot(p, vec3(0.506532, -0.711908, -0.486429)) - 0.19037);
  d = max(d, dot(p, vec3(0.0, -0.915476, 0.402374)) - 0.073212);
  d = max(d, dot(p, vec3(0.506532, -0.711908, 0.486429)) - 0.19037);
  d = max(d, dot(p, vec3(-0.401142, -0.916016, 0.0)) - 0.08067);
  d = max(d, dot(p, vec3(-0.506532, -0.711908, 0.486429)) - 0.19037);
  d = max(d, dot(p, vec3(-0.506532, -0.711908, -0.486429)) - 0.19037);
  d = max(d, dot(p, vec3(0.0, 0.123236, -0.992377)) - 0.188552);
  d = max(d, dot(p, vec3(0.691139, 0.186805, -0.698163)) - 0.270168);
  d = max(d, dot(p, vec3(0.0, 0.455465, -0.890254)) - 0.210116);
  d = max(d, dot(p, vec3(0.657914, 0.36412, -0.659216)) - 0.278365);
  d = max(d, dot(p, vec3(0.691501, 0.186742, -0.697821)) - 0.270175);
  d = max(d, dot(p, vec3(-0.691139, 0.186805, -0.698163)) - 0.270168);
  d = max(d, dot(p, vec3(-0.691501, 0.186742, -0.697821)) - 0.270175);
  d = max(d, dot(p, vec3(-0.657914, 0.36412, -0.659216)) - 0.278365);
  d = max(d, dot(p, vec3(-0.990712, 0.13598, 0.0)) - 0.208049);
  d = max(d, dot(p, vec3(-0.853445, 0.521184, 0.0)) - 0.227078);
  d = max(d, dot(p, vec3(-0.691501, 0.186742, 0.697821)) - 0.270175);
  d = max(d, dot(p, vec3(-0.691139, 0.186805, 0.698163)) - 0.270168);
  d = max(d, dot(p, vec3(-0.657914, 0.36412, 0.659216)) - 0.278365);
  d = max(d, dot(p, vec3(-0.658443, 0.417402, 0.626282)) - 0.279394);
  d = max(d, dot(p, vec3(-0.658443, 0.417402, -0.626282)) - 0.279394);
  d = max(d, dot(p, vec3(0.990712, 0.13598, 0.0)) - 0.208049);
  d = max(d, dot(p, vec3(0.853445, 0.521184, 0.0)) - 0.227078);
  d = max(d, dot(p, vec3(0.658443, 0.417402, -0.626282)) - 0.279394);
  d = max(d, dot(p, vec3(0.691501, 0.186742, 0.697821)) - 0.270175);
  d = max(d, dot(p, vec3(0.691139, 0.186805, 0.698163)) - 0.270168);
  d = max(d, dot(p, vec3(0.657914, 0.36412, 0.659216)) - 0.278365);
  d = max(d, dot(p, vec3(0.658443, 0.417402, 0.626282)) - 0.279394);
  d = max(d, dot(p, vec3(0.0, 0.123236, 0.992377)) - 0.188552);
  d = max(d, dot(p, vec3(0.0, 0.455465, 0.890254)) - 0.210116);
  d = max(d, dot(p, vec3(0.0, 0.79697, -0.604019)) - 0.203132);
  d = max(d, dot(p, vec3(0.285878, 0.906443, -0.310862)) - 0.21805);
  d = max(d, dot(p, vec3(0.0, 0.970561, -0.240854)) - 0.196474);
  d = max(d, dot(p, vec3(0.25384, 0.926936, -0.276323)) - 0.21524);
  d = max(d, dot(p, vec3(0.300459, 0.906187, -0.297572)) - 0.218373);
  d = max(d, dot(p, vec3(-0.285878, 0.906443, -0.310862)) - 0.21805);
  d = max(d, dot(p, vec3(-0.300459, 0.906187, -0.297572)) - 0.218373);
  d = max(d, dot(p, vec3(-0.25384, 0.926936, -0.276323)) - 0.21524);
  d = max(d, dot(p, vec3(-0.529008, 0.848617, 0.0)) - 0.206075);
  d = max(d, dot(p, vec3(-0.221552, 0.975149, 0.0)) - 0.195961);
  d = max(d, dot(p, vec3(-0.300459, 0.906187, 0.297572)) - 0.218373);
  d = max(d, dot(p, vec3(-0.285878, 0.906443, 0.310862)) - 0.21805);
  d = max(d, dot(p, vec3(-0.25384, 0.926936, 0.276323)) - 0.21524);
  d = max(d, dot(p, vec3(0.529008, 0.848617, 0.0)) - 0.206075);
  d = max(d, dot(p, vec3(0.300459, 0.906187, 0.297572)) - 0.218373);
  d = max(d, dot(p, vec3(0.221552, 0.975149, 0.0)) - 0.195961);
  d = max(d, dot(p, vec3(0.285878, 0.906443, 0.310862)) - 0.21805);
  d = max(d, dot(p, vec3(0.25384, 0.926936, 0.276323)) - 0.21524);
  d = max(d, dot(p, vec3(0.0, 0.79697, 0.604019)) - 0.203132);
  d = max(d, dot(p, vec3(0.0, 0.970561, 0.240854)) - 0.196474);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.18);
  return d;
}
float sdHull203(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.11;
  d = max(d, dot(p, vec3(0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, 0.981175)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, -0.981175)) - 0.021243);
  return d;
}
float sdHull207(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.11;
  d = max(d, dot(p, vec3(0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, 0.981175)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, 0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(-0.849723, 0.193119, -0.490588)) - 0.021243);
  d = max(d, dot(p, vec3(0.0, 0.193119, -0.981175)) - 0.021243);
  return d;
}
float sdHull210(vec3 p) {
  float d = dot(p, vec3(0.0, -0.124035, -0.992278)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.780869, 0.624695)) - 0.0);
  d = max(d, dot(p, vec3(-0.383914, -0.22395, 0.895799)) - 0.053748);
  d = max(d, dot(p, vec3(0.383914, -0.22395, 0.895799)) - 0.053748);
  return d;
}
float sdHull216(vec3 p) {
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
float sdHull219(vec3 p) {
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
float sdHull226(vec3 p) {
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
float sdHull230(vec3 p) {
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
float sdHull233(vec3 p) {
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
float sdLoft243(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.935925, -0.049995, 0.348632)) - 0.132154), dot(p, vec3(0.935929, -0.074676, -0.344181)) - 0.122776), dot(p, vec3(0.93677, -0.051203, 0.346179)) - 0.131831), dot(p, vec3(0.936824, -0.075767, -0.341497)) - 0.122506), dot(p, vec3(0.419469, -0.032322, 0.907194)) - 0.100546), dot(p, vec3(0.422297, -0.033607, 0.905834)) - 0.100368), dot(p, vec3(-0.419469, -0.032322, 0.907194)) - 0.028817), dot(p, vec3(-0.935925, -0.049995, 0.348632)) - -0.027889), dot(p, vec3(-0.422297, -0.033607, 0.905834)) - 0.028155), dot(p, vec3(-0.935929, -0.074676, -0.344181)) - -0.037268), dot(p, vec3(-0.93677, -0.051203, 0.346179)) - -0.028356), dot(p, vec3(-0.936824, -0.075767, -0.341497)) - -0.037691), dot(p, vec3(-0.419472, -0.096866, -0.902585)) - 0.004291), dot(p, vec3(-0.422365, -0.098076, -0.901104)) - 0.003653), dot(p, vec3(0.419472, -0.096866, -0.902585)) - 0.07602), dot(p, vec3(0.422365, -0.098076, -0.901104)) - 0.075877), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.937454, -0.038583, 0.345963)) - 0.134963), dot(p, vec3(0.937409, -0.06499, -0.342111)) - 0.125178), dot(p, vec3(0.939832, -0.041903, 0.339056)) - 0.134493), dot(p, vec3(0.939832, -0.067822, -0.334836)) - 0.124903), dot(p, vec3(0.422774, -0.013915, 0.906128)) - 0.105213), dot(p, vec3(0.430832, -0.01744, 0.902264)) - 0.105203), dot(p, vec3(-0.422774, -0.013915, 0.906128)) - 0.032918), dot(p, vec3(-0.937454, -0.038583, 0.345963)) - -0.025342), dot(p, vec3(-0.430832, -0.01744, 0.902264)) - 0.031531), dot(p, vec3(-0.937409, -0.06499, -0.342111)) - -0.035119), dot(p, vec3(-0.939832, -0.041903, 0.339056)) - -0.026218), dot(p, vec3(-0.939832, -0.067822, -0.334836)) - -0.035808), dot(p, vec3(-0.422723, -0.083396, -0.902414)) - 0.007196), dot(p, vec3(-0.430833, -0.086631, -0.898264)) - 0.005915), dot(p, vec3(0.422723, -0.083396, -0.902414)) - 0.079482), dot(p, vec3(0.430833, -0.086631, -0.898264)) - 0.079587), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull246(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.64899, -0.760797, 0.0)) - 0.049993);
  d = max(d, dot(p, vec3(0.0, -0.764563, -0.64455)) - 0.056475);
  d = max(d, dot(p, vec3(0.58389, -0.546673, -0.600185)) - 0.097566);
  d = max(d, dot(p, vec3(0.737749, -0.67505, -0.005829)) - 0.057341);
  d = max(d, dot(p, vec3(0.0, -0.900887, 0.434053)) - 0.059734);
  d = max(d, dot(p, vec3(0.587034, -0.616778, 0.524381)) - 0.117385);
  d = max(d, dot(p, vec3(-0.64899, -0.760797, 0.0)) - 0.049993);
  d = max(d, dot(p, vec3(-0.587034, -0.616778, 0.524381)) - 0.117385);
  d = max(d, dot(p, vec3(-0.58389, -0.546673, -0.600185)) - 0.097566);
  d = max(d, dot(p, vec3(-0.737749, -0.67505, -0.005829)) - 0.057341);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.732685, 0.09026, -0.674555)) - 0.122294);
  d = max(d, dot(p, vec3(0.0, 0.729883, -0.683572)) - 0.163847);
  d = max(d, dot(p, vec3(0.734728, 0.090604, -0.672284)) - 0.122271);
  d = max(d, dot(p, vec3(0.562521, 0.603747, -0.564854)) - 0.172729);
  d = max(d, dot(p, vec3(-0.732685, 0.09026, -0.674555)) - 0.122294);
  d = max(d, dot(p, vec3(-0.734728, 0.090604, -0.672284)) - 0.122271);
  d = max(d, dot(p, vec3(-0.562521, 0.603747, -0.564854)) - 0.172729);
  d = max(d, dot(p, vec3(-0.998379, 0.056908, 0.0)) - 0.085361);
  d = max(d, dot(p, vec3(-0.84698, 0.531522, 0.010438)) - 0.139598);
  d = max(d, dot(p, vec3(-0.996323, 0.078778, 0.033679)) - 0.08994);
  d = max(d, dot(p, vec3(-0.715257, 0.698754, 0.012298)) - 0.152778);
  d = max(d, dot(p, vec3(-0.635978, 0.771708, 0.0)) - 0.157863);
  d = max(d, dot(p, vec3(-0.620467, -0.550928, 0.558121)) - 0.125296);
  d = max(d, dot(p, vec3(-0.993915, 0.092157, 0.060331)) - 0.09347);
  d = max(d, dot(p, vec3(0.998379, 0.056908, 0.0)) - 0.085361);
  d = max(d, dot(p, vec3(0.84698, 0.531522, 0.010438)) - 0.139598);
  d = max(d, dot(p, vec3(0.715257, 0.698754, 0.012298)) - 0.152778);
  d = max(d, dot(p, vec3(0.635978, 0.771708, 0.0)) - 0.157863);
  d = max(d, dot(p, vec3(0.996323, 0.078778, 0.033679)) - 0.08994);
  d = max(d, dot(p, vec3(0.620467, -0.550928, 0.558121)) - 0.125296);
  d = max(d, dot(p, vec3(0.993915, 0.092157, 0.060331)) - 0.09347);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.43159, -0.005308, 0.902054)) - 0.167035);
  d = max(d, dot(p, vec3(0.0, 0.478388, 0.878149)) - 0.17433);
  d = max(d, dot(p, vec3(0.611265, 0.110612, 0.783658)) - 0.166569);
  d = max(d, dot(p, vec3(0.513574, 0.357923, 0.779829)) - 0.178457);
  d = max(d, dot(p, vec3(-0.43159, -0.005308, 0.902054)) - 0.167035);
  d = max(d, dot(p, vec3(-0.611265, 0.110612, 0.783658)) - 0.166569);
  d = max(d, dot(p, vec3(-0.513574, 0.357923, 0.779829)) - 0.178457);
  d = max(d, dot(p, vec3(-0.961533, 0.179542, 0.20789)) - 0.113395);
  d = max(d, dot(p, vec3(-0.545661, 0.638168, 0.543135)) - 0.168382);
  d = max(d, dot(p, vec3(-0.395381, 0.874703, 0.280301)) - 0.171266);
  d = max(d, dot(p, vec3(-0.289467, 0.771035, 0.567199)) - 0.16877);
  d = max(d, dot(p, vec3(0.961533, 0.179542, 0.20789)) - 0.113395);
  d = max(d, dot(p, vec3(0.545661, 0.638168, 0.543135)) - 0.168382);
  d = max(d, dot(p, vec3(0.395381, 0.874703, 0.280301)) - 0.171266);
  d = max(d, dot(p, vec3(0.289467, 0.771035, 0.567199)) - 0.16877);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959076, 0.283147)) - 0.157886);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft248(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.935925, -0.049995, 0.348632)) - -0.027889), dot(p, vec3(0.935929, -0.074676, -0.344181)) - -0.037268), dot(p, vec3(0.93677, -0.051203, 0.346179)) - -0.028356), dot(p, vec3(0.936824, -0.075767, -0.341497)) - -0.037691), dot(p, vec3(0.419469, -0.032322, 0.907194)) - 0.028817), dot(p, vec3(0.422297, -0.033607, 0.905834)) - 0.028155), dot(p, vec3(-0.419469, -0.032322, 0.907194)) - 0.100546), dot(p, vec3(-0.935925, -0.049995, 0.348632)) - 0.132154), dot(p, vec3(-0.422297, -0.033607, 0.905834)) - 0.100368), dot(p, vec3(-0.935929, -0.074676, -0.344181)) - 0.122776), dot(p, vec3(-0.93677, -0.051203, 0.346179)) - 0.131831), dot(p, vec3(-0.936824, -0.075767, -0.341497)) - 0.122506), dot(p, vec3(-0.419472, -0.096866, -0.902585)) - 0.07602), dot(p, vec3(-0.422365, -0.098076, -0.901104)) - 0.075877), dot(p, vec3(0.419472, -0.096866, -0.902585)) - 0.004291), dot(p, vec3(0.422365, -0.098076, -0.901104)) - 0.003653), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.937454, -0.038583, 0.345963)) - -0.025342), dot(p, vec3(0.937409, -0.06499, -0.342111)) - -0.035119), dot(p, vec3(0.939832, -0.041903, 0.339056)) - -0.026218), dot(p, vec3(0.939832, -0.067822, -0.334836)) - -0.035808), dot(p, vec3(0.422774, -0.013915, 0.906128)) - 0.032918), dot(p, vec3(0.430832, -0.01744, 0.902264)) - 0.031531), dot(p, vec3(-0.422774, -0.013915, 0.906128)) - 0.105213), dot(p, vec3(-0.937454, -0.038583, 0.345963)) - 0.134963), dot(p, vec3(-0.430832, -0.01744, 0.902264)) - 0.105203), dot(p, vec3(-0.937409, -0.06499, -0.342111)) - 0.125178), dot(p, vec3(-0.939832, -0.041903, 0.339056)) - 0.134493), dot(p, vec3(-0.939832, -0.067822, -0.334836)) - 0.124903), dot(p, vec3(-0.422723, -0.083396, -0.902414)) - 0.079482), dot(p, vec3(-0.430833, -0.086631, -0.898264)) - 0.079587), dot(p, vec3(0.422723, -0.083396, -0.902414)) - 0.007196), dot(p, vec3(0.430833, -0.086631, -0.898264)) - 0.005915), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull251(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.64899, -0.760797, 0.0)) - 0.049993);
  d = max(d, dot(p, vec3(0.0, -0.764563, -0.64455)) - 0.056475);
  d = max(d, dot(p, vec3(0.58389, -0.546673, -0.600185)) - 0.097566);
  d = max(d, dot(p, vec3(0.737749, -0.67505, -0.005829)) - 0.057341);
  d = max(d, dot(p, vec3(0.0, -0.900887, 0.434053)) - 0.059734);
  d = max(d, dot(p, vec3(0.587034, -0.616778, 0.524381)) - 0.117385);
  d = max(d, dot(p, vec3(-0.64899, -0.760797, 0.0)) - 0.049993);
  d = max(d, dot(p, vec3(-0.587034, -0.616778, 0.524381)) - 0.117385);
  d = max(d, dot(p, vec3(-0.58389, -0.546673, -0.600185)) - 0.097566);
  d = max(d, dot(p, vec3(-0.737749, -0.67505, -0.005829)) - 0.057341);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.732685, 0.09026, -0.674555)) - 0.122294);
  d = max(d, dot(p, vec3(0.0, 0.729883, -0.683572)) - 0.163847);
  d = max(d, dot(p, vec3(0.734728, 0.090604, -0.672284)) - 0.122271);
  d = max(d, dot(p, vec3(0.562521, 0.603747, -0.564854)) - 0.172729);
  d = max(d, dot(p, vec3(-0.732685, 0.09026, -0.674555)) - 0.122294);
  d = max(d, dot(p, vec3(-0.734728, 0.090604, -0.672284)) - 0.122271);
  d = max(d, dot(p, vec3(-0.562521, 0.603747, -0.564854)) - 0.172729);
  d = max(d, dot(p, vec3(-0.998379, 0.056908, 0.0)) - 0.085361);
  d = max(d, dot(p, vec3(-0.84698, 0.531522, 0.010438)) - 0.139598);
  d = max(d, dot(p, vec3(-0.996323, 0.078778, 0.033679)) - 0.08994);
  d = max(d, dot(p, vec3(-0.715257, 0.698754, 0.012298)) - 0.152778);
  d = max(d, dot(p, vec3(-0.635978, 0.771708, 0.0)) - 0.157863);
  d = max(d, dot(p, vec3(-0.620467, -0.550928, 0.558121)) - 0.125296);
  d = max(d, dot(p, vec3(-0.993915, 0.092157, 0.060331)) - 0.09347);
  d = max(d, dot(p, vec3(0.998379, 0.056908, 0.0)) - 0.085361);
  d = max(d, dot(p, vec3(0.84698, 0.531522, 0.010438)) - 0.139598);
  d = max(d, dot(p, vec3(0.715257, 0.698754, 0.012298)) - 0.152778);
  d = max(d, dot(p, vec3(0.635978, 0.771708, 0.0)) - 0.157863);
  d = max(d, dot(p, vec3(0.996323, 0.078778, 0.033679)) - 0.08994);
  d = max(d, dot(p, vec3(0.620467, -0.550928, 0.558121)) - 0.125296);
  d = max(d, dot(p, vec3(0.993915, 0.092157, 0.060331)) - 0.09347);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.43159, -0.005308, 0.902054)) - 0.167035);
  d = max(d, dot(p, vec3(0.0, 0.478388, 0.878149)) - 0.17433);
  d = max(d, dot(p, vec3(0.611265, 0.110612, 0.783658)) - 0.166569);
  d = max(d, dot(p, vec3(0.513574, 0.357923, 0.779829)) - 0.178457);
  d = max(d, dot(p, vec3(-0.43159, -0.005308, 0.902054)) - 0.167035);
  d = max(d, dot(p, vec3(-0.611265, 0.110612, 0.783658)) - 0.166569);
  d = max(d, dot(p, vec3(-0.513574, 0.357923, 0.779829)) - 0.178457);
  d = max(d, dot(p, vec3(-0.961533, 0.179542, 0.20789)) - 0.113395);
  d = max(d, dot(p, vec3(-0.545661, 0.638168, 0.543135)) - 0.168382);
  d = max(d, dot(p, vec3(-0.395381, 0.874703, 0.280301)) - 0.171266);
  d = max(d, dot(p, vec3(-0.289467, 0.771035, 0.567199)) - 0.16877);
  d = max(d, dot(p, vec3(0.961533, 0.179542, 0.20789)) - 0.113395);
  d = max(d, dot(p, vec3(0.545661, 0.638168, 0.543135)) - 0.168382);
  d = max(d, dot(p, vec3(0.395381, 0.874703, 0.280301)) - 0.171266);
  d = max(d, dot(p, vec3(0.289467, 0.771035, 0.567199)) - 0.16877);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959076, 0.283147)) - 0.157886);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft253(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.34, dot(p, vec3(-0.903109, 0.13564, 0.407427)) - 0.209129), dot(p, vec3(-0.903109, 0.13564, -0.407427)) - 0.209129), dot(p, vec3(-0.906737, 0.143567, 0.396505)) - 0.212479), dot(p, vec3(-0.906737, 0.143567, -0.396505)) - 0.212479), dot(p, vec3(-0.461645, 0.092508, 0.882228)) - 0.166278), dot(p, vec3(-0.472498, 0.103396, 0.875246)) - 0.171032), dot(p, vec3(0.0, 0.079007, 0.996874)) - 0.150113), dot(p, vec3(0.461645, 0.092508, 0.882228)) - 0.166278), dot(p, vec3(0.903109, 0.13564, 0.407427)) - 0.209129), dot(p, vec3(0.472498, 0.103396, 0.875246)) - 0.171032), dot(p, vec3(0.903109, 0.13564, -0.407427)) - 0.209129), dot(p, vec3(0.906737, 0.143567, 0.396505)) - 0.212479), dot(p, vec3(0.906737, 0.143567, -0.396505)) - 0.212479), dot(p, vec3(0.461645, 0.092508, -0.882228)) - 0.166278), dot(p, vec3(0.472498, 0.103396, -0.875246)) - 0.171032), dot(p, vec3(0.0, 0.079007, -0.996874)) - 0.150113), dot(p, vec3(-0.461645, 0.092508, -0.882228)) - 0.166278), dot(p, vec3(-0.472498, 0.103396, -0.875246)) - 0.171032), dot(p, vec3(0.0, 1.0, 0.0)) - 0.46);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.46, dot(p, vec3(-0.863814, -0.333378, 0.377735)) - -0.013848), dot(p, vec3(-0.863814, -0.333378, -0.377735)) - -0.013848), dot(p, vec3(-0.461366, -0.23824, 0.854625)) - 0.01097), dot(p, vec3(-0.855148, -0.312579, 0.41354)) - -0.002887), dot(p, vec3(0.0, -0.175554, 0.98447)) - 0.0316), dot(p, vec3(-0.429093, -0.207921, 0.879004)) - 0.026089), dot(p, vec3(0.461366, -0.23824, 0.854625)) - 0.01097), dot(p, vec3(0.429093, -0.207921, 0.879004)) - 0.026089), dot(p, vec3(0.863814, -0.333378, 0.377735)) - -0.013848), dot(p, vec3(0.855148, -0.312579, 0.41354)) - -0.002887), dot(p, vec3(0.863814, -0.333378, -0.377735)) - -0.013848), dot(p, vec3(0.461366, -0.23824, -0.854625)) - 0.01097), dot(p, vec3(0.855148, -0.312579, -0.41354)) - -0.002887), dot(p, vec3(0.0, -0.175554, -0.98447)) - 0.0316), dot(p, vec3(0.429093, -0.207921, -0.879004)) - 0.026089), dot(p, vec3(-0.461366, -0.23824, -0.854625)) - 0.01097), dot(p, vec3(-0.429093, -0.207921, -0.879004)) - 0.026089), dot(p, vec3(-0.855148, -0.312579, -0.41354)) - -0.002887), dot(p, vec3(0.0, 1.0, 0.0)) - 0.62);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.62, dot(p, vec3(-0.788547, 0.482472, 0.381332)) - 0.475176), dot(p, vec3(-0.788547, 0.482472, -0.381332)) - 0.475176), dot(p, vec3(-0.790517, 0.491033, 0.366018)) - 0.480923), dot(p, vec3(-0.790517, 0.491033, -0.366018)) - 0.480923), dot(p, vec3(-0.405473, 0.381662, 0.830618)) - 0.383098), dot(p, vec3(-0.417332, 0.394766, 0.818532)) - 0.392299), dot(p, vec3(0.0, 0.34353, 0.939142)) - 0.346965), dot(p, vec3(0.405473, 0.381662, 0.830618)) - 0.383098), dot(p, vec3(0.788547, 0.482472, 0.381332)) - 0.475176), dot(p, vec3(0.417332, 0.394766, 0.818532)) - 0.392299), dot(p, vec3(0.788547, 0.482472, -0.381332)) - 0.475176), dot(p, vec3(0.790517, 0.491033, 0.366018)) - 0.480923), dot(p, vec3(0.790517, 0.491033, -0.366018)) - 0.480923), dot(p, vec3(0.405473, 0.381662, -0.830618)) - 0.383098), dot(p, vec3(0.417332, 0.394766, -0.818532)) - 0.392299), dot(p, vec3(0.0, 0.34353, -0.939142)) - 0.346965), dot(p, vec3(-0.405473, 0.381662, -0.830618)) - 0.383098), dot(p, vec3(-0.417332, 0.394766, -0.818532)) - 0.392299), dot(p, vec3(0.0, 1.0, 0.0)) - 0.75);
  r = min(r, d);
  return r;
}
float sdLoft255(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.39, dot(p, vec3(-0.910981, 0.07029, 0.406416)) - 0.187518), dot(p, vec3(-0.910981, 0.07029, -0.406416)) - 0.187518), dot(p, vec3(-0.911414, 0.072154, 0.405115)) - 0.188321), dot(p, vec3(-0.911414, 0.072154, -0.405115)) - 0.188321), dot(p, vec3(-0.467037, 0.053397, 0.882624)) - 0.153636), dot(p, vec3(-0.468317, 0.05591, 0.88179)) - 0.154735), dot(p, vec3(0.0, 0.047499, 0.998871)) - 0.140122), dot(p, vec3(0.467037, 0.053397, 0.882624)) - 0.153636), dot(p, vec3(0.910981, 0.07029, 0.406416)) - 0.187518), dot(p, vec3(0.468317, 0.05591, 0.88179)) - 0.154735), dot(p, vec3(0.910981, 0.07029, -0.406416)) - 0.187518), dot(p, vec3(0.911414, 0.072154, 0.405115)) - 0.188321), dot(p, vec3(0.911414, 0.072154, -0.405115)) - 0.188321), dot(p, vec3(0.467037, 0.053397, -0.882624)) - 0.153636), dot(p, vec3(0.468317, 0.05591, -0.88179)) - 0.154735), dot(p, vec3(0.0, 0.047499, -0.998871)) - 0.140122), dot(p, vec3(-0.467037, 0.053397, -0.882624)) - 0.153636), dot(p, vec3(-0.468317, 0.05591, -0.88179)) - 0.154735), dot(p, vec3(0.0, 1.0, 0.0)) - 0.45);
  r = min(r, d);
  return r;
}
float sdHull258(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.032332;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.032332);
  return d;
}
float sdHull261(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.939329, 0.156555, 0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(0.939329, 0.156555, -0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(0.580537, 0.156555, 0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 0.156555, 0.987669)) - 0.197259);
  d = max(d, dot(p, vec3(-0.580537, 0.156555, 0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(-0.939329, 0.156555, 0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(-0.939329, 0.156555, -0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(-0.580537, 0.156555, -0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 0.156555, -0.987669)) - 0.197259);
  d = max(d, dot(p, vec3(0.580537, 0.156555, -0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull265(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.091021;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.089563);
  return d;
}
float sdLoft268(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.165062, 0.984581, -0.057917)) - 0.648436, dot(p, vec3(0.664414, 0.048355, -0.745799)) - 0.252366), dot(p, vec3(-0.046551, -0.085349, -0.995263)) - -0.016836), dot(p, vec3(0.277817, -0.07594, -0.957628)) - 0.074104), dot(p, vec3(0.987952, 0.143139, -0.058836)) - 0.398628), dot(p, vec3(0.870236, 0.050864, -0.490002)) - 0.3092), dot(p, vec3(0.734583, 0.143204, 0.663235)) - 0.336092), dot(p, vec3(0.957045, 0.109802, 0.268342)) - 0.371905), dot(p, vec3(0.052792, 0.048117, 0.997446)) - 0.101128), dot(p, vec3(0.487389, 0.065743, 0.870706)) - 0.225062), dot(p, vec3(-0.658071, -0.086142, 0.748012)) - -0.168437), dot(p, vec3(-0.259437, -0.05488, 0.964199)) - -0.04385), dot(p, vec3(-0.981675, -0.180525, 0.061034)) - -0.314434), dot(p, vec3(-0.847281, -0.180844, 0.49941)) - -0.277237), dot(p, vec3(-0.728407, -0.180035, -0.661067)) - -0.251534), dot(p, vec3(-0.937028, -0.239344, -0.25435)) - -0.340362), dot(p, vec3(-0.471934, -0.196122, -0.859543)) - -0.195222), dot(p, vec3(0.125049, -0.987227, 0.098723)) - -0.487792);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.125049, 0.987227, -0.098723)) - 0.487792, dot(p, vec3(0.876818, -0.030044, -0.479884)) - 0.268036), dot(p, vec3(0.285647, -0.14529, -0.947257)) - 0.03944), dot(p, vec3(0.676102, -0.135189, -0.7243)) - 0.158028), dot(p, vec3(0.958606, 0.090324, 0.270029)) - 0.361985), dot(p, vec3(0.998982, -0.007875, -0.044416)) - 0.321369), dot(p, vec3(0.478857, 0.146327, 0.865612)) - 0.265529), dot(p, vec3(0.739768, 0.080724, 0.668002)) - 0.304298), dot(p, vec3(-0.281233, 0.104753, 0.953905)) - 0.034927), dot(p, vec3(0.050458, 0.079551, 0.995553)) - 0.117199), dot(p, vec3(-0.874246, -0.010565, 0.485367)) - -0.194267), dot(p, vec3(-0.665188, -0.011252, 0.746592)) - -0.130551), dot(p, vec3(-0.954755, -0.132507, -0.266241)) - -0.288536), dot(p, vec3(-0.987969, -0.13936, 0.067056)) - -0.294173), dot(p, vec3(-0.473087, -0.188428, -0.86063)) - -0.191455), dot(p, vec3(-0.728895, -0.229125, -0.645146)) - -0.277606), dot(p, vec3(-0.039683, -0.227159, -0.973049)) - -0.090225), dot(p, vec3(0.07204, -0.985804, 0.151662)) - -0.36924);
  r = min(r, d);
  return r;
}
float sdHull271(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.047631;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.0475);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.0475);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.047631);
  return d;
}
float sdLoft273(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(0.55009, -0.69485, -0.463233)) - -0.132803, dot(p, vec3(0.776954, 0.413998, 0.474287)) - 0.383132), dot(p, vec3(0.247158, -0.302853, 0.920431)) - 0.039773), dot(p, vec3(0.485801, 0.772423, -0.409096)) - 0.371245), dot(p, vec3(-0.335148, 0.413998, -0.846334)) - 0.015999), dot(p, vec3(-0.864944, -0.302853, -0.40019)) - -0.32736), dot(p, vec3(-0.573791, -0.661279, 0.483192)) - -0.315473), dot(p, vec3(-0.55009, 0.69485, 0.463233)) - 0.175978);
  r = min(r, d);
  return r;
}
float sdHull277(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.091021;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.091021);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.091021);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.089563);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.08811);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.08811);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.089563);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.089563);
  return d;
}
float sdLoft280(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.165062, 0.984581, -0.057917)) - 0.648436, dot(p, vec3(-0.052792, 0.048117, 0.997446)) - 0.101128), dot(p, vec3(0.658071, -0.086142, 0.748012)) - -0.168437), dot(p, vec3(0.259437, -0.05488, 0.964199)) - -0.04385), dot(p, vec3(-0.734583, 0.143204, 0.663235)) - 0.336092), dot(p, vec3(-0.487389, 0.065743, 0.870706)) - 0.225062), dot(p, vec3(-0.987952, 0.143139, -0.058836)) - 0.398628), dot(p, vec3(-0.957045, 0.109802, 0.268342)) - 0.371905), dot(p, vec3(-0.664414, 0.048355, -0.745799)) - 0.252366), dot(p, vec3(-0.870236, 0.050864, -0.490002)) - 0.3092), dot(p, vec3(0.046551, -0.085349, -0.995263)) - -0.016836), dot(p, vec3(-0.277817, -0.07594, -0.957628)) - 0.074104), dot(p, vec3(0.728407, -0.180035, -0.661067)) - -0.251534), dot(p, vec3(0.471934, -0.196122, -0.859543)) - -0.195222), dot(p, vec3(0.981675, -0.180525, 0.061034)) - -0.314434), dot(p, vec3(0.937028, -0.239344, -0.25435)) - -0.340362), dot(p, vec3(0.847281, -0.180844, 0.49941)) - -0.277237), dot(p, vec3(-0.125049, -0.987227, 0.098723)) - -0.487792);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.125049, 0.987227, -0.098723)) - 0.487792, dot(p, vec3(0.281233, 0.104753, 0.953905)) - 0.034927), dot(p, vec3(0.874246, -0.010565, 0.485367)) - -0.194267), dot(p, vec3(0.665188, -0.011252, 0.746592)) - -0.130551), dot(p, vec3(-0.478857, 0.146327, 0.865612)) - 0.265529), dot(p, vec3(-0.050458, 0.079551, 0.995553)) - 0.117199), dot(p, vec3(-0.958606, 0.090324, 0.270029)) - 0.361985), dot(p, vec3(-0.739768, 0.080724, 0.668002)) - 0.304298), dot(p, vec3(-0.876818, -0.030044, -0.479884)) - 0.268036), dot(p, vec3(-0.998982, -0.007875, -0.044416)) - 0.321369), dot(p, vec3(-0.285647, -0.14529, -0.947257)) - 0.03944), dot(p, vec3(-0.676102, -0.135189, -0.7243)) - 0.158028), dot(p, vec3(0.473087, -0.188428, -0.86063)) - -0.191455), dot(p, vec3(0.039683, -0.227159, -0.973049)) - -0.090225), dot(p, vec3(0.954755, -0.132507, -0.266241)) - -0.288536), dot(p, vec3(0.728895, -0.229125, -0.645146)) - -0.277606), dot(p, vec3(0.987969, -0.13936, 0.067056)) - -0.294173), dot(p, vec3(-0.07204, -0.985804, 0.151662)) - -0.36924);
  r = min(r, d);
  return r;
}
float sdHull283(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.047631;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.0475);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.0475);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.044194);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.047631);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.04773);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.047631);
  return d;
}
float sdLoft285(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(-0.55009, -0.69485, -0.463233)) - -0.132803, dot(p, vec3(0.335148, 0.413998, -0.846334)) - 0.015999), dot(p, vec3(0.864944, -0.302853, -0.40019)) - -0.32736), dot(p, vec3(-0.485801, 0.772423, -0.409096)) - 0.371245), dot(p, vec3(-0.776954, 0.413998, 0.474287)) - 0.383132), dot(p, vec3(-0.247158, -0.302853, 0.920431)) - 0.039773), dot(p, vec3(0.573791, -0.661279, 0.483192)) - -0.315473), dot(p, vec3(0.55009, 0.69485, 0.463233)) - 0.175978);
  r = min(r, d);
  return r;
}
float sdHull288(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.207846;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.207846);
  return d;
}
float sdHull293(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.033282;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.032105);
  return d;
}
float sdHull297(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.928477, 0.371391)) - 0.0);
  d = max(d, dot(p, vec3(-0.747392, 0.46979, 0.46979)) - 0.016443);
  d = max(d, dot(p, vec3(0.747392, 0.46979, 0.46979)) - 0.016443);
  return d;
}
float sdHull301(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.021651;
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.021651);
  return d;
}
float sdHull306(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.024249;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.024249);
  return d;
}
float sdHull309(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.020496;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.020496);
  return d;
}
float sdHull312(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.540597, -0.841282, 0.0)) - 0.114131);
  d = max(d, dot(p, vec3(0.0, -0.945362, -0.326021)) - 0.062573);
  d = max(d, dot(p, vec3(0.581632, -0.701832, -0.411262)) - 0.201727);
  d = max(d, dot(p, vec3(0.0, -0.844357, 0.535781)) - 0.102831);
  d = max(d, dot(p, vec3(0.569479, -0.618658, 0.541254)) - 0.224111);
  d = max(d, dot(p, vec3(-0.540597, -0.841282, 0.0)) - 0.114131);
  d = max(d, dot(p, vec3(-0.569479, -0.618658, 0.541254)) - 0.224111);
  d = max(d, dot(p, vec3(-0.581632, -0.701832, -0.411262)) - 0.201727);
  d = max(d, dot(p, vec3(0.0, -0.316228, -0.948683)) - 0.189737);
  d = max(d, dot(p, vec3(0.096058, -0.203748, -0.974299)) - 0.215265);
  d = max(d, dot(p, vec3(-0.096058, -0.203748, -0.974299)) - 0.215265);
  d = max(d, dot(p, vec3(0.0, -0.063119, -0.998006)) - 0.245051);
  d = max(d, dot(p, vec3(0.670661, -0.520386, -0.528594)) - 0.244447);
  d = max(d, dot(p, vec3(0.145963, -0.147885, -0.978174)) - 0.226624);
  d = max(d, dot(p, vec3(-0.670661, -0.520386, -0.528594)) - 0.244447);
  d = max(d, dot(p, vec3(-0.145963, -0.147885, -0.978174)) - 0.226624);
  d = max(d, dot(p, vec3(-0.995037, 0.099504, 0.0)) - 0.218908);
  d = max(d, dot(p, vec3(-0.924664, 0.380785, 0.0)) - 0.25948);
  d = max(d, dot(p, vec3(-0.703976, 0.107108, 0.702101)) - 0.287963);
  d = max(d, dot(p, vec3(-0.69084, 0.107894, 0.714912)) - 0.28778);
  d = max(d, dot(p, vec3(-0.673751, 0.253083, 0.694268)) - 0.308877);
  d = max(d, dot(p, vec3(-0.691654, 0.332769, 0.640999)) - 0.318403);
  d = max(d, dot(p, vec3(-0.910932, 0.111856, -0.397103)) - 0.275679);
  d = max(d, dot(p, vec3(-0.850169, 0.121261, -0.512355)) - 0.285996);
  d = max(d, dot(p, vec3(-0.772271, 0.357314, -0.525285)) - 0.318585);
  d = max(d, dot(p, vec3(-0.322226, 0.079389, -0.943328)) - 0.259555);
  d = max(d, dot(p, vec3(-0.28361, 0.342858, -0.895552)) - 0.29322);
  d = max(d, dot(p, vec3(0.0, 0.345989, -0.938239)) - 0.301672);
  d = max(d, dot(p, vec3(-0.274008, 0.378028, -0.884316)) - 0.296419);
  d = max(d, dot(p, vec3(-0.726506, 0.40786, -0.553027)) - 0.324786);
  d = max(d, dot(p, vec3(0.995037, 0.099504, 0.0)) - 0.218908);
  d = max(d, dot(p, vec3(0.924664, 0.380785, 0.0)) - 0.25948);
  d = max(d, dot(p, vec3(0.910932, 0.111856, -0.397103)) - 0.275679);
  d = max(d, dot(p, vec3(0.850169, 0.121261, -0.512355)) - 0.285996);
  d = max(d, dot(p, vec3(0.772271, 0.357314, -0.525285)) - 0.318585);
  d = max(d, dot(p, vec3(0.703976, 0.107108, 0.702101)) - 0.287963);
  d = max(d, dot(p, vec3(0.69084, 0.107894, 0.714912)) - 0.28778);
  d = max(d, dot(p, vec3(0.673751, 0.253083, 0.694268)) - 0.308877);
  d = max(d, dot(p, vec3(0.691654, 0.332769, 0.640999)) - 0.318403);
  d = max(d, dot(p, vec3(0.322226, 0.079389, -0.943328)) - 0.259555);
  d = max(d, dot(p, vec3(0.28361, 0.342858, -0.895552)) - 0.29322);
  d = max(d, dot(p, vec3(0.726506, 0.40786, -0.553027)) - 0.324786);
  d = max(d, dot(p, vec3(0.274008, 0.378028, -0.884316)) - 0.296419);
  d = max(d, dot(p, vec3(0.0, 0.049938, 0.998752)) - 0.19975);
  d = max(d, dot(p, vec3(0.0, 0.266495, 0.963836)) - 0.235257);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.282843);
  d = max(d, dot(p, vec3(-0.338119, 0.941103, 0.0)) - 0.313545);
  d = max(d, dot(p, vec3(-0.45792, 0.778174, 0.429831)) - 0.325);
  d = max(d, dot(p, vec3(-0.412541, 0.776379, 0.476493)) - 0.324853);
  d = max(d, dot(p, vec3(-0.342269, 0.846796, 0.407172)) - 0.330743);
  d = max(d, dot(p, vec3(-0.547341, 0.777704, -0.309184)) - 0.320958);
  d = max(d, dot(p, vec3(-0.347471, 0.891804, -0.289742)) - 0.331717);
  d = max(d, dot(p, vec3(-0.506853, 0.773724, -0.380066)) - 0.324844);
  d = max(d, dot(p, vec3(-0.181083, 0.679061, -0.711397)) - 0.307194);
  d = max(d, dot(p, vec3(-0.09004, 0.724054, -0.683841)) - 0.307662);
  d = max(d, dot(p, vec3(-0.295641, 0.90113, -0.317113)) - 0.332762);
  d = max(d, dot(p, vec3(0.0, 0.605771, -0.795639)) - 0.313387);
  d = max(d, dot(p, vec3(-0.080334, 0.727828, -0.681038)) - 0.307558);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.282843);
  d = max(d, dot(p, vec3(0.45792, 0.778174, 0.429831)) - 0.325);
  d = max(d, dot(p, vec3(0.547341, 0.777704, -0.309184)) - 0.320958);
  d = max(d, dot(p, vec3(0.506853, 0.773724, -0.380066)) - 0.324844);
  d = max(d, dot(p, vec3(0.338119, 0.941103, 0.0)) - 0.313545);
  d = max(d, dot(p, vec3(0.347471, 0.891804, -0.289742)) - 0.331717);
  d = max(d, dot(p, vec3(0.412541, 0.776379, 0.476493)) - 0.324853);
  d = max(d, dot(p, vec3(0.342269, 0.846796, 0.407172)) - 0.330743);
  d = max(d, dot(p, vec3(0.181083, 0.679061, -0.711397)) - 0.307194);
  d = max(d, dot(p, vec3(0.09004, 0.724054, -0.683841)) - 0.307662);
  d = max(d, dot(p, vec3(0.080334, 0.727828, -0.681038)) - 0.307558);
  d = max(d, dot(p, vec3(0.295641, 0.90113, -0.317113)) - 0.332762);
  d = max(d, dot(p, vec3(0.0, 0.573462, 0.819232)) - 0.270347);
  d = max(d, dot(p, vec3(0.0, 0.928477, 0.371391)) - 0.319686);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.3);
  d = max(d, dot(p, vec3(0.0, 0.959833, -0.280572)) - 0.319032);
  d = max(d, dot(p, vec3(0.0, 0.759257, -0.650791)) - 0.305872);
  return d;
}
float sdHull322(vec3 p) {
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
float sdHull326(vec3 p) {
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
float sdHull332(vec3 p) {
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
float sdHull336(vec3 p) {
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
float sdLoft349(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.929717, -0.052277, 0.364546)) - 0.138186), dot(p, vec3(0.929721, -0.078085, -0.359892)) - 0.12838), dot(p, vec3(0.930634, -0.053545, 0.362012)) - 0.137861), dot(p, vec3(0.930693, -0.079232, -0.357117)) - 0.12811), dot(p, vec3(0.401959, -0.032603, 0.915077)) - 0.10142), dot(p, vec3(0.404716, -0.033903, 0.913814)) - 0.101252), dot(p, vec3(-0.401959, -0.032603, 0.915077)) - 0.029068), dot(p, vec3(-0.929717, -0.052277, 0.364546)) - -0.029163), dot(p, vec3(-0.404716, -0.033903, 0.913814)) - 0.028403), dot(p, vec3(-0.929721, -0.078085, -0.359892)) - -0.03897), dot(p, vec3(-0.930634, -0.053545, 0.362012)) - -0.029653), dot(p, vec3(-0.930693, -0.079232, -0.357117)) - -0.039415), dot(p, vec3(-0.401961, -0.097708, -0.910429)) - 0.004328), dot(p, vec3(-0.404783, -0.09894, -0.909044)) - 0.003685), dot(p, vec3(0.401961, -0.097708, -0.910429)) - 0.076681), dot(p, vec3(0.404783, -0.09894, -0.909044)) - 0.076546), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.931378, -0.04035, 0.361811)) - 0.141145), dot(p, vec3(0.931329, -0.067967, -0.357781)) - 0.130912), dot(p, vec3(0.933963, -0.043833, 0.354672)) - 0.140687), dot(p, vec3(0.933963, -0.070946, -0.350257)) - 0.130656), dot(p, vec3(0.405182, -0.014038, 0.914128)) - 0.106142), dot(p, vec3(0.413045, -0.0176, 0.910541)) - 0.106168), dot(p, vec3(-0.405182, -0.014038, 0.914128)) - 0.033209), dot(p, vec3(-0.931378, -0.04035, 0.361811)) - -0.026503), dot(p, vec3(-0.413045, -0.0176, 0.910541)) - 0.03182), dot(p, vec3(-0.931329, -0.067967, -0.357781)) - -0.036728), dot(p, vec3(-0.933963, -0.043833, 0.354672)) - -0.027426), dot(p, vec3(-0.933963, -0.070946, -0.350257)) - -0.037458), dot(p, vec3(-0.405132, -0.084132, -0.910379)) - 0.00726), dot(p, vec3(-0.413046, -0.087426, -0.906504)) - 0.005969), dot(p, vec3(0.405132, -0.084132, -0.910379)) - 0.080183), dot(p, vec3(0.413046, -0.087426, -0.906504)) - 0.080317), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull352(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(0.0, -0.768783, -0.63951)) - 0.056166);
  d = max(d, dot(p, vec3(0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, -0.904876, 0.425675)) - 0.058669);
  d = max(d, dot(p, vec3(0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(-0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(-0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(0.0, 0.729865, -0.683591)) - 0.164036);
  d = max(d, dot(p, vec3(0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(-0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(-0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(-0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(-0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(-0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(-0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(-0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(-0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(0.0, 0.480799, 0.876831)) - 0.174464);
  d = max(d, dot(p, vec3(0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(-0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(-0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(-0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(-0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(-0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959305, 0.282373)) - 0.15796);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft354(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.929717, -0.052277, 0.364546)) - -0.029163), dot(p, vec3(0.929721, -0.078085, -0.359892)) - -0.03897), dot(p, vec3(0.930634, -0.053545, 0.362012)) - -0.029653), dot(p, vec3(0.930693, -0.079232, -0.357117)) - -0.039415), dot(p, vec3(0.401959, -0.032603, 0.915077)) - 0.029068), dot(p, vec3(0.404716, -0.033903, 0.913814)) - 0.028403), dot(p, vec3(-0.401959, -0.032603, 0.915077)) - 0.10142), dot(p, vec3(-0.929717, -0.052277, 0.364546)) - 0.138186), dot(p, vec3(-0.404716, -0.033903, 0.913814)) - 0.101252), dot(p, vec3(-0.929721, -0.078085, -0.359892)) - 0.12838), dot(p, vec3(-0.930634, -0.053545, 0.362012)) - 0.137861), dot(p, vec3(-0.930693, -0.079232, -0.357117)) - 0.12811), dot(p, vec3(-0.401961, -0.097708, -0.910429)) - 0.076681), dot(p, vec3(-0.404783, -0.09894, -0.909044)) - 0.076546), dot(p, vec3(0.401961, -0.097708, -0.910429)) - 0.004328), dot(p, vec3(0.404783, -0.09894, -0.909044)) - 0.003685), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.931378, -0.04035, 0.361811)) - -0.026503), dot(p, vec3(0.931329, -0.067967, -0.357781)) - -0.036728), dot(p, vec3(0.933963, -0.043833, 0.354672)) - -0.027426), dot(p, vec3(0.933963, -0.070946, -0.350257)) - -0.037458), dot(p, vec3(0.405182, -0.014038, 0.914128)) - 0.033209), dot(p, vec3(0.413045, -0.0176, 0.910541)) - 0.03182), dot(p, vec3(-0.405182, -0.014038, 0.914128)) - 0.106142), dot(p, vec3(-0.931378, -0.04035, 0.361811)) - 0.141145), dot(p, vec3(-0.413045, -0.0176, 0.910541)) - 0.106168), dot(p, vec3(-0.931329, -0.067967, -0.357781)) - 0.130912), dot(p, vec3(-0.933963, -0.043833, 0.354672)) - 0.140687), dot(p, vec3(-0.933963, -0.070946, -0.350257)) - 0.130656), dot(p, vec3(-0.405132, -0.084132, -0.910379)) - 0.080183), dot(p, vec3(-0.413046, -0.087426, -0.906504)) - 0.080317), dot(p, vec3(0.405132, -0.084132, -0.910379)) - 0.00726), dot(p, vec3(0.413046, -0.087426, -0.906504)) - 0.005969), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull357(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(0.0, -0.768783, -0.63951)) - 0.056166);
  d = max(d, dot(p, vec3(0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, -0.904876, 0.425675)) - 0.058669);
  d = max(d, dot(p, vec3(0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(-0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(-0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(0.0, 0.729865, -0.683591)) - 0.164036);
  d = max(d, dot(p, vec3(0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(-0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(-0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(-0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(-0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(-0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(-0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(-0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(-0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(0.0, 0.480799, 0.876831)) - 0.174464);
  d = max(d, dot(p, vec3(0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(-0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(-0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(-0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(-0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(-0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959305, 0.282373)) - 0.15796);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft359(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.34, dot(p, vec3(-0.894245, 0.141377, 0.424662)) - 0.217975), dot(p, vec3(-0.894245, 0.141377, -0.424662)) - 0.217975), dot(p, vec3(-0.898151, 0.149692, 0.413421)) - 0.221544), dot(p, vec3(-0.898151, 0.149692, -0.413421)) - 0.221544), dot(p, vec3(-0.443191, 0.093484, 0.891539)) - 0.168033), dot(p, vec3(-0.45384, 0.10454, 0.88493)) - 0.172924), dot(p, vec3(0.0, 0.079007, 0.996874)) - 0.150113), dot(p, vec3(0.443191, 0.093484, 0.891539)) - 0.168033), dot(p, vec3(0.894245, 0.141377, 0.424662)) - 0.217975), dot(p, vec3(0.45384, 0.10454, 0.88493)) - 0.172924), dot(p, vec3(0.894245, 0.141377, -0.424662)) - 0.217975), dot(p, vec3(0.898151, 0.149692, 0.413421)) - 0.221544), dot(p, vec3(0.898151, 0.149692, -0.413421)) - 0.221544), dot(p, vec3(0.443191, 0.093484, -0.891539)) - 0.168033), dot(p, vec3(0.45384, 0.10454, -0.88493)) - 0.172924), dot(p, vec3(0.0, 0.079007, -0.996874)) - 0.150113), dot(p, vec3(-0.443191, 0.093484, -0.891539)) - 0.168033), dot(p, vec3(-0.45384, 0.10454, -0.88493)) - 0.172924), dot(p, vec3(0.0, 1.0, 0.0)) - 0.46);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.46, dot(p, vec3(-0.852209, -0.34621, 0.392274)) - -0.014381), dot(p, vec3(-0.852209, -0.34621, -0.392274)) - -0.014381), dot(p, vec3(-0.442918, -0.240751, 0.863633)) - 0.011086), dot(p, vec3(-0.842999, -0.324356, 0.429121)) - -0.002996), dot(p, vec3(0.0, -0.175554, 0.98447)) - 0.0316), dot(p, vec3(-0.411347, -0.209813, 0.887002)) - 0.026326), dot(p, vec3(0.442918, -0.240751, 0.863633)) - 0.011086), dot(p, vec3(0.411347, -0.209813, 0.887002)) - 0.026326), dot(p, vec3(0.852209, -0.34621, 0.392274)) - -0.014381), dot(p, vec3(0.842999, -0.324356, 0.429121)) - -0.002996), dot(p, vec3(0.852209, -0.34621, -0.392274)) - -0.014381), dot(p, vec3(0.442918, -0.240751, -0.863633)) - 0.011086), dot(p, vec3(0.842999, -0.324356, -0.429121)) - -0.002996), dot(p, vec3(0.0, -0.175554, -0.98447)) - 0.0316), dot(p, vec3(0.411347, -0.209813, -0.887002)) - 0.026326), dot(p, vec3(-0.442918, -0.240751, -0.863633)) - 0.011086), dot(p, vec3(-0.411347, -0.209813, -0.887002)) - 0.026326), dot(p, vec3(-0.842999, -0.324356, -0.429121)) - -0.002996), dot(p, vec3(0.0, 1.0, 0.0)) - 0.62);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.62, dot(p, vec3(-0.772915, 0.497798, 0.393445)) - 0.49027), dot(p, vec3(-0.772915, 0.497798, -0.393445)) - 0.49027), dot(p, vec3(-0.774972, 0.506712, 0.377705)) - 0.49628), dot(p, vec3(-0.774972, 0.506712, -0.377705)) - 0.49628), dot(p, vec3(-0.388324, 0.384758, 0.837356)) - 0.386206), dot(p, vec3(-0.399875, 0.398161, 0.825571)) - 0.395672), dot(p, vec3(0.0, 0.34353, 0.939142)) - 0.346965), dot(p, vec3(0.388324, 0.384758, 0.837356)) - 0.386206), dot(p, vec3(0.772915, 0.497798, 0.393445)) - 0.49027), dot(p, vec3(0.399875, 0.398161, 0.825571)) - 0.395672), dot(p, vec3(0.772915, 0.497798, -0.393445)) - 0.49027), dot(p, vec3(0.774972, 0.506712, 0.377705)) - 0.49628), dot(p, vec3(0.774972, 0.506712, -0.377705)) - 0.49628), dot(p, vec3(0.388324, 0.384758, -0.837356)) - 0.386206), dot(p, vec3(0.399875, 0.398161, -0.825571)) - 0.395672), dot(p, vec3(0.0, 0.34353, -0.939142)) - 0.346965), dot(p, vec3(-0.388324, 0.384758, -0.837356)) - 0.386206), dot(p, vec3(-0.399875, 0.398161, -0.825571)) - 0.395672), dot(p, vec3(0.0, 1.0, 0.0)) - 0.75);
  r = min(r, d);
  return r;
}
float sdLoft361(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.39, dot(p, vec3(-0.902723, 0.073319, 0.423928)) - 0.195598), dot(p, vec3(-0.902723, 0.073319, -0.423928)) - 0.195598), dot(p, vec3(-0.903191, 0.075266, 0.422589)) - 0.196444), dot(p, vec3(-0.903191, 0.075266, -0.422589)) - 0.196444), dot(p, vec3(-0.44848, 0.053974, 0.892162)) - 0.155296), dot(p, vec3(-0.449736, 0.056517, 0.891372)) - 0.156416), dot(p, vec3(0.0, 0.047499, 0.998871)) - 0.140122), dot(p, vec3(0.44848, 0.053974, 0.892162)) - 0.155296), dot(p, vec3(0.902723, 0.073319, 0.423928)) - 0.195598), dot(p, vec3(0.449736, 0.056517, 0.891372)) - 0.156416), dot(p, vec3(0.902723, 0.073319, -0.423928)) - 0.195598), dot(p, vec3(0.903191, 0.075266, 0.422589)) - 0.196444), dot(p, vec3(0.903191, 0.075266, -0.422589)) - 0.196444), dot(p, vec3(0.44848, 0.053974, -0.892162)) - 0.155296), dot(p, vec3(0.449736, 0.056517, -0.891372)) - 0.156416), dot(p, vec3(0.0, 0.047499, -0.998871)) - 0.140122), dot(p, vec3(-0.44848, 0.053974, -0.892162)) - 0.155296), dot(p, vec3(-0.449736, 0.056517, -0.891372)) - 0.156416), dot(p, vec3(0.0, 1.0, 0.0)) - 0.45);
  r = min(r, d);
  return r;
}
float sdHull364(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.032332;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.032332);
  return d;
}
float sdHull367(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.18;
  d = max(d, dot(p, vec3(0.91951, 0.25542, 0.298767)) - 0.229878);
  d = max(d, dot(p, vec3(0.91951, 0.25542, -0.298767)) - 0.229878);
  d = max(d, dot(p, vec3(0.568289, 0.25542, 0.782182)) - 0.229878);
  d = max(d, dot(p, vec3(0.0, 0.25542, 0.96683)) - 0.229878);
  d = max(d, dot(p, vec3(-0.568289, 0.25542, 0.782182)) - 0.229878);
  d = max(d, dot(p, vec3(-0.91951, 0.25542, 0.298767)) - 0.229878);
  d = max(d, dot(p, vec3(-0.91951, 0.25542, -0.298767)) - 0.229878);
  d = max(d, dot(p, vec3(-0.568289, 0.25542, -0.782182)) - 0.229878);
  d = max(d, dot(p, vec3(0.0, 0.25542, -0.96683)) - 0.229878);
  d = max(d, dot(p, vec3(0.568289, 0.25542, -0.782182)) - 0.229878);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.18);
  return d;
}
float sdHull370(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.101036;
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.101036);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.024749);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.024749);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.106066);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.106066);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.101036);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.101036);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.106066);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.106066);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.101036);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.101036);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.024749);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.024749);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.101036);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.101036);
  return d;
}
float sdHull374(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.095811;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.094277);
  return d;
}
float sdLoft377(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.173494, 0.983135, -0.057831)) - 0.643086, dot(p, vec3(0.652424, 0.05028, -0.756185)) - 0.262095), dot(p, vec3(-0.061309, -0.089489, -0.994099)) - -0.021313), dot(p, vec3(0.254729, -0.081089, -0.963607)) - 0.071139), dot(p, vec3(0.985961, 0.149359, -0.07465)) - 0.418171), dot(p, vec3(0.857724, 0.051897, -0.511485)) - 0.321017), dot(p, vec3(0.743965, 0.149447, 0.651293)) - 0.355313), dot(p, vec3(0.962926, 0.114672, 0.244179)) - 0.392321), dot(p, vec3(0.068272, 0.050032, 0.996411)) - 0.110042), dot(p, vec3(0.508603, 0.069793, 0.858168)) - 0.242785), dot(p, vec3(-0.645336, -0.090385, 0.758532)) - -0.173789), dot(p, vec3(-0.234753, -0.055833, 0.97045)) - -0.038436), dot(p, vec3(-0.978939, -0.189079, 0.076986)) - -0.329611), dot(p, vec3(-0.832611, -0.187923, 0.521002)) - -0.286362), dot(p, vec3(-0.737068, -0.188519, -0.648993)) - -0.266332), dot(p, vec3(-0.940605, -0.250167, -0.229517)) - -0.358022), dot(p, vec3(-0.491403, -0.20618, -0.846175)) - -0.210431), dot(p, vec3(0.131519, -0.986394, 0.098639)) - -0.483662);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.131519, 0.986394, -0.098639)) - 0.483662, dot(p, vec3(0.864968, -0.031835, -0.500816)) - 0.27862), dot(p, vec3(0.262782, -0.148042, -0.95343)) - 0.037913), dot(p, vec3(0.661527, -0.139168, -0.736895)) - 0.163982), dot(p, vec3(0.965017, 0.08975, 0.246349)) - 0.379677), dot(p, vec3(0.997891, -0.010605, -0.064039)) - 0.3365), dot(p, vec3(0.500125, 0.146674, 0.853441)) - 0.281197), dot(p, vec3(0.753115, 0.078598, 0.653176)) - 0.320257), dot(p, vec3(-0.257763, 0.105226, 0.960461)) - 0.040467), dot(p, vec3(0.070773, 0.077167, 0.994503)) - 0.125217), dot(p, vec3(-0.862045, -0.010901, 0.506714)) - -0.200883), dot(p, vec3(-0.649456, -0.014563, 0.76026)) - -0.134572), dot(p, vec3(-0.960857, -0.134209, -0.242365)) - -0.302322), dot(p, vec3(-0.985695, -0.143871, 0.087783)) - -0.307342), dot(p, vec3(-0.493779, -0.191204, -0.848306)) - -0.203168), dot(p, vec3(-0.741079, -0.234436, -0.629159)) - -0.291688), dot(p, vec3(-0.05886, -0.232261, -0.970871)) - -0.096396), dot(p, vec3(0.07581, -0.985527, 0.15162)) - -0.366919);
  r = min(r, d);
  return r;
}
float sdHull380(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.049075;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.049075);
  return d;
}
float sdLoft382(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(0.569803, -0.683763, -0.455842)) - -0.11624, dot(p, vec3(0.760611, 0.417538, 0.497124)) - 0.391787), dot(p, vec3(0.228338, -0.309901, 0.922942)) - 0.035874), dot(p, vec3(0.487424, 0.781258, -0.389939)) - 0.382329), dot(p, vec3(-0.318036, 0.417538, -0.851184)) - 0.016958), dot(p, vec3(-0.850309, -0.309901, -0.425366)) - -0.338956), dot(p, vec3(-0.577122, -0.673621, 0.461697)) - -0.329497), dot(p, vec3(-0.569803, 0.683763, 0.455842)) - 0.160115);
  r = min(r, d);
  return r;
}
float sdHull386(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.095811;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.094277);
  return d;
}
float sdLoft389(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.173494, 0.983135, -0.057831)) - 0.643086, dot(p, vec3(-0.068272, 0.050032, 0.996411)) - 0.110042), dot(p, vec3(0.645336, -0.090385, 0.758532)) - -0.173789), dot(p, vec3(0.234753, -0.055833, 0.97045)) - -0.038436), dot(p, vec3(-0.743965, 0.149447, 0.651293)) - 0.355313), dot(p, vec3(-0.508603, 0.069793, 0.858168)) - 0.242785), dot(p, vec3(-0.985961, 0.149359, -0.07465)) - 0.418171), dot(p, vec3(-0.962926, 0.114672, 0.244179)) - 0.392321), dot(p, vec3(-0.652424, 0.05028, -0.756185)) - 0.262095), dot(p, vec3(-0.857724, 0.051897, -0.511485)) - 0.321017), dot(p, vec3(0.061309, -0.089489, -0.994099)) - -0.021313), dot(p, vec3(-0.254729, -0.081089, -0.963607)) - 0.071139), dot(p, vec3(0.737068, -0.188519, -0.648993)) - -0.266332), dot(p, vec3(0.491403, -0.20618, -0.846175)) - -0.210431), dot(p, vec3(0.978939, -0.189079, 0.076986)) - -0.329611), dot(p, vec3(0.940605, -0.250167, -0.229517)) - -0.358022), dot(p, vec3(0.832611, -0.187923, 0.521002)) - -0.286362), dot(p, vec3(-0.131519, -0.986394, 0.098639)) - -0.483662);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.131519, 0.986394, -0.098639)) - 0.483662, dot(p, vec3(0.257763, 0.105226, 0.960461)) - 0.040467), dot(p, vec3(0.862045, -0.010901, 0.506714)) - -0.200883), dot(p, vec3(0.649456, -0.014563, 0.76026)) - -0.134572), dot(p, vec3(-0.500125, 0.146674, 0.853441)) - 0.281197), dot(p, vec3(-0.070773, 0.077167, 0.994503)) - 0.125217), dot(p, vec3(-0.965017, 0.08975, 0.246349)) - 0.379677), dot(p, vec3(-0.753115, 0.078598, 0.653176)) - 0.320257), dot(p, vec3(-0.864968, -0.031835, -0.500816)) - 0.27862), dot(p, vec3(-0.997891, -0.010605, -0.064039)) - 0.3365), dot(p, vec3(-0.262782, -0.148042, -0.95343)) - 0.037913), dot(p, vec3(-0.661527, -0.139168, -0.736895)) - 0.163982), dot(p, vec3(0.493779, -0.191204, -0.848306)) - -0.203168), dot(p, vec3(0.05886, -0.232261, -0.970871)) - -0.096396), dot(p, vec3(0.960857, -0.134209, -0.242365)) - -0.302322), dot(p, vec3(0.741079, -0.234436, -0.629159)) - -0.291688), dot(p, vec3(0.985695, -0.143871, 0.087783)) - -0.307342), dot(p, vec3(-0.07581, -0.985527, 0.15162)) - -0.366919);
  r = min(r, d);
  return r;
}
float sdHull392(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.049075;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.049075);
  return d;
}
float sdLoft394(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(-0.569803, -0.683763, -0.455842)) - -0.11624, dot(p, vec3(0.318036, 0.417538, -0.851184)) - 0.016958), dot(p, vec3(0.850309, -0.309901, -0.425366)) - -0.338956), dot(p, vec3(-0.487424, 0.781258, -0.389939)) - 0.382329), dot(p, vec3(-0.760611, 0.417538, 0.497124)) - 0.391787), dot(p, vec3(-0.228338, -0.309901, 0.922942)) - 0.035874), dot(p, vec3(0.577122, -0.673621, 0.461697)) - -0.329497), dot(p, vec3(0.569803, 0.683763, 0.455842)) - 0.160115);
  r = min(r, d);
  return r;
}
float sdHull397(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.207846;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.207846);
  return d;
}
float sdHull402(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.033282;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.032105);
  return d;
}
float sdHull406(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.928477, 0.371391)) - 0.0);
  d = max(d, dot(p, vec3(-0.747392, 0.46979, 0.46979)) - 0.016443);
  d = max(d, dot(p, vec3(0.747392, 0.46979, 0.46979)) - 0.016443);
  return d;
}
float sdHull410(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.021651;
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.021651);
  return d;
}
float sdHull415(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.024249;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.024249);
  return d;
}
float sdHull418(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.020496;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.020496);
  return d;
}
float sdHull421(vec3 p) {
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
float sdHull426(vec3 p) {
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
float sdHull429(vec3 p) {
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
float sdHull432(vec3 p) {
  float d = dot(p, vec3(0.0, -0.196116, -0.980581)) - 0.0;
  d = max(d, dot(p, vec3(0.0, 0.928477, 0.371391)) - 0.0);
  d = max(d, dot(p, vec3(-0.36541, -0.051634, 0.929413)) - 0.047503);
  d = max(d, dot(p, vec3(0.36541, -0.051634, 0.929413)) - 0.047503);
  return d;
}
float sdHull438(vec3 p) {
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
float sdHull442(vec3 p) {
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
float sdHull445(vec3 p) {
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
float sdLoft466(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.929717, -0.052277, 0.364546)) - 0.138186), dot(p, vec3(0.929721, -0.078085, -0.359892)) - 0.12838), dot(p, vec3(0.930634, -0.053545, 0.362012)) - 0.137861), dot(p, vec3(0.930693, -0.079232, -0.357117)) - 0.12811), dot(p, vec3(0.401959, -0.032603, 0.915077)) - 0.10142), dot(p, vec3(0.404716, -0.033903, 0.913814)) - 0.101252), dot(p, vec3(-0.401959, -0.032603, 0.915077)) - 0.029068), dot(p, vec3(-0.929717, -0.052277, 0.364546)) - -0.029163), dot(p, vec3(-0.404716, -0.033903, 0.913814)) - 0.028403), dot(p, vec3(-0.929721, -0.078085, -0.359892)) - -0.03897), dot(p, vec3(-0.930634, -0.053545, 0.362012)) - -0.029653), dot(p, vec3(-0.930693, -0.079232, -0.357117)) - -0.039415), dot(p, vec3(-0.401961, -0.097708, -0.910429)) - 0.004328), dot(p, vec3(-0.404783, -0.09894, -0.909044)) - 0.003685), dot(p, vec3(0.401961, -0.097708, -0.910429)) - 0.076681), dot(p, vec3(0.404783, -0.09894, -0.909044)) - 0.076546), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.931378, -0.04035, 0.361811)) - 0.141145), dot(p, vec3(0.931329, -0.067967, -0.357781)) - 0.130912), dot(p, vec3(0.933963, -0.043833, 0.354672)) - 0.140687), dot(p, vec3(0.933963, -0.070946, -0.350257)) - 0.130656), dot(p, vec3(0.405182, -0.014038, 0.914128)) - 0.106142), dot(p, vec3(0.413045, -0.0176, 0.910541)) - 0.106168), dot(p, vec3(-0.405182, -0.014038, 0.914128)) - 0.033209), dot(p, vec3(-0.931378, -0.04035, 0.361811)) - -0.026503), dot(p, vec3(-0.413045, -0.0176, 0.910541)) - 0.03182), dot(p, vec3(-0.931329, -0.067967, -0.357781)) - -0.036728), dot(p, vec3(-0.933963, -0.043833, 0.354672)) - -0.027426), dot(p, vec3(-0.933963, -0.070946, -0.350257)) - -0.037458), dot(p, vec3(-0.405132, -0.084132, -0.910379)) - 0.00726), dot(p, vec3(-0.413046, -0.087426, -0.906504)) - 0.005969), dot(p, vec3(0.405132, -0.084132, -0.910379)) - 0.080183), dot(p, vec3(0.413046, -0.087426, -0.906504)) - 0.080317), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull469(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(0.0, -0.768783, -0.63951)) - 0.056166);
  d = max(d, dot(p, vec3(0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, -0.904876, 0.425675)) - 0.058669);
  d = max(d, dot(p, vec3(0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(-0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(-0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(0.0, 0.729865, -0.683591)) - 0.164036);
  d = max(d, dot(p, vec3(0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(-0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(-0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(-0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(-0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(-0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(-0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(-0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(-0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(0.0, 0.480799, 0.876831)) - 0.174464);
  d = max(d, dot(p, vec3(0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(-0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(-0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(-0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(-0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(-0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959305, 0.282373)) - 0.15796);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft471(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999363, -0.035692)) - 0.379758, dot(p, vec3(0.929717, -0.052277, 0.364546)) - -0.029163), dot(p, vec3(0.929721, -0.078085, -0.359892)) - -0.03897), dot(p, vec3(0.930634, -0.053545, 0.362012)) - -0.029653), dot(p, vec3(0.930693, -0.079232, -0.357117)) - -0.039415), dot(p, vec3(0.401959, -0.032603, 0.915077)) - 0.029068), dot(p, vec3(0.404716, -0.033903, 0.913814)) - 0.028403), dot(p, vec3(-0.401959, -0.032603, 0.915077)) - 0.10142), dot(p, vec3(-0.929717, -0.052277, 0.364546)) - 0.138186), dot(p, vec3(-0.404716, -0.033903, 0.913814)) - 0.101252), dot(p, vec3(-0.929721, -0.078085, -0.359892)) - 0.12838), dot(p, vec3(-0.930634, -0.053545, 0.362012)) - 0.137861), dot(p, vec3(-0.930693, -0.079232, -0.357117)) - 0.12811), dot(p, vec3(-0.401961, -0.097708, -0.910429)) - 0.076681), dot(p, vec3(-0.404783, -0.09894, -0.909044)) - 0.076546), dot(p, vec3(0.401961, -0.097708, -0.910429)) - 0.004328), dot(p, vec3(0.404783, -0.09894, -0.909044)) - 0.003685), dot(p, vec3(0.0, -0.999315, 0.037012)) - -0.239651);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, 0.999315, -0.037012)) - 0.239651, dot(p, vec3(0.931378, -0.04035, 0.361811)) - -0.026503), dot(p, vec3(0.931329, -0.067967, -0.357781)) - -0.036728), dot(p, vec3(0.933963, -0.043833, 0.354672)) - -0.027426), dot(p, vec3(0.933963, -0.070946, -0.350257)) - -0.037458), dot(p, vec3(0.405182, -0.014038, 0.914128)) - 0.033209), dot(p, vec3(0.413045, -0.0176, 0.910541)) - 0.03182), dot(p, vec3(-0.405182, -0.014038, 0.914128)) - 0.106142), dot(p, vec3(-0.931378, -0.04035, 0.361811)) - 0.141145), dot(p, vec3(-0.413045, -0.0176, 0.910541)) - 0.106168), dot(p, vec3(-0.931329, -0.067967, -0.357781)) - 0.130912), dot(p, vec3(-0.933963, -0.043833, 0.354672)) - 0.140687), dot(p, vec3(-0.933963, -0.070946, -0.350257)) - 0.130656), dot(p, vec3(-0.405132, -0.084132, -0.910379)) - 0.080183), dot(p, vec3(-0.413046, -0.087426, -0.906504)) - 0.080317), dot(p, vec3(0.405132, -0.084132, -0.910379)) - 0.00726), dot(p, vec3(0.413046, -0.087426, -0.906504)) - 0.005969), dot(p, vec3(0.0, -0.999261, 0.038433)) - -0.109534);
  r = min(r, d);
  return r;
}
float sdHull474(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(0.0, -0.768783, -0.63951)) - 0.056166);
  d = max(d, dot(p, vec3(0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, -0.904876, 0.425675)) - 0.058669);
  d = max(d, dot(p, vec3(0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.636325, -0.771421, 0.0)) - 0.051692);
  d = max(d, dot(p, vec3(-0.585833, -0.624302, 0.516766)) - 0.118815);
  d = max(d, dot(p, vec3(-0.583729, -0.55039, -0.596935)) - 0.099846);
  d = max(d, dot(p, vec3(-0.726486, -0.687156, -0.005939)) - 0.059538);
  d = max(d, dot(p, vec3(0.0, 0.066519, -0.997785)) - 0.099779);
  d = max(d, dot(p, vec3(0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(0.0, 0.729865, -0.683591)) - 0.164036);
  d = max(d, dot(p, vec3(0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.725114, 0.092721, -0.682358)) - 0.125601);
  d = max(d, dot(p, vec3(-0.726364, 0.092937, -0.680998)) - 0.125595);
  d = max(d, dot(p, vec3(-0.56204, 0.603969, -0.565095)) - 0.175034);
  d = max(d, dot(p, vec3(-0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(-0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(-0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(-0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(-0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(-0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(-0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.998205, 0.059892, 0.0)) - 0.089838);
  d = max(d, dot(p, vec3(0.834031, 0.551611, 0.010831)) - 0.144792);
  d = max(d, dot(p, vec3(0.706792, 0.707311, 0.012523)) - 0.156191);
  d = max(d, dot(p, vec3(0.626227, 0.779641, 0.0)) - 0.160778);
  d = max(d, dot(p, vec3(0.995928, 0.082893, 0.035441)) - 0.094637);
  d = max(d, dot(p, vec3(0.624982, -0.545748, 0.558172)) - 0.128523);
  d = max(d, dot(p, vec3(0.993267, 0.09693, 0.063438)) - 0.098322);
  d = max(d, dot(p, vec3(0.0, -0.124035, 0.992278)) - 0.148842);
  d = max(d, dot(p, vec3(0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(0.0, 0.480799, 0.876831)) - 0.174464);
  d = max(d, dot(p, vec3(0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.426385, -0.001752, 0.90454)) - 0.168896);
  d = max(d, dot(p, vec3(-0.603568, 0.114732, 0.789014)) - 0.169427);
  d = max(d, dot(p, vec3(-0.508225, 0.363045, 0.780964)) - 0.180589);
  d = max(d, dot(p, vec3(-0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(-0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(-0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(-0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.957638, 0.188225, 0.217945)) - 0.118879);
  d = max(d, dot(p, vec3(0.534779, 0.643175, 0.54803)) - 0.170747);
  d = max(d, dot(p, vec3(0.394957, 0.875161, 0.279468)) - 0.172839);
  d = max(d, dot(p, vec3(0.283614, 0.772044, 0.56878)) - 0.169718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.15);
  d = max(d, dot(p, vec3(0.0, 0.959305, 0.282373)) - 0.15796);
  d = max(d, dot(p, vec3(0.0, 0.819232, 0.573462)) - 0.157293);
  return d;
}
float sdLoft476(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.34, dot(p, vec3(-0.894245, 0.141377, 0.424662)) - 0.217975), dot(p, vec3(-0.894245, 0.141377, -0.424662)) - 0.217975), dot(p, vec3(-0.898151, 0.149692, 0.413421)) - 0.221544), dot(p, vec3(-0.898151, 0.149692, -0.413421)) - 0.221544), dot(p, vec3(-0.443191, 0.093484, 0.891539)) - 0.168033), dot(p, vec3(-0.45384, 0.10454, 0.88493)) - 0.172924), dot(p, vec3(0.0, 0.079007, 0.996874)) - 0.150113), dot(p, vec3(0.443191, 0.093484, 0.891539)) - 0.168033), dot(p, vec3(0.894245, 0.141377, 0.424662)) - 0.217975), dot(p, vec3(0.45384, 0.10454, 0.88493)) - 0.172924), dot(p, vec3(0.894245, 0.141377, -0.424662)) - 0.217975), dot(p, vec3(0.898151, 0.149692, 0.413421)) - 0.221544), dot(p, vec3(0.898151, 0.149692, -0.413421)) - 0.221544), dot(p, vec3(0.443191, 0.093484, -0.891539)) - 0.168033), dot(p, vec3(0.45384, 0.10454, -0.88493)) - 0.172924), dot(p, vec3(0.0, 0.079007, -0.996874)) - 0.150113), dot(p, vec3(-0.443191, 0.093484, -0.891539)) - 0.168033), dot(p, vec3(-0.45384, 0.10454, -0.88493)) - 0.172924), dot(p, vec3(0.0, 1.0, 0.0)) - 0.46);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.46, dot(p, vec3(-0.852209, -0.34621, 0.392274)) - -0.014381), dot(p, vec3(-0.852209, -0.34621, -0.392274)) - -0.014381), dot(p, vec3(-0.442918, -0.240751, 0.863633)) - 0.011086), dot(p, vec3(-0.842999, -0.324356, 0.429121)) - -0.002996), dot(p, vec3(0.0, -0.175554, 0.98447)) - 0.0316), dot(p, vec3(-0.411347, -0.209813, 0.887002)) - 0.026326), dot(p, vec3(0.442918, -0.240751, 0.863633)) - 0.011086), dot(p, vec3(0.411347, -0.209813, 0.887002)) - 0.026326), dot(p, vec3(0.852209, -0.34621, 0.392274)) - -0.014381), dot(p, vec3(0.842999, -0.324356, 0.429121)) - -0.002996), dot(p, vec3(0.852209, -0.34621, -0.392274)) - -0.014381), dot(p, vec3(0.442918, -0.240751, -0.863633)) - 0.011086), dot(p, vec3(0.842999, -0.324356, -0.429121)) - -0.002996), dot(p, vec3(0.0, -0.175554, -0.98447)) - 0.0316), dot(p, vec3(0.411347, -0.209813, -0.887002)) - 0.026326), dot(p, vec3(-0.442918, -0.240751, -0.863633)) - 0.011086), dot(p, vec3(-0.411347, -0.209813, -0.887002)) - 0.026326), dot(p, vec3(-0.842999, -0.324356, -0.429121)) - -0.002996), dot(p, vec3(0.0, 1.0, 0.0)) - 0.62);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.62, dot(p, vec3(-0.772915, 0.497798, 0.393445)) - 0.49027), dot(p, vec3(-0.772915, 0.497798, -0.393445)) - 0.49027), dot(p, vec3(-0.774972, 0.506712, 0.377705)) - 0.49628), dot(p, vec3(-0.774972, 0.506712, -0.377705)) - 0.49628), dot(p, vec3(-0.388324, 0.384758, 0.837356)) - 0.386206), dot(p, vec3(-0.399875, 0.398161, 0.825571)) - 0.395672), dot(p, vec3(0.0, 0.34353, 0.939142)) - 0.346965), dot(p, vec3(0.388324, 0.384758, 0.837356)) - 0.386206), dot(p, vec3(0.772915, 0.497798, 0.393445)) - 0.49027), dot(p, vec3(0.399875, 0.398161, 0.825571)) - 0.395672), dot(p, vec3(0.772915, 0.497798, -0.393445)) - 0.49027), dot(p, vec3(0.774972, 0.506712, 0.377705)) - 0.49628), dot(p, vec3(0.774972, 0.506712, -0.377705)) - 0.49628), dot(p, vec3(0.388324, 0.384758, -0.837356)) - 0.386206), dot(p, vec3(0.399875, 0.398161, -0.825571)) - 0.395672), dot(p, vec3(0.0, 0.34353, -0.939142)) - 0.346965), dot(p, vec3(-0.388324, 0.384758, -0.837356)) - 0.386206), dot(p, vec3(-0.399875, 0.398161, -0.825571)) - 0.395672), dot(p, vec3(0.0, 1.0, 0.0)) - 0.75);
  r = min(r, d);
  return r;
}
float sdLoft478(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.0, -1.0, 0.0)) - -0.39, dot(p, vec3(-0.902723, 0.073319, 0.423928)) - 0.195598), dot(p, vec3(-0.902723, 0.073319, -0.423928)) - 0.195598), dot(p, vec3(-0.903191, 0.075266, 0.422589)) - 0.196444), dot(p, vec3(-0.903191, 0.075266, -0.422589)) - 0.196444), dot(p, vec3(-0.44848, 0.053974, 0.892162)) - 0.155296), dot(p, vec3(-0.449736, 0.056517, 0.891372)) - 0.156416), dot(p, vec3(0.0, 0.047499, 0.998871)) - 0.140122), dot(p, vec3(0.44848, 0.053974, 0.892162)) - 0.155296), dot(p, vec3(0.902723, 0.073319, 0.423928)) - 0.195598), dot(p, vec3(0.449736, 0.056517, 0.891372)) - 0.156416), dot(p, vec3(0.902723, 0.073319, -0.423928)) - 0.195598), dot(p, vec3(0.903191, 0.075266, 0.422589)) - 0.196444), dot(p, vec3(0.903191, 0.075266, -0.422589)) - 0.196444), dot(p, vec3(0.44848, 0.053974, -0.892162)) - 0.155296), dot(p, vec3(0.449736, 0.056517, -0.891372)) - 0.156416), dot(p, vec3(0.0, 0.047499, -0.998871)) - 0.140122), dot(p, vec3(-0.44848, 0.053974, -0.892162)) - 0.155296), dot(p, vec3(-0.449736, 0.056517, -0.891372)) - 0.156416), dot(p, vec3(0.0, 1.0, 0.0)) - 0.45);
  r = min(r, d);
  return r;
}
float sdHull481(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.032332;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.015);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.023335);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.032332);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.037477);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.032332);
  return d;
}
float sdHull484(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.06;
  d = max(d, dot(p, vec3(0.939329, 0.156555, 0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(0.939329, 0.156555, -0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(0.580537, 0.156555, 0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 0.156555, 0.987669)) - 0.197259);
  d = max(d, dot(p, vec3(-0.580537, 0.156555, 0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(-0.939329, 0.156555, 0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(-0.939329, 0.156555, -0.305207)) - 0.197259);
  d = max(d, dot(p, vec3(-0.580537, 0.156555, -0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 0.156555, -0.987669)) - 0.197259);
  d = max(d, dot(p, vec3(0.580537, 0.156555, -0.799041)) - 0.197259);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.06);
  return d;
}
float sdHull488(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.095811;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.094277);
  return d;
}
float sdLoft491(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.173494, 0.983135, -0.057831)) - 0.643086, dot(p, vec3(0.652424, 0.05028, -0.756185)) - 0.262095), dot(p, vec3(-0.061309, -0.089489, -0.994099)) - -0.021313), dot(p, vec3(0.254729, -0.081089, -0.963607)) - 0.071139), dot(p, vec3(0.985961, 0.149359, -0.07465)) - 0.418171), dot(p, vec3(0.857724, 0.051897, -0.511485)) - 0.321017), dot(p, vec3(0.743965, 0.149447, 0.651293)) - 0.355313), dot(p, vec3(0.962926, 0.114672, 0.244179)) - 0.392321), dot(p, vec3(0.068272, 0.050032, 0.996411)) - 0.110042), dot(p, vec3(0.508603, 0.069793, 0.858168)) - 0.242785), dot(p, vec3(-0.645336, -0.090385, 0.758532)) - -0.173789), dot(p, vec3(-0.234753, -0.055833, 0.97045)) - -0.038436), dot(p, vec3(-0.978939, -0.189079, 0.076986)) - -0.329611), dot(p, vec3(-0.832611, -0.187923, 0.521002)) - -0.286362), dot(p, vec3(-0.737068, -0.188519, -0.648993)) - -0.266332), dot(p, vec3(-0.940605, -0.250167, -0.229517)) - -0.358022), dot(p, vec3(-0.491403, -0.20618, -0.846175)) - -0.210431), dot(p, vec3(0.131519, -0.986394, 0.098639)) - -0.483662);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(-0.131519, 0.986394, -0.098639)) - 0.483662, dot(p, vec3(0.864968, -0.031835, -0.500816)) - 0.27862), dot(p, vec3(0.262782, -0.148042, -0.95343)) - 0.037913), dot(p, vec3(0.661527, -0.139168, -0.736895)) - 0.163982), dot(p, vec3(0.965017, 0.08975, 0.246349)) - 0.379677), dot(p, vec3(0.997891, -0.010605, -0.064039)) - 0.3365), dot(p, vec3(0.500125, 0.146674, 0.853441)) - 0.281197), dot(p, vec3(0.753115, 0.078598, 0.653176)) - 0.320257), dot(p, vec3(-0.257763, 0.105226, 0.960461)) - 0.040467), dot(p, vec3(0.070773, 0.077167, 0.994503)) - 0.125217), dot(p, vec3(-0.862045, -0.010901, 0.506714)) - -0.200883), dot(p, vec3(-0.649456, -0.014563, 0.76026)) - -0.134572), dot(p, vec3(-0.960857, -0.134209, -0.242365)) - -0.302322), dot(p, vec3(-0.985695, -0.143871, 0.087783)) - -0.307342), dot(p, vec3(-0.493779, -0.191204, -0.848306)) - -0.203168), dot(p, vec3(-0.741079, -0.234436, -0.629159)) - -0.291688), dot(p, vec3(-0.05886, -0.232261, -0.970871)) - -0.096396), dot(p, vec3(0.07581, -0.985527, 0.15162)) - -0.366919);
  r = min(r, d);
  return r;
}
float sdHull494(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.049075;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.049075);
  return d;
}
float sdLoft496(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(0.569803, -0.683763, -0.455842)) - -0.11624, dot(p, vec3(0.760611, 0.417538, 0.497124)) - 0.391787), dot(p, vec3(0.228338, -0.309901, 0.922942)) - 0.035874), dot(p, vec3(0.487424, 0.781258, -0.389939)) - 0.382329), dot(p, vec3(-0.318036, 0.417538, -0.851184)) - 0.016958), dot(p, vec3(-0.850309, -0.309901, -0.425366)) - -0.338956), dot(p, vec3(-0.577122, -0.673621, 0.461697)) - -0.329497), dot(p, vec3(-0.569803, 0.683763, 0.455842)) - 0.160115);
  r = min(r, d);
  return r;
}
float sdHull500(vec3 p) {
  float d = dot(p, vec3(0.377964, -0.912487, 0.156558)) - 0.095811;
  d = max(d, dot(p, vec3(0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, -0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, -0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, 0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, 0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.377964, 0.912487, -0.156558)) - 0.095811);
  d = max(d, dot(p, vec3(-0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.156558, 0.912487, -0.377964)) - 0.095811);
  d = max(d, dot(p, vec3(0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, -0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, -0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, -0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, -0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, -0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, 0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, 0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, 0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(-0.956082, 0.293099, 0.0)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, 0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(-0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(-0.829525, 0.440257, -0.343601)) - 0.094277);
  d = max(d, dot(p, vec3(0.0, 0.293099, -0.956082)) - 0.092747);
  d = max(d, dot(p, vec3(-0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.676052, 0.293099, -0.676052)) - 0.092747);
  d = max(d, dot(p, vec3(0.343601, 0.440257, -0.829525)) - 0.094277);
  d = max(d, dot(p, vec3(0.829525, 0.440257, -0.343601)) - 0.094277);
  return d;
}
float sdLoft503(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.173494, 0.983135, -0.057831)) - 0.643086, dot(p, vec3(-0.068272, 0.050032, 0.996411)) - 0.110042), dot(p, vec3(0.645336, -0.090385, 0.758532)) - -0.173789), dot(p, vec3(0.234753, -0.055833, 0.97045)) - -0.038436), dot(p, vec3(-0.743965, 0.149447, 0.651293)) - 0.355313), dot(p, vec3(-0.508603, 0.069793, 0.858168)) - 0.242785), dot(p, vec3(-0.985961, 0.149359, -0.07465)) - 0.418171), dot(p, vec3(-0.962926, 0.114672, 0.244179)) - 0.392321), dot(p, vec3(-0.652424, 0.05028, -0.756185)) - 0.262095), dot(p, vec3(-0.857724, 0.051897, -0.511485)) - 0.321017), dot(p, vec3(0.061309, -0.089489, -0.994099)) - -0.021313), dot(p, vec3(-0.254729, -0.081089, -0.963607)) - 0.071139), dot(p, vec3(0.737068, -0.188519, -0.648993)) - -0.266332), dot(p, vec3(0.491403, -0.20618, -0.846175)) - -0.210431), dot(p, vec3(0.978939, -0.189079, 0.076986)) - -0.329611), dot(p, vec3(0.940605, -0.250167, -0.229517)) - -0.358022), dot(p, vec3(0.832611, -0.187923, 0.521002)) - -0.286362), dot(p, vec3(-0.131519, -0.986394, 0.098639)) - -0.483662);
  r = min(r, d);
  d = max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(max(dot(p, vec3(0.131519, 0.986394, -0.098639)) - 0.483662, dot(p, vec3(0.257763, 0.105226, 0.960461)) - 0.040467), dot(p, vec3(0.862045, -0.010901, 0.506714)) - -0.200883), dot(p, vec3(0.649456, -0.014563, 0.76026)) - -0.134572), dot(p, vec3(-0.500125, 0.146674, 0.853441)) - 0.281197), dot(p, vec3(-0.070773, 0.077167, 0.994503)) - 0.125217), dot(p, vec3(-0.965017, 0.08975, 0.246349)) - 0.379677), dot(p, vec3(-0.753115, 0.078598, 0.653176)) - 0.320257), dot(p, vec3(-0.864968, -0.031835, -0.500816)) - 0.27862), dot(p, vec3(-0.997891, -0.010605, -0.064039)) - 0.3365), dot(p, vec3(-0.262782, -0.148042, -0.95343)) - 0.037913), dot(p, vec3(-0.661527, -0.139168, -0.736895)) - 0.163982), dot(p, vec3(0.493779, -0.191204, -0.848306)) - -0.203168), dot(p, vec3(0.05886, -0.232261, -0.970871)) - -0.096396), dot(p, vec3(0.960857, -0.134209, -0.242365)) - -0.302322), dot(p, vec3(0.741079, -0.234436, -0.629159)) - -0.291688), dot(p, vec3(0.985695, -0.143871, 0.087783)) - -0.307342), dot(p, vec3(-0.07581, -0.985527, 0.15162)) - -0.366919);
  r = min(r, d);
  return r;
}
float sdHull506(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.049075;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.045);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.05);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.045962);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.049075);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.049497);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.049075);
  return d;
}
float sdLoft508(vec3 p) {
  float r = 1e10, d;
  d = max(max(max(max(max(max(max(dot(p, vec3(-0.569803, -0.683763, -0.455842)) - -0.11624, dot(p, vec3(0.318036, 0.417538, -0.851184)) - 0.016958), dot(p, vec3(0.850309, -0.309901, -0.425366)) - -0.338956), dot(p, vec3(-0.487424, 0.781258, -0.389939)) - 0.382329), dot(p, vec3(-0.760611, 0.417538, 0.497124)) - 0.391787), dot(p, vec3(-0.228338, -0.309901, 0.922942)) - 0.035874), dot(p, vec3(0.577122, -0.673621, 0.461697)) - -0.329497), dot(p, vec3(0.569803, 0.683763, 0.455842)) - 0.160115);
  r = min(r, d);
  return r;
}
float sdHull511(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.207846;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.17);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.180312);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.19);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.207846);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.194454);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.207846);
  return d;
}
float sdHull516(vec3 p) {
  float d = dot(p, vec3(0.480384, -0.83205, 0.27735)) - 0.033282;
  d = max(d, dot(p, vec3(0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, 0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, 0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(-0.480384, -0.83205, -0.27735)) - 0.033282);
  d = max(d, dot(p, vec3(0.0, -0.83205, -0.5547)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, 0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(-0.5547, 0.83205, 0.0)) - 0.033282);
  d = max(d, dot(p, vec3(-0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.27735, 0.83205, -0.480384)) - 0.033282);
  d = max(d, dot(p, vec3(0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, 0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, 0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, 0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(-0.860254, -0.115252, -0.496668)) - 0.032105);
  d = max(d, dot(p, vec3(-0.993336, 0.115252, 0.0)) - 0.032105);
  d = max(d, dot(p, vec3(0.0, -0.115252, -0.993336)) - 0.032105);
  d = max(d, dot(p, vec3(-0.496668, 0.115252, -0.860254)) - 0.032105);
  d = max(d, dot(p, vec3(0.496668, 0.115252, -0.860254)) - 0.032105);
  return d;
}
float sdHull520(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.0, -0.928477, 0.371391)) - 0.0);
  d = max(d, dot(p, vec3(-0.747392, 0.46979, 0.46979)) - 0.016443);
  d = max(d, dot(p, vec3(0.747392, 0.46979, 0.46979)) - 0.016443);
  return d;
}
float sdHull524(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.021651;
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.019445);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.014142);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.021651);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.021651);
  return d;
}
float sdHull529(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.024249;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.01);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.009);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.009192);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.035);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.027577);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.024249);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.02687);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.024249);
  return d;
}
float sdHull532(vec3 p) {
  float d = dot(p, vec3(-0.57735, -0.57735, -0.57735)) - 0.020496;
  d = max(d, dot(p, vec3(-0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(-0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(-1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.0, -0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, -1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(0.0, 0.0, -1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.0, -0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 0.0, 1.0)) - 0.0075);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(-0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.0, 0.707107, -0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.0, 1.0, 0.0)) - 0.006);
  d = max(d, dot(p, vec3(-0.57735, 0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.0, 0.707107, 0.707107)) - 0.006718);
  d = max(d, dot(p, vec3(0.57735, -0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, -0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.707107, 0.0, -0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(1.0, 0.0, 0.0)) - 0.03);
  d = max(d, dot(p, vec3(0.57735, -0.57735, 0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.0, 0.707107)) - 0.023688);
  d = max(d, dot(p, vec3(0.57735, 0.57735, -0.57735)) - 0.020496);
  d = max(d, dot(p, vec3(0.707107, 0.707107, 0.0)) - 0.022627);
  d = max(d, dot(p, vec3(0.57735, 0.57735, 0.57735)) - 0.020496);
  return d;
}
float sdHull535(vec3 p) {
  float d = dot(p, vec3(0.0, -1.0, 0.0)) - 0.0;
  d = max(d, dot(p, vec3(0.34534, -0.938478, 0.0)) - 0.069448);
  d = max(d, dot(p, vec3(0.0, -0.937737, -0.347347)) - 0.063199);
  d = max(d, dot(p, vec3(0.471928, -0.755814, -0.453904)) - 0.177493);
  d = max(d, dot(p, vec3(0.0, -0.937737, 0.347347)) - 0.063199);
  d = max(d, dot(p, vec3(0.471928, -0.755814, 0.453904)) - 0.177493);
  d = max(d, dot(p, vec3(-0.34534, -0.938478, 0.0)) - 0.069448);
  d = max(d, dot(p, vec3(-0.471928, -0.755814, 0.453904)) - 0.177493);
  d = max(d, dot(p, vec3(-0.471928, -0.755814, -0.453904)) - 0.177493);
  d = max(d, dot(p, vec3(0.0, 0.196116, -0.980581)) - 0.18631);
  d = max(d, dot(p, vec3(0.54675, 0.273944, -0.791214)) - 0.259094);
  d = max(d, dot(p, vec3(0.0, 0.305766, -0.952107)) - 0.192083);
  d = max(d, dot(p, vec3(0.67533, 0.277721, -0.683228)) - 0.264149);
  d = max(d, dot(p, vec3(-0.54675, 0.273944, -0.791214)) - 0.259094);
  d = max(d, dot(p, vec3(-0.67533, 0.277721, -0.683228)) - 0.264149);
  d = max(d, dot(p, vec3(-0.980581, 0.196116, 0.0)) - 0.205922);
  d = max(d, dot(p, vec3(-0.784189, 0.620522, 0.0)) - 0.209481);
  d = max(d, dot(p, vec3(-0.67808, 0.28016, 0.679498)) - 0.264067);
  d = max(d, dot(p, vec3(-0.66106, 0.356631, 0.660162)) - 0.265145);
  d = max(d, dot(p, vec3(-0.647149, 0.496957, 0.578128)) - 0.263048);
  d = max(d, dot(p, vec3(-0.68637, 0.280046, -0.671171)) - 0.264317);
  d = max(d, dot(p, vec3(-0.664419, 0.552651, -0.503114)) - 0.259832);
  d = max(d, dot(p, vec3(-0.723653, 0.690161, -0.001921)) - 0.204971);
  d = max(d, dot(p, vec3(-0.674962, 0.279414, 0.682901)) - 0.264019);
  d = max(d, dot(p, vec3(0.980581, 0.196116, 0.0)) - 0.205922);
  d = max(d, dot(p, vec3(0.784189, 0.620522, 0.0)) - 0.209481);
  d = max(d, dot(p, vec3(0.68637, 0.280046, -0.671171)) - 0.264317);
  d = max(d, dot(p, vec3(0.664419, 0.552651, -0.503114)) - 0.259832);
  d = max(d, dot(p, vec3(0.723653, 0.690161, -0.001921)) - 0.204971);
  d = max(d, dot(p, vec3(0.67808, 0.28016, 0.679498)) - 0.264067);
  d = max(d, dot(p, vec3(0.66106, 0.356631, 0.660162)) - 0.265145);
  d = max(d, dot(p, vec3(0.647149, 0.496957, 0.578128)) - 0.263048);
  d = max(d, dot(p, vec3(0.674962, 0.279414, 0.682901)) - 0.264019);
  d = max(d, dot(p, vec3(0.0, 0.196116, 0.980581)) - 0.18631);
  d = max(d, dot(p, vec3(0.0, 0.433114, 0.901339)) - 0.195768);
  d = max(d, dot(p, vec3(0.0, 0.447214, -0.894427)) - 0.196774);
  d = max(d, dot(p, vec3(0.231842, 0.770644, -0.593597)) - 0.220275);
  d = max(d, dot(p, vec3(0.374896, 0.869745, -0.320932)) - 0.209814);
  d = max(d, dot(p, vec3(-0.231842, 0.770644, -0.593597)) - 0.220275);
  d = max(d, dot(p, vec3(-0.374896, 0.869745, -0.320932)) - 0.209814);
  d = max(d, dot(p, vec3(0.0, 0.886585, -0.462566)) - 0.225791);
  d = max(d, dot(p, vec3(-0.465746, 0.884918, 0.0)) - 0.176984);
  d = max(d, dot(p, vec3(-0.390944, 0.918451, 0.060091)) - 0.175974);
  d = max(d, dot(p, vec3(0.0, 0.936289, -0.351231)) - 0.222781);
  d = max(d, dot(p, vec3(-0.588458, 0.606749, 0.53439)) - 0.256336);
  d = max(d, dot(p, vec3(-0.373666, 0.924602, 0.074056)) - 0.175592);
  d = max(d, dot(p, vec3(0.465746, 0.884918, 0.0)) - 0.176984);
  d = max(d, dot(p, vec3(0.390944, 0.918451, 0.060091)) - 0.175974);
  d = max(d, dot(p, vec3(0.588458, 0.606749, 0.53439)) - 0.256336);
  d = max(d, dot(p, vec3(0.373666, 0.924602, 0.074056)) - 0.175592);
  d = max(d, dot(p, vec3(0.0, 0.759257, 0.650791)) - 0.18656);
  d = max(d, dot(p, vec3(0.111465, 0.894621, 0.4327)) - 0.183365);
  d = max(d, dot(p, vec3(0.134524, 0.909681, 0.392918)) - 0.182293);
  d = max(d, dot(p, vec3(-0.111465, 0.894621, 0.4327)) - 0.183365);
  d = max(d, dot(p, vec3(0.0, 0.924315, 0.381632)) - 0.182312);
  d = max(d, dot(p, vec3(-0.134524, 0.909681, 0.392918)) - 0.182293);
  d = max(d, dot(p, vec3(-0.23777, 0.955654, 0.173755)) - 0.17028);
  d = max(d, dot(p, vec3(0.0, 0.982713, 0.185135)) - 0.173405);
  d = max(d, dot(p, vec3(0.23777, 0.955654, 0.173755)) - 0.17028);
  return d;
}
float sdHull539(vec3 p) {
  float d = dot(p, vec3(0.0, 0.0, -1.0)) - 0.0;
  d = max(d, dot(p, vec3(0.9327, -0.103633, 0.345444)) - 0.0);
  d = max(d, dot(p, vec3(-0.9327, -0.103633, 0.345444)) - 0.0);
  d = max(d, dot(p, vec3(0.0, 0.351123, 0.936329)) - 0.063202);
  return d;
}
float sdHull572(vec3 p) {
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
float sdHull575(vec3 p) {
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
float sdHull580(vec3 p) {
  float d = dot(p, vec3(0.988936, -0.14834, 0.0)) - -0.024723;
  d = max(d, dot(p, vec3(-0.988936, -0.14834, 0.0)) - -0.064281);
  d = max(d, dot(p, vec3(0.973009, 0.072976, -0.218927)) - 0.043542);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, -0.218927)) - 0.004622);
  d = max(d, dot(p, vec3(0.973009, 0.072976, 0.218927)) - 0.047921);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, 0.218927)) - 0.009);
  return d;
}
float sdHull585(vec3 p) {
  float d = dot(p, vec3(0.988936, -0.14834, 0.0)) - -0.064281;
  d = max(d, dot(p, vec3(-0.988936, -0.14834, 0.0)) - -0.024723);
  d = max(d, dot(p, vec3(0.973009, 0.072976, -0.218927)) - 0.002433);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, -0.218927)) - 0.041353);
  d = max(d, dot(p, vec3(0.973009, 0.072976, 0.218927)) - 0.01119);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, 0.218927)) - 0.05011);
  return d;
}
float sdHull590(vec3 p) {
  float d = dot(p, vec3(0.988936, -0.14834, 0.0)) - -0.044502;
  d = max(d, dot(p, vec3(-0.988936, -0.14834, 0.0)) - -0.044502);
  d = max(d, dot(p, vec3(0.973009, 0.072976, -0.218927)) - 0.03065);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, -0.218927)) - 0.03065);
  d = max(d, dot(p, vec3(0.973009, 0.072976, 0.218927)) - 0.021893);
  d = max(d, dot(p, vec3(-0.973009, 0.072976, 0.218927)) - 0.021893);
  return d;
}
float sdHull594(vec3 p) {
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
  if (sdBox(p - vec3(-2.282943, 0.665, -0.037436), vec3(0.458871, 0.675, 0.299474)) < u0.d) {
    vec3 q1 = p - vec3(-2.295, 0.665, 0.005384);
    vec3 q2 = q1 * mat3(0.895712, 0.0, -0.444635, 0.0, 1.0, 0.0, 0.444635, 0.0, 0.895712);
    vec3 q3 = q2 - vec3(0.095, -0.665, -0.005384);
    M u4 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q3 - vec3(0.0, 0.665, 0.005384), vec3(0.377007, 0.675, 0.224616)) < u4.d) {
      vec3 q5 = q3 - vec3(0.0, 0.0, 0.0);
      vec3 q6 = q5 - vec3(0.0, 0.0, 0.0);
      vec3 q7 = q6 - vec3(0.0, 0.0, 0.0);
      vec3 q8 = q7 - vec3(0.0, 0.0, 0.0);
      vec3 q9 = q8 - vec3(0.0, 0.0, 0.0);
      vec3 q10 = q9 - vec3(0.0, 0.0, 0.0);
      M u11 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m13 = M(sdLoft12(q10), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m13);
      }
      {
        vec3 q14 = q10 - vec3(0.09, 0.0, 0.0);
        M m16 = M(sdHull15(q14), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m16);
      }
      {
        M m18 = M(sdLoft17(q10), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m18);
      }
      {
        vec3 q19 = q10 - vec3(-0.09, 0.0, 0.0);
        M m21 = M(sdHull20(q19), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m21);
      }
      {
        M m23 = M(sdLoft22(q10), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m23);
      }
      {
        M m25 = M(sdLoft24(q10), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m25);
      }
      {
        vec3 q26 = q10 - vec3(0.0, 0.42, 0.13);
        M m28 = M(sdHull27(q26), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m28);
      }
      {
        vec3 q29 = q10 - vec3(0.0, 0.56, 0.15);
        M m31 = M(sdHull30(q29), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m31);
      }
      {
        vec3 q32 = q10 - vec3(0.0, 0.6, 0.165);
        M m34 = M(sdHull33(q32), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m34);
      }
      {
        vec3 q35 = q10 - vec3(0.0, 0.33, 0.0);
        M m37 = M(sdHull36(q35), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m37);
      }
      {
        vec3 q38 = q10 - vec3(0.27, 0.71, 0.0);
        vec3 q39 = q38 / vec3(1.0, 0.78, 1.0);
        M m41 = M(sdHull40(q39), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m42 = m41; m42.d = m41.d * 0.78;
        u11 = mU(u11, m42);
      }
      {
        M m44 = M(sdLoft43(q10), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m44);
      }
      {
        vec3 q45 = q10 - vec3(0.3, 0.33, 0.04);
        M m47 = M(sdHull46(q45), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m47);
      }
      {
        M m49 = M(sdLoft48(q10), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m49);
      }
      {
        vec3 q50 = q10 - vec3(-0.27, 0.71, 0.0);
        vec3 q51 = q50 / vec3(1.0, 0.78, 1.0);
        M m53 = M(sdHull52(q51), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m54 = m53; m54.d = m53.d * 0.78;
        u11 = mU(u11, m54);
      }
      {
        M m56 = M(sdLoft55(q10), vec3(0.024158, 0.072272, 0.215861), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m56);
      }
      {
        vec3 q57 = q10 - vec3(-0.3, 0.33, 0.04);
        M m59 = M(sdHull58(q57), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m59);
      }
      {
        M m61 = M(sdLoft60(q10), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m61);
      }
      {
        vec3 q62 = q10 - vec3(0.0, 0.95, 0.0);
        M m64 = M(sdHull63(q62), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m64);
      }
      {
        vec3 q65 = q10;
        q65.x = abs(q65.x);
        vec3 q66 = q65 - vec3(0.19, 0.94, 0.0);
        vec3 q67 = q66 / vec3(0.6, 1.0, 0.8);
        M m69 = M(sdHull68(q67), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m70 = m69; m70.d = m69.d * 0.6;
        u11 = mU(u11, m70);
      }
      {
        vec3 q71 = q10 - vec3(0.0, 0.905, 0.17);
        M m73 = M(sdHull72(q71), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m73);
      }
      {
        vec3 q74 = q10;
        q74.x = abs(q74.x);
        vec3 q75 = q74 - vec3(0.075, 0.97, 0.17);
        M m77 = M(sdHull76(q75), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m77);
      }
      {
        vec3 q78 = q10;
        q78.x = abs(q78.x);
        vec3 q79 = q78 - vec3(0.075, 1.025, 0.172);
        vec3 q80 = q79 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
        M m82 = M(sdHull81(q80), vec3(0.147027, 0.057805, 0.016807), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m82);
      }
      {
        vec3 q83 = q10 - vec3(0.0, 0.865, 0.171);
        M m85 = M(sdHull84(q83), vec3(0.254152, 0.042311, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m85);
      }
      {
        vec3 q86 = q10 - vec3(0.0, 0.9, 0.0);
        M m88 = M(sdHull87(q86), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m88);
      }
      {
        vec3 q89 = q10 - vec3(0.0, 0.98, 0.205);
        M m90 = M(sdBox(q89, vec3(0.15, 0.025, 0.015)), vec3(0.014444, 0.017642, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m90);
      }
      {
        vec3 q91 = q10 - vec3(0.0, 1.21, 0.0);
        M m93 = M(sdHull92(q91), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u11 = mU(u11, m93);
      }
      u4 = mU(u4, u11);
    }
    if (sdBox(q3 - vec3(0.3, 0.6085, 0.04), vec3(0.1, 0.3865, 0.035)) < u4.d) {
      vec3 q94 = q3 - vec3(0.3, 0.33, 0.04);
      vec3 q95 = q94 - vec3(0.0, 0.0, 0.0);
      M u96 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q97 = q95 - vec3(0.0, 0.075, 0.0);
        M m99 = M(sdHull98(q97), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u96 = mU(u96, m99);
      }
      {
        vec3 q100 = q95 - vec3(0.0, 0.06, 0.0);
        M m101 = M(sdCBox(q100, vec3(0.09, 0.0175, 0.025), 0.012), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u96 = mU(u96, m101);
      }
      {
        M m103 = M(sdHull102(q95), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u96 = mU(u96, m103);
      }
      {
        vec3 q104 = q95 - vec3(0.0, -0.07, 0.0);
        M m106 = M(sdHull105(q104), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u96 = mU(u96, m106);
      }
      u4 = mU(u4, u96);
    }
    {
      vec3 q107 = q3 - vec3(-0.36, 0.42, 0.0);
      vec3 q108 = q107 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      vec3 q109 = q108 - vec3(0.0, 0.0, 0.0);
      M u110 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m112 = M(sdHull111(q109), vec3(0.049707, 0.158961, 0.462077), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u110 = mU(u110, m112);
      }
      {
        vec3 q113 = q109 - vec3(0.0, 0.0, 0.04);
        M m115 = M(sdHull114(q113), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u110 = mU(u110, m115);
      }
      u4 = mU(u4, u110);
    }
    u0 = mU(u0, u4);
  }
  if (sdBox(p - vec3(-1.139589, 0.592026, -0.009796), vec3(0.599692, 0.602026, 0.336892)) < u0.d) {
    vec3 q116 = p - vec3(-1.1429, 0.592026, 0.0);
    vec3 q117 = q116 * mat3(0.973579, 0.0, -0.228351, 0.0, 1.0, 0.0, 0.228351, 0.0, 0.973579);
    vec3 q118 = q117 - vec3(0.0429, -0.592026, 0.0);
    M u119 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q118 - vec3(0.0, 0.592026, 0.0), vec3(0.443069, 0.602026, 0.279339)) < u119.d) {
      vec3 q120 = q118 - vec3(0.0, 0.0, 0.0);
      vec3 q121 = q120 - vec3(0.0, 0.0, 0.0);
      vec3 q122 = q121 - vec3(0.0, 0.0, 0.0);
      vec3 q123 = q122 - vec3(0.0, 0.0, 0.0);
      vec3 q124 = q123 - vec3(0.0, 0.0, 0.0);
      vec3 q125 = q124 - vec3(0.0, 0.0, 0.0);
      M u126 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m128 = M(sdLoft127(q125), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m128);
      }
      {
        vec3 q129 = q125 - vec3(0.1062, 0.0, 0.0);
        M m131 = M(sdHull130(q129), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m131);
      }
      {
        M m133 = M(sdLoft132(q125), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m133);
      }
      {
        vec3 q134 = q125 - vec3(-0.1062, 0.0, 0.0);
        M m136 = M(sdHull135(q134), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m136);
      }
      {
        M m138 = M(sdLoft137(q125), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m138);
      }
      {
        M m140 = M(sdLoft139(q125), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m140);
      }
      {
        vec3 q141 = q125 - vec3(0.0, 0.42, 0.13);
        M m143 = M(sdHull142(q141), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m143);
      }
      {
        vec3 q144 = q125 - vec3(0.0, 0.33, 0.0);
        M m146 = M(sdHull145(q144), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m146);
      }
      {
        vec3 q147 = q125 - vec3(0.0, 0.55, 0.14);
        M m149 = M(sdHull148(q147), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m149);
      }
      {
        vec3 q150 = q125 - vec3(0.3186, 0.71, 0.0);
        vec3 q151 = q150 / vec3(1.0, 0.78, 1.0);
        M m153 = M(sdHull152(q151), vec3(0.584078, 0.456411, 0.274677), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m154 = m153; m154.d = m153.d * 0.78;
        u126 = mU(u126, m154);
      }
      {
        M m156 = M(sdLoft155(q125), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m156);
      }
      {
        vec3 q157 = q125 - vec3(0.354, 0.33, 0.04);
        M m159 = M(sdHull158(q157), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m159);
      }
      {
        M m161 = M(sdLoft160(q125), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m161);
      }
      {
        vec3 q162 = q125 - vec3(-0.3186, 0.71, 0.0);
        vec3 q163 = q162 / vec3(1.0, 0.78, 1.0);
        M m165 = M(sdHull164(q163), vec3(0.584078, 0.456411, 0.274677), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m166 = m165; m166.d = m165.d * 0.78;
        u126 = mU(u126, m166);
      }
      {
        M m168 = M(sdLoft167(q125), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m168);
      }
      {
        vec3 q169 = q125 - vec3(-0.354, 0.33, 0.04);
        M m171 = M(sdHull170(q169), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m171);
      }
      {
        M m173 = M(sdLoft172(q125), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m173);
      }
      {
        vec3 q174 = q125 - vec3(0.0, 0.95, 0.0);
        M m176 = M(sdHull175(q174), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m176);
      }
      {
        vec3 q177 = q125;
        q177.x = abs(q177.x);
        vec3 q178 = q177 - vec3(0.19, 0.94, 0.0);
        vec3 q179 = q178 / vec3(0.6, 1.0, 0.8);
        M m181 = M(sdHull180(q179), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m182 = m181; m182.d = m181.d * 0.6;
        u126 = mU(u126, m182);
      }
      {
        vec3 q183 = q125 - vec3(0.0, 0.905, 0.17);
        M m185 = M(sdHull184(q183), vec3(0.693872, 0.3564, 0.168269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m185);
      }
      {
        vec3 q186 = q125;
        q186.x = abs(q186.x);
        vec3 q187 = q186 - vec3(0.075, 0.97, 0.17);
        M m189 = M(sdHull188(q187), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m189);
      }
      {
        vec3 q190 = q125;
        q190.x = abs(q190.x);
        vec3 q191 = q190 - vec3(0.075, 1.025, 0.172);
        vec3 q192 = q191 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
        M m194 = M(sdHull193(q192), vec3(0.024158, 0.012286, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m194);
      }
      {
        vec3 q195 = q125 - vec3(0.0, 0.865, 0.171);
        M m197 = M(sdHull196(q195), vec3(0.254152, 0.042311, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m197);
      }
      {
        vec3 q198 = q125 - vec3(0.0, 0.95, 0.0);
        M m200 = M(sdHull199(q198), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m200);
      }
      {
        vec3 q201 = q125 - vec3(0.27, 1.08, 0.0);
        vec3 q202 = q201 * mat3(0.573576, -0.819152, 0.0, 0.819152, 0.573576, 0.0, 0.0, 0.0, 1.0);
        M m204 = M(sdHull203(q202), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m204);
      }
      {
        vec3 q205 = q125 - vec3(-0.27, 1.08, 0.0);
        vec3 q206 = q205 * mat3(0.573576, 0.819152, 0.0, -0.819152, 0.573576, 0.0, 0.0, 0.0, 1.0);
        M m208 = M(sdHull207(q206), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m208);
      }
      {
        vec3 q209 = q125 - vec3(0.0, 0.74, 0.17);
        M m211 = M(sdHull210(q209), vec3(0.024158, 0.012286, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u126 = mU(u126, m211);
      }
      u119 = mU(u119, u126);
    }
    {
      vec3 q212 = q118 - vec3(0.354, 0.33, 0.04);
      vec3 q213 = q212 - vec3(0.0, 0.0, 0.0);
      M u214 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q215 = q213 - vec3(0.0, 0.22, 0.0);
        M m217 = M(sdHull216(q215), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u214 = mU(u214, m217);
      }
      {
        vec3 q218 = q213 - vec3(0.01, 0.43, 0.0);
        M m220 = M(sdHull219(q218), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u214 = mU(u214, m220);
      }
      u119 = mU(u119, u214);
    }
    if (sdBox(q118 - vec3(-0.4248, 0.42, 0.02), vec3(0.225, 0.225, 0.061962)) < u119.d) {
      vec3 q221 = q118 - vec3(-0.4248, 0.42, 0.0);
      vec3 q222 = q221 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      vec3 q223 = q222 - vec3(0.0, 0.0, 0.0);
      M u224 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q225 = q223 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
        M m227 = M(sdHull226(q225), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u224 = mU(u224, m227);
      }
      {
        vec3 q228 = q223 - vec3(0.0, 0.0, -0.008);
        vec3 q229 = q228 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
        M m231 = M(sdHull230(q229), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u224 = mU(u224, m231);
      }
      {
        vec3 q232 = q223 - vec3(0.0, 0.0, 0.02);
        M m234 = M(sdHull233(q232), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u224 = mU(u224, m234);
      }
      u119 = mU(u119, u224);
    }
    u0 = mU(u0, u119);
  }
  if (sdBox(p - vec3(0.0, 0.6, -0.021988), vec3(0.358657, 0.61, 0.241221)) < u0.d) {
    M u235 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(p - vec3(0.0, 0.6, -0.021988), vec3(0.358657, 0.61, 0.241221)) < u235.d) {
      vec3 q236 = p - vec3(0.0, 0.0, 0.0);
      vec3 q237 = q236 - vec3(0.0, 0.0, 0.0);
      vec3 q238 = q237 - vec3(0.0, 0.0, 0.0);
      vec3 q239 = q238 - vec3(0.0, 0.0, 0.0);
      vec3 q240 = q239 - vec3(0.0, 0.0, 0.0);
      vec3 q241 = q240 - vec3(0.0, 0.0, 0.0);
      M u242 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m244 = M(sdLoft243(q241), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m244);
      }
      {
        vec3 q245 = q241 - vec3(0.0855, 0.0, 0.0);
        M m247 = M(sdHull246(q245), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m247);
      }
      {
        M m249 = M(sdLoft248(q241), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m249);
      }
      {
        vec3 q250 = q241 - vec3(-0.0855, 0.0, 0.0);
        M m252 = M(sdHull251(q250), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m252);
      }
      {
        M m254 = M(sdLoft253(q241), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m254);
      }
      {
        M m256 = M(sdLoft255(q241), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m256);
      }
      {
        vec3 q257 = q241 - vec3(0.0, 0.42, 0.13);
        M m259 = M(sdHull258(q257), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m259);
      }
      {
        vec3 q260 = q241 - vec3(0.0, 0.33, 0.0);
        M m262 = M(sdHull261(q260), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m262);
      }
      {
        vec3 q263 = q241 - vec3(0.2565, 0.71, 0.0);
        vec3 q264 = q263 / vec3(1.0, 0.78, 1.0);
        M m266 = M(sdHull265(q264), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m267 = m266; m267.d = m266.d * 0.78;
        u242 = mU(u242, m267);
      }
      {
        M m269 = M(sdLoft268(q241), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m269);
      }
      {
        vec3 q270 = q241 - vec3(0.285, 0.33, 0.04);
        M m272 = M(sdHull271(q270), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m272);
      }
      {
        M m274 = M(sdLoft273(q241), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m274);
      }
      {
        vec3 q275 = q241 - vec3(-0.2565, 0.71, 0.0);
        vec3 q276 = q275 / vec3(1.0, 0.78, 1.0);
        M m278 = M(sdHull277(q276), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m279 = m278; m279.d = m278.d * 0.78;
        u242 = mU(u242, m279);
      }
      {
        M m281 = M(sdLoft280(q241), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m281);
      }
      {
        vec3 q282 = q241 - vec3(-0.285, 0.33, 0.04);
        M m284 = M(sdHull283(q282), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m284);
      }
      {
        M m286 = M(sdLoft285(q241), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m286);
      }
      {
        vec3 q287 = q241 - vec3(0.0, 0.95, 0.0);
        M m289 = M(sdHull288(q287), vec3(0.391572, 0.158961, 0.06301), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m289);
      }
      {
        vec3 q290 = q241;
        q290.x = abs(q290.x);
        vec3 q291 = q290 - vec3(0.19, 0.94, 0.0);
        vec3 q292 = q291 / vec3(0.6, 1.0, 0.8);
        M m294 = M(sdHull293(q292), vec3(0.391572, 0.158961, 0.06301), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m295 = m294; m295.d = m294.d * 0.6;
        u242 = mU(u242, m295);
      }
      {
        vec3 q296 = q241 - vec3(0.0, 0.905, 0.17);
        M m298 = M(sdHull297(q296), vec3(0.391572, 0.158961, 0.06301), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m298);
      }
      {
        vec3 q299 = q241;
        q299.x = abs(q299.x);
        vec3 q300 = q299 - vec3(0.075, 0.97, 0.17);
        M m302 = M(sdHull301(q300), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m302);
      }
      {
        vec3 q303 = q241;
        q303.x = abs(q303.x);
        vec3 q304 = q303 - vec3(0.075, 1.025, 0.172);
        vec3 q305 = q304 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
        M m307 = M(sdHull306(q305), vec3(0.693872, 0.456411, 0.144128), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m307);
      }
      {
        vec3 q308 = q241 - vec3(0.0, 0.865, 0.171);
        M m310 = M(sdHull309(q308), vec3(0.254152, 0.042311, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m310);
      }
      {
        vec3 q311 = q241 - vec3(0.0, 0.9, 0.003457);
        M m313 = M(sdHull312(q311), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m313);
      }
      {
        vec3 q314 = q241 - vec3(0.0, 0.97, 0.18);
        M m315 = M(sdBox(q314, vec3(0.16, 0.035, 0.015)), vec3(0.046665, 0.102242, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m315);
      }
      {
        vec3 q316 = q241 - vec3(0.0, 0.71, 0.155);
        M m317 = M(sdCBox(q316, vec3(0.18, 0.05, 0.025), 0.02), vec3(0.019382, 0.039546, 0.019382), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u242 = mU(u242, m317);
      }
      u235 = mU(u235, u242);
    }
    if (sdBox(p - vec3(0.285, 0.4625, 0.04), vec3(0.06, 0.1825, 0.0275)) < u235.d) {
      vec3 q318 = p - vec3(0.285, 0.33, 0.04);
      vec3 q319 = q318 - vec3(0.0, 0.0, 0.0);
      M u320 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q321 = q319 - vec3(0.0, 0.055, 0.0);
        M m323 = M(sdHull322(q321), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u320 = mU(u320, m323);
      }
      {
        vec3 q324 = q319 - vec3(0.0, 0.045, 0.0);
        M m325 = M(sdCBox(q324, vec3(0.05, 0.0125, 0.0175), 0.008), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u320 = mU(u320, m325);
      }
      {
        M m327 = M(sdHull326(q319), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u320 = mU(u320, m327);
      }
      u235 = mU(u235, u320);
    }
    if (sdBox(p - vec3(-0.285, 0.4625, 0.04), vec3(0.06, 0.1825, 0.0275)) < u235.d) {
      vec3 q328 = p - vec3(-0.285, 0.33, 0.04);
      vec3 q329 = q328 - vec3(0.0, 0.0, 0.0);
      M u330 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q331 = q329 - vec3(0.0, 0.055, 0.0);
        M m333 = M(sdHull332(q331), vec3(0.584078, 0.617207, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u330 = mU(u330, m333);
      }
      {
        vec3 q334 = q329 - vec3(0.0, 0.045, 0.0);
        M m335 = M(sdCBox(q334, vec3(0.05, 0.0125, 0.0175), 0.008), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u330 = mU(u330, m335);
      }
      {
        M m337 = M(sdHull336(q329), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u330 = mU(u330, m337);
      }
      u235 = mU(u235, u330);
    }
    u0 = mU(u0, u235);
  }
  if (sdBox(p - vec3(1.097158, 0.698083, 0.001483), vec3(0.392133, 0.708083, 0.356284)) < u0.d) {
    vec3 q338 = p - vec3(1.093504, 0.698083, 0.0);
    vec3 q339 = q338 * mat3(0.973579, 0.0, 0.228351, 0.0, 1.0, 0.0, -0.228351, 0.0, 0.973579);
    vec3 q340 = q339 - vec3(0.006496, -0.698083, 0.0);
    M u341 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q340 - vec3(0.0, 0.698083, 0.0), vec3(0.377007, 0.708083, 0.295317)) < u341.d) {
      vec3 q342 = q340 - vec3(0.0, 0.0, 0.0);
      vec3 q343 = q342 - vec3(0.0, 0.0, 0.0);
      vec3 q344 = q343 - vec3(0.0, 0.0, 0.0);
      vec3 q345 = q344 - vec3(0.0, 0.0, 0.0);
      vec3 q346 = q345 - vec3(0.0, 0.0, 0.0);
      vec3 q347 = q346 - vec3(0.0, 0.0, 0.0);
      M u348 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m350 = M(sdLoft349(q347), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m350);
      }
      {
        vec3 q351 = q347 - vec3(0.09, 0.0, 0.0);
        M m353 = M(sdHull352(q351), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m353);
      }
      {
        M m355 = M(sdLoft354(q347), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m355);
      }
      {
        vec3 q356 = q347 - vec3(-0.09, 0.0, 0.0);
        M m358 = M(sdHull357(q356), vec3(0.059511, 0.029557, 0.194618), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m358);
      }
      {
        M m360 = M(sdLoft359(q347), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m360);
      }
      {
        M m362 = M(sdLoft361(q347), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m362);
      }
      {
        vec3 q363 = q347 - vec3(0.0, 0.42, 0.13);
        M m365 = M(sdHull364(q363), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m365);
      }
      {
        vec3 q366 = q347 - vec3(0.0, 0.2, 0.0);
        M m368 = M(sdHull367(q366), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m368);
      }
      {
        vec3 q369 = q347 - vec3(0.0, 0.55, 0.14);
        M m371 = M(sdHull370(q369), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m371);
      }
      {
        vec3 q372 = q347 - vec3(0.27, 0.71, 0.0);
        vec3 q373 = q372 / vec3(1.0, 0.78, 1.0);
        M m375 = M(sdHull374(q373), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m376 = m375; m376.d = m375.d * 0.78;
        u348 = mU(u348, m376);
      }
      {
        M m378 = M(sdLoft377(q347), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m378);
      }
      {
        vec3 q379 = q347 - vec3(0.3, 0.33, 0.04);
        M m381 = M(sdHull380(q379), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m381);
      }
      {
        M m383 = M(sdLoft382(q347), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m383);
      }
      {
        vec3 q384 = q347 - vec3(-0.27, 0.71, 0.0);
        vec3 q385 = q384 / vec3(1.0, 0.78, 1.0);
        M m387 = M(sdHull386(q385), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m388 = m387; m388.d = m387.d * 0.78;
        u348 = mU(u348, m388);
      }
      {
        M m390 = M(sdLoft389(q347), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m390);
      }
      {
        vec3 q391 = q347 - vec3(-0.3, 0.33, 0.04);
        M m393 = M(sdHull392(q391), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m393);
      }
      {
        M m395 = M(sdLoft394(q347), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m395);
      }
      {
        vec3 q396 = q347 - vec3(0.0, 0.95, 0.0);
        M m398 = M(sdHull397(q396), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m398);
      }
      {
        vec3 q399 = q347;
        q399.x = abs(q399.x);
        vec3 q400 = q399 - vec3(0.19, 0.94, 0.0);
        vec3 q401 = q400 / vec3(0.6, 1.0, 0.8);
        M m403 = M(sdHull402(q401), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m404 = m403; m404.d = m403.d * 0.6;
        u348 = mU(u348, m404);
      }
      {
        vec3 q405 = q347 - vec3(0.0, 0.905, 0.17);
        M m407 = M(sdHull406(q405), vec3(0.871367, 0.545724, 0.323143), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m407);
      }
      {
        vec3 q408 = q347;
        q408.x = abs(q408.x);
        vec3 q409 = q408 - vec3(0.075, 0.97, 0.17);
        M m411 = M(sdHull410(q409), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m411);
      }
      {
        vec3 q412 = q347;
        q412.x = abs(q412.x);
        vec3 q413 = q412 - vec3(0.075, 1.025, 0.172);
        vec3 q414 = q413 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
        M m416 = M(sdHull415(q414), vec3(0.147027, 0.057805, 0.016807), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m416);
      }
      {
        vec3 q417 = q347 - vec3(0.0, 0.865, 0.171);
        M m419 = M(sdHull418(q417), vec3(0.254152, 0.042311, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m419);
      }
      {
        vec3 q420 = q347 - vec3(0.0, 0.935, 0.0);
        M m422 = M(sdHull421(q420), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m422);
      }
      {
        vec3 q423 = q347 - vec3(0.0, 0.95, -0.02);
        vec3 q424 = q423 * mat3(1.0, 0.0, 0.0, 0.0, 0.978148, -0.207912, 0.0, 0.207912, 0.978148);
        vec3 q425 = q424 - vec3(0.0, 0.21, 0.0);
        M m427 = M(sdHull426(q425), vec3(0.144128, 0.07036, 0.434154), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m427);
      }
      {
        vec3 q428 = q347 - vec3(0.0, 0.95, 0.0);
        M m430 = M(sdHull429(q428), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m430);
      }
      {
        vec3 q431 = q347 - vec3(0.0, 0.73, 0.17);
        M m433 = M(sdHull432(q431), vec3(0.806952, 0.775822, 0.701102), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u348 = mU(u348, m433);
      }
      u341 = mU(u341, u348);
    }
    if (sdBox(q340 - vec3(0.3, 0.655, 0.04), vec3(0.061962, 0.635, 0.061962)) < u341.d) {
      vec3 q434 = q340 - vec3(0.3, 0.33, 0.04);
      vec3 q435 = q434 - vec3(0.0, 0.0, 0.0);
      M u436 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q437 = q435 - vec3(0.0, 0.25, 0.0);
        M m439 = M(sdHull438(q437), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u436 = mU(u436, m439);
      }
      {
        vec3 q440 = q435 - vec3(0.0, 0.82, 0.0);
        vec3 q441 = q440 * mat3(1.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, -1.0);
        M m443 = M(sdHull442(q441), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u436 = mU(u436, m443);
      }
      {
        vec3 q444 = q435 - vec3(0.0, 0.89, 0.0);
        M m446 = M(sdHull445(q444), vec3(0.102242, 0.637597, 0.791298), vec3(0.6, 0.0, 0.8), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u436 = mU(u436, m446);
      }
      u341 = mU(u341, u436);
    }
    if (sdBox(q340 - vec3(-0.2985, 0.33, 0.043), vec3(0.0915, 0.12, 0.038)) < u341.d) {
      vec3 q447 = q340 - vec3(-0.3, 0.33, 0.04);
      vec3 q448 = q447 - vec3(0.0, 0.0, 0.0);
      M u449 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m450 = M(sdCBox(q448, vec3(0.08, 0.11, 0.025), 0.01), vec3(0.254152, 0.042311, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u449 = mU(u449, m450);
      }
      {
        vec3 q451 = q448 - vec3(0.008, 0.0, 0.0);
        M m452 = M(sdBox(q451, vec3(0.075, 0.1, 0.02)), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u449 = mU(u449, m452);
      }
      {
        vec3 q453 = q448 - vec3(0.0, 0.03, 0.026);
        M m454 = M(sdCBox(q453, vec3(0.025, 0.025, 0.005), 0.005), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u449 = mU(u449, m454);
      }
      u341 = mU(u341, u449);
    }
    u0 = mU(u0, u341);
  }
  if (sdBox(p - vec3(2.2, 0.561604, 0.0), vec3(0.381866, 0.619984, 0.295232)) < u0.d) {
    vec3 q455 = p - vec3(2.2, 0.561604, 0.0);
    vec3 q456 = q455 * mat3(0.895712, 0.0, 0.444635, 0.0, 1.0, 0.0, -0.444635, 0.0, 0.895712);
    vec3 q457 = q456 - vec3(0.0, -0.561604, 0.0);
    M u458 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q457 - vec3(0.0, 0.585794, 0.0), vec3(0.377007, 0.595794, 0.219232)) < u458.d) {
      vec3 q459 = q457 - vec3(0.0, 0.0, 0.0);
      vec3 q460 = q459 - vec3(0.0, 0.0, 0.0);
      vec3 q461 = q460 - vec3(0.0, 0.0, 0.0);
      vec3 q462 = q461 - vec3(0.0, 0.0, 0.0);
      vec3 q463 = q462 - vec3(0.0, 0.0, 0.0);
      vec3 q464 = q463 - vec3(0.0, 0.0, 0.0);
      M u465 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m467 = M(sdLoft466(q464), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m467);
      }
      {
        vec3 q468 = q464 - vec3(0.09, 0.0, 0.0);
        M m470 = M(sdHull469(q468), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m470);
      }
      {
        M m472 = M(sdLoft471(q464), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m472);
      }
      {
        vec3 q473 = q464 - vec3(-0.09, 0.0, 0.0);
        M m475 = M(sdHull474(q473), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m475);
      }
      {
        M m477 = M(sdLoft476(q464), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m477);
      }
      {
        M m479 = M(sdLoft478(q464), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m479);
      }
      {
        vec3 q480 = q464 - vec3(0.0, 0.42, 0.13);
        M m482 = M(sdHull481(q480), vec3(0.760525, 0.450786, 0.045186), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m482);
      }
      {
        vec3 q483 = q464 - vec3(0.0, 0.33, 0.0);
        M m485 = M(sdHull484(q483), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m485);
      }
      {
        vec3 q486 = q464 - vec3(0.27, 0.71, 0.0);
        vec3 q487 = q486 / vec3(1.0, 0.78, 1.0);
        M m489 = M(sdHull488(q487), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m490 = m489; m490.d = m489.d * 0.78;
        u465 = mU(u465, m490);
      }
      {
        M m492 = M(sdLoft491(q464), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m492);
      }
      {
        vec3 q493 = q464 - vec3(0.3, 0.33, 0.04);
        M m495 = M(sdHull494(q493), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m495);
      }
      {
        M m497 = M(sdLoft496(q464), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m497);
      }
      {
        vec3 q498 = q464 - vec3(-0.27, 0.71, 0.0);
        vec3 q499 = q498 / vec3(1.0, 0.78, 1.0);
        M m501 = M(sdHull500(q499), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m502 = m501; m502.d = m501.d * 0.78;
        u465 = mU(u465, m502);
      }
      {
        M m504 = M(sdLoft503(q464), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m504);
      }
      {
        vec3 q505 = q464 - vec3(-0.3, 0.33, 0.04);
        M m507 = M(sdHull506(q505), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m507);
      }
      {
        M m509 = M(sdLoft508(q464), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m509);
      }
      {
        vec3 q510 = q464 - vec3(0.0, 0.95, 0.0);
        M m512 = M(sdHull511(q510), vec3(0.155926, 0.059511, 0.022174), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m512);
      }
      {
        vec3 q513 = q464;
        q513.x = abs(q513.x);
        vec3 q514 = q513 - vec3(0.19, 0.94, 0.0);
        vec3 q515 = q514 / vec3(0.6, 1.0, 0.8);
        M m517 = M(sdHull516(q515), vec3(0.155926, 0.059511, 0.022174), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m518 = m517; m518.d = m517.d * 0.6;
        u465 = mU(u465, m518);
      }
      {
        vec3 q519 = q464 - vec3(0.0, 0.905, 0.17);
        M m521 = M(sdHull520(q519), vec3(0.155926, 0.059511, 0.022174), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m521);
      }
      {
        vec3 q522 = q464;
        q522.x = abs(q522.x);
        vec3 q523 = q522 - vec3(0.075, 0.97, 0.17);
        M m525 = M(sdHull524(q523), vec3(0.023153, 0.016807, 0.014444), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m525);
      }
      {
        vec3 q526 = q464;
        q526.x = abs(q526.x);
        vec3 q527 = q526 - vec3(0.075, 1.025, 0.172);
        vec3 q528 = q527 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
        M m530 = M(sdHull529(q528), vec3(0.391572, 0.056128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m530);
      }
      {
        vec3 q531 = q464 - vec3(0.0, 0.865, 0.171);
        M m533 = M(sdHull532(q531), vec3(0.254152, 0.042311, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m533);
      }
      {
        vec3 q534 = q464 - vec3(0.0, 0.92, 0.0);
        M m536 = M(sdHull535(q534), vec3(0.078187, 0.194618, 0.042311), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m536);
      }
      {
        vec3 q537 = q464 - vec3(0.14, 1.0, -0.05);
        vec3 q538 = q537 * mat3(0.906308, -0.422618, 0.0, 0.422618, 0.906308, 0.0, 0.0, 0.0, 1.0);
        M m540 = M(sdHull539(q538), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m540);
      }
      {
        vec3 q541 = q464 - vec3(0.0, 0.53, -0.17);
        M m542 = M(sdCBox(q541, vec3(0.21, 0.25, 0.015), 0.01), vec3(0.147027, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u465 = mU(u465, m542);
      }
      u458 = mU(u458, u465);
    }
    if (sdBox(q457 - vec3(-0.3, 0.33, -0.010125), vec3(0.03, 0.388381, 0.080125)) < u458.d) {
      vec3 q543 = q457 - vec3(-0.3, 0.33, -0.02);
      vec3 q544 = q543 - vec3(0.0, 0.0, 0.0);
      M u545 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q546 = q544 - vec3(0.0, -0.312111, -0.012311);
        vec3 q547 = q546 * mat3(1.0, 0.0, 0.0, 0.0, 0.862437, 0.506164, 0.0, -0.506164, 0.862437);
        M m548 = M(sdCapsule(q547, 0.016, 0.051449), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m548);
      }
      {
        vec3 q549 = q544 - vec3(0.0, -0.205571, 0.030883);
        vec3 q550 = q549 * mat3(1.0, 0.0, 0.0, 0.0, 0.963984, 0.265961, 0.0, -0.265961, 0.963984);
        M m551 = M(sdCapsule(q550, 0.016, 0.064492), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m551);
      }
      {
        vec3 q552 = q544 - vec3(0.0, -0.071701, 0.054017);
        vec3 q553 = q552 * mat3(1.0, 0.0, 0.0, 0.0, 0.996537, 0.083148, 0.0, -0.083148, 0.996537);
        M m554 = M(sdCapsule(q553, 0.016, 0.07195), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m554);
      }
      {
        vec3 q555 = q544 - vec3(0.0, 0.071701, 0.054017);
        vec3 q556 = q555 * mat3(1.0, 0.0, 0.0, 0.0, 0.996537, -0.083148, 0.0, 0.083148, 0.996537);
        M m557 = M(sdCapsule(q556, 0.016, 0.07195), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m557);
      }
      {
        vec3 q558 = q544 - vec3(0.0, 0.205571, 0.030883);
        vec3 q559 = q558 * mat3(1.0, 0.0, 0.0, 0.0, 0.963984, -0.265961, 0.0, 0.265961, 0.963984);
        M m560 = M(sdCapsule(q559, 0.016, 0.064492), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m560);
      }
      {
        vec3 q561 = q544 - vec3(0.0, 0.312111, -0.012311);
        vec3 q562 = q561 * mat3(1.0, 0.0, 0.0, 0.0, 0.862437, -0.506164, 0.0, 0.506164, 0.862437);
        M m563 = M(sdCapsule(q562, 0.016, 0.051449), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m563);
      }
      {
        vec3 q564 = q544 - vec3(0.0, 0.0, -0.038353);
        vec3 q565 = q564 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m566 = M(sdCapsule(q565, 0.004, 0.356483), vec3(0.863157, 0.791298, 0.64448), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m566);
      }
      {
        vec3 q567 = q544 - vec3(0.0, 0.0, 0.06);
        M m568 = M(sdCBox(q567, vec3(0.02, 0.045, 0.02), 0.01), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u545 = mU(u545, m568);
      }
      u458 = mU(u458, u545);
    }
    if (sdBox(q457 - vec3(0.0, 0.645, -0.095), vec3(0.082, 0.275, 0.072354)) < u458.d) {
      vec3 q569 = q457 - vec3(0.0, 0.55, -0.095);
      vec3 q570 = q569 - vec3(0.0, 0.0, 0.0);
      M u571 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m573 = M(sdHull572(q570), vec3(0.194618, 0.068478, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m573);
      }
      {
        vec3 q574 = q570 - vec3(0.0, 0.15, 0.0);
        M m576 = M(sdHull575(q574), vec3(0.266356, 0.296138, 0.341914), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m576);
      }
      {
        vec3 q577 = q570 - vec3(0.02, 0.225, 0.01);
        vec3 q578 = q577 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m579 = M(sdCapsule(q578, 0.005, 0.075), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m579);
      }
      {
        M m581 = M(sdHull580(q570), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m581);
      }
      {
        vec3 q582 = q570 - vec3(-0.02, 0.225, 0.02);
        vec3 q583 = q582 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m584 = M(sdCapsule(q583, 0.005, 0.075), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m584);
      }
      {
        M m586 = M(sdHull585(q570), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m586);
      }
      {
        vec3 q587 = q570 - vec3(0.0, 0.225, -0.02);
        vec3 q588 = q587 * mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
        M m589 = M(sdCapsule(q588, 0.005, 0.075), vec3(0.254152, 0.102242, 0.03434), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m589);
      }
      {
        M m591 = M(sdHull590(q570), vec3(0.57758, 0.039546, 0.024158), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u571 = mU(u571, m591);
      }
      u458 = mU(u458, u571);
    }
    u0 = mU(u0, u458);
  }
  {
    vec3 q592 = p - vec3(0.0, -0.04, 0.0);
    vec3 q593 = q592 / vec3(1.0, 1.0, 0.4);
    M m595 = M(sdHull594(q593), vec3(0.158961, 0.254152, 0.068478), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m596 = m595; m596.d = m595.d * 0.4;
    u0 = mU(u0, m596);
  }
  return u0;
}
