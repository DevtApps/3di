
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

uniform highp sampler2D uInst;
uniform highp sampler2D uBvh;
vec4 instFetch(int col, int row) {
  int index = row * 11 + col;
  int width = textureSize(uInst, 0).x;
  return texelFetch(uInst, ivec2(index % width, index / width), 0);
}
vec4 bvhFetch(int col, int row) {
  int index = row * 2 + col;
  int width = textureSize(uBvh, 0).x;
  return texelFetch(uBvh, ivec2(index % width, index / width), 0);
}
float instD(vec3 p, int i) {
  vec4 a = instFetch(0, i);
  vec4 b = instFetch(1, i);
  vec4 r0 = instFetch(2, i);
  vec4 r1 = instFetch(3, i);
  vec4 r2 = instFetch(4, i);
  vec3 q = vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w);
  int t = int(a.x);
  float d;
  if (t == 1) d = sdBox(q, a.yzw) - b.x;
  else if (t == 2) d = length(q) - a.y;
  else if (t == 3) d = sdCyl(q, a.y, a.z) - a.w;
  else if (t == 4) d = sdCone(q, a.y, a.z, a.w);
  else if (t == 5) d = sdTorus(q, a.y, a.z);
  else if (t == 6) d = sdCapsule(q, a.y, a.z);
  else if (t == 7) d = sdEllipsoid(q, a.yzw);
  else if (t == 8) d = sdPyramid((q + vec3(0.0, a.z * 0.5, 0.0)) / a.y, a.z / a.y) * a.y;
  else d = sdPrism(q, a.y, a.z, a.w);
  return d * b.y;
}
float boxDist(vec3 p, int ni) {
  vec3 mn = bvhFetch(0, ni).xyz;
  vec3 mx = bvhFetch(1, ni).xyz;
  return sdBox(p - (mn + mx) * 0.5, (mx - mn) * 0.5);
}
// Percorre a BVH a partir da melhor distância já conhecida; devolve a nova melhor e o índice atingido.
float bvhD(vec3 p, float best, out int hit) {
  hit = -1;
  int stack[40];
  int sp = 0;
  int ni = 0;
  if (boxDist(p, 0) >= best) return best;
  while (true) {
    vec4 a = bvhFetch(0, ni);
    int cnt = int(bvhFetch(1, ni).w);
    if (cnt > 0) {
      int st = int(a.w);
      for (int k = 0; k < cnt; k++) {
        float d = instD(p, st + k);
        if (d < best) { best = d; hit = st + k; }
      }
    } else {
      int l = ni + 1, r = int(a.w);
      float dl = boxDist(p, l), dr = boxDist(p, r);
      int nearN = dl < dr ? l : r, farN = dl < dr ? r : l;
      float dn = min(dl, dr), df = max(dl, dr);
      if (df < best && sp < 40) stack[sp++] = farN;
      if (dn < best) { ni = nearN; continue; }
    }
    // desempilha o próximo nó que ainda pode conter algo mais perto
    bool found = false;
    while (sp > 0) {
      int c = stack[--sp];
      if (boxDist(p, c) < best) { ni = c; found = true; break; }
    }
    if (!found) break;
  }
  return best;
}

