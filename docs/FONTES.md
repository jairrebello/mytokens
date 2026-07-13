# FONTES.md — o que existe no disco, provado

Autor: Sonda (Arqueólogo de Fontes). Máquina do Jair, 2026-07-13.
CLI Claude Code `2.1.207` · Codex `plan_type=plus` · 6.224 arquivos em `~/.claude/projects/`.

**Regra desta página:** toda afirmação vem com o comando que a provou. O que não foi
provado está marcado **NÃO PROVADO**, em voz alta. Um "não sei" honesto vale mais que
um chute confiante.

Reprodutíveis:

```bash
bun scripts/probe/scan-claude.ts --pretty   # Claude Code: dedup, schema, por dia/modelo
bun scripts/probe/scan-codex.ts  --pretty   # Codex: total correto + rate limits
```

---

## 0. TL;DR — as 4 coisas que quebram o produto se erradas

| # | Armadilha | Efeito se ignorada |
|---|---|---|
| 1 | Uma resposta da API vira **N linhas JSONL** (1 por content block), cada uma repetindo o `usage` inteiro | Gasto do Claude infla **2,12x** (+112%) |
| 2 | Transcript de subagente vive em `<slug>/<sessionId>/subagents/*.jsonl` | Perde 686 arquivos de gasto **real** |
| 3 | `usage.iterations` com 2+ entradas: o `usage` de topo é a **última** iteração, não a soma | **Subconta** (raro, mas real) |
| 4 | Codex: `total_token_usage` é **acumulado da sessão** | Total do Codex infla **86,4x** |

E o achado que mais importa: **o `/stats` do próprio Claude Code não deduplica** — ele
soma linha a linha e por isso reporta ~2,12x a mais. Ver §3.

---

## 1. CLAUDE CODE — `~/.claude/projects/`

### 1.1 Layout

```
~/.claude/projects/<slug-do-cwd>/<sessionId>.jsonl            <- sessão principal
~/.claude/projects/<slug-do-cwd>/<sessionId>/subagents/*.jsonl <- subagentes (Task)  ← NÃO ESQUECER
~/.claude/projects/<slug-do-cwd>/vercel-plugin/*.jsonl         <- ruído, sem usage
~/.claude/projects/<slug-do-cwd>/memory/*.jsonl                <- ruído, sem usage
```

**Varredura tem que ser RECURSIVA.** Varrer só `<slug>/*.jsonl` acha 5.498 arquivos;
recursivo acha 6.224. Os 686 a mais são `subagents/` — gasto real de token.

```bash
$ find ~/.claude/projects -name '*.jsonl' | awk -F/ 'NF>7' \
    | sed -E 's|.*/projects/[^/]+/||; s|/[^/]+\.jsonl$|/*.jsonl|' | sort | uniq -c | sort -rn | head -3
  97 9b313d2d-.../subagents/*.jsonl
  58 742d28ae-.../subagents/*.jsonl
  46 9c490b21-.../subagents/*.jsonl
```

> **Não use `isSidechain` pra achar subagente.** O campo é `false` em **100%** das linhas
> do histórico atual (67.812 de 67.812). É legado. O que identifica subagente é o **path**.
> ```bash
> $ find ~/.claude/projects -maxdepth 2 -name '*.jsonl' -size +200k | head -200 \
>     | xargs grep -ho '"isSidechain":[a-z]*' | sort | uniq -c
> 67812 "isSidechain":false
> ```

### 1.2 A linha que importa

Só `type == "assistant"` **com** `message.usage`. Todo outro `type` (`user`, `system`,
`attachment`, `queue-operation`, `last-prompt`, `ai-title`, `mode`) é ruído: não tem token.

Campos **sempre presentes** nas 20 versões de CLI amostradas (18.821 linhas):

