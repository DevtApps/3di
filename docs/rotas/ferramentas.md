# Ferramentas MCP

**Documentação:** `get_documentation(topic)` (rotas desta documentação), `describe_language` (todas as assinaturas).

**Script:** `check_script(code)` valida sem o editor (erros com linha, medidas, logs de `print`);
`get_script`; `set_script(code)` aplica e compila; `save_script`.

**Arquivos (app/extensão):** `get_workspace`, `set_workspace(path)`, `list_files`, `read_scene`, `create_scene`,
`open_scene`, `move_scene`, `delete_scene` (lixeira). Caminhos relativos ao workspace, terminando em `.3di`.

**Preview (editor aberto):** `screenshot(view, target, time)` (view: current, front, back, left, right, top,
perspective, grid); `set_camera(pos, look, fov)`; `frame(target, view)`; `list_parts`; `set_time(time, playing)`.

**Referência:** `set_reference(path, opacity, scale, x, y, side)`, `compare_reference()`.

**Exportar:** `export_glb(code, path, res)`, `check_glb(res, style, mode)`.
