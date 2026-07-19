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
    @Environment(\.colorScheme) private var scheme

    /// A paleta desta tela — resolvida do TEMA, não lida do ambiente. O MESMO bug que estava
    /// na `MainWindowView`: o `.theme(theme)` do fim do corpo injeta a paleta pros FILHOS, mas
    /// o corpo daqui (a superfície, o cabeçalho, o rodapé) já leu o `@Environment(\.palette)`
    /// antes de o modifier existir, e pegava o PADRÃO — bancada escuro. No popover o sintoma
    /// era mais silencioso que na janela e por isso durou mais: a `.ultraThinMaterial` por
    /// baixo disfarçava a superfície errada. Mas no tema Terminal o rodapé saía em bone sobre
    /// o fósforo verde das pistas. Uma tela, dois temas.
    ///
    /// A view SABE qual é o tema — é parâmetro dela. Então resolve a própria paleta e injeta
    /// a mesma pros filhos.
    private var p: Palette { theme.palette(for: scheme) }

    public let snapshot: Dashboard
    public var onOpenWindow: () -> Void = {}
    public var onConnect: (Provider) -> Void = { _ in }
    /// Pausar / abrir no login / trocar tema / sair. Sem isto, o app não tem porta de saída.
    public var controls = AppControls()
    /// O tema escolhido. Default Bancada pra galeria/preview não precisar passar.
    public var theme: Theme = .bancada

    public init(
        snapshot: Dashboard,
        onOpenWindow: @escaping () -> Void = {},
        onConnect: @escaping (Provider) -> Void = { _ in },
        controls: AppControls = AppControls(),
        theme: Theme = .bancada
    ) {
        self.snapshot = snapshot
        self.onOpenWindow = onOpenWindow
        self.onConnect = onConnect
        self.controls = controls
        self.theme = theme
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
        .theme(theme)
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
        // A RESPOSTA vem primeiro — no olho e no ouvido. Headline e frase são UMA
        // fala só: separá-las daria ao VoiceOver duas paradas pra dizer uma ideia.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verdict.spoken)
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
            // Título e número são a MESMA informação que a pista já fala, escrita
            // pro olho. Escondidos do VoiceOver: quem lê a pista é a pista.
            HStack(alignment: .firstTextBaseline) {
                Text(lane.title)
                    .font(.ui(T.sm, .medium))
                    .foregroundStyle(p.ink0)
                    .lineLimit(1)          // o TÍTULO cede, não o dado
                Spacer(minLength: S.s2)
                ValueText(lane: lane, size: T.md)
            }
            .accessibilityHidden(true)

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
                    .accessibilityHidden(true)   // a procedência já está na fala da pista
                Spacer(minLength: S.s1)
                if lane.certainty.hasInk {
                    Text(lane.displayReset ?? "")
                        .font(.num(T.micro))
                        .tracking(0.03 * T.micro)
                        .foregroundStyle(p.ink3)
                        .accessibilityHidden(true)   // idem: "zera às 16:50" já foi dito
                } else if let provider = lane.provider {
                    // Sem dado → o convite. Não é modal, não é badge vermelho,
                    // não é tour: fica no lugar onde a dor está, e some sozinho
                    // quando resolvido.
                    //
                    // É a única AÇÃO da linha, então é a única coisa daqui que o
                    // VoiceOver ainda para. E ela diz o provedor: "conectar" sozinho,
                    // fora da linha em que está, não é instrução — é adivinhação.
                    //
                    // O `let provider` não é cerimônia de Optional: é o compilador
                    // impedindo que a pista do orçamento ganhe um "conectar". Não há o que
                    // conectar num teto que o próprio usuário escreveu — e ela nunca chega
                    // aqui, porque orçamento sem tinta não é uma pista vazia, é uma pista
                    // que não existe.
                    Button("conectar") { onConnect(provider) }
                        .buttonStyle(.plain)
                        .font(.ui(T.xs))
                        .foregroundStyle(p.ember)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(p.ember.opacity(0.35)).frame(height: 1).offset(y: 2)
                        }
                        .accessibilityLabel("Conectar o \(provider.displayName)")
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
        // O orçamento diz "estimado do disco", não só "estimado" (ver `Lane.provenanceNote`):
        // em 340 px não cabe a ressalva inteira, mas cabe o DE ONDE — e o de onde é o que
        // explica o número poder andar pra trás. A ressalva inteira mora na janela grande e
        // no painel onde ele foi definido.
        var s = lane.provenanceNote
        if case .absent = lane.certainty, lane.unit == .usd,
           let cap = lane.capUSD {
            s += " · US$ \(Lane.cap(cap)) de crédito"
        }
        if let range = lane.displayRange {
            s += " · \(range)"
        }
        return s
    }

    // MARK: - Rodapé: a procedência é permanente

    private var footer: some View {
        HStack(spacing: S.s2) {
            // A legenda da procedência é INFORMAÇÃO — ela não encolhe pra caber um botão.
            // Sem o fixedSize, o ⋯ roubava largura e "MEDIDO" quebrava em "MEDID/O".
            // E ela mostra SÓ as texturas que estão na tela agora: com tudo medido, é uma
            // palavra só, e o rodapé respira.
            ProvenanceLegend(present: snapshot.legendKinds)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: 0)
            Button(action: onOpenWindow) {
                HStack(spacing: 4) {
                    Text("ABRIR")
                        .font(.ui(T.micro, .medium))
                        .tracking(0.06 * T.micro)
                    // O ⌘⏎ é lembrete de atalho, não conteúdo: dois glifos que o
                    // VoiceOver leria como "command, return" no meio do rótulo.
                    Image(systemName: "command")
                        .font(.system(size: 8, weight: .medium))
                    Image(systemName: "return")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(p.ink3)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Abrir a janela do MyTokens")

            AppMenu(controls: controls)
        }
        .padding(.horizontal, S.s4)
        .padding(.vertical, 9)
        .background(p.surfaceHi.opacity(p.isDark ? 0.7 : 0.9))
        .overlay(alignment: .top) {
            Rectangle().fill(p.line).frame(height: 1)
        }
    }
}

