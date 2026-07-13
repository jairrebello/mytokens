//  DayRack.swift
//
//  O TRILHO DOS 30 DIAS. É a mesma gramática da pista, virada de lado: trilho, tinta,
//  graduação, hachura. Nenhuma peça nova.
//
//  ═══════════════════════════════════════════════════════════════════════════════
//  O QUE ELE NÃO TEM — e por que a ausência É o desenho
//
//  Ele NÃO tem vaso. Não existe um retângulo de fundo atrás da coluna do dia esperando
//  encher. A pista tem trilho porque a janela do Claude TEM TETO: o trilho é o teto, e a
//  tinta é a fração dele. Gasto em dólar não tem teto nenhum — ninguém publica um. Desenhar
//  uma coluna que enche seria inventar um limite pra ela transbordar, que é exatamente o
//  pecado que o UI-SPEC lista como morte súbita ("soma de token apresentada como quanto
//  sobra"). Então o eixo é ABERTO em cima: a régua acaba, o dado não.
//
//  A régua fica com uma casa de folga acima do pior dia, SEMPRE. Nenhuma coluna encosta no
//  topo — encostar seria dizer "cheio", e não existe cheio aqui.
//  ═══════════════════════════════════════════════════════════════════════════════
//
//  As três leituras de uma coluna:
//
//    tinta reticulada   → gasto ESTIMADO daquele dia (custo é derivado do pricing.json:
//                         a textura é a mesma "inferido" das pistas, e é a mesma promessa)
//    nada acima da base → dia com registro e SEM gasto. Zero medido é um fato.
//    hachura diagonal   → dia SEM REGISTRO. Não é zero: é a faixa inteira do desconhecido,
//                         a mesma diagonal que a pista usa pra dizer "isto não é fato".
//
//  A diferença entre as duas últimas é o produto: "não gastei" e "não sei" não podem ter
//  o mesmo pixel. O disco do Claude é mutável — dia velho perde sessão — então "não sei"
//  acontece de verdade, e acontece pra trás.

import SwiftUI

public struct DayRack: View {
    @Environment(\.palette) private var p

    public let history: History
    /// A altura útil da tinta. A régua vive dentro dela.
    public var height: CGFloat = 68

    /// A coluna sob o cursor. Só isto — hover é chrome, não dado: some quando o
    /// mouse sai, e a leitura volta a ser a do período inteiro.
    @State private var hovered: Int?

    public init(history: History, height: CGFloat = 68) {
        self.history = history
        self.height = height
    }

    /// A calha da régua, à esquerda. É onde os `US$` da graduação moram — fora do dado,
    /// como no eixo de um registrador de papel.
    private static let gutter: CGFloat = 62
    private static let gap: CGFloat = 4

    private var days: [History.Day] { history.days }
    private var scale: Scale { Scale(peak: peakValue) }

    private var peakValue: Double {
        (history.peak?.costUSD as NSDecimalNumber?)?.doubleValue ?? 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: S.s2) {
            header
            strip
            axis
        }
        // UMA fala pro trilho inteiro. Trinta paradas do VoiceOver, uma por coluna, seriam
        // trinta números sem hierarquia — o oposto da leitura de relance que a coluna dá pro
        // olho. O que o ouvido precisa é o mesmo que o olho tira em meio segundo: quanto foi
        // no total, qual foi o pior dia, e quantos dias o disco não prova.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: - O cabeçalho e a leitura
    //
    // O visor à direita é o instrumento: sem hover, ele mostra o PERÍODO; com hover, o DIA.
    // Não é tooltip — tooltip flutua, aparece atrasado e some. Este é um visor com endereço
    // fixo, e ele nunca fica vazio.

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ÚLTIMOS 30 DIAS")
                .font(.ui(T.micro, .medium))
                .tracking(0.09 * T.micro)
                .foregroundStyle(p.ink3)

            Spacer(minLength: S.s4)