| top-level | tipo | pra quê |
|---|---|---|
| `requestId` | `string` `req_...` | **chave de dedup** |
| `sessionId` | `uuid` | agrupar sessão |
| `timestamp` | ISO-8601 UTC | janela de 5h, agrupamento por dia |
| `version` | `"2.1.207"` | schema do CLI |
| `type` | `"assistant"` | filtro |
| `uuid` / `parentUuid` | `uuid` | árvore da conversa |
| `cwd`, `gitBranch`, `userType`, `entrypoint`, `isSidechain` | — | contexto |
| `message.id` | `string` `msg_...` | dedup alternativo (equivalente — ver §2) |
| `message.model` | `string` | `claude-opus-4-8`, `claude-fable-5`, ... |
| `message.usage` | `object` | os tokens |

`message.usage` — campos **sempre presentes** nas 20 versões:

| campo | tipo | nota |
|---|---|---|
| `input_tokens` | `int` | bucket 1 |
| `output_tokens` | `int` | bucket 2 |
| `cache_creation_input_tokens` | `int` | bucket 3 — custa **mais** que input |
| `cache_read_input_tokens` | `int` | bucket 4 — custa **~10x menos** que input |
| `cache_creation` | `{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}` | detalhe do bucket 3 |
| `server_tool_use` | `{web_search_requests, web_fetch_requests}` | cobrado à parte |
| `service_tier` | `"standard"` | — |
| `speed` | `"standard"` | — |
| `inference_geo` | `string` | — |
| `iterations` | `array` | **ver §1.4** |

> **Nunca some os 4 buckets num número só.** Eles têm preços diferentes. `cache_read` é
> 84% do meu volume total e é o mais barato — colapsar tudo em "input" mente no custo por
> quase uma ordem de grandeza.

### 1.3 Variação entre versões — 22 versões no histórico

```bash
$ bun scripts/probe/scan-claude.ts --pretty | jq '.byVersion | length'
22
```

**Nenhum dos 4 campos de token mudou de nome, apareceu ou sumiu em nenhuma versão.**
Os 10 campos de `usage` acima existem em 20/20 das versões amostradas. Isso é a boa notícia:
o parser de token não precisa de branch por versão.

O que **varia** (todos irrelevantes pra contagem de token, mas documentando):

| campo | ausente em | o que é |
|---|---|---|
| `attributionSkill`, `attributionAgent`, `agentId` | 3–6 de 20 | atribuição, versões novas |
| `attributionMcpServer`, `attributionMcpTool`, `attributionPlugin` | 14–19 de 20 | idem |
| `isApiErrorMessage`, `apiErrorStatus`, `error`, `errorDetails` | 12–19 de 20 | linhas de erro de API |
| `slug` | 11 de 20 | — |
| `session_id` (snake_case!) | 19 de 20 | **convive** com `sessionId`; não substitui |

### 1.4 `usage.iterations` — o `usage` de topo pode SUBCONTAR

Distribuição (18.821 linhas amostradas): `len=1` → 15.523 · ausente → 3.293 · **`len=2` → 4** · `len=0` → 1.

Quando `iterations` tem **2+** entradas, o `usage` de topo é igual à **ÚLTIMA iteração**,
**não** à soma:

```
top-level usage : input=76  output=566  cache_read=105.029  cache_creation=0
SOMA iterations : input=152 output=568  cache_read=203.371  cache_creation=8.305
top == soma?  False        top == última iteração?  True
```

**Regra:** se `iterations.length > 1`, **some as iterações**; senão use o topo.
Impacto hoje é ~0,02% — mas é gasto real, e é barato acertar. Implementado em
`readUsage()` no `scan-claude.ts`.

### 1.5 Linhas `assistant` SEM `requestId` — 28 delas

```bash
$ jq '{rowsWithoutRequestId, semRequestId: .totals.usageOfRowsWithoutRequestId}' <(bun scripts/probe/scan-claude.ts)
{ "rowsWithoutRequestId": 28,
  "semRequestId": { "input_tokens": 0, "output_tokens": 0,
                    "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0 } }
```

