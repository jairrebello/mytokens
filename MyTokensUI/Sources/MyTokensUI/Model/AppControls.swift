//  AppControls.swift
//
//  Os controles do APP (não dos dados): pausar, abrir no login, sair.
//
//  Eles moram aqui, e não soltos no MyTokensApp, porque a APARÊNCIA de um controle é
//  desenho — e desenho é deste pacote. O que o app entrega são os verbos; onde eles ficam
//  na tela, e com que peso, é decisão do sistema visual.
//
//  Por que existem: um app de barra de menu sem saída visível é um app que se instala e
//  não se desinstala. O andaime de teste tinha um botão "Sair"; quando ele morreu, o único
//  jeito de fechar o MyTokens virou `pkill`. Isso não é minimalismo, é um buraco.

import Foundation

public struct AppControls {
    public var isPaused: Bool
    /// `nil` = o sistema não sabe dizer (app rodando fora de /Applications, por exemplo).
    /// A opção some do menu em vez de mentir um estado.
    public var launchesAtLogin: Bool?
    /// O tema em vigor. O menu marca qual está ativo.
    public var theme: Theme
    /// O que a barra mostra ao lado da proveta.
    public var menuBarStyle: MenuBarStyle
    /// De QUAL janela a barra fala: `nil` = Automática, a que aperta primeiro (§12).
    public var menuBarPin: MenuBarPin?
    /// As janelas fixáveis AGORA — mais a fixada que sumiu, marcada indisponível.
    /// Quem monta a lista é o modelo, do dashboard vivo; o menu só desenha.
    public var menuBarPinOptions: [MenuBarPinOption]
    /// O hook do statusLine — a única fonte do "quanto RESTA" do Claude, e a única coisa que
    /// o app escreve na casa do usuário.
    ///
    /// Ele precisa estar NO MENU, e não só no botão "conectar" da pista, por um motivo que só
    /// aparece quando tudo dá certo: o botão "conectar" só existe em pista SEM TINTA. Com o
    /// hook são e o número chegando, a pista tem tinta — e aí não sobra porta nenhuma pra
    /// desinstalar o que a gente instalou. Instalador sem desinstalador alcançável é uma
    /// armadilha, mesmo quando a armadilha é reversível por um `rm`.
    public enum HookState: Sendable, Equatable {
        case ausente
        case instalado
        /// Aponta pra nós e está MORTO. A statusline do usuário não está sendo desenhada agora.
        case quebrado
        /// Não dá pra opinar (settings.json ausente ou ilegível).
        case indeciso
    }

    public var hook: HookState
    /// Abre o painel do hook: o diff exato, e o verbo que couber ao estado (instalar,
    /// reinstalar, desinstalar). É o MESMO painel do botão "conectar" — uma porta a mais
    /// pro mesmo cômodo, não um segundo cômodo.
    public var openHookPanel: () -> Void

    /// O teto de gasto mensal, em US$. `nil` = NÃO EXISTE orçamento.
    ///
    /// E "não existe" não é "zero". Sem teto não há pista de orçamento na tela — não há uma
    /// pista vazia esperando um número, não há "US$ 0 de US$ 0". O menu é o único lugar onde
    /// o orçamento aparece antes de existir, e lá ele aparece como convite, não como fato.
    public var budgetUSD: Decimal?
    /// Abre o painel do orçamento: digitar, mudar, ou APAGAR.
    ///
    /// Apagar é obrigatório, e é obrigatório no MESMO painel — não numa nota de rodapé, não
    /// num "para remover, edite o plist". Um app que deixa você definir e não deixa desfazer
    /// é uma armadilha, mesmo quando a armadilha é reversível por quem sabe onde mexer. Pelo
    /// mesmo motivo o painel do hook do statusLine tem o botão de desinstalar do lado do de
    /// instalar: quem instala tem o dever de oferecer a saída, no lugar onde entrou.
    public var openBudgetPanel: () -> Void

    /// Avisar quando uma janela cruza 85% (UI-SPEC §7). Nasce ligado.
    public var notifyAt85: Bool
    /// O macOS BARROU os avisos. Quando isto é `true`, o menu para de oferecer o toggle e
    /// passa a dizer onde consertar — um ✓ ligado que não avisa nada é uma mentira de UI,
    /// e é a mesma família de mentira do "0%" que não é zero.
    public var notificationsBlocked: Bool

    public var togglePause: () -> Void
    public var toggleLaunchAtLogin: () -> Void
    public var setTheme: (Theme) -> Void
    public var setMenuBarStyle: (MenuBarStyle) -> Void
    /// `nil` volta pra Automática. Um id que não está no dashboard é ignorado pelo modelo.
    public var setMenuBarPin: (String?) -> Void
    public var toggleNotifyAt85: () -> Void
    public var openNotificationSettings: () -> Void
    public var quit: () -> Void

    public init(
        isPaused: Bool = false,
        launchesAtLogin: Bool? = nil,
        theme: Theme = .bancada,
        menuBarStyle: MenuBarStyle = .iconOnly,
        menuBarPin: MenuBarPin? = nil,
        menuBarPinOptions: [MenuBarPinOption] = [],
        hook: HookState = .indeciso,
        openHookPanel: @escaping () -> Void = {},
        budgetUSD: Decimal? = nil,
        openBudgetPanel: @escaping () -> Void = {},
        notifyAt85: Bool = true,
        notificationsBlocked: Bool = false,
        togglePause: @escaping () -> Void = {},
        toggleLaunchAtLogin: @escaping () -> Void = {},
        setTheme: @escaping (Theme) -> Void = { _ in },
        setMenuBarStyle: @escaping (MenuBarStyle) -> Void = { _ in },
        setMenuBarPin: @escaping (String?) -> Void = { _ in },
        toggleNotifyAt85: @escaping () -> Void = {},
        openNotificationSettings: @escaping () -> Void = {},
        quit: @escaping () -> Void = {}
    ) {
        self.isPaused = isPaused
        self.launchesAtLogin = launchesAtLogin
        self.theme = theme
        self.menuBarStyle = menuBarStyle
        self.menuBarPin = menuBarPin
        self.menuBarPinOptions = menuBarPinOptions
        self.hook = hook
        self.openHookPanel = openHookPanel
        self.budgetUSD = budgetUSD
        self.openBudgetPanel = openBudgetPanel
        self.notifyAt85 = notifyAt85
        self.notificationsBlocked = notificationsBlocked
        self.togglePause = togglePause
        self.toggleLaunchAtLogin = toggleLaunchAtLogin
        self.setTheme = setTheme
        self.setMenuBarStyle = setMenuBarStyle
        self.setMenuBarPin = setMenuBarPin
        self.toggleNotifyAt85 = toggleNotifyAt85
        self.openNotificationSettings = openNotificationSettings
        self.quit = quit
    }
}
