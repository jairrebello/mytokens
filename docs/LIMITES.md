# LIMITES POR PLANO

O que cada plano deixa gastar, e — mais importante — **em que unidade** o limite é medido.
Toda linha traz fonte + data. Onde a fonte oficial é vaga, digo `OBSERVADO (terceiros)` e nunca
apresento como fato. Onde não provei, escrevo `NÃO PROVADO`.

Consultado em: **2026-07-13**.

---

## Regra-mãe deste doc

Os três provedores **não publicam o denominador em tokens**. Eles entregam ao cliente um
**percentual de utilização (0..1)** de um orçamento que fica no servidor. Ou seja:

> O "restante" honesto = `100% − utilização`. NÃO é uma conta de tokens que a gente soma.
> A soma de tokens do disco serve pra **custo** e pra **fallback**, não pra "quanto sobra".

---

## 1. CLAUDE (Pro / Max 5x / Max 20x)

### Unidade — RESOLVIDO (crédito ao Sonda)
O limite tem **duas janelas**: **5 horas** (rolling) e **7 dias**. Ambas são expressas ao cliente
como **`utilization` (0..1)** — não em tokens, não em mensagens. O denominador (de QUANTO é a
utilização) é **server-side e NÃO publicado** pela Anthropic. Nem os docs oficiais, nem as strings
do binário trazem um número de token/mensagem por plano.

- Fonte oficial (confirma que existe limite, esconde o número):
  https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work
- Números de "prompts por janela" que circulam (ex.: Max 5x ~225/janela de 5h, Max 20x ~900) são
  **OBSERVADO (terceiros)**, aproximados e variam com tamanho de prompt/contexto/modelo. Proxy, não
  denominador. NÃO vão pra tela como fato.
  https://www.morphllm.com/claude-code-usage-limits

### Fonte do "restante" — a boa notícia (achado do Sonda, verificado por mim)
O restante do Claude **não precisa ser derivado de token**. Ele chega pronto:

- **Endpoint:** `GET /api/oauth/usage` — path confirmado nas strings do binário
  `@anthropic-ai/claude-code` v2.1.207.
- **Host:** `api.anthropic.com` — `PROVÁVEL`. O binário trata `api.anthropic.com` como o
  `firstPartyApi` (residency-gated) e é o host de 1ª parte; o path acima resolve contra ele.
  **Não chamei o endpoint** (não é preciso, e requisição autenticada foi barrada com razão).
- **Auth:** OAuth **Bearer** do token guardado no **Keychain do macOS**, item
  `svce="Claude Code-credentials"` (confirmei o nome do item; **nunca** li o segredo).
  Regra: esse token só serve pra `api.anthropic.com`, nunca é impresso/logado/escrito.
- **Fonte primária real = HEADERS de resposta HTTP** (achado do Sonda):
  `anthropic-ratelimit-unified-status`, `-reset`, `-overage-status`, `-overage-reset`,
  `-fallback`, `-upgrade-paths`, `-representative-claim`, `-overage-period-monthly-utilization`.

### Caminho recomendado pro MyTokens: statusLine hook (ZERO API, ZERO token)
O Claude Code **já entrega** a utilização no stdin do hook `statusLine`. Não precisa chamar API
nem tocar em credencial. Shape confirmado nas strings do binário:

```jsonc
// stdin do statusLine hook:
{
  "rate_limits": {
    "five_hour":  { "used_percentage": 0..100, "resets_at": <unix segundos> }, // Optional: 5-hour session limit (may be absent)
    "seven_day":  { "used_percentage": 0..100, "resets_at": <unix segundos> }  // Optional: 7-day weekly limit (may be absent)
  }
}
```

Objeto interno completo do `/api/oauth/usage` (chaves confirmadas pelo Sonda), cada uma
`{ utilization: 0..1, resets_at: <unix SEGUNDOS> }`:
`five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`, `seven_day_oauth_apps`.

> `used_percentage` = `utilization * 100`. `resets_at` é epoch em **segundos**.

