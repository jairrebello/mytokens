// Codex — ~/.codex/sessions/**/rollout-*.jsonl (+ archived_sessions/)
//
// ARMADILHA A (ACUMULADO): info.total_token_usage é o acumulado DA SESSÃO INTEIRA,
//   reescrito a cada turno. Somar todo token_count conta o mesmo token N vezes — infla
//   86,4x (176.076.139.447 vs 2.038.076.945). MEDIDO.
//
//   A saída óbvia é pegar só o ÚLTIMO evento de cada sessão. Faço melhor, e dá o MESMO
//   número: como a série é acumulada, o gasto do turno é a DIFERENÇA pro evento anterior.
//   Somar as diferenças = o último acumulado (verificado no disco: soma(deltas) == último
//   total nos 395 arquivos, e 0 arquivos com a série decrescendo). A vantagem é que cada
//   delta carrega o TIMESTAMP e o MODELO do turno em que aconteceu — o "último evento"
//   jogaria a sessão inteira num instante e num modelo só. 3 sessões trocam de modelo no
//   meio; agrupar por dia/modelo com o último evento mentiria nelas.
//   Se a série algum dia decrescer (sessão reiniciada), o baseline reseta — nunca conto
//   delta negativo.
//
// ARMADILHA B (SNAPSHOT): rate_limits.used_percent é um snapshot. O "agora" é o evento
//   de maior TIMESTAMP GLOBAL, não o arquivo mais recente por nome/mtime.
//
// ARMADILHA C (5h MORREU): a janela primary/5h foi REMOVIDA do Codex em 2026-07-12.
//   Só a secondary (semanal) sobrevive. O parser tolera as duas: lê primary se ainda vier
//   (rollout velho tem), mas NADA aqui depende dela existir.
//
// BUCKETS: no Codex, input_tokens JÁ INCLUI cached_input_tokens (conferido: total_tokens
//   == input + output). Então input cobrável = input - cached, e cached é cache_read.
//   Tratar `input` cru como input cobrável cobraria preço cheio por token cacheado —
//   aqui, 94% do input é cache. reasoning_output é subconjunto de output: informativo.

import Foundation

// MARK: - Linha crua

public struct CodexRow: Sendable {
    public let dedupKey: String  // rolloutFile + índice da linha. Contrato.
    public let ts: Date
    public let model: String
    public let sessionId: String
    public let project: String?
    public let tokens: TokenBuckets
}

struct CodexCumulative: Sendable, Equatable {
    var input = 0
    var cached = 0
    var output = 0
    var reasoning = 0

    static func - (a: CodexCumulative, b: CodexCumulative) -> CodexCumulative {
        CodexCumulative(
            input: a.input - b.input,
            cached: a.cached - b.cached,
            output: a.output - b.output,
            reasoning: a.reasoning - b.reasoning
        )
    }

    /// input JÁ INCLUI cached. Separa antes de precificar.
    var buckets: TokenBuckets {
        TokenBuckets(
            input: max(input - cached, 0),
            output: output,
            cacheWrite: 0,  // OpenAI não cobra escrita de cache à parte.
            cacheRead: cached,
            reasoning: reasoning > 0 ? reasoning : nil
        )
    }

    var isEmpty: Bool { input == 0 && cached == 0 && output == 0 && reasoning == 0 }
}

public struct CodexRateSnapshot: Sendable {
    public let ts: Date
    public let planType: String?
    public let fiveHour: CodexWindow?   // legado: sumiu em 2026-07-12
    public let sevenDay: CodexWindow?
}

public struct CodexWindow: Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date
}

public struct CodexSessionDigest: Sendable {
    public var rows: [CodexRow] = []
    var cumulative = CodexCumulative()
    var model = "unknown"
    var sessionId = ""
    var project: String?
    var lineIndex = 0
    public var rate: CodexRateSnapshot?
    /// só pra diagnóstico: o que a soma ingênua (todo token_count) daria.
    public var naiveTotal = 0
}

// MARK: - Parser

public struct CodexFileParser: IncrementalFileParser {
    public typealias Digest = CodexSessionDigest

    public init() {}