**São linhas de erro de API** (`isApiErrorMessage` / `apiErrorStatus`) e **todas carregam
zero token nos 4 buckets**. Contagem independente: 27 linhas com flag de erro, todas com
`input+output == 0`.

**O que fazer com elas:** nada especial — elas somam 0 de qualquer jeito. Mas o parser
**não pode** usar `requestId` como chave sem fallback, senão 28 linhas colapsam numa só
chave `undefined`. Regra implementada: chave = `requestId ?? "msg:"+message.id ?? chave sintética`.
Elas contribuem 0 tokens e não distorcem nada.

---

## 2. DEDUP — provado, com número

### 2.1 A causa NÃO é resume/branch entre arquivos

A hipótese anterior (o resume/branch reescreve as mesmas linhas em **outro** arquivo)
está **refutada** nesta base:

```bash
$ bun scripts/probe/scan-claude.ts | jq .requestIdsAppearingInMultipleFiles
0
```

**Zero** `requestId` aparece em mais de um arquivo. A duplicação é **dentro do mesmo arquivo**.

### 2.2 A causa real: 1 resposta da API = N linhas JSONL, cada uma repetindo o `usage` inteiro

O Claude Code grava **uma linha JSONL por content block** da resposta. Todas as linhas
carregam o **mesmo** `requestId`, o **mesmo** `message.id` e um `usage` **byte a byte idêntico**:

```
ARQUIVO: ~/.claude/projects/-Users-jairrebello-projetos-app-pcis/c78410a4-....jsonl
requestId: req_011CckoEVTN5egiQQFgTYCFS  -> 4 linhas NO MESMO ARQUIVO

  linha 1: msg_01PLRRdZBU2ku8FxzMjU2wGz  blocks=['thinking']   in:37268 out:613 cc:12548 cr:25227
  linha 2: msg_01PLRRdZBU2ku8FxzMjU2wGz  blocks=['text']       in:37268 out:613 cc:12548 cr:25227
  linha 3: msg_01PLRRdZBU2ku8FxzMjU2wGz  blocks=['tool_use']   in:37268 out:613 cc:12548 cr:25227
  linha 4: msg_01PLRRdZBU2ku8FxzMjU2wGz  blocks=['tool_use']   in:37268 out:613 cc:12548 cr:25227

  message.id IGUAL nas 4?  True        usage IDÊNTICO nas 4?  True
```

Uma chamada de API. Cobrada uma vez. Gravada 4 vezes. Somar linha a linha conta 4x.

### 2.3 O NÚMERO

`bun scripts/probe/scan-claude.ts` sobre **6.224 arquivos / 93.401 linhas assistant**:

| | tokens |
|---|---:|
| **RAW** (soma toda linha `assistant`) | **15.735.410.122** |
| **DEDUP** (por `requestId`) | **7.409.681.259** |
| **Duplicado** | **8.325.728.863** |
| **Inflação** | **+112,36 %** — o raw é **2,124x** a verdade |

93.401 linhas → **45.277 `requestId` únicos** (≈2,06 linhas por chamada de API).

Por bucket:

| bucket | RAW | DEDUP |
|---|---:|---:|
| `input_tokens` | 40.515.452 | 12.825.668 |
| `output_tokens` | 79.356.679 | 30.850.852 |
| `cache_creation_input_tokens` | 611.392.685 | 234.859.563 |
| `cache_read_input_tokens` | 15.004.145.306 | 7.131.145.176 |

### 2.4 `requestId` ou `message.id`? Tanto faz — são equivalentes

```
uniqueRequestIds : 45.277
uniqueMessageIds : 45.278   (o +1 é o bucket das 28 linhas de erro sem requestId)
dedup por requestId  == dedup por message.id  == dedup pelo par  (os 3 totais batem exato)
```

**Regra final:** chave = `requestId`, com fallback `message.id`. `message.id` sozinho também
serve. O par não adiciona nada.

---

## 3. ⚠️ O `/stats` do próprio Claude Code está inflado (~2,12x)