**Hierarquia de fontes do "restante" do Claude:**
1. **statusLine hook** (`rate_limits.*.used_percentage`) — primário. Sem API, sem credencial.
2. **`GET /api/oauth/usage`** com OAuth Bearer do Keychain — secundário, se precisar de detalhe
   (opus/sonnet separados, overage) que o statusLine não traz.
3. **Derivar de token** (somar janela 5h/7d do disco vs. limite do plano) — **só FALLBACK**, e
   como o denominador não é publicado, esse fallback é aproximado e deve vir rotulado como tal.

### Plano do usuário — lê do disco, não pergunta (achado do Sonda)
`~/.claude/telemetry/1p_failed_events.*.json` → `event_data.additional_metadata` é base64 →
JSON com `subscription_type`. Nesta máquina: **`max`**. Também traz `organization_uuid` e
`account_uuid` em claro (tratar como PII: não logar/commitar).

### Custo client-side (achado do Sonda)
`tengu_api_success.additional_metadata` (base64) traz `costUSD` por request → existe tabela de
preço embutida no binário. Vale como **conferência cruzada** do nosso `data/pricing.json`, não como
fonte única (binário muda de versão sem aviso).

---

## 2. CODEX (ChatGPT Free / Plus / Pro / Business)

### Unidade — crédito, e o restante vem de bandeja no disco
Sistema é **credit-based** (créditos ≈ tokens ponderados por modelo), não message-based.
Janela **5h (rolling)** + **cap semanal (7 dias)**.

- Fonte: https://learn.chatgpt.com/docs/pricing (2026-07-13)
- **Mudança recente:** em **2026-07-12** a janela de 5h foi **removida** em Plus/Pro/Business;
  o **cap semanal** (reseta 7 dias após a 1ª mensagem da semana) **permanece**.
  https://explainx.ai/blog/chatgpt-codex-5-hour-limit-removed-weekly-reset-july-2026

Limites por plano (créditos por janela de 5h, quando a janela existia — OBSERVADO/oficial):
| Plano | Preço | GPT-5.6 Sol | Terra | Luna |
|---|---|---|---|---|
| Plus | $20/mês | 15–90 | 20–110 | 50–280 |
| Pro 5x | $100/mês | 5× o Plus | 5× | 5× |
| Pro 20x | $200/mês | 20× o Plus | 20× | 20× |
| Business | $20/assento | = Plus por assento | | |
| Free | $0 | acesso limitado | | |

Consumo típico: **5–40 créditos/mensagem** (varia com modelo/contexto/reasoning/tools).
Tarifa em crédito (ex. Terra): 62.5 in / 6.25 cached / 375 out por 1M tokens.

### Fonte do "restante" do Codex = DISCO (já mapeado em `fontes-de-dados`)
Não precisa API. O rollout jsonl entrega pronto:
`rate_limits.primary` (`window_minutes: 300` = 5h) e `rate_limits.secondary`
(`window_minutes: 10080` = 7 dias), cada um com `used_percent` + `resets_at`.
Isto é o **equivalente exato** ao `utilization` do Claude. Armadilha (do `fontes-de-dados`):
`used_percent` é snapshot → pegar o `token_count` mais recente entre **todas** as sessões
(ordenar por timestamp global).

---

## 3. CURSOR (Free / Pro / Teams / Enterprise)

### Unidade — DÓLAR de compute, não requests
Desde 2026 o Cursor mede em **$ de compute consumido**, não em nº de requests.

- Fonte: https://cursor.com/pricing (2026-07-13) — a página **não publica número** de request/crédito.
- **Pro ($20/mês):** inclui **$20 de créditos de uso/mês** para modelos frontier. Cada request
  debita o preço do provedor (ver `data/pricing.json`) do saldo. `OBSERVADO (terceiros)`: ~225
  Sonnet, ~550 Gemini, ~500 GPT-5 requests/mês, dependendo do modelo.
  https://www.cloudzero.com/blog/cursor-ai-pricing/
