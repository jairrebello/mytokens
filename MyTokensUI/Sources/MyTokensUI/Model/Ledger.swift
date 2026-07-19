//  Ledger.swift
//
//  O LIVRO-RAZÃO AGRUPADO (UI-SPEC §11). A partir daqui as janelas têm DONOS:
//  cada grupo é uma assinatura — "Claude", "Codex" — e o orçamento, que não é
//  assinatura de ninguém, vira o próprio grupo, porque na janela grande todo
//  mundo tem header e uma linha órfã embaixo de headers leria como erro.
//
//  O HERÓI FICA FORA. A janela mais apertada continua sozinha no topo — o
//  agrupamento organiza o livro-razão; o veredito não é dele. A linha do herói
//  não se repete no grupo, e grupo que ficaria vazio some.
//
//  A chave de VERDADE do spec é a assinatura (conta + plano). O contrato ainda
//  não carrega `account`/`planLabel` — hoje uma conta por provedor é o que
//  existe, então o provedor É a assinatura. Quando o core entregar os campos,
//  só a chave deste arquivo muda; view nenhuma aprende nada novo.

import MyTokensCore
import Foundation

/// Um grupo do livro-razão: a assinatura e as janelas dela, já ordenadas.
public struct LedgerGroup: Identifiable, Sendable, Equatable {
    public let id: String
    /// "Claude" · "Codex" · "Orçamento". A view põe em caixa alta — o dado não grita.
    public let title: String
    /// A procedência IÇADA pro header — só quando TODAS as linhas do grupo
    /// compartilham fonte e carimbo. Senão `nil`, e cada linha diz a sua.
    /// Içar metadado repetido limpa a linha; içar metadado divergente mente.
    public let hoistedProvenance: String?
    public let lanes: [Lane]

    /// Só linhas sem tinta (o Cursor sem credencial). A janela grande mostra o
    /// grupo com a linha "conectar"; o popover o esconde — lá o Cursor ausente
    /// é ressalva do veredito, não grupo.
    public var isAllAbsent: Bool {
        lanes.allSatisfy { !$0.certainty.hasInk }
    }
}

extension Lane {
    /// O rótulo da linha DENTRO de um grupo: o dono já está no header, então a
    /// linha diz só a janela — "5 h", "Semana", "Semana · Fable".
    ///
    /// Janela primeiro, modelo como qualificador depois do middot. Nunca o
    /// modelo sozinho: "Fable" como nome de linha leria como provedor (§11).
    /// O guard contra duplicar existe porque o label é do provedor: se um dia a
    /// fonte escrever "Semana · Fable" no label, repetir aqui viraria gagueira.
    public var groupedTitle: String {
        let base = windowLabel
        guard let scope = modelScope, !scope.isEmpty,
              !base.localizedCaseInsensitiveContains(scope) else { return base }
        return "\(base) · \(scope.capitalized)"
    }
}

extension Dashboard {
    /// O livro-razão: grupos por assinatura, SEM a linha do herói.
    ///
    /// Ordenação (§11): grupos pela janela mais apertada que contêm; dentro do
    /// grupo, por folga. Linha sem folga calculável (a ausente) vai pro fim —
    /// ela não compete por urgência porque não afirma nada.
    public var ledger: [LedgerGroup] {
        let heroID = tightest?.id
        let rest = lanes.filter { $0.id != heroID }
        guard !rest.isEmpty else { return [] }

        // Agrupa preservando a chave. Dictionary(grouping:) embaralharia a
        // ordem dos grupos entre refreshes — aqui a ordem final é recalculada,
        // mas a estabilidade do conteúdo importa pros diffs da view.
        var keys: [String] = []
        var byKey: [String: [Lane]] = [:]
        for lane in rest {
            let key = Self.groupKey(lane)
            if byKey[key] == nil { keys.append(key) }
            byKey[key, default: []].append(lane)
        }

        var groups: [LedgerGroup] = keys.map { key in
            let lanes = byKey[key]!.sorted {
                ($0.slackPoints ?? .infinity) < ($1.slackPoints ?? .infinity)
            }
            return LedgerGroup(
                id: key,
                title: Self.groupTitle(lanes[0]),
                hoistedProvenance: Self.hoist(lanes),
                lanes: lanes
            )
        }

        groups.sort {
            (Self.tightestSlack($0)) < (Self.tightestSlack($1))
        }
        return groups
    }

    /// O popover só ganha headers quando ≥ 2 ASSINATURAS têm linha no
    /// livro-razão (§11) — e assinatura aqui exclui o orçamento e os grupos
    /// inteiramente ausentes, que lá nem aparecem. Uma assinatura só → lista
    /// lisa: um header órfão é um rótulo que o usuário lê pra não ganhar nada.
    public var popoverGroups: [LedgerGroup]? {
        let visible = ledger.filter { !$0.isAllAbsent }
        let subscriptions = visible.filter { $0.id != "budget" }
        guard subscriptions.count >= 2 else { return nil }
        return visible
    }

    // MARK: - As regras, nomeadas

    private static func groupKey(_ lane: Lane) -> String {
        switch lane.owner {
        case .provider(let p): p.rawValue
        case .budget: "budget"
        }
    }

    private static func groupTitle(_ lane: Lane) -> String {
        lane.ownerName
    }

    /// A folga que ORDENA o grupo: a da janela mais apertada que ele contém.
    private static func tightestSlack(_ g: LedgerGroup) -> Double {
        g.lanes.compactMap(\.slackPoints).min() ?? .infinity
    }

    /// `asOf` sobe pro header SÓ quando todas as linhas compartilham fonte e
    /// carimbo — o rótulo de procedência já é exatamente (fonte + carimbo), então
    /// a igualdade dele é a igualdade que o spec pede. Linha sem tinta não iça:
    /// "sem dado local" no header afirmaria sobre o grupo o que é de uma linha.
    private static func hoist(_ lanes: [Lane]) -> String? {
        guard lanes.count > 1, lanes.allSatisfy({ $0.certainty.hasInk }) else { return nil }
        let labels = Set(lanes.map { $0.provenanceNote })
        return labels.count == 1 ? labels.first : nil
    }
}
