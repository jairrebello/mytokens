// Parser de timestamp ISO-8601 UTC.
//
// Por que não ISO8601DateFormatter: ele é uma classe pesada, não é Sendable, e custa
// ~2µs por chamada. São 93.790 linhas assistant a cada scan completo — o formatter
// sozinho viraria uma fatia visível do orçamento de 200ms. O formato no disco é fixo
// ("2026-07-06T12:23:58.036Z"), então parsear na mão é exato e ~50x mais barato.
// Formato inesperado cai no formatter de verdade — correção antes de velocidade.

import Foundation

public enum ISO8601 {
    /// Aceita YYYY-MM-DDTHH:MM:SS(.sss)?(Z|±HH:MM). Fora disso, delega.
    public static func date(_ s: String) -> Date? {
        if let d = fast(s) { return d }
        return fallback(s)
    }

    private static func fast(_ s: String) -> Date? {
        let u = Array(s.utf8)
        guard u.count >= 20, u[4] == 0x2D, u[7] == 0x2D, u[10] == 0x54,
              u[13] == 0x3A, u[16] == 0x3A
        else { return nil }

        func num(_ i: Int, _ n: Int) -> Int? {
            var v = 0
            for k in i..<(i + n) {
                let c = u[k]
                guard c >= 0x30, c <= 0x39 else { return nil }
                v = v * 10 + Int(c - 0x30)
            }
            return v
        }

        guard let year = num(0, 4), let month = num(5, 2), let day = num(8, 2),
              let hour = num(11, 2), let minute = num(14, 2), let second = num(17, 2)
        else { return nil }

        var idx = 19
        var frac = 0.0
        if idx < u.count, u[idx] == 0x2E {  // "."
            idx += 1
            var scale = 0.1
            while idx < u.count, u[idx] >= 0x30, u[idx] <= 0x39 {
                frac += Double(u[idx] - 0x30) * scale
                scale /= 10
                idx += 1
            }
        }

        // Fuso. Só Z e ±HH:MM — o disco só emite Z, mas custa 4 linhas tolerar o resto.
        var offset = 0
        if idx < u.count {
            switch u[idx] {
            case 0x5A:  // Z
                offset = 0
            case 0x2B, 0x2D:  // + -
                let sign = u[idx] == 0x2B ? 1 : -1
                guard u.count >= idx + 6, let oh = num(idx + 1, 2), let om = num(idx + 4, 2)
                else { return nil }
                offset = sign * (oh * 3600 + om * 60)
            default:
                return nil
            }
        }

        let days = daysFromCivil(year: year, month: month, day: day)
        let secs = Double(days * 86_400 + hour * 3600 + minute * 60 + second - offset)
        return Date(timeIntervalSince1970: secs + frac)
    }

    /// Howard Hinnant, days_from_civil. Dias desde 1970-01-01, calendário proléptico.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private static func fallback(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
