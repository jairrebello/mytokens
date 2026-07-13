import Foundation
import Testing

@testable import MyTokensCore

@Suite("Parsers — as armadilhas, uma a uma")
struct ParserTests {

    // MARK: - Claude

    @Test("iterations com 2+ entradas: SOMA as iterações. O topo é a última, não a soma.")
    func iterationsAreSummed() {
        // Caso REAL do docs/FONTES.md §1.4: topo diz cache_read=105.029, soma=203.371.
        let usage: [String: Any] = [
            "input_tokens": 76,
            "output_tokens": 566,
            "cache_read_input_tokens": 105_029,
            "cache_creation_input_tokens": 0,
            "iterations": [
                ["input_tokens": 76, "output_tokens": 2, "cache_read_input_tokens": 98_342,
                 "cache_creation_input_tokens": 8_305],
                ["input_tokens": 76, "output_tokens": 566, "cache_read_input_tokens": 105_029,
                 "cache_creation_input_tokens": 0],
            ],
        ]
        let t = ClaudeFileParser.readUsage(usage)
        #expect(t.cacheRead == 203_371)  // e NÃO 105.029
        #expect(t.input == 152)
        #expect(t.output == 568)
        #expect(t.cacheWrite == 8_305)
    }

    @Test("iterations com 1 entrada: usa o topo (não duplica)")
    func singleIterationUsesTop() {
        let usage: [String: Any] = [
            "input_tokens": 37_268, "output_tokens": 613,
            "cache_read_input_tokens": 25_227, "cache_creation_input_tokens": 12_548,
            "iterations": [["input_tokens": 37_268, "output_tokens": 613,
                            "cache_read_input_tokens": 25_227,
                            "cache_creation_input_tokens": 12_548]],
        ]
        let t = ClaudeFileParser.readUsage(usage)
        #expect(t.input == 37_268)
        #expect(t.cacheRead == 25_227)
    }

    @Test("cache_creation separa 5m de 1h — preços diferentes")
    func cacheCreationSplitsByTTL() {
        let usage: [String: Any] = [
            "input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0,
            "cache_creation_input_tokens": 12_548,
            "cache_creation": ["ephemeral_1h_input_tokens": 12_548,
                               "ephemeral_5m_input_tokens": 0],
        ]
        let t = ClaudeFileParser.readUsage(usage)
        #expect(t.cacheWrite == 12_548)
        #expect(t.cacheWrite1h == 12_548)
        #expect(t.cacheWrite5m == 0)
    }

