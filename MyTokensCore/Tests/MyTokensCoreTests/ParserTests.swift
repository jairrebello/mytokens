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

    @Test("statusLine: chave desconhecida de rate_limits vai pra extras, crua — não cai no chão")
    func statusLineCapturesUnknownWindows() throws {
        let stdin = """
        {"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":9999999999},
        "seven_day_fable":{"used_percentage":77,"resets_at":9999999999},
        "sem_percentual":{"resets_at":9999999999}}}
        """.data(using: .utf8)!

        let snap = try #require(ClaudeRateLimitReader.ingest(statusLineStdin: stdin))
        #expect(snap.fiveHour?.usedPercentage == 42.5)
        #expect(snap.extras?["seven_day_fable"]?.usedPercentage == 77)
        // entrada sem used_percentage não é janela — não entra nem em extras
        #expect(snap.extras?.count == 1)

        // extras ainda NÃO viram LimitWindow: falta a tabela chave→(label, span,
        // modelScope). Capturar sem emitir é o comportamento da etapa 1.
        let w = ClaudeRateLimitReader.windows(from: snap, now: Date())
        #expect(w.count == 1)
    }

    @Test("statusLine: payload SÓ com janela desconhecida ainda vira snapshot")
    func statusLineOnlyUnknownWindowsStillIngests() throws {
        let stdin = """
        {"rate_limits":{"seven_day_opus":{"used_percentage":12,"resets_at":9999999999}}}
        """.data(using: .utf8)!

        let snap = try #require(ClaudeRateLimitReader.ingest(statusLineStdin: stdin))
        #expect(snap.fiveHour == nil && snap.sevenDay == nil)
        #expect(snap.extras?["seven_day_opus"]?.usedPercentage == 12)
    }

    @Test("sem snapshot do statusLine -> ZERO janela. A view mostra 'não sabemos'.")
    func noSnapshotMeansNoWindow() throws {
        let dir = try TempDir()
        let r = ClaudeRateLimitReader(url: dir.url.appending(path: "nao-existe.json"))
        #expect(r.read().isEmpty)
    }

    // MARK: - Cursor (rede)

    /// O schema REAL, capturado ao vivo em 13/07 do cursor.com/api/usage-summary. Fixado
    /// aqui pra travar a leitura sem depender da rede — o endpoint é interno do Cursor e
    /// muda sem avisar; se mudar, é este teste que grita.
    @Test("Cursor: totalPercentUsed vira a janela do mês, em US$")
    func cursorUsageSummary() throws {
        let json = """
        {"billingCycleStart":"2026-06-30T12:59:20.000Z",
         "billingCycleEnd":"2026-07-30T12:59:20.000Z",
         "membershipType":"pro","isUnlimited":false,
         "individualUsage":{"plan":{"used":2000,"limit":2000,"remaining":0,
           "breakdown":{"included":2000,"bonus":1207,"total":3207},
           "totalPercentUsed":16.446153846153848},
           "onDemand":{"enabled":false}}}
        """.data(using: .utf8)!

        let status = try CursorCollector.parse(json, now: Date())
        #expect(status.connected)
        let w = try #require(status.windows.first)
        #expect(w.id == "cursor-month")
        #expect(w.source == .measured)          // o Cursor DEU o número. Nunca derivado.
        #expect(w.unit == .usd)                 // dólar de compute, não % de cota opaca
        #expect(w.capUSD == Decimal(20))        // included 2000 centavos = US$ 20
        #expect(Int(w.usedPercent.rounded()) == 16)
    }

    /// Sessão válida mas SEM plano individual (conta de time): conectado, mas sem janela
    /// que a gente saiba desenhar. Não inventa uma.
    @Test("Cursor: resposta sem plano individual -> conectado, sem janela")
    func cursorNoIndividualPlan() throws {
        let json = #"{"membershipType":"pro","teamUsage":{},"individualUsage":{}}"#
            .data(using: .utf8)!
        let status = try CursorCollector.parse(json, now: Date())
        #expect(status.connected)
        #expect(status.windows.isEmpty)
    }

    /// O `sub` sai do payload do JWT sem tocar em assinatura nem no header. É o que entra
    /// no cookie de sessão — e é a única parte do token que este código manipula por nome.
    @Test("Cursor: extrai o sub do JWT")
    func cursorJWTSubject() {
        // header.payload.signature — payload = {"sub":"google-oauth2|123","exp":9}
        let payload = Data(#"{"sub":"google-oauth2|123","exp":9}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "aaa.\(payload).bbb"
        #expect(CursorCollector.subject(ofJWT: jwt) == "google-oauth2|123")
        #expect(CursorCollector.subject(ofJWT: "não é jwt") == nil)
    }

    /// JANELA VENCIDA SOME. Não vira 0%, não vira o último valor: SOME.
    ///
    /// Esta regra existia nos dois collectors e não tinha UM teste — o tipo de coisa que
    /// morre num refactor sem ninguém notar, e que ninguém percebe na tela, porque "0%"
    /// parece um número perfeitamente saudável.
    ///
    /// E o risco é REAL, não teórico: nesta máquina o rollout mais novo do Codex é de
    /// 18/05, e os `resets_at` dele venceram em 19/05 e 23/05 — oito semanas atrás. O
    /// `used_percent: 1.0` que está gravado ali é um FÓSSIL. Mostrá-lo seria dizer ao
    /// usuário "você usou 1% da sua semana" sobre uma semana que acabou em maio.
    @Test("janela VENCIDA some — um bloco morto não vira 0%")
    func expiredWindowDisappears() throws {
        let ontem = Date().addingTimeInterval(-24 * 3600)
        let amanha = Date().addingTimeInterval(24 * 3600)

        // Claude: o snapshot do hook envelheceu.
        let snap = ClaudeRateLimitSnapshot(
            capturedAt: ontem,
            fiveHour: .init(usedPercentage: 87, resetsAt: ontem.timeIntervalSince1970),
            sevenDay: .init(usedPercentage: 40, resetsAt: amanha.timeIntervalSince1970)
        )
        let claude = ClaudeRateLimitReader.windows(from: snap, now: Date())
        #expect(claude.count == 1, "a de 5 h venceu e tinha que sumir")
        #expect(claude.first?.id == "claude-7d")
        #expect(!claude.contains { $0.usedPercent == 0 }, "vencida virou zero — é a mentira")

        // Codex: o rollout envelheceu (é o caso REAL desta máquina).
        let fossil = CodexRateSnapshot(
            ts: ontem,
            planType: "plus",
            fiveHour: CodexWindow(usedPercent: 1, windowMinutes: 300, resetsAt: ontem),
            sevenDay: CodexWindow(usedPercent: 20, windowMinutes: 10_080, resetsAt: ontem)
        )
        #expect(CodexCollector.windows(from: fossil, now: Date()).isEmpty)
    }
}

