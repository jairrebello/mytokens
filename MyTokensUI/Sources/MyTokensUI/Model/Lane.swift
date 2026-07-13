//  Lane.swift
//
//  A PISTA — a peça central do sistema. Um eixo, DUAS leituras:
//
//    eixo x  = 0 → 100% DAQUELA janela (5 h, 7 d, ou o mês em US$)
//    tinta   = % da COTA queimada
//    cursor  = % do TEMPO decorrido nessa janela ("agora")
//
//    O VÃO ENTRE A TINTA E O CURSOR É A RESPOSTA DO APP.
//      tinta ATRÁS do cursor  → gasta mais devagar que o relógio. Folga.
//      tinta NA FRENTE        → acaba antes da janela fechar.
//
//  O eixo é NORMALIZADO, não temporal. Foi a única coisa que sobreviveu ao
//  Codex matar a janela de 5 h em 12/07: se o eixo fosse "5 horas de relógio",
//  o app estaria desenhando um dado que não existe mais. Fração de janela é a
//  única unidade em que 5 h, 7 d e US$ 20/mês são honestamente comparáveis.

import MyTokensCore
import Foundation

/// O que uma pista precisa saber pra se desenhar. Nada além disto.
/// A view NUNCA vê um LimitWindow cru — vê isto, que já resolveu a certeza.
public struct Lane: Identifiable, Sendable, Equatable {
    public let id: String
    public let provider: Provider
    /// "Claude · 5 h"
    public let title: String
    /// 0...100+ da janela. `nil` quando ausente — NUNCA 0.
    public let used: Double?
    public let certainty: Certainty
    /// % do TEMPO decorrido na janela. O relógio a gente SEMPRE sabe, mesmo
    /// quando não sabemos a tinta: o Cursor desconectado também tem cursor.
    /// Falta a tinta, não a pista. Meia leitura honesta > zero mentiroso.
    public let nowFraction: Double?
    public let resetsAt: Date?
    public let unit: WindowUnit
    public let capUSD: Decimal?
    public let burnRatePerHour: Double?

    /// Está queimando AGORA (evento recente). É a única coisa que acende a
    /// matiz ember — e ela não significa perigo, significa CALOR = atividade.
    /// Provedor parado fica cinza (`emberCold`). Sem verde e sem amarelo no
    /// sistema, não existe semáforo nem se eu quisesse fazer um.
    public let isLive: Bool

    public init(
        id: String, provider: Provider, title: String,
        used: Double?, certainty: Certainty, nowFraction: Double?,
        resetsAt: Date?, unit: WindowUnit = .percent,
        capUSD: Decimal? = nil, burnRatePerHour: Double? = nil,
        isLive: Bool = false
    ) {
        self.isLive = isLive
        self.id = id
        self.provider = provider
        self.title = title
        self.used = used
        self.certainty = certainty
        self.nowFraction = nowFraction
        self.resetsAt = resetsAt
        self.unit = unit
        self.capUSD = capUSD
        self.burnRatePerHour = burnRatePerHour
    }

    public var heat: Heat { Heat(percent: used ?? 0) }

    /// Onde a tinta chega no fim da janela, no ritmo dos últimos 20 min.
    /// Só existe acima de 70% — abaixo disso é ruído: a resposta já é "pode ir".
    public var projected: Double? {
        guard let used, used >= 70,
              let burn = burnRatePerHour,
              let resetsAt, certainty.hasInk else { return nil }
        let hoursLeft = resetsAt.timeIntervalSinceNow / 3600
        guard hoursLeft > 0 else { return nil }
        return used + burn * hoursLeft
    }

    /// O quanto a projeção passa de 100. É isto que vaza PRA FORA do trilho.
    /// O trilho é o limite. O que sai dele é o que você não tem.
    public var overrun: Double? {
        guard let p = projected, p > 100 else { return nil }
        return p - 100
    }

    /// Folga em pontos: quanto do relógio você tem a mais que da cota.
    /// Positivo = folga. Negativo = você fura antes da janela virar.
    public var slackPoints: Double? {
        guard let used, let nowFraction, certainty.hasInk else { return nil }
        return nowFraction * 100 - used
    }

    // MARK: - Como o número é escrito
    //
    // Segundo canal da honestidade. A textura fala com o olho de raspão;
    // isto fala com o olho que para.

    /// `50%` (medido) · `~53%` (derivado/composta) · `—` (ausente. NUNCA `0`)
    public var displayValue: String {
        guard let used, certainty.hasInk else { return "—" }
        switch unit {
        case .percent:
            let n = "\(Int(used.rounded()))%"
            return certainty.isApproximate ? "~\(n)" : n
        case .usd:
            // 32% de um crédito em dólar e 32% de uma cota opaca não são a
            // mesma coisa. Fingir que são é a mentira que o UI-SPEC §12.2 mata.
            guard let cap = capUSD else { return "—" }
            let spent = used / 100 * (cap as NSDecimalNumber).doubleValue
            let n = String(format: "US$ %.2f", spent).replacingOccurrences(of: ".", with: ",")
            return certainty.isApproximate ? "~\(n)" : n
        }
    }

