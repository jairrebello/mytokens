// Preço. Vem de data/pricing.json. Decimal, NUNCA Double.
//
// Regra 7 do `regras-repo`: 4 buckets separados. cache_read custa ~10x MENOS que
// input; cache_write custa MAIS (1.25x no TTL de 5m, 2x no de 1h). Somar os quatro
// como "input" é mentir no custo — aqui o cache_read é 96% do volume, então o erro
// seria de quase uma ordem de grandeza.
//
// Modelo sem preço na tabela NÃO vira zero silencioso: sai em `unpricedModels` e o
// chamador é obrigado a decidir o que mostrar. Regra 5: sem dado, estado honesto.

import Foundation

public struct ModelPrice: Sendable, Equatable {
    /// USD por 1.000.000 de tokens.
    public let input: Decimal
    public let output: Decimal
    /// nil = o provedor não cobra escrita de cache à parte (OpenAI).
    public let cacheWrite5m: Decimal?
    public let cacheWrite1h: Decimal?
    /// nil = sem cache read publicado pro modelo.
    public let cacheRead: Decimal?

    public init(
        input: Decimal,
        output: Decimal,
        cacheWrite5m: Decimal? = nil,
        cacheWrite1h: Decimal? = nil,
        cacheRead: Decimal? = nil
    ) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }
}

public enum PricingError: Error, Sendable {
    case malformed(String)
}

public struct PricingTable: Sendable {
    /// chave = id do modelo já normalizado.
    private let models: [String: ModelPrice]
    public let generatedAt: String?

    public init(models: [String: ModelPrice], generatedAt: String? = nil) {
        self.models = models
        self.generatedAt = generatedAt
    }

    public var modelIDs: [String] { models.keys.sorted() }

    // MARK: - Carga

    public static func load(from url: URL) throws -> PricingTable {
        try PricingTable(data: Data(contentsOf: url))
    }

    /// Parse via JSONSerialization: os números viram NSNumber e a gente converte por
    /// STRING pra Decimal. Passar por Double perderia precisão — 0.175 não é exato em
    /// binário. Decimal(string:) do texto original é exato.
    public init(data: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let providers = root["providers"] as? [String: Any]
        else { throw PricingError.malformed("faltou `providers` na raiz") }

        var out: [String: ModelPrice] = [:]
        for (_, rawProvider) in providers {
            guard
                let provider = rawProvider as? [String: Any],
                let models = provider["models"] as? [String: Any]
            else { continue }

            for (modelID, rawPrice) in models {
                guard let p = rawPrice as? [String: Any] else { continue }
                guard
                    let input = Self.decimal(p["input"]),
                    let output = Self.decimal(p["output"])
                else { throw PricingError.malformed("modelo \(modelID) sem input/output") }

                // Anthropic separa por TTL; OpenAI tem um `cache_write` (que é null).
                let w5 = Self.decimal(p["cache_write_5m"]) ?? Self.decimal(p["cache_write"])
                let w1h = Self.decimal(p["cache_write_1h"]) ?? w5

                out[Self.normalize(modelID)] = ModelPrice(
                    input: input,
                    output: output,
                    cacheWrite5m: w5,
                    cacheWrite1h: w1h,
                    cacheRead: Self.decimal(p["cache_read"])
                )
            }
        }
        guard !out.isEmpty else { throw PricingError.malformed("zero modelos") }
        self.models = out
        self.generatedAt = root["generated_at"] as? String
    }

    private static func decimal(_ any: Any?) -> Decimal? {
        switch any {
        case let n as NSNumber:
            // .stringValue devolve o texto do literal ("0.175"), não o binário.
            return Decimal(string: n.stringValue)
        case let s as String:
            return Decimal(string: s)
        default:
            return nil  // inclui NSNull (cache_write: null da OpenAI)
        }
    }

    // MARK: - Lookup

    /// O disco traz `claude-haiku-4-5-20251001`; a tabela tem `claude-haiku-4-5`.
    /// Corta o sufixo de data (-YYYYMMDD) e baixa a caixa. Nada mais — inventar
    /// aproximação de modelo é chutar preço, e chute não vai pra tela.
    public static func normalize(_ model: String) -> String {
        let m = model.lowercased()
        let parts = m.split(separator: "-")
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            return parts.dropLast().joined(separator: "-")
        }
        return m
    }

    public func price(for model: String) -> ModelPrice? {
        models[Self.normalize(model)]
    }

    // MARK: - Custo

    /// Custo dos 4 buckets, em USD. `nil` se o modelo não tem preço publicado.
    ///
    /// cacheWrite: se o disco separou por TTL (cacheWrite5m/1h), cada um cobra o seu.
    /// Se veio só o total, assume 5m — que é o TTL default e o mais barato dos dois;
    /// documentado pra ninguém achar que é preciso quando não é.
    public func cost(model: String, tokens: TokenBuckets) -> Decimal? {
        guard let p = price(for: model) else { return nil }

        let w5m: Int
        let w1h: Int
        if tokens.cacheWrite5m != nil || tokens.cacheWrite1h != nil {
            w5m = tokens.cacheWrite5m ?? 0
            w1h = tokens.cacheWrite1h ?? 0
        } else {
            w5m = tokens.cacheWrite
            w1h = 0
        }

        var total: Decimal = 0
        total += Decimal(tokens.input) * p.input
        total += Decimal(tokens.output) * p.output
        total += Decimal(w5m) * (p.cacheWrite5m ?? 0)
        total += Decimal(w1h) * (p.cacheWrite1h ?? 0)
        total += Decimal(tokens.cacheRead) * (p.cacheRead ?? 0)

        return total / 1_000_000
    }
}
