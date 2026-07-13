# MyTokens — UI-SPEC (SwiftUI / macOS)

Sistema de design. Direção **Bancada**.
Autoria: Prisma. Implementação: Vitral. Divergência que ninguém cobra vira o design de outra pessoa.

- **Direção visual:** `mockups/index.html` — abre no browser. É a *intenção*, não o alvo.
  **Não porte o CSS.** Metade dele era esforço pra fingir de macOS. Agora é de graça.
- Escrito contra: `docs/LIMITES.md` (Sonda), `docs/CURSOR.md` (Sextante). Lidos em 2026-07-13.
- Alvo: macOS 14+, SwiftUI, `MenuBarExtra` + janela.

---

## 0. O problema central — mudou de forma

Na Fase 1 o problema era **certeza** (medido × derivado × ausente). O `statusLine` hook matou
metade disso: o Claude agora vem medido, igual ao Codex.

O que sobrou é mais sutil e mais difícil: **as janelas têm FORMAS diferentes.**

| Provedor | Janelas | Unidade |
|---|---|---|
| Claude | **5 h** + **7 d** | % de utilização |
| Codex | **7 d** apenas (a de 5 h morreu em 2026-07-12) | % de utilização |
| Cursor | **mês** — ou **nada**, sem credencial | **US$** de compute |

Três formas. Nenhuma mentirosa. Todas legítimas. E se eu deixar o **provedor** ser o eixo
principal da tela, viram colcha de retalhos na hora — porque aí um provedor tem 2 barras, outro
tem 1, outro tem meia, e a tela fica torta sem motivo.

### A decisão: o eixo principal não é o provedor. É o TEMPO ATÉ TE PARAR.

**Uma linha por JANELA, não por provedor. Ordenadas por folga, a mais apertada em cima.**

*Porquê: a pergunta do usuário é "posso continuar?", e quem responde isso é UMA janela — a que acaba primeiro. Provedor é metadado dela, não o contrário. Assim, "o Claude tem 2 linhas e o Codex tem 1" deixa de ser tensão de design e vira só um fato sobre o Claude.*

Isso resolve a assimetria por **recusa**: eu não tento equilibrar os provedores, porque eles não são
equilibrados. Escala pra qualquer provedor com qualquer número de janelas, sem redesenho.

### A tela tem DUAS zonas

| Zona | O que é | Peso |
|---|---|---|
| **O QUE APERTA** | a janela de menor folga. **Uma só.** Instrumento inteiro. | herói |
| **OS OUTROS TETOS** | todas as outras, meia altura, ordenadas por folga. | livro-razão |

*Porquê: só UMA janela pode te parar primeiro. Promover uma a herói é o que impede as três formas de brigarem — elas nunca competem pelo mesmo espaço.*

### As três formas se distinguem pela GRADUAÇÃO, não pelo instrumento

Mesma pista, mesma tinta, mesma gramática. **Muda a régua:**

| Janela | Graduação | Rótulo do eixo |
|---|---|---|
| 5 h | 5 marcas — **hora** | `0h · 1h · 2h · 3h · 4h · 5h` |
| 7 d | 7 marcas — **dia** | `seg · ter · qua …` |
| Mês (US$) | 4 marcas — **US$ 5** | `$0 · $5 · $10 · $15 · $20` |

*Porquê: régua em cm e régua em polegada são obviamente o mesmo objeto, e obviamente medem coisas diferentes. A graduação diz a escala de tempo sem gastar um rótulo — e é o que faz "5 h" e "7 d" nunca serem confundidos, mesmo tendo o mesmo comprimento na tela.*

E o **eixo é normalizado** (0 → 100% *daquela* janela).
*Porquê: é a única unidade em que 5 h, 7 d e US$ 20/mês são honestamente comparáveis. Foi o que salvou o design quando o Codex matou a janela de 5 h — nenhum pixel precisou mudar.*

### O veredito carrega o próprio ponto cego

O Cursor pode não ter dado nenhum. Então o veredito **nunca** afirma mais do que sabe:

> **Dá pra continuar** — dos tetos que eu enxergo.
> O Cursor não me conta nada. *[conectar]*

