# Plano: personagens no nível do KayKit Adventurers

Referência: [KayKit Adventurers](https://kaylousberg.itch.io/kaykit-adventurers) (CC0).

O pacote tem 5 personagens no plano grátis: cavaleiro, bárbaro, ladino, mago e arqueiro. Os planos
pagos trazem mais 3 personagens e mais de 25 armas e acessórios (espadas, escudos, arco, besta,
cajado, livro). O estilo é *low poly* estilizado e chibi: cabeça grande, mãos e pés grandes e
silhuetas limpas. Cada modelo usa uma única textura de degradê 1024², que pode cair para 128². Vem
com rig, animações básicas e partes removíveis (elmo, viseira, capuz) e sai em glTF/FBX.

## O que falta no 3DI hoje

| KayKit | 3DI hoje |
|---|---|
| Malha low poly limpa: poucas faces grandes, quinas vivas, chanfros intencionais | O `person()` monta tudo com SDF. A exportação (dual contouring + simplificação) dá superfícies "derretidas" e muitos triângulos. As facetas imitam o low poly, mas em grade, não pela forma. |
| Proporção chibi (cabeça ≈ 1/3 da altura) e anatomia simplificada, mas desenhada | Só há corpos realistas (`average`, `slim`, `child`...). |
| Armadura, capuz, ombreiras, cinto e bolsas que seguem o corpo | A roupa só muda a cor. Não há peças que encaixem no corpo. |
| Armas e acessórios presos à mão e às costas | Não há biblioteca de armas. As âncoras existem, mas o corpo não as declara. |
| Uma textura de degradê (paleta) compartilhada | Cor por vértice, ou um atlas assado por triângulo, que é grande e sem paleta. |
| Rig com pesos suaves e animações (andar, correr, atacar) | Partes rígidas, peso 1 por osso, e só poses fixas. |
| Triângulos na faixa de 1 a 3 mil por personagem | Cerca de 10 mil ou mais. |

## Proposta, em etapas

1. **Primitivas poligonais de verdade (malha direta low poly).** Novas formas que já nascem como
   poliedros:
   - `bevelbox` (caixa chanfrada), `hull(pontos)` (casco convexo), `loft` de seções com poucos lados,
     e esfera ou cilindro com `sides=` baixo.
   - No GLB elas saem exatas pela malha direta (`nativemesh`), sem amostragem. No shader são SDF de
     poliedro, para o preview bater com a exportação.
   - Essa é a base de tudo: dá as faces planas e as quinas do KayKit.
2. **Booleanas de malha simples.** União de peças sem fundir vértices, como fazem os artistas low poly
   com peças sobrepostas. A malha direta passa a aceitar `subtract` de caixas e chanfros. Isso cobre
   viseira, recortes e sulcos.
3. **Paleta de degradê.** `palette("kaykit")`: uma textura 128² com faixas de cor, e cada material
   aponta uma célula dela. A exportação gera um só PNG pequeno e UVs por face, no lugar do atlas por
   triângulo. A troca de paleta dá as variações de cor do pacote pago.
4. **Corpo chibi com âncoras.** `character(build="chibi")` com proporções de herói estilizado e
   âncoras declaradas (`mao_dir`, `mao_esq`, `costas`, `cabeca`, `cintura`, `ombro_*`) e ossos.
   Peças de roupa (`helmet`, `hood`, `pauldron`, `belt`, `cape`) se encaixam com `attach` e já vêm
   presas ao osso.
5. **Biblioteca de armas e acessórios** em kit (`lib/`): espada, machado, escudo redondo e de pipa,
   arco, besta, cajado, varinha, livro, caneca, aljava, cada um com âncora de empunhadura. São de 10
   a 40 primitivas low poly cada.
6. **Rig de verdade.** Pesos suaves nas juntas (cotovelo, joelho, ombro) e clipes de animação nomeados
   (`idle`, `walk`, `run`, `attack`) exportados no glTF. Os nomes dos ossos devem ser compatíveis com
   rigs humanoides, para reaproveitar animações.
7. **Validação.** Montar em `examples/aventureiros.3di` os 5 personagens do plano grátis (cavaleiro,
   bárbaro, ladino, mago e arqueiro) com as armas de cada um. Comparar silhueta, triângulos (meta: no
   máximo 3 mil por personagem) e o GLB aberto no Godot/Blender. As 4 vistas ficam como referência
   no README.

As etapas 1 e 3 são as que mais mudam o resultado visual. As etapas 4 e 5 dão a variedade. A etapa 6
deixa os personagens prontos para jogo. Tudo isso entra no núcleo C++ (`native/core`) e no JS em
paralelo, enquanto o port não substitui o JS.
