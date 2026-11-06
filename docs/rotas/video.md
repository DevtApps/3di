# Animação por chaves, roteiro e vídeo

## Chaves: `keys()`

`keys((t0, v0), (t1, v1), ..., ease="smooth", loop=False)` devolve um valor que muda com o tempo,
passando pelas chaves `(tempo em s, valor)`. O valor é número ou tupla (posição, ângulos, escala, cor de glow).
Vale em tudo que aceita `time`: `.at()`, `.rotate()`, `.scale()`, `material(glow=)`, `camera(pos=, look=, fov=)`.

- `ease`: `linear`, `smooth` (padrão: acelera e freia), `in`, `out`, `step` (segura até a próxima chave).
- `loop=True`: repete a cada duração da última chave.
- Antes da primeira chave vale o primeiro valor; depois da última, o último.

```python
timeline(12, fps=30)                       # duração do vídeo e quadros por segundo
cubo = box(0.5).at(keys((0, (0, 0, 0)), (2, (1, 0, 0)), (4, (1, 1, 0))))
cubo = cubo.rotate(y=keys((0, 0), (12, 720), ease="linear"))
camera(pos=keys((0, (0, 1.6, 5)), (6, (3, 2, 3)), (12, (0, 1.6, 5))), look=(0, 0.5, 0), fov=40)
```

O layout (`on`, `beside`, `place`) e as caixas usam o valor em t = 0. Anime a peça já posicionada.

## Roteiro: falas, legendas e vozes

| | |
|---|---|
| `voice(name, speaker=None, language="Portuguese", instruct=None, provider=None, template=None)` | define uma voz. `provider`: `"qwen"` (Qwen3-TTS local) ou `"elevenlabs"`; `speaker`: voz pronta do Qwen (Vivian, Serena, Uncle_Fu, Dylan, Eric, Ryan, Aiden, Ono_Anna, Sohee; nenhuma nativa de português), uma **voz clonada** ou uma voz da sua conta do ElevenLabs (nome ou id); `template`: template de áudio; `instruct`: estilo livre (Qwen). Sem `speaker`/`provider`, valem os padrões das configurações |
| `say(text, at=None, dur=None, voice=None, style=None)` | fala: legenda + áudio. Sem `at`, entra depois da fala anterior; `style` é o nome de um template de áudio ou um estilo livre. Devolve o instante em que termina |
| `caption(text, at=None, dur=None)` | só legenda, sem áudio |

**Narração contínua:** falas seguidas com a mesma voz e o mesmo estilo (sem `at` explícito) são geradas numa
chamada só, para a voz manter o ritmo e a entonação entre as frases; as legendas de cada frase são achadas pelas
pausas do áudio. Uma fala com `at`, outra voz ou outro estilo começa outro trecho (e trechos passam de ~900 caracteres
são divididos).

`dur` é estimada pelo tamanho do texto (~12 caracteres/s). No vídeo vale a duração real do áudio:
falas sem `at` são reagendadas em sequência; com `at` ficam no lugar (o render avisa se sobrepuserem).
Sem `timeline()`, a duração é o fim do roteiro ou a última chave.

## Templates de áudio

Estilos com nome e o prompt que será usado (⚙ → Templates de áudio): `narrador`, `animado`, `calmo`, `sussurro`,
`comercial`, `noticiario` e `crianca` vêm prontos; edite ou crie outros. Cada template tem o **prompt** (instrução de
estilo para o Qwen3-TTS) e, para o ElevenLabs, **marcações de áudio** do modelo v3 (ex.: `[excited]`, `[whispers]`)
e os ajustes de estabilidade, estilo e velocidade. Use em `say("...", style="narrador")` ou `voice("n", template="calmo")`.

## ElevenLabs

Em ⚙ → ElevenLabs: cole a chave de API (fica em `~/.local/share/3di/secrets.json`, só legível por você; ou use a
variável `ELEVENLABS_API_KEY`), escolha o modelo e carregue as vozes da sua conta para escolher a padrão (a chave precisa da permissão **Voices: Read**; sem ela,
cole o ID da voz, ou use o ID em `speaker=`). Use como
provedor padrão ou por voz: `voice("narrador", provider="elevenlabs", speaker="Rachel")`. As falas ficam no mesmo
cache (cada fala é paga uma vez só). A conta e o consumo são os do ElevenLabs.

## Vozes clonadas

Nas configurações (⚙) → **Vozes clonadas**: dê um nome, envie um áudio (ou grave pelo microfone) com 5 a 20 s de
fala limpa e, se puder, o texto falado nele. A voz entra no catálogo e é usada pelo nome:
`voice("narrador", speaker="minha-voz")`. O áudio de referência fica em `~/.local/share/3di/voices/`; a geração usa
o modelo Base do Qwen3-TTS (1.7B ou 0.6B, baixado na primeira vez). Clone só vozes que você tem permissão de usar.

## Textos e sobreposições: `overlay()`

`overlay(component, at=0, dur=None, z=0, **props)` põe um componente **React com Tailwind CSS** por
cima da imagem, de `at` até `at + dur` (sem `dur`, até o fim). Aparece no preview e é gravado no vídeo.
Os outros argumentos nomeados viram props do componente; `z` ordena as camadas.

