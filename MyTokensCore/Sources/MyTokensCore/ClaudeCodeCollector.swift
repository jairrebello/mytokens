// Claude Code — ~/.claude/projects/**/*.jsonl
//
// A RAZÃO DE EXISTIR DESTE APP mora neste arquivo. O /stats do próprio Claude Code
// soma linha a linha e infla o total em 2,12x. Não repita o erro deles.
//
// POR QUE INFLA (causa provada, docs/FONTES.md §1):
//   1 resposta da API vira N LINHAS JSONL — uma por content block (thinking / text /
//   tool_use) — e CADA linha repete o objeto `usage` INTEIRO, com o MESMO requestId.
//   Somar linha a linha conta o mesmo token N vezes. Média medida: 2,06 linhas/chamada.
//   NÃO é resume/branch reescrevendo arquivo: requestIdsAppearingInMultipleFiles = 0.
//
// DEDUP: chave = requestId, fallback message.id.
//   As 28 linhas assistant sem requestId são erro de API e carregam ZERO token — mas
//   precisam de fallback, senão as 28 colapsam numa chave `nil` só e viram uma.
//
// SUBAGENTE: transcript de Task vive em <slug>/<sessionId>/subagents/*.jsonl.
//   A varredura É recursiva. 686 arquivos de gasto REAL moram lá.
//   NÃO use isSidechain pra achá-los: é false em 100% das linhas. É campo legado.

import Foundation

// MARK: - Linha crua

public struct ClaudeRow: Sendable {
    /// requestId, ou msg:<message.id>, ou row:<arquivo>#<linha>. Nunca vazia.
    public let dedupKey: String
    public let ts: Date
    public let model: String
    public let sessionId: String
    public let project: String?
    public let tokens: TokenBuckets
}

// MARK: - Parser de arquivo

public struct ClaudeFileParser: IncrementalFileParser {
    public typealias Digest = [ClaudeRow]

    public init() {}

