//  Bancada.swift
//
//  Os tokens da direção "Bancada". Cópia LITERAL de mockups/bancada.css —
//  os oklch() estão idênticos, dígito por dígito. docs/UI-SPEC.md tem o porquê
//  de cada um; aqui só mora o valor.
//
//  Dark e light são DUAS paletas escritas à mão pelo Prisma, não uma invertida.
//  É por isso que `Palette` é um struct com dois valores nomeados em vez de um
//  monte de `Color(light:dark:)` espalhado pelas views.

import SwiftUI

// MARK: - Paleta

public struct Palette: Sendable {
    // superfícies — preto QUENTE (60°). Preto-azulado é o SaaS de 2021.
    public let canvas: Color
    public let surface: Color
    public let surfaceHi: Color
    public let track: Color
    public let line: Color
    public let lineSoft: Color

    // tinta — bone. É a cor do DADO, não do texto.
    public let ink0: Color   // número principal
    public let ink1: Color   // número secundário
    public let ink2: Color   // rótulo
    public let ink3: Color   // unidade, rótulo apagado
    public let ink4: Color   // traço fantasma

    // ember — a ÚNICA matiz do app. Não significa perigo: significa calor.
    public let emberCold: Color  // quase cinza: medido, parado
    public let ember: Color      // vivo: queimando agora
    public let emberHot: Color   // ESTOURO. E só estouro.
    public let emberGlow: Color

    public let isDark: Bool

    // MARK: - Traços de tema
    //
    // O Console (tema brand) precisa dizer três coisas que Bancada e Terminal
    // nunca precisaram: que a UI inteira é mono, que o chrome fala a gramática
    // de console (glifos, grid, popover opaco), e que a tinta de DADO não é o
    // ember — porque lá o ember é RED, e red é MARCA, nunca estado de dado.
    // São `var` com default pra os temas existentes nem saberem que existem.

    /// SF Mono em TUDO — UI e números. Pesos acima de .medium são clampados:
    /// SF Mono bold engorda; medium é o "bold" do tema mono.
    public var monoUI: Bool = false

    /// A gramática de console: glifos de chrome (⌐ no header de grupo), grid
    /// de fundo na janela grande, vinheta, popover OPACO (exceção consciente à
    /// vibrancy — a identidade deste tema é o console preto, não o vidro).
    /// Liga tudo junto de propósito: é UMA identidade, não quatro toggles.
    public var console: Bool = false

    /// Tinta da pista quando o tema tem tinta PRÓPRIA de dado. `nil` = o ember
    /// é a tinta, como sempre foi. No Console o dado também fala red — a marca
    /// pinta tudo; o que separa dado de chrome lá é GEOMETRIA, não matiz.
    public var laneInkLive: Color?
    public var laneInkCold: Color?

    /// Tinta do NÚMERO medido (os "5%", "US$ 3,63", a SOMA). `nil` = a escada
    /// de inks de sempre (ink2→ink0 por calor). O Console põe red: o número É
    /// o dado, e lá o dado fala a cor da marca. O estouro (emberHot) e o
    /// fantasma (ink4) não passam por aqui — significado antes de estilo.
    public var numberInk: Color?

    /// A tinta que as views usam de fato. Um caminho só — nenhuma view decide
    /// sozinha se o tema separa dado de chrome.
    public var laneLive: Color { laneInkLive ?? ember }
    public var laneCold: Color { laneInkCold ?? emberCold }

    /// A tinta dos RÓTULOS de chrome — os caps com tracking ("JANELA", "FONTE",
    /// os headers de grupo, "SOMA", "HOJE"). No Console eles falam a língua da
    /// marca: red, como os "⌐ TARGET / CONFIG / QUEUE" dos apps do Jair. Rótulo
    /// é chrome, e chrome pode gritar; o VALOR ao lado continua em tinta de
    /// dado. Nos outros temas, o ink3 de sempre.
    public var labelInk: Color { console ? ember : ink3 }

    // MARK: - Fonte via paleta
    //
    // `.font(.ui(...))` era estático e servia enquanto todo tema usava as duas
    // famílias nos mesmos papéis. O Console quebra isso (mono em tudo), então a
    // fonte passa a sair da PALETA — mesmo canal do resto do vocabulário visual.

