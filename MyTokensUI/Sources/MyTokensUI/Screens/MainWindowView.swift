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

    /// O dia pinado no `DayRack`. Guardamos a DATA, não o `Day`: o `History` é
    /// reconstruído a cada scan, e um `Day` de um snapshot antigo ficaria preso no
    /// passado. A data é a única parte do dia que sobrevive ao refresh.
    @State private var selectedDayDate: Date?

    /// O dia selecionado, resolvido contra o trilho ATUAL. `nil` também quando a
    /// data pinada saiu da janela de 30 dias (o trilho rolou) — a seleção então
    /// simplesmente se desfaz sozinha, sem código extra pra "limpar".
    private var selectedDay: History.Day? {
        guard let selectedDayDate else { return nil }
        return history.days.first { $0.start == selectedDayDate }
    }

    /// As duas listas ("ONDE FOI" · "EM QUE MODELO") cortam por dia quando há
    /// seleção, e pelo período inteiro quando não há. As duas SEMPRE cortam pela
    /// MESMA coisa — uma no dia e a outra no mês seria uma dupla mentirosa.
    private var projectCuts: [History.Cut] { selectedDay?.breakdown?.projects ?? history.projects }
    private var modelCuts: [History.Cut] { selectedDay?.breakdown?.models ?? history.models }
    private var unattributedUSD: Decimal { selectedDay?.breakdown?.unattributedUSD ?? history.unattributedUSD }

    /// O sub-rótulo que avisa: o denominador mudou. Sem ele, "87%" no corte de um
    /// dia e "87%" no corte do mês são o mesmo número gritando coisas diferentes.
    private var scopeSubtitle: String? {
        guard let selectedDay else { return nil }
        let isToday = selectedDay.start == history.days.last?.start
        return DayRack.dayLabel(selectedDay.start, isToday: isToday)
    }

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

    // GRID, e não HStack de larguras chumbadas — que é o que o UI-SPEC §5 sempre pediu, e o
    // que esta tela vinha desobedecendo desde o primeiro dia.
    //
    // A coluna do número era `.frame(width: 190)`, dimensionada à mão pro "pior caso": o
    // "US$ 18,40 / 20" do Cursor. Só que o número da pista NÃO TRUNCA (é `fixedSize`, e isso
    // é lei desde o commit 270684b — dado com reticências é dado que mentiu por omissão).
    // Largura fixa + proibição de truncar = TRANSBORDO. E o orçamento produz "US$ 2.833,37 /
    // 200", que é o que finalmente fez o número escorrer PRA CIMA DO TRILHO, colidindo com a
    // tinta. Fotografado contra o disco real do Jair, não deduzido.
    //
    // O `Grid` mede antes de desenhar: a coluna do número nasce da largura do MAIOR número da
    // tela, e a pista fica com o que sobra — em todas as linhas ao mesmo tempo, que é o que
    // mantém as pistas começando e terminando no mesmo x. É a mesma correção que o `SpendList`
    // já tinha feito quando o disco real estourou a coluna dele. Uma régua chumbada só
    // funciona com números que a gente já viu.
    private var bench: some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: S.s4, verticalSpacing: 0) {
                axisHeader
                ForEach(snapshot.lanes) { lane in
                    // Uma view solta dentro do Grid ocupa uma linha que ATRAVESSA todas as
                    // colunas — é assim que o fio continua indo de ponta a ponta agora que
                    // ele não pode mais ser um `.overlay` da linha inteira.
                    Rectangle().fill(p.lineSoft).frame(height: 1)
                    benchRow(lane)
                }
            }

            // A NOTA FICA FORA DA GRADE, e isso não é arrumação — é a diferença entre a tela
            // caber e não caber.
            //
            // Uma linha que atravessa o Grid participa do dimensionamento dele, e a largura
            // IDEAL de um parágrafo é o parágrafo SEM QUEBRA: ~1.020 pt de frase numa janela
            // de 960. O Grid obedecia (é o trabalho dele: acomodar a linha mais larga), a
            // bancada inteira esticava pra 1.220 pt e a coluna do número era empurrada pra
            // fora da tela. Fotografei, vi, e é por isso que ela mora aqui: ela é uma
            // RESSALVA sobre a grade, não uma linha dela.
            budgetNote
        }
        .padding(.horizontal, S.s6)
        .padding(.vertical, S.s4)
    }

    /// A RESSALVA DO DINHEIRO. Só existe quando existe a pista do orçamento — uma frase sobre
    /// uma pista que ninguém está vendo é ruído, e o app já tem rodapé demais pra ler.
    ///
    /// Ela diz as duas coisas que o desenho não consegue dizer sozinho, e que nenhum outro
    /// texto da tela cobre:
    ///
    ///   1. O NÚMERO É UM PISO. O disco do Claude é MUTÁVEL: sessão antiga é reescrita e
    ///      compactada, e gasto SOME do passado. Um orçamento relê o mês inteiro a cada
    ///      refresh — então esta barra pode ENCOLHER entre duas leituras, sem que ninguém
    ///      tenha devolvido um centavo. Uma barra que anda pra trás sem explicação destrói a
    ///      confiança no instrumento de uma vez só; explicada, ela vira exatamente o que é:
    ///      um erro que só acontece pra baixo. Ele subestima, e nunca exagera.
    ///
    ///   2. O CURSOR NÃO ENTRA. Ele não grava uso no disco e não emite evento nenhum — o que
    ///      ele publica é a fração de um crédito INCLUÍDO no plano, no ciclo de cobrança dele,
    ///      que não é o mês do calendário. Um usuário de Cursor que lesse "orçamento" e
    ///      pensasse "então está tudo aqui dentro" teria sido enganado por omissão, que é a
    ///      mentira preferida dos dashboards.
    ///
    /// Que isto é preço de tabela e não fatura, o rodapé já diz — e diz pros dois números em
    /// US$ da tela. Repetir aqui seria roubar a linha de quem tem o que dizer.
    /// UMA LINHA, e não duas — e a segunda linha não foi cortada por estética.
    ///
    /// A janela não rola e a tela do Jair tem 1080 px. Com a pista do orçamento, a bancada
    /// passou a medir exatamente 1080: a ressalva em dois parágrafos era o que empurrava a
    /// resposta pra fora da tela. Uma frase que ninguém consegue ver porque a janela não abre
    /// é menos honesta que uma frase curta. O que sobrou diz as duas coisas que precisavam ser
    /// ditas — o piso e o Cursor — e o resto (o porquê inteiro) mora no painel onde o teto foi
    /// definido, que é onde ele tem espaço pra ser lido com calma.
    @ViewBuilder
    private var budgetNote: some View {
        if snapshot.lanes.contains(where: { $0.owner == .budget }) {
            Text(
                "O orçamento é um PISO: o Claude reescreve sessões antigas, e o que sai do "
                + "disco sai daqui. O Cursor não entra — ele mede crédito incluído."
            )
            .font(.ui(T.xs))
            .foregroundStyle(p.ink4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, S.s2)
        }
    }

    /// A régua do eixo. Ela diz, sem uma palavra, que o eixo é NORMALIZADO:
    /// "50% DA JANELA", não "2h30". É o que autoriza 5 h, 7 d e US$ 20/mês a
    /// dividirem a mesma tela sem que isso seja mentira.
    private var axisHeader: some View {
        GridRow {
            Text("JANELA")
                .font(.ui(T.micro, .medium))
                .tracking(0.09 * T.micro)
                .foregroundStyle(p.ink3)
                .frame(width: Self.nameColumn, alignment: .leading)

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
            .frame(minWidth: Self.laneMin, idealWidth: Self.laneIdeal, maxWidth: .infinity)

            Text("FONTE")
                .font(.ui(T.micro, .medium))
                .tracking(0.09 * T.micro)
                .foregroundStyle(p.ink3)
                // É esta coluna que o Grid dimensiona pelo MAIOR número da tela. O
                // `.trailing` é declarado UMA vez, aqui, e vale pra coluna inteira.
                .gridColumnAlignment(.trailing)
        }
        .padding(.bottom, S.s4)
        // A régua é GRADUAÇÃO — ela existe pra dar escala ao traço. Quem lê por
        // som não tem traço nenhum: ouve "68% da cota" direto da pista, e "0%,
        // 50% da janela, 100%" seria só uma fileira de números sem referente.
        .accessibilityHidden(true)
    }

    /// A coluna do NOME. Esta continua chumbada, e pode: o que mora nela são dois rótulos
    /// nossos ("Claude", "Orçamento") e um label de janela — texto que o app escreve, não
    /// número que o disco produz. É o número que é imprevisível, e é ele que ganhou o Grid.
    static let nameColumn: CGFloat = 170

    /// A pista é um `GeometryReader`, e um `GeometryReader` NÃO TEM tamanho ideal — ele
    /// devolve o que lhe propuserem. Num `HStack` isso não importava (o flexível come a
    /// sobra); num `Grid` importa muito: sem uma largura ideal, o Grid não sabe dimensionar a
    /// coluna, e a régua toda escapa pra fora da janela. O `SpendList` já tinha aprendido
    /// isto — a pista dele leva `minWidth: 60, idealWidth: 200` pelo mesmo motivo.
    ///
    /// O `min` é o ponto em que a pista para de ceder: abaixo disso ela deixaria de ser
    /// legível como medida, e aí é melhor a janela ficar apertada do que a pista virar um
    /// traço. `max: .infinity` mantém ela sendo quem paga a conta quando o número engorda.
    static let laneMin: CGFloat = 200
    static let laneIdeal: CGFloat = 460

    private func benchRow(_ lane: Lane) -> some View {
        GridRow(alignment: .center) {
            // quem — escrito pro olho. Pro ouvido, quem se apresenta é a pista:
            // "Claude, janela de 5 h" abre a fala dela.
            VStack(alignment: .leading, spacing: 2) {
                Text(lane.ownerName)
                    .font(.ui(T.md, .medium))
                    .foregroundStyle(p.ink0)
                Text(lane.windowLabel)
                    .font(.ui(T.xs))
                    .foregroundStyle(p.ink3)
            }
            .frame(width: Self.nameColumn, alignment: .leading)
            .accessibilityHidden(true)

            // a pista — 14 pt, com agulha. É ela que FALA a linha inteira.
            // Ela é a coluna ELÁSTICA: quando o número engorda, quem cede largura é a pista,
            // que tem folga de sobra. O contrário — a pista fixa e o número espremido — só
            // teria duas saídas, truncar o dado ou escorrer por cima do trilho, e as duas
            // já foram cometidas nesta tela.
            LaneView(lane: lane, height: 14, showNeedle: true)
                .frame(minWidth: Self.laneMin, idealWidth: Self.laneIdeal, maxWidth: .infinity)

            // o número + a procedência, em palavra
            VStack(alignment: .trailing, spacing: 3) {
                ValueText(lane: lane, size: T.xl)
                    .accessibilityHidden(true)   // já está na fala da pista
                HStack(spacing: 5) {
                    RangeText(lane: lane)
                        .accessibilityHidden(true)   // idem: a faixa 41–68 é dita lá
                    if lane.certainty.hasInk {
                        Text(lane.provenanceNote)
                            .font(.ui(T.micro))
                            .tracking(0.05 * T.micro)
                            .foregroundStyle(p.ink3)
                            .accessibilityHidden(true)   // idem: a certeza abre a frase
                    } else if let provider = lane.provider {
                        // A única AÇÃO da linha — e a única coisa dela que o
                        // VoiceOver ainda para. "conectar", sozinho, não diz o quê.
                        // (o orçamento nunca cai aqui: não há o que conectar num teto
                        // que o próprio usuário digitou — ver PopoverView)
                        Button("conectar") { onConnect(provider) }
                            .buttonStyle(.plain)
                            .font(.ui(T.xs))
                            .foregroundStyle(p.ember)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(p.ember.opacity(0.35))
                                    .frame(height: 1).offset(y: 2)
                            }
                            .accessibilityLabel("Conectar o \(provider.displayName)")
                    }
                }
            }
        }
        // 24 → 16 → 12 → 8. A bancada cede ar vertical toda vez que ganha uma linha, porque a
        // tela do Jair tem 1080 px e esta janela NÃO ROLA — uma tela que rola é uma tela onde
        // a resposta pode estar embaixo da dobra, e este app existe pra responder de relance.
        // Com a pista do orçamento a bancada bateu 1.080 px exatos: sem este passo, ela deixava
        // de abrir.
        //
        // Continua sendo a MARGEM que encolhe, nunca o que cada pista diz — a mesma troca que
        // a história já tinha feito. E ainda sobra folga: o que fixa a altura da linha é a
        // coluna do nome (~36 pt), e a agulha do "agora" (34 pt) continua cabendo inteira.
        .padding(.vertical, S.s2)
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
            DayRack(history: history, selected: $selectedDayDate)

            provenance

            // Onde foi | em que modelo. Lado a lado porque são a MESMA pergunta cortada de
            // dois jeitos: uma diz o lugar, a outra diz o preço do lugar. Empilhadas,
            // pareceriam duas seções, e o olho leria uma e abandonaria a outra.
            //
            // Com um dia selecionado no trilho, as duas cortam pelo DIA — e o sub-rótulo
            // diz isso, porque "87%" do dia e "87%" do mês são o mesmo número mentindo
            // sobre denominadores diferentes se ninguém escrever qual é qual.
            HStack(alignment: .top, spacing: S.s7) {
                SpendList(
                    title: "ONDE FOI",
                    subtitle: scopeSubtitle,
                    cuts: projectCuts,
                    restNoun: "projetos",
                    // Evento sem `cwd` no disco existe (Codex antigo, sessão fora de repo).
                    // Ele não vira um projeto chamado "desconhecido" — vira uma linha que
                    // FECHA a conta. A alternativa era a coluna somar menos que o trilho e
                    // ninguém explicar por quê.
                    tail: unattributedUSD > 0
                        ? .init(label: "sem projeto no disco", costUSD: unattributedUSD)
                        : nil
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                SpendList(
                    title: "EM QUE MODELO",
                    subtitle: scopeSubtitle,
                    cuts: modelCuts,
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
                //
                // `Verdict.usd` é o formatter de dinheiro DO APP, e agora ele é o único: o
                // `String(format:)` que morava aqui não agrupava milhar, e num dia de US$
                // 4608 imprimia "US$ 4608,00" enquanto a lista de projetos, do lado, imprimia
                // "US$ 4.608,00". Dois jeitos de escrever o mesmo dinheiro na mesma tela.
                Text(Verdict.usd(snapshot.todayCostUSD))
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