    public func digest(newBytes: Data, file: URL, previous: CodexSessionDigest?) -> CodexSessionDigest {
        var d = previous ?? CodexSessionDigest()
        if d.sessionId.isEmpty {
            d.sessionId = file.deletingPathExtension().lastPathComponent
        }
        guard !newBytes.isEmpty else { return d }

        newBytes.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var start = 0
            var i = 0
            let n = buf.count
            while i < n {
                if buf[i] == UInt8(ascii: "\n") {
                    if i > start {
                        let data = Data(bytes: buf.baseAddress!.advanced(by: start), count: i - start)
                        Self.consume(data, file: file, into: &d)
                    }
                    d.lineIndex += 1
                    start = i + 1
                }
                i += 1
            }
        }
        return d
    }

    private static func consume(_ data: Data, file: URL, into d: inout CodexSessionDigest) {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = o["type"] as? String
        else { return }

        let payload = o["payload"] as? [String: Any]

        switch type {
        case "session_meta":
            // cwd = o projeto. id = a sessão de verdade (o nome do arquivo é derivado).
            if let cwd = payload?["cwd"] as? String, d.project == nil {
                d.project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            if let id = payload?["id"] as? String, !id.isEmpty { d.sessionId = id }

        case "turn_context":
            // o modelo do turno. Vem ANTES do token_count do mesmo turno.
            if let m = payload?["model"] as? String, !m.isEmpty { d.model = m }

        case "event_msg":
            guard payload?["type"] as? String == "token_count" else { return }

            if let rl = payload?["rate_limits"] as? [String: Any],
               let tsRaw = o["timestamp"] as? String,
               let ts = ISO8601.date(tsRaw) {
                // rate_limits pode vir null num token_count. Tolerado: só ignora.
                let snap = CodexRateSnapshot(
                    ts: ts,
                    planType: rl["plan_type"] as? String,
                    fiveHour: window(rl["primary"]),
                    sevenDay: window(rl["secondary"])
                )
                if snap.fiveHour != nil || snap.sevenDay != nil {
                    if d.rate.map({ ts > $0.ts }) ?? true { d.rate = snap }
                }
            }

            guard let info = payload?["info"] as? [String: Any],
                  let tu = info["total_token_usage"] as? [String: Any],
                  let tsRaw = o["timestamp"] as? String,
                  let ts = ISO8601.date(tsRaw)
            else { return }

            let cur = CodexCumulative(
                input: int(tu["input_tokens"]),
                cached: int(tu["cached_input_tokens"]),
                output: int(tu["output_tokens"]),
                reasoning: int(tu["reasoning_output_tokens"])
            )
            d.naiveTotal += int(tu["total_tokens"])

            // Série reiniciou (sessão retomada do zero)? Baseline volta pro zero em vez
            // de gerar delta negativo.
            let base = cur.input < d.cumulative.input ? CodexCumulative() : d.cumulative
            let delta = cur - base
            d.cumulative = cur

            let buckets = delta.buckets
            guard buckets.total > 0 else { return }

            d.rows.append(CodexRow(
                dedupKey: "\(file.path)#\(d.lineIndex)",
                ts: ts,
                model: d.model,
                sessionId: d.sessionId,
                project: d.project,
                tokens: buckets
            ))

        default:
            return
        }
    }

    private static func window(_ any: Any?) -> CodexWindow? {
        guard let w = any as? [String: Any],
              let pct = (w["used_percent"] as? NSNumber)?.doubleValue,
              let resets = (w["resets_at"] as? NSNumber)?.doubleValue
        else { return nil }
        return CodexWindow(
            usedPercent: pct,
            windowMinutes: (w["window_minutes"] as? NSNumber)?.intValue ?? 0,
            resetsAt: Date(timeIntervalSince1970: resets)
        )
    }

    private static func int(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? 0 }
}

// MARK: - Collector

public struct CodexDiagnostics: Sendable {
    public var files = 0
    public var sessionsWithUsage = 0
    public var correctTokens = 0
    /// somar todo token_count (o erro): infla ~86x. Só pra provar que a armadilha existe.
    public var naiveTokens = 0
    public var unpricedModels: Set<String> = []
    public var planType: String?
    public var scan = ScanStats()

    public var naiveOverCorrectRatio: Double {
        correctTokens > 0 ? Double(naiveTokens) / Double(correctTokens) : 0
    }
}

public struct CodexCollectResult: Sendable {
    public let events: [UsageEvent]
    public let status: ProviderStatus
    public let diagnostics: CodexDiagnostics
}

