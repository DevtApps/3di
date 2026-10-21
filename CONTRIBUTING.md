# Contribuir com o 3DI

Use Node.js 22.12 ou superior e instale as dependências com `npm ci`.
Inicie o editor com `npm run dev` ou o app com `npm run app`.

A engine e a linguagem ficam em `src/`, a interface em `src/ide/` e os serviços
compartilhados em `src/services/`. Integrações específicas do desktop ficam em
`apps/desktop/`. Comandos de desenvolvimento ficam em `scripts/`.

Antes de enviar uma alteração, execute:

```sh
npm run typecheck
npm test
```

Para alterações no app, execute também `npm run desktop:smoke`. Para mudanças visuais
ou de geometria, renderize uma cena representativa com `scripts/render.mjs` e examine
as imagens. Atualize as rotas em `docs/rotas/` e a referência `docs/language.md` quando
mudar a linguagem ou o comportamento das ferramentas MCP.

Não versione dependências, builds, instaladores ou exportações locais. `build/`
concentra todas as saídas de compilação e empacotamento; `npm run clean` remove essa
pasta. Preserve cenas e arquivos criados pelo usuário.
