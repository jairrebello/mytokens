// O cache incremental. Se ele mentir, todo número depois dele mente.

import Foundation
import Testing

@testable import MyTokensCore

/// Parser bobo: só conta linhas. Isola a mecânica do cache do parsing de verdade.
struct LineCounter: IncrementalFileParser {
    func digest(newBytes: Data, file: URL, previous: [String]?) -> [String] {
        var out = previous ?? []
        for line in newBytes.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            out.append(String(decoding: line, as: UTF8.self))
        }
        return out
    }
}

/// O scanner exige tamanho e mtime JÁ LIDOS (o walker os pega de graça do enumerator).
/// Aqui, com uma URL solta na mão, a gente paga o stat — é teste, e um arquivo só.
func stat(_ u: URL) -> ScannedFile { ScannedFile(stating: u)! }

@Suite("Cache incremental — (arquivo, mtime, offset)")
struct ScannerTests {

    @Test("arquivo que cresceu: só o rabo é lido")
    func appendReadsOnlyTheTail() async throws {
        let dir = try TempDir()
        let f = dir.url.appending(path: "a.jsonl")
        try "um\ndois\n".write(to: f, atomically: true, encoding: .utf8)

        let s = IncrementalScanner(parser: LineCounter())
        let r1 = await s.scan(files: [stat(f)])
        #expect(r1.digests[f.path] == ["um", "dois"])
        #expect(r1.stats.bytesRead == 8)  // "um\ndois\n" = 2+1+4+1. São 8.

        // append
        let h = try FileHandle(forWritingTo: f)
        try h.seekToEnd()
        try h.write(contentsOf: Data("tres\n".utf8))
        try h.close()

        let r2 = await s.scan(files: [stat(f)])
        #expect(r2.digests[f.path] == ["um", "dois", "tres"])
        #expect(r2.stats.filesAppended == 1)
        #expect(r2.stats.filesReparsed == 0)
        #expect(r2.stats.bytesRead == 5)  // só "tres\n". NÃO releu o arquivo todo.
    }

    @Test("nada mudou: ZERO byte lido")
    func unchangedReadsNothing() async throws {
        let dir = try TempDir()
        let f = dir.url.appending(path: "a.jsonl")
        try "um\ndois\n".write(to: f, atomically: true, encoding: .utf8)

        let s = IncrementalScanner(parser: LineCounter())
        _ = await s.scan(files: [stat(f)])
        let r = await s.scan(files: [stat(f)])

        #expect(r.stats.filesUnchanged == 1)
        #expect(r.stats.bytesRead == 0)
        #expect(r.digests[f.path] == ["um", "dois"])  // veio do cache, de graça.
    }

    @Test("linha pela metade (escrita em voo) NÃO é consumida — espera o \\n")
    func partialLineIsNotConsumed() async throws {
        let dir = try TempDir()
        let f = dir.url.appending(path: "a.jsonl")
        try "um\ndoi".write(to: f, atomically: true, encoding: .utf8)  // sem \n no fim

        let s = IncrementalScanner(parser: LineCounter())
        let r1 = await s.scan(files: [stat(f)])
        #expect(r1.digests[f.path] == ["um"])  // "doi" fica pra depois

        // o resto chega
        let h = try FileHandle(forWritingTo: f)
        try h.seekToEnd()
        try h.write(contentsOf: Data("s\ntres\n".utf8))
        try h.close()

        let r2 = await s.scan(files: [stat(f)])
        #expect(r2.digests[f.path] == ["um", "dois", "tres"])  // "dois" inteiro, não "s"
    }

    @Test("arquivo encolheu ou foi reescrito: reparse TOTAL, o offset não vale mais")
    func rewriteForcesFullReparse() async throws {
        let dir = try TempDir()
        let f = dir.url.appending(path: "a.jsonl")
        try "um\ndois\ntres\n".write(to: f, atomically: true, encoding: .utf8)

        let s = IncrementalScanner(parser: LineCounter())
        _ = await s.scan(files: [stat(f)])

        try "outro\n".write(to: f, atomically: true, encoding: .utf8)  // encolheu
        let r = await s.scan(files: [stat(f)])

        #expect(r.stats.filesReparsed == 1)
        #expect(r.digests[f.path] == ["outro"])  // não pode sobrar lixo do anterior
    }

    @Test("arquivo apagado sai do cache")
    func deletedFileIsEvicted() async throws {
        let dir = try TempDir()
        let f = dir.url.appending(path: "a.jsonl")
        try "um\n".write(to: f, atomically: true, encoding: .utf8)

        let s = IncrementalScanner(parser: LineCounter())
        _ = await s.scan(files: [stat(f)])
        #expect(await s.cachedFileCount == 1)

        try FileManager.default.removeItem(at: f)
        let r = await s.scan(files: [])
        #expect(r.digests.isEmpty)
        #expect(await s.cachedFileCount == 0)
    }
}

