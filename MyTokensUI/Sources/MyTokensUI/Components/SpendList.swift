//  SpendList.swift
//
//  O CORTE — onde o dinheiro foi. Por projeto e por modelo, a mesma peça duas vezes.
//
//  A linha é a MESMA gramática da bancada: [ nome ][ pista ][ leitura ]. Nenhum tipo novo
//  de gráfico entrou no app pra dizer isto — e não entrou de propósito. Uma tela que
//  responde "posso continuar?" com pista e responde "onde foi meu dinheiro?" com um donut
//  são duas telas coladas com fita. Aqui a pista muda de denominador, e só.
//
//  E o denominador aqui EXISTE de verdade: é a soma do período. Por isso esta pista tem
//  trilho (ao contrário do DayRack, que não tem teto pra ter trilho): 100% do trilho é
//  100% do que você gastou em 30 dias, e "o Opus comeu 87% disso" é uma fração honesta de
//  uma coisa que a gente mediu inteira.
//
//  Quem não custou não aparece. Não como `US$ 0,00`, não como linha cinza, não como
//  "outros": não aparece. Uma linha é um lugar caro na tela e ela pertence a quem tem o
//  que dizer.

import SwiftUI

public struct SpendList: View {
    @Environment(\.palette) private var p

    /// "ONDE FOI" · "EM QUE MODELO"
    public let title: String
    /// O escopo, quando não é o período inteiro — ex. a data de um dia selecionado
    /// no `DayRack`. `nil` é o padrão silencioso: "corto o período", que não precisa
    /// de rótulo porque é o que a tela sempre disse. Existe SÓ pra avisar quando o
    /// denominador da pista mudou — ver `norte-ux`, princípio 3.
    public var subtitle: String?
    public let cuts: [History.Cut]
    /// Quantas linhas antes da cauda virar uma só.
    public var limit: Int = 5
    /// O substantivo da cauda: "projetos", "modelos".
    public var restNoun: String = "projetos"
    /// A linha que não é uma fatia. Hoje só uma coisa mora aqui: o gasto que o disco não
    /// sabe de quem é (evento sem `cwd`). Ela existe pra a coluna FECHAR com o trilho —
    /// um resto que não bate é o jeito mais silencioso de um número mentir.
    public var tail: Tail?

    public struct Tail: Sendable, Equatable {
        public let label: String
        public let costUSD: Decimal
        public init(label: String, costUSD: Decimal) {
            self.label = label
            self.costUSD = costUSD
        }
    }

    public init(
        title: String,
        subtitle: String? = nil,
        cuts: [History.Cut],
        limit: Int = 5,
        restNoun: String = "projetos",
        tail: Tail? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.cuts = cuts
        self.limit = limit
        self.restNoun = restNoun
        self.tail = tail
    }

    private var split: (shown: [History.Cut], rest: History.Rest?) {
        History.top(cuts, limit)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: S.s3) {
            HStack(alignment: .firstTextBaseline, spacing: S.s2) {
                Text(title)
                    .font(p.ui(T.micro, .medium))
                    .tracking(0.09 * T.micro)
                    .foregroundStyle(p.ink3)

                // O escopo muda, o rótulo não pode ficar calado sobre isso. Fonte
                // solta (sem tracking de caixa-alta): é aviso, não título.
                if let subtitle {
                    Text(subtitle)
                        .font(p.ui(T.xs))
                        .foregroundStyle(p.ink4)
                }
            }
            .accessibilityHidden(true)   // já abre a fala de cada linha

            if cuts.isEmpty {
                // Nada custou nada. Travessão — nunca um zero.
                Text("—")
                    .font(p.num(T.lg))
                    .foregroundStyle(p.ink4)
                    .padding(.top, S.s1)
            } else {
                // GRID, não HStack de larguras chumbadas (UI-SPEC §5): a coluna do número se
                // dimensiona sozinha pelo MAIOR número da lista, e todas as linhas seguem.
                //
                // Não é preferência de API. Com largura fixa, o disco real do Jair estourou a
                // coluna e o app imprimiu `US$ 4.608,…` — um DADO TRUNCADO, que é a mentira
                // por omissão que este repo já matou uma vez (commit 270684b). Um número que
                // cabe com US$ 52 e não cabe com US$ 4.608 é uma coluna que só funciona com
                // gente pobre. O Grid mede antes de desenhar; a régua chumbada, não.
                Grid(alignment: .leading, horizontalSpacing: S.s3, verticalSpacing: 5) {
                    ForEach(split.shown) { cut in
                        row(cut)
                    }
                    if let rest = split.rest {
                        // A cauda tem TAMANHO e tem NOME: "+ 81 projetos". "Outros" sozinho
                        // é o lugar onde os dashboards escondem o que não entenderam.
                        minor("+ \(rest.count) \(restNoun)", rest.costUSD)
                    }
                    if let tail {
                        minor(tail.label, tail.costUSD)
                    }
                }
            }
        }
    }

    // MARK: - A linha

    private func row(_ cut: History.Cut) -> some View {
        GridRow {
            Text(cut.label)
                .font(p.ui(T.sm))
                .foregroundStyle(p.ink1)
                .lineLimit(1)
                .truncationMode(.middle)   // nome de repo é longo NO MEIO, não no fim
                .frame(maxWidth: Self.nameCap, alignment: .leading)

            // A pista. Trilho = os 30 dias inteiros; tinta = a parte que foi pra cá.
            // Reticulada, como todo custo neste app: é preço de tabela, não é fatura.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(p.track)
                        .frame(height: Self.laneHeight)
                    Hatch(color: p.laneCold)
                        .frame(width: max(1, geo.size.width * cut.share), height: Self.laneHeight)
                }
                .frame(height: Self.laneHeight, alignment: .leading)
            }
            .frame(minWidth: 60, idealWidth: 200, maxHeight: Self.laneHeight)
            .motion(.data, value: cut.share)

            Text(Verdict.usd(cut.costUSD))
                .font(p.num(T.sm, .medium))
                .foregroundStyle(p.ink0)
                .gridColumnAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)   // dado não trunca. NUNCA.
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cut.label)
        .accessibilityValue(
            Verdict.usd(cut.costUSD).replacingOccurrences(of: "US$ ", with: "")
            + " dólares, \(Int((cut.share * 100).rounded()))% do período. Estimado."
        )
    }

    /// A cauda e o não-atribuído. Mesma conta, meia voz: eles fecham o total, não
    /// disputam a leitura. E não têm pista — eles não são UMA fatia, são um saco delas.
    private func minor(_ label: String, _ cost: Decimal) -> some View {
        GridRow {
            Text(label)
                .font(p.ui(T.xs))
                .foregroundStyle(p.ink3)
                .lineLimit(1)
                .frame(maxWidth: Self.nameCap, alignment: .leading)

            Color.clear.frame(height: 1)   // a coluna da pista fica VAZIA, e de propósito

            Text(Verdict.usd(cost))
                .font(p.num(T.xs))
                .foregroundStyle(p.ink3)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(
            Verdict.usd(cost).replacingOccurrences(of: "US$ ", with: "") + " dólares. Estimado."
        )
    }

    /// Teto do nome, não largura dele: nome de repo é imprevisível, e uma coluna que cresce
    /// sem limite come a pista — que é justamente a peça que responde a pergunta.
    static let nameCap: CGFloat = 150
    static let laneHeight: CGFloat = 7
}
