// Configurações (⚙): vozes do Qwen3-TTS (instalar, modelo, dispositivo, voz padrão, ouvir) e modelos dos
// agentes (padrão de cada um e lista de modelos próprios). Ficam no servidor, em ~/.local/share/3di.
export function createSettingsDialog({ button, onChange = () => {} }) {
  const box = document.createElement('div');
  box.id = 'settingsDialog';
  box.hidden = true;
  box.innerHTML = `<div class="card">
    <h3>Configurações</h3>
    <section>
      <h4>Vozes (Qwen3-TTS)</h4>
      <p class="tts-state"></p>
      <div class="row"><button data-a="install">Instalar vozes</button><button data-a="remove">Remover vozes</button></div>
      <label>Modelo <select data-k="tts.model"></select></label>
      <label>Dispositivo <select data-k="tts.device"><option value="auto">automático (GPU se houver)</option><option value="cuda">GPU</option><option value="cpu">CPU (lento)</option></select></label>
      <label>Voz padrão (say() sem voice) <select data-k="tts.speaker"></select></label>
      <label>Idioma <select data-k="tts.language">${['Portuguese', 'English', 'Spanish', 'French', 'German', 'Italian', 'Russian', 'Japanese', 'Korean', 'Chinese', 'Auto'].map((l) => `<option>${l}</option>`).join('')}</select></label>
      <label>Estilo padrão (instruct) <input data-k="tts.instruct" placeholder="ex.: tom calmo e claro"></label>
      <div class="row"><input data-k="sample" value="Olá! Esta é a minha voz no três D I." title="Texto para ouvir"><button data-a="listen">Ouvir</button></div>
    </section>
    <section>
      <h4>Agentes</h4>
      ${['claude', 'codex'].map((p) => `<div class="agent" data-p="${p}">
        <b>${p === 'claude' ? 'Claude Code' : 'Codex'}</b> <span class="ver"></span>
        <label>Modelo padrão <select data-k="agents.${p}.model"></select></label>
        <div class="models"></div>
        <div class="row"><input placeholder="adicionar modelo (ex.: ${p === 'claude' ? 'claude-sonnet-5-5' : 'gpt-5.5-codex'})"><button data-a="add">Adicionar</button></div>
      </div>`).join('')}
    </section>
    <pre class="log"></pre>
    <div class="actions"><button data-a="close" class="primary">Fechar</button></div>
  </div>`;
  document.body.append(box);
  const $ = (s) => box.querySelector(s);
  const logEl = $('.log');
  let token = null, data = null, es = null, audio = null;
  const BUILTIN = { claude: [['', 'padrão do Claude Code'], ['sonnet', 'Sonnet'], ['opus', 'Opus'], ['haiku', 'Haiku']], codex: [['', 'padrão do Codex']] };

  const log = (text) => { logEl.hidden = false; logEl.textContent = `${logEl.textContent}${text}\n`.split('\n').slice(-10).join('\n'); logEl.scrollTop = logEl.scrollHeight; };
  const call = async (path, body) => {
    token ??= (await (await fetch('/bridge/session', { headers: { 'X-3DI-Client': 'ide' } })).json()).token;
    const r = await fetch(path, { method: body === undefined ? 'GET' : 'POST', headers: { 'X-3DI-Token': token, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error ?? `erro ${r.status}`);
    return j;
  };
  const get = (o, path) => path.split('.').reduce((v, k) => v?.[k], o);
  const patchOf = (path, value) => path.split('.').reduceRight((v, k) => ({ [k]: v }), value);
  const save = async (patch) => { data.settings = (await call('/settings', patch)).settings; onChange(data.settings); render(); };

  const render = async () => {
    const s = data.settings;
    $('[data-k="tts.model"]').replaceChildren(...data.ttsModels.map((m) => new Option(m.label, m.id)));
    $('[data-k="tts.speaker"]').replaceChildren(...data.speakers.map((v) => new Option(`${v.id} (${v.note})`, v.id)));
    for (const p of ['claude', 'codex']) {
      const opts = [...BUILTIN[p], ...s.agents[p].models.map((m) => [m, m])];
      box.querySelector(`[data-k="agents.${p}.model"]`).replaceChildren(...opts.map(([v, l]) => new Option(l, v)));
      const list = box.querySelector(`[data-p=${p}] .models`);
      list.replaceChildren(...s.agents[p].models.map((m) => {
        const chip = document.createElement('span');
        chip.className = 'chip';
        chip.textContent = m;
        const x = document.createElement('button');
        x.textContent = '✕';
        x.title = 'Remover este modelo';
        x.onclick = () => save({ agents: { [p]: { models: s.agents[p].models.filter((v) => v !== m), model: s.agents[p].model === m ? '' : s.agents[p].model } } });
        chip.append(x);
        return chip;
      }));
    }
    for (const el of box.querySelectorAll('[data-k^="tts."], [data-k^="agents."]')) el.value = get(s, el.dataset.k) ?? '';
    const st = data.status;
    $('.tts-state').textContent = !st ? 'Servidor do 3DI indisponível.' : st.installing ? 'Instalando as vozes…'
      : st.tts.installed ? `Instaladas em ${st.tts.dir}.` : `Não instaladas. O 3DI cria um ambiente Python em ${st.tts.dir} (alguns GB; precisa do python3-venv).`;
    $('[data-a=install]').textContent = st?.tts.installed ? 'Reinstalar vozes' : 'Instalar vozes';
    $('[data-a=install]').disabled = !st || st.installing;
    $('[data-a=remove]').hidden = !st?.tts.installed;
    $('[data-a=listen]').disabled = !st?.tts.installed;
  };

  const open = async () => {
    box.hidden = false;
    logEl.hidden = true;
    logEl.textContent = '';
    try {
      data = await call('/settings');
      data.status = await call('/video/status').catch(() => null);
      const agents = await call('/agent/status').catch(() => null);
      for (const p of ['claude', 'codex']) {
        const a = agents?.agents?.[p];
        box.querySelector(`[data-p=${p}] .ver`).textContent = a ? (a.available ? a.version : 'não encontrado: instale o CLI e faça login') : '';
      }
      if (!es) {
        es = new EventSource(`/video/events?token=${encodeURIComponent(token)}`);
        es.onmessage = async (ev) => {
          const e = JSON.parse(ev.data);
          if (e.kind === 'log') log(e.text);
          else if (e.kind === 'error') log(`erro: ${e.text}`);
          if (e.kind === 'tts-ready' || e.kind === 'error') { data.status = await call('/video/status').catch(() => null); render(); }
        };
        es.onerror = () => { es.close(); es = null; };
      }
      render();
    } catch (e) { $('.tts-state').textContent = `Configurações indisponíveis: ${e.message} (abra pelo app 3DI ou npm run dev).`; }
  };

  box.addEventListener('change', (e) => {
    const k = e.target.dataset.k;
    if (k && (k.startsWith('tts.') || k.startsWith('agents.'))) save(patchOf(k, e.target.value)).catch((err) => log(`erro: ${err.message}`));
  });
  box.addEventListener('click', async (e) => {
    const a = e.target.dataset.a;
    try {
      if (a === 'close') box.hidden = true;
      else if (a === 'install') { log('instalando as vozes…'); await call('/video/install-tts', {}); data.status = await call('/video/status'); render(); }
      else if (a === 'remove') {
        if (!confirm('Remover o ambiente das vozes e as falas em cache?')) return;
        await call('/video/remove-tts', {});
        data.status = await call('/video/status');
        render();
        log('vozes removidas');
      } else if (a === 'listen') {
        e.target.disabled = true;
        log('gerando a amostra…');
        const r = await call('/video/sample', { text: $('[data-k=sample]').value });
        audio?.pause();
        audio = new Audio(`/video/clip?k=${r.key}&token=${encodeURIComponent(token)}`);
        audio.play().catch(() => {});
        log(`amostra: ${r.seconds.toFixed(1)} s`);
        e.target.disabled = false;
      } else if (a === 'add') {
        const p = e.target.closest('.agent').dataset.p;
        const input = e.target.previousElementSibling;
        const m = input.value.trim();
        if (!m) return;
        input.value = '';
        await save({ agents: { [p]: { models: [...data.settings.agents[p].models, m] } } });
      }
    } catch (err) { log(`erro: ${err.message}`); if (a === 'listen') e.target.disabled = false; }
  });
  button.onclick = open;
  return { open };
}
