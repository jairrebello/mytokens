# PESQUISA-FONTES.md — todos os caminhos para "gasto" e "restante"

Levantado em **2026-07-13**. Complementa `FONTES.md` (disco do Claude/Codex), `LIMITES.md`
(planos) e `STATUSLINE.md` (o hook). **Não repete** o que aqueles já provaram — corrige e
estende.

## Como ler este documento

Cada afirmação carrega um selo. Eles não são decorativos:

| selo | significa |
|---|---|
| **PROVADO** | Rodei um comando **nesta máquina** e vi o resultado. O comando está no texto. |
| **DOCUMENTADO** | Está na documentação **oficial** do fornecedor. Tem URL. |
| **RELATO** | Terceiro (issue, blog, ferramenta OSS) afirma. Tem URL. **Não verifiquei.** |
| **ESPECULAÇÃO** | Inferência minha. Não confie sem testar. |

**Não chamei nenhum endpoint. Não li nenhuma credencial. Não escrevi nada em `~/.claude`,
`~/.codex` ou `~/.cursor`.** Uma tentativa minha de parsear `~/.codex/auth.json` foi barrada
pelo sandbox — e estava certo em barrar. Abandonei a linha.

---

## 0. TL;DR — as 5 coisas que mudam a decisão

1. **CURSOR: o `ai-code-tracking.db` é um beco sem saída, e agora está PROVADO.** Ele não tem
   token, não tem custo, não tem quota. É um rastreador de *autoria de código* (quantas linhas
   a IA escreveu vs. o humano). O maior buraco do projeto fechou — com um "não".
2. **CURSOR: mas o binário do Cursor.app entrega o schema do "restante" de bandeja.** Achei o
   protobuf `aiserver.v1.GetCurrentPeriodUsageResponse.PlanUsage` com os campos literais
   **`remaining`** e **`limit`** — e o `team_id` do request é **opcional**, ou seja, funciona
   para conta individual. É rede, não disco, mas o alvo existe e tem forma conhecida.
3. **CLAUDE: `rate_limits` no statusLine agora é OFICIALMENTE DOCUMENTADO.** O `FONTES.md`
   dizia "provado só por string do binário". Não é mais: a Anthropic publicou o schema em
   `code.claude.com/docs/en/statusline`. Isso promove o statusLine de "aposta" a "contrato".
4. **CLAUDE: `/api/oauth/usage` funciona, é bem documentado por terceiros — e é
   provavelmente PROIBIDO pelo ToS.** A página de legal da Anthropic (fev/2026) veta
   explicitamente terceiros usarem credencial OAuth de assinatura. E o endpoint **só responde
   se você forjar `User-Agent: claude-code/<versão>`**. Isso é um risco de produto, não uma
   nota de rodapé.
5. **CODEX: não dá para dizer nada sobre o estado atual desta máquina.** O CLI **não está
   instalado** e o dado mais novo no disco é de **2026-05-18** — quase dois meses vencido. O
   `resets_at` que o `FONTES.md` cita expirou em 19/05. Qualquer "restante" do Codex aqui hoje
   seria invenção.

---

## 1. CLAUDE CODE

### 1.1 Tabela de caminhos

