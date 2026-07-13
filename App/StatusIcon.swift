import AppKit

/// O ícone da barra: uma PROVETA GRADUADA.
///
/// Desenho do Prisma (docs/UI-SPEC.md §9 + mockups/06-icone.html). Aqui só o motor.
///
/// É TEMPLATE IMAGE: só o alfa importa. O macOS pinta de preto na barra clara e de branco
/// na escura — dark/light sai de graça e não temos controle de cor, só de FORMA. Por isso
/// o estado é codificado em textura e silhueta, nunca em semáforo.
///
/// Desenhado por código (não PNG assado) porque o nível da tinta varia. `NSImage(size:flipped:)`
/// re-executa o handler por escala, então @1x e @2x saem nítidos do mesmo código.
enum StatusIcon {

    /// O que o ícone mostra. Regra do Prisma: UM provedor só — o de menor folga.
    /// Três provetas em 22 px não é informação, é sujeira.
    enum State: Equatable {
        /// Nenhuma fonte deu número. Contorno tracejado, zero tinta. Nunca um zero sólido.
        case noData
        /// O provedor NOS DEU o número (statusLine / rollout). Tinta sólida, topo com corte reto.
        case measured(level: Double)
        /// NÓS calculamos. Tinta reticulada, topo pontilhado.
        case derived(level: Double)
        /// ≥100%. Sólido + régua acima da boca — a única silhueta diferente do app.
        case overflow
        /// Quem parou fui eu, não a fonte. Contorno íntegro, tudo a 42% de alfa.
        case paused(State.Base)

        enum Base: Equatable { case noData, measured(Double), derived(Double), overflow }
    }

    // Geometria, em pontos, no espaço 22×22 do mockup (y cresce pra BAIXO).
    private enum G {
        static let canvas = NSSize(width: 22, height: 22)
        /// Contorno em coordenada .5 — em 22 px, meio pixel de erro vira cinza borrado
        /// e o ícone perde o corte reto, que é justamente o sinal de "medido".
        static let body = NSRect(x: 7.5, y: 3.5, width: 9, height: 15)
        static let corner: CGFloat = 2.4
        static let stroke: CGFloat = 1.1
        /// Tinta e topo em coordenada INTEIRA (por isso x:7 w:10, transbordando o contorno
        /// e sendo cortada pelo clip — é assim que o menisco encosta na parede sem antialiasing).
        static let inkX: CGFloat = 7
        static let inkW: CGFloat = 10
        static let meniscus: CGFloat = 1.7
        static let ticksX: (CGFloat, CGFloat) = (4, 6)
        static let ticksY: [CGFloat] = [8, 11, 14]
    }

    private static let ink = NSColor.black  // template: só o alfa conta

    static func image(for state: State) -> NSImage {
        let image = NSImage(size: G.canvas, flipped: true) { _ in
            switch state {
            case .paused(let base):
                // Ícone íntegro, só esmaecido. Diferente de "sem dado" (tracejado):
                // aqui a fonte está viva, quem pausou fui eu.
                draw(base: base, alpha: 0.42)
            case .noData:
                draw(base: .noData, alpha: 1)
            case .measured(let level):
                draw(base: .measured(level), alpha: 1)
            case .derived(let level):
                draw(base: .derived(level), alpha: 1)
            case .overflow:
                draw(base: .overflow, alpha: 1)
            }
            return true
        }
        // A linha que faz dark/light funcionar sozinho.
        image.isTemplate = true
        image.accessibilityDescription = describe(state)
        return image
    }

    // MARK: - desenho

    private static func draw(base: State.Base, alpha: CGFloat) {
        drawGraduations(alpha: alpha)

        let dashed: Bool
        switch base {
        case .noData: dashed = true
        default: dashed = false
        }
        drawBody(dashed: dashed, alpha: alpha)

        switch base {
        case .noData:
            break  // zero tinta. o vazio é a resposta.
        case .measured(let level):
            drawInk(level: level, stippled: false, dottedTop: false, alpha: alpha)
        case .derived(let level):
            drawInk(level: level, stippled: true, dottedTop: true, alpha: alpha)
        case .overflow:
            drawInk(level: 1, stippled: false, dottedTop: false, alpha: alpha)
            drawRuler(alpha: alpha)
        }
    }

    private static func drawGraduations(alpha: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = 1
        for y in G.ticksY {
            path.move(to: NSPoint(x: G.ticksX.0, y: y))
            path.line(to: NSPoint(x: G.ticksX.1, y: y))
        }
        ink.withAlphaComponent(0.55 * alpha).setStroke()
        path.stroke()
    }

