//  Theme.swift
//
//  O tema é ESCOLHA do usuário — a única coisa neste app que é preferência e não
//  significado. Tudo o mais (a textura, o peso, o ember) carrega informação e não se
//  troca. O tema troca só o VOCABULÁRIO visual: as mesmas regras, ditas em bone ou em
//  fósforo. Um tema que mudasse o SIGNIFICADO de algo seria um bug, não uma opção.

import SwiftUI

public enum Theme: String, CaseIterable, Sendable, Identifiable {
    /// A direção original: bone sobre preto quente. Segue o claro/escuro do sistema.
    case bancada
    /// Fósforo verde sobre vidro preto. Um VT220 no escuro. Sempre escuro.
    case terminal
    /// O console da marca: preto #0A0A0A, tudo mono, red como chrome.
    /// O visual dos apps do Jair (norte-ux, "TEMA-BRAND"). Sempre escuro.
    case brand

    public var id: String { rawValue }

    /// O nome que aparece no menu. pt-BR, como todo texto do app.
    public var label: String {
        switch self {
        case .bancada: "Bancada"
        case .terminal: "Terminal"
        case .brand: "Console"
        }
    }

    /// A paleta deste tema, dado o esquema do sistema.
    ///
    /// O Bancada RESPEITA o claro/escuro do sistema (são duas paletas escritas à mão). O
    /// Terminal o IGNORA: fósforo sobre papel branco não é terminal, é contradição. Cada
    /// tema decide sozinho se o esquema do sistema significa algo pra ele — é aqui.
    public func palette(for scheme: ColorScheme) -> Palette {
        switch self {
        case .bancada:  .forScheme(scheme)
        case .terminal: .terminal
        case .brand:    .brand   // console claro não existe; o esquema não o alcança
        }
    }
}

// MARK: - Persistência + injeção

public struct ThemeStore {
    /// A chave no UserDefaults. Namespaced pra não colidir com nada do sistema.
    public static let key = "mytokens.theme"

    public static var current: Theme {
        get {
            (UserDefaults.standard.string(forKey: key)).flatMap(Theme.init(rawValue:)) ?? .bancada
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

/// Aplica um tema explícito. É o que o app usa: ele SABE qual tema o usuário escolheu.
public struct ThemedModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let theme: Theme

    public func body(content: Content) -> some View {
        content.environment(\.palette, theme.palette(for: scheme))
    }
}

extension View {
    /// Injeta a paleta de um tema específico.
    public func theme(_ theme: Theme) -> some View { modifier(ThemedModifier(theme)) }

    /// Compat: `.bancada()` continua existindo e significa "o tema Bancada", pra as telas
    /// e a galeria que ainda não passam tema explícito não quebrarem.
    public func bancada() -> some View { theme(.bancada) }
}

extension ThemedModifier {
    init(_ theme: Theme) { self.theme = theme }
}
