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

extension Dashboard {
    /// O texto que vai NA BARRA pro estilo escolhido. Vazio = só a proveta.
    ///
    /// Sem dado a mostrar, VOLTA VAZIO — nunca "0%" nem "—" pendurado na barra. Se não
    /// sabemos, a proveta (tracejada) já conta isso; um número fantasma ao lado seria a
    /// mentira que o app inteiro evita.
    public func menuBarText(style: MenuBarStyle, now: Date = Date()) -> String {
        switch style {
        case .iconOnly:
            return ""

        case .percent:
            guard let t = tightest, let used = t.used, t.certainty.hasInk else { return "" }
            let mark = t.certainty.isApproximate ? "~" : ""
            return "\(mark)\(Int(used.rounded()))%"

        case .countdown:
            guard let t = tightest, t.certainty.hasInk, let reset = t.resetsAt else { return "" }
            return Self.shortCountdown(to: reset, now: now)

        case .cost:
            let c = (todayCostUSD as NSDecimalNumber).doubleValue
            guard c > 0 else { return "" }
            // Barra é estreita: sem centavos acima de US$ 10, um decimal abaixo.
            return c >= 10 ? "US$\(Int(c.rounded()))"
                           : "US$\(String(format: "%.1f", c).replacingOccurrences(of: ".", with: ","))"
        }
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