    private static func drawBody(dashed: Bool, alpha: CGFloat) {
        let path = bodyPath()
        path.lineWidth = G.stroke
        if dashed {
            path.setLineDash([2, 1.8], count: 2, phase: 0)
        }
        ink.withAlphaComponent(0.55 * alpha).setStroke()
        path.stroke()
    }

    private static func bodyPath() -> NSBezierPath {
        NSBezierPath(roundedRect: G.body, xRadius: G.corner, yRadius: G.corner)
    }

    /// `level` 0...1, JÁ quantizado em degraus de 5% pelo chamador.
    private static func drawInk(level: Double, stippled: Bool, dottedTop: Bool, alpha: CGFloat) {
        let p = min(max(level, 0), 1)
        guard p > 0 else { return }

        // y cresce pra baixo: tinta sobe = topo desce de valor.
        let top = G.body.maxY - (CGFloat(p) * G.body.height)

        NSGraphicsContext.saveGraphicsState()
        bodyPath().addClip()  // a tinta transborda e a proveta corta. sem meio-pixel.

        // corpo da tinta (abaixo do menisco)
        let bodyInk = NSRect(x: G.inkX, y: top + 0.7, width: G.inkW, height: G.body.maxY - top)
        if stippled {
            drawStipple(in: bodyInk, alpha: alpha)  // reticulado = dado inferido
        } else {
            ink.withAlphaComponent(alpha).setFill()
            bodyInk.fill()
        }

        // o menisco: a faixa do topo. É ELE que diz "medido" (corte reto) ou "derivado" (pontilhado).
        let meniscus = NSRect(x: G.inkX, y: top, width: G.inkW, height: G.meniscus)
        ink.withAlphaComponent(alpha).setFill()
        if dottedTop {
            // topo pontilhado: 2 on / 2 off. Sobrevive a 22 px; um tracejado fino viraria papa.
            var x = meniscus.minX
            while x < meniscus.maxX {
                NSRect(x: x, y: meniscus.minY, width: 2, height: meniscus.height).fill()
                x += 4
            }
        } else {
            meniscus.fill()  // corte reto = fato
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    /// Reticulado: xadrez de 1 pt. Em 22 px um hachurado fino vira cinza; o xadrez
    /// continua LEGÍVEL como "não-sólido", que é a informação inteira.
    private static func drawStipple(in rect: NSRect, alpha: CGFloat) {
        ink.withAlphaComponent(alpha).setFill()
        var y = rect.minY.rounded(.down)
        while y < rect.maxY {
            var x = rect.minX.rounded(.down)
            while x < rect.maxX {
                if (Int(x) + Int(y)).isMultiple(of: 2) {
                    NSRect(x: x, y: y, width: 1, height: 1).intersection(rect).fill()
                }
                x += 1
            }
            y += 1
        }
    }

    /// A régua acima da boca. Estourou. Não pisca — piscar é o semáforo de quem não tem
    /// cor disponível. A resposta é esta silhueta, parada, até você resolver.
    private static func drawRuler(alpha: CGFloat) {
        ink.withAlphaComponent(alpha).setFill()
        NSRect(x: 5, y: 1, width: 12, height: 1).fill()
        for x in stride(from: CGFloat(6), through: 16, by: 5) {
            NSRect(x: x, y: 0, width: 1, height: 1).fill()
        }
    }

    // MARK: - quantização

    /// Degraus de 5% (20 níveis). 1% são 0,15 px — invisível, e ainda forçaria repaint
    /// a cada evento de disco. O degrau é performance E honestidade visual.
    static func quantize(percent: Double) -> Double {
        let clamped = min(max(percent, 0), 100)
        return (clamped / 5).rounded() * 5 / 100
    }

    /// O VOCABULÁRIO É UM SÓ. A proveta dizia "Limite estourado" e "Sem dado de uso"
    /// enquanto a pista, a três centímetros dali, dizia "Passou do teto" e "sem dado
    /// local". Duas palavras pro mesmo fato é o começo de duas verdades — e pra quem
    /// navega de VoiceOver, a barra e a janela viram dois apps diferentes.
    private static func describe(_ state: State) -> String {
        switch state {
        case .noData: "Sem dado local de uso"
        case .measured(let l): "Uso medido: \(Int(l * 100))%"
        case .derived(let l): "Uso estimado: \(Int(l * 100))%"
        case .overflow: "Passou do teto"
        case .paused: "Monitoramento pausado"
        }
    }
}
