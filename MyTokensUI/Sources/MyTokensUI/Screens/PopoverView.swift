//  PopoverView.swift
//
//  A TELA PRINCIPAL. É onde o app vive: 340 px na barra de menu, aberto 30x
//  por dia. Se a leitura falhar aqui, não importa o que a janela grande faça.
//
//  O que NÃO muda do popover pra janela: o reticulado e a costura. Se sumissem
//  aqui, o app mentiria justamente onde é mais olhado. A pista cai de 14 pt pra
//  8 pt e a agulha some — a honestidade, não.

import MyTokensCore
import SwiftUI

public struct PopoverView: View {
    @Environment(\.palette) private var p

    public let snapshot: Dashboard
    public var onOpenWindow: () -> Void = {}
    public var onConnect: (Provider) -> Void = { _ in }

    public init(
        snapshot: Dashboard,
        onOpenWindow: @escaping () -> Void = {},
        onConnect: @escaping (Provider) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.onOpenWindow = onOpenWindow
        self.onConnect = onConnect
    }

    private var verdict: Verdict { .of(snapshot) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            lanes
            footer
        }
        .frame(width: 340)
        .background(surface)
        .bancada()
    }

    // MARK: - Superfície
    //
    // O popover é a ÚNICA peça que de fato flutua sobre o desktop, então é a
    // única que ganha material nativo de verdade. O preto quente do Prisma
    // (oklch 60°) entra como TINTA por cima do material, não no lugar dele:
    // assim o app pega a vibrancy do macOS e continua sendo quente, em vez de
    // ser um retângulo opaco fingindo ser nativo.

    private var surface: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(p.surface.opacity(p.isDark ? 0.88 : 0.80))
        }
    }

    // MARK: - O veredito, em miniatura
    // A pergunta é a mesma da janela grande; só o espaço muda. Este é o texto
    // que o usuário lê 30x por dia — ele É o produto.

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: S.s2) {
                if snapshot.isEmpty { EmptyPulse() }
                Text(verdict.headline)
                    .font(.ui(T.xl, .semibold))
                    .tracking(-0.03 * T.xl)
                    .foregroundStyle(verdict.heat == .over ? p.emberHot : p.ink0)
                    .contentTransition(.opacity)
            }
            RichText(verdict.detail, base: p.ink2, strong: p.ink1)
                .font(.ui(T.xs))
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, S.s4)
        .padding(.top, S.s4)
        .padding(.bottom, S.s3)
    }

    // MARK: - As pistas

    private var lanes: some View {
        VStack(spacing: 0) {
            ForEach(snapshot.lanes) { lane in
                row(lane)
            }
        }
        .padding(.horizontal, S.s4)
        .padding(.bottom, S.s2)
    }

    private func row(_ lane: Lane) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(lane.title)
                    .font(.ui(T.sm, .medium))
                    .foregroundStyle(p.ink0)
                Spacer(minLength: S.s2)
                ValueText(lane: lane, size: T.md)
            }

            // 8 pt, sem agulha. O reticulado sobrevive a 8 px — se não
            // sobrevivesse, o sistema inteiro cairia.
            LaneView(lane: lane, height: 8, showNeedle: false)
                .padding(.top, 5)
                .padding(.bottom, 3)

            HStack(spacing: S.s2) {
                Text(footnote(lane))
                    .font(.num(T.micro))
                    .tracking(0.03 * T.micro)
                    .foregroundStyle(p.ink3)
                Spacer(minLength: S.s1)
                if lane.certainty.hasInk {
                    Text(lane.displayReset ?? "")
                        .font(.num(T.micro))
                        .tracking(0.03 * T.micro)
                        .foregroundStyle(p.ink3)
                } else {
                    // Sem dado → o convite. Não é modal, não é badge vermelho,
                    // não é tour: fica no lugar onde a dor está, e some sozinho
                    // quando resolvido.
                    Button("conectar") { onConnect(lane.provider) }
                        .buttonStyle(.plain)
                        .font(.ui(T.xs))
                        .foregroundStyle(p.ember)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(p.ember.opacity(0.35)).frame(height: 1).offset(y: 2)
                        }
                }
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            Rectangle().fill(p.lineSoft).frame(height: 1)
        }
    }

    /// O rodapé de cada pista carrega a procedência em PALAVRA — o segundo
    /// canal. A textura já disse; isto confirma pra quem parou pra ler.
    private func footnote(_ lane: Lane) -> String {
        var s = lane.certainty.provenanceLabel()
        if case .absent = lane.certainty, lane.unit == .usd,
           let cap = lane.capUSD {
            s += " · US$ \(Int((cap as NSDecimalNumber).doubleValue)) de crédito"
        }
        if let range = lane.displayRange {
            s += " · \(range)"
        }
        return s
    }

    // MARK: - Rodapé: a procedência é permanente

    private var footer: some View {
        HStack {
            ProvenanceLegend()
            Spacer()
            Button(action: onOpenWindow) {
                HStack(spacing: 4) {
                    Text("ABRIR")
                        .font(.ui(T.micro, .medium))
                        .tracking(0.06 * T.micro)
                    Image(systemName: "command")
                        .font(.system(size: 8, weight: .medium))
                    Image(systemName: "return")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(p.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, S.s4)
        .padding(.vertical, 9)
        .background(p.surfaceHi.opacity(p.isDark ? 0.7 : 0.9))
        .overlay(alignment: .top) {
            Rectangle().fill(p.line).frame(height: 1)
        }
    }
}

// MARK: - O pulso do estado vazio
//
// Instrumento LIGADO, esperando. Não é spinner (spinner diz "estou travado"),
// é um sinal de vida a 2,4 s — o mesmo ritmo de uma respiração calma.

struct EmptyPulse: View {
    @Environment(\.palette) private var p
    @State private var on = false

    var body: some View {
        Circle()
            .fill(p.ember)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Markup mínimo
//
// A frase do veredito precisa de UM nível de ênfase (o fato dentro da frase).
// AttributedString resolve sem trazer um parser de markdown pra dentro da view.

struct RichText: View {
    let raw: String
    let base: Color
    let strong: Color

    init(_ raw: String, base: Color, strong: Color) {
        self.raw = raw
        self.base = base
        self.strong = strong
    }

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        var isStrong = false
        for chunk in raw.components(separatedBy: "**") {
            var piece = AttributedString(chunk)
            piece.foregroundColor = isStrong ? strong : base
            if isStrong { piece.font = .ui(T.xs, .medium) }
            out.append(piece)
            isStrong.toggle()
        }
        return out
    }
}
