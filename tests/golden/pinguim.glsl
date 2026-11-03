
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
    M m1 = M(p.y, vec3(0.023153, 0.158961, 0.309469), vec3(0.05, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  {
    vec3 q2 = p - vec3(0.0, -0.03, 0.0);
    M m3 = M(sdCyl(q2, 1.5, 0.05) - 0.1, vec3(0.806952, 0.904661, 0.964686), vec3(0.4, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m3);
  }
  if (sdBox(p - vec3(-0.25, 0.77826, 0.0), vec3(0.441717, 0.66826, 0.3225)) < u0.d) {
    vec3 q4 = p - vec3(-0.25, 0.12, -0.0225);
    M u5 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q4 - vec3(0.0, 0.595, 0.01), vec3(0.441717, 0.575, 0.31)) < u5.d) {
      vec3 q6 = q4 - vec3(0.0, 0.45, 0.0);
      M m7 = M(sdEllipsoid(q6, vec3(0.32, 0.42, 0.29)), vec3(0.012286, 0.017642, 0.029557), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      vec3 q8 = q4 - vec3(0.0, 0.93, 0.0);
      M m9 = M(length(q8) - 0.23, vec3(0.012286, 0.017642, 0.029557), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m10 = mUs(m7, m9, 0.1);
      vec3 q11 = q4;
      q11.x = abs(q11.x);
      vec3 q12 = q11 - vec3(0.31, 0.5, -0.02);
      vec3 q13 = q12 * mat3(0.951057, 0.309017, 0.0, -0.309017, 0.951057, 0.0, 0.0, 0.0, 1.0);
      M m14 = M(sdEllipsoid(q13, vec3(0.05, 0.24, 0.13)), vec3(0.012286, 0.017642, 0.029557), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m15 = mUs(m10, m14, 0.1);
      M u16 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q17 = q4 - vec3(0.0, 0.42, 0.11);
        M m18 = M(sdEllipsoid(q17, vec3(0.25, 0.34, 0.2)), vec3(0.887923, 0.887923, 0.887923), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u16 = mU(u16, m18);
      }
      {
        vec3 q19 = q4;
        q19.x = abs(q19.x);
        vec3 q20 = q19 - vec3(0.07, 0.96, 0.13);
        M m21 = M(length(q20) - 0.1, vec3(0.887923, 0.887923, 0.887923), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u16 = mU(u16, m21);
      }
      M m22 = mUs(m15, u16, 0.03);
      u5 = mU(u5, m22);
    }
    {
      vec3 q23 = q4;
      q23.x = abs(q23.x);
      vec3 q24 = q23 - vec3(0.075, 0.98, 0.21);
      M m25 = M(length(q24) - 0.035, vec3(0.011612, 0.011612, 0.011612), vec3(0.1, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u5 = mU(u5, m25);
    }
    {
      vec3 q26 = q4;
      q26.x = abs(q26.x);
      vec3 q27 = q26 - vec3(0.085, 0.995, 0.24);
      M m28 = M(length(q27) - 0.01, vec3(0.887923, 0.887923, 0.887923), vec3(0.6, 0.0, 0.6), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u5 = mU(u5, m28);
    }
    {
      vec3 q29 = q4 - vec3(0.0, 0.91, 0.27);
      vec3 q30 = q29 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m31 = M(sdCone(q30, 0.065, 0.045, 0.0), vec3(0.854993, 0.254152, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u5 = mU(u5, m31);
    }
    {
      vec3 q32 = q4;
      q32.x = abs(q32.x);
      vec3 q33 = q32 - vec3(0.11, 0.03, 0.14);
      M m34 = M(sdEllipsoid(q33, vec3(0.09, 0.03, 0.13)), vec3(0.854993, 0.254152, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u5 = mU(u5, m34);
    }
    {
      vec3 q35 = q4 - vec3(0.0, 0.74, 0.0);
      M m36 = M(sdTorus(q35, 0.2, 0.045), vec3(0.672443, 0.045186, 0.045186), vec3(0.9, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      vec3 q37 = q4 - vec3(0.1, 0.62, 0.2);
      vec3 q38 = q37 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
      M m39 = M(sdBox(q38, vec3(0.028, 0.098, 0.003)) - 0.012, vec3(0.672443, 0.045186, 0.045186), vec3(0.9, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m40 = mUs(m36, m39, 0.03);
      u5 = mU(u5, m40);
    }
    if (sdBox(q4 - vec3(0.0, 1.019308, -0.002203), vec3(0.26, 0.307212, 0.288724)) < u5.d) {
      vec3 q41 = q4 - vec3(0.0, 1.0375, -0.01);
      vec3 q42 = q41 * mat3(1.0, 0.0, 0.0, 0.0, 0.978148, -0.207912, 0.0, 0.207912, 0.978148);
      vec3 q43 = q42 - vec3(0.0, -0.0375, 0.0);
      M u44 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m45 = M(length(q43) - 0.235, vec3(0.043735, 0.158961, 0.672443), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        vec3 q46 = q43 - vec3(0.0, -0.5, 0.0);
        M m47 = M(sdBox(q46, vec3(0.5, 0.5, 0.5)), vec3(0.043735, 0.158961, 0.672443), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m48 = mS(m45, m47);
        u44 = mU(u44, m48);
      }
      {
        M m49 = M(sdTorus(q43, 0.215, 0.035), vec3(0.043735, 0.158961, 0.672443), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u44 = mU(u44, m49);
      }
      {
        vec3 q50 = q43 - vec3(0.0, 0.25, 0.0);
        M m51 = M(length(q50) - 0.06, vec3(0.043735, 0.158961, 0.672443), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u44 = mU(u44, m51);
      }
      u5 = mU(u5, u44);
    }
    u0 = mU(u0, u5);
  }
  if (sdBox(p - vec3(0.55, 0.528121, 0.35), vec3(0.279125, 0.418121, 0.271081)) < u0.d) {
    vec3 q52 = p - vec3(0.538523, -0.130139, 0.338927);
    vec3 q53 = q52 - vec3(0.0, 0.65826, 0.0225);
    vec3 q54 = q53 * mat3(0.819152, 0.0, 0.573576, 0.0, 1.0, 0.0, -0.573576, 0.0, 0.819152);
    vec3 q55 = q54 / vec3(0.62, 0.62, 0.62);
    vec3 q56 = q55 - vec3(0.0, -0.65826, -0.0225);
    M u57 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q56 - vec3(0.0, 0.595, 0.01), vec3(0.441717, 0.575, 0.31)) < u57.d) {
      vec3 q58 = q56 - vec3(0.0, 0.45, 0.0);
      M m59 = M(sdEllipsoid(q58, vec3(0.32, 0.42, 0.29)), vec3(0.012286, 0.017642, 0.029557), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      vec3 q60 = q56 - vec3(0.0, 0.93, 0.0);
      M m61 = M(length(q60) - 0.23, vec3(0.012286, 0.017642, 0.029557), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m62 = mUs(m59, m61, 0.1);
      vec3 q63 = q56;
      q63.x = abs(q63.x);
      vec3 q64 = q63 - vec3(0.31, 0.5, -0.02);
      vec3 q65 = q64 * mat3(0.951057, 0.309017, 0.0, -0.309017, 0.951057, 0.0, 0.0, 0.0, 1.0);
      M m66 = M(sdEllipsoid(q65, vec3(0.05, 0.24, 0.13)), vec3(0.012286, 0.017642, 0.029557), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m67 = mUs(m62, m66, 0.1);
      M u68 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q69 = q56 - vec3(0.0, 0.42, 0.11);
        M m70 = M(sdEllipsoid(q69, vec3(0.25, 0.34, 0.2)), vec3(0.887923, 0.887923, 0.887923), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u68 = mU(u68, m70);
      }
      {
        vec3 q71 = q56;
        q71.x = abs(q71.x);
        vec3 q72 = q71 - vec3(0.07, 0.96, 0.13);
        M m73 = M(length(q72) - 0.1, vec3(0.887923, 0.887923, 0.887923), vec3(0.7, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u68 = mU(u68, m73);
      }
      M m74 = mUs(m67, u68, 0.03);
      u57 = mU(u57, m74);
    }
    {
      vec3 q75 = q56;
      q75.x = abs(q75.x);
      vec3 q76 = q75 - vec3(0.075, 0.98, 0.21);
      M m77 = M(length(q76) - 0.035, vec3(0.011612, 0.011612, 0.011612), vec3(0.1, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u57 = mU(u57, m77);
    }
    {
      vec3 q78 = q56;
      q78.x = abs(q78.x);
      vec3 q79 = q78 - vec3(0.085, 0.995, 0.24);
      M m80 = M(length(q79) - 0.01, vec3(0.887923, 0.887923, 0.887923), vec3(0.6, 0.0, 0.6), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u57 = mU(u57, m80);
    }
    {
      vec3 q81 = q56 - vec3(0.0, 0.91, 0.27);
      vec3 q82 = q81 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m83 = M(sdCone(q82, 0.065, 0.045, 0.0), vec3(0.854993, 0.254152, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u57 = mU(u57, m83);
    }
    {
      vec3 q84 = q56;
      q84.x = abs(q84.x);
      vec3 q85 = q84 - vec3(0.11, 0.03, 0.14);
      M m86 = M(sdEllipsoid(q85, vec3(0.09, 0.03, 0.13)), vec3(0.854993, 0.254152, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u57 = mU(u57, m86);
    }
    {
      vec3 q87 = q56 - vec3(0.0, 0.74, 0.0);
      M m88 = M(sdTorus(q87, 0.2, 0.045), vec3(0.887923, 0.55834, 0.046665), vec3(0.9, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      vec3 q89 = q56 - vec3(0.1, 0.62, 0.2);
      vec3 q90 = q89 * mat3(0.990268, -0.139173, 0.0, 0.139173, 0.990268, 0.0, 0.0, 0.0, 1.0);
      M m91 = M(sdBox(q90, vec3(0.028, 0.098, 0.003)) - 0.012, vec3(0.887923, 0.55834, 0.046665), vec3(0.9, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      M m92 = mUs(m88, m91, 0.03);
      u57 = mU(u57, m92);
    }
    if (sdBox(q56 - vec3(0.0, 1.019308, -0.002203), vec3(0.26, 0.307212, 0.288724)) < u57.d) {
      vec3 q93 = q56 - vec3(0.0, 1.0375, -0.01);
      vec3 q94 = q93 * mat3(1.0, 0.0, 0.0, 0.0, 0.978148, -0.207912, 0.0, 0.207912, 0.978148);
      vec3 q95 = q94 - vec3(0.0, -0.0375, 0.0);
      M u96 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        M m97 = M(length(q95) - 0.235, vec3(0.838799, 0.212231, 0.434154), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        vec3 q98 = q95 - vec3(0.0, -0.5, 0.0);
        M m99 = M(sdBox(q98, vec3(0.5, 0.5, 0.5)), vec3(0.838799, 0.212231, 0.434154), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        M m100 = mS(m97, m99);
        u96 = mU(u96, m100);
      }
      {
        M m101 = M(sdTorus(q95, 0.215, 0.035), vec3(0.838799, 0.212231, 0.434154), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u96 = mU(u96, m101);
      }
      {
        vec3 q102 = q95 - vec3(0.0, 0.25, 0.0);
        M m103 = M(length(q102) - 0.06, vec3(0.838799, 0.212231, 0.434154), vec3(0.95, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u96 = mU(u96, m103);
      }
      u57 = mU(u57, u96);
    }
    M m104 = u57; m104.d = u57.d * 0.62;
    u0 = mU(u0, m104);
  }
  {
    vec3 q105 = p - vec3(0.094189, 0.17, 0.761622);
    vec3 q106 = q105 * mat3(0.906308, 0.0, -0.422618, 0.0, 1.0, 0.0, 0.422618, 0.0, 0.906308);
    vec3 q107 = q106 - vec3(0.0275, 0.0, 0.0);
    M m108 = M(sdEllipsoid(q107, vec3(0.12, 0.05, 0.035)), vec3(0.527115, 0.552011, 0.57758), vec3(0.3, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q109 = q107 - vec3(-0.14, 0.0, 0.0);
    vec3 q110 = q109 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
    M m111 = M(sdPrism(q110, 0.04, 0.07, 0.0075), vec3(0.527115, 0.552011, 0.57758), vec3(0.3, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m112 = mUs(m108, m111, 0.02);
    u0 = mU(u0, m112);
  }
  return u0;
}
