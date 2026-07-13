//  Hatch.swift
//
//  O RETICULADO. Convenção cartográfica de "inferido", com 300 anos de uso:
//  área não-sólida = dado não-sólido. Não precisa de legenda pra ser SENTIDO;
//  a legenda existe pra ser confirmada.
//
//  Nota de implementação: o CSS faz isto com `repeating-linear-gradient`. Em
//  SwiftUI não existe fill com padrão, e a saída óbvia (HStack de Rectangles)
//  gera N views por pista e derruba o 60fps quando a barra anima.
//
//  Aqui é um Canvas: UM comando de desenho, listras em coordenada ABSOLUTA a
//  partir da origem da pista. Isso importa — as listras ficam paradas enquanto
//  a máscara de largura cresce. Se elas fossem relativas à largura da tinta,
//  o padrão escorreria durante a animação e o olho leria movimento onde não há.

import SwiftUI

/// Listras 1 px on / 3 px off. O `phase` desloca o padrão pra que a tinta
/// reticulada de um trecho composto continue o mesmo grid do trecho medido, em
/// vez de recomeçar do zero e criar uma emenda falsa.
///
/// A listra é sempre PERPENDICULAR ao sentido em que a tinta cresce. Na pista a
/// tinta anda pra direita, então a listra é vertical; na coluna do trilho de 30
/// dias ela SOBE, e a listra deita. Não é gosto: listra paralela ao avanço vira
/// um cabo de vassoura que o olho lê como uma linha só — e o reticulado só
/// significa "estimado" enquanto ele se lê como TEXTURA.
///
/// No modo deitado o grid ancora na BASE, não no topo: a coluna cresce pra cima,
/// e um padrão preso ao topo escorreria a cada centavo novo. Listra que se mexe
/// sozinha é movimento sem dado — o pecado do §6.
struct Hatch: View {
    var color: Color
    var on: CGFloat = 1
    var off: CGFloat = 3
    var phase: CGFloat = 0
    var horizontal: Bool = false

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            guard !horizontal else {
                var y = size.height - on
                while y > -on {
                    ctx.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: on)),
                        with: .color(color)
                    )
                    y -= on + off
                }
                return
            }
            var x = -phase.truncatingRemainder(dividingBy: on + off)
            while x < size.width {
                ctx.fill(
                    Path(CGRect(x: x, y: 0, width: on, height: size.height)),
                    with: .color(color)
                )
                x += on + off
            }
        }
        .drawingGroup()   // uma camada só: a pista inteira vira uma textura
        // A textura é um CANAL, não um conteúdo: ela diz "estimado" pro olho, e a
        // frase da pista já diz "estimado" pro ouvido. Um elemento acessível aqui
        // seria um retângulo sem nome no meio da leitura.
        .accessibilityHidden(true)
    }
}

/// Hachura diagonal a 135°. Usada em duas coisas MUITO diferentes, de propósito
/// com a mesma gramática: a faixa de incerteza (piso–teto) e o transbordo.
/// As duas dizem "isto não é fato". A cor é que diz qual dos dois.
struct DiagonalHatch: View {
    var color: Color
    var on: CGFloat = 1
    var gap: CGFloat = 5

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let step = on + gap
            let reach = size.width + size.height
            var d: CGFloat = -size.height
            while d < reach {
                var p = Path()
                p.move(to: CGPoint(x: d, y: 0))
                p.addLine(to: CGPoint(x: d + size.height, y: size.height))
                ctx.stroke(p, with: .color(color), lineWidth: on)
                d += step
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)   // ornamento: a faixa e o transbordo já estão na fala
    }
}
