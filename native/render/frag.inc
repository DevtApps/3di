// Gerado de src/renderer.js (fragSource); conferido por tests/golden/_frag.glsl.
static const char *FRAG_HEAD = R"GLSL(#version 300 es
precision highp float;
uniform vec2 uRes;
uniform vec3 uRo, uTa;
uniform float uFov, uFog, uMaxDist, uTime;
uniform vec3 uSun, uSunCol, uSky, uRimCol;
uniform vec3 uLight; // rim, fill, ao
uniform int uZero, uShadowSteps;
out vec4 outColor;
)GLSL";
static const char *FRAG_TAIL = R"GLSL(

vec3 skyCol(vec3 rd) {
  vec3 horizon = mix(uSky, vec3(1.0), 0.55);
  vec3 col = mix(horizon, uSky, clamp(rd.y * 1.6, 0.0, 1.0));
  col = mix(col, horizon * 0.75, clamp(-rd.y * 3.0, 0.0, 1.0));
  float s = clamp(dot(rd, normalize(uSun)), 0.0, 1.0);
  return col + uSunCol * (pow(s, 600.0) * 4.0 + pow(s, 12.0) * 0.08);
}

vec3 gFill; // direção da luz de preenchimento (do lado da câmera)
vec3 shade(M m, vec3 rd, vec3 n, float dif, float occ) {
  if (m.tx.x > 0.5) m.c = texColor(m.tp, m.c, m.c2, m.tx, n);
  vec3 L = normalize(uSun);
  float rough = clamp(m.m.x, 0.03, 1.0), metal = clamp(m.m.y, 0.0, 1.0);
  vec3 H = normalize(L - rd);
  float shin = exp2(11.0 * (1.0 - rough) + 1.0);
  float spe = pow(clamp(dot(n, H), 0.0, 1.0), shin) * (shin + 8.0) / 25.0 * dif;
  float fre = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 5.0);
  vec3 F0 = mix(vec3(0.04), m.c, metal);
  vec3 F = F0 + (1.0 - F0) * fre * (1.0 - rough * 0.8);
  vec3 diff = m.c * (1.0 - metal);
  float bounce = clamp(0.3 - 0.7 * n.y, 0.0, 1.0);
  vec3 lin = uSunCol * dif * 1.6
           + skyCol(vec3(n.x, max(n.y, 0.0), n.z)) * (0.55 + 0.45 * n.y) * occ * 0.7
           + uSunCol * vec3(0.9, 0.8, 0.7) * bounce * occ * 0.15;
  vec3 col = diff * lin;
  col += uSunCol * spe * F * 0.6;
  col += skyCol(reflect(rd, n)) * F * occ * (1.0 - rough) * 0.9;
  col += m.c * m.m.z * 2.0;
  // luzes de estúdio: preenchimento sem sombra e contorno nas bordas da silhueta
  float ndv = clamp(dot(n, -rd), 0.0, 1.0);
  col += diff * uSunCol * uLight.y * 0.8 * clamp(dot(n, gFill), 0.0, 1.0) * (0.4 + 0.6 * occ);
  col += uRimCol * uLight.x * pow(1.0 - ndv, 3.0) * (0.35 + 0.65 * occ) * (0.5 + 0.5 * clamp(n.y + 0.5, 0.0, 1.0));
  // verniz: reflexo nítido por cima da cor, como plástico de brinquedo
  float coat = floor(mod(m.fc, 16384.0) / 1024.0) * 0.1;
  if (coat > 0.0) {
    float cf = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);
    col += coat * (uSunCol * pow(clamp(dot(n, H), 0.0, 1.0), 900.0) * 30.0 * dif
                 + uSunCol * pow(clamp(dot(n, normalize(gFill - rd)), 0.0, 1.0), 300.0) * 3.0 * uLight.y
                 + skyCol(reflect(rd, n)) * cf * occ * 1.5);
  }
  return col;
}

