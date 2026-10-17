# Copiar uma imagem de referência

1. `set_reference(path="ref.png", opacity=0.5)`: a imagem fica por cima da vista 3D do editor
   (também pelo botão Referência da IDE ou arrastando a imagem). `scale`, `x`, `y` (em % da imagem)
   e `side=True` (lado a lado) ajustam o encaixe.
2. Posicione a câmera como na imagem (`set_camera(pos, look, fov)`; isométrico ~ `pos=(5, 4.5, 5.5), fov=34`).
3. `compare_reference()` devolve referência | cena | sobreposição: compare silhueta e proporções
   (tamanho da cabeça em relação ao corpo, largura do tronco, comprimento dos membros) **antes** das cores.
4. Corrija proporções nas variáveis principais, depois cores e detalhes; repita o compare.

Recorte a imagem para o objeto antes (uma referência com vários objetos atrapalha a sobreposição).
