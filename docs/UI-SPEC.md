# MyTokens — UI-SPEC

Sistema de design. Direção **Bancada**.
Autoria: Prisma. Implementação: Vitral. Divergência que ninguém cobra vira o design de outra pessoa.

Mockups: `mockups/index.html` (abre no browser, sem build).
Tokens executáveis: `mockups/bancada.css` — copiar de lá, não redigitar.

---

## 0. O problema central, e a solução

As três fontes não são três valores. São **três níveis de certeza sobre um valor**.

| Fonte | O que o disco entrega | Certeza |
|---|---|---|
| Codex | `rate_limits.primary.used_percent` + `resets_at` | **medido** |
| Claude Code | só gasto (4 buckets de token). Teto do plano não existe no disco | **derivado** |
| Cursor | nada local | **ausente** |

Se os três aparecem com o mesmo anel de progresso, o app mente com CSS.
A saída **não** é dar um card diferente pra cada um — isso vira colcha de retalhos.
A saída é: **certeza vira uma dimensão visual de primeira classe**, e a *mesma* peça
(a pista) exibe as três com texturas diferentes.

### A regra de granularidade — o detalhe que salva o design

**Certeza é por CAMPO, não por provedor.**

No Claude, o **início da janela é MEDIDO** (está no `timestamp` do primeiro `assistant`
do jsonl). Só o **teto** é derivado. Então:

- o horário de reset do Claude é **sólido** (17:40, sem til);
- a % do Claude é **reticulada** (~61%, com faixa 52–70).

Na mesma linha, um campo duro e um campo mole. É isso que impede o Claude de virar
"o provedor borrado" e faz o app parecer honesto em vez de derrotado.
*Porquê: se a incerteza fosse aplicada ao provedor inteiro, jogaríamos fora dado bom que nós temos.*

### As três texturas

| | MEDIDO | DERIVADO | AUSENTE |
|---|---|---|---|
| Tinta | sólida | reticulado 1 px / 3 px | nenhuma |
| Topo | corte reto, 2 px sólido | pontilhado 2 px on / 2 px off | — |
| Extra | — | faixa de incerteza (piso–teto, 2 ticks duros) | pista tracejada |
| Número | `58%` | `~61%` + range `52–70` | `—` (nunca `0`) |
| Peso | 600 | 500 | 400 |
| Selo | **nenhum** | rodapé diz "estimado" | rodapé diz "sem dado local" |

**Medido é o caso não-marcado.** Não tem badge, não tem ícone, não tem nada.
*Porquê: a honestidade não pode custar enfeite. Quem paga o preço visual é a incerteza — que é o que ela merece.*

O reticulado é convenção cartográfica de "inferido", com 300 anos de uso: área não-sólida
= dado não-sólido. Não precisa de legenda pra ser **sentida** — a legenda existe só pra
ser confirmada.

**Dois canais, sempre.** Textura (olho de raspão) + til/palavra (olho que para).
*Porquê: um canal só é um ponto único de falha de compreensão.*

**Nunca zero.** Zero é um número, e número é uma afirmação. Ausente é `—`.

---

## 1. Cor

**Regra que governa tudo: o app é ACROMÁTICO.**
Existe **uma** matiz (ember, ~40–48°) e ela **não significa perigo** — significa **calor = atividade**.

```
cinza (ember-cold)  →  provedor parado
ember               →  está queimando AGORA
ember-hot           →  vai estourar
```

Uma matiz só, croma crescente. *Porquê: sem verde e sem amarelo no sistema, não existe semáforo nem se eu quisesse fazer um. A restrição é a garantia.*

```css
/* superfícies — preto QUENTE (60°). Preto-azulado é o SaaS de 2021. */
--canvas:     oklch(0.165 0.006 60);
--surface:    oklch(0.205 0.007 60);
--surface-hi: oklch(0.235 0.008 60);
--track:      oklch(0.265 0.007 60);
--line:       oklch(0.305 0.008 60);
--line-soft:  oklch(0.255 0.007 60);

/* tinta — bone. É a cor do DADO, não do texto. */
--ink-0: oklch(0.955 0.008 80);   /* número principal        */
--ink-1: oklch(0.780 0.008 80);   /* número secundário       */
--ink-2: oklch(0.590 0.008 80);   /* rótulo                  */
--ink-3: oklch(0.455 0.008 80);   /* unidade, rótulo apagado */
--ink-4: oklch(0.360 0.008 80);   /* traço fantasma          */

/* ember — a única matiz do app */
--ember-cold: oklch(0.700 0.035 45);   /* quase cinza: medido, parado */
--ember:      oklch(0.760 0.130 48);   /* vivo: queimando agora       */
--ember-hot:  oklch(0.680 0.195 32);   /* ESTOURO. E só estouro.      */
```