*Porquê: um herói escolhido entre 3 janelas quando existem 4 é um herói possivelmente errado. A alternativa honesta não é esconder o Cursor — é **escopar a afirmação**. Uma janela ausente nunca pode ser promovida a herói (não dá pra provar que ela aperta), mas ela sempre aparece como ressalva do veredito.*

---

## 1. Certeza — o que sobrou (e continua valendo)

Ainda existem três certezas, só que agora são **estados de runtime**, não propriedades do provedor:

| | MEDIDO | INFERIDO | AUSENTE |
|---|---|---|---|
| Quando | hook/disco entregou | fallback: token do disco ÷ teto **não publicado** | sem credencial, sem arquivo |
| Tinta | sólida | **reticulada** | nenhuma |
| Topo | corte reto | pontilhado | — |
| Número | `50%` | `~53%` + faixa `41–68` | `—` (**nunca** `0`) |
| Selo | **nenhum** | rodapé: "estimado" | rodapé: "sem dado" |

**Medido é o caso não-marcado.** Sem badge, sem selo.
*Porquê: honestidade não paga enfeite. Quem paga o preço visual é a incerteza.*

**Nunca `0`.** Zero é uma afirmação. Ausente é `—`.

### A barra composta (`mockups/01`)

O `statusLine` só dispara **enquanto o Claude Code roda**. Logo todo valor medido tem **idade**.
Se a última verdade chegou às 14:35 e o disco registrou gasto desde então, a barra é composta:

```
[========sólido========][:::reticulado:::]
 medido, statusLine 14:35   inferido do disco
                        ↑ a COSTURA = carimbo de hora da última verdade
```

*Porquê da costura: sem ela a barra vira degradê, e degradê não diz ONDE o fato acaba e o palpite começa.*

Em SwiftUI: um `HStack(spacing: 0)` de duas `Rectangle`s dentro de um `.clipShape`, com um
`Divider` de 1pt entre elas. Uma linha de código. No CSS era um `repeating-linear-gradient` e um
pseudo-elemento.

---

## 2. Cor — semântica do sistema, não hex solto

**Regra: quase tudo é semântico. A única cor nossa é a que carrega SIGNIFICADO.**

### Texto e chrome — 100% do sistema

```swift
.foregroundStyle(.primary)      // número principal
.foregroundStyle(.secondary)    // número secundário, nome do provedor
.foregroundStyle(.tertiary)     // rótulo, unidade
.foregroundStyle(.quaternary)   // traço fantasma, graduação
Color(nsColor: .separatorColor) // fios
```

*Porquê: `.primary`…`.quaternary` são **vibrantes** sobre material. Um cinza fixo em cima de um `NSVisualEffectView` fica chapado e o popover imediatamente para de parecer nativo. Esse é o erro que denuncia um app "web preso numa janela".*

### Superfícies — material, não cor

| Peça | Material | Porquê |
|---|---|---|
| Popover (`MenuBarExtra`) | **o do sistema. Não pinte nada.** | *o `MenuBarExtra(.window)` já traz o material certo. Pintar um fundo opaco em cima mata a vibrancy — é o pecado capital do pivot.* |
| Janela principal | `NSVisualEffectView(.underWindowBackground)` | *pega o desktop de leve. É o "de graça" que o Electron não tinha.* |
| Painel do número cru | `.quaternary.opacity(0.5)` sobre o material | *elevação por densidade, não por caixa.* |
| Pista (track) | `Color.primary.opacity(0.10)` | *é ausência de tinta, não uma cor.* |

**Zero `Color(hex:)` para chrome. Zero fundo opaco dentro do popover.**

### A ÚNICA cor nossa: o ember

Uma matiz. Não significa perigo — significa **calor = atividade**.

```
ember-cold  →  provedor parado        (deriva de .secondary, sem croma própria)
ember       →  está queimando AGORA
ember-hot   →  vai estourar
```

*Porquê: sem verde e sem amarelo no sistema, não existe semáforo nem se eu quisesse fazer um. A restrição é a garantia.*

**Asset Catalog, Color Set, 2 aparências (Any + Dark).** Nunca hex inline.