public actor CodexCollector: UsageCollector {
    public nonisolated let provider: Provider = .codex

    private let roots: [URL]
    private let pricing: PricingTable
    private let scanner: IncrementalScanner<CodexFileParser>
    private let calendar: Calendar

    /// O último resultado caro. Válido enquanto o disco não mexer. Mesma razão do Claude:
    /// sem isto, cada evento de FSEvents reconstrói eventos idênticos aos de antes.
    private struct Memo: Sendable {
        let events: [UsageEvent]
        let diagnostics: CodexDiagnostics
        let rate: CodexRateSnapshot?
    }
    private var memo: Memo?

    /// ONDE o Codex mora. É UMA lista, e ela é pública porque quem confere o número
    /// (o teste, o bench) TEM que varrer exatamente o mesmo disco que o collector.
    /// Repetir esses caminhos na mão foi como o teste passou meses acusando uma
    /// divergência de 280.956 tokens que era só ele olhando metade do disco.
    public static func defaultRoots(
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> [URL] {
        [
            home.appending(path: ".codex/sessions"),
            home.appending(path: ".codex/archived_sessions"),
        ]
    }

    public init(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        pricing: PricingTable,
        calendar: Calendar = .current
    ) {
        self.roots = Self.defaultRoots(home: home)
        self.pricing = pricing
        self.scanner = IncrementalScanner(parser: CodexFileParser())
        self.calendar = calendar
    }

    public init(roots: [URL], pricing: PricingTable, calendar: Calendar = .current) {
        self.roots = roots
        self.pricing = pricing
        self.scanner = IncrementalScanner(parser: CodexFileParser())
        self.calendar = calendar
    }

    public func collect() async throws -> (events: [UsageEvent], status: ProviderStatus) {
        let r = try await collectDetailed()
        return (r.events, r.status)
    }

    public func collectDetailed(now: Date = Date()) async throws -> CodexCollectResult {
        let files = roots.flatMap { FileWalker.jsonl(under: $0, namePrefix: "rollout-") }
        let result = await scanner.scan(files: files)

        // Disco idêntico ao scan anterior? Os eventos também são. Só o status é refeito —
        // ele depende do relógio (a janela anda, o dia vira), os eventos não.
        let events: [UsageEvent]
        let newest: CodexRateSnapshot?
        var diag: CodexDiagnostics

        if !result.changed, let cache = memo {
            (events, diag, newest) = (cache.events, cache.diagnostics, cache.rate)
        } else {
            (events, diag, newest) = Self.build(
                digests: result.digests, pricing: pricing, files: files.count
            )
            memo = Memo(events: events, diagnostics: diag, rate: newest)
        }
        diag.scan = result.stats

        let status = Aggregator.status(
            provider: .codex,
            events: events,
            windows: Self.windows(from: newest, now: now),
            connected: !files.isEmpty,
            now: now,
            calendar: calendar
        )
        return CodexCollectResult(events: events, status: status, diagnostics: diag)
    }

    /// O trabalho caro: deltas, precificação e ordenação. Só roda quando o disco mexeu.
    private static func build(
        digests: [String: CodexSessionDigest],
        pricing: PricingTable,
        files: Int
    ) -> ([UsageEvent], CodexDiagnostics, CodexRateSnapshot?) {
        var diag = CodexDiagnostics()
        diag.files = files

        var events: [UsageEvent] = []
        var newest: CodexRateSnapshot?

        for (_, d) in digests {
            if !d.rows.isEmpty { diag.sessionsWithUsage += 1 }
            diag.naiveTokens += d.naiveTotal

            // ARMADILHA B: o "agora" é o maior timestamp GLOBAL, não o arquivo mais novo.
            if let r = d.rate, newest.map({ r.ts > $0.ts }) ?? true { newest = r }

            for row in d.rows {
                let cost = pricing.cost(model: row.model, tokens: row.tokens)
                if cost == nil { diag.unpricedModels.insert(row.model) }
                diag.correctTokens += row.tokens.total

                events.append(UsageEvent(
                    id: row.dedupKey,
                    provider: .codex,
                    ts: row.ts,
                    sessionId: row.sessionId,
                    model: row.model,
                    project: row.project,
                    tokens: row.tokens,
                    costUSD: cost ?? 0
                ))
            }
        }

        events.sort { $0.ts < $1.ts }
        diag.planType = newest?.planType
        return (events, diag, newest)
    }

    /// Janela VENCIDA não vai pra tela: um used_percent de um bloco que já morreu é um
    /// número velho fingindo ser o de agora. Vencida -> some. Regra 5.
    static func windows(from snap: CodexRateSnapshot?, now: Date) -> [LimitWindow] {
        guard let snap else { return [] }
        var out: [LimitWindow] = []

        // O snapshot foi lido do rollout em `snap.ts` — NÃO é de agora. `measuredAt`
        // carrega essa idade pra tela, que é o que separa fato de palpite.
        // O começo da janela sai de graça: o Codex publica a duração dela.
        func window(_ w: CodexWindow?, id: String, label: String) -> LimitWindow? {
            guard let w, w.resetsAt > now else { return nil }
            return LimitWindow(
                id: id,
                label: label,
                usedPercent: w.usedPercent,
                resetsAt: w.resetsAt,
                source: .measured,
                startedAt: w.resetsAt.addingTimeInterval(-Double(w.windowMinutes) * 60),
                measuredAt: snap.ts,
                measuredPercent: w.usedPercent
            )
        }

        if let w = window(snap.fiveHour, id: "codex-5h", label: "5 horas") { out.append(w) }
        if let w = window(snap.sevenDay, id: "codex-7d", label: "Semana") { out.append(w) }
        return out
    }
}