    @Test("DEDUP: 4 linhas, 1 requestId, usage idêntico -> conta UMA vez")
    func dedupCollapsesRepeatedRequestId() async throws {
        // É exatamente o que acontece no disco: 1 resposta da API vira N linhas JSONL
        // (uma por content block) e CADA uma repete o usage inteiro.
        let line = """
        {"type":"assistant","requestId":"req_ABC","sessionId":"s1","timestamp":"2026-07-06T12:23:58.036Z","cwd":"/Users/x/projetos/foo","message":{"id":"msg_1","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}
        """
        let dir = try TempDir()
        let file = dir.url.appending(path: "s1.jsonl")
        try Array(repeating: line, count: 4).joined(separator: "\n").appending("\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let c = ClaudeCodeCollector(root: dir.url, pricing: try PricingTable.bundled())
        let r = try await c.collectDetailed()

        #expect(r.diagnostics.assistantRows == 4)
        #expect(r.diagnostics.uniqueRequestIds == 1)
        #expect(r.diagnostics.rawTokens == 4 * 1110)
        #expect(r.diagnostics.dedupTokens == 1110)
        #expect(r.events.count == 1)
        #expect(r.events[0].project == "foo")
        #expect(r.events[0].model == "claude-opus-4-8")
    }

    @Test("linha sem requestId cai no fallback message.id — 28 linhas de erro não viram 1")
    func fallbackKeyDoesNotCollapse() async throws {
        let a = """
        {"type":"assistant","sessionId":"s1","timestamp":"2026-07-06T12:00:00.000Z","message":{"id":"msg_A","model":"claude-opus-4-8","usage":{"input_tokens":1,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        let b = """
        {"type":"assistant","sessionId":"s1","timestamp":"2026-07-06T12:00:01.000Z","message":{"id":"msg_B","model":"claude-opus-4-8","usage":{"input_tokens":1,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        let dir = try TempDir()
        try "\(a)\n\(b)\n".write(to: dir.url.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)

        let r = try await ClaudeCodeCollector(root: dir.url, pricing: try PricingTable.bundled())
            .collectDetailed()

        #expect(r.events.count == 2)  // se colapsassem numa chave nil só, seria 1.
        #expect(r.diagnostics.dedupTokens == 2)
    }

    @Test("linha que não é assistant é ruído: user, summary, system — zero token")
    func nonAssistantLinesIgnored() async throws {
        let dir = try TempDir()
        try """
        {"type":"user","message":{"role":"user","content":"oi"}}
        {"type":"summary","summary":"x"}
        {"type":"system","subtype":"init"}
        """.write(to: dir.url.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)

        let r = try await ClaudeCodeCollector(root: dir.url, pricing: try PricingTable.bundled())
            .collectDetailed()
        #expect(r.events.isEmpty)
        #expect(r.diagnostics.dedupTokens == 0)
    }

    @Test("subagente vive um nível abaixo: a varredura É recursiva")
    func recursiveWalkFindsSubagents() async throws {
        let dir = try TempDir()
        let sub = dir.url.appending(path: "slug/sessao-1/subagents")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)

        let line = """
        {"type":"assistant","requestId":"req_SUB","sessionId":"s2","timestamp":"2026-07-06T12:00:00.000Z","message":{"id":"m","model":"claude-opus-4-8","usage":{"input_tokens":500,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        try "\(line)\n".write(to: sub.appending(path: "agent.jsonl"), atomically: true, encoding: .utf8)

        let r = try await ClaudeCodeCollector(root: dir.url, pricing: try PricingTable.bundled())
            .collectDetailed()
        #expect(r.diagnostics.dedupTokens == 500)  // varredura rasa acharia 0.
    }

    // MARK: - Codex

    @Test("Codex: total_token_usage é ACUMULADO. Somar tudo infla; delta acerta.")
    func codexCumulativeIsNotSummed() async throws {
        let dir = try TempDir()
        // 3 turnos. O acumulado vai 100 -> 300 -> 600. O gasto REAL é 600, não 1000.
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            codexTokenCount(ts: "2026-05-18T10:00:00.000Z", input: 90, cached: 0, output: 10),
            codexTokenCount(ts: "2026-05-18T11:00:00.000Z", input: 270, cached: 0, output: 30),
            codexTokenCount(ts: "2026-05-18T12:00:00.000Z", input: 540, cached: 0, output: 60),
        ]
        try (lines.joined(separator: "\n") + "\n")
            .write(to: dir.url.appending(path: "rollout-x.jsonl"), atomically: true, encoding: .utf8)

        let r = try await CodexCollector(roots: [dir.url], pricing: try PricingTable.bundled())
            .collectDetailed()

        #expect(r.diagnostics.correctTokens == 600)   // o último acumulado
        #expect(r.diagnostics.naiveTokens == 1000)    // 100 + 300 + 600: a armadilha
        // e os deltas preservam o TEMPO de cada turno
        #expect(r.events.count == 3)
        #expect(r.events.map(\.tokens.total) == [100, 200, 300])
    }

    @Test("Codex: input JÁ INCLUI cached. Cobrar input cheio seria 10x mais caro.")
    func codexInputIncludesCached() async throws {
        let dir = try TempDir()
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-5.4"}}"#,
            codexTokenCount(ts: "2026-05-18T10:00:00.000Z", input: 1000, cached: 900, output: 100),
        ]
        try (lines.joined(separator: "\n") + "\n")
            .write(to: dir.url.appending(path: "rollout-y.jsonl"), atomically: true, encoding: .utf8)

        let r = try await CodexCollector(roots: [dir.url], pricing: try PricingTable.bundled())
            .collectDetailed()

        let t = try #require(r.events.first).tokens
        #expect(t.input == 100)      // 1000 - 900
        #expect(t.cacheRead == 900)
        #expect(t.output == 100)
        #expect(t.total == 1100)     // = total_tokens do disco (input + output)

        // gpt-5.4: input 2.50/1M, cache_read 0.25/1M.
        // honesto: 100*2.50/1M + 900*0.25/1M + 100*15/1M = 0.00025 + 0.000225 + 0.0015
        let p = try PricingTable.bundled()
        #expect(p.cost(model: "gpt-5.4", tokens: t) == Decimal(string: "0.001975"))
    }

    @Test("Codex: janela VENCIDA não vai pra tela — número velho não finge ser de agora")
    func expiredWindowIsDropped() {
        let passado = Date(timeIntervalSince1970: 1_779_203_683)  // maio/2026
        let snap = CodexRateSnapshot(
            ts: passado,
            planType: "plus",
            fiveHour: CodexWindow(usedPercent: 1, windowMinutes: 300, resetsAt: passado),
            sevenDay: CodexWindow(usedPercent: 20, windowMinutes: 10080, resetsAt: passado)
        )
        let agora = Date(timeIntervalSince1970: 1_784_000_000)  // julho/2026
        #expect(CodexCollector.windows(from: snap, now: agora).isEmpty)

        // Ainda válida -> aparece, e marcada como MEDIDA (o provedor nos deu).
        let futuro = agora.addingTimeInterval(3600)
        let viva = CodexRateSnapshot(
            ts: agora, planType: "plus", fiveHour: nil,
            sevenDay: CodexWindow(usedPercent: 42, windowMinutes: 10080, resetsAt: futuro)
        )
        let w = CodexCollector.windows(from: viva, now: agora)
        #expect(w.count == 1)
        #expect(w[0].label == "Semana")
        #expect(w[0].source == .measured)
        #expect(w[0].usedPercent == 42)
    }

    @Test("Codex sem janela primary (removida em 2026-07-12) continua funcionando")
    func worksWithoutPrimaryWindow() {
        let agora = Date()
        let snap = CodexRateSnapshot(
            ts: agora, planType: "plus",
            fiveHour: nil,  // a 5h MORREU. Nada aqui depende dela.
            sevenDay: CodexWindow(usedPercent: 33, windowMinutes: 10080,
                                  resetsAt: agora.addingTimeInterval(86_400))
        )
        let w = CodexCollector.windows(from: snap, now: agora)
        #expect(w.count == 1)
        #expect(w[0].id == "codex-7d")
    }

    // MARK: - ISO8601

    @Test("timestamp do disco parseia exato (e bate com o ISO8601DateFormatter)")
    func iso8601() throws {
        let s = "2026-07-06T12:23:58.036Z"
        let d = try #require(ISO8601.date(s))

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ref = try #require(f.date(from: s))
        #expect(abs(d.timeIntervalSince1970 - ref.timeIntervalSince1970) < 0.0005)

        #expect(ISO8601.date("2026-01-01T00:00:00Z")?.timeIntervalSince1970 == 1_767_225_600)
        #expect(ISO8601.date("não é data") == nil)
    }

    // MARK: - Rate limits do Claude (statusLine)

    @Test("statusLine: used_percentage vira janela MEDIDA")
    func statusLineIngest() throws {
        let stdin = """
        {"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":9999999999},
        "seven_day":{"used_percentage":10,"resets_at":9999999999}}}
        """.data(using: .utf8)!

        let snap = try #require(ClaudeRateLimitReader.ingest(statusLineStdin: stdin))
        #expect(snap.fiveHour?.usedPercentage == 42.5)

        let w = ClaudeRateLimitReader.windows(from: snap, now: Date())
        #expect(w.count == 2)
        #expect(w[0].source == .measured)  // o provedor nos DEU. Nunca .derived.
        #expect(w[0].usedPercent == 42.5)
    }

    @Test("sem snapshot do statusLine -> ZERO janela. A view mostra 'não sabemos'.")
    func noSnapshotMeansNoWindow() throws {
        let dir = try TempDir()
        let r = ClaudeRateLimitReader(url: dir.url.appending(path: "nao-existe.json"))
        #expect(r.read().isEmpty)
    }
}

// MARK: - Helpers

func codexTokenCount(ts: String, input: Int, cached: Int, output: Int) -> String {
    """
    {"type":"event_msg","timestamp":"\(ts)","payload":{"type":"token_count","info":{\
    "total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),\
    "output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(input + output)}}}}
    """
}

/// Diretório temporário que se apaga sozinho.
/// Sendable de verdade (uma `let` imutável), não `@unchecked` pra calar o compilador.
final class TempDir: Sendable {
    let url: URL
    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mytokens-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