- **Modo Auto:** roteador da casa, **flat** ($1.25/M in, $6/M out) e no Pro **não consome** o
  crédito de $20 (efetivamente ilimitado).
- **Free (Hobby):** Agent/Tab limitados, sem número publicado.
- **Teams ($40/assento):** inclui analytics de uso + Admin API (ver `docs/CURSOR.md`).
- Plano nesta máquina, lido do disco (`state.vscdb`): `stripeMembershipType = pro`,
  `stripeSubscriptionStatus = active`.

### Fonte do "restante" do Cursor
Ver **`docs/CURSOR.md`**. Resumo: não há uso no disco; a conta **individual** depende de endpoint
autenticado do `cursor.com`, e a **Admin API** (`api.cursor.com`, `spendCents`) é **só time/enterprise**.

---

## Resumo pro `contrato-dados` / Sonda

| Provedor | "Restante" vem de | Unidade real | Precisa de credencial? |
|---|---|---|---|
| Claude | statusLine hook (1º) / `/api/oauth/usage` (2º) / derivar token (fallback) | `utilization` 0..1, janelas 5h + 7d | statusLine: **não**. Endpoint: OAuth do Keychain |
| Codex | disco (`rate_limits.primary/secondary`) | `used_percent`, janelas 5h + 7d | **não** |
| Cursor | endpoint autenticado cursor.com (individual) / Admin API (time) | **$** de compute vs. crédito do plano | **sim** (accessToken ou API key) |

**Denominador em tokens: NÃO PROVADO em nenhum dos três.** Os três só expõem % de utilização.
Somatório de token do disco = custo e fallback, nunca "quanto sobra".

---

# 4. STATUSLINE — O MECANISMO EXATO (Sonda, Fase 2)

