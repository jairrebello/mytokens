// Cursor — o ÚNICO collector que fala com a rede.
//
// Todos os outros leem arquivo local e nada mais. O Cursor não pode: ele NÃO GRAVA uso no
// disco (docs/CURSOR.md, docs/PESQUISA-FONTES.md — provado, é um "não"). O `used`/`remaining`
// existe só atrás de um endpoint autenticado do cursor.com. Então, e só então, o app fala
// com um servidor — e com UM servidor: o do próprio provedor, dono legítimo da credencial.
//
// AUTORIZADO pelo Jair em 2026-07-13 ("reusar a sessão local"). Antes disto o app era 100%
// local, e a regra 2 era "zero rede". Ela virou "só o domínio oficial do provedor" — o `aud`
// do JWT é `https://cursor.com`, então o token FOI FEITO pra falar com esse host, e com
// nenhum outro.
//
// ─────────────────────────────────────────────────────────────────────────────
// A CREDENCIAL — as regras, e por que existem:
//   • o accessToken vem do state.vscdb do Cursor (o app não pede login: reusa a sessão
//     que o próprio Cursor já mantém na máquina);
//   • ele NUNCA é impresso, logado, escrito em disco nosso, nem mandado pra telemetria;
//   • ele NUNCA vai pra lugar nenhum além de cursor.com, num header, numa request read-only;
//   • se qualquer passo falhar (sem sessão, offline, token expirado, 401), o resultado é
//     "sem dado" HONESTO — nunca um número inventado, nunca uma tela em branco.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SQLite3

public actor CursorCollector: UsageCollector {
    public nonisolated let provider: Provider = .cursor

    private let statePath: String
    private let session: URLSession
    private let ttl: TimeInterval

    /// A rede não é de graça e o uso do Cursor não muda de segundo em segundo. O refresh do
    /// app dispara por evento de DISCO (Claude/Codex escrevendo) e pode ser muito frequente;
    /// o Cursor pega carona nele, mas com um TTL — só bate na rede se o cache passou do prazo.
    private var cache: (status: ProviderStatus, at: Date)?

    public init(
        statePath: String? = nil,
        ttl: TimeInterval = 5 * 60,
        session: URLSession? = nil
    ) {
        self.statePath = statePath ?? Self.defaultStatePath
        self.ttl = ttl
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral   // nada de cache/cookie em disco
            cfg.timeoutIntervalForRequest = 12
            cfg.httpCookieStorage = nil
            cfg.urlCache = nil
            self.session = URLSession(configuration: cfg)
        }
    }

    public static var defaultStatePath: String {
        NSHomeDirectory()
            + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    public func collect() async throws -> (events: [UsageEvent], status: ProviderStatus) {
        if let c = cache, Date().timeIntervalSince(c.at) < ttl {
            return ([], c.status)
        }

        // Sem sessão local = "sem dado local". É o estado honesto, não um erro.
        guard let cred = readCredential() else {
            return ([], ProviderStatus(provider: .cursor, connected: false))
        }

        let status: ProviderStatus
        do {
            status = try await fetchUsage(token: cred.token, sub: cred.sub)
        } catch {
            // Offline, timeout, token vencido, o Cursor mudou o endpoint: tudo cai aqui, e
            // tudo vira a MESMA resposta honesta. O motivo não vaza — nem pro log.
            return ([], ProviderStatus(provider: .cursor, connected: false))
        }

        cache = (status, Date())
        return ([], status)
    }

    // MARK: - A credencial (nunca sai daqui em texto)

    private struct Credential { let token: String; let sub: String }

    /// Lê o accessToken do state.vscdb — READONLY + immutable (não cria WAL, não encosta no
    /// arquivo do Cursor), como manda a regra 3. O token fica numa `let` local e morre no
    /// fim do escopo. Não há um `print` nem um `try data.write` nesta função de propósito.
    private func readCredential() -> Credential? {
        var db: OpaquePointer?
        // immutable=1: promete ao SQLite que ninguém mais mexe no arquivo — evita o
        // SQLITE_CANTOPEN que `mode=ro` sozinho dá neste .vscdb de 3 GB.
        let uri = "file:\(statePath)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK
        else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let c = sqlite3_column_text(stmt, 0)
        else { return nil }

        let token = String(cString: c)
        guard !token.isEmpty, let sub = Self.subject(ofJWT: token) else { return nil }
        return Credential(token: token, sub: sub)
    }

    /// O `sub` do JWT (o id do usuário), que entra no cookie de sessão. Decodifica só o
    /// PAYLOAD (a parte do meio, não sensível) — não valida assinatura, não toca no header.
    static func subject(ofJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String
        else { return nil }
        return sub
    }

    // MARK: - A request (read-only, só pro cursor.com)

    static let usageURL = URL(string: "https://cursor.com/api/usage-summary")!

    private func fetchUsage(token: String, sub: String) async throws -> ProviderStatus {
        // Cookie de sessão: WorkosCursorSessionToken=<sub>::<token>, url-encoded.
        // É como o próprio cliente do Cursor autentica — não é Authorization: Bearer.
        let enc: (String) -> String = { $0.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) ?? $0 }
        let cookie = "WorkosCursorSessionToken=\(enc(sub))%3A%3A\(enc(token))"

        var req = URLRequest(url: Self.usageURL)
        req.httpMethod = "GET"
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw CursorError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try Self.parse(data, now: Date())
    }

    enum CursorError: Error { case badStatus(Int); case malformed }

    /// O JSON do usage-summary vira UMA janela: o mês corrente, medido, em US$.
    ///
    /// O número de ouro é `individualUsage.plan.totalPercentUsed` — é LITERALMENTE o que o
    /// Cursor mostra pro usuário ("You've used 16% of your included total usage"). Não é
    /// derivado nosso: é o servidor dele dizendo. Logo `.measured`.
    static func parse(_ data: Data, now: Date) throws -> ProviderStatus {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CursorError.malformed }

        let connected = true
        let plan = ((root["individualUsage"] as? [String: Any])?["plan"] as? [String: Any])

        guard let plan,
              let pct = (plan["totalPercentUsed"] as? NSNumber)?.doubleValue
        else {
            // Sessão válida mas sem plano individual (conta de time, por ex.): conectado,
            // mas sem janela que a gente saiba desenhar. Honesto.
            return ProviderStatus(provider: .cursor, connected: connected)
        }

        // O teto incluído, em dólar (a API dá em CENTAVOS: included 2000 = US$ 20).
        let breakdown = plan["breakdown"] as? [String: Any]
        let includedCents = (breakdown?["included"] as? NSNumber)?.doubleValue
            ?? (plan["limit"] as? NSNumber)?.doubleValue
        let capUSD = includedCents.map { Decimal($0 / 100) }

        let resets = (root["billingCycleEnd"] as? String).flatMap(ISO8601.date)
            ?? now.addingTimeInterval(30 * 86_400)

        // A resposta é de AGORA — a request acabou de voltar. Diferente do Claude (cujo
        // hook tem idade), aqui `measuredAt == now` é a verdade.
        let window = LimitWindow(
            id: "cursor-month",
            label: "Mês",
            usedPercent: min(max(pct, 0), 100),
            resetsAt: resets,
            source: .measured,
            startedAt: (root["billingCycleStart"] as? String).flatMap(ISO8601.date),
            measuredAt: now,
            measuredPercent: min(max(pct, 0), 100),
            unit: .usd,
            capUSD: capUSD
        )

        return ProviderStatus(provider: .cursor, connected: connected, windows: [window])
    }
}