M codeM(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    M m1 = M(p.y, vec3(0.114435, 0.212231, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  if (sdBox(p - vec3(1.25, 0.24879, -1.5), vec3(0.389253, 0.343743, 0.389253)) < u0.d) {
    vec3 q2 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.25, 0.24879, -1.5));
    vec3 q3 = q2 / vec3(1.0, 0.85, 1.0);
    M m4 = M(length(q3) - 0.303403, vec3(0.055976, 0.171614, 0.035226), vec3(0.6, 0.0, 0.0), vec3(0.176733, 0.407412, 0.075241), vec4(8.0, 0.303403, 1.0, 0.21), q2, 0.0);
    M m5 = m4; m5.d = m4.d * 0.85;
    M m6 = m5; m6.d = (m5.d + 0.075851 * (fbm(q2 / 0.212382) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m6);
  }
  if (sdBox(p - vec3(1.469959, 0.26144, -1.304714), vec3(0.408537, 0.360712, 0.408537)) < u0.d) {
    vec3 q7 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.469959, 0.26144, -1.304714));
    vec3 q8 = q7 / vec3(1.0, 0.85, 1.0);
    M m9 = M(length(q8) - 0.318829, vec3(0.039861, 0.11738, 0.0326), vec3(0.6, 0.0, 0.0), vec3(0.156649, 0.350062, 0.072757), vec4(8.0, 0.318829, 1.0, 0.21), q7, 0.0);
    M m10 = m9; m10.d = m9.d * 0.85;
    M m11 = m10; m11.d = (m10.d + 0.079707 * (fbm(q7 / 0.223181) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m11);
  }
  if (sdBox(p - vec3(1.453737, 0.243314, -1.347563), vec3(0.380905, 0.336396, 0.380905)) < u0.d) {
    vec3 q12 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.453737, 0.243314, -1.347563));
    vec3 q13 = q12 / vec3(1.0, 0.85, 1.0);
    M m14 = M(length(q13) - 0.296724, vec3(0.034108, 0.140573, 0.016734), vec3(0.6, 0.0, 0.0), vec3(0.148749, 0.375528, 0.055874), vec4(8.0, 0.296724, 1.0, 0.21), q12, 0.0);
    M m15 = m14; m15.d = m14.d * 0.85;
    M m16 = m15; m16.d = (m15.d + 0.074181 * (fbm(q12 / 0.207707) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m16);
  }
  if (sdBox(p - vec3(1.312099, 0.260658, -1.160682), vec3(0.407345, 0.359663, 0.407345)) < u0.d) {
    vec3 q17 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.312099, 0.260658, -1.160682));
    vec3 q18 = q17 / vec3(1.0, 0.85, 1.0);
    M m19 = M(length(q18) - 0.317876, vec3(0.072301, 0.250228, 0.057567), vec3(0.6, 0.0, 0.0), vec3(0.194993, 0.480544, 0.094439), vec4(8.0, 0.317876, 1.0, 0.21), q17, 0.0);
    M m20 = m19; m20.d = m19.d * 0.85;
    M m21 = m20; m21.d = (m20.d + 0.079469 * (fbm(q17 / 0.222513) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m21);
  }
  if (sdBox(p - vec3(1.211464, 0.196795, -1.275792), vec3(0.309993, 0.273994, 0.309993)) < u0.d) {
    vec3 q22 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.211464, 0.196795, -1.275792));
    vec3 q23 = q22 / vec3(1.0, 0.85, 1.0);
    M m24 = M(length(q23) - 0.239994, vec3(0.027572, 0.129798, 0.018339), vec3(0.6, 0.0, 0.0), vec3(0.139102, 0.363899, 0.057786), vec4(8.0, 0.239994, 1.0, 0.21), q22, 0.0);
    M m25 = m24; m25.d = m24.d * 0.85;
    M m26 = m25; m26.d = (m25.d + 0.059999 * (fbm(q22 / 0.167996) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m26);
  }
  if (sdBox(p - vec3(1.079679, 0.20325, -1.193972), vec3(0.319833, 0.282653, 0.319833)) < u0.d) {
    vec3 q27 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.079679, 0.20325, -1.193972));
    vec3 q28 = q27 / vec3(1.0, 0.85, 1.0);
    M m29 = M(length(q28) - 0.247866, vec3(0.057823, 0.15539, 0.040417), vec3(0.6, 0.0, 0.0), vec3(0.178888, 0.391021, 0.079981), vec4(8.0, 0.247866, 1.0, 0.21), q27, 0.0);
    M m30 = m29; m30.d = m29.d * 0.85;
    M m31 = m30; m31.d = (m30.d + 0.061967 * (fbm(q27 / 0.173507) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m31);
  }
  if (sdBox(p - vec3(1.045682, 0.225314, -1.362757), vec3(0.353466, 0.31225, 0.353466)) < u0.d) {
    vec3 q32 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.045682, 0.225314, -1.362757));
    vec3 q33 = q32 / vec3(1.0, 0.85, 1.0);
    M m34 = M(length(q33) - 0.274773, vec3(0.034522, 0.098707, 0.024368), vec3(0.6, 0.0, 0.0), vec3(0.149334, 0.328205, 0.064485), vec4(8.0, 0.274773, 1.0, 0.21), q32, 0.0);
    M m35 = m34; m35.d = m34.d * 0.85;
    M m36 = m35; m36.d = (m35.d + 0.068693 * (fbm(q32 / 0.192341) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m36);
  }
  if (sdBox(p - vec3(1.015337, 0.274194, -1.48878), vec3(0.427978, 0.377821, 0.427978)) < u0.d) {
    vec3 q37 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.015337, 0.274194, -1.48878));
    vec3 q38 = q37 / vec3(1.0, 0.85, 1.0);
    M m39 = M(length(q38) - 0.334382, vec3(0.041253, 0.119501, 0.032241), vec3(0.6, 0.0, 0.0), vec3(0.158492, 0.352461, 0.072412), vec4(8.0, 0.334382, 1.0, 0.21), q37, 0.0);
    M m40 = m39; m40.d = m39.d * 0.85;
    M m41 = m40; m41.d = (m40.d + 0.083596 * (fbm(q37 / 0.234068) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m41);
  }
  if (sdBox(p - vec3(1.012352, 0.277269, -1.620106), vec3(0.432665, 0.381946, 0.432665)) < u0.d) {
    vec3 q42 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.012352, 0.277269, -1.620106));
    vec3 q43 = q42 / vec3(1.0, 0.85, 1.0);
    M m44 = M(length(q43) - 0.338132, vec3(0.065329, 0.252035, 0.034974), vec3(0.6, 0.0, 0.0), vec3(0.187398, 0.482129, 0.075005), vec4(8.0, 0.338132, 1.0, 0.21), q42, 0.0);
    M m45 = m44; m45.d = m44.d * 0.85;
    M m46 = m45; m46.d = (m45.d + 0.084533 * (fbm(q42 / 0.236693) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m46);
  }
  if (sdBox(p - vec3(1.015241, 0.235216, -1.776205), vec3(0.368561, 0.325534, 0.368561)) < u0.d) {
    vec3 q47 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.015241, 0.235216, -1.776205));
    vec3 q48 = q47 / vec3(1.0, 0.85, 1.0);
    M m49 = M(length(q48) - 0.286849, vec3(0.057427, 0.18698, 0.034214), vec3(0.6, 0.0, 0.0), vec3(0.178428, 0.422457, 0.074291), vec4(8.0, 0.286849, 1.0, 0.21), q47, 0.0);
    M m50 = m49; m50.d = m49.d * 0.85;
    M m51 = m50; m51.d = (m50.d + 0.071712 * (fbm(q47 / 0.200794) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m51);
  }
  if (sdBox(p - vec3(1.228527, 0.254358, -1.805284), vec3(0.397741, 0.351212, 0.397741)) < u0.d) {
    vec3 q52 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.228527, 0.254358, -1.805284));
    vec3 q53 = q52 / vec3(1.0, 0.85, 1.0);
    M m54 = M(length(q53) - 0.310193, vec3(0.047156, 0.16839, 0.039105), vec3(0.6, 0.0, 0.0), vec3(0.166059, 0.404198, 0.078803), vec4(8.0, 0.310193, 1.0, 0.21), q52, 0.0);
    M m55 = m54; m55.d = m54.d * 0.85;
    M m56 = m55; m56.d = (m55.d + 0.077548 * (fbm(q52 / 0.217135) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m56);
  }
  if (sdBox(p - vec3(1.345543, 0.197028, -1.72392), vec3(0.310347, 0.274305, 0.310347)) < u0.d) {
    vec3 q57 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.345543, 0.197028, -1.72392));
    vec3 q58 = q57 / vec3(1.0, 0.85, 1.0);
    M m59 = M(length(q58) - 0.240278, vec3(0.031405, 0.199765, 0.013484), vec3(0.6, 0.0, 0.0), vec3(0.144858, 0.434662, 0.051776), vec4(8.0, 0.240278, 1.0, 0.21), q57, 0.0);
    M m60 = m59; m60.d = m59.d * 0.85;
    M m61 = m60; m61.d = (m60.d + 0.060069 * (fbm(q57 / 0.168194) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m61);
  }
  if (sdBox(p - vec3(1.481486, 0.204471, -1.669963), vec3(0.321693, 0.28429, 0.321693)) < u0.d) {
    vec3 q62 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.481486, 0.204471, -1.669963));
    vec3 q63 = q62 / vec3(1.0, 0.85, 1.0);
    M m64 = M(length(q63) - 0.249355, vec3(0.051852, 0.22096, 0.02139), vec3(0.6, 0.0, 0.0), vec3(0.171827, 0.454342, 0.061261), vec4(8.0, 0.249355, 1.0, 0.21), q62, 0.0);
    M m65 = m64; m65.d = m64.d * 0.85;
    M m66 = m65; m66.d = (m65.d + 0.062339 * (fbm(q62 / 0.174548) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m66);
  }
  if (sdBox(p - vec3(1.495006, 0.222493, -1.64832), vec3(0.349166, 0.308466, 0.349166)) < u0.d) {
    vec3 q67 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.495006, 0.222493, -1.64832));
    vec3 q68 = q67 / vec3(1.0, 0.85, 1.0);
    M m69 = M(length(q68) - 0.271333, vec3(0.023783, 0.130921, 0.008921), vec3(0.6, 0.0, 0.0), vec3(0.133083, 0.365127, 0.045298), vec4(8.0, 0.271333, 1.0, 0.21), q67, 0.0);
    M m70 = m69; m70.d = m69.d * 0.85;
    M m71 = m70; m71.d = (m70.d + 0.067833 * (fbm(q67 / 0.189933) * 2.0 - 1.0)) * 0.528302;
    u0 = mU(u0, m71);
  }
  return u0;
}
M mapAll(vec3 p, bool wantMat) {
  M r = codeM(p);
  int hit;
  r.d = bvhD(p, r.d, hit);
  if (hit >= 0 && wantMat) {
    vec4 bb = instFetch(1, hit);
    vec4 c = instFetch(5, hit);
    vec4 e = instFetch(6, hit);
    vec4 c2 = instFetch(7, hit);
    vec4 t0 = instFetch(8, hit), t1 = instFetch(9, hit), t2 = instFetch(10, hit);
    vec3 tp = vec3(dot(t0.xyz, p) + t0.w, dot(t1.xyz, p) + t1.w, dot(t2.xyz, p) + t2.w);
    r = M(r.d, c.rgb, vec3(c.a, e.x, e.y), c2.rgb, vec4(e.z, e.w, c2.a, bb.z), tp, bb.w);
  }
  return r;
}
