// Lado do navegador da ponte com o servidor MCP (src/services/mcp.ts): recebe comandos por SSE,
// executa na IDE e responde por POST. Sem o servidor MCP (ex: scripts/serve.py), não faz nada.

export function connectBridge(api, onState = () => {}) {
  if (typeof EventSource === 'undefined') return;
  let es, token;
  const open = async () => {
    try {
      const response = await fetch('/bridge/session', { headers: { 'X-3DI-Client': 'ide' } });
      if (!response.ok) throw new Error('ponte indisponível');
      ({ token } = await response.json());
    } catch { onState(false); setTimeout(open, 5000); return; }
    es = new EventSource(`/bridge/events?token=${encodeURIComponent(token)}`);
    es.onopen = () => onState(true);
    es.onerror = () => {
      onState(false);
      // servidor sem ponte (404) ou caiu: tenta de novo mais tarde
      es.close();
      setTimeout(open, 5000);
    };
    es.onmessage = async (ev) => {
      const { id, cmd, args } = JSON.parse(ev.data);
      let reply;
      try {
        if (cmd === 'ping') reply = { id, ok: true, result: 'pong' };
        else if (!Object.hasOwn(api, cmd) || typeof api[cmd] !== 'function') throw new Error(`comando desconhecido: ${cmd}`);
        else reply = { id, ok: true, result: await api[cmd](args ?? {}) };
      } catch (e) {
        reply = { id, ok: false, error: e.message ?? String(e) };
      }
      fetch('/bridge/reply', { method: 'POST', headers: { 'X-3DI-Token': token }, body: JSON.stringify(reply) }).catch(() => {});
    };
  };
  open();
}
