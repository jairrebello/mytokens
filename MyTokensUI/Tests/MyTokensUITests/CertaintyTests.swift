import Testing
import MyTokensCore
import Foundation
@testable import MyTokensUI

// A regra que não se quebra tem teste. Se algum destes cair, o app está
// mentindo com pixel — e é melhor o CI descobrir isso do que o usuário.

@Suite("Certeza — medido, derivado, ausente")
struct CertaintyTests {

    @Test("janela ausente NUNCA vira zero — vira travessão")
    func absentIsNeverZero() {
        let lane = Lane.absent(provider: .cursor, label: "mês", capUSD: 20)
        #expect(lane.used == nil)
        #expect(lane.displayValue == "—")
        #expect(lane.certainty.hasInk == false)
    }

    @Test("medido fresco é sólido e SEM til")
    func measuredIsExact() {
        let w = LimitWindow(
            id: "5h", label: "5 horas", usedPercent: 50,
            resetsAt: .now.addingTimeInterval(3600), source: .measured,
            measuredAt: .now, measuredPercent: 50
        )
        let lane = Lane(window: w, provider: .claudeCode, startedAt: .now.addingTimeInterval(-3600))
        #expect(lane.certainty == .measured(at: w.measuredAt))
        #expect(lane.certainty.isApproximate == false)
        #expect(lane.displayValue == "50%")
    }

    @Test("medido + gasto no disco depois = composta, com costura no valor medido")
    func measuredPlusDiskBecomesComposite() {
        let at = Date.now.addingTimeInterval(-720)
        let w = LimitWindow(
            id: "5h", label: "5 horas", usedPercent: 53,
            resetsAt: .now.addingTimeInterval(3600), source: .measured,
            measuredAt: at, measuredPercent: 47
        )
        let lane = Lane(window: w, provider: .claudeCode, startedAt: .now.addingTimeInterval(-3600))
        #expect(lane.certainty == .composite(measuredUpTo: 47, at: at))
        // a PONTA é palpite, logo o número inteiro é aproximado
        #expect(lane.displayValue == "~53%")
    }

    @Test("derivado é aproximado e carrega faixa")
    func derivedCarriesRange() {
        let w = LimitWindow(
            id: "5h", label: "5 horas", usedPercent: 54,
            resetsAt: .now.addingTimeInterval(3600), source: .derived,
            lo: 41, hi: 68
        )
        let lane = Lane(window: w, provider: .claudeCode, startedAt: .now.addingTimeInterval(-3600))
        #expect(lane.displayValue == "~54%")
        #expect(lane.displayRange == "41–68")
    }

    @Test("derivado sem faixa degrada com honestidade: mantém o til, omite a faixa")
    func derivedWithoutRangeDoesNotInventOne() {
        let w = LimitWindow(
            id: "5h", label: "5 horas", usedPercent: 54,
            resetsAt: .now.addingTimeInterval(3600), source: .derived
        )
        let lane = Lane(window: w, provider: .claudeCode, startedAt: nil)
        #expect(lane.displayValue == "~54%")
        #expect(lane.displayRange == nil)   // não inventa faixa pra ficar bonito
    }

    @Test("Cursor é rotulado em US$, nunca em % solto")
    func cursorSpeaksDollars() {
        let w = LimitWindow(
            id: "mes", label: "mês", usedPercent: 32,
            resetsAt: .now.addingTimeInterval(86400 * 10), source: .measured,
            measuredAt: .now, measuredPercent: 32, unit: .usd, capUSD: 20
        )
        let lane = Lane(window: w, provider: .cursor, startedAt: .now)
        #expect(lane.displayValue == "US$ 6,40")
        #expect(lane.displayUnitSuffix == "/ 20")
    }

    @Test("projeção só existe acima de 70% — abaixo é ruído")
    func projectionOnlyWhenItMatters() {
        func lane(used: Double) -> Lane {
            let w = LimitWindow(
                id: "5h", label: "5 horas", usedPercent: used,
                resetsAt: .now.addingTimeInterval(3600), source: .measured,
                measuredAt: .now, measuredPercent: used, burnRatePerHour: 30
            )
            return Lane(window: w, provider: .claudeCode, startedAt: .now.addingTimeInterval(-3600))
        }
        #expect(lane(used: 50).projected == nil)
        #expect(lane(used: 85).projected != nil)
        // 85 + 30 pts/h × 1 h = 115 → 15 pontos VAZAM pra fora do trilho
        #expect((lane(used: 85).overrun ?? 0) > 10)
    }

    @Test("o ícone mostra a pista que APERTA, não a soma")
    func tightestLaneWins() {
        let folgada = Lane(id: "a", provider: .codex, title: "Codex · 7 d",
                           used: 31, certainty: .measured(at: .now),
                           nowFraction: 0.46, resetsAt: .now.addingTimeInterval(3600))
        let apertada = Lane(id: "b", provider: .claudeCode, title: "Claude · 5 h",
                            used: 86, certainty: .measured(at: .now),
                            nowFraction: 0.59, resetsAt: .now.addingTimeInterval(3600))
        let ausente = Lane.absent(provider: .cursor, label: "mês")
        let snap = Dashboard(lanes: [folgada, apertada, ausente])
        #expect(snap.tightest?.id == "b")   // e o ausente nunca ganha: não tem tinta
    }

    @Test("peso sobe com a tensão — e só o estouro ganha croma")
    func heatScale() {
        #expect(Heat(percent: 10) == .idle)
        #expect(Heat(percent: 40) == .low)
        #expect(Heat(percent: 60) == .mid)
        #expect(Heat(percent: 85) == .high)
        #expect(Heat(percent: 104) == .over)
    }
}
