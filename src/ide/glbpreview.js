// Painel "Conferir GLB": exporta a cena pelo mesmo caminho do botão GLB e abre o resultado num motor
// padrão (three.js), no mesmo ângulo do shader, para checar se a conversão ficou boa.
//   - Dividido / GLB / Shader: a malha exportada contra a forma exata (o shader), com uma divisória.
//   - Sólido / Triângulos / Normais: como a malha é desenhada (densidade, quinas, sombreamento).
//   - Relatório por peça: triângulos e desvio da malha em relação à forma (em mm), com veredito.
import { sceneTask } from './tasks.js';

let threeLoading = null;
const loadThree = () => (threeLoading ??= import(new URL('../../assets/vendor/three-preview.js', import.meta.url).href));

const MB = (n) => `${(n / 1048576).toFixed(n > 1048576 * 9.95 ? 0 : 1)} MB`;
const mm = (v) => (v * 1000 >= 100 ? (v * 1000).toFixed(0) : (v * 1000).toFixed(v * 1000 >= 10 ? 1 : 2));
const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

/**
 * getView(): { eye, target, fov } do editor; getSun(): direção do sol; getTime(): instante da animação;
 * renderShader(view, w, h): Promise<dataURL> com o shader no mesmo ângulo; saveGlb(bytes): salva o arquivo.
 */
