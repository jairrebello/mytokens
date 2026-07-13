//  Terminal.swift
//
//  A segunda direção: fósforo verde sobre vidro preto. Um VT220 ligado no escuro.
//
//  Isto parece violar a lei do Prisma ("ember é a ÚNICA matiz; a tensão sobe por peso,
//  não por cor; sem semáforo") — e não viola, por um motivo que só o terminal permite:
//
//    num CRT de fósforo, o verde NÃO É UM STATUS. É a tinta de TUDO. Se o dado inteiro é
//    verde, "verde" deixa de significar e vira só o meio — exatamente o papel do bone no
//    Bancada. O que carrega significado continua sendo o MESMO de sempre:
//
//      • parado / medido  → fósforo APAGADO (verde escuro, sem brilho)
//      • queimando agora  → fósforo ACESO   (verde claro + glow) — calor é BRILHO, não cor
//      • ESTOURO          → ÂMBAR           — a única fuga do verde, e só ela
//
//  O âmbar não é decoração: é o segundo fósforo do CRT (P3), a cor que os terminais de
//  verdade usavam pro alarme. Ele ocupa exatamente o lugar do `emberHot` do Bancada — a
//  regra "só o estouro ganha uma segunda cor" sobrevive intacta, só troca de matiz.
//
//  Terminal é DARK-ONLY de propósito: um terminal claro é uma contradição. `Theme` deixa
//  este tema ignorar o esquema do sistema (ver Theme.swift). Não é limitação — é a fonte.

import SwiftUI

extension Palette {

    /// Fósforo P1 (verde) sobre vidro. Matiz base 150° pra tudo que é "tinta"; 78° (âmbar)
    /// só no estouro. As lightnesses sobem em degraus perceptuais — é o brilho do feixe.
    public static let terminal = Palette(
        // vidro preto com o menor tint verde possível — um CRT desligado não é preto neutro.
        canvas:    Color(oklch: 0.145, 0.014, 150),
        surface:   Color(oklch: 0.175, 0.018, 150),
        surfaceHi: Color(oklch: 0.205, 0.020, 150),
        track:     Color(oklch: 0.250, 0.025, 150),   // o trilho vazio da pista: scanline apagada
        line:      Color(oklch: 0.320, 0.035, 150),
        lineSoft:  Color(oklch: 0.260, 0.028, 150),

        // a tinta: o feixe do fósforo em cinco intensidades. ink0 é o texto vivo do cursor.
        //
        // O L do topo fica em 0.85, não 0.92: acima disso o verde perde saturação e vira
        // branco-esverdeado — deixa de parecer fósforo. A croma sobe junto pra segurar a
        // "verdice". Verde é onde o sRGB tem mais gamut, então dá pra saturar sem estourar.
        ink0: Color(oklch: 0.855, 0.235, 150),
        ink1: Color(oklch: 0.755, 0.205, 150),
        ink2: Color(oklch: 0.635, 0.165, 150),
        ink3: Color(oklch: 0.505, 0.120, 150),
        ink4: Color(oklch: 0.390, 0.085, 150),

        // calor = brilho, não matiz. Parado é fósforo apagado; vivo é o feixe no talo.
        emberCold: Color(oklch: 0.560, 0.100, 150),
        ember:     Color(oklch: 0.870, 0.250, 150),
        // ESTOURO: âmbar P3. A única cor não-verde do tema, e só aqui.
        emberHot:  Color(oklch: 0.800, 0.165, 78),
        emberGlow: Color(oklch: 0.870, 0.250, 150, alpha: 0.30),
        isDark: true
    )
}
