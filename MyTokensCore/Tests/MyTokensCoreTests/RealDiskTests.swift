// Testes contra o DISCO REAL do Jair. Não é fixture inventada.
//
// Core com 100% de cobertura em fixture e 0% em dado real é core que não foi testado.
// Aqui o oráculo é o probe do Sonda (scripts/probe/scan-claude.ts), que já provou os
// números. Se o Swift discorda do probe, um dos dois está errado.
//
// COMO ISSO SOBREVIVE AO DISCO CRESCENDO: o total muda toda hora (o Jair está usando o
// Claude agora mesmo). Mas o passado é imutável — nenhum requestId de ontem muda. Então
// o teste compara DIA A DIA, em UTC, excluindo o dia de hoje. Todo dia passado tem que
// bater com o probe BYTE A BYTE, nos 4 buckets, por modelo. É comparação exata, não
// tolerância.
//
// Sem ~/.claude no disco (CI), os testes se desativam sozinhos.

import Foundation
import Testing

@testable import MyTokensCore

struct ProbeSnapshot: Sendable {
    let uniqueRequestIds: Int
    let rawTotal: Int
    let dedupTotal: Int
    let ratio: Double
    /// dia (UTC) -> modelo -> bucket -> tokens
    let byDayDedup: [String: [String: [String: Int]]]

    static func load() throws -> ProbeSnapshot {
        let url = try #require(Bundle.module.url(
            forResource: "probe-claude", withExtension: "json", subdirectory: "Fixtures"
        ))
        let root = try #require(
            JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        let infl = root["inflation"] as! [String: Any]
        return ProbeSnapshot(
            uniqueRequestIds: root["uniqueRequestIds"] as! Int,
            rawTotal: (infl["rawTotalTokens"] as! NSNumber).intValue,
            dedupTotal: (infl["dedupTotalTokens"] as! NSNumber).intValue,
            ratio: (infl["rawOverDedupRatio"] as! NSNumber).doubleValue,
            byDayDedup: root["byDayDedup"] as! [String: [String: [String: Int]]]
        )
    }
}

/// A PROMESSA é 200 ms — no binário que o usuário roda, que é RELEASE.
///
/// O teste, por padrão, compila em DEBUG: sem otimização, o mesmo trabalho custa de 5 a
/// 10x mais. Cobrar 200 ms em debug não mede o produto, mede o compilador — e o jeito
/// covarde de fazer o vermelho sumir seria afrouxar a meta pra 1 s e chamar de "meta".
///
/// Então a meta REAL vale onde ela é real, e o debug ganha um teto largo, que só serve
/// pra pegar regressão grosseira (um O(n²) novo, um reparse do mundo).
///   Medido em release em 13/07: Claude 103 ms, Codex 97 ms, refresh completo 157 ms.
///   Conferir com:  swift test -c release
enum PerfBudget {
    #if DEBUG
    static let incremental: TimeInterval = 1.2
    static let config = "debug (teto largo — a promessa de 200 ms é medida em release)"
    #else
    static let incremental: TimeInterval = 0.200
    static let config = "release (a promessa)"
    #endif

    static func recado(_ inc: TimeInterval) -> Comment {
        Comment(rawValue: "incremental levou \(Int(inc * 1000))ms — teto de "
            + "\(Int(incremental * 1000))ms em \(config)")
    }

    /// O MENOR de 5. As suítes do swift-testing rodam EM PARALELO, e as outras estão
    /// varrendo 1 GB de disco enquanto esta mede — sob contenção, uma medição única mede
    /// a máquina, não o código (o mesmo refresh deu 103 ms sozinho e 803 ms no meio da
    /// suíte). O mínimo é a medida limpa: é o custo quando ninguém está atrapalhando.
    /// Regressão de verdade (um reparse do mundo, um O(n²) novo) suja TODAS as 5.
    static func bestOfFive<T>(_ body: () async throws -> T) async rethrows -> (TimeInterval, T) {
        var best = TimeInterval.infinity
        var last: T!
        for _ in 1...5 {
            let t = DispatchTime.now()
            last = try await body()
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e9
            best = min(best, dt)
        }
        return (best, last)
    }
}

let claudeRoot = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/projects")
let hasClaudeDisk = FileManager.default.fileExists(atPath: claudeRoot.path)

@Suite("Disco real — Claude", .enabled(if: hasClaudeDisk))
struct ClaudeRealDiskTests {

