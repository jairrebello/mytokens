// A fachada que o app consome. Um refresh -> um Snapshot -> a view desenha.
//
// Cursor continua VAZIO de propósito: ninguém provou o schema do
// ~/.cursor/ai-tracking/ai-code-tracking.db ainda (docs/FONTES.md §6, lead aberto).
// Melhor "Cursor: sem dado local" do que um zero mentiroso. Regra 5.
// Quando o Sonda provar, troca o EmptyCollector por um CursorCollector — `UsageCollector`
// é o único ponto de contato. Zero mudança no resto.

import Foundation

/// Placeholder que não lê nada e não inventa nada.
public struct EmptyCollector: UsageCollector {
    public let provider: Provider

    public init(provider: Provider) { self.provider = provider }

    public func collect() async throws -> (events: [UsageEvent], status: ProviderStatus) {
        ([], ProviderStatus(provider: provider, connected: false))
    }
}

public enum CollectorRegistry {
    public static func makeAll(pricing: PricingTable) -> [any UsageCollector] {
        [
            ClaudeCodeCollector(pricing: pricing),
            CodexCollector(pricing: pricing),
            EmptyCollector(provider: .cursor),
        ]
    }

    public static func makeAll() throws -> [any UsageCollector] {
        makeAll(pricing: try PricingTable.bundled())
    }
}

extension PricingTable {
    /// pricing.json embarcado. É SYMLINK pra data/pricing.json — o arquivo que o Sonda
    /// mantém. Não existe segunda cópia pra dessincronizar.
    public static func bundled() throws -> PricingTable {
        guard let url = Bundle.module.url(forResource: "pricing", withExtension: "json") else {
            throw PricingError.malformed("pricing.json não veio no bundle")
        }
        return try PricingTable.load(from: url)
    }
}

// MARK: - Snapshot

public struct Snapshot: Sendable {
    public let statuses: [ProviderStatus]
    public let events: [UsageEvent]
    public let generatedAt: Date
    public let duration: TimeInterval

    public func status(_ p: Provider) -> ProviderStatus? {
        statuses.first { $0.provider == p }
    }

    public func events(_ p: Provider) -> [UsageEvent] {
        events.filter { $0.provider == p }
    }

    // Recortes. A view NÃO faz conta — pede aqui. Regra 10.
    public func byDay(calendar: Calendar = .current) -> [Bucket] {
        Aggregator.by(.day, events: events, calendar: calendar)
    }

    public func byWeek(calendar: Calendar = .current) -> [Bucket] {
        Aggregator.by(.week, events: events, calendar: calendar)
    }

    public func byMonth(calendar: Calendar = .current) -> [Bucket] {
        Aggregator.by(.month, events: events, calendar: calendar)
    }

    public func byModel() -> [String: Spend] { Aggregator.byModel(events) }
    public func byProject() -> [String: Spend] { Aggregator.byProject(events) }
    public func byProvider() -> [Provider: Spend] { Aggregator.byProvider(events) }

    /// Blocos rolling de 5h (ancorados no 1º request pós-expiração), por provider.
    public func blocks(_ p: Provider) -> [UsageBlock] {
        Aggregator.fiveHourBlocks(events(p))
    }

    public func currentBlock(_ p: Provider, now: Date = Date()) -> UsageBlock? {
        Aggregator.currentBlock(events(p), now: now)
    }
}

/// Motor. Guarda os collectors vivos — é o cache incremental deles que faz o refresh
/// custar milissegundos em vez de reparsear 1,4GB.
public actor MyTokensEngine {
    private let collectors: [any UsageCollector]

    public init(collectors: [any UsageCollector]) {
        self.collectors = collectors
    }

    public init(pricing: PricingTable) {
        self.collectors = CollectorRegistry.makeAll(pricing: pricing)
    }

    public init() throws {
        self.collectors = try CollectorRegistry.makeAll()
    }

    /// Um provider que explode não derruba os outros: ele entra desconectado e o resto
    /// segue. A tela nunca fica em branco por causa de um parser.
    public func refresh() async -> Snapshot {
        let start = DispatchTime.now()

        let results = await withTaskGroup(
            of: (events: [UsageEvent], status: ProviderStatus).self
        ) { group in
            for c in collectors {
                group.addTask {
                    do {
                        return try await c.collect()
                    } catch {
                        return ([], ProviderStatus(provider: c.provider, connected: false))
                    }
                }
            }
            var acc: [(events: [UsageEvent], status: ProviderStatus)] = []
            for await r in group { acc.append(r) }
            return acc
        }

        var events = results.flatMap(\.events)
        events.sort { $0.ts < $1.ts }

        let order = Provider.allCases
        let statuses = results.map(\.status).sorted {
            (order.firstIndex(of: $0.provider) ?? 0) < (order.firstIndex(of: $1.provider) ?? 0)
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        return Snapshot(
            statuses: statuses,
            events: events,
            generatedAt: Date(),
            duration: elapsed
        )
    }
}