    public func digest(newBytes: Data, file: URL, previous: [ClaudeRow]?) -> [ClaudeRow] {
        var rows = previous ?? []
        guard !newBytes.isEmpty else { return rows }

        // offset da linha DENTRO do arquivo é irrelevante pra chave sintética; o que
        // importa é ela ser única. Usa caminho + contador acumulado.
        var lineIndex = rows.count

        newBytes.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var start = 0
            let n = buf.count
            var i = 0
            while i < n {
                if buf[i] == UInt8(ascii: "\n") {
                    if i > start,
                       let row = Self.parseLine(
                           buf: buf, from: start, to: i, file: file, lineIndex: lineIndex
                       ) {
                        rows.append(row)
                    }
                    lineIndex += 1
                    start = i + 1
                }
                i += 1
            }
        }
        return rows
    }

    /// `"type":"assistant"` — 12 bytes. Fast path: 99% das linhas nem chegam no JSON.
    private static let assistantMarker = Array(#""type":"assistant""#.utf8)

    private static func parseLine(
        buf: UnsafeRawBufferPointer, from: Int, to: Int, file: URL, lineIndex: Int
    ) -> ClaudeRow? {
        let len = to - from
        guard len > 2 else { return nil }
        guard contains(buf: buf, from: from, to: to, needle: assistantMarker) else { return nil }

        let data = Data(bytes: buf.baseAddress!.advanced(by: from), count: len)
        guard
            let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            o["type"] as? String == "assistant",
            let message = o["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        guard let tsRaw = o["timestamp"] as? String, let ts = ISO8601.date(tsRaw) else { return nil }

        let requestId = o["requestId"] as? String
        let messageId = message["id"] as? String
        let key = requestId
            ?? messageId.map { "msg:\($0)" }
            ?? "row:\(file.path)#\(lineIndex)"

        // project = último componente do cwd. Sem cwd, cai pro slug da pasta.
        let project = (o["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }

        return ClaudeRow(
            dedupKey: key,
            ts: ts,
            model: message["model"] as? String ?? "unknown",
            sessionId: o["sessionId"] as? String ?? "unknown",
            project: project,
            tokens: readUsage(usage)
        )
    }

    /// ARMADILHA (docs/FONTES.md §1.4): quando `usage.iterations` tem 2+ entradas, o
    /// `usage` de TOPO é igual à ÚLTIMA iteração — NÃO à soma. Confiar no topo SUBCONTA.
    /// Provado: topo diz cache_read=105.029, a soma das iterações é 203.371.
    /// Regra: iterations.count > 1 -> some as iterações. Senão, use o topo.
    static func readUsage(_ u: [String: Any]) -> TokenBuckets {
        if let its = u["iterations"] as? [[String: Any]], its.count > 1 {
            return its.reduce(TokenBuckets()) { $0 + pick($1) }
        }
        return pick(u)
    }

    private static func pick(_ u: [String: Any]) -> TokenBuckets {
        let cacheWrite = int(u["cache_creation_input_tokens"])
        // cache_creation separa por TTL: 5m custa 1.25x input, 1h custa 2x. Preços
        // diferentes, buckets diferentes. Sem o objeto, o total vira 5m no cálculo.
        var w5m: Int?
        var w1h: Int?
        if let cc = u["cache_creation"] as? [String: Any] {
            w5m = int(cc["ephemeral_5m_input_tokens"])
            w1h = int(cc["ephemeral_1h_input_tokens"])
        }
        return TokenBuckets(
            input: int(u["input_tokens"]),
            output: int(u["output_tokens"]),
            cacheWrite: cacheWrite,
            cacheRead: int(u["cache_read_input_tokens"]),
            reasoning: nil,
            cacheWrite5m: w5m,
            cacheWrite1h: w1h
        )
    }

    private static func int(_ any: Any?) -> Int {
        (any as? NSNumber)?.intValue ?? 0
    }

    /// Busca de subsequência de bytes. Aspas dentro de string JSON vêm escapadas (\"),
    /// então `"type":"assistant"` literal não casa com texto de conteúdo. Seguro.
    private static func contains(
        buf: UnsafeRawBufferPointer, from: Int, to: Int, needle: [UInt8]
    ) -> Bool {
        let m = needle.count
        guard to - from >= m else { return false }
        let first = needle[0]
        var i = from
        let last = to - m
        while i <= last {
            if buf[i] == first {
                var j = 1
                while j < m && buf[i + j] == needle[j] { j += 1 }
                if j == m { return true }
            }
            i += 1
        }
        return false
    }
}

// MARK: - Collector

public struct ClaudeCollectResult: Sendable {
    public let events: [UsageEvent]
    public let status: ProviderStatus
    /// Diagnóstico — é o que prova o dedup. Bate com o probe do Sonda.
    public let diagnostics: ClaudeDiagnostics
}

public struct ClaudeDiagnostics: Sendable {
    public var files = 0
    public var assistantRows = 0
    public var uniqueRequestIds = 0
    public var rawTokens = 0
    public var dedupTokens = 0
    public var rawBuckets = TokenBuckets()
    public var dedupBuckets = TokenBuckets()
    /// modelos sem preço em pricing.json. Custo NÃO é chutado: sai zero e o modelo
    /// vem listado aqui pra alguém decidir. Regra 5.
    public var unpricedModels: Set<String> = []
    public var scan = ScanStats()

    public var inflationRatio: Double {
        dedupTokens > 0 ? Double(rawTokens) / Double(dedupTokens) : 0
    }
}

public actor ClaudeCodeCollector: UsageCollector {
    public nonisolated let provider: Provider = .claudeCode

    private let root: URL
    private let pricing: PricingTable
    private let rateLimits: ClaudeRateLimitReader
    private let scanner: IncrementalScanner<ClaudeFileParser>
    private let calendar: Calendar

    /// O último resultado caro. Válido enquanto o disco não mexer.
    private struct Memo: Sendable {
        let events: [UsageEvent]
        let diagnostics: ClaudeDiagnostics
    }
    private var memo: Memo?

    public init(
        root: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/projects"),
        pricing: PricingTable,
        rateLimits: ClaudeRateLimitReader = ClaudeRateLimitReader(),
        calendar: Calendar = .current
    ) {
        self.root = root
        self.pricing = pricing
        self.rateLimits = rateLimits
        self.scanner = IncrementalScanner(parser: ClaudeFileParser())
        self.calendar = calendar
    }

    public func collect() async throws -> (events: [UsageEvent], status: ProviderStatus) {
        let r = try await collectDetailed()
        return (r.events, r.status)
    }

    public func collectDetailed(now: Date = Date()) async throws -> ClaudeCollectResult {
        let files = FileWalker.jsonl(under: root)
        let result = await scanner.scan(files: files)

        // Disco IDÊNTICO ao scan anterior? Então os eventos também são. Reconstruí-los
        // (dedup de 93 mil linhas + Decimal de custo em 45 mil + ordenação) daria
        // exatamente o mesmo array, por 314 ms. O que MUDA com o tempo é o status —
        // janela de 5h anda, o dia vira — e só ele é recalculado.
        let (events, diag): ([UsageEvent], ClaudeDiagnostics)
        if !result.changed, let cache = memo {
            (events, diag) = (cache.events, cache.diagnostics)
        } else {
            (events, diag) = Self.build(digests: result.digests, pricing: pricing, files: files.count)
            memo = Memo(events: events, diagnostics: diag)
        }

        var diagnostics = diag
        diagnostics.scan = result.stats

        let windows = rateLimits.read(now: now)
        let status = Aggregator.status(
            provider: .claudeCode,
            events: events,
            windows: windows,
            connected: !files.isEmpty,
            now: now,
            calendar: calendar
        )
        return ClaudeCollectResult(events: events, status: status, diagnostics: diagnostics)
    }

    /// O trabalho caro: dedup global, precificação e ordenação. Só roda quando o disco mexeu.
    private static func build(
        digests: [String: [ClaudeRow]],
        pricing: PricingTable,
        files: Int
    ) -> ([UsageEvent], ClaudeDiagnostics) {
        var diag = ClaudeDiagnostics()
        diag.files = files

        // DEDUP GLOBAL por requestId. É aqui que 8,3 bilhões de tokens fantasma morrem.
        //
        // QUAL ocorrência fica? A de MAIOR TOTAL. Não é detalhe — é 9,8% do output.
        //
        // O Claude Code reescreve a MESMA mensagem (mesmo requestId, mesmo message.id, no
        // mesmo arquivo) enquanto ela é gerada, e o `output_tokens` CRESCE a cada reescrita:
        //     out=5 → out=5 → out=330
        // Ficar com a PRIMEIRA congela a mensagem no começo dela. Medido no disco real:
        // 7.360 chaves afetadas, 3.477.980 tokens de output perdidos — e output é o bucket
        // CARO (Opus: US$ 75/M contra US$ 15/M do input). O custo saía subestimado.
        //
        // E por que não a ÚLTIMA, que seria o óbvio? Porque existe registro TRUNCADO: uma
        // chave (em 46.518) tem a última ocorrência ZERADA em todos os buckets. "Última"
        // jogaria 271 mil tokens fora naquele caso. "Maior total" acerta os dois.
        //
        // De quebra, é a única regra DETERMINÍSTICA: "primeira" depende da ordem do
        // readdir, então o total de um dia ANTIGO mudava só porque um arquivo novo entrou
        // e reordenou a varredura. Conferido no disco: zero empate ambíguo (mesmo total,
        // buckets diferentes), então a escolha nunca é sorteio.
        var best: [String: ClaudeRow] = [:]
        best.reserveCapacity(64_000)

        for (_, rows) in digests {
            for row in rows {
                diag.assistantRows += 1
                diag.rawBuckets += row.tokens

                if let atual = best[row.dedupKey], atual.tokens.total >= row.tokens.total {
                    continue
                }
                best[row.dedupKey] = row
            }
        }

        var events: [UsageEvent] = []
        events.reserveCapacity(best.count)

        for row in best.values {
            diag.dedupBuckets += row.tokens

            let cost = pricing.cost(model: row.model, tokens: row.tokens)
            if cost == nil, row.tokens.total > 0 { diag.unpricedModels.insert(row.model) }

            events.append(UsageEvent(
                id: row.dedupKey,
                provider: .claudeCode,
                ts: row.ts,
                sessionId: row.sessionId,
                model: row.model,
                project: row.project,
                tokens: row.tokens,
                costUSD: cost ?? 0
            ))
        }

        diag.uniqueRequestIds = best.count
        diag.rawTokens = diag.rawBuckets.total
        diag.dedupTokens = diag.dedupBuckets.total

        events.sort { $0.ts < $1.ts }
        return (events, diag)
    }
}
