---
name: 3di-scenes
description: Criar e editar cenas .3di com medidas, layout semântico, materiais e composição pelo MCP do 3DI. Use para modelagem no 3DI, incluindo casas e objetos compostos.
---

# Construir cenas 3DI

## Preparar

Leia `get_script` antes de alterar uma cena existente. Consulte `get_documentation`
com `topic="language"` e `topic="best-practices"`; `describe_language` resume a API.
As mesmas referências são recursos `threedi://docs/language` e
`threedi://docs/best-practices`. Não invente métodos ou sintaxe Python não suportada.

A skill complementar `3di-geometry-review` descreve a revisão antes da entrega.
Leia pelo recurso `threedi://skills/3di-geometry-review` ou por `get_skill` com esse
nome; não exige instalação. Para instalar as duas no workspace do agente, use
`install_skills` com o caminho absoluto real do workspace e `target="both"`.
Não deduza a pasta do projeto a partir do caminho de instalação do app.

## Arquivos e workspace

Use `get_workspace` antes de gerenciar arquivos. Se não houver pasta ativa, use
`set_workspace` somente com a pasta real do projeto pedido pelo usuário, ou peça
para escolher no app. `list_files` e `read_scene` inspecionam sem trocar a cena.
`create_scene` valida e cria; `open_scene` abre; `move_scene` move/renomeia;
`delete_scene` envia à lixeira. Caminhos são relativos, terminam em `.3di` e não
atravessam links. Não escolha a instalação do app como projeto por conveniência.
Para editar e salvar, use `open_scene`, `set_script`, `save_script`. Respeite recusas
por alterações não salvas ou destino existente; não tente contorná-las apagando
arquivos. Exclusões devem fazer parte do pedido, nunca servir para esconder falhas.

## Definir medidas e relações

- Unidades em metros, y para cima, +z para frente. Primitivas nascem centradas.
- Escolha parâmetros principais antes dos detalhes: largura, altura, profundidade,
  espessuras e nível do piso. Derive dimensões dependentes desses parâmetros.
- Defina referências locais por conjunto: corpo, base, fachada, cobertura. Posicione
  peças no referencial do conjunto e mova o grupo pronto uma única vez.
- Registre no código as relações esperadas: qual superfície apoia qual peça,
  alinhamento de centros/bordas, afastamentos e interpenetrações intencionais.
- Use nomes distintos nas peças que precisam de inspeção: `piso_varanda`,
  `pilar_esquerdo`, `janela_frente`, `telhado`, `chamine`. Uma única caixa da casa
  inteira não permite medir os encontros entre peças.

## Posicionar sem acumular erros

`place(x,y,z)` posiciona o centro da BASE; `at` e `move` DESLOCAM a forma.
Não trate `at` como posicionamento absoluto de uma peça já deslocada.
`on(alvo,x,z,gap)` apoia no topo e usa x/z relativos ao centro do alvo.
`beside` alinha bases e encosta caixas envolventes; não alinha automaticamente
uma abertura ou superfície inclinada. Confira a assinatura antes de chamar.

Formas são imutáveis: atribua o retorno. Rotacione e escale a peça antes de calcular
seu apoio final; rotações mudam a caixa envolvente. `mirror` usa o plano global de
origem do eixo: modele o par centrado na origem local antes de mover o conjunto.
`repeat` é centrado; derive quantidade, espaçamento e margens para caber no suporte.

Use propriedades reais `top`, `bottom`, `left`, `right`, `front`, `back`, `width`,
`height`, `depth`, `center`, `x`, `y`, `z`. Evite repetir números independentes para
bordas que precisam coincidir. Após modificar a base, recalcule seus dependentes.

## Para arquitetura e peças encaixadas

- Parede, recorte e caixilho devem compartilhar centro, nível e dimensão de abertura.
  O cortador deve atravessar toda a espessura com pequena margem; mantenha vergas
  e pilares laterais. Material transparente não substitui um recorte.
- Posicione as janelas de uma mesma fileira pelo mesmo peitoril e altura. Portas
  se referenciam ao piso acabado. Confira frontais e laterais separadamente.
- Pilares da varanda se apoiam no piso e alcançam a face inferior da cobertura,
  respeitando a inclinação. A caixa do telhado não descreve a altura de cada água.
- Derive a cobertura da largura, profundidade, beiral e inclinação. Verifique cumeeira,
  encontro com paredes, pontas expostas e espessura visível sob o beiral.
- A chaminé atravessa a cobertura até o corpo; não a apoie só no topo da caixa do
  telhado. Avalie a altura da superfície inclinada na posição da chaminé.
- Degraus compartilham espelho e piso derivados do desnível e percurso. Confira o
  encontro do primeiro com o terreno e do último com o patamar.
- Evite faces coplanares e sobreposições duplicadas; use folga ou penetração pequena
  e deliberada nas junções. Não esconda uma lacuna escolhendo uma câmera favorável.

## Construir e revisar

Construa primeiro os volumes e apoios; confira-os antes de acrescentar frisos,
texturas, ferragens e vegetação. Compile com `check_script`, examine `bbox`,
`parts` e `logs`, corrija erros e só então aplique com `set_script`.
Leia o status e examine `screenshot(view="grid")`. Use vistas individuais e `target`
para encontros encobertos. Siga a revisão de geometria antes de declarar finalizado.
Se não houver preview conectado, continue as verificações numéricas e informe a
revisão visual pendente. Reutilize a janela existente.

Para animação GLB, use ossos e `.bind()`; `time` fora dos ossos exporta em t=0.
Salve/exporte quando fizer parte do pedido. Confira a malha exportada: o preview
SDF não prova que detalhes finos ou texturas sobreviveram à conversão.
