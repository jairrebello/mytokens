//  OKLCH.swift
//
//  O UI-SPEC e o bancada.css definem TODA a cor em oklch(). Duas opções
//  existiam: converter os valores na mão pra hex (e errar), ou ensinar o app
//  a falar oklch. A segunda é a única que deixa `Bancada.swift` ser uma cópia
//  literal do arquivo do Prisma — divergiu lá, divergiu aqui, e ninguém precisa
//  reconferir 30 hex à mão.
//
//  Matemática: Björn Ottosson, "A perceptual color space for image processing".
//  oklch → oklab → LMS → sRGB linear → sRGB gamma.

import SwiftUI

extension Color {
    /// Cor escrita como no CSS do Prisma: `oklch(0.165 0.006 60)`.
    /// - Parameters:
    ///   - l: lightness perceptual, 0...1
    ///   - c: croma, 0...~0.4
    ///   - h: matiz em graus
    ///   - alpha: opacidade
    init(oklch l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
        let (r, g, b) = oklchToSRGB(l: l, c: c, h: h)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// oklch → sRGB gamma-encoded (0...1, já clampado ao gamut).
func oklchToSRGB(l L: Double, c C: Double, h hDeg: Double) -> (Double, Double, Double) {
    let h = hDeg * .pi / 180
    let a = C * cos(h)
    let b = C * sin(h)

    // oklab → LMS (raiz cúbica)
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b

    let lms_l = l_ * l_ * l_
    let lms_m = m_ * m_ * m_
    let lms_s = s_ * s_ * s_

    // LMS → sRGB linear
    let rLin =  4.0767416621 * lms_l - 3.3077115913 * lms_m + 0.2309699292 * lms_s
    let gLin = -1.2684380046 * lms_l + 2.6097574011 * lms_m - 0.3413193965 * lms_s
    let bLin = -0.0041960863 * lms_l - 0.7034186147 * lms_m + 1.7076147010 * lms_s

    return (gammaEncode(rLin), gammaEncode(gLin), gammaEncode(bLin))
}

/// sRGB linear → sRGB com gamma, clampado. Fora do gamut a gente corta em vez
/// de fazer gamut-mapping: os valores do Prisma já estão todos dentro.
private func gammaEncode(_ x: Double) -> Double {
    let v = max(0, min(1, x))
    let encoded = v <= 0.0031308
        ? 12.92 * v
        : 1.055 * pow(v, 1 / 2.4) - 0.055
    return max(0, min(1, encoded))
}
