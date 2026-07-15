import Testing
import MyTokensCore
import Foundation
@testable import MyTokensUI

// O passado tem as MESMAS regras do presente: nunca um zero onde a resposta é ausência,
// nunca um nome inventado, nunca um número que não fecha. Se algum destes cair, a bancada
// está desenhando uma história que o disco não contou.

@Suite("História — 30 dias, projeto, modelo")
struct HistoryTests {

    // MARK: - Fábrica

    private static let cal = Calendar.current

    /// Um evento com custo, num dia relativo a hoje. `d = 0` é hoje; `d = 3` é anteontem +1.
    private static func ev(
        daysAgo d: Int,
        usd: Decimal,
        project: String? = "mytokens",
        model: String = "claude-opus-4-8",
        now: Date = Date()
    ) -> UsageEvent {
        let day = cal.date(byAdding: .day, value: -d, to: cal.startOfDay(for: now))!
        let ts = day.addingTimeInterval(12 * 3600)   // meio-dia: longe de qualquer fronteira
        return UsageEvent(
            id: "\(d)-\(project ?? "-")-\(model)-\(usd)",
            provider: .claudeCode,
            ts: ts,
            sessionId: "s",
            model: model,
            project: project,
            tokens: TokenBuckets(input: 100, output: 50),
            costUSD: usd
        )
    }

    // MARK: - A ausência

    @Test("dia sem evento é AUSÊNCIA — nil, nunca zero")
    func absentDayIsNil() {
        let h = History(events: [Self.ev(daysAgo: 0, usd: 5)])

        #expect(h.days.count == 30)
        #expect(h.days.last?.costUSD == 5)            // hoje tem registro
        #expect(h.days.first?.costUSD == nil)         // 29 dias atrás, não
        #expect(h.days.first?.hasRecord == false)
        #expect(h.daysWithoutRecord == 29)
    }

    @Test("dia COM evento e custo zero é ZERO — e isso é diferente de ausência")
    func zeroIsAFactWhenMeasured() {
        // Um modelo sem preço na tabela (o `<synthetic>` do Claude) gera evento e não gera
        // dinheiro. O dia foi lido. Ele só não custou — e isso eu POSSO afirmar.
        let h = History(events: [Self.ev(daysAgo: 1, usd: 0, model: "<synthetic>")])
        let ontem = h.days[28]

        #expect(ontem.costUSD == 0)
        #expect(ontem.hasRecord)                       // registro existe
        #expect(h.days[27].hasRecord == false)         // o vizinho, não
        #expect(h.daysWithoutRecord == 29)
    }

    @Test("evento fora da janela de 30 dias não entra no trilho")
    func outsideWindowIsIgnored() {
        let h = History(events: [Self.ev(daysAgo: 45, usd: 999), Self.ev(daysAgo: 2, usd: 3)])

        #expect(h.totalUSD == 3)
        #expect(h.days.allSatisfy { ($0.costUSD ?? 0) < 999 })
        // ...mas o disco LEMBRA que ele existe: é o que permite dizer "o registro começa em".
        #expect(h.firstRecordAt != nil)
    }

    // MARK: - Onde o dinheiro foi

    @Test("projeto sem custo NÃO aparece como US$ 0,00 — não aparece")
    func zeroCostProjectDoesNotExist() {
        let h = History(events: [
            Self.ev(daysAgo: 1, usd: 10, project: "mytokens"),
            Self.ev(daysAgo: 1, usd: 0, project: "fantasma"),
        ])

        #expect(h.projects.map(\.key) == ["mytokens"])
        #expect(h.projects.contains { $0.key == "fantasma" } == false)
    }

    @Test("gasto sem projeto no disco vira o resto que FECHA a conta")
    func unattributedClosesTheSum() {
        let h = History(events: [
            Self.ev(daysAgo: 1, usd: 8, project: "mytokens"),
            Self.ev(daysAgo: 1, usd: 2, project: nil),
        ])

        #expect(h.totalUSD == 10)
        #expect(h.unattributedUSD == 2)
        // projetos + não-atribuído == total. Um resto que não fecha é uma mentira silenciosa.
        #expect(h.projects.reduce(Decimal(0)) { $0 + $1.costUSD } + h.unattributedUSD == h.totalUSD)
    }

    @Test("as fatias somam o todo e vêm em ordem de custo")
    func sharesAddUp() {
        let h = History(events: [
            Self.ev(daysAgo: 1, usd: 60, project: "a"),
            Self.ev(daysAgo: 1, usd: 30, project: "b"),
            Self.ev(daysAgo: 1, usd: 10, project: "c"),
        ])

        #expect(h.projects.map(\.key) == ["a", "b", "c"])
        #expect(abs(h.projects.map(\.share).reduce(0, +) - 1.0) < 0.0001)
        #expect(abs((h.projects.first?.share ?? 0) - 0.6) < 0.0001)
    }

