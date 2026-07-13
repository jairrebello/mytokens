//  MainWindowView.swift
//
//  A janela expandida. 960 pt. Mesmo sistema, mais ar — NÃO é uma tela nova.
//  O que ela ganha em relação ao popover: a agulha do agora, a régua do eixo,
//  a linha do relógio (folga / reset / ritmo) e o custo do dia.
//  O que ela NÃO ganha: nenhuma textura nova, nenhuma cor nova.
//
//  Densidade sem sujeira: hierarquia por tipografia e espaço, nunca por
//  caixa-dentro-de-caixa. Repare que não existe um único card aqui.

import MyTokensCore
import SwiftUI

public struct MainWindowView: View {
    @Environment(\.palette) private var p

    public let snapshot: Dashboard
    public var onConnect: (Provider) -> Void = { _ in }
    public var theme: Theme = .bancada

    public init(
        snapshot: Dashboard,
        onConnect: @escaping (Provider) -> Void = { _ in },
        theme: Theme = .bancada
    ) {
        self.snapshot = snapshot
        self.onConnect = onConnect
        self.theme = theme
    }

    private var verdict: Verdict { .of(snapshot) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            verdictBlock
            Rectangle().fill(p.lineSoft).frame(height: 1)
            bench
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 960, alignment: .leading)
        .background(p.canvas)
        .theme(theme)
    }

    // MARK: - O veredito
    //
    // 54 pt, e SÓ ele. Se o usuário precisou ler um rótulo pra entender,
    // falhamos. A resposta vem antes de qualquer pista.

    private var verdictBlock: some View {
        VStack(alignment: .leading, spacing: S.s3) {
            HStack(spacing: S.s3) {
                if snapshot.isEmpty { EmptyPulse() }
                Text(verdict.headline)
                    .font(.ui(T.xxxl, .semibold))
                    .tracking(-0.035 * T.xxxl)
                    .foregroundStyle(verdict.heat == .over ? p.emberHot : p.ink0)
            }

            RichText(verdict.detail, base: p.ink2, strong: p.ink0)
                .font(.ui(T.md))
                .lineSpacing(4)
                .frame(maxWidth: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let t = snapshot.tightest, !snapshot.isEmpty {
                clockline(t)
                    .padding(.top, S.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(S.s6)
    }

    /// TEMPO > TOKEN. Folga em pontos, hora do reset, ritmo relativo à janela.
    /// Nenhum destes é um token — e é de propósito: token é a unidade da máquina.
    private func clockline(_ t: Lane) -> some View {
        HStack(spacing: S.s4) {
            if let slack = t.slackLabel {
                metric("Folga na mais apertada", slack, hot: (t.slackPoints ?? 0) < 0)
            }
            if let reset = t.resetsAt {
                metric("Zera", Verdict.hm(reset), hot: false)
            }
            if let pace = t.paceLabel {
                metric("Ritmo", pace, hot: false)
            }
        }
    }

    private func metric(_ label: String, _ value: String, hot: Bool) -> some View {
        HStack(spacing: S.s2) {
            Text(label.uppercased())
                .font(.ui(T.micro, .medium))
                .tracking(0.09 * T.micro)
                .foregroundStyle(p.ink3)
            Text(value)
                .font(.num(T.lg, hot ? .semibold : .regular))
                .foregroundStyle(hot ? p.emberHot : p.ink1)
        }
        .padding(.trailing, S.s3)
    }

    // MARK: - A bancada
    // grid: 170 · 1fr · 150

    private var bench: some View {
        VStack(alignment: .leading, spacing: 0) {
            axisHeader
            ForEach(snapshot.lanes) { lane in
                benchRow(lane)
            }
        }
        .padding(.horizontal, S.s6)
        .padding(.vertical, S.s5)
    }

    /// A régua do eixo. Ela diz, sem uma palavra, que o eixo é NORMALIZADO:
    /// "50% DA JANELA", não "2h30". É o que autoriza 5 h, 7 d e US$ 20/mês a
    /// dividirem a mesma tela sem que isso seja mentira.
    private var axisHeader: some View {
        HStack(spacing: S.s4) {
            Text("JANELA")
                .font(.ui(T.micro, .medium))
                .tracking(0.09 * T.micro)
                .foregroundStyle(p.ink3)
                .frame(width: 170, alignment: .leading)

            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    ForEach([(0.0, "0%"), (0.5, "50% da janela"), (1.0, "100%")], id: \.0) { pos, label in
                        Text(label)
                            .font(.ui(T.micro))
                            .tracking(0.05 * T.micro)
                            .foregroundStyle(p.ink4)
                            .fixedSize()
                            .alignmentGuide(.leading) { d in
                                pos == 1.0 ? d.width : (pos == 0.5 ? d.width / 2 : 0)
                            }
                            .offset(x: geo.size.width * pos)
                    }
                }
                .frame(height: 12)
            }

            Text("FONTE")
                .font(.ui(T.micro, .medium))
                .tracking(0.09 * T.micro)
                .foregroundStyle(p.ink3)
                .frame(width: Self.valueColumn, alignment: .trailing)
        }
        .padding(.bottom, S.s4)
    }

    /// A coluna do número, larga o bastante pro PIOR caso: "US$ 18,40 / 20" em 26 pt mono.
    /// Fixa (não por-linha) pra as pistas alinharem — começam e terminam no mesmo x. A
    /// janela tem 960 px; os 40 px a mais saem da pista, que tem folga de sobra.
    static let valueColumn: CGFloat = 190

    private func benchRow(_ lane: Lane) -> some View {
        HStack(alignment: .center, spacing: S.s4) {
            // quem
            VStack(alignment: .leading, spacing: 2) {
                Text(lane.provider.displayName)
                    .font(.ui(T.md, .medium))
                    .foregroundStyle(p.ink0)
                Text(lane.windowLabel)
                    .font(.ui(T.xs))
                    .foregroundStyle(p.ink3)
            }
            .frame(width: 170, alignment: .leading)

            // a pista — 14 pt, com agulha
            LaneView(lane: lane, height: 14, showNeedle: true)
                .frame(maxWidth: .infinity)

            // o número + a procedência, em palavra
            VStack(alignment: .trailing, spacing: 3) {
                ValueText(lane: lane, size: T.xl)
                HStack(spacing: 5) {
                    RangeText(lane: lane)
                    if lane.certainty.hasInk {
                        Text(lane.certainty.provenanceLabel())
                            .font(.ui(T.micro))
                            .tracking(0.05 * T.micro)
                            .foregroundStyle(p.ink3)
                    } else {
                        Button("conectar") { onConnect(lane.provider) }
                            .buttonStyle(.plain)
                            .font(.ui(T.xs))
                            .foregroundStyle(p.ember)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(p.ember.opacity(0.35))
                                    .frame(height: 1).offset(y: 2)
                            }
                    }
                }
            }
            .frame(width: Self.valueColumn, alignment: .trailing)
        }
        .padding(.vertical, S.s5)
        .overlay(alignment: .top) {
            Rectangle().fill(p.lineSoft).frame(height: 1)
        }
    }

    // MARK: - Rodapé
    // A procedência é permanente. Contrato de honestidade se imprime na peça.

    private var footer: some View {
        HStack {
            ProvenanceLegend(present: snapshot.legendKinds)
            Spacer()
            HStack(spacing: S.s2) {
                Text("HOJE")
                    .font(.ui(T.micro, .medium))
                    .tracking(0.09 * T.micro)
                    .foregroundStyle(p.ink3)
                // Custo é a ÚNICA coisa que a soma de token pode virar.
                // Ela NUNCA vira "quanto sobra" — ninguém publica o teto em token.
                Text(String(format: "US$ %.2f", (snapshot.todayCostUSD as NSDecimalNumber).doubleValue)
                        .replacingOccurrences(of: ".", with: ","))
                    .font(.num(T.sm))
                    .foregroundStyle(p.ink1)
            }
        }
        .padding(.horizontal, S.s6)
        .padding(.vertical, S.s3)
        .background(p.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(p.line).frame(height: 1)
        }
    }
}
