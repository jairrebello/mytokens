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

    // MARK: - O passado
    //
    // 29 dias atrás + hoje. O `nil` NÃO é um buraco de conveniência pra fotografar a
    // hachura bonita: é o estado mais comum do disco real do Claude, que reescreve e
    // compacta sessão antiga. Se o mock não tivesse dia sem registro, a tela seria
    // desenhada contra um disco que não existe.
    //
    // Repare no `0`: dia COM registro e SEM gasto. Ele existe e é diferente do `nil` —
    // um é um zero que eu posso provar, o outro é a ausência da prova. Se os dois
    // desenhassem igual, o app perdia a única distinção que ele existe pra fazer.
    private static let past29: [Decimal?] = [
        3.10, 6.42, 0.90, nil, nil, 8.15, 12.90, 4.05, 2.20, 0, 5.60, 9.35, 7.10, 1.85,
        nil, 6.05, 11.40, 3.75, 0.42, 8.90, 10.20, 5.15, 2.95, 4.60, 7.85, 12.05, 6.30,
        9.10, 5.05,
    ]

    /// As fatias vêm em PARTES POR MIL do total, não em valores soltos: assim a coluna
    /// SEMPRE fecha com o trilho, em qualquer mock. Um mock cujos pedaços não somam o
    /// todo valida uma tela que o disco nunca vai produzir.
    ///
    /// Os 23‰ que faltam nos projetos são de propósito: é o gasto que o disco não sabe
    /// atribuir (evento sem `cwd`), e é ele que vira a linha "sem projeto no disco".
    private static let projectMix: [(String, Int)] = [
        ("mytokens", 328), ("funnel", 195), ("matriculas", 155), ("aion", 96),
        ("lms-isc", 70), ("sanavox", 54), ("channels", 38), ("clone-pages", 27),
        ("pesquisa-channels", 14),
    ]

    /// O Opus come 74% da conta. É esta linha que explica o custo — e é por isso que a
    /// tela mostra modelo, e não só total. O `gpt-5.6-terra` fica com o id CRU: o app não
    /// batiza modelo cujo esquema de nome ele não conhece.
    private static let modelMix: [(String, Int)] = [
        ("claude-opus-4-8", 742), ("claude-sonnet-4-6", 164),
        ("claude-haiku-4-5-20251001", 62), ("claude-fable-5", 24), ("gpt-5.6-terra", 8),
    ]

    /// O último dia do trilho é HOJE — e hoje é o mesmo número que o rodapé mostra em
    /// "HOJE". Duas leituras do mesmo fato não podem divergir na mesma tela.
    public static func history(today: Decimal, liveToday: Bool = true) -> History {
        let total = past29.compactMap { $0 }.reduce(Decimal(0), +) + today
        func mix(_ pairs: [(String, Int)]) -> [(String, Decimal)] {
            pairs.map { ($0.0, total * Decimal($0.1) / 1000) }
        }
        return History.assembled(
            dailyUSD: past29 + [today],
            projects: mix(projectMix),
            models: mix(modelMix),
            liveToday: liveToday
        )
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
            todayCostUSD: 4.12,
            history: history(today: 4.12)
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
            todayCostUSD: 11.80,
            history: history(today: 11.80)
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
            todayCostUSD: 3.40,
            history: history(today: 3.40)
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
            justReset: "claude-5h",
            history: history(today: 12.05, liveToday: false)
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
            todayCostUSD: 18.60,
            history: history(today: 18.60)
        )
    }
}
