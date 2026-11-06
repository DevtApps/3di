
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
        if (!cullVis(0 + st + k)) continue;
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
    M m1 = M(p.y, vec3(0.152926, 0.162029, 0.187821), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  {
    vec3 q2 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-5.98, 0.33, 4.295));
    vec3 q3 = q2 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u4 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q5 = q3 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m6 = M(sdCyl(q5, 0.33, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u4 = mU(u4, m6);
    }
    {
      M m7 = M(sdBox(q3, vec3(0.126, 0.16368, 0.035805)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u4 = mU(u4, m7);
    }
    u0 = mU(u0, u4);
  }
  {
    vec3 q8 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-5.98, 0.33, 6.905));
    vec3 q9 = q8 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u10 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q11 = q9 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m12 = M(sdCyl(q11, 0.33, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u10 = mU(u10, m12);
    }
    {
      M m13 = M(sdBox(q9, vec3(0.126, 0.16368, 0.035805)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u10 = mU(u10, m13);
    }
    u0 = mU(u0, u10);
  }
  {
    vec3 q14 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-4.42, 0.33, 4.295));
    vec3 q15 = q14 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u16 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q17 = q15 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m18 = M(sdCyl(q17, 0.33, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u16 = mU(u16, m18);
    }
    {
      M m19 = M(sdBox(q15, vec3(0.126, 0.16368, 0.035805)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u16 = mU(u16, m19);
    }
    u0 = mU(u0, u16);
  }
  {
    vec3 q20 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-4.42, 0.33, 6.905));
    vec3 q21 = q20 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u22 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q23 = q21 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m24 = M(sdCyl(q23, 0.33, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u22 = mU(u22, m24);
    }
    {
      M m25 = M(sdBox(q21, vec3(0.126, 0.16368, 0.035805)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u22 = mU(u22, m25);
    }
    u0 = mU(u0, u22);
  }
  {
    vec3 q26 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.77, 0.33, 4.295));
    vec3 q27 = q26 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u28 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q29 = q27 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m30 = M(sdCyl(q29, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u28 = mU(u28, m30);
    }
    {
      vec3 q31 = q27 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m32 = M(sdCyl(q31, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u28 = mU(u28, m32);
    }
    {
      M m33 = M(sdBox(q27, vec3(0.143, 0.028644, 0.17391)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u28 = mU(u28, m33);
    }
    u0 = mU(u0, u28);
  }
  {
    vec3 q34 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.77, 0.33, 6.905));
    vec3 q35 = q34 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u36 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q37 = q35 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m38 = M(sdCyl(q37, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u36 = mU(u36, m38);
    }
    {
      vec3 q39 = q35 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m40 = M(sdCyl(q39, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u36 = mU(u36, m40);
    }
    {
      M m41 = M(sdBox(q35, vec3(0.143, 0.028644, 0.17391)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u36 = mU(u36, m41);
    }
    u0 = mU(u0, u36);
  }
  {
    vec3 q42 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.77, 0.33, 4.295));
    vec3 q43 = q42 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u44 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q45 = q43 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m46 = M(sdCyl(q45, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u44 = mU(u44, m46);
    }
    {
      vec3 q47 = q43 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m48 = M(sdCyl(q47, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u44 = mU(u44, m48);
    }
    {
      M m49 = M(sdBox(q43, vec3(0.143, 0.028644, 0.17391)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u44 = mU(u44, m49);
    }
    u0 = mU(u0, u44);
  }
  {
    vec3 q50 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.77, 0.33, 6.905));
    vec3 q51 = q50 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u52 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q53 = q51 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m54 = M(sdCyl(q53, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u52 = mU(u52, m54);
    }
    {
      vec3 q55 = q51 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m56 = M(sdCyl(q55, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u52 = mU(u52, m56);
    }
    {
      M m57 = M(sdBox(q51, vec3(0.143, 0.028644, 0.17391)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u52 = mU(u52, m57);
    }
    u0 = mU(u0, u52);
  }
  {
    vec3 q58 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.43, 0.3696, 4.295));
    vec3 q59 = q58 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u60 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q61 = q59 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m62 = M(sdCyl(q61, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m62);
    }
    {
      vec3 q63 = q59 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m64 = M(sdCyl(q63, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m64);
    }
    {
      M m65 = M(sdBox(q59, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m65);
    }
    {
      vec3 q66 = q59 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m67 = M(sdBox(q66, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m67);
    }
    {
      vec3 q68 = q59 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m69 = M(sdBox(q68, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m69);
    }
    {
      vec3 q70 = q59 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m71 = M(sdBox(q70, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m71);
    }
    {
      vec3 q72 = q59 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m73 = M(sdBox(q72, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u60 = mU(u60, m73);
    }
    u0 = mU(u0, u60);
  }
  {
    vec3 q74 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.43, 0.3696, 6.905));
    vec3 q75 = q74 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u76 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q77 = q75 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m78 = M(sdCyl(q77, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m78);
    }
    {
      vec3 q79 = q75 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m80 = M(sdCyl(q79, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m80);
    }
    {
      M m81 = M(sdBox(q75, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m81);
    }
    {
      vec3 q82 = q75 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m83 = M(sdBox(q82, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m83);
    }
    {
      vec3 q84 = q75 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m85 = M(sdBox(q84, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m85);
    }
    {
      vec3 q86 = q75 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m87 = M(sdBox(q86, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m87);
    }
    {
      vec3 q88 = q75 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m89 = M(sdBox(q88, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m89);
    }
    u0 = mU(u0, u76);
  }
  {
    vec3 q90 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(5.97, 0.3696, 4.295));
    vec3 q91 = q90 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u92 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q93 = q91 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m94 = M(sdCyl(q93, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u92 = mU(u92, m94);
    }
    {
      vec3 q95 = q91 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m96 = M(sdCyl(q95, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u92 = mU(u92, m96);
    }
    {
      M m97 = M(sdBox(q91, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u92 = mU(u92, m97);
    }
    {
      vec3 q98 = q91 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m99 = M(sdBox(q98, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u92 = mU(u92, m99);
    }
    {
      vec3 q100 = q91 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m101 = M(sdBox(q100, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u92 = mU(u92, m101);
    }
    {
      vec3 q102 = q91 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m103 = M(sdBox(q102, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u92 = mU(u92, m103);
    }
    {
      vec3 q104 = q91 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m105 = M(sdBox(q104, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u92 = mU(u92, m105);
    }
    u0 = mU(u0, u92);
  }
  {
    vec3 q106 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(5.97, 0.3696, 6.905));
    vec3 q107 = q106 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u108 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q109 = q107 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m110 = M(sdCyl(q109, 0.252, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u108 = mU(u108, m110);
    }
    {
      vec3 q111 = q107 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m112 = M(sdCyl(q111, 0.2046, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u108 = mU(u108, m112);
    }
    {
      M m113 = M(sdBox(q107, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u108 = mU(u108, m113);
    }
    {
      vec3 q114 = q107 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m115 = M(sdBox(q114, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u108 = mU(u108, m115);
    }
    {
      vec3 q116 = q107 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m117 = M(sdBox(q116, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u108 = mU(u108, m117);
    }
    {
      vec3 q118 = q107 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m119 = M(sdBox(q118, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u108 = mU(u108, m119);
    }
    {
      vec3 q120 = q107 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m121 = M(sdBox(q120, vec3(0.143, 0.028644, 0.17391)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u108 = mU(u108, m121);
    }
    u0 = mU(u0, u108);
  }
  {
    vec3 q122 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-6.03, 0.38, -1.363));
    vec3 q123 = q122 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u124 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q125 = q123 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m126 = M(sdCyl(q125, 0.38, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u124 = mU(u124, m126);
    }
    {
      M m127 = M(sdBox(q123, vec3(0.126, 0.18848, 0.04123)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u124 = mU(u124, m127);
    }
    u0 = mU(u0, u124);
  }
  {
    vec3 q128 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-6.03, 0.38, 1.363));
    vec3 q129 = q128 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u130 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q131 = q129 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m132 = M(sdCyl(q131, 0.38, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u130 = mU(u130, m132);
    }
    {
      M m133 = M(sdBox(q129, vec3(0.126, 0.18848, 0.04123)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u130 = mU(u130, m133);
    }
    u0 = mU(u0, u130);
  }
  {
    vec3 q134 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-4.37, 0.38, -1.363));
    vec3 q135 = q134 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u136 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q137 = q135 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m138 = M(sdCyl(q137, 0.38, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u136 = mU(u136, m138);
    }
    {
      M m139 = M(sdBox(q135, vec3(0.126, 0.18848, 0.04123)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u136 = mU(u136, m139);
    }
    u0 = mU(u0, u136);
  }
  {
    vec3 q140 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-4.37, 0.38, 1.363));
    vec3 q141 = q140 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u142 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q143 = q141 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m144 = M(sdCyl(q143, 0.38, 0.12), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u142 = mU(u142, m144);
    }
    {
      M m145 = M(sdBox(q141, vec3(0.126, 0.18848, 0.04123)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u142 = mU(u142, m145);
    }
    u0 = mU(u0, u142);
  }
  {
    vec3 q146 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.82, 0.38, -1.363));
    vec3 q147 = q146 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u148 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q149 = q147 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m150 = M(sdCyl(q149, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u148 = mU(u148, m150);
    }
    {
      vec3 q151 = q147 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m152 = M(sdCyl(q151, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u148 = mU(u148, m152);
    }
    {
      M m153 = M(sdBox(q147, vec3(0.143, 0.032984, 0.20026)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u148 = mU(u148, m153);
    }
    u0 = mU(u0, u148);
  }
  {
    vec3 q154 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.82, 0.38, 1.363));
    vec3 q155 = q154 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u156 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q157 = q155 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m158 = M(sdCyl(q157, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u156 = mU(u156, m158);
    }
    {
      vec3 q159 = q155 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m160 = M(sdCyl(q159, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u156 = mU(u156, m160);
    }
    {
      M m161 = M(sdBox(q155, vec3(0.143, 0.032984, 0.20026)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u156 = mU(u156, m161);
    }
    u0 = mU(u0, u156);
  }
  {
    vec3 q162 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.82, 0.38, -1.363));
    vec3 q163 = q162 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u164 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q165 = q163 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m166 = M(sdCyl(q165, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u164 = mU(u164, m166);
    }
    {
      vec3 q167 = q163 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m168 = M(sdCyl(q167, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u164 = mU(u164, m168);
    }
    {
      M m169 = M(sdBox(q163, vec3(0.143, 0.032984, 0.20026)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u164 = mU(u164, m169);
    }
    u0 = mU(u0, u164);
  }
  {
    vec3 q170 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.82, 0.38, 1.363));
    vec3 q171 = q170 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u172 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q173 = q171 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m174 = M(sdCyl(q173, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u172 = mU(u172, m174);
    }
    {
      vec3 q175 = q171 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m176 = M(sdCyl(q175, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u172 = mU(u172, m176);
    }
    {
      M m177 = M(sdBox(q171, vec3(0.143, 0.032984, 0.20026)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u172 = mU(u172, m177);
    }
    u0 = mU(u0, u172);
  }
  {
    vec3 q178 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.38, 0.4256, -1.363));
    vec3 q179 = q178 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u180 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q181 = q179 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m182 = M(sdCyl(q181, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u180 = mU(u180, m182);
    }
    {
      vec3 q183 = q179 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m184 = M(sdCyl(q183, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u180 = mU(u180, m184);
    }
    {
      M m185 = M(sdBox(q179, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u180 = mU(u180, m185);
    }
    {
      vec3 q186 = q179 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m187 = M(sdBox(q186, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u180 = mU(u180, m187);
    }
    {
      vec3 q188 = q179 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m189 = M(sdBox(q188, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u180 = mU(u180, m189);
    }
    {
      vec3 q190 = q179 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m191 = M(sdBox(q190, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u180 = mU(u180, m191);
    }
    {
      vec3 q192 = q179 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m193 = M(sdBox(q192, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u180 = mU(u180, m193);
    }
    u0 = mU(u0, u180);
  }
  {
    vec3 q194 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.38, 0.4256, 1.363));
    vec3 q195 = q194 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u196 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q197 = q195 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m198 = M(sdCyl(q197, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u196 = mU(u196, m198);
    }
    {
      vec3 q199 = q195 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m200 = M(sdCyl(q199, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u196 = mU(u196, m200);
    }
    {
      M m201 = M(sdBox(q195, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u196 = mU(u196, m201);
    }
    {
      vec3 q202 = q195 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m203 = M(sdBox(q202, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u196 = mU(u196, m203);
    }
    {
      vec3 q204 = q195 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m205 = M(sdBox(q204, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u196 = mU(u196, m205);
    }
    {
      vec3 q206 = q195 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m207 = M(sdBox(q206, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u196 = mU(u196, m207);
    }
    {
      vec3 q208 = q195 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m209 = M(sdBox(q208, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u196 = mU(u196, m209);
    }
    u0 = mU(u0, u196);
  }
  {
    vec3 q210 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.02, 0.4256, -1.363));
    vec3 q211 = q210 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u212 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q213 = q211 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m214 = M(sdCyl(q213, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u212 = mU(u212, m214);
    }
    {
      vec3 q215 = q211 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m216 = M(sdCyl(q215, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u212 = mU(u212, m216);
    }
    {
      M m217 = M(sdBox(q211, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u212 = mU(u212, m217);
    }
    {
      vec3 q218 = q211 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m219 = M(sdBox(q218, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u212 = mU(u212, m219);
    }
    {
      vec3 q220 = q211 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m221 = M(sdBox(q220, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u212 = mU(u212, m221);
    }
    {
      vec3 q222 = q211 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m223 = M(sdBox(q222, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u212 = mU(u212, m223);
    }
    {
      vec3 q224 = q211 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m225 = M(sdBox(q224, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u212 = mU(u212, m225);
    }
    u0 = mU(u0, u212);
  }
  {
    vec3 q226 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.02, 0.4256, 1.363));
    vec3 q227 = q226 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u228 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q229 = q227 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m230 = M(sdCyl(q229, 0.302, 0.052) - 0.078, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u228 = mU(u228, m230);
    }
    {
      vec3 q231 = q227 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m232 = M(sdCyl(q231, 0.2356, 0.1352), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u228 = mU(u228, m232);
    }
    {
      M m233 = M(sdBox(q227, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u228 = mU(u228, m233);
    }
    {
      vec3 q234 = q227 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m235 = M(sdBox(q234, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u228 = mU(u228, m235);
    }
    {
      vec3 q236 = q227 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m237 = M(sdBox(q236, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u228 = mU(u228, m237);
    }
    {
      vec3 q238 = q227 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m239 = M(sdBox(q238, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u228 = mU(u228, m239);
    }
    {
      vec3 q240 = q227 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m241 = M(sdBox(q240, vec3(0.143, 0.032984, 0.20026)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u228 = mU(u228, m241);
    }
    u0 = mU(u0, u228);
  }
  {
    vec3 q242 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-6.3, 0.5, -3.05));
    vec3 q243 = q242 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u244 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q245 = q243 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m246 = M(sdCyl(q245, 0.5, 0.15), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u244 = mU(u244, m246);
    }
    {
      M m247 = M(sdBox(q243, vec3(0.1575, 0.248, 0.05425)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u244 = mU(u244, m247);
    }
    u0 = mU(u0, u244);
  }
  {
    vec3 q248 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-6.3, 0.5, -8.05));
    vec3 q249 = q248 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u250 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q251 = q249 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m252 = M(sdCyl(q251, 0.5, 0.15), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u250 = mU(u250, m252);
    }
    {
      M m253 = M(sdBox(q249, vec3(0.1575, 0.248, 0.05425)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u250 = mU(u250, m253);
    }
    u0 = mU(u0, u250);
  }
  {
    vec3 q254 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-6.3, 0.5, -6.9));
    vec3 q255 = q254 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u256 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q257 = q255 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m258 = M(sdCyl(q257, 0.5, 0.15), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u256 = mU(u256, m258);
    }
    {
      M m259 = M(sdBox(q255, vec3(0.1575, 0.248, 0.05425)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u256 = mU(u256, m259);
    }
    u0 = mU(u0, u256);
  }
  {
    vec3 q260 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-4.1, 0.5, -3.05));
    vec3 q261 = q260 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u262 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q263 = q261 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m264 = M(sdCyl(q263, 0.5, 0.15), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u262 = mU(u262, m264);
    }
    {
      M m265 = M(sdBox(q261, vec3(0.1575, 0.248, 0.05425)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u262 = mU(u262, m265);
    }
    u0 = mU(u0, u262);
  }
  {
    vec3 q266 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-4.1, 0.5, -8.05));
    vec3 q267 = q266 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u268 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q269 = q267 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m270 = M(sdCyl(q269, 0.5, 0.15), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u268 = mU(u268, m270);
    }
    {
      M m271 = M(sdBox(q267, vec3(0.1575, 0.248, 0.05425)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u268 = mU(u268, m271);
    }
    u0 = mU(u0, u268);
  }
  {
    vec3 q272 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-4.1, 0.5, -6.9));
    vec3 q273 = q272 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u274 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q275 = q273 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m276 = M(sdCyl(q275, 0.5, 0.15), vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u274 = mU(u274, m276);
    }
    {
      M m277 = M(sdBox(q273, vec3(0.1575, 0.248, 0.05425)), vec3(0.570482, 0.603827, 0.67386), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u274 = mU(u274, m277);
    }
    u0 = mU(u0, u274);
  }
  {
    vec3 q278 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.1, 0.5, -3.05));
    vec3 q279 = q278 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u280 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q281 = q279 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m282 = M(sdCyl(q281, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u280 = mU(u280, m282);
    }
    {
      vec3 q283 = q279 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m284 = M(sdCyl(q283, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u280 = mU(u280, m284);
    }
    {
      M m285 = M(sdBox(q279, vec3(0.165, 0.0434, 0.2635)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u280 = mU(u280, m285);
    }
    u0 = mU(u0, u280);
  }
  {
    vec3 q286 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.1, 0.5, -8.05));
    vec3 q287 = q286 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u288 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q289 = q287 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m290 = M(sdCyl(q289, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u288 = mU(u288, m290);
    }
    {
      vec3 q291 = q287 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m292 = M(sdCyl(q291, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u288 = mU(u288, m292);
    }
    {
      M m293 = M(sdBox(q287, vec3(0.165, 0.0434, 0.2635)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u288 = mU(u288, m293);
    }
    u0 = mU(u0, u288);
  }
  {
    vec3 q294 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.1, 0.5, -6.9));
    vec3 q295 = q294 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u296 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q297 = q295 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m298 = M(sdCyl(q297, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u296 = mU(u296, m298);
    }
    {
      vec3 q299 = q295 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m300 = M(sdCyl(q299, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u296 = mU(u296, m300);
    }
    {
      M m301 = M(sdBox(q295, vec3(0.165, 0.0434, 0.2635)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u296 = mU(u296, m301);
    }
    u0 = mU(u0, u296);
  }
  {
    vec3 q302 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.1, 0.5, -3.05));
    vec3 q303 = q302 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u304 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q305 = q303 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m306 = M(sdCyl(q305, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u304 = mU(u304, m306);
    }
    {
      vec3 q307 = q303 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m308 = M(sdCyl(q307, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u304 = mU(u304, m308);
    }
    {
      M m309 = M(sdBox(q303, vec3(0.165, 0.0434, 0.2635)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u304 = mU(u304, m309);
    }
    u0 = mU(u0, u304);
  }
  {
    vec3 q310 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.1, 0.5, -8.05));
    vec3 q311 = q310 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u312 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q313 = q311 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m314 = M(sdCyl(q313, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u312 = mU(u312, m314);
    }
    {
      vec3 q315 = q311 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m316 = M(sdCyl(q315, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u312 = mU(u312, m316);
    }
    {
      M m317 = M(sdBox(q311, vec3(0.165, 0.0434, 0.2635)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u312 = mU(u312, m317);
    }
    u0 = mU(u0, u312);
  }
  {
    vec3 q318 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.1, 0.5, -6.9));
    vec3 q319 = q318 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u320 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q321 = q319 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m322 = M(sdCyl(q321, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u320 = mU(u320, m322);
    }
    {
      vec3 q323 = q319 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m324 = M(sdCyl(q323, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u320 = mU(u320, m324);
    }
    {
      M m325 = M(sdBox(q319, vec3(0.165, 0.0434, 0.2635)), vec3(0.050876, 0.050876, 0.063724), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u320 = mU(u320, m325);
    }
    u0 = mU(u0, u320);
  }
  {
    vec3 q326 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.1, 0.55, -3.05));
    vec3 q327 = q326 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u328 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q329 = q327 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m330 = M(sdCyl(q329, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u328 = mU(u328, m330);
    }
    {
      vec3 q331 = q327 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m332 = M(sdCyl(q331, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u328 = mU(u328, m332);
    }
    {
      M m333 = M(sdBox(q327, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u328 = mU(u328, m333);
    }
    {
      vec3 q334 = q327 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m335 = M(sdBox(q334, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u328 = mU(u328, m335);
    }
    {
      vec3 q336 = q327 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m337 = M(sdBox(q336, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u328 = mU(u328, m337);
    }
    {
      vec3 q338 = q327 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m339 = M(sdBox(q338, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u328 = mU(u328, m339);
    }
    {
      vec3 q340 = q327 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m341 = M(sdBox(q340, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u328 = mU(u328, m341);
    }
    u0 = mU(u0, u328);
  }
  {
    vec3 q342 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.1, 0.55, -8.05));
    vec3 q343 = q342 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u344 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q345 = q343 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m346 = M(sdCyl(q345, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u344 = mU(u344, m346);
    }
    {
      vec3 q347 = q343 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m348 = M(sdCyl(q347, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u344 = mU(u344, m348);
    }
    {
      M m349 = M(sdBox(q343, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u344 = mU(u344, m349);
    }
    {
      vec3 q350 = q343 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m351 = M(sdBox(q350, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u344 = mU(u344, m351);
    }
    {
      vec3 q352 = q343 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m353 = M(sdBox(q352, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u344 = mU(u344, m353);
    }
    {
      vec3 q354 = q343 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m355 = M(sdBox(q354, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u344 = mU(u344, m355);
    }
    {
      vec3 q356 = q343 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m357 = M(sdBox(q356, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u344 = mU(u344, m357);
    }
    u0 = mU(u0, u344);
  }
  {
    vec3 q358 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(4.1, 0.55, -6.9));
    vec3 q359 = q358 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u360 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q361 = q359 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m362 = M(sdCyl(q361, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u360 = mU(u360, m362);
    }
    {
      vec3 q363 = q359 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m364 = M(sdCyl(q363, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u360 = mU(u360, m364);
    }
    {
      M m365 = M(sdBox(q359, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u360 = mU(u360, m365);
    }
    {
      vec3 q366 = q359 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m367 = M(sdBox(q366, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u360 = mU(u360, m367);
    }
    {
      vec3 q368 = q359 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m369 = M(sdBox(q368, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u360 = mU(u360, m369);
    }
    {
      vec3 q370 = q359 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m371 = M(sdBox(q370, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u360 = mU(u360, m371);
    }
    {
      vec3 q372 = q359 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m373 = M(sdBox(q372, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u360 = mU(u360, m373);
    }
    u0 = mU(u0, u360);
  }
  {
    vec3 q374 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.3, 0.55, -3.05));
    vec3 q375 = q374 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u376 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q377 = q375 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m378 = M(sdCyl(q377, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u376 = mU(u376, m378);
    }
    {
      vec3 q379 = q375 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m380 = M(sdCyl(q379, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u376 = mU(u376, m380);
    }
    {
      M m381 = M(sdBox(q375, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u376 = mU(u376, m381);
    }
    {
      vec3 q382 = q375 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m383 = M(sdBox(q382, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u376 = mU(u376, m383);
    }
    {
      vec3 q384 = q375 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m385 = M(sdBox(q384, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u376 = mU(u376, m385);
    }
    {
      vec3 q386 = q375 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m387 = M(sdBox(q386, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u376 = mU(u376, m387);
    }
    {
      vec3 q388 = q375 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m389 = M(sdBox(q388, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u376 = mU(u376, m389);
    }
    u0 = mU(u0, u376);
  }
  {
    vec3 q390 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.3, 0.55, -8.05));
    vec3 q391 = q390 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u392 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q393 = q391 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m394 = M(sdCyl(q393, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u392 = mU(u392, m394);
    }
    {
      vec3 q395 = q391 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m396 = M(sdCyl(q395, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u392 = mU(u392, m396);
    }
    {
      M m397 = M(sdBox(q391, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u392 = mU(u392, m397);
    }
    {
      vec3 q398 = q391 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m399 = M(sdBox(q398, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u392 = mU(u392, m399);
    }
    {
      vec3 q400 = q391 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m401 = M(sdBox(q400, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u392 = mU(u392, m401);
    }
    {
      vec3 q402 = q391 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m403 = M(sdBox(q402, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u392 = mU(u392, m403);
    }
    {
      vec3 q404 = q391 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m405 = M(sdBox(q404, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u392 = mU(u392, m405);
    }
    u0 = mU(u0, u392);
  }
  {
    vec3 q406 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(6.3, 0.55, -6.9));
    vec3 q407 = q406 * rotEuler(vec3((uTime * 200.0), 0.0, 0.0));
    M u408 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q409 = q407 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m410 = M(sdCyl(q409, 0.41, 0.06) - 0.09, vec3(0.003936, 0.003936, 0.004401), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u408 = mU(u408, m410);
    }
    {
      vec3 q411 = q407 * mat3(0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0);
      M m412 = M(sdCyl(q411, 0.31, 0.156), vec3(0.570482, 0.603827, 0.67386), vec3(0.3, 0.8, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u408 = mU(u408, m412);
    }
    {
      M m413 = M(sdBox(q407, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u408 = mU(u408, m413);
    }
    {
      vec3 q414 = q407 * mat3(1.0, 0.0, 0.0, 0.0, 0.809017, 0.587785, 0.0, -0.587785, 0.809017);
      M m415 = M(sdBox(q414, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u408 = mU(u408, m415);
    }
    {
      vec3 q416 = q407 * mat3(1.0, 0.0, 0.0, 0.0, 0.309017, 0.951057, 0.0, -0.951057, 0.309017);
      M m417 = M(sdBox(q416, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u408 = mU(u408, m417);
    }
    {
      vec3 q418 = q407 * mat3(1.0, 0.0, 0.0, 0.0, -0.309017, 0.951057, 0.0, -0.951057, -0.309017);
      M m419 = M(sdBox(q418, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u408 = mU(u408, m419);
    }
    {
      vec3 q420 = q407 * mat3(1.0, 0.0, 0.0, 0.0, -0.809017, 0.587785, 0.0, -0.587785, -0.809017);
      M m421 = M(sdBox(q420, vec3(0.165, 0.0434, 0.2635)), vec3(0.214041, 0.233022, 0.273838), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u408 = mU(u408, m421);
    }
    u0 = mU(u0, u408);
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
