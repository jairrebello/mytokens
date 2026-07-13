//  Certainty.swift
//
//  ═══════════════════════════════════════════════════════════════════════
//  A ESPINHA DO PRODUTO. Se este arquivo estiver errado, o app MENTE.
//
//  As três fontes não são três valores — são três NÍVEIS DE CERTEZA sobre
//  um valor. E nenhuma das três publica o denominador em token: as três
//  expõem fração de uma cota que mora no servidor.
//
//  A regra: medido, derivado e ausente são VISUALMENTE DIFERENTES na tela.
//  Aqui a certeza vira TIPO, não um `if` espalhado por cinco views. Uma view
//  não consegue desenhar tinta sólida num dado derivado porque não existe
//  caminho de código que permita isso: a textura sai daqui, do enum.
//
//  Dois canais, SEMPRE — textura (o olho de raspão) e til/palavra (o olho que
//  para). Um canal só é ponto único de falha de compreensão.
//  ═══════════════════════════════════════════════════════════════════════

import MyTokensCore
import Foundation

public enum Certainty: Sendable, Equatable {

    /// O provedor NOS DEU o número, e ele está fresco.
    /// Tinta SÓLIDA, topo com corte reto, peso 600, SEM SELO.
    /// Medido é o caso NÃO-MARCADO: a honestidade não pode custar enfeite.
    /// Quem paga o preço visual é a incerteza, que é o que ela merece.
    case measured(at: Date?)

    /// Medido até `measuredUpTo`, inferido do disco daí em diante.
    /// O hook `statusLine` só dispara ENQUANTO o Claude Code roda — logo todo
    /// valor medido tem IDADE. Se a verdade chegou às 14:35 e o disco registrou
    /// gasto depois, o app sabe duas coisas com certezas diferentes, e elas
    /// moram na MESMA barra, separadas pela COSTURA.
    ///
    /// Nenhuma peça nova foi inventada: são as duas texturas que já existiam,
    /// na ordem certa. A fronteira é a informação.
    case composite(measuredUpTo: Double, at: Date)

    /// NÓS calculamos. O teto do plano não é publicado por ninguém.
    /// Tinta RETICULADA, topo pontilhado, peso 500, til no número, faixa de
    /// incerteza (piso–teto). Sem a faixa, o reticulado é só um borrão bonito.
    /// `lo`/`hi` são nil quando o core ainda não os manda — aí a view degrada
    /// com honestidade: mantém o reticulado e o til, e omite a faixa. Nunca
    /// inventa uma faixa pra ficar bonito.
    case derived(lo: Double?, hi: Double?)

    /// Não sabemos. SEM TINTA — a pista existe, tracejada, e vazia.
    /// O número é `—`. NUNCA `0`: zero é um número, e número é uma afirmação.
    case absent

    /// Traduz uma janela do contrato na certeza que ela realmente carrega.
    /// Este é o ÚNICO lugar do app que decide isso.
    public static func of(_ w: LimitWindow) -> Certainty {
        switch w.source {
        case .derived:
            return .derived(lo: w.lo, hi: w.hi)

        case .measured:
            // Medido mas com gasto no disco depois da última leitura → composta.
            if let at = w.measuredAt,
               let measured = w.measuredPercent,
               w.usedPercent - measured > 0.5 {   // meio ponto: abaixo disso a
                                                  // costura não caberia num px
                return .composite(measuredUpTo: measured, at: at)
            }
            return .measured(at: w.measuredAt)
        }
    }

    /// Ausente é a falta da janela inteira, não uma janela com zero.
    /// `windows` vazio no ProviderStatus = "não sabemos" (contrato-dados).
    public var hasInk: Bool {
        if case .absent = self { return false }
        return true
    }

    /// O til é o eco tipográfico do reticulado: mesma mensagem, outro canal.
    public var isApproximate: Bool {
        switch self {
        case .derived: true
        case .composite: true   // a PONTA é palpite, logo o número é aproximado
        case .measured, .absent: false
        }
    }

    /// A palavra do rodapé de cada pista. Medido não ganha selo — ganha silêncio.
    public func provenanceLabel(now: Date = Date()) -> String {
        switch self {
        case .measured(let at):
            guard let at else { return "medido" }
            return "medido \(Self.hm(at))"
        case .composite(_, let at):
            return "medido \(Self.hm(at)) · + do disco"
        case .derived:
            return "estimado"
        case .absent:
            return "sem dado local"
        }
    }

    private static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Peso como tensão
//
// A tensão sobe por DENSIDADE E PESO, não por matiz. `norte-ux` #4 proíbe
// semáforo; isto é literalmente a alternativa, e não gasta uma gota de cor.

public enum Heat: Int, Sendable, Comparable {
    case idle = 0    //   0–25%
    case low = 1     //  25–50%
    case mid = 2     //  50–75%
    case high = 3    //  75–100%
    case over = 4    //  >100%  — o ÚNICO que ganha croma

    public init(percent: Double) {
        switch percent {
        case ..<25: self = .idle
        case ..<50: self = .low
        case ..<75: self = .mid
        case ..<100: self = .high
        default: self = .over
        }
    }

    public static func < (a: Heat, b: Heat) -> Bool { a.rawValue < b.rawValue }
}
