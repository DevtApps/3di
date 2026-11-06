// Botão Vídeo: renderiza a cena (timeline, chaves, câmera e roteiro) num MP4 com falas e legendas.
// Os quadros são desenhados aqui, pela própria vista; o servidor do 3DI (src/services/video.mjs)
// codifica com o ffmpeg do pacote, gera as falas e junta tudo na pasta out/ do projeto.
import { hydrateIcons } from './icons.js';

export function createVideoDialog({ button, tdi, openSettings = () => {} }) {
  const box = document.createElement('div');
  box.id = 'videoDialog';
  box.hidden = true;
  box.className = 'modal';
  box.setAttribute('role', 'dialog');
  box.setAttribute('aria-modal', 'true');
  box.setAttribute('aria-labelledby', 'videoTitle');
  box.innerHTML = `<div class="modal-card">
    <div class="modal-head">
      <div><h3 id="videoTitle">Exportar vídeo</h3><p>MP4 com timeline, falas, legendas e textos</p></div>
      <span class="spacer"></span>
      <button data-a="close" class="ghost icon-btn" title="Fechar (Esc)" aria-label="Fechar"><i data-icon="x"></i></button>
    </div>
    <div class="modal-body">
      <label class="field">Nome do arquivo <input data-k="name" value="video"></label>
      <div class="grid-2">
        <label class="field">Tamanho <select data-k="size"><option value="640x360">640 × 360</option><option value="1280x720" selected>1280 × 720 (HD)</option><option value="1920x1080">1920 × 1080 (Full HD)</option><option value="1080x1920">1080 × 1920 (vertical)</option></select></label>
        <label class="field">Quadros por segundo <input data-k="fps" type="number" min="1" max="120"></label>
      </div>
      <label class="field">Legendas <select data-k="subs"><option value="soft">Faixa embutida (liga/desliga no player)</option><option value="burn">Gravadas na imagem</option><option value="off">Sem legendas</option></select></label>
      <div class="card">
        <label class="check"><input data-k="audio" type="checkbox" checked> Falas com voz</label>
        <label class="field">Voz <select data-k="voice"><option value="">Voz do roteiro</option></select></label>
        <p class="tts hint"></p>
        <div class="row"><button data-a="settings" class="sm" title="Vozes e modelo do TTS"><i data-icon="audio-lines"></i>Gerenciar vozes</button><button data-a="install" class="sm" hidden><i data-icon="download"></i>Instalar vozes</button></div>
      </div>
      <div class="progress"><div></div></div>
      <pre class="log"></pre>
    </div>
    <div class="modal-foot">
      <span class="status">Salvo na pasta Downloads</span>
      <button data-a="close">Fechar</button>
      <button data-a="render" class="primary"><i data-icon="clapperboard"></i>Renderizar</button>
    </div>
  </div>`;
  hydrateIcons(box);
  document.body.append(box);
  const $ = (s) => box.querySelector(s);
  const logEl = $('.log'), bar = $('.progress div'), tts = $('.tts'), renderBtn = $('[data-a=render]'), installBtn = $('[data-a=install]');
  let token = null, status = null, running = false, cancel = false, es = null;

  const log = (text) => { logEl.textContent = `${logEl.textContent}${text}\n`.split('\n').slice(-12).join('\n'); logEl.scrollTop = logEl.scrollHeight; };
  const api = async (path, body, raw) => {
    const r = await fetch(`/video/${path}`, { method: body === undefined ? 'GET' : 'POST', headers: { 'X-3DI-Token': token, ...(raw ? { 'Content-Type': 'image/png' } : { 'Content-Type': 'application/json' }) }, body: raw ?? (body === undefined ? undefined : JSON.stringify(body)) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.error ?? `erro ${r.status}`);
    return j;
  };
  const refresh = async () => {
    try {
      if (!token) ({ token } = await (await fetch('/bridge/session', { headers: { 'X-3DI-Client': 'ide' } })).json());
      status = await api('status');
    } catch { status = null; }
    if (!status) {
      tts.textContent = 'Vídeo indisponível: abra pelo app 3DI ou por npm run dev.';
      renderBtn.disabled = true;
      return;
    }
    renderBtn.disabled = running;
    installBtn.hidden = status.tts.installed || status.installing;
    tts.textContent = status.tts.installed
      ? 'Vozes instaladas.'
      : status.installing ? 'Instalando as vozes…' : `Vozes não instaladas: o 3DI cria o ambiente em ${status.tts.dir} (alguns GB; precisa do python3-venv). Sem elas, o vídeo sai sem as falas.`;
    if (!es) {
      es = new EventSource(`/video/events?token=${encodeURIComponent(token)}`);
      es.onmessage = (ev) => {
        const e = JSON.parse(ev.data);
        if (e.kind === 'log') log(e.text);
        else if (e.kind === 'error') { log(`erro: ${e.text}`); refresh(); }
        else if (e.kind === 'tts-ready') { log('vozes prontas'); refresh(); }
      };
      es.onerror = () => { es.close(); es = null; };
    }
  };

  const b64ToBytes = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const render = async () => {
    const info = tdi.info();
    if (!(info.duration > 0)) { log('a cena não tem duração: use timeline(segundos), keys(...) ou say(...)'); return; }
    const [w, h] = $('[data-k=size]').value.split('x').map((v) => Number(v) & ~1);
    const fps = Number($('[data-k=fps]').value) || info.fps || 30;
    const subs = $('[data-k=subs]').value, audio = $('[data-k=audio]').checked;
    running = true; cancel = false;
    renderBtn.disabled = true;
    $('[data-a=close]').textContent = 'Cancelar';
    logEl.textContent = '';
    let id = null;
    try {
      const job = await api('start', { name: $('[data-k=name]').value, fps });
      id = job.id;
      const n = Math.max(1, Math.round(info.duration * fps));
      const t0 = performance.now();
      for (let i = 0; i < n; i++) {
        if (cancel) throw new Error('cancelado');
        const png = await tdi.frame({ t: i / fps, width: w, height: h });
        await api(`frame?id=${id}`, null, b64ToBytes(png));
        bar.style.width = `${(70 * (i + 1)) / n}%`;
        if (i % fps === 0) tts.textContent = `quadro ${i + 1}/${n} · ${((i + 1) / ((performance.now() - t0) / 1000)).toFixed(0)} q/s`;
      }
      tdi.at(0);
      log(`${n} quadros desenhados`);
      const vsel = $('[data-k=voice]').value;
      const r = await api(`finish?id=${id}`, { script: info.script, voices: info.voices, from: 0, to: info.duration, subs: subs !== 'off', burn: subs === 'burn', audio, override: vsel ? JSON.parse(vsel) : null });
      bar.style.width = '100%';
      log(`pronto: ${r.output}${r.falas ? ` (${r.falas} fala(s))` : ''}${r.srt ? `\nlegendas: ${r.srt}` : ''}`);
      tts.textContent = 'Vídeo gravado.';
    } catch (e) {
      log(`erro: ${e.message}`);
      if (id !== null) api(`cancel?id=${id}`, {}).catch(() => {});
      tdi.at(0);
    } finally {
      running = false;
      renderBtn.disabled = false;
      $('[data-a=close]').textContent = 'Fechar';
    }
  };

  box.addEventListener('click', (e) => {
    const a = e.target.dataset.a;
    if (a === 'render') render();
    else if (a === 'install') { installBtn.hidden = true; log('instalando as vozes…'); api('install-tts', {}).then(refresh, (err) => log(`erro: ${err.message}`)); }
    else if (a === 'close') { if (running) cancel = true; else box.hidden = true; }
    else if (a === 'settings') { box.hidden = true; openSettings(); }
  });
  button.onclick = () => {
    box.hidden = false;
    const info = tdi.info();
    $('[data-k=fps]').value = info.fps || 30;
    bar.style.width = '0';
    refresh();
    // mesma voz escolhida no preview
    (async () => {
      try {
        const opts = (await api('voice-options', {})).options;
        const cur = (() => { try { return localStorage.getItem('3di.voiceOverride'); } catch { return null; } })();
        const sel = $('[data-k=voice]');
        sel.replaceChildren(new Option('voz do roteiro', ''), ...opts.map((o) => new Option(o.label, JSON.stringify({ provider: o.provider, speaker: o.speaker }))));
        sel.value = cur ?? '';
      } catch {}
    })();
  };
}
