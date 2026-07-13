//  AccessibilityTests.swift
//
//  A frase que o VoiceOver lê é PRODUTO, não enfeite — e é pura, então é testável
//  sem subir uma tela. O que estes testes protegem é a mesma coisa que o
//  `CertaintyTests` protege no pixel: a honestidade não pode existir só pra quem
//  enxerga.
//
//  A regressão que este arquivo existe pra impedir: uma pista sem tinta ser lida
//  como "0%". Zero é um número, número é uma afirmação, e essa afirmação seria
//  falsa. Ausência é ausência — em tinta, em texto, e em som.

import Testing
import Foundation
import SwiftUI
import MyTokensCore
@testable import MyTokensUI

@Suite("A pista falada — a certeza atravessa pro som, ou o app mente pra quem não vê")
struct LaneSpeechTests {

    private func at(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Ausência

    @Test("pista sem tinta NUNCA é lida como 0%")
    func absentIsNeverZero() {
        let lane = Lane.absent(provider: .cursor, label: "mês", nowFraction: 0.42, capUSD: 20, unit: .usd)
        let said = lane.accessibilityReading()

        #expect(!said.contains("0%"))
        #expect(!said.contains("zero"))
        #expect(said.contains("Não sei quanto da cota foi usada"))
        // ...e vem com o PORQUÊ. "Não sei" sem motivo é desculpa; com motivo é leitura.
        #expect(said.contains("sem dado local"))
    }

    @Test("pista sem tinta ainda diz o RELÓGIO — falta a tinta, não a pista")
    func absentStillSpeaksTheClock() {
        let lane = Lane.absent(provider: .cursor, label: "mês", nowFraction: 0.42)
        #expect(lane.accessibilityReading().contains("Passaram 42% do tempo da janela."))
    }

    @Test("ausente com crédito conhecido diz o TETO, que é o que se sabe")
    func absentSpeaksTheCapItKnows() {
        let lane = Lane.absent(provider: .cursor, label: "mês", capUSD: 20, unit: .usd)
        #expect(lane.accessibilityReading().contains("crédito da janela é de 20 dólares"))
    }

    // MARK: - Medido

    @Test("medido: provedor, janela, quanto queimou, a certeza, o tempo e o reset")
    func measuredReadsWholeLane() {
        let lane = Lane(
            id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
            used: 68, certainty: .measured(at: at(14, 35)),
            nowFraction: 0.52, resetsAt: at(16, 50)
        )
        let said = lane.accessibilityReading()

        #expect(said.contains("Claude"))
        #expect(said.contains("janela de 5 h"))
        #expect(said.contains("Queimou 68% da cota"))
        #expect(said.contains("medido pelo provedor às 14:35"))
        #expect(said.contains("Passaram 52% do tempo da janela"))
        #expect(said.contains("Zera às 16:50"))
        // Medido é FATO: nada de "cerca de".
        #expect(!said.contains("cerca de"))
        #expect(!said.contains("estimado"))
    }

    @Test("acima de 100% a fala diz que passou do teto")
    func overrunSaysItBusted() {
        let lane = Lane(
            id: "x", provider: .codex, title: "Codex · 7 d",
            used: 104, certainty: .measured(at: at(9, 0)),
            nowFraction: 0.8, resetsAt: at(23, 0)
        )
        #expect(lane.accessibilityReading().contains("Passou do teto."))
    }

    // MARK: - Estimado

    @Test("derivado: a fala diz 'estimado' e carrega a FAIXA")
    func derivedSpeaksTheRange() {
        let lane = Lane(
            id: "x", provider: .codex, title: "Codex · 7 d",
            used: 53, certainty: .derived(lo: 41, hi: 68),
            nowFraction: 0.5, resetsAt: at(18, 0)
        )
        let said = lane.accessibilityReading()

        #expect(said.contains("cerca de 53% da cota"))
        #expect(said.contains("estimado"))
        #expect(said.contains("entre 41% e 68%"))
        // O `~` do número na tela viraria "til" na fala. A palavra é que atravessa.
        #expect(!said.contains("~"))
    }

    @Test("derivado sem faixa: mantém o 'estimado' e NÃO inventa piso e teto")
    func derivedWithoutRangeInventsNothing() {
        let lane = Lane(
            id: "x", provider: .codex, title: "Codex · 7 d",
            used: 53, certainty: .derived(lo: nil, hi: nil),
            nowFraction: 0.5, resetsAt: at(18, 0)
        )
        let said = lane.accessibilityReading()

        #expect(said.contains("estimado"))
        #expect(!said.contains("entre"))
    }

    // MARK: - Composta — a costura dita em palavra

    @Test("composta: diz até ONDE é fato, a hora do fato, e que o resto é palpite")
    func compositeSpeaksTheSeam() {
        let lane = Lane(
            id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
            used: 50, certainty: .composite(measuredUpTo: 47, at: at(14, 35)),
            nowFraction: 0.59, resetsAt: at(16, 50)
        )
        let said = lane.accessibilityReading()

        #expect(said.contains("cerca de 50% da cota"))
        #expect(said.contains("medido até 47% às 14:35"))
        #expect(said.contains("estimado do que ficou no disco"))
    }

    // MARK: - Dólar

    @Test("janela em dólar fala DÓLARES — 32% de crédito e 32% de cota opaca não são a mesma coisa")
    func usdSpeaksMoneyAndQuota() {
        let lane = Lane(
            id: "cursor", provider: .cursor, title: "Cursor · mês",
            used: 32, certainty: .measured(at: at(15, 0)),
            nowFraction: 0.5, resetsAt: at(23, 59),
            unit: .usd, capUSD: 20
        )
        let said = lane.accessibilityReading()

        #expect(said.contains("6,40 dólares dos 20 do crédito"))
        #expect(said.contains("32% da cota"))
        #expect(!said.contains("US$"))   // sigla é coisa de olho
    }

    // MARK: - As métricas da janela

    @Test("folga vira palavra, não sinal: '+14 pts' não se lê em voz alta")
    func slackSpeaksInWords() {
        let ahead = Lane(
            id: "a", provider: .claudeCode, title: "Claude · 5 h",
            used: 40, certainty: .measured(at: nil), nowFraction: 0.54, resetsAt: nil
        )
        let behind = Lane(
            id: "b", provider: .claudeCode, title: "Claude · 5 h",
            used: 78, certainty: .measured(at: nil), nowFraction: 0.54, resetsAt: nil
        )
        #expect(ahead.spokenSlack == "14 pontos de folga: a cota anda mais devagar que o relógio")
        #expect(behind.spokenSlack == "24 pontos de aperto: a cota anda mais rápido que o relógio")
    }

    @Test("o veredito falado perde o markup, não perde palavra")
    func verdictDropsMarkupNotWords() {
        let v = Verdict.of(Mock.normal)
        #expect(!v.spoken.contains("**"))
        #expect(v.spoken.hasPrefix(v.headline))
        #expect(v.spoken.contains(v.detail.replacingOccurrences(of: "**", with: "")))
    }
}

// MARK: - Reduce motion
//
// UI-SPEC §6: "reduce motion corta a ANIMAÇÃO, nunca a INFORMAÇÃO." A resolução é
// pura — testar aqui é testar a regra, não a renderização dela.

@Suite("Reduce motion — corta o movimento, nunca o dado")
struct ReduceMotionTests {

