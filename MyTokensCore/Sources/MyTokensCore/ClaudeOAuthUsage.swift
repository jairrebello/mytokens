// As janelas POR MODELO do Claude (ex: semanal do Fable) — e a ÚNICA fonte delas.
//
// PROVADO (Sonda, 2026-07-19, zod do binário v2.1.215): o statusLine só publica
// five_hour/seven_day. Per-modelo vive em GET /api/oauth/usage:
//     utilization: { five_hour, seven_day, seven_day_oauth_apps, seven_day_opus,
//                    seven_day_sonnet, cinder_cove, extra_usage, limits: [...] }
// Cada janela = { utilization: number|null (0..1), resets_at: STRING ISO|null }.
// ATENÇÃO: resets_at aqui é STRING ISO — no hook é epoch em SEGUNDOS. Não misturar.
// limits[] = { kind, group, percent (JÁ 0-100), resets_at, scope.model.display_name }
// filtrado server-side por allowlist dinâmica (ex: display_name "Fable").
//
// PAPÉIS: o Core NÃO TOCA no Keychain. O token OAuth ("Claude Code-credentials")
// exige prompt do macOS e consentimento — gesto do APP. O Chassi implementa
// ClaudeOAuthTokenProvider; aqui só se usa o token que ele entregar.
//
// O hook segue sendo a fonte PRIMÁRIA das janelas da conta: é event-driven e mais
// fresco. Este endpoint ACRESCENTA as janelas que o hook não tem. No merge, o hook
// ganha em id repetido. Falha aqui (rede, token, schema) NUNCA derruba o collect.

import Foundation

public protocol ClaudeOAuthTokenProvider: Sendable {
    /// Access token OAuth do Claude Code. Implementado pelo app (Keychain, com
    /// consentimento). Jogue erro à vontade — o fetch degrada pra [].
    func accessToken() async throws -> String
}

public struct ClaudeOAuthUsageSource: Sendable {
    /// Host PROVÁVEL (api.anthropic.com), NÃO confirmado — ninguém chamou o endpoint
    /// ainda. Injetável de propósito: teste aponta pra fixture, correção não recompila
    /// o mundo.
    public static let defaultEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let tokens: any ClaudeOAuthTokenProvider
    private let endpoint: URL

    public init(tokens: any ClaudeOAuthTokenProvider, endpoint: URL = Self.defaultEndpoint) {
        self.tokens = tokens
        self.endpoint = endpoint
    }

    /// Busca e traduz. Qualquer falha -> [] — o statusLine continua de pé sozinho.
    public func fetch(now: Date = Date()) async -> [LimitWindow] {
        guard let token = try? await tokens.accessToken() else { return [] }
        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200
        else { return [] }
        return Self.windows(fromResponse: data, now: now)
    }

    /// Tradução pura, testável sem rede.
    static func windows(fromResponse data: Data, now: Date) -> [LimitWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        // O CLI embrulha em {fetchedAtMs, accountUuid, utilization}; o endpoint pode
        // devolver o miolo direto. Tolera os dois.
        let u = (root["utilization"] as? [String: Any]) ?? root

        var out: [LimitWindow] = []
        let week: TimeInterval = 7 * 24 * 3600

        // Janela ausente, utilization null ou resets vencido -> NÃO emite. Regra 5:
        // melhor lacuna honesta que número fabricado.
        func fixed(_ key: String, id: String, label: String, span: TimeInterval, modelScope: String?) {
            guard let w = u[key] as? [String: Any],
                  let util = (w["utilization"] as? NSNumber)?.doubleValue,  // 0..1
                  let resetsRaw = w["resets_at"] as? String,                // STRING ISO, ≠ hook
                  let resets = ISO8601.date(resetsRaw),
                  resets > now
            else { return }
            let pct = min(max(util * 100, 0), 100)
            out.append(LimitWindow(
                id: id, label: label, usedPercent: pct, resetsAt: resets,
                source: .measured, startedAt: resets.addingTimeInterval(-span),
                measuredAt: now, measuredPercent: pct, modelScope: modelScope
            ))
        }

        fixed("five_hour", id: "claude-5h", label: "5 horas", span: 5 * 3600, modelScope: nil)
        fixed("seven_day", id: "claude-7d", label: "Semana", span: week, modelScope: nil)
        // Rótulos do /usage provam a semântica: "Current week (Sonnet only)" etc.
        fixed("seven_day_opus", id: "claude-7d-opus", label: "Semana · Opus", span: week, modelScope: "Opus")
        fixed("seven_day_sonnet", id: "claude-7d-sonnet", label: "Semana · Sonnet", span: week, modelScope: "Sonnet")
        // seven_day_oauth_apps: não é modelo e a semântica não foi provada -> fora.
        // cinder_cove: codename opaco, NÃO PROVADO o que mede -> regra de ouro, fora.
        // extra_usage: crédito em US$, outro conceito — entra quando alguém provar o shape na prática.

        // limits[]: as janelas por-modelo da allowlist dinâmica. `percent` JÁ é 0-100
        // (≠ utilization). Span semanal provado pelo rótulo "Current week (<modelo>)".
        for entry in (u["limits"] as? [[String: Any]]) ?? [] {
            guard let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String, !name.isEmpty,
                  let pctRaw = (entry["percent"] as? NSNumber)?.doubleValue,
                  let resetsRaw = entry["resets_at"] as? String,
                  let resets = ISO8601.date(resetsRaw),
                  resets > now
            else { continue }
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
            let id = "claude-7d-\(slug)"
            // Opus/Sonnet podem vir DUAS vezes (campo fixo + limits[]). O fixo entrou
            // primeiro; não duplica.
            guard !out.contains(where: { $0.id == id }) else { continue }
            let pct = min(max(pctRaw, 0), 100)
            out.append(LimitWindow(
                id: id, label: "Semana · \(name)", usedPercent: pct, resetsAt: resets,
                source: .measured, startedAt: resets.addingTimeInterval(-week),
                measuredAt: now, measuredPercent: pct, modelScope: name
            ))
        }
        return out
    }

    /// Hook GANHA em id repetido: é event-driven, sempre mais fresco que um GET
    /// esporádico. O endpoint só acrescenta o que o hook não tem.
    public static func merge(hook: [LimitWindow], endpoint: [LimitWindow]) -> [LimitWindow] {
        let taken = Set(hook.map(\.id))
        return hook + endpoint.filter { !taken.contains($0.id) }
    }
}