    @Test("o corte do top-N devolve a cauda com tamanho e valor")
    func topAndRest() throws {
        let cuts = (1...8).map {
            History.Cut(key: "p\($0)", label: "p\($0)", costUSD: Decimal(10 - $0), share: 0)
        }
        let (shown, rest) = History.top(cuts, 5)

        let cauda = try #require(rest)
        #expect(shown.count == 5)
        #expect(shown.map(\.costUSD) == [9, 8, 7, 6, 5])
        #expect(cauda.count == 3)
        #expect(cauda.costUSD == Decimal(9))   // 4 + 3 + 2

        // Cabe tudo? Então não existe cauda — e não existe linha "+ 0 projetos".
        #expect(History.top(Array(cuts.prefix(3)), 5).rest == nil)
    }

    // MARK: - O corte por dia (a barra que vira seleção)

    @Test("cada dia carrega o próprio corte — e a fatia é fração DO DIA, não do período")
    func perDayBreakdownIsScopedToTheDay() {
        let h = History(events: [
            // Ontem: dois projetos, dois modelos.
            Self.ev(daysAgo: 1, usd: 6, project: "mytokens", model: "claude-opus-4-8"),
            Self.ev(daysAgo: 1, usd: 4, project: "funnel", model: "claude-sonnet-4-6"),
            // Hoje: só um projeto, pra provar que o corte NÃO vaza de um dia pro outro.
            Self.ev(daysAgo: 0, usd: 100, project: "mytokens", model: "claude-opus-4-8"),
        ])

        let ontem = h.days[28]
        let bd = try! #require(ontem.breakdown)
        #expect(bd.projects.map(\.key) == ["mytokens", "funnel"])
        #expect(bd.projects.first?.costUSD == 6)
        // 60% do DIA (6 de 10) — não 6% do período (6 de ~110), que seria o número
        // do corte do mês vazando pra dentro do corte do dia.
        #expect(abs((bd.projects.first?.share ?? 0) - 0.6) < 0.0001)
        #expect(bd.models.map(\.key) == ["claude-opus-4-8", "claude-sonnet-4-6"])
        #expect(bd.unattributedUSD == 0)

        let hoje = h.days[29]
        let bdHoje = try! #require(hoje.breakdown)
        #expect(bdHoje.projects.map(\.costUSD) == [100])
        #expect(ontem.isSelectable)
        #expect(hoje.isSelectable)
    }

    @Test("dia sem registro é selecionável e honesto: corte vazio, não corte inventado")
    func dayWithoutRecordHasEmptyBreakdown() {
        let h = History(events: [Self.ev(daysAgo: 0, usd: 5)])
        let semRegistro = h.days[0]   // 29 dias atrás — nenhum evento caiu aqui

        #expect(semRegistro.hasRecord == false)
        let bd = try! #require(semRegistro.breakdown)
        #expect(bd.projects.isEmpty)
        #expect(bd.models.isEmpty)
        #expect(bd.unattributedUSD == 0)
        // Selecionável mesmo sem registro: a lista vira "—", que é a resposta honesta,
        // não uma seleção recusada.
        #expect(semRegistro.isSelectable)
    }

    @Test("evento sem projeto no dia vira o não-atribuído DAQUELE dia, não do mês")
    func perDayUnattributedClosesTheDaySum() {
        let h = History(events: [
            Self.ev(daysAgo: 1, usd: 8, project: "mytokens"),
            Self.ev(daysAgo: 1, usd: 2, project: nil),
            Self.ev(daysAgo: 0, usd: 50, project: nil),   // outro dia, não pode contaminar
        ])

        let ontem = try! #require(h.days[28].breakdown)
        #expect(ontem.unattributedUSD == 2)
        #expect(ontem.projects.reduce(Decimal(0)) { $0 + $1.costUSD } + ontem.unattributedUSD == 10)

        let hoje = try! #require(h.days[29].breakdown)
        #expect(hoje.unattributedUSD == 50)
        #expect(hoje.projects.isEmpty)
    }

    @Test("History.assembled não sabe cortar por dia — e diz isso não fingindo seleção")
    func assembledHistoryHasNoPerDayBreakdown() {
        let h = History.assembled(
            dailyUSD: [3, nil, 0],
            projects: [("mytokens", 3)],
            models: [("claude-opus-4-8", 3)]
        )

        #expect(h.days.allSatisfy { $0.breakdown == nil })
        #expect(h.days.allSatisfy { $0.isSelectable == false })
    }

    // MARK: - O nome do modelo

