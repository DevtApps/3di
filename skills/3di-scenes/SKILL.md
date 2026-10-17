---
name: 3di-scenes
description: Criar, editar, revisar e exportar cenas .3di pelo MCP do 3DI (modelagem 3D por código com funções genéricas). Use sempre que for modelar ou conferir algo no 3DI.
---

# Cenas 3DI

A documentação completa e sempre atual está no próprio servidor MCP `3di`, dividida em rotas.
Não use conhecimento de memória sobre a linguagem: leia as rotas.

1. `get_documentation(topic="inicio")`: o que é possível e qual rota ler para cada tarefa
   (fundamentos, formas, combinar, deformar, materiais, organico, hard-surface, cenarios,
   animacao, exportar, referencia-visual, revisao, desempenho, ferramentas, exemplos).
2. `describe_language`: todas as assinaturas atuais.
3. Fluxo: `get_script` → escrever → `check_script` → `set_script` → `screenshot(view="grid")`
   → rota `revisao` → `check_glb` se for exportar → `save_script` / `export_glb` quando pedido.
4. Para copiar uma imagem: rota `referencia-visual` (`set_reference`, `compare_reference`).

Regras: só funções genéricas da linguagem; objetos específicos são `def` no script. Metros, y para cima,
+z à frente. Formas são imutáveis (guarde o retorno). Termine com `show(...)`.
Não declare pronto sem conferir as imagens (e a malha, se houver GLB).
