//  MenuBarStyleTests.swift
//
//  O texto da barra é lido de relance, dezenas de vezes por dia. Se ele mentir — mostrar
//  um número onde não há dado — mente no lugar mais visível do app.

import Testing
import Foundation
import MyTokensCore
@testable import MyTokensUI

@Suite("Texto da barra de menu")
struct MenuBarStyleTests {

    private func dash(used: Double?, certainty: Certainty, resetsIn: TimeInterval?,
                      cost: Decimal = 0, unit: WindowUnit = .percent, cap: Decimal? = nil) -> Dashboard {
        let lane = Lane(
            id: "l", provider: .claudeCode, title: "Claude · 5 h",
            used: used, certainty: certainty, nowFraction: 0.5,
            resetsAt: resetsIn.map { Date().addingTimeInterval($0) },
            unit: unit, capUSD: cap
        )
        return Dashboard(lanes: [lane], todayCostUSD: cost)
    }

    @Test("só ícone: sempre vazio")
    func iconOnlyIsEmpty() {
        let d = dash(used: 42, certainty: .measured(at: nil), resetsIn: 3600)
        #expect(d.menuBarText(style: .iconOnly) == "")
    }

    @Test("porcentagem: a pista que aperta, com til se aproximado")
    func percent() {
        let medido = dash(used: 42.6, certainty: .measured(at: nil), resetsIn: 3600)
        #expect(medido.menuBarText(style: .percent) == "43%")

        let derivado = dash(used: 42.6, certainty: .derived(lo: 30, hi: 55), resetsIn: 3600)
        #expect(derivado.menuBarText(style: .percent) == "~43%")
    }

    @Test("sem dado NÃO vira 0% na barra — volta vazio")
    func absentIsEmptyNotZero() {
        let d = Dashboard(lanes: [.absent(provider: .cursor, label: "mês")])
        #expect(d.menuBarText(style: .percent) == "")
        #expect(d.menuBarText(style: .countdown) == "")
    }

    @Test("tempo até zerar: curto — 18m, 2h10, 3d")
    func countdownFormat() {
        let now = Date()
        #expect(Dashboard.shortCountdown(to: now.addingTimeInterval(18 * 60), now: now) == "18m")
        #expect(Dashboard.shortCountdown(to: now.addingTimeInterval(2 * 3600 + 10 * 60), now: now) == "2h10")
        #expect(Dashboard.shortCountdown(to: now.addingTimeInterval(3 * 3600), now: now) == "3h")
        #expect(Dashboard.shortCountdown(to: now.addingTimeInterval(3 * 86_400), now: now) == "3d")
        #expect(Dashboard.shortCountdown(to: now.addingTimeInterval(-10), now: now) == "0m")
    }

    @Test("custo: sem centavos acima de US$10, um decimal abaixo; zero some")
    func cost() {
        #expect(dash(used: nil, certainty: .absent, resetsIn: nil, cost: 8.37).menuBarText(style: .cost) == "US$8,4")
        #expect(dash(used: nil, certainty: .absent, resetsIn: nil, cost: 42.9).menuBarText(style: .cost) == "US$43")
        #expect(dash(used: nil, certainty: .absent, resetsIn: nil, cost: 0).menuBarText(style: .cost) == "")
    }
}
