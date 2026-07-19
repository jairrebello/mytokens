//  Brand.swift
//
//  A terceira direção: o CONSOLE — preto #0A0A0A, tudo monospace, red #FF2B2B.
//  É o visual dos apps DOWNLOADER e LISTENER OS do Jair, entrando aqui como
//  tema selecionável (norte-ux, "TEMA-BRAND"). O default continua o Bancada.
//
//  A REGRA QUE SALVA O TEMA: red é CHROME — título, botão, badge, foco,
//  seleção. Red NUNCA é estado de dado. A tinta de dado é #EDEDED, sempre; o
//  único red permitido perto de um dado é o excedente ≥100%, que já é
//  geometria fora do trilho (o alarme é a hachura rompendo o limite, não a
//  cor). Se red virasse tinta, o app inteiro gritaria e o alarme ficava mudo.
//
//  Por isso este tema é o motivo de `laneInkLive/laneInkCold` existirem na
//  paleta: aqui o slot `ember` carrega o red DE MARCA (o "conectar", o pulso
//  do vazio, a seleção do dia) — e as pistas pintam com bone, não com ele.
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

        // ember = o RED de marca, e ele só alcança CHROME: o "conectar", o
        // pulso do estado vazio, a seleção. As pistas nem o veem — a tinta
        // delas sai de laneInk* logo abaixo.
        emberCold: Color(hex: 0x9A9A9A),
        ember:     brandRed,
        // ESTOURO: o único red que encosta em dado — e ele já mora FORA do
        // trilho, como hachura. O alarme é geometria; a cor só o assina.
        emberHot:  brandRed,
        emberGlow: Color(hex: 0xEDEDED, alpha: 0.22),   // o brilho do cap vivo é do feixe, não do red
        isDark: true,

        monoUI: true,
        console: true,

        // TINTA DE DADO: #EDEDED. NUNCA red. Calor continua sendo BRILHO,
        // como no Terminal: parado é um bone mais apagado, vivo é o cheio.
        laneInkLive: Color(hex: 0xEDEDED),
        laneInkCold: Color(hex: 0xC9C9C9)
    )
}
