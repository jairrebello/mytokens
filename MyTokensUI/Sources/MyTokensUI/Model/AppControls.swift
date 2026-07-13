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

    public var togglePause: () -> Void
    public var toggleLaunchAtLogin: () -> Void
    public var setTheme: (Theme) -> Void
    public var setMenuBarStyle: (MenuBarStyle) -> Void
    public var quit: () -> Void

    public init(
        isPaused: Bool = false,
        launchesAtLogin: Bool? = nil,
        theme: Theme = .bancada,
        menuBarStyle: MenuBarStyle = .iconOnly,
        togglePause: @escaping () -> Void = {},
        toggleLaunchAtLogin: @escaping () -> Void = {},
        setTheme: @escaping (Theme) -> Void = { _ in },
        setMenuBarStyle: @escaping (MenuBarStyle) -> Void = { _ in },
        quit: @escaping () -> Void = {}
    ) {
        self.isPaused = isPaused
        self.launchesAtLogin = launchesAtLogin
        self.theme = theme
        self.menuBarStyle = menuBarStyle
        self.togglePause = togglePause
        self.toggleLaunchAtLogin = toggleLaunchAtLogin
        self.setTheme = setTheme
        self.setMenuBarStyle = setMenuBarStyle
        self.quit = quit
    }
}