// MARK: - Os controles do app
//
// Um app de barra de menu SEM SAÍDA VISÍVEL é um app que se instala e não se desinstala.
// Aqui é a única porta: pausar, abrir no login, sair.
//
// Ele mora no rodapé — a faixa que já é do app, não do dado. Peso `ink3`, o mesmo do
// "ABRIR" ao lado: é ferramenta, não informação. Nada aqui compete com a pista.

struct AppMenu: View {
    @Environment(\.palette) private var p
    let controls: AppControls

    var body: some View {
        Menu {
            Button(controls.isPaused ? "Retomar leitura" : "Pausar leitura",
                   action: controls.togglePause)

            // Escolhas do usuário, não interruptores: submenu com marca no ativo.
            Divider()
            Menu("Mostrar na barra") {
                ForEach(MenuBarStyle.allCases) { s in
                    Button(action: { controls.setMenuBarStyle(s) }) {
                        Label(s.label, systemImage: s == controls.menuBarStyle ? "checkmark" : "")
                    }
                }
                // De QUAL janela o número fala (UI-SPEC §12). Só aparece quando o estilo
                // ativo fala de uma janela — fixar janela no "custo de hoje" não é nada.
                if controls.menuBarStyle.usesWindow {
                    Divider()
                    Button(action: { controls.setMenuBarPin(nil) }) {
                        Label("Automática — a que aperta primeiro",
                              systemImage: controls.menuBarPin == nil ? "checkmark" : "")
                    }
                    ForEach(controls.menuBarPinOptions) { o in
                        // A fixada que sumiu continua NA LISTA, marcada e apagada: a barra
                        // caiu pra Automática sozinha, mas a escolha não foi jogada fora.
                        Button(action: { controls.setMenuBarPin(o.id) }) {
                            Label(o.available ? o.label : "\(o.label) — indisponível",
                                  systemImage: o.id == controls.menuBarPin?.id ? "checkmark" : "")
                        }
                        .disabled(!o.available)
                    }
                }
            }
            Menu("Tema") {
                ForEach(Theme.allCases) { t in
                    Button(action: { controls.setTheme(t) }) {
                        Label(t.label, systemImage: t == controls.theme ? "checkmark" : "")
                    }
                }
            }

            Divider()
            // O ORÇAMENTO. Este item é o ÚNICO lugar onde ele existe quando não existe — e é
            // por isso que ele não é um submenu com valores prontos: um teto é um número que
            // só o dono da fatura sabe, e oferecer "US$ 20 / US$ 50 / US$ 100" seria o app
            // chutando o bolso de alguém.
            //
            // O rótulo CARREGA o estado, como o do hook logo abaixo: com um teto definido, ele
            // diz qual é, e o usuário confere sem clicar. Sem teto, ele é um convite — e o
            // convite é discreto de propósito. Ele NÃO tem uma pista fantasma na tela pra
            // chamar atenção: uma pista de orçamento que aparece antes de existir um orçamento
            // seria o app afirmando um teto que ninguém pôs, que é a mesma família de mentira
            // do "0%" que não é zero.
            Button(
                controls.budgetUSD.map { "Orçamento: US$ \(Lane.cap($0)) por mês…" }
                    ?? "Definir um orçamento mensal…",
                action: controls.openBudgetPanel
            )

            Divider()
            // O hook do statusLine. O rótulo CARREGA o estado, porque este é o único item do
            // menu que fala de um arquivo que o app escreveu na casa do usuário — e ele tem
            // direito de saber disso sem clicar. "Quebrado" aparece em voz alta: significa que
            // a statusline dele não está sendo desenhada AGORA, e a culpa é nossa.
            switch controls.hook {
            case .ausente:
                Button("Conectar o Claude (instalar o hook)…", action: controls.openHookPanel)
            case .instalado:
                Button("Hook do statusLine: instalado…", action: controls.openHookPanel)
            case .quebrado:
                Button("Hook do statusLine: QUEBRADO…", action: controls.openHookPanel)
            case .indeciso:
                EmptyView()   // sem settings.json legível não há o que oferecer. Silêncio > chute.
            }

            Divider()
            // O aviso de 85% (UI-SPEC §7). Se o macOS barrou, o menu NÃO deixa um ✓ ligado
            // fingindo que avisa — ele conta o que houve e abre onde se conserta. Mesma
            // regra do "Abrir no login" logo abaixo: o menu nunca mostra um estado que mente.
            if controls.notificationsBlocked {
                Button("Avisos bloqueados no macOS…", action: controls.openNotificationSettings)
            } else {
                Button(action: controls.toggleNotifyAt85) {
                    Label("Avisar em 85%", systemImage: controls.notifyAt85 ? "checkmark" : "")
                }
            }

            // Só aparece se o sistema souber responder. Um toggle que não sabe o próprio
            // estado é pior que toggle nenhum.
            if let liga = controls.launchesAtLogin {
                Divider()
                Button(action: controls.toggleLaunchAtLogin) {
                    Label("Abrir no login", systemImage: liga ? "checkmark" : "")
                }
            }

            Divider()
            Button("Sair do MyTokens", action: controls.quit)
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.ink3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 14)
        .accessibilityLabel("Controles do MyTokens")
    }
}

// MARK: - O pulso do estado vazio
//
// Instrumento LIGADO, esperando. Não é spinner (spinner diz "estou travado"),
// é um sinal de vida a 2,4 s — o mesmo ritmo de uma respiração calma.
//
// É o único movimento do app que não carrega um bit de dado — e por isso é o
// único que o Reduce Motion pode matar inteiro. Sob Reduce Motion o `.pulse`
// resolve pra `nil`: o `on` vira `true` na hora e o ponto fica ACESO, parado.
// A informação (o instrumento está ligado) é a LUZ, não a oscilação dela.
//
// Pro VoiceOver ele não existe: quem diz "nada queimado ainda" é o veredito,
// em palavra. Um ponto laranja de 7 px não tem o que dizer.

struct EmptyPulse: View {
    @Environment(\.palette) private var p
    @State private var on = false

    var body: some View {
        Circle()
            .fill(p.ember)
            .frame(width: 7, height: 7)
            .opacity(on ? 1 : 0.25)
            .motion(.pulse, value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
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
