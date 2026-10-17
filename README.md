# 3DI — Engine 3D para VS Code

Crie cenas 3D com código `.3di`, um subconjunto de Python. A engine gera SDF/GLSL
para o preview WebGL2 e malhas GLB para exportação. O desenvolvimento no navegador
continua disponível e utiliza a mesma engine.

## Usar a extensão

Abra um arquivo `.3di` para editar e visualizar a cena ao lado. Na paleta de comandos:

- **3DI: Novo projeto** — escolha a pasta de destino e um nome. Cria `main.3di`,
  `3di.json`, `scenes/`, `assets/`, `.agents/skills/3di-scenes/SKILL.md` e `AGENTS.md`.
  Pastas existentes não são sobrescritas.
- **3DI: Abrir preview 3D** — acompanha o documento ativo e atualiza ao editar.
- **3DI: Somente preview / Mostrar código** — alterna entre visualizar e editar.
- **3DI: Exportar GLB / Exportar PNG** — escolhe o arquivo de saída.
- **3DI: Abrir exemplo** — copia um exemplo para um documento novo, sem alterar a instalação.
- **3DI: Integrações MCP e skills** — mostra o endpoint ativo e configurações para copiar.

A linguagem inclui destaque, snippets, autocomplete, hover e diagnóstico no painel
**Problems**. Erros de execução preservam a última cena válida. A engine processa
scripts e exportações em workers para manter o editor responsivo.

## MCP HTTP

A extensão inicia o MCP HTTP em `127.0.0.1:8317`; o app desktop e o ambiente web usam
`127.0.0.1:8318`. A porta é fixa entre inicializações e releases. Se estiver ocupada,
o MCP informa erro e não migra silenciosamente para outra porta. No VS Code, altere
`3di.mcp.port` para escolher explicitamente outra porta. O serviço encerra com o app
ou Extension Host.

Use o endereço real da sua instância nos exemplos:

```sh
codex mcp add 3di --url http://127.0.0.1:8318/mcp
claude mcp add --transport http --scope user 3di http://127.0.0.1:8318/mcp
```

Não há caminhos de instalação ou projeto na configuração. As ferramentas operam sobre
o documento `.3di` ativo: `get_script`, `set_script`, `check_script`, `save_script`,
`screenshot`, `list_parts`, `frame`, `set_camera`, `set_time` e `export_glb`.
A exportação MCP é relativa à pasta da cena e não sobrescreve arquivos existentes.

Documentação: `get_documentation` com `topic` `language`, `best-practices`, `examples`
ou `skill`, e os recursos `3di://docs/<topic>`. A skill gerada em projetos novos fica
em `.agents/skills`; para Claude Code, copie-a para `.claude/skills/3di-scenes/SKILL.md`.

## Desenvolvimento

```sh
npm install
npm run dev                 # ambiente web, http://localhost:8317
npm run typecheck
npm run build               # bundles da extensão e do preview
npm test
npm run package             # out/3di-engine.vsix
code --install-extension out/3di-engine.vsix --force
```

O ambiente web original permanece independente do VS Code. A engine em `src/` é
compartilhada. A interface da extensão e o serviço FastMCP ficam em `extension/`.
No navegador, os comandos legados de `tools/` continuam disponíveis para desenvolvimento.

Leia a [referência da linguagem](docs/language.md), as [boas práticas](docs/best-practices.md)
e os [exemplos](docs/examples.md).
