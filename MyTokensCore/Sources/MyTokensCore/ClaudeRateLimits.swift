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
    /// O despejo CRU do stdin do statusLine, escrito pelo wrapper
    /// (`scripts/statusline-install.sh`). É o payload do Claude Code, sem tradução —
    /// o wrapper é um shell script de 5 linhas e não tem opinião sobre o conteúdo.
    ///
    /// Território do MyTokens, e só. O Core NUNCA escreve aqui e NUNCA lê de ~/.claude
    /// (regra 3): quem escreve é o wrapper, que é do usuário e vive na casa dele.
    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/MyTokens/statusline.json")
    }

    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
    }

    public func read(now: Date = Date()) -> [LimitWindow] {
        guard let data = try? Data(contentsOf: url) else { return [] }

        // A IDADE do número é o mtime do arquivo. Não existe carimbo de hora DENTRO do
        // payload do statusLine — e a idade não é detalhe: o hook só dispara enquanto o
        // Claude Code roda. Fechou o Claude, o número CONGELA. Sem `capturedAt`, a tela
        // venderia um valor de ontem como se fosse de agora.
        let capturado = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? now

        guard let snap = Self.ingest(statusLineStdin: data, now: capturado) else { return [] }
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

    /// O hook está instalado? É o que o app pergunta pra decidir entre oferecer o
    /// "conectar" e mostrar o número. Existir o arquivo já é a resposta: quem o cria é o
    /// wrapper, e o wrapper só existe se o usuário mandou instalar.
    public var isConnected: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

// O Core NÃO ESCREVE o despejo — quem escreve é o wrapper (um shell script, na casa do
// usuário, que ele instalou por vontade própria e desinstala com um comando). Aqui só se
// LÊ. Foi de propósito: manter o app fora do caminho crítico da statusline dele.

extension JSONDecoder {
    static let mytokens: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
