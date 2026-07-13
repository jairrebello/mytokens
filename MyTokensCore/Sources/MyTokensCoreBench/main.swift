// Bench/relatório do core contra o disco REAL. É o que confere número com o probe do Sonda.
//   swift run -c release mtcore-bench
//   swift run -c release mtcore-bench --json   (pra diff automático contra o probe)

import Foundation
import MyTokensCore

let jsonOut = CommandLine.arguments.contains("--json")

func log(_ s: String) { if !jsonOut { print(s) } }

func money(_ d: Decimal) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.groupingSeparator = "."
    f.decimalSeparator = ","
    return f.string(from: d as NSDecimalNumber) ?? "\(d)"
}

func n(_ i: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "."
    return f.string(from: NSNumber(value: i)) ?? "\(i)"
}

func ms(_ t: TimeInterval) -> String { String(format: "%.0f ms", t * 1000) }

let pricing = try PricingTable.bundled()
log("pricing.json: \(pricing.modelIDs.count) modelos, gerado em \(pricing.generatedAt ?? "?")\n")

// ---------- CLAUDE ----------
let claude = ClaudeCodeCollector(pricing: pricing)

let t0 = DispatchTime.now()
let c1 = try await claude.collectDetailed()
let fullScan = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9

// refresh incremental: nada mudou (ou quase nada) -> só stat() nos arquivos.
let t1 = DispatchTime.now()
let c2 = try await claude.collectDetailed()
let incScan = Double(DispatchTime.now().uptimeNanoseconds - t1.uptimeNanoseconds) / 1e9

let d = c1.diagnostics

// Custo SEM dedup: reprecifica os buckets crus, pra mostrar o tamanho da mentira.
let rawCost = pricing.cost(model: "claude-opus-4-8", tokens: d.rawBuckets) ?? 0
let dedupCost = c1.events.reduce(Decimal(0)) { $0 + $1.costUSD }

log("""
========== CLAUDE CODE ==========
arquivos ............... \(n(d.files))
linhas assistant ....... \(n(d.assistantRows))
requestIds únicos ...... \(n(d.uniqueRequestIds))

TOKENS
  SEM dedup (raw) ...... \(n(d.rawTokens))
  COM dedup ............ \(n(d.dedupTokens))
  duplicado ............ \(n(d.rawTokens - d.dedupTokens))
  inflação ............. \(String(format: "%.4f", d.inflationRatio))x  (+\(String(format: "%.1f", (d.inflationRatio - 1) * 100))%)

BUCKETS (com dedup)
  input ................ \(n(d.dedupBuckets.input))
  output ............... \(n(d.dedupBuckets.output))
  cache-write .......... \(n(d.dedupBuckets.cacheWrite))   (5m: \(n(d.dedupBuckets.cacheWrite5m ?? 0)) / 1h: \(n(d.dedupBuckets.cacheWrite1h ?? 0)))
  cache-read ........... \(n(d.dedupBuckets.cacheRead))

BUCKETS (sem dedup)
  input ................ \(n(d.rawBuckets.input))
  output ............... \(n(d.rawBuckets.output))
  cache-write .......... \(n(d.rawBuckets.cacheWrite))
  cache-read ........... \(n(d.rawBuckets.cacheRead))

CUSTO (USD, preço por modelo, 4 buckets)
  COM dedup ............ $\(money(dedupCost))
  SEM dedup (só p/ ver o tamanho do erro, tudo a preço de opus-4-8) ... $\(money(rawCost))

modelos sem preço ...... \(d.unpricedModels.isEmpty ? "nenhum" : d.unpricedModels.sorted().joined(separator: ", "))

TEMPO
  scan completo ........ \(ms(fullScan))   (\(n(Int(d.scan.bytesRead / 1_048_576))) MB lidos, \(d.scan.filesReparsed) arquivos parseados)
  refresh incremental .. \(ms(incScan))   (\(c2.diagnostics.scan.filesUnchanged) inalterados, \(c2.diagnostics.scan.filesAppended) cresceram, \(c2.diagnostics.scan.filesReparsed) reparseados)
""")

// custo por modelo
log("\nCUSTO POR MODELO (com dedup)")
let byModel = Aggregator.byModel(c1.events)
for (model, spend) in byModel.sorted(by: { $0.value.tokens > $1.value.tokens }) {
    log("  \(model.padding(toLength: 28, withPad: " ", startingAt: 0)) \(n(spend.tokens).padding(toLength: 16, withPad: " ", startingAt: 0)) $\(money(spend.costUSD))")
}

// ---------- CODEX ----------
let codex = CodexCollector(pricing: pricing)
let t2 = DispatchTime.now()
let x1 = try await codex.collectDetailed()
let codexFull = Double(DispatchTime.now().uptimeNanoseconds - t2.uptimeNanoseconds) / 1e9
let t3 = DispatchTime.now()
let x2 = try await codex.collectDetailed()
let codexInc = Double(DispatchTime.now().uptimeNanoseconds - t3.uptimeNanoseconds) / 1e9