Autor: **Sonda**. Detalha o §1 acima com o que foi extraído do binário
`/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (v2.1.207).
Responde ponto a ponto as 5 perguntas do Chassi.

> **NÃO ESCREVI NADA em `~/.claude`.** Tudo abaixo é leitura de binário + leitura de config.
> Nada foi executado. Onde não testei em runtime, está marcado.

## 4.0 ⚠️ A resposta mais importante primeiro (Chassi #5)

**NÃO existe lugar no disco onde o Claude Code persista `rate_limits`. Zero.**
Leitura passiva **não é possível**. Provas:

```bash
# 1. Nenhum arquivo de estado do Claude Code contém as chaves (só ruído de plugin/doc):
$ grep -rl -iE 'five_hour|seven_day|used_percentage|utilization' ~/.claude/ | grep -v '/projects/'
   -> só ~/.claude/plugins/**, cache/changelog.md, agents/*.md  (docs de terceiros, não estado)

# 2. Não existe sqlite/db nenhum:
$ find ~/.claude -type f \( -name '*.db' -o -name '*.sqlite*' \)
   -> vazio

# 3. Telemetria não carrega valor de rate limit (só o NOME de um evento):
$ cat ~/.claude/telemetry/*.json | grep -o -iE '"[a-z_]*(rate|limit|quota|remain|reset)[a-z_]*"' | sort | uniq -c
   7 "tengu_policy_limits_fetch"     # nome do evento. nenhum valor.

# 4. OTEL exporta token/custo, mas NENHUMA métrica de rate limit:
$ strings claude.exe | grep -oiE 'claude_code\.[a-z_.]*' | sort -u
   claude_code.token.usage, claude_code.cost.usage, ... -> nenhum rate_limit

# 5. O OUTPUT do statusLine (statusLineText) vive só em app-state. Nunca vai pra disco.
```

O CLI lê o rate limit dos **headers HTTP de resposta** (`anthropic-ratelimit-unified-*`) e
guarda **só em memória do processo**. Quando o processo morre, o dado morre.

**Corolário duro:** o `statusLine` é o único jeito de capturar isso sem rede — e ele
**exige escrever em `~/.claude/settings.json`**.

**MAS existe um caminho de ZERO ESCRITA em `~/.claude`** — não é o statusLine, é o endpoint:

| caminho | escreve em `~/.claude`? | precisa de rede? | precisa de credencial? | provado? |
|---|---|---|---|---|
| Ler arquivo de disco | — | — | — | ❌ **NÃO EXISTE** |
| **`GET /api/oauth/usage`** | ✅ **NÃO** | sim | OAuth do Keychain | ⚠️ path sim, resposta **NÃO PROVADA** |
| `statusLine` hook | ❌ **SIM** (settings.json) | não | não | ⚠️ **NÃO TESTADO em runtime** |

Item do Keychain **confirmado existir** (li só metadados, **nunca o segredo**):

```bash
$ security find-generic-password -s "Claude Code-credentials"
class: "genp"
    "acct"<blob>="jairrebello"
    "svce"<blob>="Claude Code-credentials"
```

**Recomendação ao Chassi:** se a meta é "não mexer na casa do Jair", o caminho é
**Keychain + `/api/oauth/usage`**, não o statusLine. Custo: um prompt do macOS pedindo
acesso ao Keychain (consentimento explícito do usuário, reversível, e não altera config
nenhuma). O statusLine só entra se o endpoint não servir.

## 4.1 Schema do settings (Chassi #1) — PROVADO

Schema zod extraído do binário, literal:

```js
statusLine: E.object({
  type:                 E.literal("command"),   // <- LITERAL. NÃO existe outro type.
  command:              E.string(),
  padding:              E.number().optional(),
  refreshInterval:      E.number().min(1).optional()
                         .describe("Re-run the status line command every N seconds in addition to event-driven updates"),
  hideVimModeIndicator: E.boolean().optional(),
})
```

Resposta direta: **sim**, a chave é `statusLine`, e `type` só aceita `"command"` — **não
existe outro tipo**. `padding` existe. E existem 2 campos que você não citou:
**`refreshInterval`** (segundos, ≥1) e `hideVimModeIndicator`.

Config atual do Jair (**ele JÁ TEM um statusLine** — ver §4.4):

```json
"statusLine": {
  "type": "command",
  "command": "\"/opt/homebrew/bin/node\" \"/Users/jairrebello/.claude/hooks/gsd-statusline.js\""
}
```

## 4.2 Invocação (Chassi #2) — PROVADO

**É event-driven, com debounce de 300ms. Polling é OPT-IN e vem desligado.**

Do binário:
- Dispara quando muda: `messageId` (ou seja, **a cada turno**), `permissionMode`, `vimMode`,
  `mainLoopModel`, `fastMode`, `effortValue`, `thinkingEnabled`, `prStatus`, e quando o
  próprio `command` muda.
- Debounce: `DK(() => { D() }, 300)` → **300ms**.
- Polling: `Jl(j, W !== undefined ? Math.max(1, W) * 1000 : null)` onde `W = refreshInterval`.
  **Sem `refreshInterval`, o segundo argumento é `null` → NÃO HÁ POLLING.**
- Timeout do comando: **5000ms** default (`pPs(e, t, r = 5000, ...)`).
- É **pulado** se: workspace trust não aceito, ou statusLine desabilitado.

**O que isso significa pro Chassi, e é a parte que morde:** o statusLine é um "push"
**confiável só ENQUANTO o Claude Code está rodando e ativo**. Fechou o Claude Code, a
fonte seca. O MyTokens vai ter que tratar isso como **cache com `asOf`** e mostrar a idade
do dado ("5h: 34% — visto há 12 min"), nunca como leitura ao vivo. Com `refreshInterval: 60`
ele reatualiza de minuto em minuto **com o app aberto** — e mesmo assim, só se houver
resposta de API nova pra mudar o número.

## 4.3 Payload no stdin (Chassi #3) — PROVADO (doc embutida no binário)

O comando recebe **um JSON no stdin**. Schema completo, copiado da doc que a própria
Anthropic embute no binário:

```jsonc
{
  "session_id": "string",        // Unique session ID
  "session_name": "string",      // Optional: set via /rename
  "prompt_id": "string",         // Optional: UUID do prompt (mesmo do OTel prompt.id)
  "transcript_path": "string",   // Path do transcript .jsonl  <- amarra com FONTES.md!
  "cwd": "string",
  "model": { "id": "string", "display_name": "string" },
  "workspace": {
    "current_dir": "string", "project_dir": "string", "added_dirs": ["string"],
    "git_worktree": "string",   // Optional
    "repo": { "host": "string", "owner": "string", "name": "string" }  // Optional
  },
  "version": "string",           // versão do Claude Code
  "output_style": { "name": "string" },

  "context_window": {
    "total_input_tokens":  number,   // tokens no contexto AGORA (incl. cache read/write)
    "total_output_tokens": number,
    "context_window_size": number,   // ex: 200000
    "current_usage": {               // null se não houver mensagem ainda
      "input_tokens": number, "output_tokens": number,
      "cache_creation_input_tokens": number, "cache_read_input_tokens": number
    } | null,
    "used_percentage":      number | null,
    "remaining_percentage": number | null
  },

  "effort":   { "level": "low"|"medium"|"high"|"xhigh"|"max" },  // Optional
  "thinking": { "enabled": boolean },

  // ====== O QUE NOS INTERESSA ======
  "rate_limits": {   // Optional: "Only present for subscribers AFTER FIRST API RESPONSE"
    "five_hour": {   // Optional: "5-hour session limit (may be absent)"
      "used_percentage": number,   // 0-100
      "resets_at":       number    // Unix epoch SEGUNDOS
    },
    "seven_day": {   // Optional: "7-day weekly limit (may be absent)"
      "used_percentage": number,   // 0-100
      "resets_at":       number    // Unix epoch SEGUNDOS
    }
  },

  "vim":      { "mode": "INSERT"|"NORMAL"|"VISUAL"|"VISUAL LINE" },  // Optional
  "agent":    { "name": "string", "type": "string" },                // Optional (--agent)
  "pr":       { "number": number, "url": "string", "review_state": "approved"|"pending"|"changes_requested"|"draft" },
  "worktree": { "name": "string", "path": "string", "branch": "string",
                "original_cwd": "string", "original_branch": "string" }
}
```

Respondendo suas perguntas exatas:
- **`rate_limits.five_hour.used_percentage`** → `number`, **0–100** (o CLI já fez `utilization * 100`).
- **`resets_at`** → **existe**, e é **Unix epoch em SEGUNDOS** (não ISO, não ms).
- **`session_id`, `cwd`, `model`** → todos presentes, no topo.
- **Bônus que você não pediu e vale ouro:** `context_window.used_percentage` (quanto do
  contexto da sessão foi consumido) e `transcript_path` — que **amarra o statusLine ao
  arquivo `.jsonl`** de `docs/FONTES.md`. Dá pra correlacionar rate limit ao gasto por sessão.

**⚠️ 3 armadilhas do payload:**
1. `rate_limits` é **Optional** e **"only present after first API response"**. Numa sessão
   recém-aberta, **ele não vem**. O parser tem que tolerar ausência — não pode assumir presença.
2. `five_hour` e `seven_day` são independentemente opcionais ("may be absent"). Trate um a um.
3. Não existe `seven_day_opus`/`seven_day_sonnet` **aqui**. Esses só aparecem no objeto interno
   / headers (§1). O statusLine expõe **só** `five_hour` e `seven_day`.

**NÃO PROVADO:** nunca vi um payload REAL com `rate_limits` preenchido — não executei o hook.
O schema acima é a doc do binário, não uma captura. **Chassi: valide na primeira execução.**

## 4.4 Convivência (Chassi #4) — o Jair JÁ TEM statusLine. Cuidado.

```bash
$ jq '.statusLine' ~/.claude/settings.json
{ "type": "command",
  "command": "\"/opt/homebrew/bin/node\" \"/Users/jairrebello/.claude/hooks/gsd-statusline.js\"" }
```

**Não existe encadeamento nativo.** O schema tem **um único** campo `command: string`.
Sobrescrever = **destruir o statusline do GSD dele**. Isso é inaceitável.

E não dá pra pegar carona: o `gsd-statusline.js` dele **não consome `rate_limits`** e não
persiste nada útil (`grep -nE 'rate_limits|five_hour|used_percentage' ~/.claude/hooks/gsd-statusline.js`
→ zero match). Ele lê o stdin (linha 301) mas ignora esse campo.

**Única saída honesta: wrapper que faz tee e repassa.** Pegadinhas reais:

1. **stdin só pode ser lido UMA vez.** O wrapper tem que **bufferizar o stdin inteiro** antes
   de qualquer coisa, e depois **reescrever esse buffer no stdin do comando original**.
2. **stdout tem que ser repassado byte a byte.** O que o original imprimir é o que a status
   line mostra. Nosso wrapper não pode adicionar nem uma quebra de linha.
3. **exit code** tem que ser propagado.
4. **timeout de 5s** é do Claude Code, e é pro wrapper INTEIRO — o tee tem que ser rápido.
   Escreva o cache de forma **não bloqueante e atômica** (write em tmp + `rename`), e
   **nunca** deixe o cache falhar derrubar o statusline do Jair (envolva em try/catch mudo).
5. **Se o comando original mudar** (o GSD atualiza), nosso wrapper fica apontando pra versão
   velha. Guarde o comando original em arquivo NOSSO e re-leia a cada execução.

Forma mínima e reversível:

```bash
#!/bin/sh
# mytokens-statusline-wrapper.sh — tee do payload, repassa tudo pro comando original.
# Reverter = restaurar settings.json.statusLine.command pro valor original. Uma linha.
set -e
PAYLOAD=$(cat)                                    # 1. bufferiza stdin UMA vez

# 2. tee atômico, silencioso, não-bloqueante. NUNCA derruba o statusline do usuário.
{ printf '%s' "$PAYLOAD" > "$HOME/.mytokens/ratelimits.json.tmp" \
  && mv -f "$HOME/.mytokens/ratelimits.json.tmp" "$HOME/.mytokens/ratelimits.json"; } 2>/dev/null || true

# 3. repassa o MESMO payload pro comando original, stdout byte a byte, exit code preservado.
printf '%s' "$PAYLOAD" | exec "/opt/homebrew/bin/node" "$HOME/.claude/hooks/gsd-statusline.js"
```

Config resultante (a **única** mudança em `~/.claude/settings.json`):

```json
"statusLine": {
  "type": "command",
  "command": "/Users/jairrebello/.mytokens/mytokens-statusline-wrapper.sh"
}
```

**Reversão = 1 campo string de volta ao valor original.** Guarde o valor antigo antes de
escrever. Idealmente: faça backup de `settings.json` inteiro e ofereça um botão "Desinstalar".

**REGRA:** o MyTokens **não escreve isso sem o Jair clicar em "instalar"**, com a config
antiga mostrada na tela e um botão de desfazer. Mexer na casa do usuário sem pedir é
exatamente o tipo de coisa que quebra a confiança no produto.

## 4.5 Ordem recomendada pro Chassi

1. **Tente `/api/oauth/usage` + Keychain primeiro.** Zero escrita em `~/.claude`. Se
   funcionar, o statusLine vira desnecessário. **Valide o formato da resposta** — é NÃO PROVADO.
2. **Se o endpoint não servir**, ofereça o statusLine como **opt-in explícito**, com wrapper
   (§4.4), backup e botão de desinstalar.
3. **Nunca** sobrescreva o `command` do Jair sem encadear.
4. Trate o número sempre como **cache com `asOf`**. Mostre a idade. A fonte seca quando o
   Claude Code fecha.