const mat3 FACET_ROT = mat3(0.8571, 0.4286, -0.2857, -0.2857, 0.8571, 0.4286, 0.4286, -0.2857, 0.8571);

// direções do tetraedro usado para a normal
vec3 tetra(int k) { return 0.5773 * (2.0 * vec3((((k + 3) >> 1) & 1), ((k >> 1) & 1), (k & 1)) - 1.0); }

// Facetas (low poly): o espaço é dividido numa grade de tetraedros (a do ruído simplex) de lado
// ~s. A distância nos 4 vértices do tetraedro que contém o ponto define uma função linear; a
// normal é o gradiente dela, constante dentro do tetraedro. É a faceta que a malha de marching
// tetrahedra teria ali: triângulos e quadriláteros planos, como um modelo low poly.
// Devolve o vértice k (0..3) do tetraedro e, em cell, um identificador para variar o tom.
vec3 facetVertex(vec3 p, float s, int k, out vec3 cell) {
  vec3 g = p / s;
  vec3 i = floor(g + dot(g, vec3(1.0 / 3.0)));
  vec3 x0 = g - (i - dot(i, vec3(1.0 / 6.0)));
  vec3 e = step(x0.yzx, x0.xyz);
  vec3 i1 = e * (1.0 - e.zxy), i2 = 1.0 - e.zxy * (1.0 - e);
  vec3 o = k == 0 ? vec3(0.0) : k == 1 ? i1 : k == 2 ? i2 : vec3(1.0);
  cell = i + 0.37 * i1 + 0.61 * i2;
  vec3 v = i + o;
  return (v - dot(v, vec3(1.0 / 6.0))) * s;
}

const int S_RAY = 0, S_MAT = 1, S_NOR = 2, S_SHADOW = 3, S_AO = 4, S_FAC = 5;