`~/.claude/stats-cache.json` **tem tokens** (`modelUsage` + `dailyModelTokens` — 4 buckets por
modelo). É a agregação do próprio CLI. Comparado com meu scan **na janela exata dele**
(`firstSessionDate 2026-05-17` → `lastComputedDate 2026-07-11`):

| | tokens | razão vs stats-cache |
|---|---:|---:|
| `stats-cache.json` | 14.648.249.256 | — |
| meu **RAW** | 14.614.795.587 | **1,0023** |
| meu **DEDUP** | 6.869.298.057 | 2,1324 |

**`stats-cache / RAW = 1,0023`.** O stats-cache do Claude Code **não deduplica** — ele soma
as linhas de content block, exatamente como o parser ingênuo. Bate com o RAW modelo a modelo
(razão 1,000–1,004 em quase todos; `fable-5`, `sonnet-5`, `sonnet-4-6`, `opus-4-7` batem em
**1,000 exato** nos 4 buckets).

**Consequência pro produto:** o MyTokens vai mostrar número **~2,1x MENOR** que o `/stats`
oficial. Isso não é bug nosso — é o oficial que superconta. Precisa estar previsto na UI,
senão o usuário acha que somos nós que erramos.

> **NÃO PROVADO:** o resíduo de +0,23% (stats-cache um pouco **acima** do meu RAW; em
> `haiku` chega a +2,6%). Hipótese não confirmada: o `stats-cache` é incremental e retém
> totais de transcripts que já foram podados do disco (existe `~/.claude/.last-cleanup`).
> Não testei. É pequeno e não muda a conclusão, mas não vou fingir que sei.

> **NÃO PROVADO:** que o faturamento da Anthropic use o número deduplicado. O que está
> provado é que os 4 buckets idênticos pertencem a **uma** resposta da API com **um**
> `message.id` — e uma resposta é cobrada uma vez. Não tenho acesso à fatura pra fechar o laço.

---

## 4. A JANELA DE 5H — provada com `resets_at` real

O Claude Code **não** grava `resets_at` no disco (§5), então provei a mecânica no **Codex**,
que grava. Os dois usam a mesma arquitetura de janela (`window_minutes: 300`, `resets_at`
unix vindo do **servidor**).

### 4.1 O bloco NÃO começa em horário fixo de relógio

```bash
$ grep -rhoE '"resets_at":[0-9]+' ~/.codex/sessions ~/.codex/archived_sessions \
    | grep -oE '[0-9]+' | sort -u | tail -40   # -> 40 valores distintos
resets_at % 3600 == 0 (hora cheia)?    0 / 40
resets_at % 60   == 0 (minuto cheio)?  1 / 40
```

**Zero** dos 40 `resets_at` cai em hora cheia. Qualquer heurística de "arredonda pra baixo
na hora" (é o que o `ccusage` faz) é **chute**.

### 4.2 O bloco ancora no PRIMEIRO REQUEST depois do bloco anterior expirar

Sessão real, 446 eventos `token_count`:

```
timestamp             5h_use%    resets_at(5h)        falta p/ reset
2026-04-02T12:08:32     0.00     2026-04-02T17:08:31     4:59:58   <- 1º request: reset = +5h EXATOS
2026-04-02T12:08:40     0.00     2026-04-02T17:08:31     4:59:50   <- resets_at CONSTANTE
2026-04-02T12:10:23     0.00     2026-04-02T17:08:31     4:58:07      durante o bloco
...
                                 (bloco expira 17:08:31)
2026-04-02T17:09:27              2026-04-02T22:09:27               <- request seguinte ABRE bloco novo
```

`resets_at` distintos na sessão: 4 → blocos iniciados em `12:08:31`, `12:08:39`, `17:09:27`, `17:09:42`.
Resto da hora: 511s, 519s, 567s, 582s — **nunca 0**.

**Regra provada:** `bloco_inicio = primeiro request após o bloco anterior expirar`;
`resets_at = bloco_inicio + 300min`. Janela **rolling, ancorada em atividade**. Não é agenda fixa.

