// Renderizador WebGL2: um triângulo de tela cheia + raymarching do SDF gerado.

const VERT = `#version 300 es
in vec2 pos;
void main() { gl_Position = vec4(pos, 0.0, 1.0); }`;

// Toda a cena é avaliada em UM único ponto do shader: o compilador da GPU copia (inline) a
// função da cena em cada chamada, então chamar em vários lugares multiplica o tempo de compilação.
// Por isso o main é uma máquina de estados: raio primário -> material -> normal -> sombra -> AO,
// todos usando mapAll (distância + material, com o material só calculado quando pedido).
export const fragSource = (sceneGlsl) => `#version 300 es
precision highp float;
uniform vec2 uRes;
uniform vec3 uRo, uTa;
uniform float uFov, uFog, uMaxDist, uTime;
uniform vec3 uSun, uSunCol, uSky;
uniform int uZero;
out vec4 outColor;
${sceneGlsl}

vec3 skyCol(vec3 rd) {
  vec3 horizon = mix(uSky, vec3(1.0), 0.55);
  vec3 col = mix(horizon, uSky, clamp(rd.y * 1.6, 0.0, 1.0));
  col = mix(col, horizon * 0.75, clamp(-rd.y * 3.0, 0.0, 1.0));
  float s = clamp(dot(rd, normalize(uSun)), 0.0, 1.0);
  return col + uSunCol * (pow(s, 600.0) * 4.0 + pow(s, 12.0) * 0.08);
}

vec3 shade(M m, vec3 rd, vec3 n, float dif, float occ) {
  if (m.tx.x > 0.5) m.c = texColor(m.tp, m.c, m.c2, m.tx);
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
  return col;
}

// direções do tetraedro usado para a normal
vec3 tetra(int k) { return 0.5773 * (2.0 * vec3((((k + 3) >> 1) & 1), ((k >> 1) & 1), (k & 1)) - 1.0); }

const int S_RAY = 0, S_MAT = 1, S_NOR = 2, S_SHADOW = 3, S_AO = 4;

void main() {
  vec2 uv = (2.0 * gl_FragCoord.xy - uRes) / min(uRes.x, uRes.y);
  vec3 ww = normalize(uTa - uRo);
  vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
  if (length(cross(ww, vec3(0.0, 1.0, 0.0))) < 1e-4) uu = vec3(1.0, 0.0, 0.0);
  vec3 vv = cross(uu, ww);
  float fl = 1.0 / tan(radians(uFov) * 0.5);
  vec3 rd = normalize(uv.x * uu + uv.y * vv + fl * ww);
  vec3 L = normalize(uSun);

  int state = S_RAY, k = 0, steps = 0;
  float t = 0.001, hitT = -1.0;
  vec3 pos = vec3(0.0), nor = vec3(0.0);
  float sh = 1.0, st = 0.003, occ = 0.0, sca = 1.0;
  M mat = M(0.0, vec3(0.5), vec3(1.0, 0.0, 0.0), vec3(0.0), vec4(0.0), vec3(0.0));
  // uZero = 0 (uniform) impede o compilador de desenrolar o laço e duplicar a cena
  for (int it = uZero; it < 420; it++) {
    vec3 q;
    if (state == S_RAY) q = uRo + rd * t;
    else if (state == S_MAT) q = pos;
    else if (state == S_NOR) q = pos + 0.0004 * tetra(k);
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
      state = S_NOR;
    } else if (state == S_NOR) {
      nor += tetra(k) * d;
      if (++k == 4) {
        nor = normalize(nor);
        k = 0;
        if (dot(nor, L) > 0.001) { state = S_SHADOW; steps = 0; }
        else { sh = 0.0; state = S_AO; }
      }
    } else if (state == S_SHADOW) {
      sh = min(sh, 12.0 * d / st);
      st += clamp(d, 0.004, 0.25);
      if (sh < 0.002 || st > uMaxDist * 0.5 || ++steps >= 80) { state = S_AO; k = 0; }
    } else {
      occ += (0.01 + 0.04 * float(k) - d) * sca;
      sca *= 0.8;
      if (++k == 5) break;
    }
  }

  vec3 col = skyCol(rd);
  if (hitT > 0.0) {
    float dif = clamp(dot(nor, L), 0.0, 1.0) * clamp(sh, 0.0, 1.0);
    vec3 c = shade(mat, rd, nor, dif, clamp(1.0 - 3.0 * occ, 0.0, 1.0));
    col = mix(col, c, exp(-uFog * hitT));
  }
  col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
  col = pow(clamp(col, 0.0, 1.0), vec3(1.0 / 2.2));
  vec2 sq = gl_FragCoord.xy / uRes;
  col *= 0.6 + 0.4 * pow(16.0 * sq.x * sq.y * (1.0 - sq.x) * (1.0 - sq.y), 0.1);
  outColor = vec4(col, 1.0);
}`;

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    const gl = canvas.getContext('webgl2', { antialias: false, preserveDrawingBuffer: true });
    if (!gl) throw new Error('WebGL2 não disponível neste navegador');
    this.gl = gl;
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    this.vs = this.shader(gl.VERTEX_SHADER, VERT);
    this.parallel = gl.getExtension('KHR_parallel_shader_compile');
    this.gen = 0;
    this.program = null;
    this.glsl = null;
  }

  shader(type, src) {
    const gl = this.gl;
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(s);
      gl.deleteShader(s);
      throw new Error(`erro ao compilar shader:\n${log}`);
    }
    return s;
  }

  // Recompila só quando o GLSL da cena muda; os dados (BVH) são enviados sempre.
  // Com KHR_parallel_shader_compile a compilação roda em segundo plano: a cena anterior
  // continua na tela e o editor não trava. Uma chamada mais nova cancela a pendente.
  // Resolve com o tempo em ms, ou null se foi substituída por outra.
  setScene(glsl, data = null) {
    const gen = ++this.gen;
    if (glsl === this.glsl) { this.uploadData(data); return Promise.resolve(0); }
    const t0 = performance.now();
    const gl = this.gl;
    const fs = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(fs, fragSource(glsl));
    gl.compileShader(fs);
    const prog = gl.createProgram();
    gl.attachShader(prog, this.vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    const discard = () => { gl.deleteProgram(prog); gl.deleteShader(fs); return null; };
    const finish = () => {
      if (gen !== this.gen) return discard();
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
        const log = gl.getShaderInfoLog(fs) || gl.getProgramInfoLog(prog);
        discard();
        throw new Error(`erro ao compilar shader:\n${log}`);
      }
      gl.deleteShader(fs);
      this.use(prog, glsl);
      this.uploadData(data);
      return performance.now() - t0;
    };
    if (!this.parallel) return Promise.resolve().then(finish);
    return new Promise((resolve, reject) => {
      const poll = () => {
        if (gen !== this.gen) { resolve(discard()); return; }
        if (!gl.getProgramParameter(prog, this.parallel.COMPLETION_STATUS_KHR)) { setTimeout(poll, 8); return; }
        try { resolve(finish()); } catch (e) { reject(e); }
      };
      poll();
    });
  }

  use(prog, glsl) {
    const gl = this.gl;
    if (this.program) gl.deleteProgram(this.program);
    this.program = prog;
    this.glsl = glsl;
    this.loc = {};
    for (const u of ['uRes', 'uRo', 'uTa', 'uFov', 'uFog', 'uMaxDist', 'uSun', 'uSunCol', 'uSky', 'uTime', 'uZero']) {
      this.loc[u] = gl.getUniformLocation(prog, u);
    }
    gl.useProgram(prog);
    const posLoc = gl.getAttribLocation(prog, 'pos');
    gl.enableVertexAttribArray(posLoc);
    gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);
  }

  uploadData(data) {
    if (!data) return;
    const gl = this.gl;
    const max = gl.getParameter(gl.MAX_TEXTURE_SIZE);
    if (data.instCount > max || data.nodeCount > max) throw new Error(`cena excede o limite de textura da GPU (${max})`);
    this.tex ??= [gl.createTexture(), gl.createTexture()];
    const put = (unit, tex, w, h, arr, name) => {
      gl.activeTexture(gl.TEXTURE0 + unit);
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, w, h, 0, gl.RGBA, gl.FLOAT, arr);
      gl.uniform1i(gl.getUniformLocation(this.program, name), unit);
    };
    gl.useProgram(this.program);
    put(0, this.tex[0], data.instW, data.instCount, data.inst, 'uInst');
    put(1, this.tex[1], data.bvhW, data.nodeCount, data.bvh, 'uBvh');
  }

  render(view, scale = 1) {
    if (!this.program) return;
    const gl = this.gl;
    const dpr = Math.min(window.devicePixelRatio || 1, 1.5) * scale;
    const w = Math.max(1, Math.round(this.canvas.clientWidth * dpr));
    const h = Math.max(1, Math.round(this.canvas.clientHeight * dpr));
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    gl.viewport(0, 0, w, h);
    gl.useProgram(this.program);
    const L = this.loc;
    gl.uniform2f(L.uRes, w, h);
    gl.uniform3fv(L.uRo, view.eye);
    gl.uniform3fv(L.uTa, view.target);
    gl.uniform1f(L.uFov, view.fov);
    gl.uniform1f(L.uFog, view.fog);
    gl.uniform1f(L.uMaxDist, view.maxDist);
    gl.uniform3fv(L.uSun, view.sun);
    gl.uniform3fv(L.uSunCol, view.sunColor);
    gl.uniform3fv(L.uSky, view.sky);
    gl.uniform1f(L.uTime, view.time ?? 0);
    gl.uniform1i(L.uZero, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
}