void main() {
  vec2 uv = (2.0 * gl_FragCoord.xy - uRes) / min(uRes.x, uRes.y);
  vec3 ww = normalize(uTa - uRo);
  vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
  if (length(cross(ww, vec3(0.0, 1.0, 0.0))) < 1e-4) uu = vec3(1.0, 0.0, 0.0);
  vec3 vv = cross(uu, ww);
  float fl = 1.0 / tan(radians(uFov) * 0.5);
  vec3 rd = normalize(uv.x * uu + uv.y * vv + fl * ww);
  vec3 L = normalize(uSun);
  gFill = normalize(-ww - 0.7 * uu + 0.5 * vv);

  int state = S_RAY, k = 0, steps = 0;
  float t = 0.001, hitT = -1.0;
  vec3 pos = vec3(0.0), nor = vec3(0.0);
  float sh = 1.0, st = 0.003, occ = 0.0, sca = 1.0;
  M mat = M(0.0, vec3(0.5), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0), 0.0);
  vec3 fcell = vec3(0.0), fv[4];
  float nEps = 0.0004;
  float fd[4];
  // uZero = 0 (uniform) impede o compilador de desenrolar o laço e duplicar a cena
  for (int it = uZero; it < 420; it++) {
    vec3 q;
    if (state == S_RAY) q = uRo + rd * t;
    else if (state == S_MAT) q = pos;
    else if (state == S_NOR) q = pos + nEps * tetra(k);
    else if (state == S_FAC) q = fv[k];
    else if (state == S_SHADOW) q = pos + nor * 0.002 + L * st;
    else q = pos + nor * (0.01 + 0.04 * float(k));

    M r = mapAll(q, state == S_MAT);
    float d = r.d;

    if (state == S_RAY) {
      if (abs(d) < 0.00025 * t + 0.00005) {
        hitT = t; pos = uRo + rd * t; k = 0; steps = 0;
        state = S_MAT;
      } else {
        t += d;
        if (t > uMaxDist || ++steps >= 320) break;
      }
    } else if (state == S_MAT) {
      mat = r;
      // formas com smooth= trazem no material um raio maior para a normal: a diferença central
      // mais larga mistura as faces vizinhas e o preview mostra a suavização do GLB
      if (mat.fc >= 16384.0) nEps = floor(mat.fc / 16384.0) * 0.001;
      state = S_NOR;
    } else if (state == S_NOR) {
      nor += tetra(k) * d;
      if (++k == 4) {
        nor = normalize(nor);
        k = 0;
        if (mod(mat.fc, 1024.0) > 0.0) {
          // a grade gira um pouco para as facetas não ficarem alinhadas aos eixos
          for (int j = 0; j < 4; j++) fv[j] = FACET_ROT * facetVertex(pos * FACET_ROT, mod(mat.fc, 16.0), j, fcell);
          state = S_FAC;
        }
        else if (dot(nor, L) > 0.001) { state = S_SHADOW; steps = 0; }
        else { sh = 0.0; state = S_AO; }
      }
    } else if (state == S_FAC) {
      fd[k] = d;
      if (++k == 4) {
        k = 0;
        if (dot(nor, L) > 0.001) { state = S_SHADOW; steps = 0; }
        else { sh = 0.0; state = S_AO; }
      }
    } else if (state == S_SHADOW) {
      sh = min(sh, 12.0 * d / st);
      st += clamp(d, 0.004, 0.25);
      if (sh < 0.002 || st > uMaxDist * 0.5 || ++steps >= uShadowSteps) { state = S_AO; k = 0; }
    } else {
      occ += (0.01 + 0.04 * float(k) - d) * sca;
      sca *= 0.8;
      if (++k == 5) break;
    }
  }

  vec3 col = skyCol(rd);
  // relevo (bump): as derivadas de tela exigem fluxo uniforme, por isso a altura é calculada
  // para todos os pixels (textura sem relevo devolve 0 de imediato)
  float bumpH = texHeight(mat.tp, mat.tx, nor);
  float dhx = dFdx(bumpH), dhy = dFdy(bumpH);
  vec3 dpx = dFdx(pos), dpy = dFdy(pos);
  if (hitT > 0.0) {
    if (mat.tx.w > 0.0) {
      float px = hitT * 2.0 * tan(radians(uFov) * 0.5) / min(uRes.x, uRes.y);
      nor = bumpNormal(nor, mat.tx.w * mat.tx.y, dhx, dhy, dpx, dpy, px);
    }
    if (mod(mat.fc, 1024.0) > 0.0) {
      // normal da faceta (a semente pode cair em outra parte do corpo: nesse caso fica a lisa)
      // gradiente da função linear nos 4 vértices: resolve [v1-v0; v2-v0; v3-v0] g = [d1-d0, ...]
      mat3 A = transpose(mat3(fv[1] - fv[0], fv[2] - fv[0], fv[3] - fv[0]));
      vec3 g = inverse(A) * vec3(fd[1] - fd[0], fd[2] - fd[0], fd[3] - fd[0]);
      vec3 fn = normalize(g);
      if (length(g) > 0.2 && dot(fn, nor) > 0.3) nor = fn;
      float vary = floor(mod(mat.fc, 1024.0) / 16.0) * 0.01;
      mat.c *= 1.0 + vary * (2.0 * hash31(fcell + 5.17) - 1.0);
    }
    float dif = clamp(dot(nor, L), 0.0, 1.0) * clamp(sh, 0.0, 1.0);
    vec3 c = shade(mat, rd, nor, dif, clamp(1.0 - 3.0 * occ * uLight.z, 0.0, 1.0));
    col = mix(col, c, exp(-uFog * hitT));
  }
  col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
  col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / 2.2));
  vec2 sq = gl_FragCoord.xy / uRes;
  col *= 0.6 + 0.4 * pow(16.0 * sq.x * sq.y * (1.0 - sq.x) * (1.0 - sq.y), 0.1);
  outColor = vec4(col, 1.0);
})GLSL";
