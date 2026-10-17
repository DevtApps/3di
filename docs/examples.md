# Exemplos e fluxo de trabalho

Os arquivos estão em `examples/` no projeto e também no seletor Exemplos da IDE.

| Arquivo | Recurso principal |
|---|---|
| mesa.3di | Layout semântico, apoio e medidas |
| basico.3di | Primitivas |
| materiais.3di | Materiais, texturas e deformação |
| organico.3di | União suave e twist |
| pinguim.3di | Personagem e simetria |
| castelo.3di | Booleanas e repetição |
| templo.3di | Arquitetura e repeat |
| vila.3di | Geração procedural |
| arvore.3di | Recursão e BVH |
| animacao.3di | Transformações com time |
| boneco.3di | Esqueleto, bind e exportação animada |
| grama.3di | Cinco tipos de grama (gramado, capim, espigas, trevo com flores, touceiras): lâminas curvas em `segment` com degradê |
| gramas.3di | Gerador `grass()`: os sete tipos de grama |
| gramas-estilos.3di | O mesmo gerador em lowpoly, stylized e realistic |
| plantas.3di | Gerador `plant()`: sete plantas nos três estilos |
| arvores.3di | Gerador `tree()`: oito tipos de árvore |
| arvores-estilos.3di | A mesma árvore em lowpoly, stylized e realistic |
| pessoas.3di | Gerador `person()`: cinco biotipos nos três estilos |
| pessoas-poses.3di | Poses e roupas do `person()` |
| veiculos.3di | Gerador `vehicle()`: dez tipos de veículo |
| veiculos-estilos.3di | O mesmo veículo em três estilos, com rodas girando |
| campo.3di | Campo estilizado denso em quatro paletas: lâminas achatadas em camadas de `repeat` recortadas por `&`, poucas primitivas |

## Cena inicial

```python
mesa = box(1.2, 0.05, 0.8).place(y=0.7).color("wood").name("mesa")
caneca = cylinder(0.045, 0.1).color("red").on(mesa, x=0.2).name("caneca")
show(plane(), mesa, caneca)
```

Valide com `check_script`, aplique com `set_script` e peça uma imagem com
`screenshot` usando `view="grid"`. O editor deve estar aberto na porta configurada
no servidor MCP para comandos de preview; a documentação e `check_script` funcionam sem ele.
