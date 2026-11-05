// Falas no preview: quando a cena tem say(), pede ao servidor do 3DI as falas (geradas pelo
// Qwen3-TTS, em cache) e as toca em sincronia com a timeline. Devolve o roteiro reagendado pela
// duração real das falas, para as legendas baterem com o áudio (como no vídeo).
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

  return {
    // chamado a cada compilação: gera (ou reaproveita) as falas do roteiro
    async setScene(scene) {
      const lines = (scene?.script ?? []).filter((l) => l.speak);
      const key = JSON.stringify([lines.map((l) => [l.text, l.voice, l.style, l.start]), scene?.voices]);
      if (key === wanted) return;
      wanted = key;
      stopAll();
      clips = [];
      players = new Map();
      if (!lines.length) { onStatus(''); return; }
      try {
        const status = await (await fetch('/video/status', { headers: { 'X-3DI-Token': await session() } })).json();
        if (!status.tts?.installed) { onStatus('falas sem voz: instale as vozes nas configurações (⚙)'); return; }
        onStatus('gerando as falas…');
        const r = await fetch('/video/speech', { method: 'POST', headers: { 'X-3DI-Token': token, 'Content-Type': 'application/json' }, body: JSON.stringify({ script: scene.script, voices: scene.voices }) });
        const j = await r.json();
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
      } catch (e) { onStatus(`falas: ${e.message}`); }
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
  };
}
