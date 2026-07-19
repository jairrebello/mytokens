//  MenuBarStyle.swift
//
//  O que o app diz na BARRA, sem um clique. A proveta já mostra o estado em forma; isto
//  põe um número ao lado, pra quem quer a resposta de relance.
//
//  Todo modo segue a mesma regra do ícone (UI-SPEC §9): fala de UM provedor, o de MENOR
//  FOLGA — o que aperta. Dois números em 40 px de barra não é informação, é sujeira. O
//  custo é a exceção: ele é a soma do dia, não uma pista.

import Foundation

public enum MenuBarStyle: String, CaseIterable, Sendable, Identifiable {
    /// Só a proveta. O mais discreto.
    case iconOnly
    /// A % da janela que aperta. "quanto perto do teto".
    case percent
    /// Tempo até a janela que aperta zerar. "quando alivia".
    case countdown
    /// O custo do dia, somando os provedores. "quanto gastei".
    case cost

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .iconOnly:  "Só o ícone"
        case .percent:   "Porcentagem"
        case .countdown: "Tempo até zerar"
        case .cost:      "Custo de hoje"
        }
    }

    /// Os estilos que falam de UMA janela — e que portanto aceitam FIXAR qual (§12).
    /// Custo é a soma do dia e ícone é ícone: fixar janela neles não significa nada.
    public var usesWindow: Bool {
        switch self {
        case .percent, .countdown: true
        case .iconOnly, .cost: false
        }
    }
}

public struct MenuBarStyleStore {
    public static let key = "mytokens.menuBarStyle"

    public static var current: MenuBarStyle {
        get {
            UserDefaults.standard.string(forKey: key)
                .flatMap(MenuBarStyle.init(rawValue:)) ?? .iconOnly
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

// MARK: - A janela FIXADA na barra (UI-SPEC §12)

/// A escolha do picker "Mostrar na barra": `nil` = Automática (a janela que aperta).
///
/// O rótulo é persistido JUNTO com o id de propósito: quando a janela fixada some do disco
/// (fonte piscou, hook morreu), a barra volta pra Automática mas o picker continua mostrando
/// a escolha — marcada como indisponível. Sem o rótulo guardado, a entrada indisponível
/// viraria um id cru ("claude-7d.fable") na cara do usuário.
public struct MenuBarPin: Sendable, Equatable {
    /// O `Lane.id` da janela fixada — que embute o id do LimitWindow (ex. "claude.7d.fable").
    public let id: String
    /// "Claude · Semana · Fable" — como o picker escreveu na hora de fixar.
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct MenuBarPinStore {
    public static let idKey = "mytokens.menuBarPinnedWindowID"
    public static let labelKey = "mytokens.menuBarPinnedWindowLabel"

    public static var current: MenuBarPin? {
        get {
            guard let id = UserDefaults.standard.string(forKey: idKey) else { return nil }
            return MenuBarPin(id: id, label: UserDefaults.standard.string(forKey: labelKey) ?? id)
        }
        set {
            if let pin = newValue {
                UserDefaults.standard.set(pin.id, forKey: idKey)
                UserDefaults.standard.set(pin.label, forKey: labelKey)
            } else {
                UserDefaults.standard.removeObject(forKey: idKey)
                UserDefaults.standard.removeObject(forKey: labelKey)
            }
        }
    }
}

/// Uma linha do picker. `available == false` é a janela fixada que sumiu: continua marcada
/// (a preferência não foi apagada) mas não é clicável — a barra já caiu pra Automática.
public struct MenuBarPinOption: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let available: Bool

    public init(id: String, label: String, available: Bool) {
        self.id = id
        self.label = label
        self.available = available
    }
}

extension Dashboard {
    /// O texto que vai NA BARRA pro estilo escolhido. Vazio = só a proveta.
    ///
    /// Sem dado a mostrar, VOLTA VAZIO — nunca "0%" nem "—" pendurado na barra. Se não
    /// sabemos, a proveta (tracejada) já conta isso; um número fantasma ao lado seria a
    /// mentira que o app inteiro evita.
    public func menuBarText(style: MenuBarStyle, pinnedID: String? = nil, now: Date = Date()) -> String {
        switch style {
        case .iconOnly:
            return ""

        case .percent:
            guard let t = barLane(pinnedID: pinnedID), let used = t.used, t.certainty.hasInk
            else { return "" }
            switch t.unit {
            case .percent:
                // Acima do teto o número REAL sai — "104%". O alarme é da proveta (a régua
                // acima da boca), não do texto: sem cor, sem bold, sem piscar (§12).
                let mark = t.certainty.isApproximate ? "~" : ""
                return "\(mark)\(Int(used.rounded()))%"
            case .usd:
                // §13.2: US$ nunca vira % solto. 32% de um crédito em dólar e 32% de uma
                // cota opaca não são a mesma coisa. Na barra, o dólar É a forma compacta.
                guard let cap = t.capUSD else { return "" }
                return Self.shortUSD(((Decimal(used) / 100 * cap) as NSDecimalNumber).doubleValue)
            }

        case .countdown:
            guard let t = barLane(pinnedID: pinnedID), t.certainty.hasInk, let reset = t.resetsAt
            else { return "" }
            return Self.shortCountdown(to: reset, now: now)

        case .cost:
            let c = (todayCostUSD as NSDecimalNumber).doubleValue
            guard c > 0 else { return "" }
            return Self.shortUSD(c)
        }
    }

    /// A janela de quem a barra fala: a FIXADA, se existe e tem tinta — senão a que aperta.
    ///
    /// A queda pra Automática é silenciosa e NÃO apaga a preferência (§12): a fonte piscar
    /// não pode custar a escolha do usuário. Quem conta que a fixada sumiu é o picker,
    /// marcando-a como indisponível.
    public func barLane(pinnedID: String?) -> Lane? {
        if let pinnedID,
           let pinned = lanes.first(where: {
               $0.id == pinnedID && $0.certainty.hasInk && $0.used != nil
           }) {
            return pinned
        }
        return tightest
    }

    /// Barra é estreita: sem centavos acima de US$ 10, um decimal abaixo.
    static func shortUSD(_ c: Double) -> String {
        c >= 10 ? "US$\(Int(c.rounded()))"
                : "US$\(String(format: "%.1f", c).replacingOccurrences(of: ".", with: ","))"
    }

    /// "18m" · "2h10" · "3d". Curto, porque a barra não tem largura pra frase.
    static func shortCountdown(to date: Date, now: Date) -> String {
        let s = Int(date.timeIntervalSince(now))
        guard s > 0 else { return "0m" }
        let min = s / 60, h = min / 60, d = h / 24
        if d >= 1 { return "\(d)d" }
        if h >= 1 {
            let m = min % 60
            return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
        }
        return "\(min)m"
    }
}