    @Test("id de modelo conhecido vira nome; o desconhecido fica CRU")
    func modelNaming() {
        #expect(History.modelLabel("claude-opus-4-8") == "Opus 4.8")
        #expect(History.modelLabel("claude-sonnet-5") == "Sonnet 5")
        #expect(History.modelLabel("claude-haiku-4-5-20251001") == "Haiku 4.5")   // data some
        #expect(History.modelLabel("claude-fable-5") == "Fable 5")

        // O app NÃO batiza o que não conhece. Inventar "GPT 5.6 Terra" é afirmar mais do que
        // se sabe — a mesma família de mentira do zero.
        #expect(History.modelLabel("gpt-5.6-terra") == "gpt-5.6-terra")
        #expect(History.modelLabel("<synthetic>") == "<synthetic>")
    }

    // MARK: - A prova de que a passada única não mentiu
    //
    // A `History` NÃO chama `Aggregator.by(.day)` / `byProject` / `byModel`: ela faz UMA
    // passada, porque as três juntas custam 150 ms sobre o disco real e o refresh tem 200.
    // Duplicar agregação sem provar equivalência é assinar um cheque em branco pro dia em
    // que as duas divergirem em silêncio. Este teste é o cheque.

    @Test("a passada única bate, centavo por centavo, com o Aggregator do core")
    func matchesTheCoreAggregator() {
        var events: [UsageEvent] = []
        let projects = ["mytokens", "funnel", "aion", nil]
        let models = ["claude-opus-4-8", "claude-sonnet-4-6", "<synthetic>"]

        for d in 0..<28 where d % 5 != 3 {           // buracos de propósito: dias sem registro
            for (i, p) in projects.enumerated() {
                events.append(Self.ev(
                    daysAgo: d,
                    usd: Decimal(d + i + 1) / 100,
                    project: p,
                    model: models[(d + i) % models.count]
                ))
            }
        }

        let h = History(events: events)

        // 1) o dia
        let cutoff = Self.cal.date(byAdding: .day, value: -29, to: Self.cal.startOfDay(for: Date()))!
        let slice = events.filter { $0.ts >= cutoff }
        let buckets = Aggregator.by(.day, events: slice)

        for b in buckets {
            let mine = h.days.first { Self.cal.isDate($0.start, inSameDayAs: b.start) }
            #expect(mine?.costUSD == b.spend.costUSD)
        }
        // e o inverso: dia que o Aggregator não tem, o trilho desenha como ausência
        let known = Set(buckets.map { Self.cal.startOfDay(for: $0.start) })
        for day in h.days where !known.contains(Self.cal.startOfDay(for: day.start)) {
            #expect(day.costUSD == nil)
        }

        // 2) o projeto
        let ref = Aggregator.byProject(slice)
        #expect(h.projects.count == ref.filter { $0.value.costUSD > 0 }.count)
        for cut in h.projects {
            #expect(cut.costUSD == ref[cut.key]?.costUSD)
        }

        // 3) o modelo
        let refM = Aggregator.byModel(slice)
        for cut in h.models {
            #expect(cut.costUSD == refM[cut.key]?.costUSD)
        }

        // 4) o todo
        #expect(h.totalUSD == slice.reduce(Decimal(0)) { $0 + $1.costUSD })
    }

    // MARK: - A régua

    @Test("a régua SEMPRE sobra acima do pior dia — nenhuma coluna encosta no topo")
    func scaleAlwaysHasHeadroom() {
        // Encostar no topo diria "cheio". Gasto não tem teto, e um trilho que finge ter um
        // é a mesma mentira de apresentar soma de token como "quanto sobra" (UI-SPEC §10).
        for peak in [0.03, 0.9, 4.9, 5.0, 12.9, 100.0, 458.2, 5_277.0] {
            let s = DayRack.Scale(peak: peak)
            #expect(s.max > peak, "o pico \(peak) encostou no topo (\(s.max))")
            #expect(s.grades.allSatisfy { $0 < s.max })   // nenhuma linha NO topo: teto nenhum
            #expect(s.grades.count <= 3)                  // régua, não papel quadriculado
        }
    }

    @Test("sem gasto nenhum, a régua não divide por zero")
    func emptyScaleIsSafe() {
        let s = DayRack.Scale(peak: 0)
        #expect(s.max > 0)
        #expect(s.grades.isEmpty)
    }

    // MARK: - O vazio

    @Test("história vazia não desenha trinta colunas de nada")
    func emptyHistoryDrawsNothing() {
        #expect(History.empty.days.isEmpty)
        #expect(History.empty.hasAnyRecord == false)
        // E o Dashboard nasce assim: antes do primeiro scan, o app não afirma 30 dias de nada.
        #expect(Dashboard(lanes: []).history.days.isEmpty)
    }
}