@Suite("Agregação — janela / dia / semana / mês")
struct AggregatorTests {

    func evento(_ iso: String, model: String = "claude-opus-4-8", project: String? = "p",
                tokens: Int = 100, cost: Decimal = 1) -> UsageEvent {
        UsageEvent(
            id: UUID().uuidString, provider: .claudeCode, ts: ISO8601.date(iso)!,
            sessionId: "s", model: model, project: project,
            tokens: TokenBuckets(input: tokens), costUSD: cost
        )
    }

    @Test("bloco de 5h ancora no 1º evento e ROLA — não é hora cheia de relógio")
    func fiveHourBlocksAreRolling() {
        // docs/FONTES.md §2: 0 de 40 resets_at caem em hora cheia. Arredondar é chute.
        let eventos = [
            evento("2026-07-06T12:08:32Z"),  // abre o bloco -> vence 17:08:32
            evento("2026-07-06T14:00:00Z"),  // dentro
            evento("2026-07-06T17:00:00Z"),  // ainda dentro (17:00 < 17:08:32)
            evento("2026-07-06T17:09:27Z"),  // bloco venceu -> abre outro
        ]
        let blocos = Aggregator.fiveHourBlocks(eventos)

        #expect(blocos.count == 2)
        #expect(blocos[0].start == ISO8601.date("2026-07-06T12:08:32Z"))
        #expect(blocos[0].end == ISO8601.date("2026-07-06T17:08:32Z"))
        #expect(blocos[0].spend.tokens == 300)  // 3 eventos
        #expect(blocos[1].start == ISO8601.date("2026-07-06T17:09:27Z"))
        #expect(blocos[1].spend.tokens == 100)
    }

    @Test("dia / semana / mês agrupam pelo timestamp do EVENTO, não pela data do arquivo")
    func periodBuckets() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        let eventos = [
            evento("2026-07-06T12:00:00Z"),
            evento("2026-07-06T23:00:00Z"),
            evento("2026-07-07T01:00:00Z"),
            evento("2026-06-30T10:00:00Z"),
        ]

        let dias = Aggregator.by(.day, events: eventos, calendar: cal)
        #expect(dias.count == 3)
        #expect(dias.first(where: { $0.id == "2026-07-06" })?.spend.tokens == 200)
        #expect(dias.first(where: { $0.id == "2026-07-07" })?.spend.tokens == 100)

        let meses = Aggregator.by(.month, events: eventos, calendar: cal)
        #expect(meses.count == 2)
        #expect(meses.first(where: { $0.id == "2026-07" })?.spend.tokens == 300)
        #expect(meses.first(where: { $0.id == "2026-06" })?.spend.tokens == 100)

        #expect(Aggregator.by(.week, events: eventos, calendar: cal).count == 2)
    }

    @Test("por modelo, por projeto, por provider")
    func slices() {
        let eventos = [
            evento("2026-07-06T12:00:00Z", model: "claude-opus-4-8", project: "a", cost: 2),
            evento("2026-07-06T13:00:00Z", model: "claude-sonnet-5", project: "a", cost: 1),
            evento("2026-07-06T14:00:00Z", model: "claude-opus-4-8", project: "b", cost: 3),
        ]

        let m = Aggregator.byModel(eventos)
        #expect(m["claude-opus-4-8"]?.tokens == 200)
        #expect(m["claude-opus-4-8"]?.costUSD == 5)
        #expect(m["claude-sonnet-5"]?.tokens == 100)

        let p = Aggregator.byProject(eventos)
        #expect(p["a"]?.tokens == 200)
        #expect(p["b"]?.costUSD == 3)

        #expect(Aggregator.byProvider(eventos)[.claudeCode]?.costUSD == 6)
    }

    @Test("Spend.byModel guarda tokens por modelo — a view não faz conta")
    func spendCarriesModelBreakdown() {
        let s = Aggregator.spend([
            evento("2026-07-06T12:00:00Z", model: "claude-opus-4-8"),
            evento("2026-07-06T13:00:00Z", model: "claude-opus-4-8"),
            evento("2026-07-06T14:00:00Z", model: "claude-haiku-4-5"),
        ])
        #expect(s.tokens == 300)
        #expect(s.byModel["claude-opus-4-8"] == 200)
        #expect(s.byModel["claude-haiku-4-5"] == 100)
    }

    @Test("TokenBuckets.total NÃO soma reasoning duas vezes (ele já está no output)")
    func reasoningIsNotDoubleCounted() {
        let t = TokenBuckets(input: 10, output: 100, cacheWrite: 5, cacheRead: 1000, reasoning: 40)
        #expect(t.total == 1115)  // e não 1155
    }
}
