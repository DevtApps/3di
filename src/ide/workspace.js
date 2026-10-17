import { integrationConfig } from '../integration-config.js';

export function setupWorkspace() {
  const $ = (id) => document.getElementById(id);
  const app = $('app');
  let activeGuide = 'codex';
  let previewOnly = false;
  try { previewOnly = localStorage.getItem('3di.previewOnly') === 'true'; } catch {}
  const applyPreview = () => {
    app.classList.toggle('preview-only', previewOnly);
    $('btnToggleCode').textContent = previewOnly ? 'Mostrar código' : 'Ocultar código';
    $('btnToggleCode').setAttribute('aria-expanded', String(!previewOnly));
  };
  const selectTab = (tab) => {
    const integration = tab === 'integrations';
    $('codePanel').hidden = integration;
    $('integrations').hidden = !integration;
    for (const [id, selected] of [['tabCode', !integration], ['tabIntegrations', integration]]) {
      $(id).setAttribute('aria-selected', String(selected));
      $(id).tabIndex = selected ? 0 : -1;
    }
  };
  $('btnToggleCode').onclick = () => {
    previewOnly = !previewOnly;
    if (!previewOnly) selectTab('code');
    applyPreview();
    try { localStorage.setItem('3di.previewOnly', String(previewOnly)); } catch {}
  };
  $('tabCode').onclick = () => selectTab('code');
  $('tabIntegrations').onclick = () => selectTab('integrations');
  $('btnIntegrations').onclick = () => {
    previewOnly = false;
    applyPreview();
    selectTab('integrations');
    $('tabIntegrations').focus();
    try { localStorage.setItem('3di.previewOnly', 'false'); } catch {}
  };
  document.querySelector('.workspace-tabs').addEventListener('keydown', (event) => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const integration = event.key === 'End' || (event.key !== 'Home' && $('integrations').hidden);
    selectTab(integration ? 'integrations' : 'code');
    $(integration ? 'tabIntegrations' : 'tabCode').focus();
  });
  applyPreview();

  let endpoint = 'http://127.0.0.1:8318/mcp';
  $('mcpEndpoint').textContent = endpoint;
  const feedback = (message) => { $('integrationFeedback').textContent = message; };
  const download = (text, name) => {
    const href = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }));
    const a = Object.assign(document.createElement('a'), { href, download: name });
    a.click();
    setTimeout(() => URL.revokeObjectURL(href), 1000);
    feedback(`Download preparado: ${name}`);
  };
  const card = (title, description, code, filename) => {
    const section = document.createElement('section');
    section.className = 'guide-card';
    const h = document.createElement('h3'); h.textContent = title;
    const p = document.createElement('p'); p.textContent = description;
    section.append(h, p);
    if (code !== undefined) {
      const pre = document.createElement('pre'); pre.textContent = code;
      const actions = document.createElement('div'); actions.className = 'guide-actions';
      const copy = document.createElement('button'); copy.textContent = 'Copiar';
      copy.setAttribute('aria-label', `Copiar ${title}`);
      copy.onclick = async () => {
        try { await navigator.clipboard.writeText(code); feedback(`${title} copiado.`); }
        catch { feedback('Não foi possível acessar a área de transferência. Selecione o texto para copiar.'); }
      };
      actions.append(copy);
      if (filename) {
        const save = document.createElement('button'); save.textContent = 'Baixar';
        save.setAttribute('aria-label', `Baixar ${title}`);
        save.onclick = () => download(code, filename);
        actions.append(save);
      }
      section.append(pre, actions);
    }
    $('integrationContent').append(section);
    return section;
  };
  const link = (parent, label, href) => {
    const a = document.createElement('a'); a.textContent = label; a.href = href;
    a.target = '_blank'; a.rel = 'noopener'; parent.append(a);
  };
  let skill = null;
  let geometrySkill = null;
  const render = () => {
    $('integrationContent').replaceChildren();
    feedback('');
    document.querySelector('.integration-settings').hidden = activeGuide === 'skills' || activeGuide === 'docs';
    if (activeGuide === 'docs') {
      for (const [title, description, uri, href] of [
        ['Linguagem 3DI', 'Sintaxe, primitivas, materiais, animação e exportação.', 'threedi://docs/language', '/docs/language.md'],
        ['Boas práticas', 'Layout, desempenho e revisão visual das cenas.', 'threedi://docs/best-practices', '/docs/best-practices.md'],
        ['Exemplos', 'Cenas prontas e um fluxo de trabalho para agentes.', 'threedi://docs/examples', '/docs/examples.md'],
      ]) {
        const section = card(title, description, uri);
        link(section, 'Abrir documentação', href);
      }
      card('Consultar pelo MCP', 'Peça ao agente para ler esses recursos MCP ou chamar get_documentation com topic language, best-practices ou examples. A documentação pode ser consultada sem o editor aberto.');
      return;
    }
    if (activeGuide === 'skills') {
      card('Skills pelo MCP', 'Use list_skills para descobrir e get_skill para ler 3di-scenes e 3di-geometry-review. O agente pode seguir as instruções diretamente nesta sessão, sem instalar arquivos.', 'threedi://skills/3di-scenes\nthreedi://skills/3di-geometry-review');
      card('Instalar pelo agente', 'Peça ao agente para executar install_skills com o caminho absoluto do workspace dele. target both prepara Codex e Claude Code; arquivos existentes diferentes são preservados.', 'install_skills({workspace: "/caminho/absoluto/do/seu-workspace", target: "both"})');
      card('Codex · instalação no projeto', 'Crie esta pasta no projeto em que você usa o agente e salve o arquivo baixado como SKILL.md.', '.agents/skills/3di-scenes/SKILL.md');
      card('Claude Code · instalação no projeto', 'Salve o mesmo arquivo neste caminho do projeto em que você inicia o Claude Code.', '.claude/skills/3di-scenes/SKILL.md');
      if (geometrySkill) card('Revisão geométrica', 'Salve em 3di-geometry-review/SKILL.md dentro do diretório de skills do cliente. Invoque $3di-geometry-review ou /3di-geometry-review.', geometrySkill, '3di-geometry-review-SKILL.md');
      if (skill) card('Construção de cenas', 'Depois de instalar, invoque $3di-scenes no Codex ou /3di-scenes no Claude Code.', skill, 'SKILL.md');
      else card('Skill indisponível', 'Não foi possível carregar a skill. Reabra esta seção para tentar novamente.');
      const section = card('Referências oficiais', 'Confira os diretórios e a descoberta de skills do seu cliente.');
      link(section, 'Skills no Codex', 'https://developers.openai.com/codex/skills/');
      section.append(' · '); link(section, 'Skills no Claude Code', 'https://code.claude.com/docs/en/skills');
      return;
    }
    let config;
    try { config = integrationConfig(endpoint); }
    catch (e) { card('Endpoint indisponível', e.message); return; }
    const codex = activeGuide === 'codex';
    card('1. Conectar o agente', 'Mantenha o app 3DI ou o servidor de desenvolvimento em execução. Use o endpoint HTTP mostrado acima para controlar esta cena.', codex ? config.codexCommand : config.claudeCommand);
    card('Alternativa · arquivo de configuração', codex
      ? 'Adicione esta seção ao ~/.codex/config.toml. O download contém apenas a seção do 3DI; preserve as outras configurações.'
      : 'Mescle a entrada 3di em mcpServers no .mcp.json do seu projeto. Preserve os outros servidores. Aprove o servidor no Claude Code quando solicitado.',
    codex ? config.codex : config.claude, codex ? '3di-mcp.toml' : '3di-mcp.json');
    card('2. Verificar a conexão', 'Reinicie a sessão do agente após configurar. Use /mcp no cliente para conferir se o servidor 3di está disponível.', codex ? 'codex mcp list' : 'claude mcp list');
    card('3. Criar e revisar', 'Mantenha este preview aberto na mesma porta. O indicador “Ponte ativa” confirma a conexão do editor ao servidor local; o estado do cliente externo é conferido no próprio cliente.', 'Consulte a documentação e as boas práticas do 3DI. Leia a cena atual com get_script, valide alterações com check_script, aplique com set_script e confira screenshot com view="grid".');
    const section = card('Documentação oficial', 'Consulte as opções de configuração do cliente.');
    link(section, codex ? 'MCP no Codex' : 'MCP no Claude Code', codex ? 'https://developers.openai.com/codex/mcp/' : 'https://code.claude.com/docs/en/mcp');
  };
  document.querySelectorAll('[data-guide]').forEach((button) => {
    button.onclick = async () => {
      activeGuide = button.dataset.guide;
      document.querySelectorAll('[data-guide]').forEach((b) => b.setAttribute('aria-pressed', String(b === button)));
      if (activeGuide === 'skills' && !skill) {
        try {
          const r = await fetch('/skills/3di-scenes/SKILL.md');
          if (r.ok) skill = await r.text();
          const geometry = await fetch('/skills/3di-geometry-review/SKILL.md');
          if (geometry.ok) geometrySkill = await geometry.text();
        } catch {}
      }
      render();
    };
  });
  render();
  fetch('/integration/config').then((r) => r.json()).then((config) => {
    if (config.endpoint) { endpoint = config.endpoint; $('mcpEndpoint').textContent = endpoint; render(); }
  }).catch(() => {});
}
