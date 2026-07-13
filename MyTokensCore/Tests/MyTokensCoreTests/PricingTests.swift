import Foundation
import Testing

@testable import MyTokensCore

@Suite("Preço — 4 buckets, Decimal, nunca Double")
struct PricingTests {

    @Test("o pricing.json embarcado é BYTE A BYTE igual ao data/pricing.json")
    func bundledDoesNotDriftFromCanonical() throws {
        // O bundle precisa de uma cópia (symlink não sobrevive ao .copy do SwiftPM), e
        // cópia é convite a dessincronizar. Este teste é o guarda: o Sonda mexe no preço
        // em data/pricing.json e esquece de propagar? Aqui quebra, na hora.
        // Propagar:  cp data/pricing.json MyTokensCore/Sources/MyTokensCore/Resources/
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MyTokensCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MyTokensCore
            .deletingLastPathComponent()  // repo

        let canonicalURL = repo.appending(path: "data/pricing.json")
        // `Bundle.module` resolve por MÓDULO: aqui dentro do teste, ele é o bundle DE
        // TESTE — que não tem o pricing.json, porque o recurso é do target do core.
        // O arquivo que de fato vai pro bundle é este, e é ele que tem que bater.
        let bundledURL = repo.appending(path: "MyTokensCore/Sources/MyTokensCore/Resources/pricing.json")

        #expect(
            try Data(contentsOf: bundledURL) == Data(contentsOf: canonicalURL),
            "pricing.json do bundle divergiu de data/pricing.json — recopie"
        )

        let bundled = try PricingTable.bundled()
        let canonical = try PricingTable.load(from: canonicalURL)
        #expect(bundled.modelIDs == canonical.modelIDs)
    }

    @Test("Decimal vem do texto, não do Double — 0.175 é exato")
    func decimalIsExact() throws {
        let p = try PricingTable.bundled()
        let codex = try #require(p.price(for: "gpt-5.3-codex"))
        #expect(codex.cacheRead == Decimal(string: "0.175"))

        // O ponto NÃO é que `Decimal(0.175)` erre — ele até acerta, porque converte pro
        // decimal mais curto que representa aquele Double. O ponto é a ARITMÉTICA: em
        // Double, somar o mesmo preço 10x não dá o preço × 10, e é somando preço milhares
        // de vezes que este app calcula custo. Em Decimal, dá.
        let preco = try #require(codex.cacheRead)
        let dezVezes = (1...10).reduce(Decimal(0)) { acc, _ in acc + preco }
        #expect(dezVezes == Decimal(string: "1.75")!)

        let emDouble = (1...10).reduce(0.0) { acc, _ in acc + 0.175 }
        #expect(emDouble != 1.75, "se o Double acertasse, este teste não teria razão de existir")
    }

    @Test("sufixo de data cai fora: o disco diz claude-haiku-4-5-20251001")
    func normalizesDateSuffix() throws {
        let p = try PricingTable.bundled()
        #expect(PricingTable.normalize("claude-haiku-4-5-20251001") == "claude-haiku-4-5")
        #expect(p.price(for: "claude-haiku-4-5-20251001") != nil)
        #expect(p.price(for: "claude-haiku-4-5-20251001") == p.price(for: "claude-haiku-4-5"))
    }

    @Test("modelo desconhecido devolve nil — NÃO chuta preço nem devolve zero silencioso")
    func unknownModelIsNil() throws {
        let p = try PricingTable.bundled()
        #expect(p.price(for: "gpt-5.2-codex") == nil)
        #expect(p.cost(model: "modelo-que-nao-existe", tokens: TokenBuckets(input: 1000)) == nil)
    }

    @Test("os 4 buckets têm preços diferentes: cache-read é 10x MAIS BARATO que input")
    func fourBucketsFourPrices() throws {
        let p = try PricingTable.bundled()
        let opus = try #require(p.price(for: "claude-opus-4-8"))

        #expect(opus.input == 5)
        #expect(opus.output == 25)
        #expect(opus.cacheWrite5m == Decimal(string: "6.25"))  // 1.25x input
        #expect(opus.cacheWrite1h == 10)                       // 2x input
        #expect(opus.cacheRead == Decimal(string: "0.50"))     // 0.1x input

        // 1M tokens em cada bucket, um de cada vez.
        let m = 1_000_000
        #expect(p.cost(model: "claude-opus-4-8", tokens: TokenBuckets(input: m)) == 5)
        #expect(p.cost(model: "claude-opus-4-8", tokens: TokenBuckets(output: m)) == 25)
        #expect(p.cost(model: "claude-opus-4-8", tokens: TokenBuckets(cacheRead: m)) == Decimal(string: "0.50"))

        // Colapsar cache-read como input cobraria 10x a mais. É essa a mentira.
        let honesto = p.cost(model: "claude-opus-4-8", tokens: TokenBuckets(cacheRead: m))!
        let mentira = p.cost(model: "claude-opus-4-8", tokens: TokenBuckets(input: m))!
        #expect(mentira == honesto * 10)
    }

    @Test("cache-write cobra por TTL: 5m e 1h têm preços diferentes")
    func cacheWriteSplitsByTTL() throws {
        let p = try PricingTable.bundled()
        let m = 1_000_000

        let cinco = TokenBuckets(cacheWrite: m, cacheWrite5m: m, cacheWrite1h: 0)
        let hora = TokenBuckets(cacheWrite: m, cacheWrite5m: 0, cacheWrite1h: m)
        #expect(p.cost(model: "claude-opus-4-8", tokens: cinco) == Decimal(string: "6.25"))
        #expect(p.cost(model: "claude-opus-4-8", tokens: hora) == 10)

        // Sem detalhe de TTL no disco, assume 5m (o mais barato dos dois) — documentado.
        let semDetalhe = TokenBuckets(cacheWrite: m)
        #expect(p.cost(model: "claude-opus-4-8", tokens: semDetalhe) == Decimal(string: "6.25"))
    }

    @Test("soma dos 4 buckets, na mão, bate exato")
    func fullCost() throws {
        let p = try PricingTable.bundled()
        let t = TokenBuckets(
            input: 100_000, output: 50_000,
            cacheWrite: 200_000, cacheRead: 3_000_000,
            cacheWrite5m: 200_000, cacheWrite1h: 0
        )
        // 0.1*5 + 0.05*25 + 0.2*6.25 + 3*0.50 = 0.5 + 1.25 + 1.25 + 1.5 = 4.50
        #expect(p.cost(model: "claude-opus-4-8", tokens: t) == Decimal(string: "4.50"))
    }

    @Test("OpenAI não cobra escrita de cache — cache_write é null e vira zero")
    func openAIHasNoCacheWrite() throws {
        let p = try PricingTable.bundled()
        let gpt = try #require(p.price(for: "gpt-5.4"))
        #expect(gpt.cacheWrite5m == nil)
        #expect(p.cost(model: "gpt-5.4", tokens: TokenBuckets(cacheWrite: 1_000_000)) == 0)
        #expect(p.cost(model: "gpt-5.4", tokens: TokenBuckets(cacheRead: 1_000_000)) == Decimal(string: "0.25"))
    }
}
