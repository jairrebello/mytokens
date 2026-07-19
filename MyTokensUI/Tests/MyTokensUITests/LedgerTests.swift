//  LedgerTests.swift
//
//  O agrupamento por assinatura (UI-SPEC §11) tem cinco regras que dá pra
//  quebrar sem o compilador reclamar: herói fora, grupo vazio some, ordenação
//  por folga nas duas camadas, içamento só com carimbo unânime, e o popover
//  exigindo duas assinaturas pra ganhar header. Cada uma tem um teste.

import Foundation
import Testing
import MyTokensCore
@testable import MyTokensUI

private func lane(
    id: String,
    provider: Provider = .claudeCode,
    window: String = "5 h",
    used: Double? = 50,
    certainty: Certainty = .measured(at: nil),
    now: Double? = 0.5,
    modelScope: String? = nil
) -> Lane {
    Lane(
        id: id, provider: provider,
        title: "\(provider.displayName) · \(window)",
        used: used, certainty: certainty, nowFraction: now,
        resetsAt: used == nil ? nil : Date().addingTimeInterval(3600),
        modelScope: modelScope
    )
}

@Suite("Livro-razão agrupado")
struct LedgerTests {

    @Test("herói fora do grupo, e a linha dele não se repete")
    func heroExcluded() {
        // Claude 5h aperta mais (folga -30); Semana folga +20.
        let hero = lane(id: "c5", window: "5 h", used: 80, now: 0.5)
        let week = lane(id: "c7", window: "Semana", used: 30, now: 0.5)
        let dash = Dashboard(lanes: [hero, week])

        #expect(dash.tightest?.id == "c5")
        let ledger = dash.ledger
        #expect(ledger.count == 1)
        #expect(ledger[0].lanes.map(\.id) == ["c7"])
    }

    @Test("grupo que ficaria vazio some")
    func emptyGroupDropped() {
        let hero = lane(id: "c5", window: "5 h", used: 80)
        let codex = lane(id: "x7", provider: .codex, window: "Semana", used: 40)
        let dash = Dashboard(lanes: [hero, codex])

        // O grupo do Claude só tinha o herói → não existe no livro-razão.
        #expect(dash.ledger.map(\.id) == ["codex"])
    }

    @Test("grupos ordenados pela janela mais apertada; linhas por folga")
    func ordering() {
        let hero = lane(id: "b", provider: .cursor, window: "Ciclo", used: 99, now: 0.1)
        // Claude: folgas +40 e -10 → grupo ordena por -10.
        let cA = lane(id: "cA", window: "Semana", used: 10, now: 0.5)
        let cB = lane(id: "cB", window: "5 h", used: 60, now: 0.5, modelScope: "fable")
        // Codex: folga +5.
        let x = lane(id: "x", provider: .codex, window: "Semana", used: 45, now: 0.5)
        let dash = Dashboard(lanes: [hero, cA, cB, x])

        let ledger = dash.ledger
        #expect(ledger.map(\.id) == ["claude-code", "codex"])
        #expect(ledger[0].lanes.map(\.id) == ["cB", "cA"])
    }

    @Test("o grupo do herói herda a folga dele — a família fica junta, logo abaixo")
    func heroGroupStaysAdjacent() {
        // Claude 5h é o herói (folga -30). A Semana do Claude tem folga +40 —
        // pior que a do Codex (+5). Sem a herança, CLAUDE afundaria pro fim
        // e "Semana" ficaria longe do "5 h" lá do topo.
        let hero = lane(id: "c5", window: "5 h", used: 80, now: 0.5)
        let week = lane(id: "c7", window: "Semana", used: 10, now: 0.5)
        let x = lane(id: "x7", provider: .codex, window: "Semana", used: 45, now: 0.5)
        let dash = Dashboard(lanes: [hero, week, x])

        #expect(dash.tightest?.id == "c5")
        #expect(dash.ledger.map(\.id) == ["claude-code", "codex"])
    }

    @Test("procedência iça só com fonte e carimbo unânimes")
    func hoisting() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let hero = lane(id: "h", provider: .codex, used: 90)
        let a = lane(id: "a", window: "5 h", used: 30, certainty: .measured(at: at))
        let b = lane(id: "b", window: "Semana", used: 20, certainty: .measured(at: at))
        let c = lane(id: "c", window: "Mês", used: 10, certainty: .derived(lo: nil, hi: nil))

        // Unânime → iça.
        let uniform = Dashboard(lanes: [hero, a, b]).ledger
        #expect(uniform[0].hoistedProvenance != nil)

        // Divergente → cada linha diz a sua.
        let mixed = Dashboard(lanes: [hero, a, b, c]).ledger
        #expect(mixed[0].hoistedProvenance == nil)
    }

    @Test("popover: header só com duas assinaturas no livro-razão")
    func popoverRule() {
        let hero = lane(id: "c5", window: "5 h", used: 80)
        let week = lane(id: "c7", window: "Semana", used: 30)

        // Uma assinatura só → lista lisa.
        #expect(Dashboard(lanes: [hero, week]).popoverGroups == nil)

        // Duas assinaturas com linha → headers.
        let x = lane(id: "x7", provider: .codex, window: "Semana", used: 40)
        let grouped = Dashboard(lanes: [hero, week, x]).popoverGroups
        #expect(grouped?.count == 2)

        // A segunda "assinatura" sendo o Cursor AUSENTE não conta — e o grupo
        // ausente nem aparece no popover: lá ele é ressalva do veredito.
        let ghost = lane(id: "cu", provider: .cursor, window: "Ciclo",
                         used: nil, certainty: .absent, now: 0.4)
        #expect(Dashboard(lanes: [hero, week, ghost]).popoverGroups == nil)
    }

    @Test("rótulo da linha agrupada: janela primeiro, modelo qualifica")
    func groupedTitle() {
        let scoped = lane(id: "f", window: "Semana", used: 40, modelScope: "fable")
        #expect(scoped.groupedTitle == "Semana · Fable")

        let plain = lane(id: "p", window: "Semana", used: 40)
        #expect(plain.groupedTitle == "Semana")

        // Fonte que um dia já mandar o modelo no label não ganha gagueira.
        let dup = lane(id: "d", window: "Semana · Fable", used: 40, modelScope: "fable")
        #expect(dup.groupedTitle == "Semana · Fable")
    }
}
