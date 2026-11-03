
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
    M m1 = M(p.y, vec3(0.158961, 0.254152, 0.068478), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m1);
  }
  {
    vec3 q2 = p;
    q2.x = -abs(q2.x);
    vec3 q3 = q2 - vec3(-4.5, 0.25, 0.0);
    M m4 = M(sdBox(q3, vec3(3.0, 0.25, 7.0)), vec3(0.114435, 0.194618, 0.048172), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m4);
  }
  if (sdBox(p - vec3(0.0, 0.790397, 0.0), vec3(3.287756, 0.525144, 0.78)) < u0.d) {
    vec3 q5 = p;
    q5.z = abs(q5.z);
    M u6 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q7 = q5 - vec3(-3.107787, 0.428875, 0.7);
      vec3 q8 = q7 * mat3(0.0, 0.0, -1.0, -0.468309, 0.883565, 0.0, 0.883565, 0.468309, 0.0);
      M m9 = M(sdBox(q8, vec3(0.07, 0.1, 0.139365)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m9);
    }
    {
      vec3 q10 = q5 - vec3(-2.921889, 0.523742, 0.7);
      vec3 q11 = q10 * mat3(0.0, 0.0, -1.0, -0.440685, 0.897662, 0.0, 0.897662, 0.440685, 0.0);
      M m12 = M(sdBox(q11, vec3(0.07, 0.1, 0.139365)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m12);
    }
    {
      vec3 q13 = q5 - vec3(-2.733136, 0.612788, 0.7);
      vec3 q14 = q13 * mat3(0.0, 0.0, -1.0, -0.412539, 0.91094, 0.0, 0.91094, 0.412539, 0.0);
      M m15 = M(sdBox(q14, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m15);
    }
    {
      vec3 q16 = q5 - vec3(-2.5417, 0.695909, 0.7);
      vec3 q17 = q16 * mat3(0.0, 0.0, -1.0, -0.383908, 0.923371, 0.0, 0.923371, 0.383908, 0.0);
      M m18 = M(sdBox(q17, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m18);
    }
    {
      vec3 q19 = q5 - vec3(-2.34776, 0.773006, 0.7);
      vec3 q20 = q19 * mat3(0.0, 0.0, -1.0, -0.354827, 0.934932, 0.0, 0.934932, 0.354827, 0.0);
      M m21 = M(sdBox(q20, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m21);
    }
    {
      vec3 q22 = q5 - vec3(-2.1515, 0.84399, 0.7);
      vec3 q23 = q22 * mat3(0.0, 0.0, -1.0, -0.325335, 0.945599, 0.0, 0.945599, 0.325335, 0.0);
      M m24 = M(sdBox(q23, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m24);
    }
    {
      vec3 q25 = q5 - vec3(-1.95311, 0.908779, 0.7);
      vec3 q26 = q25 * mat3(0.0, 0.0, -1.0, -0.295467, 0.955353, 0.0, 0.955353, 0.295467, 0.0);
      M m27 = M(sdBox(q26, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m27);
    }
    {
      vec3 q28 = q5 - vec3(-1.752781, 0.967299, 0.7);
      vec3 q29 = q28 * mat3(0.0, 0.0, -1.0, -0.265262, 0.964176, 0.0, 0.964176, 0.265262, 0.0);
      M m30 = M(sdBox(q29, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m30);
    }
    {
      vec3 q31 = q5 - vec3(-1.550708, 1.019483, 0.7);
      vec3 q32 = q31 * mat3(0.0, 0.0, -1.0, -0.234756, 0.972054, 0.0, 0.972054, 0.234756, 0.0);
      M m33 = M(sdBox(q32, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m33);
    }
    {
      vec3 q34 = q5 - vec3(-1.347091, 1.065272, 0.7);
      vec3 q35 = q34 * mat3(0.0, 0.0, -1.0, -0.203985, 0.978974, 0.0, 0.978974, 0.203985, 0.0);
      M m36 = M(sdBox(q35, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m36);
    }
    {
      vec3 q37 = q5 - vec3(-1.142131, 1.104614, 0.7);
      vec3 q38 = q37 * mat3(0.0, 0.0, -1.0, -0.172986, 0.984924, 0.0, 0.984924, 0.172986, 0.0);
      M m39 = M(sdBox(q38, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m39);
    }
    {
      vec3 q40 = q5 - vec3(-0.93603, 1.137466, 0.7);
      vec3 q41 = q40 * mat3(0.0, 0.0, -1.0, -0.141794, 0.989896, 0.0, 0.989896, 0.141794, 0.0);
      M m42 = M(sdBox(q41, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m42);
    }
    {
      vec3 q43 = q5 - vec3(-0.728995, 1.16379, 0.7);
      vec3 q44 = q43 * mat3(0.0, 0.0, -1.0, -0.110446, 0.993882, 0.0, 0.993882, 0.110446, 0.0);
      M m45 = M(sdBox(q44, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m45);
    }
    {
      vec3 q46 = q5 - vec3(-0.521232, 1.183559, 0.7);
      vec3 q47 = q46 * mat3(0.0, 0.0, -1.0, -0.078977, 0.996876, 0.0, 0.996876, 0.078977, 0.0);
      M m48 = M(sdBox(q47, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m48);
    }
    {
      vec3 q49 = q5 - vec3(-0.312948, 1.196751, 0.7);
      vec3 q50 = q49 * mat3(0.0, 0.0, -1.0, -0.04742, 0.998875, 0.0, 0.998875, 0.04742, 0.0);
      M m51 = M(sdBox(q50, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m51);
    }
    {
      vec3 q52 = q5 - vec3(-0.104351, 1.20335, 0.7);
      vec3 q53 = q52 * mat3(0.0, 0.0, -1.0, -0.015813, 0.999875, 0.0, 0.999875, 0.015813, 0.0);
      M m54 = M(sdBox(q53, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m54);
    }
    {
      vec3 q55 = q5 - vec3(0.104351, 1.20335, 0.7);
      vec3 q56 = q55 * mat3(0.0, 0.0, -1.0, 0.015813, 0.999875, 0.0, 0.999875, -0.015813, 0.0);
      M m57 = M(sdBox(q56, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m57);
    }
    {
      vec3 q58 = q5 - vec3(0.312948, 1.196751, 0.7);
      vec3 q59 = q58 * mat3(0.0, 0.0, -1.0, 0.04742, 0.998875, 0.0, 0.998875, -0.04742, 0.0);
      M m60 = M(sdBox(q59, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m60);
    }
    {
      vec3 q61 = q5 - vec3(0.521232, 1.183559, 0.7);
      vec3 q62 = q61 * mat3(0.0, 0.0, -1.0, 0.078977, 0.996876, 0.0, 0.996876, -0.078977, 0.0);
      M m63 = M(sdBox(q62, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m63);
    }
    {
      vec3 q64 = q5 - vec3(0.728995, 1.16379, 0.7);
      vec3 q65 = q64 * mat3(0.0, 0.0, -1.0, 0.110446, 0.993882, 0.0, 0.993882, -0.110446, 0.0);
      M m66 = M(sdBox(q65, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m66);
    }
    {
      vec3 q67 = q5 - vec3(0.93603, 1.137466, 0.7);
      vec3 q68 = q67 * mat3(0.0, 0.0, -1.0, 0.141794, 0.989896, 0.0, 0.989896, -0.141794, 0.0);
      M m69 = M(sdBox(q68, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m69);
    }
    {
      vec3 q70 = q5 - vec3(1.142131, 1.104614, 0.7);
      vec3 q71 = q70 * mat3(0.0, 0.0, -1.0, 0.172986, 0.984924, 0.0, 0.984924, -0.172986, 0.0);
      M m72 = M(sdBox(q71, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m72);
    }
    {
      vec3 q73 = q5 - vec3(1.347091, 1.065272, 0.7);
      vec3 q74 = q73 * mat3(0.0, 0.0, -1.0, 0.203985, 0.978974, 0.0, 0.978974, -0.203985, 0.0);
      M m75 = M(sdBox(q74, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m75);
    }
    {
      vec3 q76 = q5 - vec3(1.550708, 1.019483, 0.7);
      vec3 q77 = q76 * mat3(0.0, 0.0, -1.0, 0.234756, 0.972054, 0.0, 0.972054, -0.234756, 0.0);
      M m78 = M(sdBox(q77, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m78);
    }
    {
      vec3 q79 = q5 - vec3(1.752781, 0.967299, 0.7);
      vec3 q80 = q79 * mat3(0.0, 0.0, -1.0, 0.265262, 0.964176, 0.0, 0.964176, -0.265262, 0.0);
      M m81 = M(sdBox(q80, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m81);
    }
    {
      vec3 q82 = q5 - vec3(1.95311, 0.908779, 0.7);
      vec3 q83 = q82 * mat3(0.0, 0.0, -1.0, 0.295467, 0.955353, 0.0, 0.955353, -0.295467, 0.0);
      M m84 = M(sdBox(q83, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m84);
    }
    {
      vec3 q85 = q5 - vec3(2.1515, 0.84399, 0.7);
      vec3 q86 = q85 * mat3(0.0, 0.0, -1.0, 0.325335, 0.945599, 0.0, 0.945599, -0.325335, 0.0);
      M m87 = M(sdBox(q86, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m87);
    }
    {
      vec3 q88 = q5 - vec3(2.34776, 0.773006, 0.7);
      vec3 q89 = q88 * mat3(0.0, 0.0, -1.0, 0.354827, 0.934932, 0.0, 0.934932, -0.354827, 0.0);
      M m90 = M(sdBox(q89, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m90);
    }
    {
      vec3 q91 = q5 - vec3(2.5417, 0.695909, 0.7);
      vec3 q92 = q91 * mat3(0.0, 0.0, -1.0, 0.383908, 0.923371, 0.0, 0.923371, -0.383908, 0.0);
      M m93 = M(sdBox(q92, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m93);
    }
    {
      vec3 q94 = q5 - vec3(2.733136, 0.612788, 0.7);
      vec3 q95 = q94 * mat3(0.0, 0.0, -1.0, 0.412539, 0.91094, 0.0, 0.91094, -0.412539, 0.0);
      M m96 = M(sdBox(q95, vec3(0.07, 0.1, 0.139364)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m96);
    }
    {
      vec3 q97 = q5 - vec3(2.921889, 0.523742, 0.7);
      vec3 q98 = q97 * mat3(0.0, 0.0, -1.0, 0.440685, 0.897662, 0.0, 0.897662, -0.440685, 0.0);
      M m99 = M(sdBox(q98, vec3(0.07, 0.1, 0.139365)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m99);
    }
    {
      vec3 q100 = q5 - vec3(3.107787, 0.428875, 0.7);
      vec3 q101 = q100 * mat3(0.0, 0.0, -1.0, 0.468309, 0.883565, 0.0, 0.883565, -0.468309, 0.0);
      M m102 = M(sdBox(q101, vec3(0.07, 0.1, 0.139365)), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u6 = mU(u6, m102);
    }
    u0 = mU(u0, u6);
  }
  if (sdBox(p - vec3(0.0, 1.3625, 0.0), vec3(3.25, 0.8725, 0.85)) < u0.d) {
    vec3 q103 = p;
    q103.z = abs(q103.z);
    M u104 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q105 = q103 - vec3(-3.2, 0.5, 0.8);
      vec3 q106 = q105 - vec3(0.0, 0.45, 0.0);
      M m107 = M(sdCyl(q106, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m107);
    }
    {
      vec3 q108 = q103 - vec3(-2.445333, 0.855975, 0.8);
      vec3 q109 = q108 - vec3(0.0, 0.45, 0.0);
      M m110 = M(sdCyl(q109, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m110);
    }
    {
      vec3 q111 = q103 - vec3(-1.652156, 1.114983, 0.8);
      vec3 q112 = q111 - vec3(0.0, 0.45, 0.0);
      M m113 = M(sdCyl(q112, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m113);
    }
    {
      vec3 q114 = q103 - vec3(-0.832721, 1.272264, 0.8);
      vec3 q115 = q114 - vec3(0.0, 0.45, 0.0);
      M m116 = M(sdCyl(q115, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m116);
    }
    {
      vec3 q117 = q103 - vec3(0.0, 1.325, 0.8);
      vec3 q118 = q117 - vec3(0.0, 0.45, 0.0);
      M m119 = M(sdCyl(q118, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m119);
    }
    {
      vec3 q120 = q103 - vec3(0.832721, 1.272264, 0.8);
      vec3 q121 = q120 - vec3(0.0, 0.45, 0.0);
      M m122 = M(sdCyl(q121, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m122);
    }
    {
      vec3 q123 = q103 - vec3(1.652156, 1.114983, 0.8);
      vec3 q124 = q123 - vec3(0.0, 0.45, 0.0);
      M m125 = M(sdCyl(q124, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m125);
    }
    {
      vec3 q126 = q103 - vec3(2.445333, 0.855975, 0.8);
      vec3 q127 = q126 - vec3(0.0, 0.45, 0.0);
      M m128 = M(sdCyl(q127, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m128);
    }
    {
      vec3 q129 = q103 - vec3(3.2, 0.5, 0.8);
      vec3 q130 = q129 - vec3(0.0, 0.45, 0.0);
      M m131 = M(sdCyl(q130, 0.04, 0.45), vec3(0.102242, 0.046665, 0.0185), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u104 = mU(u104, m131);
    }
    u0 = mU(u0, u104);
  }
  if (sdBox(p - vec3(0.0, 1.80563, 0.0), vec3(3.26416, 0.46979, 0.85)) < u0.d) {
    vec3 q132 = p;
    q132.z = abs(q132.z);
    M u133 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q134 = q132 - vec3(-3.138689, 1.432902, 0.8);
      vec3 q135 = q134 * mat3(0.472862, -0.881137, 0.0, 0.881137, 0.472862, 0.0, 0.0, 0.0, 1.0);
      M m136 = M(sdCapsule(q135, 0.04, 0.069581), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m136);
    }
    {
      vec3 q137 = q132 - vec3(-3.015406, 1.497432, 0.8);
      vec3 q138 = q137 * mat3(0.454566, -0.890713, 0.0, 0.890713, 0.454566, 0.0, 0.0, 0.0, 1.0);
      M m139 = M(sdCapsule(q138, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m139);
    }
    {
      vec3 q140 = q132 - vec3(-2.890819, 1.559396, 0.8);
      vec3 q141 = q140 * mat3(0.436031, -0.899932, 0.0, 0.899932, 0.436031, 0.0, 0.0, 0.0, 1.0);
      M m142 = M(sdCapsule(q141, 0.04, 0.069576), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m142);
    }
    {
      vec3 q143 = q132 - vec3(-2.764973, 1.618767, 0.8);
      vec3 q144 = q143 * mat3(0.417266, -0.908784, 0.0, 0.908784, 0.417266, 0.0, 0.0, 0.0, 1.0);
      M m145 = M(sdCapsule(q144, 0.04, 0.06958), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m145);
    }
    {
      vec3 q146 = q132 - vec3(-2.63792, 1.675511, 0.8);
      vec3 q147 = q146 * mat3(0.398283, -0.917262, 0.0, 0.917262, 0.398283, 0.0, 0.0, 0.0, 1.0);
      M m148 = M(sdCapsule(q147, 0.04, 0.069576), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m148);
    }
    {
      vec3 q149 = q132 - vec3(-2.509716, 1.729599, 0.8);
      vec3 q150 = q149 * mat3(0.379093, -0.925359, 0.0, 0.925359, 0.379093, 0.0, 0.0, 0.0, 1.0);
      M m151 = M(sdCapsule(q150, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m151);
    }
    {
      vec3 q152 = q132 - vec3(-2.380411, 1.781003, 0.8);
      vec3 q153 = q152 * mat3(0.359705, -0.933066, 0.0, 0.933066, 0.359705, 0.0, 0.0, 0.0, 1.0);
      M m154 = M(sdCapsule(q153, 0.04, 0.069579), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m154);
    }
    {
      vec3 q155 = q132 - vec3(-2.250061, 1.829696, 0.8);
      vec3 q156 = q155 * mat3(0.340131, -0.940378, 0.0, 0.940378, 0.340131, 0.0, 0.0, 0.0, 1.0);
      M m157 = M(sdCapsule(q156, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m157);
    }
    {
      vec3 q158 = q132 - vec3(-2.118723, 1.875652, 0.8);
      vec3 q159 = q158 * mat3(0.320383, -0.947288, 0.0, 0.947288, 0.320383, 0.0, 0.0, 0.0, 1.0);
      M m160 = M(sdCapsule(q159, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m160);
    }
    {
      vec3 q161 = q132 - vec3(-1.98645, 1.91885, 0.8);
      vec3 q162 = q161 * mat3(0.300471, -0.953791, 0.0, 0.953791, 0.300471, 0.0, 0.0, 0.0, 1.0);
      M m163 = M(sdCapsule(q162, 0.04, 0.069579), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m163);
    }
    {
      vec3 q164 = q132 - vec3(-1.853301, 1.959266, 0.8);
      vec3 q165 = q164 * mat3(0.280405, -0.959882, 0.0, 0.959882, 0.280405, 0.0, 0.0, 0.0, 1.0);
      M m166 = M(sdCapsule(q165, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m166);
    }
    {
      vec3 q167 = q132 - vec3(-1.719336, 1.996879, 0.8);
      vec3 q168 = q167 * mat3(0.260198, -0.965555, 0.0, 0.965555, 0.260198, 0.0, 0.0, 0.0, 1.0);
      M m169 = M(sdCapsule(q168, 0.04, 0.069576), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m169);
    }
    {
      vec3 q170 = q132 - vec3(-1.584608, 2.031672, 0.8);
      vec3 q171 = q170 * mat3(0.23986, -0.970807, 0.0, 0.970807, 0.23986, 0.0, 0.0, 0.0, 1.0);
      M m172 = M(sdCapsule(q171, 0.04, 0.069579), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m172);
    }
    {
      vec3 q173 = q132 - vec3(-1.449178, 2.063627, 0.8);
      vec3 q174 = q173 * mat3(0.219401, -0.975635, 0.0, 0.975635, 0.219401, 0.0, 0.0, 0.0, 1.0);
      M m175 = M(sdCapsule(q174, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m175);
    }
    {
      vec3 q176 = q132 - vec3(-1.313109, 2.092726, 0.8);
      vec3 q177 = q176 * mat3(0.198833, -0.980033, 0.0, 0.980033, 0.198833, 0.0, 0.0, 0.0, 1.0);
      M m178 = M(sdCapsule(q177, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m178);
    }
    {
      vec3 q179 = q132 - vec3(-1.176457, 2.118957, 0.8);
      vec3 q180 = q179 * mat3(0.178167, -0.984, 0.0, 0.984, 0.178167, 0.0, 0.0, 0.0, 1.0);
      M m181 = M(sdCapsule(q180, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m181);
    }
    {
      vec3 q182 = q132 - vec3(-1.039281, 2.142306, 0.8);
      vec3 q183 = q182 * mat3(0.157412, -0.987533, 0.0, 0.987533, 0.157412, 0.0, 0.0, 0.0, 1.0);
      M m184 = M(sdCapsule(q183, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m184);
    }
    {
      vec3 q185 = q132 - vec3(-0.901646, 2.162761, 0.8);
      vec3 q186 = q185 * mat3(0.13658, -0.990629, 0.0, 0.990629, 0.13658, 0.0, 0.0, 0.0, 1.0);
      M m187 = M(sdCapsule(q186, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m187);
    }
    {
      vec3 q188 = q132 - vec3(-0.763611, 2.180313, 0.8);
      vec3 q189 = q188 * mat3(0.11568, -0.993286, 0.0, 0.993286, 0.11568, 0.0, 0.0, 0.0, 1.0);
      M m190 = M(sdCapsule(q189, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m190);
    }
    {
      vec3 q191 = q132 - vec3(-0.625235, 2.194952, 0.8);
      vec3 q192 = q191 * mat3(0.094725, -0.995504, 0.0, 0.995504, 0.094725, 0.0, 0.0, 0.0, 1.0);
      M m193 = M(sdCapsule(q192, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m193);
    }
    {
      vec3 q194 = q132 - vec3(-0.486582, 2.206672, 0.8);
      vec3 q195 = q194 * mat3(0.073722, -0.997279, 0.0, 0.997279, 0.073722, 0.0, 0.0, 0.0, 1.0);
      M m196 = M(sdCapsule(q195, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m196);
    }
    {
      vec3 q197 = q132 - vec3(-0.347714, 2.215467, 0.8);
      vec3 q198 = q197 * mat3(0.052684, -0.998611, 0.0, 0.998611, 0.052684, 0.0, 0.0, 0.0, 1.0);
      M m199 = M(sdCapsule(q198, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m199);
    }
    {
      vec3 q200 = q132 - vec3(-0.20869, 2.221333, 0.8);
      vec3 q201 = q200 * mat3(0.031621, -0.9995, 0.0, 0.9995, 0.031621, 0.0, 0.0, 0.0, 1.0);
      M m202 = M(sdCapsule(q201, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m202);
    }
    {
      vec3 q203 = q132 - vec3(-0.069574, 2.224267, 0.8);
      vec3 q204 = q203 * mat3(0.010542, -0.999944, 0.0, 0.999944, 0.010542, 0.0, 0.0, 0.0, 1.0);
      M m205 = M(sdCapsule(q204, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m205);
    }
    {
      vec3 q206 = q132 - vec3(0.069574, 2.224267, 0.8);
      vec3 q207 = q206 * mat3(-0.010542, -0.999944, 0.0, 0.999944, -0.010542, 0.0, 0.0, 0.0, 1.0);
      M m208 = M(sdCapsule(q207, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m208);
    }
    {
      vec3 q209 = q132 - vec3(0.20869, 2.221333, 0.8);
      vec3 q210 = q209 * mat3(-0.031621, -0.9995, 0.0, 0.9995, -0.031621, 0.0, 0.0, 0.0, 1.0);
      M m211 = M(sdCapsule(q210, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m211);
    }
    {
      vec3 q212 = q132 - vec3(0.347714, 2.215467, 0.8);
      vec3 q213 = q212 * mat3(-0.052684, -0.998611, 0.0, 0.998611, -0.052684, 0.0, 0.0, 0.0, 1.0);
      M m214 = M(sdCapsule(q213, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m214);
    }
    {
      vec3 q215 = q132 - vec3(0.486582, 2.206672, 0.8);
      vec3 q216 = q215 * mat3(-0.073722, -0.997279, 0.0, 0.997279, -0.073722, 0.0, 0.0, 0.0, 1.0);
      M m217 = M(sdCapsule(q216, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m217);
    }
    {
      vec3 q218 = q132 - vec3(0.625235, 2.194952, 0.8);
      vec3 q219 = q218 * mat3(-0.094725, -0.995504, 0.0, 0.995504, -0.094725, 0.0, 0.0, 0.0, 1.0);
      M m220 = M(sdCapsule(q219, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m220);
    }
    {
      vec3 q221 = q132 - vec3(0.763611, 2.180313, 0.8);
      vec3 q222 = q221 * mat3(-0.11568, -0.993286, 0.0, 0.993286, -0.11568, 0.0, 0.0, 0.0, 1.0);
      M m223 = M(sdCapsule(q222, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m223);
    }
    {
      vec3 q224 = q132 - vec3(0.901646, 2.162761, 0.8);
      vec3 q225 = q224 * mat3(-0.13658, -0.990629, 0.0, 0.990629, -0.13658, 0.0, 0.0, 0.0, 1.0);
      M m226 = M(sdCapsule(q225, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m226);
    }
    {
      vec3 q227 = q132 - vec3(1.039281, 2.142306, 0.8);
      vec3 q228 = q227 * mat3(-0.157412, -0.987533, 0.0, 0.987533, -0.157412, 0.0, 0.0, 0.0, 1.0);
      M m229 = M(sdCapsule(q228, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m229);
    }
    {
      vec3 q230 = q132 - vec3(1.176457, 2.118957, 0.8);
      vec3 q231 = q230 * mat3(-0.178167, -0.984, 0.0, 0.984, -0.178167, 0.0, 0.0, 0.0, 1.0);
      M m232 = M(sdCapsule(q231, 0.04, 0.069578), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m232);
    }
    {
      vec3 q233 = q132 - vec3(1.313109, 2.092726, 0.8);
      vec3 q234 = q233 * mat3(-0.198833, -0.980033, 0.0, 0.980033, -0.198833, 0.0, 0.0, 0.0, 1.0);
      M m235 = M(sdCapsule(q234, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m235);
    }
    {
      vec3 q236 = q132 - vec3(1.449178, 2.063627, 0.8);
      vec3 q237 = q236 * mat3(-0.219401, -0.975635, 0.0, 0.975635, -0.219401, 0.0, 0.0, 0.0, 1.0);
      M m238 = M(sdCapsule(q237, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m238);
    }
    {
      vec3 q239 = q132 - vec3(1.584608, 2.031672, 0.8);
      vec3 q240 = q239 * mat3(-0.23986, -0.970807, 0.0, 0.970807, -0.23986, 0.0, 0.0, 0.0, 1.0);
      M m241 = M(sdCapsule(q240, 0.04, 0.069579), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m241);
    }
    {
      vec3 q242 = q132 - vec3(1.719336, 1.996879, 0.8);
      vec3 q243 = q242 * mat3(-0.260198, -0.965555, 0.0, 0.965555, -0.260198, 0.0, 0.0, 0.0, 1.0);
      M m244 = M(sdCapsule(q243, 0.04, 0.069576), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m244);
    }
    {
      vec3 q245 = q132 - vec3(1.853301, 1.959266, 0.8);
      vec3 q246 = q245 * mat3(-0.280405, -0.959882, 0.0, 0.959882, -0.280405, 0.0, 0.0, 0.0, 1.0);
      M m247 = M(sdCapsule(q246, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m247);
    }
    {
      vec3 q248 = q132 - vec3(1.98645, 1.91885, 0.8);
      vec3 q249 = q248 * mat3(-0.300471, -0.953791, 0.0, 0.953791, -0.300471, 0.0, 0.0, 0.0, 1.0);
      M m250 = M(sdCapsule(q249, 0.04, 0.069579), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m250);
    }
    {
      vec3 q251 = q132 - vec3(2.118723, 1.875652, 0.8);
      vec3 q252 = q251 * mat3(-0.320383, -0.947288, 0.0, 0.947288, -0.320383, 0.0, 0.0, 0.0, 1.0);
      M m253 = M(sdCapsule(q252, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m253);
    }
    {
      vec3 q254 = q132 - vec3(2.250061, 1.829696, 0.8);
      vec3 q255 = q254 * mat3(-0.340131, -0.940378, 0.0, 0.940378, -0.340131, 0.0, 0.0, 0.0, 1.0);
      M m256 = M(sdCapsule(q255, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m256);
    }
    {
      vec3 q257 = q132 - vec3(2.380411, 1.781003, 0.8);
      vec3 q258 = q257 * mat3(-0.359705, -0.933066, 0.0, 0.933066, -0.359705, 0.0, 0.0, 0.0, 1.0);
      M m259 = M(sdCapsule(q258, 0.04, 0.069579), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m259);
    }
    {
      vec3 q260 = q132 - vec3(2.509716, 1.729599, 0.8);
      vec3 q261 = q260 * mat3(-0.379093, -0.925359, 0.0, 0.925359, -0.379093, 0.0, 0.0, 0.0, 1.0);
      M m262 = M(sdCapsule(q261, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m262);
    }
    {
      vec3 q263 = q132 - vec3(2.63792, 1.675511, 0.8);
      vec3 q264 = q263 * mat3(-0.398283, -0.917262, 0.0, 0.917262, -0.398283, 0.0, 0.0, 0.0, 1.0);
      M m265 = M(sdCapsule(q264, 0.04, 0.069576), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m265);
    }
    {
      vec3 q266 = q132 - vec3(2.764973, 1.618767, 0.8);
      vec3 q267 = q266 * mat3(-0.417266, -0.908784, 0.0, 0.908784, -0.417266, 0.0, 0.0, 0.0, 1.0);
      M m268 = M(sdCapsule(q267, 0.04, 0.06958), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m268);
    }
    {
      vec3 q269 = q132 - vec3(2.890819, 1.559396, 0.8);
      vec3 q270 = q269 * mat3(-0.436031, -0.899932, 0.0, 0.899932, -0.436031, 0.0, 0.0, 0.0, 1.0);
      M m271 = M(sdCapsule(q270, 0.04, 0.069576), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m271);
    }
    {
      vec3 q272 = q132 - vec3(3.015406, 1.497432, 0.8);
      vec3 q273 = q272 * mat3(-0.454566, -0.890713, 0.0, 0.890713, -0.454566, 0.0, 0.0, 0.0, 1.0);
      M m274 = M(sdCapsule(q273, 0.04, 0.069577), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m274);
    }
    {
      vec3 q275 = q132 - vec3(3.138689, 1.432902, 0.8);
      vec3 q276 = q275 * mat3(-0.472862, -0.881137, 0.0, 0.881137, -0.472862, 0.0, 0.0, 0.0, 1.0);
      M m277 = M(sdCapsule(q276, 0.04, 0.069581), vec3(0.147027, 0.068478, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u133 = mU(u133, m277);
    }
    u0 = mU(u0, u133);
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