    /// O denominador, quando ele existe de verdade. Só o Cursor tem um.
    public var displayUnitSuffix: String? {
        guard case .usd = unit, let cap = capUSD, certainty.hasInk else { return nil }
        return "/ \(Int((cap as NSDecimalNumber).doubleValue))"
    }

    /// A faixa `41–68` que acompanha o til. Só no derivado, e só se o core
    /// mandou piso e teto. Sem faixa, sem número inventado.
    public var displayRange: String? {
        guard case .derived(let lo, let hi) = certainty, let lo, let hi else { return nil }
        return "\(Int(lo.rounded()))–\(Int(hi.rounded()))"
    }

    /// "zera 16:50" · "zera sex 09:12"
    public var displayReset: String? {
        guard let resetsAt else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        let sameDay = Calendar.current.isDate(resetsAt, inSameDayAs: Date())
        f.dateFormat = sameDay ? "HH:mm" : "EEE HH:mm"
        return "zera \(f.string(from: resetsAt))"
    }
}

// MARK: - Do contrato pra pista

extension Lane {
    /// Uma janela do core vira uma pista. A certeza é resolvida uma vez, aqui.
    ///
    /// `startedAt` vem NA janela (contrato v1.2). O parâmetro só existe pra teste poder
    /// forçar um começo — em produção ninguém passa, e o dado é o do core.
    public init(
        window w: LimitWindow,
        provider: Provider,
        startedAt: Date? = nil,
        isLive: Bool = false
    ) {
        let certainty = Certainty.of(w)
        let startedAt = startedAt ?? w.startedAt
        let now: Double? = {
            guard let startedAt else { return nil }
            let total = w.resetsAt.timeIntervalSince(startedAt)
            guard total > 0 else { return nil }
            return min(1, max(0, Date().timeIntervalSince(startedAt) / total))
        }()

        self.init(
            id: "\(provider.rawValue)-\(w.id)",
            provider: provider,
            title: "\(provider.displayName) · \(w.label)",
            used: w.usedPercent,
            certainty: certainty,
            nowFraction: now,
            resetsAt: w.resetsAt,
            unit: w.unit,
            capUSD: w.capUSD,
            burnRatePerHour: w.burnRatePerHour,
            isLive: isLive
        )
    }

    /// A pista de um provedor que não tem NENHUMA janela.
    /// `windows` vazio no contrato = "não sabemos". Isto é o estado honesto
    /// que ocupa o lugar do zero mentiroso.
    public static func absent(
        provider: Provider,
        label: String,
        nowFraction: Double? = nil,
        capUSD: Decimal? = nil,
        unit: WindowUnit = .percent
    ) -> Lane {
        Lane(
            id: "\(provider.rawValue)-absent",
            provider: provider,
            title: "\(provider.displayName) · \(label)",
            used: nil,
            certainty: .absent,
            nowFraction: nowFraction,
            resetsAt: nil,
            unit: unit,
            capUSD: capUSD
        )
    }
}

// MARK: - O app inteiro, numa struct

/// O que a view recebe. Não existe caminho daqui pro disco.
public struct Dashboard: Sendable, Equatable {
    public var lanes: [Lane]
    /// Provedores que o app ENCONTROU no disco mas que ainda não queimaram nada.
    /// Serve ao estado vazio: "achei o Codex e o Claude Code" compra confiança
    /// no segundo 1, e é diferente de "não sei onde eles estão".
    public var discovered: [Provider]
    public var todayCostUSD: Decimal
    /// Marca a última janela que resetou — o app dá o respiro visual e limpa.
    public var justReset: String?

    public init(
        lanes: [Lane],
        discovered: [Provider] = [],
        todayCostUSD: Decimal = 0,
        justReset: String? = nil
    ) {
        self.lanes = lanes
        self.discovered = discovered
        self.todayCostUSD = todayCostUSD
        self.justReset = justReset
    }

    /// A pista que APERTA: a de menor folga entre as que têm tinta.
    /// É ela que responde "posso continuar trabalhando?", e é ela que vai pro
    /// ícone da barra — três provetas em 22 px não é informação, é sujeira.
    public var tightest: Lane? {
        lanes
            .filter { $0.certainty.hasInk && $0.used != nil }
            .min { a, b in (a.slackPoints ?? .infinity) < (b.slackPoints ?? .infinity) }
    }

    public var isEmpty: Bool {
        lanes.allSatisfy { !$0.certainty.hasInk || ($0.used ?? 0) == 0 }
    }
}