`--ember-hot` aparece em, no máximo, **dois lugares por tela**: o transbordo da projeção
e uma palavra da frase. *Porquê: croma escassa grita mesmo sendo pequena; croma abundante vira decoração e ninguém olha.*

Light mode existe e está em `bancada.css`. *Porquê: o popover vive na barra do sistema e não escolhe o tema do usuário.*

---

## 2. Tipo

Duas famílias, papéis **fixos**. Nunca trocar — é o que faz parecer instrumento.

```css
--font-ui:  -apple-system, "SF Pro Text", "Inter", system-ui, sans-serif;  /* rótulo humano */
--font-num: ui-monospace, "SF Mono", "JetBrains Mono", monospace;          /* número medido */
```

*Porquê: grotesca diz o que a coisa é; mono diz o que a máquina mediu. Separar os papéis é o que dá autoridade ao número.*

```
--t-micro  10px   rótulo caixa alta, tracking .09em
--t-xs     11px
--t-sm     13px   corpo
--t-md     15px   subtítulo, nome do provedor
--t-lg     19px   número secundário (relógio, folga)
--t-xl     26px   a % de cada pista
--t-2xl    40px
--t-3xl    54px   O VEREDITO. e só ele.
```

**`font-feature-settings: "tnum" 1` no `body`, sem exceção.**
*Porquê: número que treme de largura ao atualizar destrói a leitura de relance — que é o produto inteiro.*

### Peso como tensão

A tensão sobe por **gramatura**, não por matiz. Quanto mais perto do teto, mais pesado e mais claro o número:

| `data-heat` | faixa | cor | peso |
|---|---|---|---|
| 0 | 0–25% | `--ink-2` | 400 |
| 1 | 25–50% | `--ink-1` | 500 |
| 2 | 50–75% | `--ink-0` | 600 |
| 3 | 75–100% | `--ink-0` | 700, tracking −.03em |
| 4 | >100% | `--ember-hot` | 700 |

*Porquê: `norte-ux` #4 pede tensão por densidade e peso. Isto é literalmente isso, e não gasta uma gota de cor.*

---

## 3. Espaço, raio, sombra

**Espaço — base 4.** `4 · 8 · 12 · 16 · 24 · 32 · 48 · 64`
*Porquê: 4 é o menor passo que o macOS respeita em @1x e @2x sem borrar.*

**Raio — baixo.** `0` (pista, régua, tinta) · `3` (chip, botão) · `6` (painel) · `10` (popover).
*Porquê: raio alto é bolha de SaaS; instrumento tem canto vivo. E **nada arredonda um dado** — a pista é raio 0 porque a borda dura É a informação.*

**Sombra — quase não existe.** No escuro, sombra não separa nada; elevação é fio de 1 px + `--bevel` (brilho interno no topo).
Sombra de verdade só no **popover** — *porquê: é a única peça que de fato flutua sobre o desktop do usuário.*

---

## 4. Grid

### A PISTA — a peça central

Um eixo, **duas leituras**:

```
eixo x   = a janela de 5 h (0% → 100% do TEMPO)
tinta    = % da COTA queimada
cursor   = % do TEMPO decorrido  ("agora")
```

**O vão entre a tinta e o cursor é a resposta do app.**

- tinta **atrás** do cursor → você gasta mais devagar que o relógio. Folga.
- tinta **na frente** → você acaba antes da janela fechar.

*Porquê: as duas grandezas são frações da mesma janela, logo são honestamente comparáveis no mesmo eixo. E isso transforma um medidor num conselho — sem escrever uma palavra.*

O **cursor do agora atravessa as três pistas na mesma coordenada**.
*Porquê: é o mesmo relógio. É o que costura três unidades diferentes num app só, e é por isso que a tela não parece colcha de retalhos.*

O Cursor (ausente) **também tem cursor de tempo**: o relógio a gente sempre sabe.
*Porquê: falta a tinta, não a pista. Meia leitura honesta > zero mentiroso.*

Altura: **14 px** na janela, **8 px** no popover. Ticks de hora: 1 px em `--canvas` a 55%.

### PROJEÇÃO E TRANSBORDO

Aparece só acima de **70%**. *Porquê: abaixo disso é ruído — a resposta já é "pode ir".*