| Nome | Light (sRGB) | Dark (sRGB) | Origem |
|---|---|---|---|
| `ember` | `#B85F21` | `#E8873C` | `oklch(.58 .15 42)` / `oklch(.76 .13 48)` |
| `emberHot` | `#B33418` | `#E85231` | `oklch(.53 .20 30)` / `oklch(.68 .195 32)` |

> Vitral: gerei do OKLCH. Confere no Color Picker e ajusta se o contraste em light não bater
> 4.5:1 contra o material claro. **O valor certo é o que passa no contraste, não o meu hex.**

**`emberHot` aparece em no máximo DOIS lugares por tela:** o transbordo da projeção e uma palavra
da frase. *Porquê: croma escassa grita mesmo sendo pequena; croma abundante vira decoração.*

### Não use `Color.accentColor`

*Porquê: o accent é configurável pelo usuário no macOS. Se ele escolher verde, "queimando agora" fica verde e a semântica quebra. Nossa cor carrega significado — significado não é preferência.*

---

## 3. Tipografia — sistema, com pesos reais

```swift
// VEREDITO — e só ele
.font(.system(size: 30, weight: .semibold))
.tracking(-0.4)

// NÚMERO HERÓI (a % da janela que aperta)
.font(.system(size: 34, weight: .medium, design: .monospaced))
.monospacedDigit()

// NÚMERO DE LINHA
.font(.system(size: 15, weight: .medium, design: .monospaced))
.monospacedDigit()

// NOME DO PROVEDOR / JANELA
.font(.system(size: 13, weight: .medium))

// RÓTULO (caixa alta)
.font(.system(size: 10, weight: .medium))
.kerning(0.6)

// RODAPÉ / PROCEDÊNCIA
.font(.system(size: 11, weight: .regular))
```

**`.monospacedDigit()` em TODO número, sem exceção.**
*Porquê: número que treme de largura ao atualizar destrói a leitura de relance — que é o produto inteiro. No CSS isso era `font-feature-settings: "tnum"`; aqui é um modifier.*

**`design: .monospaced` só para NÚMERO. Nunca para rótulo.**
*Porquê: grotesca diz o que a coisa é; mono diz o que a máquina mediu. Separar os papéis é o que dá autoridade ao número — e é o que faz parecer instrumento e não dashboard.*

**Não use `design: .rounded` em lugar nenhum.**
*Porquê: `.rounded` é a voz do Fitness/Reminders — amigável. Este app é um instrumento de medição. Amigável aqui soa como quem está te escondendo alguma coisa.*

### Peso como tensão

A tensão sobe por **gramatura**, não por matiz.

| Faixa | `foregroundStyle` | `weight` |
|---|---|---|
| 0–25% | `.secondary` | `.regular` |
| 25–50% | `.secondary` | `.medium` |
| 50–75% | `.primary` | `.medium` |
| 75–100% | `.primary` | `.semibold` |
| >100% | `Color.emberHot` | `.semibold` |

*Porquê: `norte-ux` #4 pede tensão por densidade e peso. Isto é literalmente isso, e não gasta uma gota de cor.*

---

## 4. Espaço, raio, sombra

**Espaço — base 4.** `4 · 8 · 12 · 16 · 24 · 32 · 48`
*Porquê: menor passo que o macOS respeita em @1x e @2x sem borrar.*

**Raio — `.continuous`, sempre.**

```swift
RoundedRectangle(cornerRadius: 6, style: .continuous)   // painel
RoundedRectangle(cornerRadius: 4, style: .continuous)   // chip, botão
Rectangle()                                             // A PISTA. raio ZERO.
```

*Porquê `.continuous`: é o squircle da Apple. `.circular` do lado do chrome do sistema fica sutilmente errado, e "sutilmente errado" é exatamente o que faz um app não parecer nativo.*
*Porquê a pista é raio 0: **nada arredonda um dado**. A borda dura da tinta É a informação (é o sinal de "medido"). Arredondar é borrar a promessa.*

**Sombra — ZERO sombra customizada.**
*Porquê: a janela e o popover já ganham sombra do sistema, com a curva certa. Uma `.shadow()` desenhada por nós dentro de um popover nativo é a assinatura visual de um app web. Elevação aqui é material + `separatorColor`, e mais nada.*

---

## 5. Grid

### A PISTA — a peça central

Um eixo, **duas leituras**:

