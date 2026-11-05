// Painel Agente: conversa com o Claude Code ou o Codex rodando no servidor do 3DI (src/services/agents.mjs).
// O agente usa o MCP do 3DI, então as mudanças aparecem direto no editor e na vista.
const MODELS = {
  claude: [['', 'padrão do Claude Code'], ['sonnet', 'Sonnet'], ['opus', 'Opus'], ['haiku', 'Haiku']],
  codex: [['', 'padrão do Codex']],
};
const STORE = '3di.agent';

export function createAgentPanel(panel) {
  panel.innerHTML = `
    <div class="agent-bar">
      <select data-k="provider" title="Agente"><option value="claude">Claude Code</option><option value="codex">Codex</option></select>
      <select data-k="model" title="Modelo"></select>
      <input data-k="custom" placeholder="outro modelo" title="Nome de modelo (opcional)">
      <button data-a="reset" title="Começa uma conversa nova">Nova</button>
    </div>
    <div class="agent-info"></div>
    <div class="agent-log" aria-live="polite"></div>
    <form class="agent-input">
      <textarea rows="3" placeholder="Peça ao agente: &quot;crie uma casa com telhado vermelho&quot;, &quot;deixe o gato mais gordo&quot;... (Ctrl+Enter envia)"></textarea>
      <div class="agent-actions"><span class="agent-state"></span><button type="button" data-a="stop" hidden>Parar</button><button type="submit">Enviar</button></div>
    </form>`;
  const $ = (sel) => panel.querySelector(sel);
  const provider = $('[data-k=provider]'), model = $('[data-k=model]'), custom = $('[data-k=custom]');
  const log = $('.agent-log'), info = $('.agent-info'), input = $('textarea'), state = $('.agent-state'), stopBtn = $('[data-a=stop]'), send = $('[type=submit]');
  let token = null, busy = false, status = null, live = null, es = null;

  try { const s = JSON.parse(localStorage.getItem(STORE) || '{}'); if (s.provider) provider.value = s.provider; custom.value = s.custom ?? ''; } catch {}
  let agentSettings = { claude: { model: '', models: [] }, codex: { model: '', models: [] } };
  // modelos: os de sempre + os cadastrados nas configurações (⚙); o padrão vem de lá
  const fillModels = (keep) => {
    const own = agentSettings[provider.value].models.map((m) => [m, m]);
    model.replaceChildren(...[...MODELS[provider.value], ...own].map(([v, label]) => new Option(label, v)));
    model.value = keep !== undefined && [...model.options].some((o) => o.value === keep) ? keep : agentSettings[provider.value].model;
  };
  const loadSettings = async () => {
    try {
      const r = await fetch('/settings', { headers: { 'X-3DI-Token': token } });
      if (r.ok) agentSettings = (await r.json()).settings.agents;
    } catch {}
    fillModels(model.value);
  };
  window.addEventListener('3di-settings', loadSettings);
  try { fillModels(JSON.parse(localStorage.getItem(STORE) || '{}').model ?? ''); } catch { fillModels(); }
  const save = () => { try { localStorage.setItem(STORE, JSON.stringify({ provider: provider.value, model: model.value, custom: custom.value })); } catch {} };
  provider.onchange = () => { fillModels(); save(); showInfo(); };
  model.onchange = save;
  custom.onchange = save;

  const api = async (path, body) => {
    const r = await fetch(`/agent/${path}`, { method: body ? 'POST' : 'GET', headers: { 'X-3DI-Token': token, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error ?? `erro ${r.status}`);
    return j;
  };

  const showInfo = () => {
    if (!status) { info.textContent = 'Agentes indisponíveis: abra pelo app 3DI ou por npm run dev (o servidor simples não roda agentes).'; return; }
    const a = status.agents[provider.value];
    info.textContent = a.available
      ? `${a.version} · trabalha em ${status.cwd}${status.mcp ? '' : ' · sem MCP: o agente não vê a cena'}`
      : `${provider.value === 'claude' ? 'Claude Code' : 'Codex'} não encontrado: instale o CLI e faça login no terminal.`;
  };
  const setBusy = (on) => {
    busy = on;
    stopBtn.hidden = !on;
    send.disabled = on || !status;
    state.textContent = on ? 'trabalhando…' : '';
  };
  const scroll = () => { log.scrollTop = log.scrollHeight; };
  const add = (cls, text) => {
    const el = document.createElement('div');
    el.className = `msg ${cls}`;
    el.textContent = text;
    log.append(el);
    scroll();
    return el;
  };
  const tools = new Map();
  const toolLabel = (name, input) => {
    const arg = input?.view ?? input?.topic ?? input?.command ?? input?.path ?? input?.file_path ?? '';
    return `🔧 ${name}${arg ? ` · ${String(arg).slice(0, 60)}` : ''}`;
  };

  const handle = (e) => {
    switch (e.kind) {
      case 'history': log.replaceChildren(); live = null; tools.clear(); for (const x of e.events) handle(x); break;
      case 'reset': log.replaceChildren(); live = null; tools.clear(); break;
      case 'user': add('user', e.text); break;
      case 'start': setBusy(true); break;
      case 'text':
        if (e.delta) { live ??= add('assistant', ''); live.textContent += e.delta; scroll(); }
        else if (e.final) { if (live) live.textContent = e.final; else add('assistant', e.final); live = null; }
        break;
      case 'tool': { live = null; const el = add('tool', toolLabel(e.name, e.input)); tools.set(e.id, el); break; }
      case 'tool-result': {
        const el = tools.get(e.id);
        if (el) { el.classList.add(e.error ? 'fail' : 'ok'); el.title = e.text || (e.images ? `${e.images} imagem(ns)` : ''); }
        break;
      }
      case 'error': live = null; add('error', e.text); break;
      case 'done': live = null; setBusy(false); if (e.stopped) add('note', 'interrompido'); break;
      default: break;
    }
  };

  const connect = async () => {
    try {
      const r = await fetch('/bridge/session', { headers: { 'X-3DI-Client': 'ide' } });
      if (!r.ok) throw new Error();
      ({ token } = await r.json());
      status = await api('status');
    } catch { status = null; showInfo(); setBusy(false); setTimeout(connect, 8000); return; }
    showInfo();
    await loadSettings();
    setBusy(!!status.active?.busy);
    es?.close();
    es = new EventSource(`/agent/events?token=${encodeURIComponent(token)}`);
    es.onmessage = (ev) => handle(JSON.parse(ev.data));
    es.onerror = () => { es.close(); setTimeout(connect, 5000); };
  };

  const submit = async () => {
    const text = input.value.trim();
    if (!text || busy || !status) return;
    input.value = '';
    setBusy(true);
    try { await api('send', { text, provider: provider.value, model: custom.value.trim() || model.value || null }); }
    catch (e) { add('error', e.message); setBusy(false); }
  };
  $('form').onsubmit = (e) => { e.preventDefault(); submit(); };
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); submit(); } });
  stopBtn.onclick = () => api('stop', {}).catch(() => {});
  $('[data-a=reset]').onclick = () => api('reset', {}).catch((e) => add('error', e.message));
  connect();
  return { focus: () => input.focus() };
}