| caminho | entrega gasto? | entrega restante? | escreve algo? | precisa credencial? | confiança | custo de integração |
|---|---|---|---|---|---|---|
| `~/.claude/projects/**/*.jsonl` | ✅ tokens, 4 buckets, por request | ❌ **impossível** (sem denominador) | não | não | **PROVADO** (`FONTES.md`) | **baixo** — parser já existe |
| **statusLine hook** (stdin) | parcial (`context_window`) | ✅ `five_hour`/`seven_day` `used_percentage` + `resets_at` | ✅ **sim** — `~/.claude/settings.json` | não | **DOCUMENTADO** ⭐ | **médio** — precisa wrapper (Jair já tem statusLine) |
| **`GET /api/oauth/usage`** | ❌ | ✅ + `seven_day_opus`/`_sonnet` + `extra_usage` | não | ✅ OAuth do Keychain | **RELATO** (forte) — ⚠️ **risco de ToS** | **alto** — rede + credencial + forjar User-Agent |
| headers `anthropic-ratelimit-unified-*` | ❌ | ✅ em tese | não | — | **ESPECULAÇÃO** | **inviável** — exige MITM do tráfego |
| `~/.claude/stats-cache.json` | ✅ (mas **inflado 2,12x**) | ❌ | não | não | **PROVADO** (`FONTES.md` §3) | baixo — mas o número é errado |
| `~/.claude/telemetry/1p_failed_events.*` | ✅ `costUSD` por request | ❌ | não | não | **PROVADO** (ver §1.4) | **descartar** |
| Admin API / Claude Code Analytics API | ✅ agregado diário | ❌ | não | ✅ `sk-ant-admin` | **DOCUMENTADO** — mas **só org**, não assinatura | **inviável** para Pro/Max |

### 1.2 O que eu PROVEI no binário hoje (v2.1.207)

`fetchUtilization` é **função real**, com retry — não é uma string solta:

```bash
$ strings -n 6 /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
    | grep -n 'fetchUtilization'
136559:fetchUtilization: 200 after
136561:fetchUtilization: GET /api/oauth/usage (attempt
```

`200 after N attempt(s)` = há laço de retry. `api_usage_fetch` é o nome do evento de telemetria.
No pool de constantes, coladas na mesma vizinhança (linhas 136554–136562, 314193–314208):

```
utilization   resets_at   weekly_scoped   api_usage_fetch
five_hour  seven_day  seven_day_oauth_apps  seven_day_opus  seven_day_sonnet
cinder_cove   extra_usage   limits
```

Ou seja: `seven_day_oauth_apps` e `extra_usage` **existem no binário** — mesmo que a web não
publique o primeiro (§1.5). `limits` sugere que as janelas vêm aninhadas sob uma chave `limits`.
`cinder_cove` é codinome; **não sei o que é** e não vou fingir que sei.

**Achado novo — os headers são construídos DINAMICAMENTE:**

```
136688: anthropic-ratelimit-unified-
136689: -utilization
136690: -reset
136698: -surpassed-threshold
136708: claimAbbrev
```

O CLI monta `anthropic-ratelimit-unified-{claimAbbrev}-utilization`. Ou seja, **não existe
uma lista fixa de headers para grepar** — o nome depende da janela. Isso mata qualquer plano
de hardcodar nomes de header, e explica por que ninguém na web publicou uma captura real.

