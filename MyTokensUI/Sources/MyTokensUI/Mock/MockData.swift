//  MockData.swift
//
//  Mock CONTRA O CONTRATO, não contra o disco. A view não sabe (e não pode
//  saber) que estes vieram de um literal em vez de um FSEvent. Quando o Turbina
//  entregar o core de verdade, é este arquivo que morre — e nenhuma view muda.
//
//  Os números vêm dos mockups do Prisma e dos achados da Fase 1:
//    Claude → 5 h E semanal, MEDIDO (statusLine)
//    Codex  → só semanal (a de 5 h morreu em 2026-07-12), MEDIDO
//    Cursor → pode não ter NADA sem credencial → AUSENTE
//  Três formas diferentes na mesma tela. É esse o problema de design.

import MyTokensCore
import Foundation

public enum Mock {

    private static func at(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private static func inDays(_ d: Int, _ h: Int, _ m: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: d, to: at(h, m)) ?? Date()
    }

    // MARK: - Normal — o dia comum
    //
    // Claude 5 h medido às 14:35, com gasto do disco DEPOIS disso: barra
    // COMPOSTA, com costura. Claude 7 d medido. Codex 7 d medido. Cursor ausente.

    public static var normal: Dashboard {
        Dashboard(
            lanes: [
                Lane(
                    id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                    used: 50,
                    certainty: .composite(measuredUpTo: 47, at: at(14, 35)),
                    nowFraction: 0.59, resetsAt: at(16, 50),
                    burnRatePerHour: 14, isLive: true
                ),
                Lane(
                    id: "claude-7d", provider: .claudeCode, title: "Claude · 7 d",
                    used: 38, certainty: .measured(at: at(14, 35)),
                    nowFraction: 0.46, resetsAt: inDays(2, 9, 12)
                ),
                Lane(
                    id: "codex-7d", provider: .codex, title: "Codex · 7 d",
                    used: 31, certainty: .measured(at: at(13, 58)),
                    nowFraction: 0.46, resetsAt: inDays(4, 9, 20)
                ),
                cursorAbsent,
            ],
            discovered: [.claudeCode, .codex],
            todayCostUSD: 4.12
        )
    }

    /// O Cursor sem credencial. NÃO é zero — é `—`, pista tracejada, e o relógio
    /// continua correndo por cima dela. Falta a tinta, não a pista.
    public static var cursorAbsent: Lane {
        Lane.absent(
            provider: .cursor, label: "mês",
            nowFraction: 0.41,          // o relógio a gente SEMPRE sabe
            capUSD: 20, unit: .usd
        )
    }

    // MARK: - Vazio — o primeiro boot
    //
    // Não é um pedido de configuração: é a prova de que o app já sabe onde
    // procurar. Pistas ABERTAS, relógio em zero. Vazio ≠ zero — a janela nem
    // começou, e isso é diferente de "não sei", que é o Cursor lá embaixo.

    public static var empty: Dashboard {
        Dashboard(
            lanes: [
                Lane(
                    id: "codex-7d", provider: .codex, title: "Codex · 7 d",
                    used: 0, certainty: .measured(at: nil),
                    nowFraction: 0.0, resetsAt: inDays(7, 9, 20)
                ),
                Lane(
                    id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                    used: 0, certainty: .measured(at: nil),
                    nowFraction: 0.0, resetsAt: Date().addingTimeInterval(5 * 3600)
                ),
                cursorAbsent,
            ],
            discovered: [.claudeCode, .codex]
        )
    }

    // MARK: - 85% — o quase-lá
    //
    // A frase muda, o número engorda (heat 3), a projeção ROMPE o trilho.
    // A tela NÃO fica vermelha. O alarme é geometria, não cor.

    public static var almostThere: Dashboard {
        Dashboard(
            lanes: [
                Lane(
                    id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                    used: 85,
                    certainty: .composite(measuredUpTo: 81, at: at(14, 35)),
                    nowFraction: 0.61, resetsAt: at(16, 50),
                    burnRatePerHour: 26, isLive: true
                ),
                Lane(
                    id: "claude-7d", provider: .claudeCode, title: "Claude · 7 d",
                    used: 44, certainty: .measured(at: at(14, 35)),
                    nowFraction: 0.46, resetsAt: inDays(2, 9, 12)
                ),
                Lane(
                    id: "codex-7d", provider: .codex, title: "Codex · 7 d",
                    used: 31, certainty: .measured(at: at(13, 58)),
                    nowFraction: 0.46, resetsAt: inDays(4, 9, 20)
                ),
                cursorAbsent,
            ],
            discovered: [.claudeCode, .codex],
            todayCostUSD: 11.80
        )
    }

    // MARK: - Sem o hook — o Claude 100% DERIVADO
    //
    // O teto do plano não é publicado por NINGUÉM. Sem o `statusLine`, tudo que
    // o app tem é token do disco ÷ um denominador que ele não conhece.
    // Reticulado de ponta a ponta + faixa larga + til.

    public static var noHook: Dashboard {
        Dashboard(
            lanes: [
                Lane(
                    id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                    used: 54, certainty: .derived(lo: 41, hi: 68),
                    nowFraction: 0.59, resetsAt: at(16, 50),
                    burnRatePerHour: 12, isLive: true
                ),
                Lane(
                    id: "codex-7d", provider: .codex, title: "Codex · 7 d",
                    used: 31, certainty: .measured(at: at(13, 58)),
                    nowFraction: 0.46, resetsAt: inDays(4, 9, 20)
                ),
                cursorAbsent,
            ],
            discovered: [.claudeCode, .codex],
            todayCostUSD: 3.40
        )
    }

    // MARK: - O reset — a janela virou
    //
    // Alívio, e alívio merece respiro. A pista DRENA (900 ms, mais lento que o
    // avanço) — e só ela: as outras não se mexem, porque as janelas são
    // independentes e têm comprimentos diferentes.

    public static var justReset: Dashboard {
        Dashboard(
            lanes: [
                Lane(
                    id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                    used: 0, certainty: .measured(at: at(16, 50)),
                    nowFraction: 0.0, resetsAt: at(21, 50)
                ),
                Lane(
                    id: "claude-7d", provider: .claudeCode, title: "Claude · 7 d",
                    used: 44, certainty: .measured(at: at(16, 50)),
                    nowFraction: 0.47, resetsAt: inDays(2, 9, 12)
                ),
                Lane(
                    id: "codex-7d", provider: .codex, title: "Codex · 7 d",
                    used: 31, certainty: .measured(at: at(13, 58)),
                    nowFraction: 0.46, resetsAt: inDays(4, 9, 20)
                ),
                cursorAbsent,
            ],
            discovered: [.claudeCode, .codex],
            todayCostUSD: 12.05,
            justReset: "claude-5h"
        )
    }

    // MARK: - Estourado

    public static var overrun: Dashboard {
        Dashboard(
            lanes: [
                Lane(
                    id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                    used: 100, certainty: .measured(at: at(15, 47)),
                    nowFraction: 0.78, resetsAt: at(16, 50),
                    burnRatePerHour: 30
                ),
                Lane(
                    id: "codex-7d", provider: .codex, title: "Codex · 7 d",
                    used: 62, certainty: .measured(at: at(15, 40)),
                    nowFraction: 0.46, resetsAt: inDays(4, 9, 20),
                    isLive: true
                ),
                cursorAbsent,
            ],
            discovered: [.claudeCode, .codex],
            todayCostUSD: 18.60
        )
    }
}
