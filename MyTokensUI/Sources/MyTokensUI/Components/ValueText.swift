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
                .font(.num(size, weight))
                .foregroundStyle(color)
                .tracking(tracking)
                .contentTransition(.numericText())   // o número TROCA, não pisca

            if let suffix = lane.displayUnitSuffix {
                // "US$ 6,40 / 20" — o Cursor mede em dólar de compute, não em %.
                // Rotular só "32%" seria a mesma mentira que o app passou o dia
                // matando: 32% de um crédito em US$ e 32% de uma cota opaca não
                // são a mesma coisa.
                Text(suffix)
                    .font(.num(size * 0.62, .regular))
                    .foregroundStyle(p.ink3)
            }
        }
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
                .font(.num(T.xs, .regular))
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
    public init() {}

    public var body: some View {
        HStack(spacing: S.s3) {
            item("Medido") {
                Rectangle().fill(p.ink2).frame(width: 16, height: 7)
            }
            item("Inferido") {
                Hatch(color: p.ink2).frame(width: 16, height: 7)
            }
            item("Sem dado") {
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(p.line)
                    .frame(width: 16, height: 7)
            }
        }
    }

    private func item(_ label: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(label.uppercased())
                .font(.ui(T.micro, .medium))
                .tracking(0.05 * T.micro)
                .foregroundStyle(p.ink3)
        }
    }
}
