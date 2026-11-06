// Configurações (⚙): provedor das falas (Qwen3-TTS local ou ElevenLabs), templates de áudio, vozes do Qwen
// (instalar, modelo, voz padrão, clonadas) e modelos dos agentes. Ficam no servidor, em ~/.local/share/3di;
// a chave do ElevenLabs vai para secrets.json e só volta para cá como '…1234'.
import { hydrateIcons } from './icons.js';

export function createSettingsDialog({ button, onChange = () => {} }) {
  const box = document.createElement('div');
  box.id = 'settingsDialog';
  box.hidden = true;
  box.className = 'modal';
  box.setAttribute('role', 'dialog');
  box.setAttribute('aria-modal', 'true');
  box.setAttribute('aria-labelledby', 'settingsTitle');
  box.innerHTML = `<div class="modal-card settings-card">
    <div class="modal-head">
      <h3 id="settingsTitle">Configurações</h3><span class="spacer"></span>
      <button data-a="close" class="ghost icon-btn" title="Fechar (Esc)" aria-label="Fechar"><i data-icon="x"></i></button>
    </div>
    <div class="settings-layout">
    <nav class="settings-nav" aria-label="Categorias"><button data-page="provider" class="on"><i data-icon="audio-lines"></i>Provedor das falas</button><button data-page="eleven" class=""><i data-icon="key-round"></i>ElevenLabs</button><button data-page="templates" class=""><i data-icon="list"></i>Templates de áudio</button><button data-page="qwen" class=""><i data-icon="cpu"></i>Vozes Qwen</button><button data-page="clone" class=""><i data-icon="mic"></i>Vozes clonadas</button><button data-page="agents" class=""><i data-icon="sparkles"></i>Agentes</button></nav>
    <div class="settings-pages">
    <section class="page" data-page="provider">
      <h4>Provedor das falas</h4>
      <label>Provedor padrão (vale para voice() sem provider) <select data-k="tts.provider"></select></label>
      <label>Template padrão <select data-k="tts.template"></select></label>
      <div class="row"><input data-k="sample" value="Olá! Esta é a minha voz no três D I." title="Texto para ouvir"><button data-a="listen">Ouvir</button></div>
    </section>
    <section class="page eleven" data-page="eleven" hidden>
      <h4>ElevenLabs</h4>
      <p class="hint eleven-state"></p>
      <div class="row"><input data-e="key" type="password" autocomplete="off" placeholder="cole aqui a sua chave de API (xi-api-key)"><button data-a="eleven-key">Salvar chave</button><button data-a="eleven-forget">Apagar</button></div>
      <label>Modelo <select data-k="elevenlabs.model"></select></label>
      <div class="row"><select data-e="voice"><option value="">— carregue as vozes da sua conta —</option></select><button data-a="eleven-load">Carregar vozes</button></div>
      <p class="hint eleven-error" hidden></p>
      <div class="row"><input data-e="voice-id" placeholder="ou cole o ID da voz (elevenlabs.io → Voices → ⋯ → Copy voice ID)"><button data-a="eleven-voice-id">Usar ID</button></div>
      <p class="hint">No script: <code>voice("narrador", provider="elevenlabs", speaker="Nome da voz")</code>. As marcações de áudio dos templates (ex.: [excited]) só valem no modelo v3.</p>
    </section>
    <section class="page templates" data-page="templates" hidden>
      <h4>Templates de áudio</h4>
      <p class="hint">Estilos com o prompt usado na fala. No script: <code>say("...", style="narrador")</code> ou <code>voice("n", template="calmo")</code>. O prompt vai para o Qwen3-TTS; marcações, estabilidade, estilo e velocidade, para o ElevenLabs.</p>
      <div class="tpl-list"></div>
      <details class="tpl-form"><summary>Novo template / editar</summary>
        <label>Nome no script (sem espaços) <input data-t="id" placeholder="ex.: vilao"></label>
        <label>Descrição <input data-t="label" placeholder="ex.: Vilão de desenho"></label>
        <label>Prompt (instrução de estilo) <textarea data-t="prompt" rows="2" placeholder="ex.: voz grave e teatral de vilão, rindo entre as frases"></textarea></label>
        <label>Marcações do ElevenLabs v3 <input data-t="tags" placeholder="ex.: [laughs] [dramatic]"></label>
        <div class="row"><label>Estabilidade <input data-t="stability" type="number" min="0" max="1" step="0.05"></label><label>Estilo <input data-t="style" type="number" min="0" max="1" step="0.05"></label><label>Velocidade <input data-t="speed" type="number" min="0.7" max="1.2" step="0.01"></label></div>
        <div class="row"><button data-a="tpl-save" class="primary">Salvar template</button><button data-a="tpl-listen">Ouvir com este template</button></div>
      </details>
    </section>
    <section class="page" data-page="qwen" hidden>
      <h4>Vozes (Qwen3-TTS)</h4>
      <p class="tts-state"></p>
      <div class="row"><button data-a="install">Instalar vozes</button><button data-a="remove">Remover vozes</button></div>
      <label>Modelo <select data-k="tts.model"></select></label>
      <label>Dispositivo <select data-k="tts.device"><option value="auto">automático (GPU se houver)</option><option value="cuda">GPU</option><option value="cpu">CPU (lento)</option></select></label>
      <label>Voz padrão (say() sem voice) <select data-k="tts.speaker"></select></label>
      <label>Idioma <select data-k="tts.language">${['Portuguese', 'English', 'Spanish', 'French', 'German', 'Italian', 'Russian', 'Japanese', 'Korean', 'Chinese', 'Auto'].map((l) => `<option>${l}</option>`).join('')}</select></label>
      <label>Estilo padrão (instruct) <input data-k="tts.instruct" placeholder="ex.: tom calmo e claro"></label>
    </section>
    <section class="page clone" data-page="clone" hidden>
      <h4>Vozes clonadas</h4>
      <p class="hint">Clone qualquer voz a partir de 5 a 20 segundos de fala limpa (sem música nem ruído). Use a sua voz ou a de quem autorizou. No script: <code>voice("narrador", speaker="nome")</code>.</p>
      <div class="voices"></div>
      <label>Nome (sem espaços) <input data-c="name" placeholder="ex.: minha-voz"></label>
      <div class="row"><input data-c="file" type="file" accept="audio/*"><button data-a="record" title="Grava pelo microfone (até 20 s)"><i data-icon="mic"></i>Gravar</button></div>
      <audio data-c="preview" controls hidden></audio>
      <label>Texto falado no áudio (melhora a cópia; pode deixar vazio) <textarea data-c="text" rows="2"></textarea></label>
      <label>Idioma da voz <select data-c="language">${['Portuguese', 'English', 'Spanish', 'French', 'German', 'Italian', 'Russian', 'Japanese', 'Korean', 'Chinese'].map((l) => `<option>${l}</option>`).join('')}</select></label>
      <label>Modelo de clonagem <select data-k="tts.cloneModel"></select></label>
      <div class="row"><button data-a="clone" class="primary">Clonar voz</button></div>
    </section>
    <section class="page" data-page="agents" hidden>
      <h4>Agentes</h4>
      ${['claude', 'codex'].map((p) => `<div class="agent" data-p="${p}">
        <b>${p === 'claude' ? 'Claude Code' : 'Codex'}</b> <span class="ver"></span>
        <div class="hint agent-info"></div>
        <label>Executável (vazio = procurar sozinho) <input data-k="agents.${p}.path" placeholder="${p === 'claude' ? '~/.local/bin/claude' : '/caminho/para/codex ou codex.js'}"></label>
        <div class="row"><button data-a="agent-rescan">Detectar novamente</button><button data-a="agent-login">Ver login</button></div>
        <div class="hint">Instalar: <code>${p === 'claude' ? 'npm i -g @anthropic-ai/claude-code' : 'npm i -g @openai/codex'}</code> · login: <code>${p === 'claude' ? 'claude' : 'codex login'}</code> num terminal</div>
        <label>Modelo padrão <select data-k="agents.${p}.model"></select></label>
        <div class="models"></div>
        <div class="row"><input placeholder="adicionar modelo (ex.: ${p === 'claude' ? 'claude-sonnet-5-5' : 'gpt-5.5-codex'})"><button data-a="add">Adicionar</button></div>
      </div>`).join('')}
    </section>
    </div>
    </div>
    <div class="modal-foot"><pre class="log"></pre><span class="spacer"></span><button data-a="close" class="primary">Concluído</button></div>
  </div>`;
  hydrateIcons(box);
  // navegação entre as categorias
  box.querySelector('.settings-nav').addEventListener('click', (e) => {
    const b = e.target.closest('[data-page]');
    if (!b) return;
    for (const n of box.querySelectorAll('.settings-nav [data-page]')) n.classList.toggle('on', n === b);
    for (const pg of box.querySelectorAll('.settings-pages .page')) pg.hidden = pg.dataset.page !== b.dataset.page;
  });
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
    $('[data-k="tts.provider"]').replaceChildren(...data.providers.map((p) => new Option(p.label, p.id)));
    $('[data-k="tts.template"]').replaceChildren(new Option('nenhum', ''), ...s.templates.map((x) => new Option(`${x.label} (${x.id})`, x.id)));
    $('[data-k="elevenlabs.model"]').replaceChildren(...data.elevenModels.map((m) => new Option(m.label, m.id)));
    const ek = data.elevenKey;
    $('.eleven-state').textContent = ek.set ? `Chave salva (${ek.hint})${ek.fromEnv ? ', vinda de ELEVENLABS_API_KEY' : ''}. Voz padrão: ${s.elevenlabs.voiceName || 'nenhuma'}.` : 'Sem chave. Crie uma em elevenlabs.io → Profile → API keys.';
    $('[data-a=eleven-forget]').hidden = !ek.set || ek.fromEnv;
    const vsel = $('[data-e=voice]');
    if (vsel.options.length <= 1 && s.elevenlabs.voice) vsel.replaceChildren(new Option('— carregue as vozes da sua conta —', ''), new Option(s.elevenlabs.voiceName || s.elevenlabs.voice, s.elevenlabs.voice));
    vsel.value = s.elevenlabs.voice;
    $('.tpl-list').replaceChildren(...s.templates.map((x) => {
      const row = document.createElement('div');
      row.className = 'voice';
      row.dataset.tpl = x.id;
      row.innerHTML = `<b></b><span></span><button data-a="tpl-edit">Editar</button><button data-a="tpl-delete">Remover</button>`;
      row.querySelector('b').textContent = x.id;
      row.querySelector('span').textContent = `${x.label}${s.tts.template === x.id ? ' · padrão' : ''} — ${x.prompt}`;
      row.title = x.prompt;
      return row;
    }));
    $('[data-k="tts.model"]').replaceChildren(...data.ttsModels.map((m) => new Option(m.label, m.id)));
    $('[data-k="tts.speaker"]').replaceChildren(...data.speakers.map((v) => new Option(`${v.id} (${v.note})`, v.id)), ...s.voices.map((v) => new Option(`${v.id} (clonada)`, v.id)));
    $('[data-k="tts.cloneModel"]').replaceChildren(...data.cloneModels.map((m) => new Option(m.label, m.id)));
    $('.voices').replaceChildren(...s.voices.map((v) => {
      const row = document.createElement('div');
      row.className = 'voice';
      row.innerHTML = `<b></b><span></span><button data-a="voice-listen">Ouvir</button><button data-a="voice-default">Usar como padrão</button><button data-a="voice-delete">Remover</button>`;
      row.dataset.voice = v.id;
      row.querySelector('b').textContent = v.id;
      row.querySelector('span').textContent = `${v.language}${s.tts.speaker === v.id ? ' · padrão' : ''}`;
      return row;
    }));
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

  const showAgents = (agents) => {
    for (const p of ['claude', 'codex']) {
      const a = agents?.[p];
      box.querySelector(`[data-p=${p}] .ver`).textContent = a ? (a.available ? `✓ ${a.version}` : '✗ não encontrado') : '';
      box.querySelector(`[data-p=${p}] .agent-info`).textContent = !a ? '' : a.available ? a.path
        : `${a.custom ? `o caminho configurado não funcionou. ` : ''}Tentados: ${a.tried.join(' · ') || 'nenhum candidato existe'}`;
    }
  };
  const open = async () => {
    box.hidden = false;
    logEl.hidden = true;
    logEl.textContent = '';
    try {
      data = await call('/settings');
      data.status = await call('/video/status').catch(() => null);
      showAgents((await call('/agent/status').catch(() => null))?.agents);
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
    if (k && (k.startsWith('tts.') || k.startsWith('agents.') || k.startsWith('elevenlabs.'))) save(patchOf(k, e.target.value)).then(() => k.endsWith('.path') && call('/agent/rescan', {}).then((r) => showAgents(r.agents))).catch((err) => log(`erro: ${err.message}`));
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
      } else if (a === 'eleven-key') {
        const k = $('[data-e=key]').value.trim();
        if (!k) throw new Error('cole a chave de API no campo');
        const r = await call('/settings', { elevenKey: k });
        $('[data-e=key]').value = '';
        data.settings = r.settings; data.elevenKey = r.elevenKey;
        render();
        log('chave salva; carregando as vozes da conta…');
        await loadEleven();
      } else if (a === 'eleven-forget') {
        if (!confirm('Apagar a chave do ElevenLabs deste computador?')) return;
        const r = await call('/settings', { elevenKey: '' });
        data.settings = r.settings; data.elevenKey = r.elevenKey;
        render();
      } else if (a === 'eleven-load') {
        await loadEleven();
      } else if (a === 'eleven-voice-id') {
        const id = $('[data-e=voice-id]').value.trim();
        if (!/^[\w-]{8,64}$/.test(id)) throw new Error('ID de voz inválido (copie em elevenlabs.io → Voices → ⋯ → Copy voice ID)');
        await save({ elevenlabs: { voice: id, voiceName: id } });
        $('[data-e=voice-id]').value = '';
        log(`voz padrão do ElevenLabs: ${id}`);
      } else if (a === 'tpl-edit') {
        const x = data.settings.templates.find((t) => t.id === e.target.closest('[data-tpl]').dataset.tpl);
        for (const k of ['id', 'label', 'prompt', 'tags', 'stability', 'style', 'speed']) box.querySelector(`[data-t=${k}]`).value = x[k] ?? '';
        $('.tpl-form').open = true;
      } else if (a === 'tpl-delete') {
        const id = e.target.closest('[data-tpl]').dataset.tpl;
        if (!confirm(`Remover o template '${id}'?`)) return;
        await save({ templates: data.settings.templates.filter((t) => t.id !== id), tts: data.settings.tts.template === id ? { template: '' } : {} });
      } else if (a === 'tpl-save' || a === 'tpl-listen') {
        const v = (k) => box.querySelector(`[data-t=${k}]`).value.trim();
        const tpl = { id: v('id'), label: v('label') || v('id'), prompt: v('prompt'), tags: v('tags'), stability: v('stability'), style: v('style'), speed: v('speed') };
        if (!/^[A-Za-z0-9_-]{2,40}$/.test(tpl.id)) throw new Error('nome do template: 2 a 40 letras, números, - ou _');
        await save({ templates: [...data.settings.templates.filter((t) => t.id !== tpl.id), tpl] });
        log(`template '${tpl.id}' salvo`);
        if (a === 'tpl-listen') {
          log('gerando a amostra…');
          const r = await call('/video/sample', { text: $('[data-k=sample]').value, template: tpl.id });
          audio?.pause();
          audio = new Audio(`/video/clip?k=${r.key}&token=${encodeURIComponent(token)}`);
          audio.play().catch(() => {});
          log(`amostra: ${r.seconds.toFixed(1)} s`);
        }
      } else if (a === 'record') {
        await toggleRecord(e.target);
      } else if (a === 'clone') {
        const name = $('[data-c=name]').value.trim();
        const blob = recorded ?? $('[data-c=file]').files[0];
        if (!blob) throw new Error('escolha um arquivo de áudio ou grave pelo microfone');
        e.target.disabled = true;
        log(`clonando '${name}'…`);
        const audio64 = await new Promise((ok, fail) => { const r = new FileReader(); r.onload = () => ok(String(r.result).split(',')[1]); r.onerror = fail; r.readAsDataURL(blob); });
        data.settings = (await call('/voices/clone', { name, audio: audio64, refText: $('[data-c=text]').value, language: $('[data-c=language]').value })).settings;
        onChange(data.settings);
        render();
        log(`voz '${name}' pronta; ouvindo uma amostra (a primeira vez baixa o modelo de clonagem)…`);
        e.target.disabled = false;
        await listen(name);
      } else if (a?.startsWith('voice-')) {
        const id = e.target.closest('.voice').dataset.voice;
        if (a === 'voice-listen') { log(`gerando a amostra de '${id}'…`); await listen(id); }
        else if (a === 'voice-default') await save({ tts: { speaker: id } });
        else if (a === 'voice-delete' && confirm(`Remover a voz '${id}'?`)) { data.settings = (await call('/voices/delete', { name: id })).settings; onChange(data.settings); render(); }
      } else if (a === 'agent-rescan') {
        showAgents((await call('/agent/rescan', {})).agents);
      } else if (a === 'agent-login') {
        const p = e.target.closest('.agent').dataset.p;
        const r = await call(`/agent/login?p=${p}`);
        log(`${p}: ${r.ok ? '' : 'sem login ou erro: '}${r.text}`);
      } else if (a === 'add') {
        const p = e.target.closest('.agent').dataset.p;
        const input = e.target.previousElementSibling;
        const m = input.value.trim();
        if (!m) return;
        input.value = '';
        await save({ agents: { [p]: { models: [...data.settings.agents[p].models, m] } } });
      }
    } catch (err) { log(`erro: ${err.message}`); if (a === 'listen' || a === 'clone') e.target.disabled = false; }
  });
  // vozes da conta do ElevenLabs no seletor; escolher uma a torna a voz padrão do ElevenLabs
  const loadEleven = async () => {
    const err = $('.eleven-error');
    err.hidden = true;
    let r;
    try { r = await call('/video/eleven-voices', {}); }
    catch (e) {
      // chave sem a permissão de listar vozes: explica e oferece colar o ID
      err.hidden = false;
      err.textContent = /voices_read/.test(e.message)
        ? 'A sua chave não tem permissão para listar vozes (voices_read). Em elevenlabs.io → Developers → API Keys, edite a chave e ligue "Voices: Read" (e "Text to Speech"), ou cole o ID da voz abaixo.'
        : `Não consegui carregar as vozes: ${e.message}`;
      throw e;
    }
    const sel = $('[data-e=voice]');
    sel.replaceChildren(new Option('— escolha a voz padrão —', ''), ...r.voices.map((v) => {
      const lab = [v.labels.gender, v.labels.accent, v.labels.language].filter(Boolean).join(', ');
      return new Option(`${v.name}${lab ? ` (${lab})` : ''}`, v.id);
    }));
    sel.value = data.settings.elevenlabs.voice;
    sel.dataset.names = JSON.stringify(Object.fromEntries(r.voices.map((v) => [v.id, v.name])));
    log(`${r.voices.length} voz(es) na sua conta`);
  };
  box.addEventListener('change', (e) => {
    if (e.target.dataset.e !== 'voice') return;
    const names = JSON.parse(e.target.dataset.names || '{}');
    save({ elevenlabs: { voice: e.target.value, voiceName: names[e.target.value] ?? '' } }).catch((err) => log(`erro: ${err.message}`));
  });
  // ouvir uma voz (pronta ou clonada) com o texto de amostra
  const listen = async (speaker) => {
    const r = await call('/video/sample', { text: $('[data-k=sample]').value, speaker });
    audio?.pause();
    audio = new Audio(`/video/clip?k=${r.key}&token=${encodeURIComponent(token)}`);
    audio.play().catch(() => {});
    log(`amostra: ${r.seconds.toFixed(1)} s`);
  };
  // gravação pelo microfone (MediaRecorder): até 20 s, com prévia para ouvir antes de clonar
  let recorder = null, recorded = null;
  const toggleRecord = async (btn) => {
    if (recorder) { recorder.stop(); return; }
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const chunks = [];
    recorder = new MediaRecorder(stream);
    recorder.ondataavailable = (ev) => chunks.push(ev.data);
    recorder.onstop = () => {
      stream.getTracks().forEach((t) => t.stop());
      recorded = new Blob(chunks, { type: recorder.mimeType });
      recorder = null;
      btn.textContent = 'Gravar de novo';
      const pv = $('[data-c=preview]');
      pv.src = URL.createObjectURL(recorded);
      pv.hidden = false;
      log(`gravado (${(recorded.size / 1024).toFixed(0)} KB); confira na prévia e clique em Clonar voz`);
    };
    recorder.start();
    btn.textContent = 'Parar gravação';
    log('gravando… fale de 5 a 20 segundos e clique em Parar');
    setTimeout(() => { if (recorder?.state === 'recording') recorder.stop(); }, 20000);
  };
  // escolher um arquivo descarta a gravação
  box.addEventListener('input', (e) => {
    if (e.target.dataset.c === 'file') { recorded = null; const pv = $('[data-c=preview]'); pv.src = URL.createObjectURL(e.target.files[0]); pv.hidden = false; }
  });
  button.onclick = open;
  return { open };
}
