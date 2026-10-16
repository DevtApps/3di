// Lado do navegador da ponte com o servidor MCP (tools/mcp.mjs): recebe comandos por SSE,
// executa na IDE e responde por POST. Sem o servidor MCP (ex: tools/serve.py), não faz nada.

export function connectBridge(api, onState = () => {}) {
  if (typeof EventSource === 'undefined') return;
  let es;
  const open = () => {
    es = new EventSource('/bridge/events');
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
        else if (!api[cmd]) throw new Error(`comando desconhecido: ${cmd}`);
        else reply = { id, ok: true, result: await api[cmd](args ?? {}) };
      } catch (e) {
        reply = { id, ok: false, error: e.message ?? String(e) };
      }
      fetch('/bridge/reply', { method: 'POST', body: JSON.stringify(reply) }).catch(() => {});
    };
  };
  open();
}
