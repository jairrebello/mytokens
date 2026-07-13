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

    public init(_ snapshot: MyTokensCore.Snapshot, now: Date = Date()) {
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

        self.init(
            lanes: lanes,
            discovered: snapshot.statuses.filter(\.connected).map(\.provider),
            todayCostUSD: snapshot.statuses.reduce(into: Decimal(0)) { $0 += $1.today.costUSD }
        )
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
