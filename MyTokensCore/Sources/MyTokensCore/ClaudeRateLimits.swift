// O "restante" do Claude. Fonte PRIMÁRIA: hook statusLine. Zero API, zero credencial.
//
// docs/FONTES.md §5: o número NÃO está em nenhum arquivo do ~/.claude. O CLI lê dos
// headers HTTP e guarda SÓ EM MEMÓRIA. O único jeito de ler sem credencial é o hook
// `statusLine`, que recebe no stdin:
//     rate_limits.five_hour.{used_percentage,resets_at}
//     rate_limits.seven_day.{used_percentage,resets_at}
//
// DIVISÃO DE TRABALHO: registrar o hook em ~/.claude/settings.json é do Chassi (o Core
// é read-only no ~/.claude — regra 3). O hook despeja o stdin num snapshot; o Core LÊ o
// snapshot. `ingest` existe pro Chassi chamar do lado do hook.
//
// Snapshot ausente, ilegível ou VENCIDO -> windows = []. A view mostra "não sabemos".
// Nunca um zero fabricado. Regra 5.

import Foundation

public struct ClaudeRateLimitSnapshot: Codable, Sendable {
    public struct Window: Codable, Sendable {
        public var usedPercentage: Double
        /// unix epoch em SEGUNDOS.
        public var resetsAt: TimeInterval
    }
    /// quando o hook capturou isso.
    public var capturedAt: Date
    public var fiveHour: Window?
    public var sevenDay: Window?
}

public struct ClaudeRateLimitReader: Sendable {
    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/MyTokens/claude-rate-limits.json")
    }

    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
    }

    public func read(now: Date = Date()) -> [LimitWindow] {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder.mytokens.decode(ClaudeRateLimitSnapshot.self, from: data)
        else { return [] }
        return Self.windows(from: snap, now: now)
    }

    static func windows(from snap: ClaudeRateLimitSnapshot, now: Date) -> [LimitWindow] {
        var out: [LimitWindow] = []

        // `capturedAt` é a IDADE do número. O hook só dispara enquanto o Claude Code roda:
        // fechou o Claude, o valor congela. Carimbar essa idade é o que impede a tela de
        // vender um número velho como se fosse de agora.
        //
        // `measuredPercent == usedPercent` aqui de propósito: o app ainda não infere o
        // gasto do disco DEPOIS da medição. Enquanto não inferir, a barra é sólida pura —
        // e a costura (composta) não aparece porque não há nada honesto pra costurar.
        func add(_ w: ClaudeRateLimitSnapshot.Window?, id: String, label: String, span: TimeInterval) {
            guard let w else { return }
            let resets = Date(timeIntervalSince1970: w.resetsAt)
            // Janela vencida = número velho. Melhor não mostrar nada do que mostrar
            // uma porcentagem de um bloco que já morreu.
            guard resets > now else { return }
            let pct = min(max(w.usedPercentage, 0), 100)
            out.append(LimitWindow(
                id: id,
                label: label,
                usedPercent: pct,
                resetsAt: resets,
                source: .measured,
                startedAt: resets.addingTimeInterval(-span),
                measuredAt: snap.capturedAt,
                measuredPercent: pct
            ))
        }
        add(snap.fiveHour, id: "claude-5h", label: "5 horas", span: 5 * 60 * 60)
        add(snap.sevenDay, id: "claude-7d", label: "Semana", span: 7 * 24 * 60 * 60)
        return out
    }

    /// Converte o payload cru do stdin do statusLine num snapshot. Chame do lado do hook.
    /// Formato do stdin (v2.1.207): { "rate_limits": { "five_hour": {...}, "seven_day": {...} } }
    public static func ingest(statusLineStdin data: Data, now: Date = Date()) -> ClaudeRateLimitSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any]
        else { return nil }

        func window(_ key: String) -> ClaudeRateLimitSnapshot.Window? {
            guard let w = limits[key] as? [String: Any],
                  let pct = (w["used_percentage"] as? NSNumber)?.doubleValue,
                  let resets = (w["resets_at"] as? NSNumber)?.doubleValue
            else { return nil }
            return .init(usedPercentage: pct, resetsAt: resets)
        }

        let five = window("five_hour")
        let seven = window("seven_day")
        guard five != nil || seven != nil else { return nil }
        return ClaudeRateLimitSnapshot(capturedAt: now, fiveHour: five, sevenDay: seven)
    }

    /// Grava o snapshot. Só escreve DENTRO do território do MyTokens — nunca em ~/.claude.
    public func write(_ snapshot: ClaudeRateLimitSnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONEncoder.mytokens.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

extension JSONDecoder {
    static let mytokens: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let mytokens: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