    /// Rótulo humano. SF Pro — ou SF Mono inteiro, se o tema é mono.
    public func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        monoUI ? .num(size, Self.monoWeight(weight)) : .ui(size, weight)
    }

    /// Número medido. Sempre mono; o tema mono só clampa o peso.
    public func num(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        monoUI ? .num(size, Self.monoWeight(weight)) : .num(size, weight)
    }

    private static func monoWeight(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .semibold, .bold, .heavy, .black: .medium
        default: w
        }
    }

    public static let dark = Palette(
        canvas:    Color(oklch: 0.165, 0.006, 60),
        surface:   Color(oklch: 0.205, 0.007, 60),
        surfaceHi: Color(oklch: 0.235, 0.008, 60),
        track:     Color(oklch: 0.265, 0.007, 60),
        line:      Color(oklch: 0.305, 0.008, 60),
        lineSoft:  Color(oklch: 0.255, 0.007, 60),
        ink0: Color(oklch: 0.955, 0.008, 80),
        ink1: Color(oklch: 0.780, 0.008, 80),
        ink2: Color(oklch: 0.590, 0.008, 80),
        ink3: Color(oklch: 0.455, 0.008, 80),
        ink4: Color(oklch: 0.360, 0.008, 80),
        emberCold: Color(oklch: 0.700, 0.035, 45),
        ember:     Color(oklch: 0.760, 0.130, 48),
        emberHot:  Color(oklch: 0.680, 0.195, 32),
        emberGlow: Color(oklch: 0.760, 0.130, 48, alpha: 0.20),
        isDark: true
    )

    /// Light NÃO é o dark invertido — é a segunda paleta do bancada.css.
    /// Repare que a tinta escurece e a croma do ember CAI de lightness pra
    /// sobreviver contra branco: inverter os canais teria dado um laranja neon.
    public static let light = Palette(
        canvas:    Color(oklch: 0.975, 0.004, 80),
        surface:   Color(oklch: 0.995, 0.002, 80),
        surfaceHi: Color(oklch: 0.945, 0.005, 80),
        track:     Color(oklch: 0.905, 0.006, 80),
        line:      Color(oklch: 0.855, 0.007, 80),
        lineSoft:  Color(oklch: 0.915, 0.006, 80),
        ink0: Color(oklch: 0.220, 0.010, 60),
        ink1: Color(oklch: 0.380, 0.010, 60),
        ink2: Color(oklch: 0.520, 0.009, 60),
        ink3: Color(oklch: 0.640, 0.008, 60),
        ink4: Color(oklch: 0.760, 0.007, 60),
        emberCold: Color(oklch: 0.560, 0.045, 45),
        ember:     Color(oklch: 0.580, 0.150, 42),
        emberHot:  Color(oklch: 0.530, 0.200, 30),
        emberGlow: Color(oklch: 0.580, 0.150, 42, alpha: 0.16),
        isDark: false
    )

    public static func forScheme(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

// MARK: - Injeção

public struct PaletteKey: EnvironmentKey {
    public static let defaultValue: Palette = .dark
}

extension EnvironmentValues {
    public var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Tipo
//
// Duas famílias, papéis FIXOS. Nunca trocar — é o que faz parecer instrumento.
//   grotesca = rótulo humano (o que a coisa é)
//   mono     = número        (o que a máquina mediu)

public enum T {
    public static let micro: CGFloat = 10   // rótulo caixa alta, tracking .09em
    public static let xs:    CGFloat = 11
    public static let sm:    CGFloat = 13   // corpo
    public static let md:    CGFloat = 15   // nome do provedor
    public static let lg:    CGFloat = 19   // número secundário
    public static let xl:    CGFloat = 26   // a % de cada pista
    public static let xxl:   CGFloat = 40
    public static let xxxl:  CGFloat = 54   // O VEREDITO. e só ele.
}

extension Font {
    /// Rótulo humano. SF Pro do sistema — não é fonte importada.
    public static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Número medido. SF Mono do sistema.
    /// `.monospacedDigit()` fica redundante aqui, mas é de graça e garante tnum
    /// mesmo se alguém trocar o design depois — número que treme de largura ao
    /// atualizar destrói a leitura de relance, que é o produto inteiro.
    public static func num(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
}

// MARK: - Espaço, raio
// Base 4: menor passo que o macOS respeita em @1x e @2x sem borrar.

public enum S {
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 16
    public static let s5: CGFloat = 24
    public static let s6: CGFloat = 32
    public static let s7: CGFloat = 48
    public static let s8: CGFloat = 64
}

/// Raio baixo. Instrumento tem canto vivo — e NADA arredonda um dado:
/// a pista é raio 0 porque a borda dura É a informação.
public enum R {
    public static let r0: CGFloat = 0   // pista, tinta
    public static let r1: CGFloat = 3   // chip, botão
    public static let r2: CGFloat = 6   // painel
    public static let r3: CGFloat = 10  // popover (única peça que flutua)
}

// MARK: - Movimento
//
// Anima ESTADO, nunca decoração. 60 fps ou não anima.
// As curvas do CSS viram mola de VERDADE onde faz sentido, e timing-curve
// onde o CSS já dizia a coisa certa (o dreno é uma expiração, não uma mola —
// mola quicaria, e nada aqui quica).

public enum Motion {
    /// número trocando de valor
    public static let tick = Animation.easeOut(duration: 0.14)

    /// hover, revelar
    public static let ui = Animation.easeOut(duration: 0.20)

    /// tinta avançando na pista. Mola crítica: assenta e PARA, sem overshoot —
    /// um dado que passa do valor e volta é um dado que mentiu por 80 ms.
    public static let state = Animation.spring(response: 0.42, dampingFraction: 1.0)

    /// O DRENO. 900 ms, mais LENTO que o avanço (420 ms), de propósito:
    /// encher é rotina, esvaziar é acontecimento. Se drenasse rápido, o alívio
    /// passava batido — e o alívio é o ponto.
    public static let drain = Animation.timingCurve(0.55, 0.00, 0.30, 1.00, duration: 0.90)

    /// "assenta e para" — o ease-out do CSS.
    public static let out = Animation.timingCurve(0.20, 0.70, 0.20, 1.00, duration: 0.42)
}