export function createGlbPreview({ getView, getSun = () => [0.6, 1, 0.4], getTime = () => 0, renderShader, saveGlb, getCode }) {
  const $ = (id) => document.getElementById(id);
  const root = $('glbcheck'), stage = $('gcStage'), shaderImg = $('gcShader'), divider = $('gcDivider'), side = $('gcSide');
  const busy = $('gcBusy'), busyText = $('gcBusyText');
  const st = {
    mode: 'split', style: 'solid', split: 0.5, res: 128, token: 0, shaderToken: 0, job: null, ticker: null,
    T: null, renderer: null, scene: null, camera: null, controls: null, sunLight: null, model: null,
    parts: [], reports: [], glb: null, stats: null, isolated: -1, normalMat: null, wires: new Map(), dirty: false, error: null,
  };

  // ---------- three.js ----------
  async function ensureThree() {
    if (st.renderer) return;
    const T = await loadThree();
    st.T = T;
    const renderer = new T.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    renderer.outputColorSpace = T.SRGBColorSpace;
    stage.insertBefore(renderer.domElement, stage.firstChild);
    st.renderer = renderer;
    st.scene = new T.Scene();
    st.scene.background = new T.Color('#9fc3e6');
    st.camera = new T.PerspectiveCamera(45, 1, 0.01, 1000);
    st.scene.add(new T.HemisphereLight('#dfefff', '#6b5b45', 1.1));
    st.sunLight = new T.DirectionalLight('#fff4e0', 2.2);
    st.scene.add(st.sunLight, st.sunLight.target);
    st.controls = new T.OrbitControls(st.camera, renderer.domElement);
    st.controls.enableDamping = false;
    st.controls.addEventListener('change', () => { draw(); scheduleShader(); });
    new ResizeObserver(() => { resize(); draw(); scheduleShader(); }).observe(stage);
  }

  function resize() {
    if (!st.renderer) return;
    const w = Math.max(1, stage.clientWidth), h = Math.max(1, stage.clientHeight);
    st.renderer.setSize(w, h, false);
    st.renderer.domElement.style.width = '100%';
    st.renderer.domElement.style.height = '100%';
    st.camera.aspect = w / h;
    applyFov();
    st.camera.updateProjectionMatrix();
  }

  // O shader aplica o fov na MENOR dimensão da tela; o three, na vertical
  let sceneFov = 45;
  function applyFov() {
    const a = st.camera.aspect;
    st.camera.fov = a >= 1 ? sceneFov : (2 * Math.atan(Math.tan((sceneFov * Math.PI) / 360) / a) * 180) / Math.PI;
  }

  function draw() {
    if (!st.renderer || !st.model) return;
    const sun = getSun(), d = Math.hypot(...sun) || 1;
    st.sunLight.position.copy(st.controls.target).add(new st.T.Vector3(sun[0] / d, sun[1] / d, sun[2] / d).multiplyScalar(20));
    st.sunLight.target.position.copy(st.controls.target);
    st.renderer.render(st.scene, st.camera);
  }

  function setCameraFromEditor() {
    const v = getView();
    sceneFov = v.fov;
    st.camera.position.set(...v.eye);
    st.controls.target.set(...v.target);
    const dist = Math.hypot(v.eye[0] - v.target[0], v.eye[1] - v.target[1], v.eye[2] - v.target[2]);
    const box = st.model ? new st.T.Box3().setFromObject(st.model) : null;
    const r = box ? box.getSize(new st.T.Vector3()).length() / 2 : 1;
    st.camera.near = Math.max(0.001, Math.min(dist, r) / 200);
    st.camera.far = Math.max(1000, dist * 100);
    resize();
    st.controls.update();
    draw();
    scheduleShader(true);
  }

  // ---------- shader no mesmo ângulo ----------
  let shaderTimer = null;
  function scheduleShader(now = false) {
    if (st.mode === 'glb' || !st.model) return;
    clearTimeout(shaderTimer);
    shaderTimer = setTimeout(refreshShader, now ? 0 : 180);
  }
  async function refreshShader() {
    if (!st.model || !st.camera) return;
    const token = ++st.shaderToken;
    const w = Math.max(2, Math.round(stage.clientWidth * 0.75)), h = Math.max(2, Math.round(stage.clientHeight * 0.75));
    const p = st.camera.position, t = st.controls.target;
    try {
      const url = await renderShader({ eye: [p.x, p.y, p.z], target: [t.x, t.y, t.z], fov: sceneFov }, w, h);
      if (token === st.shaderToken) shaderImg.src = url;
    } catch (e) { /* sem shader (cena em erro): a malha continua visível */ }
  }

  // ---------- modos ----------
  function applyCompare() {
    const showShader = st.mode !== 'glb', showGlb = st.mode !== 'shader';
    shaderImg.style.display = showShader ? '' : 'none';
    if (st.renderer) st.renderer.domElement.style.visibility = showGlb ? 'visible' : 'hidden';
    const pct = st.mode === 'split' ? st.split * 100 : 100;
    shaderImg.style.clipPath = st.mode === 'split' ? `inset(0 ${100 - pct}% 0 0)` : 'none';
    divider.style.display = st.mode === 'split' ? '' : 'none';
    divider.style.left = `${pct}%`;
    $('gcTagL').style.display = showShader ? '' : 'none';
    $('gcTagR').style.display = showGlb ? '' : 'none';
    $('gcTagL').style.left = '10px';
    $('gcTagR').style.right = '10px';
    document.querySelectorAll('#gcCompare button').forEach((b) => b.classList.toggle('on', b.dataset.m === st.mode));
    if (showShader) scheduleShader(true);
  }

  function eachMesh(fn) { for (const part of st.parts) part.traverse((o) => { if (o.isMesh && !o.userData.wire) fn(o); }); }

  function applyStyle() {
    if (!st.model) return;
    const T = st.T;
    document.querySelectorAll('#gcStyle button').forEach((b) => b.classList.toggle('on', b.dataset.s === st.style));
    st.normalMat ??= new T.MeshNormalMaterial();
    eachMesh((m) => {
      m.userData.orig ??= m.material;
      m.material = st.style === 'normals' ? st.normalMat : m.userData.orig;
      // com triângulos, o sólido recua um pouco para as arestas aparecerem por cima
      m.material.polygonOffset = st.style === 'wire';
      m.material.polygonOffsetFactor = 1;
      m.material.polygonOffsetUnits = 1;
      let w = st.wires.get(m);
      if (st.style === 'wire' && !w) {
        w = new T.Mesh(m.geometry, new T.MeshBasicMaterial({ color: 0x10131a, wireframe: true }));
        w.userData.wire = true;
        m.add(w);
        st.wires.set(m, w);
      }
      if (w) w.visible = st.style === 'wire';
    });
    draw();
  }

  function applyIsolation() {
    st.parts.forEach((p, i) => { p.visible = st.isolated < 0 || st.isolated === i; });
    side.querySelectorAll('tr.part').forEach((tr) => tr.classList.toggle('iso', Number(tr.dataset.i) === st.isolated));
    draw();
  }

  // ---------- relatório ----------
  function renderReport() {
    const s = st.stats;
    if (st.error) { side.innerHTML = `<div class="verdict ruim">${esc(st.error)}</div>`; return; }
    if (!s) { side.innerHTML = ''; return; }
    const reps = s.partReports ?? [];
    const rank = { ok: 0, 'atenção': 1, ruim: 2 };
    const worst = reps.filter((r) => r.status).reduce((a, r) => (rank[r.status] > rank[a] ? r.status : a), 'ok');
    const worstErr = Math.max(0, ...reps.filter((r) => r.status).map((r) => Math.max(r.maxError, r.faceError)));
    const lostParts = reps.filter((r) => r.reason === 'volume');
    const verdictText = lostParts.length
      ? `Faltou geometria: ${lostParts.map((r) => `${esc(r.name)} (${Math.round((1 - r.volumeRatio) * 100)}% do volume)`).join(', ')}. São partes mais finas que a célula da conversão (grama, fios, lâminas): suba o detalhe, ou modele-as mais grossas para o GLB.`
      : {
        ok: 'A malha segue a forma: desvios dentro de ~0,6 célula e nenhum volume perdido.',
        'atenção': 'Há peças com desvio entre 0,6 e 1 célula: confira as marcadas em amarelo (suba o detalhe).',
        ruim: 'Há peças com desvio maior que 1 célula: a malha se afasta da forma. Suba o detalhe e confira as peças em vermelho.',
      }[worst];
    const rows = reps.map((r, i) => {
      if (r.empty) return `<tr><td><span class="dot empty"></span>${esc(r.name)}</td><td colspan="4" class="muted">sem superfície</td></tr>`;
      const idx = reps.slice(0, i).filter((x) => !x.empty).length;
      return `<tr class="part" data-i="${idx}" title="Clique para isolar esta peça"><td><span class="dot ${r.status}"></span>${esc(r.name)}</td><td title="${r.method === 'direta' ? 'triângulos gerados direto das primitivas: exatos' : 'forma amostrada numa grade (célula de ' + mm(r.cell) + ' mm)'}">${r.method === 'direta' ? 'direta' : 'grade'}</td><td>${r.triangles.toLocaleString('pt-BR')}</td><td>${r.method === 'direta' ? 'exata' : mm(Math.max(r.maxError, r.faceError))}</td><td${r.reason === 'volume' ? ' style="color:var(--error)"' : ''}>${r.volumeRatio === null || r.volumeRatio === undefined ? '—' : `${Math.round(r.volumeRatio * 100)}%`}</td></tr>`;
    }).join('');
    side.innerHTML = `
      <h3>Resultado</h3>
      <div class="verdict ${worst}"><b>${worst === 'ok' ? '✓ Conversão boa' : worst === 'ruim' ? '✗ Conversão com problemas' : '⚠ Conferir'}</b><br>${verdictText}</div>
      <h3>Arquivo</h3>
      <div>${s.parts} peças · ${s.triangles.toLocaleString('pt-BR')} triângulos · ${s.vertices.toLocaleString('pt-BR')} vértices<br>${MB(s.bytes)} · exportado em ${(s.ms / 1000).toFixed(1)} s${s.bones ? ` · ${s.bones} ossos` : ''}${s.animated ? ' · animado' : ''}<br>
        <span class="muted">pior desvio: ${mm(worstErr)} mm</span></div>
      ${(s.warnings ?? []).length ? `<h3>Avisos</h3>${s.warnings.map((w) => `<div>⚠ ${esc(w)}</div>`).join('')}` : ''}
      <h3>Peças <span class="muted" style="text-transform:none;letter-spacing:0">(desvio em mm; volume = quanto da forma virou malha)</span></h3>
      <table><tr><th>peça</th><th>via</th><th>triâng.</th><th>desvio</th><th>volume</th></tr>${rows}</table>
      <h3>Como ler</h3>
      <div class="muted">Via: "direta" = triângulos gerados direto das primitivas (exatos, nada se perde); "grade" = a forma foi amostrada numa grade, usado quando há subtrações, deformações, fórmulas ou ruído. Desvio: quanto a malha se afasta da forma exata, medido nos vértices e no centro dos triângulos. A célula é o tamanho do voxel da conversão; o método garante desvio abaixo de ~0,6 célula. O volume compara a malha com a forma (amostragem aleatória): bem abaixo de 100% é geometria perdida, o que o desvio sozinho não mostra. "Triângulos" mostra a densidade (faces planas têm poucos, curvas têm mais) e "Normais" mostra o sombreamento: quinas devem ter cor chapada de cada lado.</div>`;
    side.querySelectorAll('tr.part').forEach((tr) => tr.addEventListener('click', () => {
      const i = Number(tr.dataset.i);
      st.isolated = st.isolated === i ? -1 : i;
      applyIsolation();
    }));
  }

  // ---------- exportação ----------
  function setBusy(text) {
    busy.hidden = !text;
    busyText.textContent = text ?? '';
  }

  async function run(res = st.res) {
    st.res = res;
    $('gcRes').value = String(res);
    const token = ++st.token;
    st.job?.cancel();
    clearInterval(st.ticker);
    st.error = null;
    st.isolated = -1;
    const t0 = performance.now();
    setBusy('Exportando…');
    st.ticker = setInterval(() => { busyText.textContent = `Exportando… ${((performance.now() - t0) / 1000).toFixed(0)} s`; }, 500);
    try {
      await ensureThree();
      const job = sceneTask('export', getCode(), { res, time: getTime() });
      st.job = job;
      const { glb, stats } = await job.promise;
      if (token !== st.token) return;
      // tempo total (a malha das peças roda antes, em outros workers; stats.ms só conta a montagem)
      st.glb = glb; st.stats = { ...stats, ms: performance.now() - t0 };
      busyText.textContent = 'Carregando a malha…';
      const gltf = await new Promise((resolve, reject) => new st.T.GLTFLoader().parse(glb.buffer.slice(glb.byteOffset, glb.byteOffset + glb.byteLength), '', resolve, reject));
      if (token !== st.token) return;
      if (st.model) { st.scene.remove(st.model); st.wires.clear(); }
      st.model = gltf.scene;
      st.model.traverse((o) => { if (o.isMesh) o.frustumCulled = false; });
      st.scene.add(st.model);
      const nParts = (stats.partReports ?? []).filter((r) => !r.empty).length;
      st.parts = st.model.children.slice(0, nParts);
      setCameraFromEditor();
      applyStyle();
      applyCompare();
    } catch (e) {
      if (e?.name === 'AbortError' || token !== st.token) return;
      st.error = `Não foi possível exportar: ${e.message ?? e}`;
      st.stats = null;
    } finally {
      if (token === st.token) { clearInterval(st.ticker); setBusy(null); renderReport(); }
    }
  }

  // ---------- controles ----------
  function open(res = st.res) {
    root.hidden = false;
    applyCompare();
    return run(res);
  }
  function close() {
    root.hidden = true;
    st.token++;
    st.job?.cancel();
    clearInterval(st.ticker);
    setBusy(null);
  }

  document.querySelectorAll('#gcCompare button').forEach((b) => { b.onclick = () => { st.mode = b.dataset.m; applyCompare(); draw(); }; });
  document.querySelectorAll('#gcStyle button').forEach((b) => { b.onclick = () => { st.style = b.dataset.s; applyStyle(); }; });
  $('gcRun').onclick = () => run(Number($('gcRes').value));
  $('gcRes').onchange = () => run(Number($('gcRes').value));
  $('gcFrame').onclick = () => setCameraFromEditor();
  $('gcClose').onclick = close;
  $('gcCancel').onclick = close;
  $('gcSave').onclick = () => st.glb && saveGlb?.(st.glb);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !root.hidden) { e.stopPropagation(); close(); } }, true);
  divider.addEventListener('pointerdown', (e) => {
    divider.setPointerCapture(e.pointerId);
    const move = (ev) => {
      const r = stage.getBoundingClientRect();
      st.split = Math.min(0.97, Math.max(0.03, (ev.clientX - r.left) / r.width));
      applyCompare();
    };
    const up = () => { divider.removeEventListener('pointermove', move); divider.removeEventListener('pointerup', up); };
    divider.addEventListener('pointermove', move);
    divider.addEventListener('pointerup', up);
  });

  return {
    open, close, run,
    isOpen: () => !root.hidden,
    hasModel: () => !!st.model,
    // para agentes: imagem da malha (ou do modo atual) + relatório em texto
    async capture({ style = null, mode = null, width = 960, height = 640 } = {}) {
      if (style) { st.style = style; applyStyle(); }
      if (mode) { st.mode = mode; applyCompare(); }
      // 'shader': a imagem da forma exata; senão a malha (em 'split', a malha inteira: a divisória é só do usuário)
      if (st.mode === 'shader') {
        await refreshShader();
        return shaderImg.src.split(',')[1];
      }
      st.renderer.setSize(width, height, false);
      st.camera.aspect = width / height;
      applyFov();
      st.camera.updateProjectionMatrix();
      draw();
      const url = st.renderer.domElement.toDataURL('image/png');
      resize();
      draw();
      return url.split(',')[1];
    },
    reportText() {
      const s = st.stats;
      if (st.error) return st.error;
      if (!s) return 'sem exportação ainda';
      const lines = [`${s.parts} peças · ${s.triangles} triângulos · ${MB(s.bytes)} · ${(s.ms / 1000).toFixed(1)} s · detalhe ${st.res}`];
      for (const r of s.partReports ?? []) lines.push(r.empty ? `  ${r.name}: sem superfície` : r.method === 'direta' ? `  ${r.name}: ${r.triangles} triângulos, malha direta (exata)` : `  ${r.name}: ${r.triangles} triângulos, amostrada, desvio ${mm(Math.max(r.maxError, r.faceError))} mm (célula ${mm(r.cell)} mm)${r.volumeRatio == null ? '' : `, volume ${Math.round(r.volumeRatio * 100)}%`} — ${r.status}${r.reason === 'volume' ? ' (faltou geometria: partes finas demais para este detalhe)' : ''}`);
      for (const w of s.warnings ?? []) lines.push(`aviso: ${w}`);
      return lines.join('\n');
    },
  };
}
