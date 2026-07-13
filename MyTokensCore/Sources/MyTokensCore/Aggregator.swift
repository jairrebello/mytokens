// Agregação: janela / dia / semana / mês. Por provider, por modelo, por projeto.
//
// REGRA (docs/FONTES.md §2): agrupar por data do ARQUIVO mente — sessões iniciadas em
// 02/03 e 03/03 reportam o bloco de 04/03. Agrupe SEMPRE pelo timestamp do EVENTO.
//
// A janela de 5h NÃO é horário de relógio: 0 de 40 resets_at observados caem em hora
// cheia. Arredondar pra baixo na hora (o que o ccusage faz) é chute. O bloco ancora no
// PRIMEIRO request depois do bloco anterior expirar, e dura 300min exatos. ROLLING.

import Foundation

public enum Period: String, Sendable, CaseIterable {
    case day, week, month
}

public struct Bucket: Sendable, Identifiable {
    public let id: String
    public let start: Date
    public let end: Date
    public let spend: Spend
}

/// Um bloco de 5h, ancorado no primeiro evento pós-expiração. Por CONTA, não por sessão.
public struct UsageBlock: Sendable, Identifiable {
    public var id: String { ISO8601Stamp.string(start) }
    public let start: Date
    public let end: Date
    public let spend: Spend
    public var isActive: Bool { end > Date() }
}

public enum Aggregator {
    public static let fiveHours: TimeInterval = 5 * 60 * 60

    // MARK: - Soma

    public static func spend(_ events: some Sequence<UsageEvent>) -> Spend {
        var s = Spend()
        for e in events {
            let t = e.tokens.total
            s.tokens += t
            s.costUSD += e.costUSD
            s.byModel[e.model, default: 0] += t
        }
        return s
    }

    // MARK: - Recortes

    public static func by(
        _ period: Period,
        events: [UsageEvent],
        calendar: Calendar = .current
    ) -> [Bucket] {
        var groups: [Date: [UsageEvent]] = [:]
        for e in events {
            guard let start = periodStart(period, of: e.ts, calendar: calendar) else { continue }
            groups[start, default: []].append(e)
        }
        return groups
            .map { start, evs in
                Bucket(
                    id: key(period, start, calendar: calendar),
                    start: start,
                    end: periodEnd(period, from: start, calendar: calendar),
                    spend: spend(evs)
                )
            }
            .sorted { $0.start < $1.start }
    }

    public static func byModel(_ events: [UsageEvent]) -> [String: Spend] {
        group(events, by: \.model)
    }

    /// Eventos sem projeto (sem cwd no disco) ficam de fora — não invento "desconhecido"
    /// pra fingir cobertura total.
    public static func byProject(_ events: [UsageEvent]) -> [String: Spend] {
        var out: [String: [UsageEvent]] = [:]
        for e in events {
            guard let p = e.project else { continue }
            out[p, default: []].append(e)
        }
        return out.mapValues(spend)
    }

    public static func byProvider(_ events: [UsageEvent]) -> [Provider: Spend] {
        group(events, by: \.provider)
    }

    private static func group<K: Hashable>(
        _ events: [UsageEvent], by keyPath: KeyPath<UsageEvent, K>
    ) -> [K: Spend] {
        var out: [K: [UsageEvent]] = [:]
        for e in events { out[e[keyPath: keyPath], default: []].append(e) }
        return out.mapValues(spend)
    }

    // MARK: - Blocos de 5h

    /// Blocos ROLLING de 5h: o bloco abre no primeiro evento depois do anterior expirar.
    /// `events` precisa estar ordenado por ts (o collector já entrega assim).
    public static func fiveHourBlocks(_ events: [UsageEvent]) -> [UsageBlock] {
        var blocks: [UsageBlock] = []
        var current: (start: Date, events: [UsageEvent])?

        for e in events {
            if let c = current, e.ts < c.start.addingTimeInterval(fiveHours) {
                current!.events.append(e)
            } else {
                if let c = current {
                    blocks.append(UsageBlock(
                        start: c.start,
                        end: c.start.addingTimeInterval(fiveHours),
                        spend: spend(c.events)
                    ))
                }
                current = (e.ts, [e])
            }
        }
        if let c = current {
            blocks.append(UsageBlock(
                start: c.start,
                end: c.start.addingTimeInterval(fiveHours),
                spend: spend(c.events)
            ))
        }
        return blocks
    }

    /// O bloco de 5h que contém `now`, se houver. nil = nenhum evento na janela aberta.
    public static func currentBlock(_ events: [UsageEvent], now: Date = Date()) -> UsageBlock? {
        guard let last = fiveHourBlocks(events).last, last.end > now else { return nil }
        return last
    }

    // MARK: - Status do provider

    public static func status(
        provider: Provider,
        events: [UsageEvent],
        windows: [LimitWindow],
        connected: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProviderStatus {
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = periodStart(.week, of: now, calendar: calendar) ?? dayStart
        let monthStart = periodStart(.month, of: now, calendar: calendar) ?? dayStart

        return ProviderStatus(
            provider: provider,
            connected: connected,
            windows: windows,
            today: spend(events.lazy.filter { $0.ts >= dayStart }),
            week: spend(events.lazy.filter { $0.ts >= weekStart }),
            month: spend(events.lazy.filter { $0.ts >= monthStart }),
            lastEventAt: events.last?.ts ?? events.max(by: { $0.ts < $1.ts })?.ts
        )
    }

    // MARK: - Calendário

    static func periodStart(_ p: Period, of date: Date, calendar: Calendar) -> Date? {
        switch p {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
        }
    }

    static func periodEnd(_ p: Period, from start: Date, calendar: Calendar) -> Date {
        let comp: Calendar.Component = switch p {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        return calendar.date(byAdding: comp, value: 1, to: start) ?? start
    }

    static func key(_ p: Period, _ start: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekOfYear, .yearForWeekOfYear], from: start)
        switch p {
        case .day:
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        case .week:
            return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
        case .month:
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
    }
}

/// Carimbo ISO estável (UTC) — usado como id de bloco e nos diagnósticos.
public enum ISO8601Stamp {
    public static func string(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    /// Dia em UTC (YYYY-MM-DD). É a chave que o probe do Sonda usa — é assim que a
    /// gente compara número com número, sem fuso no meio.
    public static func utcDay(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