let xd = x1.diagnostics
let codexCost = x1.events.reduce(Decimal(0)) { $0 + $1.costUSD }

log("""

========== CODEX ==========
rollouts ............... \(n(xd.files))
sessões com uso ........ \(n(xd.sessionsWithUsage))
plano .................. \(xd.planType ?? "?")

TOKENS
  CORRETO (deltas) ..... \(n(xd.correctTokens))
  INGÊNUO (soma tudo) .. \(n(xd.naiveTokens))
  inflação da armadilha  \(String(format: "%.1f", xd.naiveOverCorrectRatio))x

CUSTO .................. $\(money(codexCost))
modelos sem preço ...... \(xd.unpricedModels.isEmpty ? "nenhum" : xd.unpricedModels.sorted().joined(separator: ", "))
janelas (rate limits) .. \(x1.status.windows.isEmpty ? "VAZIO — nenhum snapshot válido (todos vencidos). Estado honesto." : x1.status.windows.map { "\($0.label): \($0.usedPercent)% [\($0.source.rawValue)]" }.joined(separator: " | "))

TEMPO
  scan completo ........ \(ms(codexFull))
  refresh incremental .. \(ms(codexInc))
""")

// ---------- ENGINE ----------
let engine = MyTokensEngine(pricing: pricing)
let s1 = await engine.refresh()
let s2 = await engine.refresh()

log("""

========== ENGINE (todos os providers) ==========
1º refresh (frio) ...... \(ms(s1.duration))
2º refresh (quente) .... \(ms(s2.duration))
eventos ................ \(n(s2.events.count))
""")

for st in s2.statuses {
    let w = st.windows.isEmpty ? "sem janela (honesto)" : st.windows.map { "\($0.label) \(Int($0.usedPercent))%" }.joined(separator: ", ")
    log("  \(st.provider.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) conectado=\(st.connected)  hoje=\(n(st.today.tokens)) tok / $\(money(st.today.costUSD))  mês=\(n(st.month.tokens)) tok / $\(money(st.month.costUSD))  | \(w)")
}

log("\nprojetos (top 5, todos os providers)")
for (p, spend) in Aggregator.byProject(s2.events).sorted(by: { $0.value.tokens > $1.value.tokens }).prefix(5) {
    log("  \(p.padding(toLength: 30, withPad: " ", startingAt: 0)) \(n(spend.tokens)) tok  $\(money(spend.costUSD))")
}

// ---------- JSON pro diff com o probe ----------
if jsonOut {
    var byDay: [String: [String: [String: Int]]] = [:]  // dia -> modelo -> buckets
    for e in c1.events where e.provider == .claudeCode {
        let day = ISO8601Stamp.utcDay(e.ts)
        var m = byDay[day] ?? [:]
        var b = m[e.model] ?? [:]
        b["input_tokens", default: 0] += e.tokens.input
        b["output_tokens", default: 0] += e.tokens.output
        b["cache_creation_input_tokens", default: 0] += e.tokens.cacheWrite
        b["cache_read_input_tokens", default: 0] += e.tokens.cacheRead
        m[e.model] = b
        byDay[day] = m
    }
    let out: [String: Any] = [
        "files": d.files,
        "assistantRows": d.assistantRows,
        "uniqueRequestIds": d.uniqueRequestIds,
        "rawTotalTokens": d.rawTokens,
        "dedupTotalTokens": d.dedupTokens,
        "rawOverDedupRatio": d.inflationRatio,
        "dedupBuckets": [
            "input_tokens": d.dedupBuckets.input,
            "output_tokens": d.dedupBuckets.output,
            "cache_creation_input_tokens": d.dedupBuckets.cacheWrite,
            "cache_read_input_tokens": d.dedupBuckets.cacheRead,
        ],
        "rawBuckets": [
            "input_tokens": d.rawBuckets.input,
            "output_tokens": d.rawBuckets.output,
            "cache_creation_input_tokens": d.rawBuckets.cacheWrite,
            "cache_read_input_tokens": d.rawBuckets.cacheRead,
        ],
        "byDayDedup": byDay,
        "costDedupUSD": "\(dedupCost)",
        "codexCorrectTokens": xd.correctTokens,
        "codexNaiveTokens": xd.naiveTokens,
        "timings": [
            "claudeFullScanMs": fullScan * 1000,
            "claudeIncrementalMs": incScan * 1000,
            "codexFullScanMs": codexFull * 1000,
            "codexIncrementalMs": codexInc * 1000,
            "engineColdMs": s1.duration * 1000,
            "engineWarmMs": s2.duration * 1000,
        ],
    ]
    let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
}