A projeção estende a tinta do agora até o fim da janela no ritmo dos últimos 20 min.
Se ela passa de 100%, **o excedente é desenhado FORA do trilho** (`.overrun`, hachura em `--ember-hot`).

**O trilho é o limite. O que sai dele é o que você não tem.**
*Porquê: o alarme vira geometria em vez de cor — e o fato medido (a barra sólida) nunca é recolorido por um palpite sobre o futuro. Futuro nenhum merece ser desenhado como fato.*

### JANELA / POPOVER

| | janela | popover |
|---|---|---|
| largura | 940 px | 340 px |
| grid | `148px · 1fr · 132px` | `1fr · auto`, pista em linha própria |
| veredito | 54 px | 26 px |
| pista | 14 px, com agulha | 8 px, sem agulha |

O que **não** muda entre os dois: o reticulado do derivado.
*Porquê: se ele sumisse no popover, o app mentiria justamente onde é mais olhado.*

### PROCEDÊNCIA

A legenda medido/derivado/ausente é **permanente**, no rodapé das duas telas.
Não é tooltip, não é modal, não é "saiba mais".
*Porquê: é o rodapé de um instrumento de medição. Contrato de honestidade se imprime na peça.*

---

## 5. Estados

| Estado | Como se lê |
|---|---|
| **Vazio (1º boot)** | Instrumento **ligado**, pistas abertas, relógio em 0, pulso de 2,4 s. Mostra os paths que já encontrou. *Porquê: a primeira impressão não é um pedido de configuração — é a prova de que o app já sabe onde procurar. É o que compra confiança no segundo 1.* |
| **Normal** | Veredito + 3 pistas. |
| **Quase lá (≥75%)** | A frase muda ("Aperta o passo"), o número engorda (`heat=3`), a projeção rompe o trilho. **A tela não fica vermelha.** |
| **Estourado (≥100%)** | Tinta cheia + régua acima da boca no ícone. |
| **Reset** | Ver §6. |
| **Sem dado** | Pista tracejada, `—`, link "conectar". |
| **Pausado / sem leitura** | Ícone íntegro a 42% de alfa. *Porquê: diferente de "sem dado" (tracejado) — aqui quem parou fui eu, não a fonte.* |

---

## 6. Movimento

Anima **estado**, nunca decoração. 60 fps ou não anima.

```css
--dur-tick:  140ms;   /* número trocando de valor              */
--dur-ui:    200ms;   /* hover, revelar                        */
--dur-state: 420ms;   /* tinta avançando na pista              */
--dur-reset: 900ms;   /* O DRENO. o momento de alívio.         */

--ease-out:   cubic-bezier(0.20, 0.70, 0.20, 1.00);  /* assenta e para   */
--ease-drain: cubic-bezier(0.55, 0.00, 0.30, 1.00);  /* expira: puxa, solta */
```

**Regra dura do reset: o dreno (900 ms) é MAIS LENTO que o avanço (420 ms).**
*Porquê: encher é rotina, esvaziar é acontecimento. Se drenasse rápido, o alívio passava batido — e o alívio é o ponto.*

Sequência do reset (total 1.500 ms):

```
0 ms      trava. o número congela, a agulha some.
120 ms    a TINTA DRENA da direita pra esquerda (900 ms, ease-drain).
          volume saindo — não barra encolhendo.
120 ms    um clarão fraco corre JUNTO com o dreno (.wash). é o que faz
          o esvaziar ser SENTIDO, não só visto.
120 ms    o número desce junto, mesma curva, mesma duração.
          se número e barra não andarem juntos, o olho não acredita.
900 ms    a agulha do agora salta de 100% pra 0%: a janela virou.
1020 ms   a headline troca. SÓ DEPOIS que a pista esvaziou.
1180 ms   o novo relógio entra, subindo 6 px.
```

**As outras pistas não se mexem.** *Porquê: as janelas são independentes. Se tudo animasse junto, o app mentiria sobre a mecânica dos limites e o usuário aprenderia errado.*

Nada pisca. Nada quica. Nada faz confete. *Porquê: isso não é uma conquista — é o dia recomeçando.*

`prefers-reduced-motion: reduce` → corta o `.wash` e o dreno vira crossfade de 200 ms. Estado nunca se perde.

---

## 7. O ícone da barra de menu

22 px, **template image** (PNG preto + alfa, @1x 22×22 e @2x 44×44, `isTemplate = true`).
O macOS pinta de preto na barra clara e de branco na escura: **não tenho controle de cor, só de forma.**