// MARK: - Dedup: QUAL ocorrência sobrevive

@Suite("Dedup — a mesma mensagem, escrita várias vezes")
struct DedupTests {

    /// A ARMADILHA QUE CUSTAVA 9,8% DO OUTPUT.
    ///
    /// O Claude Code reescreve a MESMA mensagem (mesmo requestId, mesmo message.id, no
    /// mesmo arquivo) enquanto ela é gerada. O `output_tokens` cresce a cada reescrita.
    /// Ficar com a PRIMEIRA ocorrência congela a mensagem no começo dela.
    ///
    /// No disco real do Jair (13/07): 7.360 chaves afetadas, 3.477.980 tokens de output
    /// a menos. E output é o bucket CARO — Opus cobra US$ 75/M contra US$ 15/M do input.
    @Test("streaming: fica a ocorrência de MAIOR total, não a primeira")
    func streamingKeepsTheLargest() async throws {
        let dir = try TempDir()
        try [
            claudeAssistant(req: "req_1", msg: "msg_1", output: 5),
            claudeAssistant(req: "req_1", msg: "msg_1", output: 5),
            claudeAssistant(req: "req_1", msg: "msg_1", output: 330),  // a mensagem pronta
        ].joined(separator: "\n").appending("\n")
            .write(to: dir.url.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)

        let r = try await ClaudeCodeCollector(
            root: dir.url, pricing: try PricingTable.bundled()
        ).collectDetailed()

        #expect(r.events.count == 1)                 // é UMA request, não três
        #expect(r.events.first?.tokens.output == 330)  // e ela custou 330, não 5
    }

    /// E por que não simplesmente a ÚLTIMA, que seria o óbvio pro caso acima?
    /// Porque existe registro TRUNCADO: no disco real, uma chave (em 46.518) tem a última
    /// ocorrência ZERADA em todos os buckets. "Última" jogaria 271 mil tokens fora.
    /// "Maior total" acerta os dois casos — e é a única regra que não depende da ordem
    /// em que os arquivos foram lidos.
    @Test("registro truncado no fim: a última é ZERO, e zero não é a verdade")
    func truncatedLastIsIgnored() async throws {
        let dir = try TempDir()
        try [
            claudeAssistant(req: "req_2", msg: "msg_2", output: 3, cacheRead: 271_165),
            claudeAssistant(req: "req_2", msg: "msg_2", output: 0, cacheRead: 0),
        ].joined(separator: "\n").appending("\n")
            .write(to: dir.url.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)

        let r = try await ClaudeCodeCollector(
            root: dir.url, pricing: try PricingTable.bundled()
        ).collectDetailed()

        #expect(r.events.count == 1)
        #expect(r.events.first?.tokens.cacheRead == 271_165)  // e NÃO 0
    }

