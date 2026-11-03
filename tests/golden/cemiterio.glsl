
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

uniform highp sampler2D uCode;
vec4 codeFetch(int col, int row) {
  int index = row * 5 + col;
  int width = textureSize(uCode, 0).x;
  return texelFetch(uCode, ivec2(index % width, index / width), 0);
}
M ci0(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    vec3 q1 = p - vec3(0.0, 0.08, 0.0);
    M m2 = M(sdCBox(q1, vec3(0.07, 0.08, 1.45), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.161572, 0.166226, 0.156994), vec4(1.0, 0.15, 1.0, 0.0), p, 0.0);
    u0 = mU(u0, m2);
  }
  if (sdBox(p - vec3(0.0, 0.4, 0.0), vec3(0.035, 0.25, 1.46)) < u0.d) {
    vec3 q3 = p - vec3(0.0, 0.16, 0.0);
    M u4 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    if (sdBox(q3 - vec3(0.0, 0.24, 0.0), vec3(0.035, 0.25, 1.415)) < u4.d) {
      vec3 q5 = q3 - vec3(0.0, 0.24, 0.0);
      vec3 id6 = clamp(round(q5 / vec3(1.0, 1.0, 0.12) + vec3(0.0, 0.0, 11.5)), vec3(0.0), vec3(0.0, 0.0, 23.0));
      vec3 q7 = q5 - vec3(1.0, 1.0, 0.12) * (id6 - vec3(0.0, 0.0, 11.5));
      vec3 q8 = q7 - vec3(0.0, -0.24, 0.0);
      M u9 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
      {
        vec3 q10 = q8 - vec3(0.0, 0.21, 0.0);
        M m11 = M(sdCyl(q10, 0.012, 0.21), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u9 = mU(u9, m11);
      }
      {
        vec3 q12 = q8 - vec3(0.0, 0.45, 0.0);
        M m13 = M(sdCone(q12, 0.03, 0.025, 0.0), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
        u9 = mU(u9, m13);
      }
      u4 = mU(u4, u9);
    }
    {
      vec3 q14 = q3 - vec3(0.0, 0.36, 0.0);
      M m15 = M(sdBox(q14, vec3(0.0125, 0.0125, 1.45)), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u4 = mU(u4, m15);
    }
    {
      vec3 q16 = q3 - vec3(0.0, 0.2, 0.0);
      M m17 = M(sdBox(q16, vec3(0.0125, 0.0125, 1.45)), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u4 = mU(u4, m17);
    }
    u0 = mU(u0, u4);
  }
  return u0;
}
M ci1(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    vec3 q1 = p - vec3(0.0, 0.275, 0.0);
    M m2 = M(sdCBox(q1, vec3(0.1, 0.275, 0.1), 0.02), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m2);
  }
  {
    vec3 q3 = p - vec3(0.0, 0.58, 0.0);
    M m4 = M(sdCBox(q3, vec3(0.13, 0.03, 0.13), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m4);
  }
  {
    vec3 q5 = p - vec3(0.0, 0.65, 0.0);
    M m6 = M(sdPyramid((q5 + vec3(0.0, 0.04, 0.0)) / 0.18, 0.444444) * 0.18, vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m6);
  }
  return u0;
}
M ci2(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  if (sdBox(p - vec3(0.0, 0.0, 0.0), vec3(0.126619, 0.09, 0.126619)) < u0.d) {
    float sec1 = 0.785398, rr3 = length(p.xz);
    float an2 = mod(atan(p.z, p.x) + 0.5 * sec1, sec1) - 0.5 * sec1;
    vec3 q4 = vec3(rr3 * cos(an2), p.y, rr3 * sin(an2));
    vec3 q5 = q4 - vec3(0.055, 0.0, 0.0);
    M m6 = M(sdEllipsoid(q5, vec3(0.045, 0.08, 0.06)), vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m7 = M(length(p) - 0.07, vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m8 = mUs(m6, m7, 0.03);
    u0 = mU(u0, m8);
  }
  {
    M m9 = M(sdRoundCone(p, vec3(0.0, 0.07, 0.0), vec3(0.01, 0.105, 0.005), 0.012, 0.007), vec3(0.102242, 0.144128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m9);
  }
  return u0;
}

M codeM(vec3 p) {
  M u0 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  {
    vec3 q1 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, -0.15, 0.0));
    M m2 = M(sdCBox(q1, vec3(2.2, 0.15, 1.7), 0.04), vec3(0.158961, 0.168269, 0.158961), vec3(0.6, 0.0, 0.0), vec3(0.07948, 0.084135, 0.07948), vec4(1.0, 0.3, 1.0, 0.0), q1, 0.0);
    u0 = mU(u0, m2);
  }
  if (sdBox(p - vec3(0.0, 0.025, 0.0), vec3(2.195, 0.035, 1.645)) < u0.d) {
    vec3 q3 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.025, 0.0));
    vec3 id4 = clamp(round(q3 / vec3(0.55, 1.0, 0.55) + vec3(3.5, 0.0, 2.5)), vec3(0.0), vec3(7.0, 0.0, 5.0));
    vec3 q5 = q3 - vec3(0.55, 1.0, 0.55) * (id4 - vec3(3.5, 0.0, 2.5));
    M m6 = M(sdCBox(q5, vec3(0.26, 0.025, 0.26), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.177729, 0.182848, 0.172694), vec4(8.0, 0.25, 1.0, 0.0), q5, 0.0);
    u0 = mU(u0, m6);
  }
  if (sdBox(p - vec3(-0.55, 0.06, 0.3), vec3(0.38, 0.03, 1.33)) < u0.d) {
    vec3 q7 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.55, 0.06, 0.3));
    vec3 id8 = clamp(round(q7 / vec3(0.19, 1.0, 0.19) + vec3(1.5, 0.0, 6.5)), vec3(0.0), vec3(3.0, 0.0, 13.0));
    vec3 q9 = q7 - vec3(0.19, 1.0, 0.19) * (id8 - vec3(1.5, 0.0, 6.5));
    M m10 = M(sdCBox(q9, vec3(0.085, 0.02, 0.085), 0.012), vec3(0.205079, 0.212231, 0.201556), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m10);
  }
  {
    vec3 q11 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.08, -1.55));
    M m12 = M(sdCBox(q11, vec3(1.95, 0.08, 0.07), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.161572, 0.166226, 0.156994), vec4(1.0, 0.15, 1.0, 0.0), q11, 0.0);
    u0 = mU(u0, m12);
  }
  if (sdBox(p - vec3(0.0, 0.4, -1.55), vec3(1.895, 0.25, 0.035)) < u0.d) {
    vec3 q13 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.0, 0.4, -1.55));
    vec3 id14 = clamp(round(q13 / vec3(0.12, 1.0, 1.0) + vec3(15.5, 0.0, 0.0)), vec3(0.0), vec3(31.0, 0.0, 0.0));
    vec3 q15 = q13 - vec3(0.12, 1.0, 1.0) * (id14 - vec3(15.5, 0.0, 0.0));
    vec3 q16 = q15 - vec3(0.0, -0.24, 0.0);
    M u17 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q18 = q16 - vec3(0.0, 0.21, 0.0);
      M m19 = M(sdCyl(q18, 0.012, 0.21), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u17 = mU(u17, m19);
    }
    {
      vec3 q20 = q16 - vec3(0.0, 0.45, 0.0);
      M m21 = M(sdCone(q20, 0.03, 0.025, 0.0), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u17 = mU(u17, m21);
    }
    u0 = mU(u0, u17);
  }
  {
    vec3 q22 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.35, 0.08, 1.55));
    M m23 = M(sdCBox(q22, vec3(0.625, 0.08, 0.07), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.161572, 0.166226, 0.156994), vec4(1.0, 0.15, 1.0, 0.0), q22, 0.0);
    u0 = mU(u0, m23);
  }
  if (sdBox(p - vec3(-1.35, 0.4, 1.55), vec3(0.575, 0.25, 0.035)) < u0.d) {
    vec3 q24 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.35, 0.4, 1.55));
    vec3 id25 = clamp(round(q24 / vec3(0.12, 1.0, 1.0) + vec3(4.5, 0.0, 0.0)), vec3(0.0), vec3(9.0, 0.0, 0.0));
    vec3 q26 = q24 - vec3(0.12, 1.0, 1.0) * (id25 - vec3(4.5, 0.0, 0.0));
    vec3 q27 = q26 - vec3(0.0, -0.24, 0.0);
    M u28 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q29 = q27 - vec3(0.0, 0.21, 0.0);
      M m30 = M(sdCyl(q29, 0.012, 0.21), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u28 = mU(u28, m30);
    }
    {
      vec3 q31 = q27 - vec3(0.0, 0.45, 0.0);
      M m32 = M(sdCone(q31, 0.03, 0.025, 0.0), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u28 = mU(u28, m32);
    }
    u0 = mU(u0, u28);
  }
  {
    vec3 q33 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.95, 0.08, 1.55));
    M m34 = M(sdCBox(q33, vec3(1.025, 0.08, 0.07), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.161572, 0.166226, 0.156994), vec4(1.0, 0.15, 1.0, 0.0), q33, 0.0);
    u0 = mU(u0, m34);
  }
  if (sdBox(p - vec3(0.95, 0.4, 1.55), vec3(0.995, 0.25, 0.035)) < u0.d) {
    vec3 q35 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.95, 0.4, 1.55));
    vec3 id36 = clamp(round(q35 / vec3(0.12, 1.0, 1.0) + vec3(8.0, 0.0, 0.0)), vec3(0.0), vec3(16.0, 0.0, 0.0));
    vec3 q37 = q35 - vec3(0.12, 1.0, 1.0) * (id36 - vec3(8.0, 0.0, 0.0));
    vec3 q38 = q37 - vec3(0.0, -0.24, 0.0);
    M u39 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      vec3 q40 = q38 - vec3(0.0, 0.21, 0.0);
      M m41 = M(sdCyl(q40, 0.012, 0.21), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u39 = mU(u39, m41);
    }
    {
      vec3 q42 = q38 - vec3(0.0, 0.45, 0.0);
      M m43 = M(sdCone(q42, 0.03, 0.025, 0.0), vec3(0.024158, 0.026241, 0.029557), vec3(0.5, 0.6, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u39 = mU(u39, m43);
    }
    u0 = mU(u0, u39);
  }
  {
    vec3 q44 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.85, 0.4, 1.55));
    M m45 = M(sdCBox(q44, vec3(0.1, 0.4, 0.1), 0.02), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m45);
  }
  {
    vec3 q46 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.85, 0.83, 1.55));
    M m47 = M(sdCBox(q46, vec3(0.13, 0.03, 0.13), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m47);
  }
  {
    vec3 q48 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.2, 0.4, 1.55));
    M m49 = M(sdCBox(q48, vec3(0.1, 0.4, 0.1), 0.02), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m49);
  }
  {
    vec3 q50 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.2, 0.83, 1.55));
    M m51 = M(sdCBox(q50, vec3(0.13, 0.03, 0.13), 0.015), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m51);
  }
  {
    vec3 q52 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.525, 0.82, 1.55));
    vec3 q53 = q52 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
    M m54 = M(sdTorus(q53, 0.33, 0.05), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q55 = q52 - vec3(0.0, 0.25, 0.0);
    M m56 = M(sdBox(q55, vec3(0.5, 0.25, 0.1)), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m57 = mI(m54, m56);
    u0 = mU(u0, m57);
  }
  if (sdBox(p - vec3(0.75, 0.57, -0.5), vec3(0.735, 0.53, 0.585)) < u0.d) {
    vec3 q58 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.75, 0.05, -0.5));
    vec3 q59 = q58 - vec3(0.0, 0.55, 0.0);
    M m60 = M(sdCBox(q59, vec3(0.65, 0.425, 0.5), 0.03), vec3(0.323143, 0.332452, 0.313989), vec3(0.6, 0.0, 0.0), vec3(0.254152, 0.262251, 0.246201), vec4(6.0, 0.3, 1.0, 0.4), q58, 0.0);
    vec3 q61 = q58 - vec3(0.0, 0.07, 0.0);
    M m62 = M(sdCBox(q61, vec3(0.725, 0.07, 0.575), 0.03), vec3(0.158961, 0.168269, 0.158961), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m63 = mMerge(m60, m62, 0.015, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
    vec3 q64 = q58 - vec3(0.0, 1.0, 0.0);
    M m65 = M(sdCBox(q64, vec3(0.7, 0.04, 0.55), 0.02), vec3(0.456411, 0.467784, 0.445201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m66 = mMerge(m63, m65, 0.015, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
    vec3 q67 = q58 - vec3(0.0, 0.38, 0.45);
    M u68 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m69 = M(sdBox(q67, vec3(0.2, 0.225, 0.1)), vec3(0.6, 0.6, 0.62), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u68 = mU(u68, m69);
    }
    {
      vec3 q70 = q67 - vec3(0.0, 0.225, 0.0);
      vec3 q71 = q70 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m72 = M(sdCyl(q71, 0.2, 0.1), vec3(0.6, 0.6, 0.62), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u68 = mU(u68, m72);
    }
    M m73 = mS(m66, u68);
    u0 = mU(u0, m73);
  }
  if (sdBox(p - vec3(0.75, 0.555, 0.01), vec3(0.26, 0.385, 0.07)) < u0.d) {
    vec3 q74 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.75, 0.05, -0.5));
    vec3 q75 = q74 - vec3(0.0, 0.38, 0.51);
    M u76 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m77 = M(sdBox(q75, vec3(0.25, 0.25, 0.06)), vec3(0.456411, 0.467784, 0.445201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m77);
    }
    {
      vec3 q78 = q75 - vec3(0.0, 0.25, 0.0);
      vec3 q79 = q78 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m80 = M(sdCyl(q79, 0.25, 0.06), vec3(0.456411, 0.467784, 0.445201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u76 = mU(u76, m80);
    }
    vec3 q81 = q74 - vec3(0.0, 0.38, 0.5);
    M u82 = M(1e10, vec3(0.0), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
    {
      M m83 = M(sdBox(q81, vec3(0.2, 0.225, 0.1)), vec3(0.456411, 0.467784, 0.445201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u82 = mU(u82, m83);
    }
    {
      vec3 q84 = q81 - vec3(0.0, 0.225, 0.0);
      vec3 q85 = q84 * mat3(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0);
      M m86 = M(sdCyl(q85, 0.2, 0.1), vec3(0.456411, 0.467784, 0.445201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      u82 = mU(u82, m86);
    }
    M m87 = mS(u76, u82);
    u0 = mU(u0, m87);
  }
  {
    vec3 q88 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.75, 0.05, -0.5));
    vec3 q89 = q88;
    q89.x = abs(q89.x);
    vec3 q90 = q89 - vec3(0.45, 0.45, 0.56);
    M m91 = M(sdCyl(q90, 0.05, 0.31), vec3(0.456411, 0.467784, 0.445201), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m91);
  }
  {
    vec3 q92 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.75, 1.36, -0.5));
    vec3 q93 = q92 - vec3(0.0, -0.02, 0.0);
    M m94 = M(sdPrism(q93, 0.79, 0.58, 0.64), vec3(0.584078, 0.132868, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m95 = M(sdPrism(q92, 0.75, 0.55, 0.6), vec3(0.745404, 0.194618, 0.027321), vec3(0.6, 0.0, 0.0), vec3(0.48515, 0.102242, 0.013702), vec4(6.0, 0.16, 1.0, 0.6), q92, 0.0);
    M m96 = mMerge(m94, m95, 0.01, 2, 0, vec3(0.0, 0.0, 0.0), 0.0);
    u0 = mU(u0, m96);
  }
  {
    vec3 q97 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m98 = M(sdRoundCone(q97, vec3(0.0, 0.0, 0.0), vec3(0.010741, 0.095, -0.000741), 0.0405, 0.037333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m98);
  }
  {
    vec3 q99 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m100 = M(sdRoundCone(q99, vec3(0.010741, 0.095, -0.000741), vec3(0.024815, 0.23, -0.001481), 0.037333, 0.034167), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m100);
  }
  {
    vec3 q101 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m102 = M(sdRoundCone(q101, vec3(0.024815, 0.23, -0.001481), vec3(0.03, 0.36, 0.0), 0.034167, 0.031), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m102);
  }
  {
    vec3 q103 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m104 = M(sdRoundCone(q103, vec3(0.03, 0.36, 0.0), vec3(0.015926, 0.471667, 0.006667), 0.031, 0.027833), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m104);
  }
  {
    vec3 q105 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m106 = M(sdRoundCone(q105, vec3(0.015926, 0.471667, 0.006667), vec3(-0.007037, 0.578333, 0.015556), 0.027833, 0.024667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m106);
  }
  {
    vec3 q107 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m108 = M(sdRoundCone(q107, vec3(-0.007037, 0.578333, 0.015556), vec3(-0.02, 0.675, 0.02), 0.024667, 0.0215), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m108);
  }
  {
    vec3 q109 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m110 = M(sdRoundCone(q109, vec3(-0.02, 0.675, 0.02), vec3(-0.011852, 0.765, 0.015556), 0.0215, 0.018333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m110);
  }
  {
    vec3 q111 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m112 = M(sdRoundCone(q111, vec3(-0.011852, 0.765, 0.015556), vec3(0.006296, 0.845, 0.006667), 0.018333, 0.015167), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m112);
  }
  {
    vec3 q113 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m114 = M(sdRoundCone(q113, vec3(0.006296, 0.845, 0.006667), vec3(0.02, 0.9, 0.0), 0.015167, 0.012), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m114);
  }
  {
    vec3 q115 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m116 = M(sdRoundCone(q115, vec3(0.02, 0.45, 0.0), vec3(0.070074, 0.504333, 0.015926), 0.0198, 0.0175), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m116);
  }
  {
    vec3 q117 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m118 = M(sdRoundCone(q117, vec3(0.070074, 0.504333, 0.015926), vec3(0.139926, 0.580667, 0.037407), 0.0175, 0.0152), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m118);
  }
  {
    vec3 q119 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m120 = M(sdRoundCone(q119, vec3(0.139926, 0.580667, 0.037407), vec3(0.198, 0.648, 0.05), 0.0152, 0.0129), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m120);
  }
  {
    vec3 q121 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m122 = M(sdRoundCone(q121, vec3(0.198, 0.648, 0.05), vec3(0.232519, 0.697333, 0.044815), 0.0129, 0.0106), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m122);
  }
  {
    vec3 q123 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m124 = M(sdRoundCone(q123, vec3(0.232519, 0.697333, 0.044815), vec3(0.255259, 0.737667, 0.030741), 0.0106, 0.0083), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m124);
  }
  {
    vec3 q125 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m126 = M(sdRoundCone(q125, vec3(0.255259, 0.737667, 0.030741), vec3(0.27, 0.765, 0.02), 0.0083, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m126);
  }
  {
    vec3 q127 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m128 = M(sdRoundCone(q127, vec3(0.0, 0.558, 0.0), vec3(-0.051667, 0.607, -0.01037), 0.018, 0.016), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m128);
  }
  {
    vec3 q129 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m130 = M(sdRoundCone(q129, vec3(-0.051667, 0.607, -0.01037), vec3(-0.123333, 0.676, -0.025185), 0.016, 0.014), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m130);
  }
  {
    vec3 q131 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m132 = M(sdRoundCone(q131, vec3(-0.123333, 0.676, -0.025185), vec3(-0.18, 0.738, -0.04), 0.014, 0.012), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m132);
  }
  {
    vec3 q133 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m134 = M(sdRoundCone(q133, vec3(-0.18, 0.738, -0.04), vec3(-0.206667, 0.786, -0.054815), 0.012, 0.01), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m134);
  }
  {
    vec3 q135 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m136 = M(sdRoundCone(q135, vec3(-0.206667, 0.786, -0.054815), vec3(-0.218333, 0.827, -0.06963), 0.01, 0.008), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m136);
  }
  {
    vec3 q137 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m138 = M(sdRoundCone(q137, vec3(-0.218333, 0.827, -0.06963), vec3(-0.225, 0.855, -0.08), 0.008, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m138);
  }
  {
    vec3 q139 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m140 = M(sdRoundCone(q139, vec3(0.0, 0.315, 0.0), vec3(-0.063, 0.3735, 0.04), 0.0162, 0.0111), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m140);
  }
  {
    vec3 q141 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.75, 0.05, -0.6));
    M m142 = M(sdRoundCone(q141, vec3(-0.063, 0.3735, 0.04), vec3(-0.126, 0.432, 0.08), 0.0111, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m142);
  }
  {
    vec3 q143 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m144 = M(sdRoundCone(q143, vec3(0.0, 0.0, 0.0), vec3(0.010741, 0.079167, -0.000741), 0.03375, 0.031333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m144);
  }
  {
    vec3 q145 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m146 = M(sdRoundCone(q145, vec3(0.010741, 0.079167, -0.000741), vec3(0.024815, 0.191667, -0.001481), 0.031333, 0.028917), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m146);
  }
  {
    vec3 q147 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m148 = M(sdRoundCone(q147, vec3(0.024815, 0.191667, -0.001481), vec3(0.03, 0.3, 0.0), 0.028917, 0.0265), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m148);
  }
  {
    vec3 q149 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m150 = M(sdRoundCone(q149, vec3(0.03, 0.3, 0.0), vec3(0.015926, 0.393056, 0.006667), 0.0265, 0.024083), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m150);
  }
  {
    vec3 q151 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m152 = M(sdRoundCone(q151, vec3(0.015926, 0.393056, 0.006667), vec3(-0.007037, 0.481944, 0.015556), 0.024083, 0.021667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m152);
  }
  {
    vec3 q153 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m154 = M(sdRoundCone(q153, vec3(-0.007037, 0.481944, 0.015556), vec3(-0.02, 0.5625, 0.02), 0.021667, 0.01925), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m154);
  }
  {
    vec3 q155 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m156 = M(sdRoundCone(q155, vec3(-0.02, 0.5625, 0.02), vec3(-0.011852, 0.6375, 0.015556), 0.01925, 0.016833), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m156);
  }
  {
    vec3 q157 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m158 = M(sdRoundCone(q157, vec3(-0.011852, 0.6375, 0.015556), vec3(0.006296, 0.704167, 0.006667), 0.016833, 0.014417), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m158);
  }
  {
    vec3 q159 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m160 = M(sdRoundCone(q159, vec3(0.006296, 0.704167, 0.006667), vec3(0.02, 0.75, 0.0), 0.014417, 0.012), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m160);
  }
  {
    vec3 q161 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m162 = M(sdRoundCone(q161, vec3(0.02, 0.375, 0.0), vec3(0.060741, 0.420278, 0.015926), 0.0165, 0.01475), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m162);
  }
  {
    vec3 q163 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m164 = M(sdRoundCone(q163, vec3(0.060741, 0.420278, 0.015926), vec3(0.117593, 0.483889, 0.037407), 0.01475, 0.013), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m164);
  }
  {
    vec3 q165 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m166 = M(sdRoundCone(q165, vec3(0.117593, 0.483889, 0.037407), vec3(0.165, 0.54, 0.05), 0.013, 0.01125), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m166);
  }
  {
    vec3 q167 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m168 = M(sdRoundCone(q167, vec3(0.165, 0.54, 0.05), vec3(0.193519, 0.581111, 0.044815), 0.01125, 0.0095), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m168);
  }
  {
    vec3 q169 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m170 = M(sdRoundCone(q169, vec3(0.193519, 0.581111, 0.044815), vec3(0.212593, 0.614722, 0.030741), 0.0095, 0.00775), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m170);
  }
  {
    vec3 q171 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m172 = M(sdRoundCone(q171, vec3(0.212593, 0.614722, 0.030741), vec3(0.225, 0.6375, 0.02), 0.00775, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m172);
  }
  {
    vec3 q173 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m174 = M(sdRoundCone(q173, vec3(0.0, 0.465, 0.0), vec3(-0.043056, 0.505833, -0.01037), 0.015, 0.0135), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m174);
  }
  {
    vec3 q175 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m176 = M(sdRoundCone(q175, vec3(-0.043056, 0.505833, -0.01037), vec3(-0.102778, 0.563333, -0.025185), 0.0135, 0.012), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m176);
  }
  {
    vec3 q177 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m178 = M(sdRoundCone(q177, vec3(-0.102778, 0.563333, -0.025185), vec3(-0.15, 0.615, -0.04), 0.012, 0.0105), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m178);
  }
  {
    vec3 q179 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m180 = M(sdRoundCone(q179, vec3(-0.15, 0.615, -0.04), vec3(-0.172222, 0.655, -0.054815), 0.0105, 0.009), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m180);
  }
  {
    vec3 q181 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m182 = M(sdRoundCone(q181, vec3(-0.172222, 0.655, -0.054815), vec3(-0.181944, 0.689167, -0.06963), 0.009, 0.0075), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m182);
  }
  {
    vec3 q183 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m184 = M(sdRoundCone(q183, vec3(-0.181944, 0.689167, -0.06963), vec3(-0.1875, 0.7125, -0.08), 0.0075, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m184);
  }
  {
    vec3 q185 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m186 = M(sdRoundCone(q185, vec3(0.0, 0.2625, 0.0), vec3(-0.0525, 0.31125, 0.04), 0.0135, 0.00975), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m186);
  }
  {
    vec3 q187 = mat3(0.34202, 0.0, 0.939693, 0.0, 1.0, 0.0, -0.939693, 0.0, 0.34202) * (p - vec3(-0.037663, 0.05, -0.132381));
    M m188 = M(sdRoundCone(q187, vec3(-0.0525, 0.31125, 0.04), vec3(-0.105, 0.36, 0.08), 0.00975, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m188);
  }
  {
    vec3 q189 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m190 = M(sdRoundCone(q189, vec3(0.0, 0.0, 0.0), vec3(0.010741, 0.084444, -0.000741), 0.036, 0.033333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m190);
  }
  {
    vec3 q191 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m192 = M(sdRoundCone(q191, vec3(0.010741, 0.084444, -0.000741), vec3(0.024815, 0.204444, -0.001481), 0.033333, 0.030667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m192);
  }
  {
    vec3 q193 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m194 = M(sdRoundCone(q193, vec3(0.024815, 0.204444, -0.001481), vec3(0.03, 0.32, 0.0), 0.030667, 0.028), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m194);
  }
  {
    vec3 q195 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m196 = M(sdRoundCone(q195, vec3(0.03, 0.32, 0.0), vec3(0.015926, 0.419259, 0.006667), 0.028, 0.025333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m196);
  }
  {
    vec3 q197 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m198 = M(sdRoundCone(q197, vec3(0.015926, 0.419259, 0.006667), vec3(-0.007037, 0.514074, 0.015556), 0.025333, 0.022667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m198);
  }
  {
    vec3 q199 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m200 = M(sdRoundCone(q199, vec3(-0.007037, 0.514074, 0.015556), vec3(-0.02, 0.6, 0.02), 0.022667, 0.02), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m200);
  }
  {
    vec3 q201 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m202 = M(sdRoundCone(q201, vec3(-0.02, 0.6, 0.02), vec3(-0.011852, 0.68, 0.015556), 0.02, 0.017333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m202);
  }
  {
    vec3 q203 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m204 = M(sdRoundCone(q203, vec3(-0.011852, 0.68, 0.015556), vec3(0.006296, 0.751111, 0.006667), 0.017333, 0.014667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m204);
  }
  {
    vec3 q205 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m206 = M(sdRoundCone(q205, vec3(0.006296, 0.751111, 0.006667), vec3(0.02, 0.8, 0.0), 0.014667, 0.012), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m206);
  }
  {
    vec3 q207 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m208 = M(sdRoundCone(q207, vec3(0.02, 0.4, 0.0), vec3(0.063852, 0.448296, 0.015926), 0.0176, 0.015667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m208);
  }
  {
    vec3 q209 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m210 = M(sdRoundCone(q209, vec3(0.063852, 0.448296, 0.015926), vec3(0.125037, 0.516148, 0.037407), 0.015667, 0.013733), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m210);
  }
  {
    vec3 q211 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m212 = M(sdRoundCone(q211, vec3(0.125037, 0.516148, 0.037407), vec3(0.176, 0.576, 0.05), 0.013733, 0.0118), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m212);
  }
  {
    vec3 q213 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m214 = M(sdRoundCone(q213, vec3(0.176, 0.576, 0.05), vec3(0.206519, 0.619852, 0.044815), 0.0118, 0.009867), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m214);
  }
  {
    vec3 q215 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m216 = M(sdRoundCone(q215, vec3(0.206519, 0.619852, 0.044815), vec3(0.226815, 0.655704, 0.030741), 0.009867, 0.007933), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m216);
  }
  {
    vec3 q217 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m218 = M(sdRoundCone(q217, vec3(0.226815, 0.655704, 0.030741), vec3(0.24, 0.68, 0.02), 0.007933, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m218);
  }
  {
    vec3 q219 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m220 = M(sdRoundCone(q219, vec3(0.0, 0.496, 0.0), vec3(-0.045926, 0.539556, -0.01037), 0.016, 0.014333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m220);
  }
  {
    vec3 q221 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m222 = M(sdRoundCone(q221, vec3(-0.045926, 0.539556, -0.01037), vec3(-0.10963, 0.600889, -0.025185), 0.014333, 0.012667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m222);
  }
  {
    vec3 q223 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m224 = M(sdRoundCone(q223, vec3(-0.10963, 0.600889, -0.025185), vec3(-0.16, 0.656, -0.04), 0.012667, 0.011), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m224);
  }
  {
    vec3 q225 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m226 = M(sdRoundCone(q225, vec3(-0.16, 0.656, -0.04), vec3(-0.183704, 0.698667, -0.054815), 0.011, 0.009333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m226);
  }
  {
    vec3 q227 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m228 = M(sdRoundCone(q227, vec3(-0.183704, 0.698667, -0.054815), vec3(-0.194074, 0.735111, -0.06963), 0.009333, 0.007667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m228);
  }
  {
    vec3 q229 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m230 = M(sdRoundCone(q229, vec3(-0.194074, 0.735111, -0.06963), vec3(-0.2, 0.76, -0.08), 0.007667, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m230);
  }
  {
    vec3 q231 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m232 = M(sdRoundCone(q231, vec3(0.0, 0.28, 0.0), vec3(-0.056, 0.332, 0.04), 0.0144, 0.0102), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m232);
  }
  {
    vec3 q233 = mat3(-0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, -0.766044) * (p - vec3(2.035321, 0.05, -0.387144));
    M m234 = M(sdRoundCone(q233, vec3(-0.056, 0.332, 0.04), vec3(-0.112, 0.384, 0.08), 0.0102, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m234);
  }
  {
    vec3 q235 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m236 = M(sdRoundCone(q235, vec3(0.0, 0.0, 0.0), vec3(0.010741, 0.063333, -0.000741), 0.027, 0.025333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m236);
  }
  {
    vec3 q237 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m238 = M(sdRoundCone(q237, vec3(0.010741, 0.063333, -0.000741), vec3(0.024815, 0.153333, -0.001481), 0.025333, 0.023667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m238);
  }
  {
    vec3 q239 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m240 = M(sdRoundCone(q239, vec3(0.024815, 0.153333, -0.001481), vec3(0.03, 0.24, 0.0), 0.023667, 0.022), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m240);
  }
  {
    vec3 q241 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m242 = M(sdRoundCone(q241, vec3(0.03, 0.24, 0.0), vec3(0.015926, 0.314444, 0.006667), 0.022, 0.020333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m242);
  }
  {
    vec3 q243 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m244 = M(sdRoundCone(q243, vec3(0.015926, 0.314444, 0.006667), vec3(-0.007037, 0.385556, 0.015556), 0.020333, 0.018667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m244);
  }
  {
    vec3 q245 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m246 = M(sdRoundCone(q245, vec3(-0.007037, 0.385556, 0.015556), vec3(-0.02, 0.45, 0.02), 0.018667, 0.017), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m246);
  }
  {
    vec3 q247 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m248 = M(sdRoundCone(q247, vec3(-0.02, 0.45, 0.02), vec3(-0.011852, 0.51, 0.015556), 0.017, 0.015333), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m248);
  }
  {
    vec3 q249 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m250 = M(sdRoundCone(q249, vec3(-0.011852, 0.51, 0.015556), vec3(0.006296, 0.563333, 0.006667), 0.015333, 0.013667), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m250);
  }
  {
    vec3 q251 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m252 = M(sdRoundCone(q251, vec3(0.006296, 0.563333, 0.006667), vec3(0.02, 0.6, 0.0), 0.013667, 0.012), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m252);
  }
  {
    vec3 q253 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m254 = M(sdRoundCone(q253, vec3(0.02, 0.3, 0.0), vec3(0.051407, 0.336222, 0.015926), 0.0132, 0.012), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m254);
  }
  {
    vec3 q255 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m256 = M(sdRoundCone(q255, vec3(0.051407, 0.336222, 0.015926), vec3(0.095259, 0.387111, 0.037407), 0.012, 0.0108), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m256);
  }
  {
    vec3 q257 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m258 = M(sdRoundCone(q257, vec3(0.095259, 0.387111, 0.037407), vec3(0.132, 0.432, 0.05), 0.0108, 0.0096), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m258);
  }
  {
    vec3 q259 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m260 = M(sdRoundCone(q259, vec3(0.132, 0.432, 0.05), vec3(0.154519, 0.464889, 0.044815), 0.0096, 0.0084), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m260);
  }
  {
    vec3 q261 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m262 = M(sdRoundCone(q261, vec3(0.154519, 0.464889, 0.044815), vec3(0.169926, 0.491778, 0.030741), 0.0084, 0.0072), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m262);
  }
  {
    vec3 q263 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m264 = M(sdRoundCone(q263, vec3(0.169926, 0.491778, 0.030741), vec3(0.18, 0.51, 0.02), 0.0072, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m264);
  }
  {
    vec3 q265 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m266 = M(sdRoundCone(q265, vec3(0.0, 0.372, 0.0), vec3(-0.034444, 0.404667, -0.01037), 0.012, 0.011), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m266);
  }
  {
    vec3 q267 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m268 = M(sdRoundCone(q267, vec3(-0.034444, 0.404667, -0.01037), vec3(-0.082222, 0.450667, -0.025185), 0.011, 0.01), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m268);
  }
  {
    vec3 q269 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m270 = M(sdRoundCone(q269, vec3(-0.082222, 0.450667, -0.025185), vec3(-0.12, 0.492, -0.04), 0.01, 0.009), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m270);
  }
  {
    vec3 q271 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m272 = M(sdRoundCone(q271, vec3(-0.12, 0.492, -0.04), vec3(-0.137778, 0.524, -0.054815), 0.009, 0.008), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m272);
  }
  {
    vec3 q273 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m274 = M(sdRoundCone(q273, vec3(-0.137778, 0.524, -0.054815), vec3(-0.145556, 0.551333, -0.06963), 0.008, 0.007), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m274);
  }
  {
    vec3 q275 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m276 = M(sdRoundCone(q275, vec3(-0.145556, 0.551333, -0.06963), vec3(-0.15, 0.57, -0.08), 0.007, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m276);
  }
  {
    vec3 q277 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m278 = M(sdRoundCone(q277, vec3(0.0, 0.21, 0.0), vec3(-0.042, 0.249, 0.04), 0.0108, 0.0084), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m278);
  }
  {
    vec3 q279 = mat3(0.866025, 0.0, 0.5, 0.0, 1.0, 0.0, -0.5, 0.0, 0.866025) * (p - vec3(-0.99799, 0.05, 1.3075));
    M m280 = M(sdRoundCone(q279, vec3(-0.042, 0.249, 0.04), vec3(-0.084, 0.288, 0.08), 0.0084, 0.006), vec3(0.068478, 0.057805, 0.051269), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m280);
  }
  if (sdBox(p - vec3(-1.55, 0.146, 0.25), vec3(0.149943, 0.106, 0.149943)) < u0.d) {
    vec3 q281 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.55, 0.146, 0.25));
    float sec282 = 0.785398, rr284 = length(q281.xz);
    float an283 = mod(atan(q281.z, q281.x) + 0.5 * sec282, sec282) - 0.5 * sec282;
    vec3 q285 = vec3(rr284 * cos(an283), q281.y, rr284 * sin(an283));
    vec3 q286 = q285 - vec3(0.066, 0.0, 0.0);
    M m287 = M(sdEllipsoid(q286, vec3(0.054, 0.096, 0.072)), vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m288 = M(length(q281) - 0.084, vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m289 = mUs(m287, m288, 0.036);
    u0 = mU(u0, m289);
  }
  {
    vec3 q290 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.55, 0.146, 0.25));
    M m291 = M(sdRoundCone(q290, vec3(0.0, 0.084, 0.0), vec3(0.012, 0.126, 0.006), 0.0144, 0.0084), vec3(0.102242, 0.144128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m291);
  }
  if (sdBox(p - vec3(-1.35, 0.114, 0.4), vec3(0.103295, 0.074, 0.103295)) < u0.d) {
    vec3 q292 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.35, 0.114, 0.4));
    float sec293 = 0.785398, rr295 = length(q292.xz);
    float an294 = mod(atan(q292.z, q292.x) + 0.5 * sec293, sec293) - 0.5 * sec293;
    vec3 q296 = vec3(rr295 * cos(an294), q292.y, rr295 * sin(an294));
    vec3 q297 = q296 - vec3(0.044, 0.0, 0.0);
    M m298 = M(sdEllipsoid(q297, vec3(0.036, 0.064, 0.048)), vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m299 = M(length(q292) - 0.056, vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m300 = mUs(m298, m299, 0.024);
    u0 = mU(u0, m300);
  }
  {
    vec3 q301 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.35, 0.114, 0.4));
    M m302 = M(sdRoundCone(q301, vec3(0.0, 0.056, 0.0), vec3(0.008, 0.084, 0.004), 0.0096, 0.0056), vec3(0.102242, 0.144128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m302);
  }
  if (sdBox(p - vec3(0.2, 0.154, 1.45), vec3(0.161605, 0.114, 0.161605)) < u0.d) {
    vec3 q303 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.2, 0.154, 1.45));
    float sec304 = 0.785398, rr306 = length(q303.xz);
    float an305 = mod(atan(q303.z, q303.x) + 0.5 * sec304, sec304) - 0.5 * sec304;
    vec3 q307 = vec3(rr306 * cos(an305), q303.y, rr306 * sin(an305));
    vec3 q308 = q307 - vec3(0.0715, 0.0, 0.0);
    M m309 = M(sdEllipsoid(q308, vec3(0.0585, 0.104, 0.078)), vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m310 = M(length(q303) - 0.091, vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m311 = mUs(m309, m310, 0.039);
    u0 = mU(u0, m311);
  }
  {
    vec3 q312 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(0.2, 0.154, 1.45));
    M m313 = M(sdRoundCone(q312, vec3(0.0, 0.091, 0.0), vec3(0.013, 0.1365, 0.0065), 0.0156, 0.0091), vec3(0.102242, 0.144128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m313);
  }
  if (sdBox(p - vec3(1.35, 0.122, 0.3), vec3(0.114957, 0.082, 0.114957)) < u0.d) {
    vec3 q314 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.35, 0.122, 0.3));
    float sec315 = 0.785398, rr317 = length(q314.xz);
    float an316 = mod(atan(q314.z, q314.x) + 0.5 * sec315, sec315) - 0.5 * sec315;
    vec3 q318 = vec3(rr317 * cos(an316), q314.y, rr317 * sin(an316));
    vec3 q319 = q318 - vec3(0.0495, 0.0, 0.0);
    M m320 = M(sdEllipsoid(q319, vec3(0.0405, 0.072, 0.054)), vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m321 = M(length(q314) - 0.063, vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m322 = mUs(m320, m321, 0.027);
    u0 = mU(u0, m322);
  }
  {
    vec3 q323 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.35, 0.122, 0.3));
    M m324 = M(sdRoundCone(q323, vec3(0.0, 0.063, 0.0), vec3(0.009, 0.0945, 0.0045), 0.0108, 0.0063), vec3(0.102242, 0.144128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m324);
  }
  if (sdBox(p - vec3(-0.9, 0.138, -0.9), vec3(0.138281, 0.098, 0.138281)) < u0.d) {
    vec3 q325 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.9, 0.138, -0.9));
    float sec326 = 0.785398, rr328 = length(q325.xz);
    float an327 = mod(atan(q325.z, q325.x) + 0.5 * sec326, sec326) - 0.5 * sec326;
    vec3 q329 = vec3(rr328 * cos(an327), q325.y, rr328 * sin(an327));
    vec3 q330 = q329 - vec3(0.0605, 0.0, 0.0);
    M m331 = M(sdEllipsoid(q330, vec3(0.0495, 0.088, 0.066)), vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m332 = M(length(q325) - 0.077, vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m333 = mUs(m331, m332, 0.033);
    u0 = mU(u0, m333);
  }
  {
    vec3 q334 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-0.9, 0.138, -0.9));
    M m335 = M(sdRoundCone(q334, vec3(0.0, 0.077, 0.0), vec3(0.011, 0.1155, 0.0055), 0.0132, 0.0077), vec3(0.102242, 0.144128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m335);
  }
  if (sdBox(p - vec3(1.25, 0.106, 1.3), vec3(0.091633, 0.066, 0.091633)) < u0.d) {
    vec3 q336 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.25, 0.106, 1.3));
    float sec337 = 0.785398, rr339 = length(q336.xz);
    float an338 = mod(atan(q336.z, q336.x) + 0.5 * sec337, sec337) - 0.5 * sec337;
    vec3 q340 = vec3(rr339 * cos(an338), q336.y, rr339 * sin(an338));
    vec3 q341 = q340 - vec3(0.0385, 0.0, 0.0);
    M m342 = M(sdEllipsoid(q341, vec3(0.0315, 0.056, 0.042)), vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m343 = M(length(q336) - 0.049, vec3(0.806952, 0.162029, 0.012983), vec3(0.5, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m344 = mUs(m342, m343, 0.021);
    u0 = mU(u0, m344);
  }
  {
    vec3 q345 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.25, 0.106, 1.3));
    M m346 = M(sdRoundCone(q345, vec3(0.0, 0.049, 0.0), vec3(0.007, 0.0735, 0.0035), 0.0084, 0.0049), vec3(0.102242, 0.144128, 0.023153), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m346);
  }
  if (sdBox(p - vec3(-0.7, 0.12, 0.9), vec3(0.09972, 0.08, 0.09972)) < u0.d) {
    vec3 q347 = mat3(0.939693, 0.0, 0.34202, 0.0, 1.0, 0.0, -0.34202, 0.0, 0.939693) * (p - vec3(-0.7, 0.12, 0.9));
    M m348 = M(length(q347) - 0.07, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q349 = q347 - vec3(0.0, -0.042, 0.0175);
    M m350 = M(sdBox(q349, vec3(0.021, 0.0035, 0.014)) - 0.0175, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m351 = mMerge(m348, m350, 0.0175, 0, 0, vec3(0.0, 0.0, 0.0), 0.0);
    if (m351.d < 0.074) {
      vec3 q353 = q347;
      q353.x = abs(q353.x);
      vec3 q354 = q353 - vec3(0.0266, -0.0105, 0.0595);
      M m355 = M(length(q354) - 0.0196, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w352 = 1.0 - smoothstep(-0.006, 0.00601, m355.d);
      m351.d -= -0.004 * w352;
      m351.c = mix(m351.c, m355.c, w352); m351.m = mix(m351.m, m355.m, w352);
      if (w352 > 0.5) { m351.c2 = m355.c2; m351.tx = m355.tx; m351.tp = m355.tp; m351.fc = m355.fc; }
    }
    if (m351.d < 0.063) {
      vec3 q357 = q347 - vec3(0.0, -0.0315, 0.07);
      M m358 = M(length(q357) - 0.0084, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w356 = 1.0 - smoothstep(-0.003, 0.00301, m358.d);
      m351.c = mix(m351.c, m358.c, w356); m351.m = mix(m351.m, m358.m, w356);
      if (w356 > 0.5) { m351.c2 = m358.c2; m351.tx = m358.tx; m351.tp = m358.tp; m351.fc = m358.fc; }
    }
    u0 = mU(u0, m351);
  }
  if (sdBox(p - vec3(1.05, 0.11, -1.1), vec3(0.091962, 0.07, 0.091962)) < u0.d) {
    vec3 q359 = mat3(0.866025, 0.0, -0.5, 0.0, 1.0, 0.0, 0.5, 0.0, 0.866025) * (p - vec3(1.05, 0.11, -1.1));
    M m360 = M(length(q359) - 0.06, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q361 = q359 - vec3(0.0, -0.036, 0.015);
    M m362 = M(sdBox(q361, vec3(0.018, 0.003, 0.012)) - 0.015, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m363 = mMerge(m360, m362, 0.015, 0, 0, vec3(0.0, 0.0, 0.0), 0.0);
    if (m363.d < 0.074) {
      vec3 q365 = q359;
      q365.x = abs(q365.x);
      vec3 q366 = q365 - vec3(0.0228, -0.009, 0.051);
      M m367 = M(length(q366) - 0.0168, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w364 = 1.0 - smoothstep(-0.006, 0.00601, m367.d);
      m363.d -= -0.004 * w364;
      m363.c = mix(m363.c, m367.c, w364); m363.m = mix(m363.m, m367.m, w364);
      if (w364 > 0.5) { m363.c2 = m367.c2; m363.tx = m367.tx; m363.tp = m367.tp; m363.fc = m367.fc; }
    }
    if (m363.d < 0.063) {
      vec3 q369 = q359 - vec3(0.0, -0.027, 0.06);
      M m370 = M(length(q369) - 0.0072, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w368 = 1.0 - smoothstep(-0.003, 0.00301, m370.d);
      m363.c = mix(m363.c, m370.c, w368); m363.m = mix(m363.m, m370.m, w368);
      if (w368 > 0.5) { m363.c2 = m370.c2; m363.tx = m370.tx; m363.tp = m370.tp; m363.fc = m370.fc; }
    }
    u0 = mU(u0, m363);
  }
  if (sdBox(p - vec3(-1.6, 0.65, -1.55), vec3(0.06, 0.06, 0.06)) < u0.d) {
    vec3 q371 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.6, 0.65, -1.55));
    M m372 = M(length(q371) - 0.05, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q373 = q371 - vec3(0.0, -0.03, 0.0125);
    M m374 = M(sdBox(q373, vec3(0.015, 0.0025, 0.01)) - 0.0125, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m375 = mMerge(m372, m374, 0.0125, 0, 0, vec3(0.0, 0.0, 0.0), 0.0);
    if (m375.d < 0.074) {
      vec3 q377 = q371;
      q377.x = abs(q377.x);
      vec3 q378 = q377 - vec3(0.019, -0.0075, 0.0425);
      M m379 = M(length(q378) - 0.014, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w376 = 1.0 - smoothstep(-0.006, 0.00601, m379.d);
      m375.d -= -0.004 * w376;
      m375.c = mix(m375.c, m379.c, w376); m375.m = mix(m375.m, m379.m, w376);
      if (w376 > 0.5) { m375.c2 = m379.c2; m375.tx = m379.tx; m375.tp = m379.tp; m375.fc = m379.fc; }
    }
    if (m375.d < 0.063) {
      vec3 q381 = q371 - vec3(0.0, -0.0225, 0.05);
      M m382 = M(length(q381) - 0.006, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w380 = 1.0 - smoothstep(-0.003, 0.00301, m382.d);
      m375.c = mix(m375.c, m382.c, w380); m375.m = mix(m375.m, m382.m, w380);
      if (w380 > 0.5) { m375.c2 = m382.c2; m375.tx = m382.tx; m375.tp = m382.tp; m375.fc = m382.fc; }
    }
    u0 = mU(u0, m375);
  }
  if (sdBox(p - vec3(0.55, 0.105, 0.4), vec3(0.087486, 0.065, 0.087486)) < u0.d) {
    vec3 q383 = mat3(0.766044, 0.0, 0.642788, 0.0, 1.0, 0.0, -0.642788, 0.0, 0.766044) * (p - vec3(0.55, 0.105, 0.4));
    M m384 = M(length(q383) - 0.055, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    vec3 q385 = q383 - vec3(0.0, -0.033, 0.01375);
    M m386 = M(sdBox(q385, vec3(0.0165, 0.00275, 0.011)) - 0.01375, vec3(0.838799, 0.791298, 0.672443), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    M m387 = mMerge(m384, m386, 0.01375, 0, 0, vec3(0.0, 0.0, 0.0), 0.0);
    if (m387.d < 0.074) {
      vec3 q389 = q383;
      q389.x = abs(q389.x);
      vec3 q390 = q389 - vec3(0.0209, -0.00825, 0.04675);
      M m391 = M(length(q390) - 0.0154, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w388 = 1.0 - smoothstep(-0.006, 0.00601, m391.d);
      m387.d -= -0.004 * w388;
      m387.c = mix(m387.c, m391.c, w388); m387.m = mix(m387.m, m391.m, w388);
      if (w388 > 0.5) { m387.c2 = m391.c2; m387.tx = m391.tx; m387.tp = m391.tp; m387.fc = m391.fc; }
    }
    if (m387.d < 0.063) {
      vec3 q393 = q383 - vec3(0.0, -0.02475, 0.055);
      M m394 = M(length(q393) - 0.0066, vec3(0.01033, 0.008023, 0.006995), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
      float w392 = 1.0 - smoothstep(-0.003, 0.00301, m394.d);
      m387.c = mix(m387.c, m394.c, w392); m387.m = mix(m387.m, m394.m, w392);
      if (w392 > 0.5) { m387.c2 = m394.c2; m387.tx = m394.tx; m387.tp = m394.tp; m387.fc = m394.fc; }
    }
    u0 = mU(u0, m387);
  }
  {
    vec3 q395 = mat3(0.984808, 0.0, -0.173648, 0.0, 1.0, 0.0, 0.173648, 0.0, 0.984808) * (p - vec3(-1.3, 0.162, -0.2));
    M m396 = M(sdCBox(q395, vec3(0.11, 0.112, 0.03), 0.01), vec3(0.391572, 0.401978, 0.381326), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m396);
  }
  {
    vec3 q397 = mat3(0.990268, 0.0, 0.139173, 0.0, 1.0, 0.0, -0.139173, 0.0, 0.990268) * (p - vec3(-1.0, 0.141, 0.1));
    M m398 = M(sdCBox(q397, vec3(0.09, 0.091, 0.03), 0.01), vec3(0.391572, 0.401978, 0.381326), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m398);
  }
  {
    vec3 q399 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.65, 0.25, 0.7));
    M m400 = M(sdCBox(q399, vec3(0.025, 0.2, 0.025), 0.008), vec3(0.341914, 0.351533, 0.332452), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m400);
  }
  {
    vec3 q401 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(-1.65, 0.33, 0.7));
    M m402 = M(sdCBox(q401, vec3(0.11, 0.025, 0.025), 0.008), vec3(0.341914, 0.351533, 0.332452), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m402);
  }
  {
    vec3 q403 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0) * (p - vec3(1.55, 0.155, -0.15));
    M m404 = M(sdCBox(q403, vec3(0.1, 0.105, 0.03), 0.01), vec3(0.391572, 0.401978, 0.381326), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m404);
  }
  {
    vec3 q405 = mat3(0.965926, 0.0, 0.258819, 0.0, 1.0, 0.0, -0.258819, 0.0, 0.965926) * (p - vec3(1.2, 0.225, 0.75));
    M m406 = M(sdCBox(q405, vec3(0.025, 0.175, 0.025), 0.008), vec3(0.341914, 0.351533, 0.332452), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m406);
  }
  {
    vec3 q407 = mat3(0.965926, 0.0, 0.258819, 0.0, 1.0, 0.0, -0.258819, 0.0, 0.965926) * (p - vec3(1.2, 0.295, 0.75));
    M m408 = M(sdCBox(q407, vec3(0.11, 0.025, 0.025), 0.008), vec3(0.341914, 0.351533, 0.332452), vec3(0.6, 0.0, 0.0), vec3(0.0, 0.0, 0.0), vec4(0.0, 1.0, 1.0, 0.0), vec3(0.0), 0.0);
    u0 = mU(u0, m408);
  }
  int mk409 = 0;
  if (sdBox(p - vec3(-2.05, 0.32, 0.0), vec3(0.08, 0.33, 1.46)) < u0.d) mk409 |= 1;
  if (sdBox(p - vec3(2.05, 0.32, 0.0), vec3(0.08, 0.33, 1.46)) < u0.d) mk409 |= 2;
  for (int b = uZero, bits = mk409; bits != 0; b++, bits = int(uint(bits) >> 1u)) {
    if ((bits & 1) == 0) continue;
    int i = 0 + b;
    vec4 bc = codeFetch(3, i);
    if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= u0.d) continue;
    vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);
    M ri = ci0(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));
    ri.d *= bc.w;
    u0 = mU(u0, ri);
  }
  int mk410 = 0;
  if (sdBox(p - vec3(-2.05, 0.345, -1.55), vec3(0.14, 0.355, 0.14)) < u0.d) mk410 |= 1;
  if (sdBox(p - vec3(2.05, 0.345, -1.55), vec3(0.14, 0.355, 0.14)) < u0.d) mk410 |= 2;
  if (sdBox(p - vec3(-2.05, 0.345, 1.55), vec3(0.14, 0.355, 0.14)) < u0.d) mk410 |= 4;
  if (sdBox(p - vec3(2.05, 0.345, 1.55), vec3(0.14, 0.355, 0.14)) < u0.d) mk410 |= 8;
  for (int b = uZero, bits = mk410; bits != 0; b++, bits = int(uint(bits) >> 1u)) {
    if ((bits & 1) == 0) continue;
    int i = 2 + b;
    vec4 bc = codeFetch(3, i);
    if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= u0.d) continue;
    vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);
    M ri = ci1(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));
    ri.d *= bc.w;
    u0 = mU(u0, ri);
  }
  int mk411 = 0;
  if (sdBox(p - vec3(0.3, 0.146, 0.75), vec3(0.126619, 0.106, 0.126619)) < u0.d) mk411 |= 1;
  if (sdBox(p - vec3(-0.1, 0.146, -1.0), vec3(0.126619, 0.106, 0.126619)) < u0.d) mk411 |= 2;
  for (int b = uZero, bits = mk411; bits != 0; b++, bits = int(uint(bits) >> 1u)) {
    if ((bits & 1) == 0) continue;
    int i = 6 + b;
    vec4 bc = codeFetch(3, i);
    if (sdBox(p - bc.xyz, codeFetch(4, i).xyz) >= u0.d) continue;
    vec4 r0 = codeFetch(0, i), r1 = codeFetch(1, i), r2 = codeFetch(2, i);
    M ri = ci2(vec3(dot(r0.xyz, p) + r0.w, dot(r1.xyz, p) + r1.w, dot(r2.xyz, p) + r2.w));
    ri.d *= bc.w;
    u0 = mU(u0, ri);
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
