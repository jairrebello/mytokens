# CURSOR — de onde sai o uso

Risco nº 1 do projeto. Investigado e **RESOLVIDO** em **2026-07-13**. Resumo de uma linha:

> **O Cursor não guarda uso no disco.** Mas o `cursor.com/api/usage-summary`, autenticado com a
> sessão que o próprio Cursor mantém em `state.vscdb`, devolve o número — CONFIRMADO AO VIVO. É o
> primeiro (e único) collector de REDE do app.

> ## ✅ IMPLEMENTADO — `MyTokensCore/CursorCollector.swift`
>
> Autorizado pelo Jair ("reusar a sessão local"). O endpoint que a FRENTE B abaixo listava como
> "não confirmado" foi **provado ao vivo** — e é mais simples que o supunha: não são os
> `dashboard/get-monthly-invoice`, é **um GET** em `cursor.com/api/usage-summary`.
>
> **Response real (13/07):**
> ```jsonc
> { "billingCycleEnd": "2026-07-30T...",     // → resetsAt
>   "membershipType": "pro",
>   "individualUsage": { "plan": {
>     "breakdown": { "included": 2000 },      // → capUSD = US$ 20 (centavos)
>     "totalPercentUsed": 16.44 } } }         // → usedPercent. É o que o Cursor MOSTRA.
> ```
> Vira **uma** `LimitWindow`: mês corrente, `source: .measured`, `unit: .usd`, `capUSD: 20`.
> Na tela: **"Cursor · Mês — US$ 3,29 / 20"**, tinta sólida.
>
> **Segurança (o que o código garante, não promete):** o accessToken sai do `state.vscdb`
> READONLY+immutable, fica só em memória, e vai num header `Cookie` para `cursor.com` e mais lugar
> nenhum. Zero `print`/log/telemetria no CursorCollector (verificado por grep no CI mental). Falha
> em qualquer passo → "sem dado local", honesto.
>
> **Limitação conhecida:** o Cursor muda por REDE, não por disco — o FSEvents não acorda por causa
> dele. Ele atualiza (a) no boot, (b) sempre que o refresh dispara por Claude/Codex, (c) quando o
> usuário abre o popover (`refreshOnOpen`). TTL de 5 min segura a rede. Se o usuário passa horas SÓ
> no Cursor com a tela fechada, o número pode ficar até 5 min velho na próxima abertura — aceitável.
>
> **Fragilidade:** `usage-summary` é endpoint interno, sem contrato. Se o Cursor mudar, o teste
> `ParserTests → "Cursor: totalPercentUsed..."` grita, e a pista degrada pra "sem dado" (nunca
> mente). O schema fixado no teste é o retrato de 13/07.

O texto abaixo é a investigação ORIGINAL, de antes de o endpoint ser confirmado. Fica como
registro do caminho — a FRENTE B previa `dashboard/*`; o que funcionou foi `usage-summary`.

---

## FRENTE A — `~/.cursor/ai-tracking/ai-code-tracking.db` (180MB) — VEREDITO: sem ouro

Aberto **READONLY + immutable** (`file:...?mode=ro&immutable=1`), como manda `regras-repo` §3.

### Tabelas e contagem (nesta máquina)
| Tabela | Linhas | O que é |
|---|---|---|
| `ai_code_hashes` | 33.639 | hash de trecho de código escrito por IA (atribuição) |
| `scored_commits` | 492 | commits com contagem de linhas add/del por autoria |
| `ai_deleted_files` | 3 | arquivos deletados atribuídos a IA |
| `tracked_file_content` | 0 | (vazio) |
| `conversation_summaries` | 0 | (vazio) |
| `tracking_state` | 1 | só `{"trackingStartTime":{"timestamp":...}}` |

### Schema real (colunas que importam)
```sql
ai_code_hashes(hash PK, source, fileExtension, fileName, requestId,
               conversationId, timestamp, createdAt, model)
scored_commits(commitHash, branchName, scoredAt, linesAdded, linesDeleted,
               tabLinesAdded, tabLinesDeleted, composerLinesAdded, composerLinesDeleted,
               humanLinesAdded, humanLinesDeleted, blankLinesAdded, blankLinesDeleted,
               commitMessage, commitDate, v1AiPercentage, v2AiPercentage, PK(commitHash,branchName))
tracked_file_content(gitPath PK, content, conversationId, model, fileExtension, createdAt)
tracking_state(key PK, value)
```

### Tem token? Tem custo? — **NÃO**
Grep por `token|cost|usage|price|credit|quota|spend|dollar|cent` em **todo** o schema: **zero**
ocorrência (o único falso-positivo foi `v1AiPercentage` — o "cent" de *Percentage*, não centavos).
`source` só assume `composer` / `human`. `model` traz `default`, `gpt-5.6-sol`, `claude-opus-4-8`.
Janela dos dados nesta máquina: 2026-06-11 → 2026-07-10.

**Conclusão:** este DB responde "quantas linhas a IA escreveu / % de código IA por commit". **Não**
responde "quantos tokens gastei / quanto custou / quanto sobra". Para o MyTokens: **descartar como
fonte de uso/custo.** (Poderia virar um card lateral "% de código IA", fora de escopo agora.)

---

## FRENTE B — API do `cursor.com` (uso da conta INDIVIDUAL)