| `component` | o que é |
|---|---|
| `"titulo"` | título grande com subtítulo (`title`, `subtitle`, `align`, `position`, `color`, `accent`) |
| `"lower_third"` | tarja de nome (`name`, `role`, `accent`, `side`) |
| `"texto"` | texto livre (`text`, `x`, `y` de 0 a 1, `size`, `color`, `weight`, `animation` = fade/slide/pop/typewriter/none, `className`) |
| `"contador"` | número que conta (`from`, `to`, `prefix`, `suffix`, `decimals`, `label`) |
| `"lista"` | tópicos que entram um a um (`title`, `items`, `every`, `accent`) |
| `"arquivo.jsx"` | componente seu, na mesma pasta da cena (salve a cena antes) |
| `"""(props) => <div …/>"""` | o JSX direto no script |

```python
overlay("titulo", at=0, dur=3, title="3DI", subtitle="cenas 3D com código")
overlay("lower_third", at=3, dur=3, name="Ana", role="apresentadora")
overlay("selo.jsx", text="NOVO!")
overlay("""({ local }) => <div className="absolute top-12 right-16 text-3xl text-white">{local.toFixed(1)} s</div>""")
```

Um componente recebe, além das props: `t` (tempo da cena), `local` (tempo desde `at`), `duration`,
`progress` (0 a 1 no trecho), `frame`, `fps`, `width` (sempre 1920) e `height`. O palco tem 1920 px de
largura lógica e é escalado para a imagem: o mesmo componente fica igual no preview e no vídeo em
qualquer resolução.

```jsx
// selo.jsx
import { spring, interpolate, fade, typewriter, easing } from '3di';
export default ({ text, local, duration }) => (
  <div className="absolute left-16 top-16 rounded-3xl bg-rose-500 px-10 py-5 text-5xl font-black text-white"
       style={{ transform: `scale(${spring(local, { from: 0, to: 1 })})`, opacity: fade(local, duration) }}>
    {text}
  </div>
);
```

Funções de animação (`import … from '3di'`, também disponíveis sem import):
`interpolate(t, [t0, t1, …], [v0, v1, …], { easing, clamp })`, `spring(t, { from, to, delay, stiffness,
damping })`, `fade(local, duration, entrada, saída)`, `typewriter(texto, progress)` e `easing`
(linear, in, out, inOut, smooth, back, elastic).

Regras:
- **Anime pelo tempo** (`t`, `local`, `progress`): cada quadro do vídeo é desenhado num instante; `transition`,
  `animate-*` e outras animações CSS não ficam sincronizadas no vídeo.
- Só dá para importar `react` e `3di`. Imagens precisam ser `data:` URLs; fontes, as do sistema.
- O React, o Tailwind (v4, gerado no navegador) e o compilador de JSX vão no pacote do 3DI: funciona offline.
  Os componentes rodam num iframe isolado: o CSS deles não afeta a IDE.

## Preview

A barra de timeline embaixo da vista toca/pausa, arrasta o tempo, mostra as chaves (amarelo) e as falas
(azul) e legendas (cinza). A legenda ativa aparece por cima da vista e as falas tocam junto (🔊 liga/desliga; o seletor ao lado troca a voz de
todas as falas no preview e, por padrão, no vídeo); enquanto são geradas,
a barra mostra o progresso (fala x de n) e os blocos das falas piscam. Com câmera animada, o botão 🎥
segue a câmera do roteiro; girar a vista solta a câmera. Pelo MCP: `set_time(time=..., playing=False)`
e `screenshot(time=...)` conferem um instante.

## Render de vídeo

**No app:** botão **Vídeo** (Exportar). Escolha nome, tamanho, quadros por segundo, legendas (faixa embutida,
gravadas na imagem ou sem) e se as falas têm voz. Os quadros são desenhados pela própria vista; o vídeo e o `.srt` vão para a pasta de
downloads do usuário (a do `xdg-user-dir DOWNLOAD`, padrão `~/Downloads`), sem sobrescrever arquivos.

**Pela linha de comando** (no repositório):

```bash
node scripts/video.mjs cena.3di out/video.mp4 [--size 1280x720] [--fps 30] [--from s] [--to s] [--burn] [--no-audio] [--no-subs] [--cpu]
```

O que o vídeo usa e onde fica:
- **ffmpeg:** vem no pacote do 3DI (no desenvolvimento, o `ffmpeg-static` do npm).
- **Vozes (Qwen3-TTS):** grandes demais para o pacote (PyTorch: alguns GB). O botão **Instalar vozes** cria um
  ambiente Python próprio em `~/.local/share/3di/tts/venv` (precisa do `python3-venv`, recomendado pelo `.deb`).
  Os pesos do modelo (1.7B CustomVoice) são baixados na primeira fala; GPU com ~6 GB ou CPU (lenta).
  `THREEDI_TTS_MODEL` troca o modelo (0.6B gasta menos memória, sem `instruct`).
- **Cache das falas:** `~/.local/share/3di/tts/cache`; só fala nova ou alterada é gerada de novo.
- Legendas: `.srt` ao lado do vídeo e faixa embutida no MP4, ou gravadas na imagem.
