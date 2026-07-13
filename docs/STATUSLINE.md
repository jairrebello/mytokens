# STATUSLINE HOOK — o que exige, e o que eu NÃO fiz

**Status: INVESTIGADO. NADA INSTALADO. NADA ESCRITO.**
O app, hoje, não escreveu um byte fora do repo. Este doc existe pro Jair decidir se autoriza — e o quê.

Levantado pelo Chassi em 2026-07-13, por leitura read-only do disco.

---

## 1. Por que isso importa tanto

O "restante" do Claude (`5h` e `7 dias`) **não é derivável de token** — a Anthropic não publica o
denominador. O número existe, pronto, e chega por **um caminho só**: o stdin do hook `statusLine`
do Claude Code.

Sem esse hook, o Claude aparece no app como **`derivado`** (tinta reticulada, topo pontilhado) em vez
de **`medido`** (tinta sólida, corte reto). O app **continua honesto e continua funcionando** — o
design do Prisma já previu exatamente este caso. Só é menos exato.

O Codex **não tem esse problema**: ele grava `rate_limits` no próprio rollout `.jsonl`. Lemos de graça,
sem hook, sem escrever nada. Só o Claude precisa disto.

---

## 2. O mecanismo exato

Chave em `~/.claude/settings.json` (confirmado no arquivo real do Jair):

```jsonc
"statusLine": {
  "type": "command",
  "command": "\"/opt/homebrew/bin/node\" \"/Users/jairrebello/.claude/hooks/gsd-statusline.js\""
}
```

O Claude Code executa esse comando e entrega um JSON no **stdin**. Dentro dele (shape confirmado pelo
Sonda nas strings do binário, `docs/LIMITES.md`):

```jsonc
{
  "rate_limits": {
    "five_hour": { "used_percentage": 0..100, "resets_at": <epoch em SEGUNDOS> },  // opcional
    "seven_day": { "used_percentage": 0..100, "resets_at": <epoch em SEGUNDOS> }   // opcional
  }
}
```

Duas propriedades que mudam o design, e valem ser ditas:

- **O hook só dispara enquanto o Claude Code está rodando.** Fechou o Claude, o número congela.
  Todo valor "medido" **tem idade** — é por isso que a UI-SPEC §1 desenha a costura na barra.
  Isto não é um defeito da nossa implementação; é a natureza da fonte.
- Ele dispara no **redesenho da statusline** (a cada turno, grosso modo). É empurrado pra gente,
  não puxado. Bom: casa com nossa arquitetura orientada a evento.

---

## 3. 🚩 A descoberta que trava tudo: o Jair JÁ TEM um statusLine

```
~/.claude/hooks/gsd-statusline.js   — 566 linhas, do GSD
```

**`statusLine` é uma chave única. Não existe encadeamento nativo. Escrever a nossa DESTRÓI a dele.**

Isso não é um detalhe de implementação — é a razão pela qual eu parei e vim perguntar em vez de
instalar. Um app de monitoramento que quebra a statusline do usuário no primeiro launch é um app
desinstalado no segundo minuto.

---

## 4. Existe caminho SEM escrever nada? Eu procurei. **Não existe.**

Era a hipótese que eu mais queria confirmar, porque tornaria esta conversa desnecessária.
Varri `~/.claude` atrás da chave JSON literal `"rate_limits":`:

| Onde procurei | Achei |
|---|---|
| `~/.claude/projects/**/*.jsonl` | só nos arquivos de **probe do próprio Sonda** — falso positivo nosso |
| `~/.claude/stats-cache.json` | só agregado (`totalMessages`, `dailyModelTokens`...). É **este** que infla 2,13x |
| `~/.claude/policy-limits.json` | vazio |
| `~/.claude/cache`, `sessions`, `telemetry` | nada |

**Conclusão: o Claude Code NÃO persiste `rate_limits` em disco. O dado é efêmero — nasce e morre no
stdin do hook.** Se a gente quer o número medido, alguém tem que se plugar naquele stdin. Não tem
jeitinho.