    /// SE ESTE TESTE FICAR VERMELHO, leia isto antes de mexer no parser.
    ///
    /// A fixture é um retrato do disco num INSTANTE. E o disco do Claude NÃO é um
    /// livro-razão append-only: sessão retomada e compactada REESCREVE o passado. Em
    /// 13/07 o dia 13/06 perdeu ~10 mil tokens de input entre 09:59 e 11:50 — sem
    /// ninguém tocar no código.
    ///
    /// Antes de acusar o core, RODE O PROBE DE NOVO e compare com ele, não com a fixture:
    ///     cp scripts/probe/scan-claude.ts /tmp/p.mts && npx tsx /tmp/p.mts > /tmp/probe.json
    /// Se o probe fresco bate com o core, o parser está certo e a fixture é que envelheceu:
    ///     cp /tmp/probe.json MyTokensCore/Tests/MyTokensCoreTests/Fixtures/probe-claude.json
    ///
    /// O valor deste teste NÃO é a igualdade em si — é ter DUAS implementações
    /// independentes (TS e Swift) que precisam concordar sobre o mesmo disco.
    @Test("o número do core BATE com o probe do Sonda, dia a dia, bucket a bucket")
    func matchesProbeDayByDay() async throws {
        let probe = try ProbeSnapshot.load()
        let r = try await ClaudeCodeCollector(pricing: try PricingTable.bundled()).collectDetailed()

        // Hoje ainda está sendo escrito (estou gastando token AGORA). Fica de fora.
        let hoje = ISO8601Stamp.utcDay(Date())

        var meu: [String: [String: TokenBuckets]] = [:]
        for e in r.events {
            let day = ISO8601Stamp.utcDay(e.ts)
            guard day != hoje else { continue }
            meu[day, default: [:]][e.model, default: TokenBuckets()] += e.tokens
        }

        var diasConferidos = 0
        for (dia, modelosProbe) in probe.byDayDedup where dia != hoje {
            let modelosMeus = try #require(meu[dia], "dia \(dia) sumiu do meu core")

            for (modelo, bucketsProbe) in modelosProbe {
                let meuB = try #require(
                    modelosMeus[modelo],
                    "dia \(dia): o probe viu o modelo \(modelo) e eu não"
                )
                #expect(meuB.input == bucketsProbe["input_tokens"], "input em \(dia)/\(modelo)")
                #expect(meuB.output == bucketsProbe["output_tokens"], "output em \(dia)/\(modelo)")
                #expect(
                    meuB.cacheWrite == bucketsProbe["cache_creation_input_tokens"],
                    "cache-write em \(dia)/\(modelo)"
                )
                #expect(
                    meuB.cacheRead == bucketsProbe["cache_read_input_tokens"],
                    "cache-read em \(dia)/\(modelo)"
                )
            }
            diasConferidos += 1
        }

        #expect(diasConferidos >= 40, "conferi só \(diasConferidos) dias — fixture vazia?")
    }

    @Test("dedup derruba o total: raw é ~2,12x a verdade. É a razão de existir do app.")
    func dedupCutsTheTotalInHalf() async throws {
        let probe = try ProbeSnapshot.load()
        let r = try await ClaudeCodeCollector(pricing: try PricingTable.bundled()).collectDetailed()
        let d = r.diagnostics

        #expect(d.rawTokens > d.dedupTokens)
        // O disco cresceu desde o probe, então o total é >=. A RAZÃO é que é estável.
        #expect(d.rawTokens >= probe.rawTotal)
        #expect(d.dedupTokens >= probe.dedupTotal)
        #expect(abs(d.inflationRatio - probe.ratio) < 0.02,
                "inflação \(d.inflationRatio) vs probe \(probe.ratio)")
        #expect(d.uniqueRequestIds >= probe.uniqueRequestIds)
        // ~2,06 linhas por chamada de API: cada content block repete o usage inteiro.
        #expect(Double(d.assistantRows) / Double(d.uniqueRequestIds) > 1.5)
    }

    @Test("todo evento tem chave de dedup única — nenhuma colisão engoliu gasto")
    func everyEventHasUniqueKey() async throws {
        let r = try await ClaudeCodeCollector(pricing: try PricingTable.bundled()).collectDetailed()
        #expect(Set(r.events.map(\.id)).count == r.events.count)
        #expect(r.events.count == r.diagnostics.uniqueRequestIds)
    }

    @Test("cache-read é a esmagadora maioria do volume — colapsar buckets mentiria no custo")
    func cacheReadDominates() async throws {
        let r = try await ClaudeCodeCollector(pricing: try PricingTable.bundled()).collectDetailed()
        let b = r.diagnostics.dedupBuckets
        let share = Double(b.cacheRead) / Double(b.total)
        #expect(share > 0.80, "cache-read é \(Int(share * 100))% do volume")

        // Se cobrássemos cache-read a preço de input, o custo explodiria.
        let p = try PricingTable.bundled()
        let honesto = p.cost(model: "claude-opus-4-8", tokens: b)!
        let colapsado = p.cost(
            model: "claude-opus-4-8", tokens: TokenBuckets(input: b.total)
        )!
        #expect(colapsado > honesto * 5)
    }

    @Test("todo modelo do disco tem preço — nenhum custo saiu chutado nem zerado à toa")
    func everyModelIsPriced() async throws {
        let r = try await ClaudeCodeCollector(pricing: try PricingTable.bundled()).collectDetailed()
        #expect(r.diagnostics.unpricedModels.isEmpty,
                "sem preço: \(r.diagnostics.unpricedModels.sorted())")
        #expect(r.events.allSatisfy { $0.costUSD >= 0 })
    }

    @Test("PERFORMANCE: refresh incremental abaixo de 200ms")
    func incrementalRefreshIsFast() async throws {
        let c = ClaudeCodeCollector(pricing: try PricingTable.bundled())

        let t0 = DispatchTime.now()
        _ = try await c.collectDetailed()
        let full = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9

        let (inc, r2) = try await PerfBudget.bestOfFive { try await c.collectDetailed() }

        // O 2º scan não pode reparsear o mundo: quase tudo tem que vir do cache.
        #expect(r2.diagnostics.scan.filesUnchanged > r2.diagnostics.scan.filesReparsed)
        #expect(r2.diagnostics.scan.bytesRead < 20_000_000, "leu \(r2.diagnostics.scan.bytesRead) bytes de novo")
        #expect(inc < PerfBudget.incremental, PerfBudget.recado(inc))
        #expect(inc < full)
    }
}

