---
name: 3di-geometry-review
description: Revisar alinhamentos, apoios, encaixes, dimensões e posições em cenas .3di antes de finalizar, ou investigar peças deslocadas e interseções. Combina medidas pelo MCP e inspeção de múltiplas vistas.
---

# Revisar geometria e posições no 3DI

Leia a cena com `get_script`. Consulte a linguagem se houver dúvida sobre transformações.
A aprovação exige relações geométricas coerentes e revisão visual da versão atual;
`check_script` compilar sem erros não significa que a geometria está correta.

## 1. Estabelecer o que medir

Identifique suportes, peças apoiadas, aberturas, pares simétricos e encaixes críticos.
Para cada relação registre: peças, eixo, valor esperado e tolerância em metros.
Use tolerância compatível com escala e finalidade; por exemplo 0.002 m para um
encaixe rígido de arquitetura em metros, ajustada para peças menores. Não aumente
uma tolerância apenas para ocultar uma falha. Diferencie folga intencional, contato
e penetração estrutural prevista.

Nomeie as peças que serão medidas. `list_parts` e `check_script.parts` fornecem
caixas das partes nomeadas; se a peça estiver agregada/oculta, imprima suas medidas
no código de diagnóstico ou examine uma cópia temporária isolada com `check_script`.
Não publique a cena de diagnóstico em lugar da cena do usuário.

## 2. Conferir numericamente

Execute `check_script` e examine bbox, parts e logs, não apenas a ausência de erro.
Use `list_parts` para comparar a cena atualmente aplicada com a versão revisada.

- Apoio horizontal: `abs(peca.bottom - suporte.top - gap) <= eps`.
- Centro em x: `abs(a.x - b.x - deslocamento) <= eps`; análogo para y/z.
- Alinhamento de bordas: compare `left/right`, `top/bottom`, `front/back` conforme
  a intenção, e não centros quando as peças têm dimensões diferentes.
- Contenção retangular: limites da peça dentro dos limites do suporte, respeitando
  a margem planejada. Verifique x e z no apoio; dimensões positivas e finitas.
- Simetria: centros equidistantes do plano local e tamanhos iguais; tolerância
  explícita para variações intencionais.
- Repetições: primeiro e último elemento dentro das margens; espaçamento constante;
  detecte cópias duplicadas ou peças faltantes.
- Colisões: para cada eixo, calcule `min(maxA,maxB)-max(minA,minB)`. Intervalo
  negativo demonstra separação das caixas; sobreposição positiva em todos os eixos
  indica um candidato à colisão, não prova interseção da geometria real.

Caixas envolventes não certificam contato com telhados inclinados, arcos, recortes,
formas côncavas, grupos ou curvas. Nesses casos confira a geometria local (equação
ou medidas da superfície), a construção dos recortes e vistas aproximadas.
Para uma água plana `y = y0 + inclinacao * (x-x0)`, compare o encontro da peça com
a altura avaliada no x de contato, não com `telhado.top`.

### Diagnóstico executável na linguagem

O 3DI suporta `if` e `print`; não invente `assert`, imports, exceções ou bibliotecas.
Este exemplo roda em `check_script`. Reutilize a função para relações reais da cena:

```python
def verificar(nome, atual, esperado, eps=0.002):
    erro = abs(atual - esperado)
    if erro > eps:
        print(f"FALHA {nome}: atual={atual:.4f}, esperado={esperado:.4f}, erro={erro:.4f}")
    else:
        print(f"OK {nome}: erro={erro:.4f}")

piso = box(3, 0.2, 2).place(y=0).name("piso")
pilar = box(0.12, 2, 0.12).on(piso, x=1.2).name("pilar")
verificar("apoio pilar", pilar.bottom, piso.top)
verificar("offset pilar x", pilar.x - piso.x, 1.2)
show(piso, pilar)
```

As mensagens FALHA são diagnósticos do script, não erros do parser. Leia os logs e
resolva as falhas; não alegue que a engine tem detector automático de colisões.
Faça diagnóstico em `check_script` sem alterar o arquivo salvo quando possível.

## 3. Conferir visualmente a versão aplicada

Aplique a versão validada com `set_script` e obtenha `screenshot(view="grid")`.
Abra/examine a imagem retornada; receber os bytes não constitui revisão visual.

- Frente: níveis de portas/janelas, alinhamento de pilares, cumeeira e simetria.
- Lado: profundidade de encaixes, paredes, cobertura e continuidade dos degraus.
- Topo: recuos, esquadro, distribuição de peças, beirais e simetria no plano.
- Perspectiva: silhueta, apoios, proporções e encontros entre conjuntos.
- Trás e lado oposto: use `back`, `left` ou `right`; a grade não cobre todas as faces.
- Detalhes suspeitos: `screenshot(target="nome", view="front")`, vistas adicionais
  ou `set_camera` com posição/look adequados. Enquadre suporte e peça juntos para
  não perder a referência. A câmera é de perspectiva: aparente convergência de
  arestas não demonstra desalinhamento; confirme com medidas.

Para uma casa, confira encontros do telhado, chaminé atravessando a cobertura,
apoio dos pilares, frisos/caixilhos dos recortes, patamar e escada, guarda-corpo e
fundação. Não conclua que um problema existe apenas a partir de uma vista ocluída.

Em animação, confira repouso e instantes críticos de contato/extremos, incluindo
pontos entre extremos quando houver risco. Registre os tempos efetivamente vistos.

## 4. Corrigir e fechar a revisão

Corrija parâmetros e relações de origem, não offsets acumulados para compensar um
erro. Recompile e repita as medidas e vistas afetadas. Uma alteração posterior a
uma captura invalida a aprovação das regiões alteradas.

Antes de finalizar, apresente um resumo curto com relações conferidas, maior erro
ou folga medidos e tolerância relevante, vistas examinadas e pendências. Não invente
valores ou resultados. Se falhar apoio/alinhamento obrigatório, corrija antes da
entrega; se depender de decisão do usuário, descreva a pendência sem declarar aprovado.
Se o preview estiver indisponível, diga "validação numérica realizada; revisão visual
pendente". Se houve exportação, confira a malha no destino/formato solicitado;
não extrapole uma revisão do preview para a malha exportada.
