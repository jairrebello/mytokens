// A tradução: o que o motor LEU vira o que a tela DESENHA.
//
// Os dois tipos existem de propósito e não são o mesmo:
//   MyTokensCore.Snapshot — uma leitura do mundo (eventos, statuses, custo, duração).
//   MyTokensUI.Dashboard  — o que está na tela (pistas, já com a certeza resolvida).
//
// Esta é a ÚNICA ponte entre eles. Se um dia a view precisar de um dado novo, ele entra
// aqui — nunca com a view indo buscar no disco.

import Foundation
import MyTokensCore

extension Dashboard {

    /// `isLive` = queimou nos últimos 5 min. É o que acende o calor (ember) na pista.
    /// Calor é ATIVIDADE, não perigo — não existe semáforo neste app.
    static let liveWindow: TimeInterval = 5 * 60

    /// `history` já pronta = o chamador a calculou FORA da MainActor. É o que o `AppModel`
    /// faz, e é o motivo de o parâmetro existir: a passada dos 30 dias custa ~45 ms sobre o
    /// disco real (68 mil eventos) e a MainActor não tem 45 ms pra dar a cada FSEvent.
    ///
    /// Quem passa `nil` (galeria, teste, preview) paga na hora — e tudo bem: lá o custo é
    /// uma vez, não trinta vezes por dia.
    /// `budgetUSD` é EXPLÍCITO, e não lido do `BudgetStore` aqui dentro.
    ///
    /// A tentação era o parâmetro nascer com `= BudgetStore.current` — daria a mesma tela com
    /// menos código nos dois chamadores. E deixaria esta ponte, que hoje é uma função pura do
    /// `Snapshot`, dependendo do UserDefaults da máquina: um teste rodando no Mac do Jair com
    /// um orçamento configurado veria uma pista a mais do que o mesmo teste no CI. Um teste
    /// que muda de resultado conforme a preferência de quem o roda não é um teste.
    /// Quem sabe do orçamento é o `AppModel` (e a galeria). Aqui, é só um número.
    public init(
        _ snapshot: MyTokensCore.Snapshot,
        now: Date = Date(),
        history: History? = nil,
        budgetUSD: Decimal? = nil
    ) {
        var lanes: [Lane] = []

        for status in snapshot.statuses {
            let isLive = status.lastEventAt.map { now.timeIntervalSince($0) < Self.liveWindow } ?? false

            if status.windows.isEmpty {
                // Sem janela = NÃO SABEMOS. A pista existe, tracejada e vazia, com o
                // convite pra conectar. O que ela NUNCA vira é um zero: zero é um
                // número, e número é uma afirmação. (regra 5 / UI-SPEC)
                lanes.append(.absent(
                    provider: status.provider,
                    label: Self.absentLabel(status.provider),
                    unit: status.provider == .cursor ? .usd : .percent
                ))
            } else {
                lanes.append(contentsOf: status.windows.map {
                    Lane(window: $0, provider: status.provider, isLive: isLive)
                })
            }
        }

        // O ORÇAMENTO entra por último — depois dos provedores, porque ele não é um deles.
        // Ele mede o MESMO dinheiro por outro denominador, e a pista é a mesma peça.
        // Se não há teto, não entra nada: a ausência do orçamento é a ausência da pista.
        if let budgetUSD,
           let budget = Lane.budget(
               spentUSD: Self.monthSpentUSD(snapshot.statuses),
               capUSD: budgetUSD,
               now: now,
               isLive: lanes.contains(where: \.isLive)
           ) {
            lanes.append(budget)
        }

        self.init(
            lanes: lanes,
            discovered: snapshot.statuses.filter(\.connected).map(\.provider),
            todayCostUSD: snapshot.statuses.reduce(into: Decimal(0)) { $0 += $1.today.costUSD },
            history: history ?? History(snapshot, now: now)
        )
    }

    /// O gasto do MÊS DO CALENDÁRIO, somando todos os provedores.
    ///
    /// ═══════════════════════════════════════════════════════════════════════════
    /// POR QUE `status.month` E NÃO A `History`, NEM UM `byMonth()`:
    ///
    ///   • a `History` é de 30 DIAS CORRIDOS. Ela é a peça mais nova da tela e a mais fácil
    ///     de agarrar por engano aqui — e seria errado: a fatura do usuário vira no dia 1,
    ///     não "trinta dias depois de hoje". No dia 3 de agosto, uma janela de 30 dias ainda
    ///     estaria contando julho inteiro, e o orçamento de agosto nasceria estourado.
    ///
    ///   • `snapshot.byMonth()` daria o mês certo (`Aggregator` usa `dateInterval(of: .month)`
    ///     com o `Calendar` local), mas custa uma varredura NOVA de todos os eventos — 68 mil
    ///     no disco do Jair, com uma chamada de `Calendar` por evento. A `History` já rejeitou
    ///     esse caminho por 150 ms; não vou reabri-lo por um único número.
    ///
    ///   • `ProviderStatus.month` JÁ É esse número. O `Aggregator.status` o calcula em toda
    ///     coleta, com `periodStart(.month, of: now, calendar: .current)` — o mês do
    ///     calendário LOCAL, que é exatamente o mês da fatura. Custo desta função: uma soma
    ///     de três `Decimal`. O dado certo já estava no contrato; faltava alguém pedir.
    ///
    /// O CURSOR NÃO ENTRA NESTA SOMA — e não porque eu o excluí, mas porque ele não tem o que
    /// somar. O `CursorCollector` não emite `UsageEvent` nenhum (o Cursor não grava uso no
    /// disco), então o `month` dele é zero por construção. O que ele publica é OUTRA coisa: a
    /// fração de um crédito INCLUÍDO no plano, no ciclo de cobrança DELE, que não é o mês do
    /// calendário. Enfiar isso aqui seria somar um dólar que já foi pago com um dólar que
    /// ainda vai ser — em duas janelas diferentes. A tela diz, por escrito, que ele fica de
    /// fora. E no dia em que um collector do Cursor emitir eventos com `costUSD`, esta soma
    /// os pega sozinha: nenhuma linha aqui menciona um provedor pelo nome.
    /// ═══════════════════════════════════════════════════════════════════════════
    public static func monthSpentUSD(_ statuses: [ProviderStatus]) -> Decimal {
        statuses.reduce(into: Decimal(0)) { $0 += $1.month.costUSD }
    }

    /// O rótulo da janela que o provedor TERIA se a gente soubesse. Não é chute sobre o
    /// número — é o nome da janela, que a gente sabe de documentação.
    private static func absentLabel(_ p: Provider) -> String {
        switch p {
        case .claudeCode: "5 h"
        case .codex: "7 d"
        case .cursor: "mês"
        }
    }
}
