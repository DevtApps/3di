// Falas no preview: quando a cena tem say(), pede ao servidor do 3DI as falas (geradas pelo
// Qwen3-TTS, em cache) e as toca em sincronia com a timeline. Devolve o roteiro reagendado pela
// duração real das falas, para as legendas baterem com o áudio (como no vídeo).
// Voz escolhida no seletor (vale para o preview e o vídeo): { provider, speaker } ou null = a do roteiro
export function voiceOverride() {
  try { return JSON.parse(localStorage.getItem('3di.voiceOverride') || 'null'); } catch { return null; }
}

export function createPreviewAudio({ onScript, onStatus }) {
  let token = null, clips = [], players = new Map(), wanted = '', muted = false, lastT = 0, lastPlaying = false;

  const session = async () => {
    if (token) return token;
    const r = await fetch('/bridge/session', { headers: { 'X-3DI-Client': 'ide' } });
    if (!r.ok) throw new Error('sem servidor do 3DI');
    ({ token } = await r.json());
    return token;
  };
  const stopAll = () => { for (const a of players.values()) { a.pause(); } };
  // progresso da geração (eventos do servidor): carregando o modelo, depois fala x de n
  let es = null, generating = false;
  const listen = () => {
    if (es) return;
    es = new EventSource(`/video/events?token=${encodeURIComponent(token)}`);
    es.onmessage = (ev) => {
      const e = JSON.parse(ev.data);
      if (e.kind !== 'speech-progress' || !generating) return;
      onStatus(e.stage === 'model' ? 'carregando o modelo de voz…' : `gerando fala ${Math.min(e.done + 1, e.total)} de ${e.total}…`,
        { busy: true, progress: e.stage === 'model' ? null : e.done / e.total });
    };
    es.onerror = () => { es.close(); es = null; };
  };

  return {
    // chamado a cada compilação: gera (ou reaproveita) as falas do roteiro
    async setScene(scene) {
      const lines = (scene?.script ?? []).filter((l) => l.speak);
      const override = voiceOverride();
      const key = JSON.stringify([lines.map((l) => [l.text, l.voice, l.style, l.start]), scene?.voices, override]);
      if (key === wanted) return;
      wanted = key;
      stopAll();
      clips = [];
      players = new Map();
      if (!lines.length) { onStatus(''); return; }
      try {
        const status = await (await fetch('/video/status', { headers: { 'X-3DI-Token': await session() } })).json();
        // cada fala usa o provedor da sua voice() ou o padrão das configurações
        const usesEleven = override ? override.provider === 'elevenlabs' : status.provider === 'elevenlabs' || Object.values(scene.voices ?? {}).some((v) => v.provider === 'elevenlabs');
        const usesQwen = override ? override.provider === 'qwen' : status.provider !== 'elevenlabs' || Object.values(scene.voices ?? {}).some((v) => v.provider === 'qwen');
        if (usesQwen && !status.tts?.installed && !usesEleven) { onStatus('falas sem voz: instale as vozes ou configure o ElevenLabs (⚙)'); return; }
        if (usesEleven && !status.elevenKey) { onStatus('falas sem voz: falta a chave do ElevenLabs (⚙)'); return; }
        listen();
        generating = true;
        onStatus('preparando as falas…', { busy: true, progress: null });
        const r = await fetch('/video/speech', { method: 'POST', headers: { 'X-3DI-Token': token, 'Content-Type': 'application/json' }, body: JSON.stringify({ script: scene.script, voices: scene.voices, override }) });
        const j = await r.json();
        generating = false;
        if (key !== wanted) return; // a cena mudou enquanto gerava
        if (!r.ok) throw new Error(j.error);
        clips = j.clips;
        for (const c of clips) {
          const a = new Audio(`/video/clip?k=${c.key}&token=${encodeURIComponent(token)}`);
          a.preload = 'auto';
          players.set(c, a);
        }
        onScript(j.script);
        onStatus('');
      } catch (e) { generating = false; onStatus(`falas: ${e.message}`); }
    },
    // chamado a cada quadro do preview com o tempo e se está tocando
    update(t, playing) {
      const jumped = Math.abs(t - lastT) > 0.25 || t < lastT;
      if (!playing || muted) { if (lastPlaying || muted) stopAll(); }
      else {
        for (const [c, a] of players) {
          const inside = t >= c.start && t < c.start + c.seconds;
          if (inside && (a.paused || jumped)) {
            a.currentTime = Math.max(0, t - c.start);
            if (a.paused) a.play().catch(() => {});
          } else if (!inside && !a.paused) a.pause();
        }
      }
      lastT = t;
      lastPlaying = playing;
    },
    setMuted(on) { muted = on; if (on) stopAll(); },
    // troca a voz de todas as falas e gera de novo (o roteiro original volta pelo scene)
    setVoice(o, scene) {
      try { o ? localStorage.setItem('3di.voiceOverride', JSON.stringify(o)) : localStorage.removeItem('3di.voiceOverride'); } catch {}
      wanted = '';
      return this.setScene(scene);
    },
    // opções do seletor de voz
    async voiceOptions() {
      const r = await fetch('/video/voice-options', { method: 'POST', headers: { 'X-3DI-Token': await session(), 'Content-Type': 'application/json' }, body: '{}' });
      return r.ok ? (await r.json()).options : [];
    },
  };
}
