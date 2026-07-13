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