```
eixo x   = 0 → 100% DAQUELA janela
tinta    = % da cota queimada
cursor   = % do tempo decorrido nessa janela  ("agora")
```

**O vão entre a tinta e o cursor é a resposta do app.**
Tinta **atrás** do cursor → gasta mais devagar que o relógio: **folga**.
Tinta **na frente** → acaba antes da janela fechar.

*Porquê: as duas grandezas são frações da mesma janela, logo são honestamente comparáveis no mesmo eixo. Isso transforma um medidor num conselho — sem escrever uma palavra.*

O cursor **não** se alinha entre as pistas: as janelas têm comprimentos diferentes.
*Porquê: uma linha vertical atravessando todas implicava que as janelas eram a mesma coisa. Era bonito e era mentira.*

| | Herói | Livro-razão | Popover |
|---|---|---|---|
| altura da pista | 16 pt | 8 pt | 8 pt |
| graduação | sim, rotulada | sim, sem rótulo | só marcas |
| agulha do "agora" | sim | sim | sim, sem cabeça |
| projeção | sim (>70%) | não | só no herói |

### Layout

```
Janela principal: 640 × 460 pt   (não 940 — app nativo é mais denso que web)
Popover:          320 pt de largura, altura por conteúdo
Grid da linha:    [ nome 140pt ][ pista flexível ][ leitura 110pt ]
```

Use `Grid` do SwiftUI com `GridRow`, não `HStack` com `.frame(width:)` chumbado.
*Porquê: `Grid` alinha as colunas entre linhas sozinho. Largura chumbada quebra quando o nome do provedor cresce.*

### PROJEÇÃO E TRANSBORDO

Aparece só acima de **70%**. *Porquê: abaixo disso é ruído — a resposta já é "pode ir".*

Se a projeção passa de 100%, **o excedente é desenhado FORA do trilho**, em `emberHot` hachurado.

**O trilho é o limite. O que sai dele é o que você não tem.**
*Porquê: o alarme vira geometria em vez de cor — e o fato medido (a barra sólida) nunca é recolorido por um palpite sobre o futuro. Futuro nenhum merece ser desenhado como fato.*

### PROCEDÊNCIA

A legenda medido/inferido/ausente é **permanente**, no rodapé. Não é tooltip, não é popover.
*Porquê: é o rodapé de um instrumento de medição. Contrato de honestidade se imprime na peça.*

---

## 6. Movimento — spring, e uma regra dura

```swift
// DADO — avanço da tinta, mudança de número
.animation(.spring(response: 0.42, dampingFraction: 1.0), value: used)

// DADO — o dreno do reset
.animation(.spring(response: 0.90, dampingFraction: 1.0), value: windowID)

// CHROME — hover, revelar, o card de convite
.animation(.spring(response: 0.30, dampingFraction: 0.82), value: isHovering)
```

### A regra dura do pivot: `dampingFraction: 1.0` em TUDO que representa um dado medido.

*Porquê: overshoot faz a barra passar do valor e voltar. Por ~80 ms ela exibe um número que é **mentira**. Numa UI de fitness isso é charme; num instrumento de medição é um defeito. Damping 1.0 não é escolha estética — é a mesma disciplina de honestidade do reticulado, aplicada ao tempo.*

Bounce (`dampingFraction < 1.0`) só em **chrome**: card que entra, hover, botão. Nunca na tinta,
nunca no número.

### O dreno é MAIS LENTO que o avanço (0.90 contra 0.42)

*Porquê: encher é rotina, esvaziar é acontecimento. Se drenasse rápido, o alívio passava batido — e o alívio é o ponto do reset.*

### Número trocando de valor

```swift
Text(pct, format: .percent)
    .contentTransition(.numericText(countsDown: isDraining))
```

*Porquê: dá o rolo de odômetro nativo, de graça, e `countsDown: true` faz o reset contar pra trás. No CSS eu tive que empilhar 18 `<br>` e animar `steps(18)`. Aqui é um modifier — este é o tipo de coisa que o pivot pagou.*

