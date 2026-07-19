//  ValueText.swift
//
//  O SEGUNDO CANAL da honestidade. A textura fala com o olho de raspão;
//  isto fala com o olho que para. Um canal só é ponto único de falha.
//
//  Peso como tensão (UI-SPEC §4): quanto mais perto do teto, mais PESADO e mais
//  CLARO o número. A tensão sobe por gramatura, não por matiz — e não gasta uma
//  gota de cor. Só o estouro (>100%) ganha croma, e ganha porque merece.

import MyTokensCore
import SwiftUI

public struct ValueText: View {
    @Environment(\.palette) private var p

    public let lane: Lane
    public var size: CGFloat = T.xl

    public init(lane: Lane, size: CGFloat = T.xl) {
        self.lane = lane
        self.size = size
    }

    private var weight: Font.Weight {
        guard lane.certainty.hasInk else { return .regular }
        // Derivado pesa MENOS que medido no mesmo valor. A incerteza paga o
        // preço visual — inclusive em gramatura.
        if case .derived = lane.certainty {
            return lane.heat >= .high ? .medium : .regular
        }
        switch lane.heat {
        case .idle: return .regular
        case .low:  return .medium
        case .mid:  return .semibold
        case .high, .over: return .bold
        }
    }

    private var color: Color {
        guard lane.certainty.hasInk else { return p.ink4 }   // o `—` é fantasma
        switch lane.heat {
        case .idle: return p.ink2
        case .low:  return p.ink1
        case .mid:  return p.ink0
        case .high: return p.ink0
        case .over: return p.emberHot   // a ÚNICA vez que o número tem matiz
        }
    }

    private var tracking: CGFloat {
        lane.heat >= .high ? -0.03 * size : -0.02 * size
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(lane.displayValue)
                .font(p.num(size, weight))
                .foregroundStyle(color)
                .tracking(tracking)
                .numericValueTransition()   // o número TROCA, não pisca — e não rola
                                            // os dígitos quando o sistema pede calma

            if let suffix = lane.displayUnitSuffix {
                // "US$ 6,40 / 20" — o Cursor mede em dólar de compute, não em %.
                // Rotular só "32%" seria a mesma mentira que o app passou o dia
                // matando: 32% de um crédito em US$ e 32% de uma cota opaca não
                // são a mesma coisa.
                Text(suffix)
                    .font(p.num(size * 0.62, .regular))
                    .foregroundStyle(p.ink3)
            }
        }
        // O valor é o DADO — ele NUNCA trunca. "US$ 3,29" é mais largo que "36%", e sem
        // isto o layout cortava em "US$ 3..." (visto no tema Terminal). Quem cede largura
        // é o título da pista, não o número medido. Um dado com reticências é um dado que
        // mentiu por omissão.
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A faixa `41–68` que acompanha o til. Terceiro canal, e só no derivado.
public struct RangeText: View {
    @Environment(\.palette) private var p
    public let lane: Lane
    public init(lane: Lane) { self.lane = lane }

    public var body: some View {
        if let r = lane.displayRange {
            Text(r)
                .font(p.num(T.xs, .regular))
                .foregroundStyle(p.ink3)
        }
    }
}

// MARK: - Rodapé de procedência
//
// A legenda medido/inferido/ausente é PERMANENTE, no rodapé das duas telas.
// Não é tooltip, não é modal, não é "saiba mais". É o rodapé de um instrumento
// de medição: contrato de honestidade se imprime na peça.

public struct ProvenanceLegend: View {
    @Environment(\.palette) private var p

    /// As texturas que a tela ESTÁ usando agora. A legenda explica o que está à vista, não
    /// um catálogo — se não há nada inferido na tela, "INFERIDO" só rouba largura e ensina
    /// a ler uma textura que ninguém está vendo. `nil` = mostra as três (compat/preview).
    private let present: Set<LegendKind>?

    public init() { self.present = nil }
    public init(present: Set<LegendKind>) { self.present = present }

    private func shows(_ k: LegendKind) -> Bool { present?.contains(k) ?? true }

    public var body: some View {
        HStack(spacing: S.s3) {
            if shows(.measured) {
                item("Medido") { Rectangle().fill(p.ink2).frame(width: 16, height: 7) }
            }
            if shows(.inferred) {
                item("Inferido") { Hatch(color: p.ink2).frame(width: 16, height: 7) }
            }
            if shows(.absent) {
                item("Sem dado") {
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundStyle(p.line)
                        .frame(width: 16, height: 7)
                }
            }
        }
        // A legenda é uma peça só, e ela é o CONTRATO — não uma fileira de
        // retângulos anônimos. Pro VoiceOver, a mesma promessa em uma frase: cada
        // pista já disse "medido" ou "estimado", isto explica que a distinção é
        // deliberada e permanente.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "Legenda das texturas na tela: medido, inferido." Só as que estão à vista —
    /// ensinar a ler uma textura que ninguém está mostrando é ruído, no olho e no ouvido.
    private var spoken: String {
        var kinds: [String] = []
        if shows(.measured) { kinds.append("medido") }
        if shows(.inferred) { kinds.append("inferido") }
        if shows(.absent)   { kinds.append("sem dado") }
        guard !kinds.isEmpty else { return "" }
        return "Legenda das texturas na tela: \(kinds.joined(separator: ", "))."
    }

    private func item(_ label: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 5) {
            swatch()
                .accessibilityHidden(true)   // a amostra da textura é puro ornamento
            Text(label.uppercased())
                .font(p.ui(T.micro, .medium))
                .tracking(0.05 * T.micro)
                .foregroundStyle(p.ink3)
        }
    }
}

/// As três texturas que a legenda nomeia. Uma pista se encaixa em exatamente uma.
public enum LegendKind: Sendable { case measured, inferred, absent }

extension Dashboard {
    /// Quais texturas de fato aparecem nas pistas de agora. É o que a legenda mostra.
    public var legendKinds: Set<LegendKind> {
        var out: Set<LegendKind> = []
        for lane in lanes {
            switch lane.certainty {
            case .measured:            out.insert(.measured)
            case .derived, .composite: out.insert(.inferred)
            case .absent:              out.insert(.absent)
            }
        }
        return out
    }
}