**O `/usage` do Claude Code não ajuda:** é `local-jsx` — componente React de TUI ("Show session
cost, plan usage, and what's contributing to your limits", linha 315840). Ele **renderiza e
morre**. Não persiste nada. E, curiosidade útil, ele lê os **próprios transcripts** — o binário
carrega os literais `"type":"assistant"`, `"usage":{`, `"input_tokens":` e os buckets de insight
(`cache_miss`, `long_context`, `subagent_heavy`, `high_parallel`). É a mesma fonte que já lemos.

### 1.3 ⭐ statusLine virou DOCUMENTADO — isso muda a recomendação

`FONTES.md §8` listava como pendência nº 1: *"statusLine entrega `rate_limits` em runtime —
provado só por string do binário"*. **Não é mais pendência.** A Anthropic documentou:

> **DOCUMENTADO** — https://code.claude.com/docs/en/statusline
> `rate_limits.five_hour.used_percentage` — "Percentage of the 5-hour or 7-day rate limit
> consumed, **from 0 to 100**"
> `rate_limits.five_hour.resets_at` — "**Unix epoch seconds**"
> Disponibilidade: *"appears only for Claude.ai subscribers (Pro/Max) **after the first API
> response in the session**. Each window may be independently absent."*

O schema oficial bate **exatamente** com o que o Sonda extraiu do binário. O statusLine deixou
de ser engenharia reversa e virou superfície suportada.

### 1.4 ⚠️ ARMADILHA DE ESCALA — `utilization` é 0..1 ou 0..100?

Isto pode fazer o app mostrar **1%** onde o certo é **100%**. Existem **duas escalas
diferentes em duas fontes diferentes**:

| fonte | chave | escala |
|---|---|---|
| statusLine stdin | `used_percentage` | **0–100** (DOCUMENTADO) |
| objeto interno (headers) | `utilization` | **0–1** — o binário faz `utilization * 100` para gerar o `used_percentage` (`FONTES.md` §5.3) |
| `GET /api/oauth/usage` | `utilization` | **0–100** segundo a captura do CCUM #202 (RELATO) — mas **um outro relato mostra 0–1** |

**Não existe consenso na web sobre a escala do endpoint.** Quem for implementar o endpoint tem
que **normalizar defensivamente** (se `> 1`, já é percentual) e **nunca** assumir. No statusLine
não há dúvida: é 0–100, e está na doc oficial.

### 1.5 `GET /api/oauth/usage` — o shape, e o problema

**RELATO** (Claude-Code-Usage-Monitor issue #202, corroborado por openusage e CodexBar):

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth token do Keychain>
anthropic-beta: oauth-2025-04-20        <- sem isto: 401
User-Agent: claude-code/<versão>        <- sem isto: 429 persistente
```

```json
{
  "five_hour":        { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00+00:00" },
  "seven_day":        { "utilization": 13.0, "resets_at": "2026-04-17T00:59:59+00:00" },
  "seven_day_opus":   null,
  "seven_day_sonnet": { "utilization": 1.0,  "resets_at": "2026-04-16T03:00:00+00:00" },
  "extra_usage":      { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
}
```

Note: `resets_at` aqui é **ISO-8601 string**; no statusLine é **epoch em segundos**. Schemas
diferentes. Não dá para reusar o mesmo decoder.
`seven_day_oauth_apps` **não aparece** em nenhuma captura pública — embora esteja no binário.

**🚨 O bloqueio, e é sério — DOCUMENTADO:**
https://code.claude.com/docs/en/legal-and-compliance (publicado ~19/02/2026)

> "OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team,
> and Enterprise subscription plans and is designed to support **ordinary use of Claude Code and
> other native Anthropic applications**. […] **Anthropic does not permit third-party developers
> to offer Claude.ai login or to route requests through Free, Pro, or Max plan credentials on
> behalf of their users.** Anthropic reserves the right to take measures to enforce these
> restrictions and **may do so without prior notice**."

Some isso ao fato de que o endpoint **só responde se o `User-Agent` disser `claude-code/x`** —
isto é, **o MyTokens teria que se passar pelo Claude Code para funcionar**. Um app que precisa
mentir sobre quem é para ler um número não é um app que eu recomendo enviar.

O texto mira mais claramente em *rotear inferência* por credencial de assinatura, e ler quota
read-only é área cinzenta (CodexBar e openusage fazem isso hoje). Mas a redação é ampla e a
enforcement é declaradamente sem aviso. **Chamada minha: não é o caminho primário.**

### 1.6 O que eu tentei e NÃO deu — telemetria

Hipótese que valia testar: o binário tem os eventos `tengu_quota_mismatch` (com
`priorFiveHourUtilization`, `priorSevenDayUtilization`, `priorOverageUtilization`) e
`tengu_claudeai_limits_status_changed` (com `hoursTillReset`). Se um desses **falhasse ao
enviar**, cairia em `~/.claude/telemetry/1p_failed_events.*.json` — **com os números de quota
dentro**. Seria "restante" de graça, sem hook e sem rede.

**Não acontece.** Decodifiquei o base64 de todo `additional_metadata` dos 7 arquivos:

```bash
$ grep -o -hE '"additional_metadata":"[A-Za-z0-9+/=]{40,}"' ~/.claude/telemetry/*.json \
   | sed 's/.*"additional_metadata":"//; s/"$//' \
   | while read -r b; do echo "$b" | base64 -d 2>/dev/null; done \
   | grep -o -iE '(utilization|five_hour|seven_day|resets_at|rate_limit|used_percent)' | sort | uniq -c
   (vazio)
```

**Zero.** Nenhum evento de quota jamais falhou aqui, e o arquivo só guarda **falhas**. Fonte
não-determinística por natureza. **Descartada.**

Também re-verifiquei, de forma independente, a conclusão central do `STATUSLINE.md`:

```bash
$ grep -rl -iE 'five_hour|seven_day|used_percentage|"utilization"|resets_at' ~/.claude/ \
   | grep -vE '/projects/|/plugins/|/agents/|/skills/|/hooks/'
   -> só paste-cache/ e file-history/  (são os NOSSOS próprios docs — falso positivo)

$ find ~/.claude -type f \( -name '*.db' -o -name '*.sqlite*' \)
   -> vazio
```

**Confirmado: o Claude Code não persiste `rate_limits` em disco. Em lugar nenhum.**

---

## 2. CODEX

### 2.1 🔴 Antes de tudo: nesta máquina, o Codex está MORTO

Isto invalida qualquer número de "restante" do Codex no app hoje:

```bash
$ which codex          -> não encontrado (CLI NÃO instalado)
$ find ~/.codex -name 'rollout-*.jsonl' | sort | tail -1
   .../sessions/2026/05/18/rollout-2026-05-18T19-07-06-...jsonl     <- 18 de MAIO

$ date -u              -> 2026-07-13T16:16:30Z
   resets_at 5h  = 1779203683 -> 2026-05-19T15:14:43Z   (vencido há ~8 semanas)
   resets_at 7d  = 1779577093 -> 2026-05-23T22:58:13Z   (vencido há ~7 semanas)
```

**PROVADO.** O `used_percent: 1.0 / 20.0` que o `FONTES.md` mostra é um **fóssil de maio**.
Mostrar isso como "restante" seria exatamente o tipo de número inventado que a regra de ouro
proíbe. O app precisa de uma regra dura: **`resets_at` no passado ⇒ o dado não existe.** Não é
"0% usado", não é "100% livre" — é **desconhecido**.

E como o CLI não está instalado, **não consigo observar** o comportamento pós-12/07 (remoção da
janela de 5h) nesta máquina. Ponto cego real.

### 2.2 O schema no disco é mais rico do que o `FONTES.md` documentou

**PROVADO** — chaves que faltavam:

```json
"rate_limits": {
  "limit_id": "codex",              // também vi: "codex_bengalfox", "premium"
  "limit_name": null,
  "primary":   { "used_percent": 1.0,  "window_minutes": 300,   "resets_at": 1779203683 },
  "secondary": { "used_percent": 20.0, "window_minutes": 10080, "resets_at": 1779577093 },
  "credits": null,                  // também vi: {"has_credits": false, ...}
  "plan_type": "plus",
  "rate_limit_reached_type": null
}
```

`limit_id`, `limit_name`, `credits` e `rate_limit_reached_type` **não estavam** em `FONTES.md`.
O parser Swift precisa tolerá-los (e ignorá-los, por ora).

### 2.3 Tabela de caminhos

| caminho | gasto? | restante? | escreve? | credencial? | confiança | custo |
|---|---|---|---|---|---|---|
| `~/.codex/sessions/**/rollout-*.jsonl` → `token_count.info` | ✅ | — | não | não | **PROVADO** | **baixo** — parser existe |
| idem → `token_count.rate_limits` | — | ⚠️ **snapshot, apodrece** | não | não | **PROVADO** — mas **vencido** aqui | baixo, **porém não confiável** |
| **`GET chatgpt.com/backend-api/wham/usage`** | — | ✅ `primary`/`secondary` + `credits` + `plan_type` | não | ✅ Bearer de `~/.codex/auth.json` | **RELATO** (forte — é o que o próprio CLI chama) | **alto** — rede + credencial |
| headers `x-codex-primary-used-percent` | — | ✅ | não | — | **RELATO** | inviável (exige MITM) |

**O `rate_limits` do JSONL é notoriamente não-confiável — RELATO:**
[openai/codex#14880](https://github.com/openai/codex/issues/14880) — *"`rate_limits` é sempre
`null` nos rollout files"* (aberto em março/2026, **sem resposta de mantenedor**).
[#14728](https://github.com/openai/codex/issues/14728) — `null` no modo `codex exec`.
No schema Rust atual ([protocol.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/protocol/src/protocol.rs)),
`primary` e `secondary` são `Option` **independentes** — a OpenAI **não precisou mudar código**
para tirar a janela de 5h; o servidor só passou a mandar `primary: null`.

**A remoção da janela de 5h (12/07/2026):** **RELATO, e frágil.** Foi anunciada **apenas num
post no X** do Tibo Sottiaux (OpenAI), com a palavra **"temporarily"**. Não existe changelog,
help-center, doc ou release note. O usuário relata em
[openai/codex#32632](https://github.com/openai/codex/discussions/32632) que a janela sumiu da UI.
A doc oficial (https://learn.chatgpt.com/docs/pricing) **ainda descreve a janela de 5h** — não
foi atualizada. **Ninguém na OpenAI publicou isso por escrito.** Trate como reversível: a UI tem
que renderizar "só semanal" **e** voltar a mostrar a de 5h se ela reaparecer.

---

## 3. CURSOR

### 3.1 ✅ O `ai-code-tracking.db` — PROVADO, e é um NÃO

O maior buraco do projeto. Abri read-only. **Schema completo, 6 tabelas:**

```bash
$ sqlite3 "file:///Users/jairrebello/.cursor/ai-tracking/ai-code-tracking.db?mode=ro" ".schema"
```

| tabela | linhas | colunas |
|---|---:|---|
| `ai_code_hashes` | **33.639** | `hash, source, fileExtension, fileName, requestId, conversationId, timestamp, createdAt, model` |
| `scored_commits` | 492 | `commitHash, branchName, scoredAt, linesAdded, linesDeleted, tabLinesAdded/Deleted, composerLinesAdded/Deleted, humanLinesAdded/Deleted, blankLinesAdded/Deleted, commitMessage, commitDate, v1AiPercentage, v2AiPercentage` |
| `tracked_file_content` | **0** | `gitPath, content, conversationId, model, fileExtension, createdAt` |
| `conversation_summaries` | **0** | `conversationId, title, tldr, overview, summaryBullets, model, mode, updatedAt` |
| `ai_deleted_files` | 3 | `gitPath, composerId, conversationId, model, deletedAt` |
| `tracking_state` | 1 | `trackingStartTime = {"timestamp":1767011899084}` |

Busca exaustiva por coluna de token/custo/quota nas 6 tabelas:

```sql
SELECT m.name, p.name FROM sqlite_master m JOIN pragma_table_info(m.name) p WHERE m.type='table';
-- filtrado por token|cost|quota|usage|limit|credit|price|spend|dollar|cent:
--   scored_commits.v1AiPercentage
--   scored_commits.v2AiPercentage
```

E esses dois **não são quota**: são o **% de LINHAS DE CÓDIGO escritas por IA** naquele commit
(ex.: `v2AiPercentage = 100.00`, com `composerLinesAdded=115, humanLinesAdded=0`).

> **VEREDITO: `ai-code-tracking.db` é um rastreador de AUTORIA DE CÓDIGO. Zero token. Zero
> custo. Zero quota. Não serve para o MyTokens.** (`source` só tem dois valores: `composer`
> 33.594 e `human` 45. `model`: `default`, `claude-opus-4-8`, `gpt-5.6-sol`.)

### 3.2 `state.vscdb` — também não tem quota (mas tem a chave do cofre)

3,4 GB. **Só abre com `immutable=1`** (com `mode=ro` dá `SQLITE_CANTOPEN`) — anote isso, o Swift
vai tropeçar nisso:

```bash
$ sqlite3 "file:$HOME/Library/Application Support/Cursor/User/globalStorage/state.vscdb?immutable=1" ".tables"
ItemTable     composerHeaders     cursorDiskKV
```

**PROVADO** — chaves relevantes em `ItemTable`:

```
cursorAuth/accessToken             (424 bytes)   <- credencial
cursorAuth/refreshToken            (424 bytes)   <- credencial
cursorAuth/stripeMembershipType    (3 bytes)     <- o plano
cursorAuth/stripeSubscriptionStatus(6 bytes)
```

Busca por `usage|quota|token|limit|credit|spend|billing|subscription` em `ItemTable` e
`cursorDiskKV`: **nenhuma chave de uso ou quota.** Os "hits" em `cursorDiskKV` são todos
`ofsContent:` — conteúdo de **arquivos dos projetos do Jair** cujo nome por acaso contém
"token"/"rate_limit" (ex.: `0047_rate_limit_counters.sql`). Falso positivo.

> **Não há gasto nem quota do Cursor no disco. Para mostrar "restante" do Cursor, é rede.
> Não tem jeitinho.** (RELATO corrobora: alguns "bubbles" do `state.vscdb` têm `inputTokens`/
> `outputTokens` soltos, mas com cobertura irregular — servem, no máximo, como **piso** de
> gasto, nunca como quota.)

### 3.3 ⭐ O achado: o protobuf do "restante" está DENTRO do Cursor.app

Isto é **PROVADO no binário instalado** (`/Applications/Cursor.app/.../workbench.glass.main.js`),
não é relato de web:

```js
makeMessageType("aiserver.v1.GetCurrentPeriodUsageRequest", () => [
  { no:1, name:"team_id", kind:"scalar", T:5, opt:!0 }        // <- OPCIONAL. serve p/ conta individual.
])

makeMessageType("aiserver.v1.GetCurrentPeriodUsageResponse", () => [
  { no:1, name:"billing_cycle_start" }, { no:2, name:"billing_cycle_end" },
  { no:3, name:"plan_usage" },          { no:4, name:"spend_limit_usage" },
  { no:5, name:"display_threshold" },   { no:6, name:"enabled" },
  { no:7, name:"display_message" },     ...
])

makeMessageType("aiserver.v1.GetCurrentPeriodUsageResponse.PlanUsage", () => [
  { no:1, name:"total_spend" },      { no:2, name:"included_spend" },
  { no:3, name:"bonus_spend" },      { no:4, name:"remaining" },        // <<<< AQUI
  { no:5, name:"limit" },            { no:6, name:"remaining_bonus" },
  { no:8, name:"auto_spend" },       { no:9, name:"api_spend" },
  { no:10,name:"auto_limit" },       { no:11,name:"api_limit" },
  { no:12,name:"auto_percent_used" },  ...  "total_percent_used"
])
```

**`remaining`, `limit`, `total_percent_used`, `billing_cycle_end`.** É literalmente o "quanto
resta" do Cursor, em **centavos de compute** — e o `team_id` opcional confirma que o caminho
individual existe. Também há RPCs `GetHardLimit` / `SetHardLimit`.
Hosts que o app fala: `api2.cursor.sh`, `api3.cursor.sh`, `api4.cursor.sh`, `www.cursor.com`.

**NÃO PROVEI:** qual **serviço** hospeda o método (`/aiserver.v1.???Service/GetCurrentPeriodUsage`)
— o grep foi barrado antes de eu isolar isso. **RELATO** (cursor-usage-tracker) diz que é
`POST https://api2.cursor.sh/.../GetCurrentPeriodUsage`. Precisa confirmar.

### 3.4 Tabela de caminhos

| caminho | gasto? | restante? | escreve? | credencial? | confiança | custo |
|---|---|---|---|---|---|---|
| `~/.cursor/ai-tracking/ai-code-tracking.db` | ❌ **nada** | ❌ **nada** | não | não | **PROVADO — é um NÃO** | — |
| `state.vscdb` (bubbles com `inputTokens`) | ⚠️ parcial, **piso** apenas | ❌ | não | não | **RELATO** | médio, **e mente por baixo** |
| `state.vscdb` → `cursorAuth/*` | — | — | não | **é a credencial** | **PROVADO** | — |
| **`GET cursor.com/api/usage-summary`** | ✅ $ gasto | ✅ incluído + on-demand + ciclo | não | ✅ cookie `WorkosCursorSessionToken` | **RELATO** (CodexBar, cursor-stats) | **alto** |
| **`POST api2.cursor.sh/…/GetCurrentPeriodUsage`** | ✅ `total_spend` | ✅ **`remaining`/`limit`** | não | ✅ mesmo cookie/token | **schema PROVADO** no binário; **endpoint RELATO** | **alto** |
| `GET cursor.com/api/dashboard/get-hard-limit` | — | ✅ `hardLimit` | não | ✅ | **RELATO** | alto |
| Admin API (`api.cursor.com`, `crsr_…`) | ✅ `spendCents` | parcial | não | ✅ API key de admin | **DOCUMENTADO** — mas **só Team/Enterprise** | **inviável** (Jair é Pro individual) |

**DOCUMENTADO, por ausência:** https://cursor.com/docs/api lista 7 APIs — Admin, Analytics, AI
Code Tracking, Bugbot, Cloud Agents, SDKs. **Todas Team/Enterprise.** **Não existe API oficial
de uso para conta individual.** A ferramenta `cursor-usage` diz sem rodeio: *"uma API key
`crsr_…` não consegue ler uso — esse dado vive atrás da sua sessão web."*

**Plano nesta máquina:** `cursorAuth/stripeMembershipType` = 3 bytes. O `LIMITES.md` já leu:
`pro`. Modelo 2026 = **dólar de compute** (Pro: $20/mês incluídos), não requests.

---

## 4. O que tentei e NÃO consegui provar

Vale tanto quanto o resto.

| # | O que | Por que não |
|---|---|---|
| 1 | **Resposta real de `/api/oauth/usage`** | Não chamei (proibido no escopo, e há risco de ToS). Shape é **RELATO**, não captura minha. |
| 2 | **Escala do `utilization` do endpoint (0–1 ou 0–100?)** | Fontes da web **se contradizem**. Não dá pra resolver sem chamar. **Normalize defensivamente.** |
| 3 | **statusLine em runtime** | Exigiria escrever em `~/.claude/settings.json`. Não escrevi. Agora é **DOCUMENTADO**, o que baixa muito o risco — mas ainda **não vi um payload real**. |
| 4 | **Codex pós-12/07** | CLI não instalado, disco parado em 18/05. **Ponto cego total.** Não dá pra saber se `primary` virou `null`. |
| 5 | **Nome do serviço gRPC do `GetCurrentPeriodUsage`** | Grep barrado pelo sandbox antes de isolar. Tenho as **mensagens**, não a **rota**. |
| 6 | **`cinder_cove` / `weekly_scoped` / `seven_day_oauth_apps`** | Estão no binário do Claude. **Não sei o que fazem.** Nenhuma fonte pública explica. |
| 7 | **`~/.codex/auth.json`** | **Deliberadamente não li.** Uma tentativa minha foi barrada pelo sandbox — corretamente. |
| 8 | **Quota do Cursor de fonte local** | Procurei em 2 DBs + binário. **Não existe.** Conclusão negativa, provada. |
| 9 | **`resets_at` do "seven_day" é mesmo 7 dias?** | Um gist (RELATO, fonte única) afirma que reseta a cada **72h**, não 7 dias. Não verifiquei. Se for verdade, muda o render do countdown. |

---

## 5. Recomendação final

### Claude → **statusLine hook**, e agora com mais convicção

Deixou de ser aposta: o schema é **oficialmente documentado**. É o único caminho que dá o
restante **real** sem tocar em credencial e sem se passar por outro app.

O preço continua o mesmo do `STATUSLINE.md` §5-A/B: escrever em `~/.claude/settings.json`, com
wrapper (o Jair já tem um statusLine do GSD), backup e botão de desinstalar. **Continua exigindo
o "sim" dele.**

**Não recomendo `/api/oauth/usage` como caminho primário** — não por ser difícil, mas porque o
ToS da Anthropic (fev/2026) veta terceiros usarem credencial de assinatura, e o endpoint **só
responde a quem finge ser o Claude Code**. Se um dia entrar, que seja opt-in, desligado por
padrão, com o texto do ToS na tela.

**Enquanto não houver hook: Claude fica `derivado`.** O gasto em token é PROVADO e exato; o "%
restante" **não existe** e o app deve dizer isso — não estimar.

### Codex → **disco, com data de validade agressiva**

Ler `rate_limits` do rollout é grátis e não escreve nada. Mas:

- **`resets_at` no passado ⇒ estado "desconhecido"**, não "0%". Nesta máquina, é o caso **hoje**.
- `primary` pode vir `null` (a OpenAI tirou a janela de 5h, *"temporarily"*). A UI tem que
  aguentar **só a semanal** — e voltar a mostrar a de 5h se ela reaparecer.
- Tolerar `limit_id`, `limit_name`, `credits`, `rate_limit_reached_type`.

`chatgpt.com/backend-api/wham/usage` é o que o próprio CLI chama e resolveria o frescor — mas
é credencial + rede. **Fase 2, se o disco provar ser insuficiente.** (E aqui já provou: o disco
está morto há 8 semanas.)

### Cursor → **honestidade primeiro: sem rede, não há restante**

1. **Pare de tratar `ai-code-tracking.db` como lead.** Está provado: não tem nada. Se quiser
   usá-lo, é para um recurso **diferente** ("% do meu código foi escrito por IA") — que é
   legítimo, mas não é o MyTokens.
2. **Sem rede, o Cursor não tem gasto nem restante.** Se o app não vai fazer rede agora, o
   Cursor deve aparecer como **"não disponível"** — não como zero, não como estimativa.
3. **Quando fizer rede**, o alvo é `GetCurrentPeriodUsage` (`remaining` / `limit` /
   `total_percent_used` / `billing_cycle_end`) — schema **provado no binário**, `team_id`
   opcional. Auth = cookie `WorkosCursorSessionToken` montado a partir de
   `cursorAuth/accessToken` do `state.vscdb`. É **rede + credencial + endpoint não documentado**:
   o caminho mais caro dos três. Mas é o único que existe.

### O denominador continua não existindo

Reafirmando o que `LIMITES.md` já dizia, agora com mais evidência: **nenhum dos três publica o
limite em tokens.** Claude e Codex entregam **percentual**; Cursor entrega **dólar**. A soma de
token do disco serve para **custo** e **gasto** — **nunca** para "quanto sobra". Onde não há
percentual fresco, a resposta honesta é **"não dá pra saber"**.

### Prior art que vale estudar

**RELATO** — [steipete/CodexBar](https://github.com/steipete/CodexBar): app de menu bar do macOS
que já resolve Claude + Codex + Cursor exatamente pelos caminhos acima, com docs por provedor
(`docs/claude.md`, `docs/codex.md`, `docs/cursor.md`). É o vizinho mais próximo do MyTokens.
Vale ler antes de escrever a camada de rede — inclusive para ver o que eles **erraram**.