### Reduce motion

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// → .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(...))
```

Estado **nunca** se perde: reduce motion corta a animação, nunca a informação.

---

## 7. Os estados

### VAZIO (1º boot)

Instrumento **ligado**, pistas abertas, cursor em 0. Mostra os paths que já encontrou
(`~/.claude/projects`, `~/.codex/sessions`).

*Porquê: a primeira impressão não é um pedido de configuração — é a prova de que o app já sabe onde procurar. É o que compra confiança no segundo 1.*

### CARREGANDO — **nunca um spinner onde cabe uma contagem**

A 1ª varredura lê ~6.100 arquivos. Isso demora.

```
lendo 2.418 / 6.111 sessões
[████████░░░░░░░░░░░░░░░]     ← a própria pista, enchendo com o que já foi confirmado
```

*Porquê: um spinner diz "espera" e não diz mais nada. Uma contagem diz "espera, estou em 40%, e o que você está vendo já é verdade". Spinner é a resposta de quem não sabe o denominador — e nós sabemos: é `readdir`.*

Depois do 1º boot, releitura é incremental e **não tem estado de carregando**. A tela nunca pisca.
*Porquê: o app é olhado 30x por dia. Flash de skeleton 30x por dia é tortura.*

### ERRO — erro vira AUSÊNCIA, não banner vermelho

Hook não instalado, arquivo ilegível, endpoint fora do ar: a linha cai pro estado **ausente**
(pista tracejada, `—`) e diz **o que quebrou e como consertar**, inline, na própria linha.

```
Claude · 5 h    ┆ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ ┆    —
                  hook statusLine não instalado   [instalar]
```

**Se havia um número anterior, ele NÃO some — mas é rebaixado:** `.tertiary`, e o rodapé passa a
dizer `última leitura 14:35`.

*Porquê: a pior combinação possível é erro + número velho parecendo fresco. O usuário toma decisão em cima de um número morto. O número velho tem valor (é melhor que nada), mas só se estiver **carimbado como velho**.*

**Não existe banner vermelho.** *Porquê: erro num app de leitura passiva não é urgência — é ausência de informação. Desenhar ausência como alarme é a mesma mentira do semáforo.*

### 85% CONSUMIDO — avisar sem dar pânico

A tela **não fica vermelha**. Três coisas mudam:
1. **a frase** — "Aperta o passo." (não é alerta, é conselho);
2. **o número engorda** — `.semibold`, `.primary`;
3. **a projeção rompe o trilho** — o único `emberHot` da tela.

*Porquê: a barra sólida é o **fato medido** e não pode mudar de cor porque o **futuro** é feio. O que vaza pra fora do trilho é a projeção — e projeção é palpite, e palpite é o que pode ser desenhado hachurado e vermelho.*

### RESET DA JANELA — o momento de alívio

```
0 ms     trava. o número congela.
+60 ms   a TINTA DRENA (spring response .90, damping 1.0). volume saindo.
+60 ms   o número desce junto — .contentTransition(.numericText(countsDown: true)),
         mesma spring. se número e barra não andarem juntos, o olho não acredita.