// As MESMAS raízes que o collector varre — perguntadas a ele, não recopiadas.
// O oráculo de um teste que olha um disco diferente do código não é oráculo: é um
// segundo bug, e ele acusa o código certo de estar errado.
let codexRoots = CodexCollector.defaultRoots()
let hasCodexDisk = codexRoots.contains { FileManager.default.fileExists(atPath: $0.path) }

@Suite("Disco real — Codex", .enabled(if: hasCodexDisk))
struct CodexRealDiskTests {

    @Test("a soma dos deltas == a soma do último acumulado de cada sessão")
    func deltasEqualLastCumulativePerSession() async throws {
        // Esta é A invariante do Codex. O probe do Sonda soma o ÚLTIMO evento de cada
        // sessão; eu somo deltas turno a turno (pra acertar data e modelo). Os dois TÊM
        // que dar o mesmo número — senão eu estou contando token que não existe.
        let c = CodexCollector(pricing: try PricingTable.bundled())
        let r = try await c.collectDetailed()

        var porSessao: [String: Int] = [:]
        for e in r.events {
            // a chave de dedup é <arquivo>#<linha>; o arquivo é a sessão.
            let file = e.id.split(separator: "#").first.map(String.init) ?? e.id
            porSessao[file, default: 0] += e.tokens.total
        }
        let somaDeltas = porSessao.values.reduce(0, +)

        // e o mesmo número lido do jeito do probe: último total_token_usage por arquivo.
        var somaUltimo = 0
        for f in codexRoots.flatMap({ FileWalker.jsonl(under: $0, namePrefix: "rollout-") }) {
            guard let txt = try? String(contentsOf: f.url, encoding: .utf8) else { continue }
            var last: (input: Int, output: Int)?
            for line in txt.split(separator: "\n") where line.contains("\"token_count\"") {
                guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let p = o["payload"] as? [String: Any],
                      let info = p["info"] as? [String: Any],
                      let tu = info["total_token_usage"] as? [String: Any]
                else { continue }
                last = (
                    (tu["input_tokens"] as? NSNumber)?.intValue ?? 0,
                    (tu["output_tokens"] as? NSNumber)?.intValue ?? 0
                )
            }
            if let last { somaUltimo += last.input + last.output }
        }

        #expect(somaDeltas == somaUltimo, "deltas=\(somaDeltas) último=\(somaUltimo)")
        #expect(r.diagnostics.correctTokens == somaUltimo)
    }

    @Test("somar todo token_count infla dezenas de vezes — a armadilha existe mesmo")
    func naiveSumIsWildlyInflated() async throws {
        let r = try await CodexCollector(pricing: try PricingTable.bundled()).collectDetailed()
        #expect(r.diagnostics.naiveTokens > r.diagnostics.correctTokens * 10)
        #expect(r.diagnostics.naiveOverCorrectRatio > 10)
    }

    @Test("eventos têm chave única e todo modelo conhecido tem preço")
    func uniqueKeysAndPricing() async throws {
        let r = try await CodexCollector(pricing: try PricingTable.bundled()).collectDetailed()
        #expect(Set(r.events.map(\.id)).count == r.events.count)
        // gpt-5.2-codex e gpt-5.4-mini NÃO estão no pricing.json. Não chuto preço: eles
        // saem listados aqui e o custo deles fica zerado, explicitamente.
        for m in r.diagnostics.unpricedModels {
            #expect(try PricingTable.bundled().price(for: m) == nil)
        }
    }

    @Test("PERFORMANCE: refresh incremental abaixo de 200ms")
    func incrementalIsFast() async throws {
        let c = CodexCollector(pricing: try PricingTable.bundled())
        _ = try await c.collectDetailed()
        let (inc, r) = try await PerfBudget.bestOfFive { try await c.collectDetailed() }
        #expect(inc < PerfBudget.incremental, PerfBudget.recado(inc))
        #expect(r.diagnostics.scan.bytesRead == 0)  // nada mudou: zero byte relido.
    }
}
