//  VerdictTests.swift
//
//  O veredito é a frase que o usuário lê 30x por dia. Se ele mentir, o app mente —
//  não importa quão honesta seja a pista logo abaixo.

import Testing
import Foundation
import MyTokensCore
@testable import MyTokensUI

@Suite("Veredito — a frase não pode afirmar o que o app não sabe")
struct VerdictTests {

    /// A REGRESSÃO QUE O DISCO REAL PEGOU (13/07): sem hook e sem janela no rollout,
    /// nenhuma pista tem tinta — e o app estampava "Nada queimado ainda" com
    /// US$ 135,87 queimados no disco naquele mesmo dia.
    ///
    /// Falta de LIMITE não é ausência de GASTO. Gasto vem do disco (a gente sabe);
    /// limite vem do provedor (a gente não sabe). Confundir os dois é a mentira que
    /// este app existe pra não contar.
    @Test("gasto sem limite conhecido NUNCA vira 'nada queimado'")
    func spendWithoutLimitsIsNotEmpty() {
        let dash = Dashboard(
            lanes: [
                .absent(provider: .claudeCode, label: "5 h"),
                .absent(provider: .codex, label: "7 d"),
            ],
            discovered: [.claudeCode, .codex],
            todayCostUSD: 135.87
        )

        let v = Verdict.of(dash)

        #expect(v.headline != "Nada queimado ainda.")
        #expect(v.detail.contains("135,87"), "o gasto que o app SABE tem que aparecer: \(v.detail)")
    }

    @Test("sem gasto e sem limite: aí sim, nada queimado")
    func trulyEmpty() {
        let dash = Dashboard(
            lanes: [.absent(provider: .claudeCode, label: "5 h")],
            discovered: [.claudeCode],
            todayCostUSD: 0
        )

        #expect(Verdict.of(dash).headline == "Nada queimado ainda.")
    }

    /// O contrário também não pode: com janela medida, quem manda é a pista que aperta,
    /// não o custo do dia.
    @Test("com limite medido, o veredito fala da pista que aperta")
    func measuredWindowWins() {
        let now = Date()
        let w = LimitWindow(
            id: "claude-5h", label: "5 h",
            usedPercent: 42, resetsAt: now.addingTimeInterval(3600),
            source: .measured,
            startedAt: now.addingTimeInterval(-4 * 3600),
            measuredAt: now, measuredPercent: 42
        )
        let dash = Dashboard(
            lanes: [Lane(window: w, provider: .claudeCode)],
            discovered: [.claudeCode],
            todayCostUSD: 135.87
        )

        let v = Verdict.of(dash)
        #expect(v.tightestID == "claude-code-claude-5h")
        #expect(v.headline == "Dá pra continuar.")
    }
}