---

## 5. As quatro saídas, com o preço de cada uma

### D — Não fazer nada (é o que está no ar AGORA)
Claude entra como `derivado`. Reticulado, topo pontilhado, e a UI diz que é palpite.
**Escreve: nada. Risco: zero. Custo: o número do Claude é aproximado.**
*O app já faz isto e já é honesto fazendo. Não é um estado de erro — é um estado previsto.*

### A — Nosso binário embrulha o dele (wrapper)
Trocamos `statusLine.command` pelo nosso executável. Ele lê o stdin, guarda o `rate_limits` num
arquivo NOSSO, chama o `gsd-statusline.js` com o mesmo JSON e repassa o stdout dele intacto.
- **Escreve em `~/.claude/settings.json`** (1 chave).
- **Preço real:** viramos ponto único de falha da statusline dele. Se nosso binário travar ou demorar,
  a statusline do Jair some. E se o GSD atualizar o caminho do hook dele, nosso wrapper aponta pro vazio.
- Honesto dizer: é o mais poderoso e o mais invasivo.

### B — Uma linha no hook que ele já tem
O `gsd-statusline.js` já recebe o JSON inteiro. Uma linha nele despeja o `rate_limits` em
`~/Library/Application Support/MyTokens/rate_limits.json`. A gente só **lê** o nosso próprio arquivo.
- **Escreve em `~/.claude/settings.json`: NÃO.** Escreve uma linha no `gsd-statusline.js` — arquivo dele,
  mas mudança visível, mínima e reversível.
- **Preço real:** um update do GSD pode sobrescrever o arquivo e a linha some — em silêncio. Degrada
  pra `derivado` sozinho, o que é uma falha segura, mas o Jair não vai perceber.
- É a menos invasiva das que funcionam.

### C — Ir na API: `GET /api/oauth/usage`
Sem hook nenhum. Bearer OAuth do Keychain (`Claude Code-credentials`), host `api.anthropic.com`.
- **Escreve: nada em lugar nenhum.**
- **Preço real:** troca "mexer na config" por "**mexer no segredo**". Exige entitlement de rede
  (hoje o app não tem NENHUMA) e ler a credencial do Jair. A regra 1 (nunca logar token) passa a
  ser código de verdade, não boa intenção. E o endpoint **nunca foi chamado por ninguém** — o Sonda
  achou o path nas strings do binário e parou ali, com razão. É a opção mais limpa no papel e a mais
  arriscada na prática.

---

## 6. 🔴 O QUE EU PRECISO DE VOCÊ, JAIR

**Eu não vou escrever nada em `~/.claude` — nem uma linha, nem "só pra testar" — sem você mandar,
por escrito, qual das opções.** O app está funcionando na opção D neste momento.

Minha recomendação: **fica no D por enquanto**, e escolha entre A e B só quando o resto do app
estiver de pé. Motivos:
1. O app **já é honesto** sem hook. O reticulado não é um remendo — é o desenho.
2. A/B só valem se a gente estiver disposto a manter o acoplamento com o GSD, que é software de
   terceiro e muda sem avisar.
3. C envolve a credencial dele. Não encosto nisso sem uma conversa separada e específica.

Se você mandar A ou B, eu quero antes:
- um **backup** do `settings.json` (ou do `gsd-statusline.js`) feito por você, não por mim;
- um **caminho de desinstalação** testado, que devolva a config ao estado exato de antes;
- e o combinado de que a falha do hook **degrada pra `derivado`**, nunca pra tela em branco.

---

## 7. O que fica pro Sonda confirmar

- [ ] `used_percentage` é mesmo 0..100 (e não 0..1) no stdin real. A regra `= utilization * 100`
      veio das strings do binário, não de um payload observado.
- [ ] `five_hour` de fato some (chave ausente) em plano sem janela de 5h, ou vem com `null`?
- [ ] O Claude Code mata o hook em quanto tempo? (o `gsd-statusline.js` se protege com 3s — isso
      sugere que existe um teto, mas não achamos o número.)