### O que existe no disco (só nomes de chave — segredo nunca é lido)
`state.vscdb` → tabela `ItemTable`, chaves `cursorAuth/*`:
`accessToken`, `refreshToken`, `cachedEmail`, `cachedScopedProfile`, `cachedSignUpType`,
`onboardingDate`, `stripeMembershipType` (=`pro`), `stripeSubscriptionStatus` (=`active`).

### O accessToken serve? — SIM, é sessão pro cursor.com
Decodifiquei **só o payload** do JWT, em memória, com `sub`/`randomness` redigidos
(**o token nunca foi impresso, logado ou escrito**). Payload:
```jsonc
{
  "sub": "<google-oauth2|user-id>",   // REDIGIDO
  "randomness": "<REDIGIDO>",
  "time": "1783721477",
  "iat/exp": "...",                    // exp ~ 2026-09-08 (sessão de ~60 dias)
  "iss": "https://authentication.cursor.sh",
  "aud": "https://cursor.com",         // <-- token é feito pra falar com cursor.com
  "scope": "openid profile email offline_access",
  "type": "session"
}
```
`alg: HS256`. `aud = https://cursor.com` confirma: é credencial de sessão do próprio site — usá-la
contra `cursor.com` respeita `regras-repo` §2 (só domínio oficial do provedor).

### Como autentica
O cliente do Cursor manda um **cookie de sessão**, não `Authorization: Bearer`. Formato observado:
```
Cookie: WorkosCursorSessionToken=<sub>%3A%3A<accessToken>
```
(`%3A%3A` = `::`). Endpoints candidatos de dashboard individual (mesma família que a UI web usa):
```
GET  https://cursor.com/api/auth/me
POST https://cursor.com/api/dashboard/get-monthly-invoice   { month, year, includeUsageEvents }
POST https://cursor.com/api/dashboard/get-hard-limit        { }
```

### STATUS DE VERIFICAÇÃO — honesto: **NÃO CONFIRMADO ao vivo**
Não bati nesses endpoints. A chamada autenticada foi **barrada pelo classificador de segurança**
(ler token de auth + mandar pra rede) — e está certo em barrar. Portanto:
- Shape do request acima = **PROVÁVEL** (baseado no formato de cookie/endpoints públicos do Cursor),
  **não** um response real capturado por mim.
- **Antes de codar isso no app**, validar o response uma vez com a conta do usuário.
- Endpoints internos de dashboard **não são contrato estável** — Cursor muda sem aviso. Tratar como
  best-effort, com fallback (Frente C / plano B).

> Requisito de segurança pro app: essa chamada só pode sair no runtime do MyTokens, do disco do
> usuário direto pra `cursor.com`, token vindo do Keychain/vscdb, **nunca** impresso/logado/telemetria.

---

## FRENTE C — Admin API oficial (`api.cursor.com`)

**Só funciona em plano de TIME / Enterprise. DITO ALTO E CLARO: um usuário Pro individual não tem.**

- Doc: https://cursor.com/docs/account/teams/admin-api (2026-07-13)
- Auth: **Admin API key** gerada em *Settings → Team → API Keys* (existe só em conta de time).
- Endpoint de gasto: `POST https://api.cursor.com/teams/spend`
  → devolve por membro: `spendCents`, `fastPremiumRequests`, `name`, `email`, `role`,
  `hardLimitOverrideDollars`, `subscriptionCycleStart`, `totalMembers`, `totalPages`.
- Também: usage events diários/filtrados por período (edições, uso de IA, taxa de aceite).

**Para o usuário-alvo do MyTokens (Pro individual): NÃO SE APLICA. Não forçar.**

---

## PLANO B HONESTO (o que o app faz de verdade)

Ordem de tentativa, do melhor ao mais honesto-vazio:

1. **Tem conta de time + Admin API key?** → Admin API (`api.cursor.com/teams/spend`), `spendCents`
   é o gasto direto em $. Melhor fonte. Pedir a key ao usuário (colar → Keychain).
2. **Conta individual, sessão válida no vscdb?** → tentar `cursor.com/api/dashboard/*` com o cookie
   de sessão. **Validar o response antes de confiar.** Se responder, mostrar $ gasto vs. crédito
   do plano (Pro = $20/mês, ver `docs/LIMITES.md`).
3. **Nada disso?** → card honesto: **"Cursor: sem dado local — conecte sua conta"** com botão que
   dispara (1) ou (2). Nunca um número inventado. (`regras-repo` §5, regra de ouro do `fontes-de-dados`.)

**PROIBIDO INVENTAR:** se o usuário não colar API key nem tiver sessão utilizável, a resposta certa é
"precisa conectar a conta, e o fluxo é este" — não é um número estimado. Melhor card vazio honesto do
que gráfico bonito e falso.

---

## Apêndice — como reproduzir a leitura do DB com segurança
```bash
# READONLY + immutable: não cria WAL, não toca no arquivo-fonte (regras-repo §3)
sqlite3 "file:$HOME/.cursor/ai-tracking/ai-code-tracking.db?mode=ro&immutable=1" \
  "SELECT type,name,sql FROM sqlite_master ORDER BY type,name;"
```
`state.vscdb` é 3.2GB — abrir igual (`?mode=ro&immutable=1`) e **só** ler nomes de chave / campos
não-sensíveis (`stripeMembershipType`, `stripeSubscriptionStatus`). **Nunca** selecionar o valor de
`cursorAuth/accessToken` nem `refreshToken` pra stdout/arquivo.
