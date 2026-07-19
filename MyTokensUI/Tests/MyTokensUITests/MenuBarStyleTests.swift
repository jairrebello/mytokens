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

    @Test("acima do teto o número REAL sai — 104%, nunca um teto fingido")
    func overflowShowsRealNumber() {
        let d = dash(used: 104.2, certainty: .measured(at: nil), resetsIn: 3600)
        #expect(d.menuBarText(style: .percent) == "104%")
    }

    // MARK: - a janela fixada (UI-SPEC §12)

    private func twoLanes(now: Date = Date()) -> Dashboard {
        let aperta = Lane(
            id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
            used: 80, certainty: .measured(at: nil), nowFraction: 0.2,
            resetsAt: now.addingTimeInterval(3600)
        )
        let fixavel = Lane(
            id: "claude-7d.fable", provider: .claudeCode, title: "Claude · Semana",
            used: 37, certainty: .derived(lo: 30, hi: 45), nowFraction: 0.5,
            resetsAt: now.addingTimeInterval(6 * 86_400)
        )
        return Dashboard(lanes: [aperta, fixavel])
    }

    @Test("fixada: a barra fala DA fixada, não da que aperta")
    func pinnedWinsOverTightest() {
        let d = twoLanes()
        #expect(d.menuBarText(style: .percent) == "80%")
        #expect(d.menuBarText(style: .percent, pinnedID: "claude-7d.fable") == "~37%")
    }

    @Test("fixada que sumiu: cai pra Automática, sem apagar nada")
    func pinnedMissingFallsBackToTightest() {
        let d = twoLanes()
        #expect(d.menuBarText(style: .percent, pinnedID: "fantasma") == "80%")
    }

    @Test("fixada sem tinta: também cai pra Automática — .absent não vira 0%")
    func pinnedAbsentFallsBack() {
        let aperta = Lane(
            id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
            used: 80, certainty: .measured(at: nil), nowFraction: 0.2,
            resetsAt: Date().addingTimeInterval(3600)
        )
        let d = Dashboard(lanes: [aperta, .absent(provider: .cursor, label: "mês")])
        #expect(d.menuBarText(style: .percent, pinnedID: "cursor-absent") == "80%")
    }

    @Test("janela em US$ na barra: dólar compacto, nunca % solto (§13.2)")
    func usdLaneShowsDollars() {
        let cursor = Lane(
            id: "cursor-mes", provider: .cursor, title: "Cursor · mês",
            used: 32, certainty: .measured(at: nil), nowFraction: 0.5,
            resetsAt: Date().addingTimeInterval(10 * 86_400),
            unit: .usd, capUSD: 20
        )
        let d = Dashboard(lanes: [cursor])
        #expect(d.menuBarText(style: .percent, pinnedID: "cursor-mes") == "US$6,4")
    }

    @Test("countdown segue a fixada")
    func countdownFollowsPin() {
        let now = Date()
        let d = twoLanes(now: now)
        #expect(d.menuBarText(style: .countdown, now: now) == "1h")
        #expect(d.menuBarText(style: .countdown, pinnedID: "claude-7d.fable", now: now) == "6d")
    }

    @Test("rótulo do picker ganha o modelo quando o escopo existe")
    func pickerLabelCarriesModelScope() {
        let semScopo = Lane(
            id: "a", provider: .claudeCode, title: "Claude · Semana",
            used: 10, certainty: .measured(at: nil), nowFraction: 0.1, resetsAt: nil
        )
        #expect(semScopo.pickerLabel == "Claude · Semana")

        let comScopo = Lane(
            id: "b", provider: .claudeCode, title: "Claude · Semana",
            used: 10, certainty: .measured(at: nil), nowFraction: 0.1, resetsAt: nil,
            modelScope: "fable"
        )
        #expect(comScopo.pickerLabel == "Claude · Semana · Fable")

        // Se um dia o label da fonte já vier com o modelo, não gaguejar.
        let jaTem = Lane(
            id: "c", provider: .claudeCode, title: "Claude · Semana · Fable",
            used: 10, certainty: .measured(at: nil), nowFraction: 0.1, resetsAt: nil,
            modelScope: "Fable"
        )
        #expect(jaTem.pickerLabel == "Claude · Semana · Fable")
    }
}
