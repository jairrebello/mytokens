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
    @Environment(\.colorScheme) private var scheme

    public let snapshot: Dashboard
    public var onConnect: (Provider) -> Void = { _ in }
    public var theme: Theme = .bancada

    /// A paleta desta tela — resolvida do TEMA, não lida do ambiente.
    ///
    /// Isto conserta um bug que estava aqui desde que o tema virou opção: o `.theme(theme)`
    /// lá embaixo injeta a paleta pros FILHOS (as pistas, os números, a legenda), mas o
    /// corpo desta view já leu o `@Environment(\.palette)` ANTES do modifier existir — e
    /// pegava o valor PADRÃO do `PaletteKey`, que é o bancada escuro. Resultado: em light,
    /// a janela desenhava fundo preto com trilhos claros; no Terminal, o canvas e o veredito
    /// saíam em bone enquanto as pistas saíam em fósforo verde. A tela obedecia a dois temas.
    ///
    /// A view SABE qual é o tema (é parâmetro dela). Então ela resolve a própria paleta e
    /// injeta a mesma pros filhos. Uma fonte de verdade, como tudo aqui.
    private var p: Palette { theme.palette(for: scheme) }

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

    /// O passado só é desenhado quando existe passado.
    ///
    /// Duas coisas o escondem, e as duas são a mesma coisa dita de dois jeitos:
    ///   • `.empty` — o motor ainda não leu (antes do 1º scan). Trinta colunas de nada
    ///     enquanto ele varre 1,4 GB seriam um instrumento afirmando o que não mediu.
    ///   • sem UM dia de registro — 30 hachuras não informam ninguém. Elas gastariam meia
    ///     tela pra dizer "não sei", e o veredito lá em cima já disse isso melhor.
    ///
    /// Basta UM dia com registro pra seção existir: aí a hachura tem contra o que ser lida.
    private var history: History { snapshot.history }
    private var showsHistory: Bool { !history.days.isEmpty && history.hasAnyRecord }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            verdictBlock
            Rectangle().fill(p.lineSoft).frame(height: 1)
            bench
            if showsHistory {
                Rectangle().fill(p.lineSoft).frame(height: 1)
                past
            }
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
            // A RESPOSTA. Headline e frase são UMA ideia — e viram UMA fala:
            // duas paradas do VoiceOver pra dizer uma coisa só seria gagueira.
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
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(verdict.spoken)

            if let t = snapshot.tightest, !snapshot.isEmpty {
                clockline(t)
                    .padding(.top, S.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // O ar VERTICAL encolheu (32 → 24) quando a história entrou. A janela do Jair tem
        // 1080 px de altura e a bancada inteira precisa caber SEM rolagem: uma tela que
        // rola é uma tela onde a resposta pode estar embaixo da dobra, e este app existe
        // pra responder de relance. O ar horizontal ficou intacto — quem cedeu foi a
        // margem, não a hierarquia.
        .padding(.horizontal, S.s6)
        .padding(.vertical, S.s5)
    }

    /// TEMPO > TOKEN. Folga em pontos, hora do reset, ritmo relativo à janela.
    /// Nenhum destes é um token — e é de propósito: token é a unidade da máquina.
    private func clockline(_ t: Lane) -> some View {
        HStack(spacing: S.s4) {
            if let slack = t.slackLabel {
                metric("Folga na mais apertada", slack,
                       spoken: t.spokenSlack ?? slack,
                       hot: (t.slackPoints ?? 0) < 0)
            }
            if let reset = t.resetsAt {
                metric("Zera", Verdict.hm(reset),
                       spoken: Verdict.hm(reset),
                       hot: false)
            }
            if let pace = t.paceLabel {
                metric("Ritmo", pace,
                       spoken: t.spokenPace ?? pace,
                       hot: false)
            }
        }
    }

    /// O rótulo vai em caixa alta e o valor em glifo (`+14 pts`, `0,86×`) — as duas
    /// coisas que o olho lê rápido e o ouvido lê mal. `spoken` é a mesma métrica
    /// dita em palavra: nada de "mais catorze p t s" nem de "zero vírgula oitenta e
    /// seis vezes o sinal de multiplicação".
    private func metric(_ label: String, _ value: String, spoken: String, hot: Bool) -> some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
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
        .padding(.vertical, S.s4)
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
        // A régua é GRADUAÇÃO — ela existe pra dar escala ao traço. Quem lê por
        // som não tem traço nenhum: ouve "68% da cota" direto da pista, e "0%,
        // 50% da janela, 100%" seria só uma fileira de números sem referente.
        .accessibilityHidden(true)
    }

    /// A coluna do número, larga o bastante pro PIOR caso: "US$ 18,40 / 20" em 26 pt mono.
    /// Fixa (não por-linha) pra as pistas alinharem — começam e terminam no mesmo x. A
    /// janela tem 960 px; os 40 px a mais saem da pista, que tem folga de sobra.
    static let valueColumn: CGFloat = 190

    private func benchRow(_ lane: Lane) -> some View {
        HStack(alignment: .center, spacing: S.s4) {
            // quem — escrito pro olho. Pro ouvido, quem se apresenta é a pista:
            // "Claude, janela de 5 h" abre a fala dela.
            VStack(alignment: .leading, spacing: 2) {
                Text(lane.provider.displayName)
                    .font(.ui(T.md, .medium))
                    .foregroundStyle(p.ink0)
                Text(lane.windowLabel)
                    .font(.ui(T.xs))
                    .foregroundStyle(p.ink3)
            }
            .frame(width: 170, alignment: .leading)
            .accessibilityHidden(true)

            // a pista — 14 pt, com agulha. É ela que FALA a linha inteira.
            LaneView(lane: lane, height: 14, showNeedle: true)
                .frame(maxWidth: .infinity)

            // o número + a procedência, em palavra
            VStack(alignment: .trailing, spacing: 3) {
                ValueText(lane: lane, size: T.xl)
                    .accessibilityHidden(true)   // já está na fala da pista
                HStack(spacing: 5) {
                    RangeText(lane: lane)
                        .accessibilityHidden(true)   // idem: a faixa 41–68 é dita lá
                    if lane.certainty.hasInk {
                        Text(lane.certainty.provenanceLabel())
                            .font(.ui(T.micro))
                            .tracking(0.05 * T.micro)
                            .foregroundStyle(p.ink3)
                            .accessibilityHidden(true)   // idem: a certeza abre a frase
                    } else {
                        // A única AÇÃO da linha — e a única coisa dela que o
                        // VoiceOver ainda para. "conectar", sozinho, não diz o quê.
                        Button("conectar") { onConnect(lane.provider) }
                            .buttonStyle(.plain)
                            .font(.ui(T.xs))
                            .foregroundStyle(p.ember)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(p.ember.opacity(0.35))
                                    .frame(height: 1).offset(y: 2)
                            }
                            .accessibilityLabel("Conectar o \(lane.provider.displayName)")
                    }
                }
            }
            .frame(width: Self.valueColumn, alignment: .trailing)
        }
        // 24 → 16 → 12. A bancada cedeu ar vertical pra história caber na tela do Jair
        // (1080 px, e a janela não rola). O ar horizontal e a hierarquia ficaram intactos:
        // quem encolheu foi a margem entre as pistas, não o que cada pista diz.
        .padding(.vertical, S.s3)
        .overlay(alignment: .top) {
            Rectangle().fill(p.lineSoft).frame(height: 1)
        }
    }

    // MARK: - O passado
    //
    // A bancada acima responde "posso continuar?". Esta metade responde a outra pergunta,
    // que é a única que o app pode responder e mais ninguém: "para ONDE foi o meu mês?".
    //
    // Ela é o mesmo instrumento — trilho, tinta, graduação, hachura — medindo outra coisa.
    // Repare no que ela NÃO ganhou: nenhuma textura nova, nenhuma cor nova, nenhum card.
    // O que muda de uma leitura pra outra é o DENOMINADOR, nunca o vocabulário.

    private var past: some View {
        VStack(alignment: .leading, spacing: S.s4) {
            DayRack(history: history)

            provenance

            // Onde foi | em que modelo. Lado a lado porque são a MESMA pergunta cortada de
            // dois jeitos: uma diz o lugar, a outra diz o preço do lugar. Empilhadas,
            // pareceriam duas seções, e o olho leria uma e abandonaria a outra.
            HStack(alignment: .top, spacing: S.s7) {
                SpendList(
                    title: "ONDE FOI",
                    cuts: history.projects,
                    restNoun: "projetos",
                    // Evento sem `cwd` no disco existe (Codex antigo, sessão fora de repo).
                    // Ele não vira um projeto chamado "desconhecido" — vira uma linha que
                    // FECHA a conta. A alternativa era a coluna somar menos que o trilho e
                    // ninguém explicar por quê.
                    tail: history.unattributedUSD > 0
                        ? .init(label: "sem projeto no disco", costUSD: history.unattributedUSD)
                        : nil
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                SpendList(
                    title: "EM QUE MODELO",
                    cuts: history.models,
                    restNoun: "modelos"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, S.s6)
        .padding(.vertical, S.s4)
    }

    /// A RESSALVA DO DESENHO. Só aparece quando há hachura na tela pra ela explicar —
    /// legenda de textura que ninguém está vendo é ruído, e o rodapé já ensina isso.
    ///
    /// É a frase mais desconfortável do app, e a única que ninguém mais pode dizer: o disco
    /// do Claude é MUTÁVEL. Sessão antiga é reescrita e compactada, e um dia de junho pode
    /// ter tido gasto e não ter mais prova disso. Um app que desenhasse aquele dia como uma
    /// coluna zerada estaria afirmando "você não trabalhou" — e essa é exatamente a
    /// afirmação que ele não pode fazer. Então ele hachura o dia e escreve o porquê.
    @ViewBuilder
    private var provenance: some View {
        if history.daysWithoutRecord > 0 {
            Text(
                "Dia hachurado é dia SEM REGISTRO — não é dia sem gasto. "
                + "O Claude reescreve sessões antigas, e o que sai do disco sai daqui."
            )
            .font(.ui(T.xs))
            .foregroundStyle(p.ink4)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Rodapé
    // A procedência é permanente. Contrato de honestidade se imprime na peça.

    private var footer: some View {
        HStack {
            // A legenda explica o que ESTÁ na tela. Com a história aberta, existe reticulado
            // à vista mesmo que toda pista esteja medida — todo custo é derivado. Se a
            // legenda não citasse o "inferido" aqui, ela estaria ensinando a ler uma tela
            // que não é esta.
            ProvenanceLegend(
                present: showsHistory
                    ? snapshot.legendKinds.union([.inferred])
                    : snapshot.legendKinds
            )

            Spacer(minLength: S.s4)

            // A PROCEDÊNCIA DO DINHEIRO. Mora aqui, e não junto do trilho, porque ela vale
            // pros DOIS números em US$ da tela: os 30 dias E o "hoje" que está do lado. É o
            // rodapé de um instrumento de medição — contrato de honestidade se imprime na
            // peça, não num tooltip que ninguém abre.
            //
            // O que ela NÃO ganha é o til `~`. O til promete uma FAIXA (`41–68`), e aqui não
            // existe faixa a prometer: o token é exato e o preço é o de tabela. A incerteza
            // não é de magnitude, é de NATUREZA — isto é preço de API, não a conta que a
            // Anthropic vai te cobrar. Isso não cabe num sinal de pontuação; cabe numa frase.
            Text("Custo estimado a preço de API (pricing.json). Não é a sua fatura.")
                .font(.ui(T.xs))
                .foregroundStyle(p.ink3)
                .lineLimit(1)
                .layoutPriority(-1)   // quem cede largura primeiro é a nota, nunca o número

            Spacer(minLength: S.s4)

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
            // "US$" é sigla pro olho. Pro ouvido é "dólares" — e o valor continua
            // sendo o gasto do dia, nunca "quanto sobra".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Queimado hoje em API")
            .accessibilityValue(
                String(format: "%.2f", (snapshot.todayCostUSD as NSDecimalNumber).doubleValue)
                    .replacingOccurrences(of: ".", with: ",") + " dólares"
            )
        }
        .padding(.horizontal, S.s6)
        .padding(.vertical, S.s3)
        .background(p.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(p.line).frame(height: 1)
        }
    }
}