+660 ms  a agulha do "agora" salta pro 0: a janela virou.
+780 ms  a headline troca. SÓ DEPOIS que a pista esvaziou.
```

**As outras pistas não se mexem.**
*Porquê: as janelas são independentes e têm comprimentos diferentes. Se tudo animasse junto, o app mentiria sobre a mecânica dos limites e o usuário aprenderia errado.*

**Nada pisca, nada quica, nada faz confete.**
*Porquê: isso não é uma conquista — é o dia recomeçando. E `dampingFraction: 1.0` garante que a tinta não quica nem se eu quisesse.*

**E se o reset promove outra janela a herói:** a reordenação anima com a spring de chrome
(response .30). *Porquê: a linha subindo pro topo É a informação — "agora quem te aperta é outro". Esconder o movimento seria esconder o fato.*

### O PALPITE VIRA MEDIDA (`mockups/07`)

Sem o hook, o Claude é 100% inferido. Instalar entrega `used_percentage` medido, e a barra
**endurece**: o reticulado condensa em tinta sólida, a faixa de incerteza **colapsa**, o til some.

*Porquê: é a recompensa mais honesta que um app pode dar — você não ganhou um confete, ganhou **precisão**, e dá pra ver a precisão chegando. É o único onboarding que este app precisa ter.*

O palpite era `~54%`; a verdade é `53%`. **A barra corrige 1 ponto, e o app mostra isso.**
*Porquê: o palpite não era lixo, era um palpite. Esconder o acerto seria tão desonesto quanto esconder o erro.*

---

## 8. O ícone da barra de menu

**22 pt, template image. Monocromático. NÃO defina cor — o macOS tinge sozinho.**

**Forma: proveta graduada.** Cilindro em pé, 3 traços de graduação na lateral, tinta subindo.

Por que proveta e não pilha:
1. a pilha do macOS é **deitada e com bico**; a nossa é **em pé e sem bico** — lado a lado na barra, nunca se confundem;
2. proveta é objeto de **medição**, que é literalmente o que o app faz;
3. tinta subindo = consumo, e **densidade de tinta é a tensão** — mais perto de estourar, mais preto o ícone.

*E aqui o pivot me deu um presente: template image **não me deixa** usar cor. Então o semáforo é literalmente impossível de implementar. A restrição que eu impus por disciplina na Fase 1, o AppKit agora impõe por contrato.*

### Como entregar

É **dinâmico** (o nível muda), então não é asset estático. Desenhe em runtime:

```swift
func menuBarIcon(fill: Double, certainty: Certainty, state: IconState) -> NSImage {
    let img = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
        let body = NSRect(x: 7.5, y: 3.5, width: 9, height: 15)   // .5 → traço cai NO pixel
        let vessel = NSBezierPath(roundedRect: body, xRadius: 2.4, yRadius: 2.4)
        vessel.lineWidth = 1.1

        // graduação: 3 traços na lateral esquerda
        for y in [8.0, 11.0, 14.0] {
            let t = NSBezierPath()
            t.move(to: NSPoint(x: 4, y: y)); t.line(to: NSPoint(x: 6, y: y))
            t.lineWidth = 1
            NSColor.black.withAlphaComponent(0.55).setStroke(); t.stroke()
        }
        // ... contorno + tinta recortada pelo vessel + topo (ver tabela de estados)
        return true
    }
    img.isTemplate = true      // ← A LINHA QUE IMPORTA. sem isso, nada disso funciona.
    return img
}
```

**`isTemplate = true` é obrigatório.**
*Porquê: é o que faz o macOS inverter na barra clara/escura E inverter de novo quando o usuário clica (menu aberto = fundo destacado). Um ícone colorido ignora o destaque de seleção e fica ilegível justamente no momento em que está sendo usado.*

### Os estados

| Estado | Desenho |
|---|---|
| **Sem dado** | contorno **tracejado**, zero tinta |
| **Medido** | tinta sólida, **topo com corte reto** |
| **Inferido** | tinta **reticulada**, **topo pontilhado** |
| **Quase lá (≥85%)** | quase sólido — massa de tinta é o aviso |
| **Estourou (≥100%)** | sólido + **régua acima da boca** (silhueta única no app) |
| **Reset** | tinta **desce**, mesma spring do dreno da janela |
| **Pausado / sem leitura** | contorno íntegro, ícone inteiro a **42% de alfa** |

*Porquê "pausado" ≠ "sem dado": no tracejado, a fonte sumiu. No alfa 42%, o vaso está íntegro e quem parou fui eu.*

### Regra de mistura

O ícone mostra **UMA** janela: **a de menor folga** — a mesma que é herói na janela principal.
A textura do topo é a **dela**.

*Porquê: três provetas em 22 pt não é informação, é sujeira. E porque o ícone tem que concordar com a janela: se discordassem, o usuário aprenderia a não confiar em nenhum dos dois.*

### Regras que não se quebram

- Contorno em coordenada `.5`; tinta e topo em coordenada **inteira**. *Porquê: em 22 pt, meio pixel de erro vira cinza borrado e o ícone perde o corte reto — que é justamente o sinal de "medido".*
- Tinta em **degraus de 5%** (20 níveis). *Porquê: 1% são 0,15 pt — invisível, e ainda força redesenho do `NSImage` a cada evento do disco.*
- **Sem cor. Sem badge. Sem emoji. Sem piscar.** *Porquê: piscar é o semáforo de quem não tem cor disponível. Se estourou, a resposta é a régua acima da boca — parada, até você resolver.*

> Alternativa que o Vitral pode preferir: exportar como **Custom SF Symbol** (SVG do template do
> app SF Symbols) e usar `Image(_:)` com `.symbolRenderingMode(.template)`. Ganha alinhamento
> óptico e variantes de peso de graça. Só vale se ele conseguir 20 níveis de nível como variantes —
> se não, o `NSImage` em runtime é mais simples e igualmente nativo.

---

## 9. Morte súbita (checklist de review)

- [ ] Card genérico: número grande + sparkline
- [ ] Gradiente roxo/azul de SaaS
- [ ] Semáforo verde/amarelo/vermelho como identidade
- [ ] Gráfico de pizza / donut / anel de progresso
- [ ] Emoji como ícone de sistema
- [ ] **`0` onde a resposta honesta é `—`**
- [ ] **Dado inferido com a mesma textura do medido**
- [ ] **Soma de token apresentada como "quanto sobra"** — ninguém publica o teto em token
- [ ] **`dampingFraction < 1.0` em barra de dado** — a barra exibe um valor falso no overshoot
- [ ] **Fundo opaco dentro do popover** — mata a vibrancy, e o app deixa de parecer macOS
- [ ] **`.shadow()` customizada** — assinatura de app web
- [ ] **Número sem `.monospacedDigit()`**

Os seis últimos são meus. Valem tanto quanto os cinco do `norte-ux`.

---

## 10. Contrato de dados (o que o Vitral precisa do core)

```swift
enum Certainty { case measured, inferred, absent }
enum WindowKind { case fiveHour, sevenDay, monthlyUSD }