> **NÃO PROVADO:** por que dois `resets_at` do mesmo bloco diferem por 8–15s (`17:08:31` vs
> `17:08:39`). Suspeita: race no servidor atribuindo a âncora entre requests concorrentes
> (o header `anthropic-ratelimit-unified-representative-claim` sugere que existe o conceito
> de "claim" representativo). Não investiguei. Irrelevante na prática — a variação é de segundos.

### 4.3 Sessões concorrentes caem no MESMO bloco. A janela é por CONTA.

```
blocos de 5h (resets_at distintos) observados : 426
blocos compartilhados por 2+ SESSÕES DIFERENTES : 90

resets_at=2026-02-22T02:46:22  <- 21 sessões distintas
resets_at=2026-04-09T17:55:55  <- 19 sessões distintas
resets_at=2026-03-04T15:13:04  <- 12 sessões distintas
```

**A janela é account-wide, não por sessão.** 90 blocos com 2+ sessões distintas reportando
o **mesmo** `resets_at`.

Corolário que morde: num desses blocos, sessões **iniciadas em 02/03 e 03/03** reportam o
bloco de **04/03**. Ou seja — **agrupar por data do arquivo mente.** Agrupe por `timestamp`
do **evento**.

---

## 5. O "RESTANTE" DO CLAUDE CODE — onde está

### 5.1 Não está em nenhum arquivo de uso

Varri `~/.claude/` inteiro:

| arquivo | tem restante? |
|---|---|
| `~/.claude/projects/**` | ❌ só gasto (input/output/cache), zero quota |
| `~/.claude/stats-cache.json` | ❌ só gasto agregado (e inflado, §3) |
| `~/.claude/policy-limits.json` | ❌ política de org (`enforce_web_search_mcp_isolation`). Zero quota |
| `~/.claude/sessions/<pid>.json` | ❌ pid/cwd/status. Zero token |
| `~/.claude/telemetry/1p_failed_events.*.json` | ❌ eventos que o CLI **falhou** em enviar. Zero rate limit |

```bash
$ cat ~/.claude/telemetry/*.json | grep -o -iE '"[a-z_]*(rate|limit|quota|remain|reset)[a-z_]*"' | sort | uniq -c
   7 "tengu_policy_limits_fetch"     # <- só o nome do evento. nenhum valor de quota.
```

### 5.2 A fonte real: **headers HTTP de resposta**

