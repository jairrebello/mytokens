//  LaneView.swift
//
//  A pista desenhada. Todo o sistema de honestidade visual sai daqui:
//  a textura da tinta é uma função do `Certainty`, e não existe outro caminho.
//
//  Camadas, de baixo pra cima:
//    trilho → ticks → faixa de incerteza → projeção → transbordo → TINTA →
//    costura → cursor do agora
//
//  O transbordo mora FORA do trilho de propósito (o trilho é o limite; o que
//  sai dele é o que você não tem), então nada aqui pode ser clipado.

import MyTokensCore
import SwiftUI

public struct LaneView: View {
    @Environment(\.palette) private var p

    public let lane: Lane
    /// 14 pt na janela · 8 pt no popover · 7 pt na janela secundária.
    /// Peso visual proporcional à chance de te atrapalhar.
    public var height: CGFloat = 14
    /// A agulha some no popover: economia de ruído em 340 px.
    public var showNeedle: Bool = true

    public init(lane: Lane, height: CGFloat = 14, showNeedle: Bool = true) {
        self.lane = lane
        self.height = height
        self.showNeedle = showNeedle
    }

    private var inkColor: Color { lane.isLive ? p.ember : p.emberCold }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (pct: Double) in w * min(max(pct, 0), 100) / 100 }

            ZStack(alignment: .leading) {
                trackBase
                if lane.certainty.hasInk { ticks(w: w) }
                band(x: x, w: w)
                projection(x: x, w: w)
                overrun(w: w)
                ink(x: x)
                nowCursor(w: w)
            }
            .frame(height: height)
            // A tinta ANDA até o valor novo — não pula. Mola crítica (damping 1.0):
            // um dado que passa do valor e volta é um dado que mentiu por 80 ms.
            // Sob Reduce Motion isto vira um ease-out de 200 ms: o movimento
            // encolhe, o valor final é exatamente o mesmo. Ver Design/ReduceMotion.
            .motion(.data, value: lane.used)
            .motion(.data, value: lane.nowFraction)
        }
        .frame(height: height)
        // ─────────────────────────────────────────────────────────────────────
        // A PISTA FALA. Ela é UM elemento acessível, e diz a leitura inteira —
        // provedor, janela, quanto queimou, com que certeza, quanto do tempo
        // passou, quando zera. `children: .ignore` porque tudo que mora dentro
        // dela é desenho: hachura, costura, cursor, transbordo. Nenhum retângulo
        // tem nome, e nenhum precisa ter — quem tem nome é a leitura.
        //
        // Os rótulos ao redor (título, número, procedência) são a MESMA
        // informação, escrita pro olho. Nas duas telas eles são escondidos do
        // VoiceOver: ouvir a mesma coisa três vezes é pior que não ouvi-la.
        // ─────────────────────────────────────────────────────────────────────
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lane.accessibilityReading())
    }

    // MARK: - Trilho
    //
    // AUSENTE: a pista EXISTE, tracejada, e vazia. O relógio continua correndo
    // por cima dela — falta a tinta, não a pista. Meia leitura honesta vale
    // mais que um zero mentiroso.

    @ViewBuilder
    private var trackBase: some View {
        if lane.certainty.hasInk {
            Rectangle()
                .fill(p.track)
                .frame(height: height)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(p.line).frame(height: 1).offset(y: 1)
                }
        } else {
            Rectangle()
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .foregroundStyle(p.line)
                .frame(height: height)
        }
    }

    /// Marcas de 25 / 50 / 75% da janela. Não são horas — são frações do eixo
    /// normalizado, senão não daria pra comparar 5 h com um mês em dólar.
    private func ticks(w: CGFloat) -> some View {
        ForEach([25.0, 50.0, 75.0], id: \.self) { t in
            Rectangle()
                .fill(p.canvas.opacity(0.55))
                .frame(width: 1, height: height)
                .offset(x: w * t / 100)
        }
    }

    // MARK: - Tinta
    //
    // O enum manda. Não há como uma view pintar sólido um dado derivado.

    @ViewBuilder
    private func ink(x: (Double) -> CGFloat) -> some View {
        switch lane.certainty {

        case .measured:
            // Sólida. Topo com CORTE RETO: a borda dura é a promessa.
            if let used = lane.used {
                Rectangle()
                    .fill(inkColor)
                    .frame(width: x(used), height: height)
                    .overlay(alignment: .trailing) { straightCap }
            }

        case .derived:
            // Reticulada de ponta a ponta. Topo PONTILHADO: a borda não é
            // uma promessa. Peso do número cai; til aparece. Três canais.
            if let used = lane.used {
                Hatch(color: inkColor)
                    .frame(width: x(used), height: height)
                    .overlay(alignment: .trailing) { dottedCap }
            }

        case .composite(let measuredUpTo, _):
            // A BARRA COMPOSTA. Fato até a costura, palpite depois dela.
            // Nenhuma peça nova: as duas texturas que já existiam, na ordem
            // certa, na mesma barra.
            if let used = lane.used {
                ZStack(alignment: .leading) {
                    // trecho medido — sólido, da origem até a costura
                    Rectangle()
                        .fill(inkColor)
                        .frame(width: x(measuredUpTo), height: height)

                    // trecho inferido do disco — reticulado, dali em diante.
                    // `phase` alinha o grid das listras com a origem da PISTA,
                    // não com a origem deste trecho: sem isso, a emenda inventa
                    // uma listra que não existe.
                    Hatch(color: inkColor, phase: x(measuredUpTo))
                        .frame(width: max(0, x(used) - x(measuredUpTo)), height: height)
                        .offset(x: x(measuredUpTo))

                    // A COSTURA. 1 px. É o carimbo de hora da última verdade.
                    // Sem ela a barra vira degradê, e degradê não diz ONDE o
                    // fato acaba e o palpite começa. A fronteira é a informação.
                    Rectangle()
                        .fill(p.ink1)
                        .frame(width: 1, height: height + 8)
                        .offset(x: x(measuredUpTo))
                }
                .frame(width: x(used), height: height, alignment: .leading)
                .overlay(alignment: .trailing) { dottedCap }
            }

        case .absent:
            // Sem tinta. E é isso. Nunca zero.
            EmptyView()
        }
    }

    /// Corte reto — 2 px sólidos. Só o MEDIDO ganha isto.
    private var straightCap: some View {
        Rectangle()
            .fill(lane.isLive ? p.ember : p.ink0)
            .frame(width: 2, height: height + 6)
            .shadow(color: lane.isLive ? p.emberGlow : .clear, radius: 5)
            .offset(x: 1)
    }

    /// Topo pontilhado — a ponta é inferida, e a borda diz isso sozinha.
    private var dottedCap: some View {
        Rectangle()
            .fill(p.ink1)
            .frame(width: 2, height: height + 6)
            .mask {
                VStack(spacing: 2) {
                    ForEach(0..<Int((height + 6) / 4) + 1, id: \.self) { _ in
                        Rectangle().frame(height: 2)
                    }
                }
            }
            .offset(x: 1)
    }

    // MARK: - Faixa de incerteza
    //
    // Só no derivado. É o que separa "borrão bonitinho" de estatística honesta:
    // vai do piso ao teto plausível, com dois ticks DUROS nas pontas.
    // Se o core não mandou lo/hi, não aparece nada — a view não inventa faixa.

    @ViewBuilder
    private func band(x: (Double) -> CGFloat, w: CGFloat) -> some View {
        if case .derived(let lo, let hi) = lane.certainty, let lo, let hi, hi > lo {
            let left = x(lo)
            let width = x(hi) - x(lo)
            DiagonalHatch(color: p.ink4)
                .frame(width: width, height: height + 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(p.ink4).frame(width: 1)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(p.ink4).frame(width: 1)
                }
                .opacity(0.5)
                .offset(x: left)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Projeção e transbordo
    //
    // A projeção estende a tinta até o fim da janela no ritmo dos últimos
    // 20 min. Só acima de 70% — abaixo disso é ruído: a resposta já é "pode ir".

    @ViewBuilder
    private func projection(x: (Double) -> CGFloat, w: CGFloat) -> some View {
        if let used = lane.used, let proj = lane.projected {
            let from = x(used)
            let to = x(min(proj, 100))
            if to > from {
                DiagonalHatch(color: p.ink4, gap: 3)
                    .frame(width: to - from, height: height - 2)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(p.ink3)
                            .frame(width: 1)
                            .mask {
                                VStack(spacing: 2) {
                                    ForEach(0..<Int(height / 4) + 1, id: \.self) { _ in
                                        Rectangle().frame(height: 2)
                                    }
                                }
                            }
                    }
                    .offset(x: from)
                    .allowsHitTesting(false)
            }
        }
    }

    /// O ESTOURO. Único lugar do app com croma alta, e o alarme é GEOMETRIA,
    /// não cor: a projeção rompe o trilho e o excedente é desenhado FORA dele.
    /// O trilho é o limite. O que sai dele é o que você não tem.
    ///
    /// Repare: a tinta sólida (o fato medido) NUNCA é recolorida por isto.
    /// Futuro nenhum merece ser desenhado como fato.
    @ViewBuilder
    private func overrun(w: CGFloat) -> some View {
        if let over = lane.overrun {
            let width = min(w * over / 100, w * 0.35)   // não come a tela inteira
            DiagonalHatch(color: p.emberHot, on: 2, gap: 3)
                .frame(width: width, height: height + 4)
                .overlay(alignment: .leading) {
                    Rectangle().fill(p.emberHot).frame(width: 2)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(p.emberHot).frame(width: 1)
                }
                .offset(x: w)
                .allowsHitTesting(false)
        }
    }

    // MARK: - O cursor do agora
    //
    // % do TEMPO decorrido na janela. O VÃO entre ele e a tinta é a resposta
    // do app — e é por isso que ele aparece até quando a tinta não existe.
    //
    // Ele NÃO se alinha entre as pistas: as janelas têm comprimentos diferentes.
    // Uma linha vertical atravessando as três implicaria que 5 h, 7 d e um mês
    // são a mesma coisa. Era bonito e era mentira.

    @ViewBuilder
    private func nowCursor(w: CGFloat) -> some View {
        if let now = lane.nowFraction {
            let ext: CGFloat = showNeedle ? 10 : 5
            Rectangle()
                .fill(p.ink2)
                .frame(width: 1, height: height + ext * 2)
                .overlay(alignment: .top) {
                    if showNeedle {
                        Rectangle()
                            .fill(p.ink2)
                            .frame(width: 5, height: 5)
                            .rotationEffect(.degrees(45))
                            .offset(y: -3)
                    }
                }
                .offset(x: w * min(max(now, 0), 1))
                .allowsHitTesting(false)
        }
    }
}