    @Test("sem reduce motion, o dado anda na mola crítica do §6")
    func dataUsesCriticalSpring() {
        #expect(Motion.Cue.data.animation(reduceMotion: false) == Motion.state)
        #expect(Motion.Cue.drain.animation(reduceMotion: false) == Motion.drain)
        #expect(Motion.Cue.chrome.animation(reduceMotion: false) == Motion.ui)
    }

    @Test("com reduce motion, TUDO que carrega dado continua animando — curto e reto")
    func dataStillAnimatesWhenCalm() {
        // `nil` aqui seria um pulo. Pulo não é honesto nem desonesto — é só pior de
        // ler. O que o §6 proíbe é a MOLA, não a transição.
        #expect(Motion.Cue.data.animation(reduceMotion: true) == Motion.calm)
        #expect(Motion.Cue.drain.animation(reduceMotion: true) == Motion.calm)
        #expect(Motion.Cue.chrome.animation(reduceMotion: true) == Motion.calm)
        #expect(Motion.Cue.tick.animation(reduceMotion: true) == Motion.calm)
    }

    @Test("o pulso é o ÚNICO movimento que o reduce motion mata — porque é o único sem dado")
    func onlyTheOrnamentDies() {
        #expect(Motion.Cue.pulse.animation(reduceMotion: false) == Motion.pulse)
        #expect(Motion.Cue.pulse.animation(reduceMotion: true) == nil)
    }
}