    /// A consequência mais traiçoeira da regra antiga: "primeira" depende da ordem do
    /// readdir. Um arquivo novo entrando reordenava a varredura e mudava o total de um
    /// dia ANTIGO — sem ninguém ter gasto nada. O total tem que ser função do CONTEÚDO
    /// do disco, não da ordem em que ele foi lido.
    @Test("o total não depende da ordem dos arquivos")
    func totalIsOrderIndependent() async throws {
        func total(reverse: Bool) async throws -> Int {
            let dir = try TempDir()
            // a mesma request, meia num arquivo e completa no outro.
            let a = claudeAssistant(req: "req_3", msg: "msg_3", output: 7) + "\n"
            let b = claudeAssistant(req: "req_3", msg: "msg_3", output: 900) + "\n"
            // os nomes decidem a ordem do enumerator; invertê-los inverte a varredura.
            try (reverse ? b : a).write(
                to: dir.url.appending(path: "1.jsonl"), atomically: true, encoding: .utf8)
            try (reverse ? a : b).write(
                to: dir.url.appending(path: "2.jsonl"), atomically: true, encoding: .utf8)

            let r = try await ClaudeCodeCollector(
                root: dir.url, pricing: try PricingTable.bundled()
            ).collectDetailed()
            return r.events.reduce(0) { $0 + $1.tokens.output }
        }

        #expect(try await total(reverse: false) == 900)
        #expect(try await total(reverse: true) == 900)
    }
}

// MARK: - Agregação incremental

@Suite("Agregação incremental — refazer só o que mudou dá o MESMO número")
struct IncrementalAggregationTests {

    /// A pergunta que decide se o cache por arquivo pode existir: ele MENTE?
    /// Um collector que viu o disco crescer aos poucos tem que chegar no mesmo número
    /// de um collector que viu o disco pronto de uma vez. Se não chegar, o cache é um bug
    /// com cara de otimização.
    @Test("o incremental chega no MESMO número que o scan do zero")
    func incrementalEqualsFullRebuild() async throws {
        let dir = try TempDir()
        let pricing = try PricingTable.bundled()

        func write(_ name: String, _ linhas: [String]) throws {
            try (linhas.joined(separator: "\n") + "\n").write(
                to: dir.url.appending(path: name), atomically: true, encoding: .utf8)
        }

        try write("a.jsonl", [claudeAssistant(req: "r1", msg: "m1", output: 100)])
        try write("b.jsonl", [claudeAssistant(req: "r2", msg: "m2", output: 200)])

        // Este viu o disco crescer: lê, depois o disco muda, lê de novo.
        let vivo = ClaudeCodeCollector(root: dir.url, pricing: pricing)
        _ = try await vivo.collectDetailed()

        // a.jsonl CRESCE (streaming: a mesma request, agora completa) e nasce um c.jsonl.
        try write("a.jsonl", [
            claudeAssistant(req: "r1", msg: "m1", output: 100),
            claudeAssistant(req: "r1", msg: "m1", output: 555),   // a mensagem pronta
        ])
        try write("c.jsonl", [claudeAssistant(req: "r3", msg: "m3", output: 300)])

        let incremental = try await vivo.collectDetailed()

        // Este chega agora e vê o disco pronto. É a verdade contra a qual o outro é medido.
        let doZero = try await ClaudeCodeCollector(root: dir.url, pricing: pricing).collectDetailed()

        let incrementalIds = incremental.events.map(\.id).sorted()
        let doZeroIds = doZero.events.map(\.id).sorted()
        let incrementalOutput = incremental.events.reduce(0) { $0 + $1.tokens.output }
        let doZeroOutput = doZero.events.reduce(0) { $0 + $1.tokens.output }

        #expect(incremental.events.count == doZero.events.count)
        #expect(incrementalIds == doZeroIds)
        #expect(incrementalOutput == doZeroOutput)
        // e o valor certo: r1 conta 555 (não 100, nem 100+555), r2 200, r3 300.
        let esperado = 555 + 200 + 300
        #expect(incrementalOutput == esperado)
    }

