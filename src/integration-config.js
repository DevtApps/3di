// HTTP-only settings: installation and workspace paths never enter client configuration.
export function integrationConfig(endpoint) {
  const url = new URL(endpoint);
  if (url.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) || url.pathname !== '/mcp' || url.username || url.password || url.search || url.hash) {
    throw new Error('Use o endpoint MCP HTTP local exibido pelo 3DI.');
  }
  const value = url.href;
  return {
    codexCommand: `codex mcp add 3di --url ${value}`,
    claudeCommand: `claude mcp add --transport http --scope user 3di ${value}`,
    codex: `[mcp_servers.3di]\nurl = "${value}"\ntool_timeout_sec = 180\n`,
    claude: JSON.stringify({ mcpServers: { '3di': { type: 'http', url: value } } }, null, 2) + '\n',
  };
}