struct Reading<T> {
    let value: T?            // nil quando .absent. NUNCA 0.
    let certainty: Certainty
    let lo: Double?          // obrigatório quando .inferred
    let hi: Double?          // obrigatório quando .inferred
    let measuredAt: Date?    // obrigatório quando .measured
}

struct LimitWindow: Identifiable {
    let id: String              // "claude.5h", "codex.7d", "cursor.month"
    let provider: Provider
    let kind: WindowKind
    let startedAt: Reading<Date>
    let resetsAt: Reading<Date>
    let used: Reading<Double>   // 0–100 em pct; US$ em monthlyUSD
    let ceiling: Reading<Double>?   // US$ 20 no Cursor Pro; nil em pct
    let burnRate: Double?           // pts (ou US$) por hora, últimos 20 min → a projeção

    var slack: Double? { ... }  // ← a chave da ORDENAÇÃO. nil quando .absent.
}
```

Regras que o core **tem** que respeitar, ou o design mente:

1. **`slack == nil` nunca vira herói.** *Porquê: não dá pra provar que uma janela ausente aperta. Ela vira ressalva do veredito, nunca o veredito.*
2. `lo`/`hi` **obrigatórios** quando `.inferred`. *Porquê: sem faixa, o reticulado é só um borrão bonito. Com faixa, é estatística honesta.*
3. `measuredAt` **obrigatório** quando `.measured`. *Porquê: é o que desenha a costura da barra composta. Sem carimbo de hora, não dá pra saber onde o fato acaba.*
4. `used.value == nil` quando `.absent`. **Nunca `0`.**
5. Soma de token **nunca** vira `used`. Vira **custo**, e só. *Porquê: nenhum dos três publica teto em token (`docs/LIMITES.md`).*

---

## 11. Pendências que travam pixel

1. **Cursor.** `docs/CURSOR.md`: o Sextante **não confirmou o endpoint ao vivo** — o shape é *PROVÁVEL*. Enquanto não confirmar: **`.absent` permanente**, com a ação "conectar". **Nunca inventar número.**
2. **Unidade do Cursor é US$, não %.** A pista normalizada aguenta (gasto ÷ crédito = fração). Mas o **rótulo tem que dizer `US$ 6,40 / 20`**, nunca `32%` sozinho. *Porquê: 32% de um crédito em dólar e 32% de uma cota opaca não são a mesma coisa, e fingir que são é exatamente a mentira que este spec inteiro existe pra matar.*
3. **Contraste do ember em light mode.** Gerei do OKLCH sem medir contra o material claro real. Vitral: mede. Se não passar, o hex certo é o que passa.