    /// Arquivo REESCRITO encolhendo: o que sumiu tem que sumir da conta também.
    /// Um cache que só sabe somar vira um vazamento de tokens.
    @Test("arquivo reescrito menor: os eventos que sumiram saem da conta")
    func rewriteDropsOldEvents() async throws {
        let dir = try TempDir()
        let pricing = try PricingTable.bundled()
        let f = dir.url.appending(path: "a.jsonl")

        try (claudeAssistant(req: "r1", msg: "m1", output: 100) + "\n"
           + claudeAssistant(req: "r2", msg: "m2", output: 200) + "\n")
            .write(to: f, atomically: true, encoding: .utf8)

        let c = ClaudeCodeCollector(root: dir.url, pricing: pricing)
        #expect(try await c.collectDetailed().events.count == 2)

        // reescrito: r2 sumiu.
        try (claudeAssistant(req: "r1", msg: "m1", output: 100) + "\n")
            .write(to: f, atomically: true, encoding: .utf8)

        let r = try await c.collectDetailed()
        let rOutput = r.events.reduce(0) { $0 + $1.tokens.output }
        #expect(r.events.count == 1)
        #expect(rOutput == 100)
    }

    /// Arquivo APAGADO: idem.
    @Test("arquivo apagado: os eventos dele saem da conta")
    func deleteDropsEvents() async throws {
        let dir = try TempDir()
        let pricing = try PricingTable.bundled()

        for (n, r) in [("a.jsonl", "r1"), ("b.jsonl", "r2")] {
            try (claudeAssistant(req: r, msg: "m", output: 100) + "\n")
                .write(to: dir.url.appending(path: n), atomically: true, encoding: .utf8)
        }

        let c = ClaudeCodeCollector(root: dir.url, pricing: pricing)
        #expect(try await c.collectDetailed().events.count == 2)

        try FileManager.default.removeItem(at: dir.url.appending(path: "b.jsonl"))
        #expect(try await c.collectDetailed().events.count == 1)
    }

    /// A PROMESSA DE PERFORMANCE, num disco de verdade em miniatura.
    ///
    /// Antes: UM arquivo crescer reconstruía os 45 mil eventos — dedup + Decimal de custo
    /// + ordenação (395 ms medidos no disco do Jair). E enquanto o usuário trabalha, SEMPRE
    /// tem arquivo crescendo: o caso comum era o caro.
    /// Agora: refaz só o arquivo que mexeu e junta o resto por merge linear.
    @Test("um arquivo que cresce NÃO reconstrói o mundo")
    func appendDoesNotRebuildTheWorld() async throws {
        let dir = try TempDir()
        let pricing = try PricingTable.bundled()

        // 300 arquivos × 150 linhas = 45 mil linhas — a mesma ORDEM de grandeza do disco
        // real (93 mil linhas, 45 mil eventos). A proporção importa: com muitos arquivos
        // pequenos, o custo de VARRER o diretório domina e esconde justamente o custo que
        // este teste existe pra medir, que é o de AGREGAR.
        for i in 0..<300 {
            let linhas = (0..<150).map {
                claudeAssistant(req: "r\(i)-\($0)", msg: "m\(i)-\($0)", output: 50)
            }
            try (linhas.joined(separator: "\n") + "\n").write(
                to: dir.url.appending(path: "f\(i).jsonl"), atomically: true, encoding: .utf8)
        }

        let c = ClaudeCodeCollector(root: dir.url, pricing: pricing)

        let t0 = DispatchTime.now()
        _ = try await c.collectDetailed()
        let completo = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9

        // UM arquivo cresce.
        let h = try FileHandle(forWritingTo: dir.url.appending(path: "f7.jsonl"))
        try h.seekToEnd()
        try h.write(contentsOf: Data((claudeAssistant(req: "novo", msg: "novo", output: 9) + "\n").utf8))
        try h.close()

        let t1 = DispatchTime.now()
        let r = try await c.collectDetailed()
        let incremental = Double(DispatchTime.now().uptimeNanoseconds - t1.uptimeNanoseconds) / 1e9

        #expect(r.diagnostics.scan.filesAppended == 1)
        #expect(r.events.count == 300 * 150 + 1)   // e o evento novo entrou
        #expect(
            incremental < completo / 3,
            Comment(rawValue: "completo=\(Int(completo * 1000))ms "
                + "incremental=\(Int(incremental * 1000))ms — o append reconstruiu o mundo?")
        )
    }
}

// MARK: - Helpers

/// Uma linha `assistant` do disco do Claude, com o mínimo que o parser exige.
func claudeAssistant(
    req: String,
    msg: String,
    output: Int,
    input: Int = 10,
    cacheWrite: Int = 0,
    cacheRead: Int = 0,
    ts: String = "2026-07-01T12:00:00.000Z",
    model: String = "claude-opus-4-8"
) -> String {
    """
    {"type":"assistant","timestamp":"\(ts)","requestId":"\(req)","sessionId":"sess",\
    "message":{"id":"\(msg)","model":"\(model)","usage":{"input_tokens":\(input),\
    "output_tokens":\(output),"cache_creation_input_tokens":\(cacheWrite),\
    "cache_read_input_tokens":\(cacheRead)}}}
    """
}

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