            readout
        }
    }

    @ViewBuilder
    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.s2) {
            if let i = hovered, days.indices.contains(i) {
                Text(Self.dayLabel(days[i].start, isToday: i == days.count - 1))
                    .font(.ui(T.xs))
                    .foregroundStyle(p.ink3)
                if let c = days[i].costUSD {
                    Text(Verdict.usd(c))
                        .font(.num(T.lg, .medium))
                        .foregroundStyle(p.ink0)
                } else {
                    // O dia sem registro NÃO vira "US$ 0,00" nem no visor. Ele vira a
                    // mesma palavra que a pista ausente usa há três telas.
                    Text("sem registro")
                        .font(.ui(T.sm))
                        .foregroundStyle(p.ink4)
                }
            } else {
                Text("SOMA")
                    .font(.ui(T.micro, .medium))
                    .tracking(0.09 * T.micro)
                    .foregroundStyle(p.ink3)
                // Sem UM dia de registro no período, a soma não é `US$ 0,00` — é `—`.
                // Zero seria afirmar que você não gastou nada em 30 dias, e o que a gente
                // tem é o oposto disso: nenhuma prova de coisa nenhuma.
                Text(history.hasAnyRecord ? Verdict.usd(history.totalUSD) : "—")
                    .font(.num(T.lg, .medium))
                    .foregroundStyle(history.hasAnyRecord ? p.ink0 : p.ink4)
                    .numericValueTransition()
            }
        }
        .motion(.chrome, value: hovered)
    }

    // MARK: - A fita

    private var strip: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cw = colWidth(w)

            ZStack(alignment: .bottomLeading) {
                grades(w: w, h: h)

                ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                    column(day, index: i, w: cw, h: h)
                        .offset(x: originX(i, cw))
                }

                // A base. É o zero — e é a única linha dura do desenho, porque é a única
                // que é um fato: abaixo dela não existe gasto negativo.
                Rectangle()
                    .fill(p.line)
                    .frame(width: w - Self.gutter, height: 1)
                    .offset(x: Self.gutter, y: 1)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt):
                    let i = Int((pt.x - Self.gutter) / (cw + Self.gap))
                    hovered = days.indices.contains(i) && pt.x >= Self.gutter ? i : nil
                case .ended:
                    hovered = nil
                }
            }
        }
        .frame(height: height)
    }

    /// A coluna de um dia.
    @ViewBuilder
    private func column(_ day: History.Day, index: Int, w: CGFloat, h: CGFloat) -> some View {
        let isToday = index == days.count - 1

        ZStack(alignment: .bottom) {
            if hovered == index {
                // A lupa. Puro chrome: marca onde o olho está, não muda o que o dado diz.
                Rectangle()
                    .fill(p.ink4.opacity(0.14))
                    .frame(width: w, height: h)
            }

            if let cost = day.costUSD {
                let v = (cost as NSDecimalNumber).doubleValue
                if v > 0 {
                    // Reticulada e DEITADA: é custo, e custo neste app é SEMPRE derivado do
                    // pricing.json. A listra deita porque a tinta sobe (ver Hatch) — e o piso
                    // de 2 pt existe porque um dia de US$ 0,03 é um dia que ACONTECEU: ele
                    // merece um traço de tinta, não um arredondamento pra invisível.
                    Hatch(color: isToday && history.liveToday ? p.ember : p.emberCold,
                          horizontal: true)
                        .frame(width: w, height: max(2, h * v / scale.max))
                }
                // v == 0 → NADA acima da base. Não é bug: é o zero MEDIDO. Eu li o dia
                // inteiro e não havia gasto. Um zero que eu posso provar tem direito de
                // ser desenhado como zero — e é o único que tem.
            } else {
                // SEM REGISTRO. A hachura ocupa a faixa INTEIRA porque a ignorância é
                // inteira: pode ter sido um dia de US$ 0 ou de US$ 400, e o disco não
                // guarda mais a resposta. Desenhar isso como coluna zerada seria afirmar
                // o mais conveniente dos dois.
                //
                // E ela é FRACA de propósito. Ausência não pode gritar mais alto que dado:
                // se o buraco tivesse mais peso visual que a tinta, o olho leria a falta
                // como se ela fosse a informação. Ela é a moldura da informação que falta.
                DiagonalHatch(color: p.ink4, gap: 6)
                    .frame(width: w, height: h)
                    .opacity(0.30)
            }
        }
        .frame(width: w, height: h, alignment: .bottom)
        .motion(.data, value: day.costUSD)
    }

    /// A GRADUAÇÃO. Em US$, porque é o que a coluna mede — e a régua diz a unidade sem
    /// gastar um rótulo, que é o mesmo truque das marcas de hora da pista.
    private func grades(w: CGFloat, h: CGFloat) -> some View {
        ForEach(scale.grades, id: \.self) { v in
            let y = h * v / scale.max

            Rectangle()
                .fill(p.lineSoft)
                .frame(width: w - Self.gutter, height: 1)
                .offset(x: Self.gutter, y: -y)

            Text(Self.round(v))
                .font(.ui(T.micro))
                .foregroundStyle(p.ink4)
                .frame(width: Self.gutter - 10, height: 12, alignment: .trailing)
                .offset(y: -y + 6)
        }
    }

    // MARK: - O eixo do tempo
    //
    // De 7 em 7 dias, contando de HOJE pra trás — o ritmo em que a semana do usuário
    // acontece. Marcar de 5 em 5, ou nas segundas do calendário, seria graduar a régua na
    // escala de outra pessoa.

    private var axis: some View {
        GeometryReader { geo in
            let cw = colWidth(geo.size.width)
            ForEach(Array(stride(from: days.count - 1, through: 0, by: -7)), id: \.self) { i in
                let isToday = i == days.count - 1
                Text(isToday ? "hoje" : Self.shortDate(days[i].start))
                    .font(.ui(T.micro))
                    .foregroundStyle(isToday ? p.ink3 : p.ink4)
                    .fixedSize()
                    .frame(width: cw + 40, alignment: .center)
                    .offset(x: originX(i, cw) - 20)
            }
        }
        .frame(height: 12)
    }

    // MARK: - Geometria

    private func colWidth(_ w: CGFloat) -> CGFloat {
        let n = CGFloat(max(days.count, 1))
        return max(1, (w - Self.gutter - (n - 1) * Self.gap) / n)
    }

    private func originX(_ i: Int, _ cw: CGFloat) -> CGFloat {
        Self.gutter + CGFloat(i) * (cw + Self.gap)
    }

    // MARK: - A régua

    /// Passo redondo, com UMA casa de folga acima do pior dia. O topo nunca é um teto.
    struct Scale {
        let step: Double
        let max: Double
        /// As linhas desenhadas. O topo NÃO entra: uma linha no topo do trilho viraria
        /// um teto, e teto é a única coisa que este eixo não tem.
        var grades: [Double] {
            guard step > 0, max > step else { return [] }
            return Array(stride(from: step, to: max, by: step))
        }

        init(peak: Double) {
            guard peak > 0 else {
                self.step = 0
                self.max = 1
                return
            }
            let candidates: [Double] = [
                0.25, 0.5, 1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1_000, 2_000, 5_000,
            ]
            // No máximo 3 divisões: régua com dez linhas vira papel quadriculado, e
            // quadriculado é fundo, não instrumento.
            let s = candidates.first { peak / $0 <= 3 } ?? (candidates.last ?? 1)
            self.step = s
            self.max = (floor(peak / s) + 1) * s
        }
    }

    // MARK: - Palavras

    /// "US$ 400" — a graduação não tem centavos. Ela é a régua, não a medida.
    static func round(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v < 1 ? 2 : 0
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        return "US$ " + (f.string(from: NSNumber(value: v)) ?? "\(v)")
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM"
        return f.string(from: d)
    }

    static func dayLabel(_ d: Date, isToday: Bool) -> String {
        if isToday { return "hoje" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE dd/MM"
        return f.string(from: d)
    }

    /// A leitura do trilho, em uma fala. Os mesmos três fatos que o olho tira dele:
    /// o total, o pior dia, e o tamanho do buraco no registro.
    private var spoken: String {
        guard history.hasAnyRecord else {
            return "Últimos 30 dias: o disco não guarda registro nenhum deste período."
        }
        var parts = [
            "Últimos 30 dias. Custo estimado de "
            + Verdict.usd(history.totalUSD).replacingOccurrences(of: "US$ ", with: "") + " dólares."
        ]
        if let peak = history.peak, let c = peak.costUSD {
            let f = DateFormatter()
            f.locale = Locale(identifier: "pt_BR")
            f.dateFormat = "EEEE, d 'de' MMMM"
            parts.append(
                "Maior dia: \(f.string(from: peak.start)), "
                + Verdict.usd(c).replacingOccurrences(of: "US$ ", with: "") + " dólares."
            )
        }
        let gaps = history.daysWithoutRecord
        if gaps > 0 {
            parts.append(
                gaps == 1
                    ? "Um dia sem registro no disco — e dia sem registro não é dia sem gasto."
                    : "\(gaps) dias sem registro no disco — e dia sem registro não é dia sem gasto."
            )
        }
        return parts.joined(separator: " ")
    }
}
