//  Brand.swift
//
//  A terceira direção: o CONSOLE — preto #0A0A0A, tudo monospace, red #FF2B2B.
//  É o visual dos apps DOWNLOADER e LISTENER OS do Jair, entrando aqui como
//  tema selecionável (norte-ux, "TEMA-BRAND"). O default continua o Bancada.
//
//  A REGRA DO TEMA: red em TUDO que fala — rótulo, barra, número, história.
//  É o visual dos apps de referência: red sobre preto, sem meio-termo. O que
//  diferencia dado de chrome aqui é GEOMETRIA e peso (trilho vs caps com
//  tracking), nunca matiz. E o alarme de estouro continua tendo voz própria:
//  ele sempre foi a hachura rompendo o limite do trilho — geometria — então
//  seguir red não o emudece.
//
//  `laneInkLive/laneInkCold/numberInk` existem pra isso: o tema declara a
//  tinta do dado na PALETA e nenhuma view decide sozinha. Texto corrido
//  (veredito, nomes, meta) segue a graduação de cinzas — red vibra demais
//  pra parágrafo; o resto é da marca.
//
//  Console é DARK-ONLY como o Terminal: um console claro é uma contradição.
//  E é OPACO — exceção consciente à vibrancy do popover: a identidade do
//  Bancada é o vidro; a DESTE tema é o console preto (norte-ux).

import SwiftUI

private extension Color {
    /// Hex sRGB, como a paleta do norte-ux escreve: `Color(hex: 0x0A0A0A)`.
    /// O Bancada fala oklch porque o CSS do Prisma fala oklch; o brand fala
    /// hex porque os screenshots dos apps do Jair falam hex. Cada fonte na
    /// língua dela — traduzir na mão é onde nasce o erro de um dígito.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// O chrome do CONSOLE: grid de fundo + vinheta. Só a janela grande o usa — em
/// 340 px de popover a grade não organiza nada, só faz ruído. O grid é fraco de
/// propósito (2,5% de branco): ele é a TEXTURA do console, não uma régua; se
/// desse pra alinhar dado nele, competiria com o eixo de verdade do bench.
public struct ConsoleChrome: View {
    public init() {}
    public var body: some View {
        ZStack {
            Canvas { ctx, size in
                let step: CGFloat = 24
                var path = Path()
                var x = step
                while x < size.width {
                    path.move(to: .init(x: x, y: 0))
                    path.addLine(to: .init(x: x, y: size.height))
                    x += step
                }
                var y = step
                while y < size.height {
                    path.move(to: .init(x: 0, y: y))
                    path.addLine(to: .init(x: size.width, y: y))
                    y += step
                }
                ctx.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 1)
            }
            // A vinheta escurece a BORDA, não o miolo: o dado continua no claro.
            RadialGradient(
                colors: [.clear, .black.opacity(0.35)],
                center: .center, startRadius: 260, endRadius: 720
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Palette {

    /// O RED de marca. Público porque o chrome de console (vinheta, foco) o
    /// referencia fora da paleta — mas nenhuma view pinta DADO com ele.
    public static let brandRed = Color(hex: 0xFF2B2B)   // 5.3:1 sobre #0A0A0A

    public static let brand = Palette(
        canvas:    Color(hex: 0x0A0A0A),
        surface:   Color(hex: 0x141414),
        surfaceHi: Color(hex: 0x181818),
        track:     Color(hex: 0x171717),
        line:      Color(hex: 0x2A2A2A),   // borda fina: inputs, trilho
        lineSoft:  Color(hex: 0x1A1A1A),   // divisor

        // a graduação de texto do norte-ux: primário, secundário, terciário —
        // e dois degraus interpolados pros papéis que a paleta já tinha.
        ink0: Color(hex: 0xEDEDED),
        ink1: Color(hex: 0xC4C4C4),
        ink2: Color(hex: 0x9A9A9A),
        ink3: Color(hex: 0x5C5C5C),
        ink4: Color(hex: 0x3A3A3A),

        // ember = o RED de marca: chrome E dado falam a mesma cor aqui. O que
        // separa os dois é geometria (rótulo caps vs trilho vs número), não
        // matiz — é o visual DOWNLOADER/LISTENER: red em cima de preto, tudo.
        emberCold: Color(hex: 0x9A9A9A),
        ember:     brandRed,
        // ESTOURO: continua sendo a hachura FORA do trilho — o alarme segue
        // sendo geometria; num tema todo red, é a ÚNICA coisa que resta pra ele.
        emberHot:  brandRed,
        emberGlow: Color(hex: 0xFF2B2B, alpha: 0.30),   // o cap vivo brilha red
        isDark: true,

        monoUI: true,
        console: true,

        // TINTA DE DADO: red. Vivo é o red cheio da marca; parado é um red
        // assentado — calor continua sendo brilho, só que dentro do vermelho.
        laneInkLive: brandRed,
        laneInkCold: Color(hex: 0xA82222),
        // E o NÚMERO também: "5%", "US$ 3,63", a SOMA — dado fala red.
        numberInk: brandRed
    )
}