**Forma: proveta graduada.** Cilindro em pé, 3 traços de graduação na lateral, tinta subindo.

Por que proveta e não pilha:
1. a pilha do macOS é **deitada e com bico**; a nossa é **em pé e sem bico** — lado a lado na barra, nunca se confundem;
2. proveta é objeto de **medição**, que é literalmente o que o app faz;
3. tinta subindo = consumo, e **densidade de tinta é a tensão** — mais perto de estourar, mais preto o ícone. O alarme é gramatura, não cor. *Sem cor eu não teria como fazer semáforo nem se quisesse, e isso é uma vantagem.*

| Estado | Desenho |
|---|---|
| Sem dado | contorno **tracejado**, zero tinta |
| Medido | tinta sólida, **topo com corte reto** |
| Derivado | tinta **reticulada**, **topo pontilhado** |
| Quase lá (85%) | quase sólido — massa de tinta é o aviso |
| Estourou | sólido + **régua acima da boca** (silhueta única no app) |
| Reset | tinta **desce** (900 ms, `ease-drain` — mesma curva da janela) |
| Pausado | contorno sólido, ícone inteiro a **42% de alfa** |

**Regra de mistura:** o ícone mostra **um** provedor — o que fecha primeiro (menor folga).
A textura do topo é a **desse** provedor: se o mais apertado for o Claude, o topo do ícone fica pontilhado.
*Porquê: três provetas em 22 px não é informação, é sujeira.*

**Regras que não se quebram:**

- Contorno em coordenada `.5` (7.5, 3.5); tinta e topo em coordenada **inteira**. *Porquê: em 22 px, meio pixel de erro vira cinza borrado e o ícone perde o corte reto — que é justamente o sinal de "medido".*
- Tinta em **degraus de 5%** (20 níveis). *Porquê: 1% são 0,15 px — invisível, e ainda força repaint a cada evento do disco.*
- Sem cor. Sem badge de contagem. Sem emoji. **Sem piscar** — *porquê: piscar é o semáforo de quem não tem cor disponível. Se estourou, a resposta é a régua acima da boca, parada, até você resolver.*

---

## 8. Morte súbita (checklist de review)

- [ ] Card genérico: número grande + sparkline
- [ ] Gradiente roxo/azul de SaaS
- [ ] Semáforo verde/amarelo/vermelho como identidade
- [ ] Gráfico de pizza / donut / anel de progresso
- [ ] Emoji como ícone de sistema
- [ ] **Um `0` onde a resposta honesta é `—`**
- [ ] **Dado derivado desenhado com a mesma textura do medido**

Os dois últimos são meus. Valem tanto quanto os outros cinco.

---

## 9. O que o Vitral precisa do core (contrato de dados)

Por provedor, por janela:

```ts
type Certeza = 'medido' | 'derivado' | 'ausente'

type Janela = {
  provider: 'codex' | 'claude' | 'cursor'
  windowMinutes: number          // 300 | 10080
  startedAt:  { v: number, c: Certeza }   // claude: MEDIDO (1º timestamp do jsonl)
  resetsAt:   { v: number, c: Certeza }   // claude: MEDIDO (startedAt + 5 h)
  usedPct:    { v: number, c: Certeza, lo?: number, hi?: number }  // claude: DERIVADO + faixa
  burnRatePct: number | null     // pts de % por hora, últimos 20 min → a projeção
}
```

`lo`/`hi` são **obrigatórios** quando `c === 'derivado'`.
*Porquê: sem faixa, o reticulado é só um borrão bonito. Com faixa, é estatística honesta — e é a faixa que autoriza o app a estimar sem mentir.*

`usedPct.v` é `null` quando `c === 'ausente'`. **Nunca `0`.**

---

## 10. Pendências que travam pixel

1. **O teto do Claude.** A faixa `lo`–`hi` depende do que a Sonda/Sextante descobrirem. Se o teto vier a ser **medido** (endpoint autenticado), o Claude vira sólido e o reticulado some da tela dele — **o design já suporta isso sem redesenho**, porque a certeza é um campo, não um layout.
2. **Cursor.** Se a API só servir plano de time: manter `ausente` pra sempre, com o link "conectar" trocado por uma frase honesta. Nunca inventar número.
3. **Janela semanal (7 d).** O Codex entrega (`rate_limits.secondary`). Ainda não desenhei — provável segunda pista, mais fina, sob a de 5 h. Fase 2.