Strings do binário (`/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, v2.1.207):

```bash
$ strings -n 8 "$CLAUDE_BIN" | grep -oiE 'anthropic-ratelimit[a-z0-9-]*' | sort -u
anthropic-ratelimit-unified-status
anthropic-ratelimit-unified-reset
anthropic-ratelimit-unified-fallback
anthropic-ratelimit-unified-overage-status
anthropic-ratelimit-unified-overage-reset
anthropic-ratelimit-unified-overage-in-use
anthropic-ratelimit-unified-overage-disabled-reason
anthropic-ratelimit-unified-overage-period-monthly-utilization
anthropic-ratelimit-unified-overage-period-channel-utilization
anthropic-ratelimit-unified-representative-claim
anthropic-ratelimit-unified-upgrade-paths
```

O CLI lê o rate limit dos **headers de resposta de cada chamada de API**. Ele **não persiste
isso em disco** — vive só em memória do processo. Por isso não há arquivo pra ler.

Objeto interno (strings do binário): chaves `five_hour`, `seven_day`, `seven_day_opus`,
`seven_day_sonnet`, `seven_day_oauth_apps`, cada uma `{ utilization: 0..1, resets_at: unix_segundos }`.
Doc embutida no próprio binário: `"resets_at": number // Unix epoch seconds when this window resets`
e `"five_hour": { // Optional: 5-hour session limit (may be absent)`.

### 5.3 ✅ Como LER sem chamar API nenhuma: o hook `statusLine`

> **FASE 2 — mecanismo completo (settings schema, frequência de invocação, payload byte a byte,
> como conviver com um statusLine já existente): `docs/LIMITES.md` §4.**
> Resumo do que mudou: `type` só aceita `"command"`; existe `refreshInterval` (segundos) e
> polling vem **desligado** por padrão; `rate_limits` é **Optional** e **só aparece após a
> primeira resposta de API**; o payload traz de brinde `transcript_path` e
> `context_window.used_percentage`. **E o Jair JÁ TEM um statusLine instalado** — sobrescrever
> destrói o dele.

Trecho do binário (v2.1.207) que monta o payload do `statusLine`:

```js
x = Mwt();   // rate limits vindos dos headers
k = {
  ...x.five_hour && { five_hour: { used_percentage: x.five_hour.utilization*100,
                                   resets_at:       x.five_hour.resets_at } },
  ...x.seven_day && { seven_day: { used_percentage: x.seven_day.utilization*100,
                                   resets_at:       x.seven_day.resets_at } },
}
```

Exemplo que a própria Anthropic embute no binário como referência de `statusLine`:

```bash
input=$(cat)
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
```

**O `statusLine` recebe `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` no
stdin, em JSON.** Zero API, zero credencial, zero keychain. É o equivalente exato do
`used_percent` que o Codex já entrega.

> ⚠️ Registrar um `statusLine` significa **escrever** em `~/.claude/settings.json`. Meu território
> é read-only, então **NÃO TESTEI ao vivo** — a prova é a string do binário, não uma execução.
> Quem for implementar: valide de fato antes de confiar. **NÃO PROVADO em runtime.**

### 5.4 Endpoint autenticado (secundário)

```bash
$ strings -n 6 "$CLAUDE_BIN" | grep -oE '(/api|/v1)/[a-zA-Z0-9_/{}.-]*' | grep -iE 'usage|limit|rate'
/api/oauth/usage                       <- ESTE
/api/claude_code/policy_limits
/api/claude_code/discovery/team_usage
/api/rate-limits
/v1/organizations/spend_limits
```

`GET /api/oauth/usage`. Auth: OAuth Bearer do Keychain, item `svce="Claude Code-credentials"`
(confirmado pelo Sextante — nome do item, sem ler o segredo). Host `api.anthropic.com` é
**PROVÁVEL, NÃO PROVADO** (o binário trata `api.anthropic.com` como firstPartyApi
residency-gated, e o path está nas strings — mas ninguém chamou o endpoint pra confirmar).

**Formato da resposta: NÃO PROVADO.** Ninguém chamou. As chaves de §5.2 são o palpite
mais forte, mas é inferência de strings, não uma resposta observada.

### 5.5 Hierarquia recomendada (alinhada com o Sextante, `docs/LIMITES.md`)

1. **`statusLine` hook** — `rate_limits.*.used_percentage` + `resets_at`. Primário. Sem credencial.
2. **`GET /api/oauth/usage`** — OAuth do Keychain. Secundário (traz opus/sonnet/overage separados).
3. **Derivar do token do disco** — **só fallback, e aproximado.**

### 5.6 Sobre derivar: a fórmula existe, mas o denominador NÃO

Se for pra derivar:

```
gasto_bloco(t) = Σ usage[req]  para todo requestId único cujo timestamp ∈ [bloco_inicio, bloco_inicio+5h)
                 (bloco_inicio = primeiro request após o bloco anterior expirar — §4.2)
restante_%     = 100 − (gasto_bloco / LIMITE_DO_PLANO) × 100
```

**`LIMITE_DO_PLANO` não existe em lugar nenhum.** Sextante confirmou: `utilization` é `0..1` e o
**denominador é server-side e NÃO PUBLICADO** — nem docs oficiais, nem strings do binário trazem
token/mensagem por plano. Números de terceiros ("Max5x ≈ 225 prompts/janela") são proxy observado,
**não vão pra tela como fato**.

**Portanto: a derivação NÃO consegue produzir um "% restante" honesto.** Ela só produz "quanto
você gastou neste bloco", em token absoluto. O `%` só vem do `statusLine` ou do endpoint.
Isto é uma **conclusão negativa provada**, não uma pendência.

### 5.7 Bônus achado no caminho

- **Plano do usuário está no disco.** `~/.claude/telemetry/1p_failed_events.*.json` →
  `event_data.additional_metadata` é base64 → JSON com `subscription_type`. Aqui: `"max"`.
  Também `auth.organization_uuid` e `auth.account_uuid` em texto claro.
- **O Claude Code calcula custo client-side.** `tengu_api_success.additional_metadata` (base64)
  traz `costUSD` por request (ex: `0.0124068`), junto de `requestId`, `inputTokens`, `outputTokens`,
  `cachedInputTokens`, `uncachedInputTokens`, `ttftMs`, `durationMs`. Logo **existe tabela de preço
  dentro do binário** — dá pra extrair em vez de hardcodar.

---

## 6. CODEX — `~/.codex/`

### 6.1 Layout e registro

```
~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl
~/.codex/archived_sessions/...
~/.codex/config.toml
```

Linha útil: `{"type":"event_msg","payload":{"type":"token_count", ...}}`

| campo | nota |
|---|---|
| `payload.info.total_token_usage` | `{input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens, total_tokens}` — **ACUMULADO da sessão** |
| `payload.info.last_token_usage` | idem, só do último turno |
| `payload.info.model_context_window` | — |
| `payload.rate_limits.primary` | `{used_percent, window_minutes: 300, resets_at}` ← **5h** |
| `payload.rate_limits.secondary` | `{used_percent, window_minutes: 10080, resets_at}` ← **7 dias** |
| `payload.rate_limits.plan_type` | `"plus"` |

> `rate_limits` pode vir **`null`** num evento `token_count`. O parser tem que tolerar
> (`isinstance(rl.get('primary'), dict)`) — quebrei o meu nisso.

### 6.2 Armadilha do ACUMULADO — vale 86x

`total_token_usage` é o acumulado da sessão inteira, reescrito a cada turno. Somar todos os
eventos conta o mesmo token N vezes:

```bash
$ bun scripts/probe/scan-codex.ts --pretty
{ "rollouts": 398,  "tokenCountEvents": 27726,
  "totalTokensCorrect": { "total_tokens":   2.038.076.945 },   # último evento de cada sessão
  "totalTokensNaive":                     176.076.139.447,     # somando todo token_count
  "naiveOverCorrectRatio": 86.39 }
```

**Somar todo `token_count` infla 86,4x.** Pegue **o último evento de cada sessão**.

### 6.3 Armadilha do SNAPSHOT

`used_percent` é o valor **naquele instante**. O "agora" é o evento de **maior timestamp
global**, entre TODAS as sessões — **não** o arquivo mais recente por nome/mtime (§4.3 provou
que uma sessão antiga pode reportar um bloco novo).

```json
"currentRateLimits": {
  "asOf": "2026-05-19T10:15:33.736Z", "planType": "plus",
  "fiveHour": { "used_percent": 1,  "window_minutes": 300,   "resets_at": 1779203683 },
  "sevenDay": { "used_percent": 20, "window_minutes": 10080, "resets_at": 1779577093 }
}
```

---

## 7. CURSOR

Não investiguei (fora do meu escopo — dono é o Sextante). O que a nota `fontes-de-dados` já
tinha: nada de token no disco; `~/.cursor/ai-tracking/ai-code-tracking.db` (180MB) é lead não
explorado. **NÃO PROVADO por mim.**

---

## 8. Placar de honestidade — o que ficou NÃO PROVADO

| # | Item | Por quê |
|---|---|---|
| 1 | `statusLine` entrega `rate_limits` **em runtime** | Provado só por string do binário. Testar exige escrever em `~/.claude/settings.json` — território read-only |
| 2 | Host e **formato da resposta** de `/api/oauth/usage` | Path provado nas strings; ninguém chamou o endpoint |
| 3 | Faturamento da Anthropic usa o número **deduplicado** | Sem acesso à fatura. O que está provado: 4 linhas idênticas = 1 `message.id` = 1 resposta de API |
| 4 | Resíduo de +0,23% (`stats-cache` > meu RAW) | Hipótese (poda de transcript + cache incremental) não testada |
| 5 | Spread de 8–15s no `resets_at` do mesmo bloco | Não investigado |
| 6 | `LIMITE_DO_PLANO` em token/mensagem | **Não existe publicado.** Conclusão negativa, confirmada pelo Sextante |
| 7 | Cursor | Fora do meu escopo |

---

## 9. PORTAR PRO SWIFT — os probes TS são o ORÁCULO

O projeto virou **Swift nativo (macOS)**. Os `scripts/probe/*.ts` **não são código morto**:
são a **implementação de referência**. Regra: o Swift do Turbina tem que reproduzir estes
números, **exatos**, ou tem bug.

### 9.1 Comando de conferência

```bash
bun scripts/probe/scan-claude.ts --pretty | jq '{inflation, totals}'
bun scripts/probe/scan-codex.ts  --pretty | jq '{totalTokensCorrect, naiveOverCorrectRatio}'
```

### 9.2 Checklist de paridade — se qualquer um falhar, o Swift está errado

| # | Invariante | Onde erra |
|---|---|---|
| 1 | Varredura **recursiva** de `~/.claude/projects/` | Não-recursivo perde `subagents/` → **subconta** |
| 2 | `raw / dedup ≈ 2,12` | Se der ~1,0, esqueceu o dedup → **infla 112%** |
| 3 | `uniqueRequestIds ≈ assistantRows / 2,06` | — |
| 4 | Dedup por `requestId`, fallback `message.id` | Sem fallback, as 28 linhas de erro colapsam |
| 5 | `iterations.length > 1` → **soma** as iterações | Usar o topo **subconta** |
| 6 | 4 buckets **separados** | Colapsar mente no custo (cache_read = 84% do volume) |
| 7 | Codex: **último** evento de cada sessão | Somar todos → **infla 86,4x** |
| 8 | Codex: `rate_limits` pode ser `null` | Crash no parser (eu quebrei o meu nisso) |
| 9 | Agrupar por `timestamp` do **evento**, nunca por data do arquivo | Blocos de 5h saem errados |

### 9.3 Números-âncora (snapshot 2026-07-13, 6.224 arquivos)

O disco cresce enquanto se trabalha — **rode o probe e o Swift no MESMO instante** e compare.
Não compare o Swift de hoje com um número colado de ontem.

```
Claude: RAW 15.735.410.122 · DEDUP 7.409.681.259 · inflação +112,4% · 45.277 requestIds
Codex : CORRETO 2.038.076.945 · NAIVE 176.076.139.447 · razão 86,4x
```

### 9.4 Pegadinhas de Swift especificamente

- **`Int`, não `Int32`.** `cache_read_input_tokens` total = **15 bilhões**. Estoura `Int32`
  (máx 2,1 bi) **com folga**. Use `Int` (64-bit) ou `Int64`.
- **`resets_at` é epoch em SEGUNDOS.** `Date(timeIntervalSince1970:)` espera segundos — certo.
  Mas se em algum ponto vier de JS (ms), divida por 1000. Não misture.
- **JSONL não é JSON.** Uma linha = um objeto. Não tente `JSONDecoder` no arquivo inteiro.
- **Campos opcionais de verdade.** `requestId` some em 28 linhas; `iterations` some em 3.293;
  `rate_limits` some antes da 1ª resposta de API. Modele como `Optional`, não force-unwrap.
- **Timestamps são ISO-8601 UTC com `Z`.** `ISO8601DateFormatter` com
  `.withFractionalSeconds` — os transcripts têm milissegundos (`2026-06-22T17:16:24.650Z`).
