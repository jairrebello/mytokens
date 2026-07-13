//  Verdict.swift
//
//  A RESPOSTA. O usuário abre o app com UMA pergunta na cabeça:
//    "Posso continuar trabalhando, ou vou bater no limite?"
//  Tudo que não responde isso em 2 segundos é ruído. Isto responde ANTES de
//  qualquer pista — sem clique, sem scroll.
//
//  TEMPO > TOKEN: "fecha a janela em 86%" vale mais que "47,3k tokens". Token é
//  a unidade da máquina; tempo e fração são a unidade do humano. O número cru
//  existe, mas nunca como resposta primária.
//
//  COPY: as headlines e as frases vêm dos mockups do Prisma (01, 03, 04, 05),
//  literalmente. As marcadas «VITRAL» eu escrevi porque o mockup não cobria o
//  caso — estão em revisão com ele. Copy é dele, não minha.

import MyTokensCore
import Foundation

public struct Verdict: Sendable, Equatable {
    public let headline: String
    /// Frase com os fatos. Os trechos entre ** viram peso — é o único markup.
    public let detail: String
    public let heat: Heat
    /// A pista que apertou. `nil` quando não há tinta em lugar nenhum.
    public let tightestID: String?

    public static func of(_ snap: Dashboard, now: Date = Date()) -> Verdict {

        // O RESET. Merece respiro visual: é alívio, e alívio é o ponto.
        if let resetID = snap.justReset,
           let lane = snap.lanes.first(where: { $0.id == resetID }) {
            return Verdict(
                headline: "Janela nova.",
                detail: "A janela de \(lane.windowLabel) do **\(lane.provider.displayName)** zerou. "
                      + "Cinco horas inteiras pela frente.",
                heat: .idle,
                tightestID: lane.id
            )
        }

        // SEM TINTA EM LUGAR NENHUM. Aqui moram DOIS estados que é fácil — e grave —
        // confundir, porque na tela eles são idênticos: nenhuma pista tem tinta.
        //
        //   (a) não teve GASTO          → "nada queimado ainda"
        //   (b) teve gasto, falta LIMITE → "gastei, mas não sei quanto sobra"
        //
        // Gasto vem do disco: a gente SABE. Limite vem do provedor: sem o hook do
        // statusLine (Claude) ou sem snapshot válido no rollout (Codex), a gente NÃO SABE.
        // Dizer "nada queimado" com US$ 135 no disco não é um bug de copy — é o app
        // mentindo exatamente no eixo que ele existe pra proteger.
        guard let t = snap.tightest, let used = t.used, used > 0 else {
            let found = snap.discovered.map(\.displayName)
            let list = found.count >= 2
                ? "\(found.dropLast().joined(separator: ", ")) e \(found.last!)"
                : (found.first ?? "nada")

            // (b) — houve gasto, mas nenhum provedor publicou o restante. «VITRAL»
            if snap.todayCostUSD > 0 {
                return Verdict(
                    headline: "Não sei quanto sobra.",
                    detail: "Hoje você queimou o equivalente a **\(Self.usd(snap.todayCostUSD))** "
                          + "em API — isso eu leio do disco. Quanto **resta** da sua cota, "
                          + "nenhum provedor publicou: sem o hook do statusLine, o Claude não "
                          + "conta o restante, e o Codex está sem janela válida no rollout.",
                    heat: .idle,
                    tightestID: nil
                )
            }

            // (a) — o primeiro boot de verdade. Não é pedido de configuração: é a prova
            // de que o app já sabe onde procurar. Compra confiança no segundo 1.
            return Verdict(
                headline: "Nada queimado ainda.",
                detail: found.isEmpty
                    ? "Ainda não achei nenhum provedor no disco."     // «VITRAL»
                    : "Achei o **\(list)** no disco. Nenhuma sessão hoje, "
                    + "então as pistas estão limpas. Assim que você mandar o primeiro "
                    + "prompt, a tinta aparece aqui — **sem configurar nada**.",
                heat: .idle,
                tightestID: nil
            )
        }

        let janela = "janela de \(t.windowLabel) do \(t.provider.displayName)"

        switch t.heat {
        case .over:
            // «VITRAL» — o mockup não escreveu o caso de estouro.
            return Verdict(
                headline: "Passou do teto.",
                detail: "A **\(janela)** estourou. Só volta a andar quando ela virar, "
                      + "**\(t.displayReset.map { $0.replacingOccurrences(of: "zera ", with: "às ") } ?? "no reset")**.",
                heat: .over,
                tightestID: t.id
            )

        case .high:
            // A frase muda e o número engorda. A TELA NÃO FICA VERMELHA.
            var d = "No ritmo dos últimos 20 min, a **\(janela)** encosta no teto "
            if let hit = t.hitsCapAt(now: now) {
                d += "às **\(Self.hm(hit))**"
                if let reset = t.resetsAt {
                    let mins = Int(reset.timeIntervalSince(hit) / 60)
                    if mins > 0 { d += " — **\(mins) min antes** de virar" }
                }
                d += ". "
            } else {
                d += "antes de virar. "
            }
            d += "Dá pra fechar o que está aberto; não dá pra abrir frente nova."
            return Verdict(headline: "Aperta o passo.", detail: d, heat: .high, tightestID: t.id)

        default:
            var d = "O teto que aperta é a **\(janela)**."
            if let proj = t.projected {
                d += " No ritmo dos últimos 20 min ela fecha em **\(Int(proj.rounded()))%** "
                   + "— sobra folga, mas não sobra para dobrar o ritmo."
            } else if let reset = t.displayReset {
                d += " Está em **\(t.displayValue)** e \(reset)."
            }
            return Verdict(headline: "Dá pra continuar.", detail: d, heat: t.heat, tightestID: t.id)
        }
    }

    /// "US$ 135,87" — vírgula decimal, que é como o pt-BR lê dinheiro.
    static func usd(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        let s = f.string(from: d as NSDecimalNumber) ?? "\(d)"
        return "US$ \(s)"
    }

    static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

extension Lane {
    /// "5 h" a partir de "Claude · 5 h"
    var windowLabel: String {
        title.split(separator: "·").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? title
    }

    /// Quando a tinta encosta em 100%, no ritmo atual. É o relógio do aperto.
    func hitsCapAt(now: Date = Date()) -> Date? {
        guard let used, let burn = burnRatePerHour, burn > 0, used < 100 else { return nil }
        let hours = (100 - used) / burn
        let hit = now.addingTimeInterval(hours * 3600)
        // Só interessa se ele chega ANTES da janela virar — senão não é aperto.
        guard let reset = resetsAt, hit < reset else { return nil }
        return hit
    }

    /// "0,86× a janela" — ritmo relativo. Abaixo de 1 você chega inteiro no fim.
    var paceLabel: String? {
        guard let proj = projected else { return nil }
        return String(format: "%.2f× a janela", proj / 100).replacingOccurrences(of: ".", with: ",")
    }

    /// "+14 pts" / "−24 pts". Folga positiva = você gasta mais devagar que o relógio.
    var slackLabel: String? {
        guard let s = slackPoints else { return nil }
        let sign = s >= 0 ? "+" : "−"
        return "\(sign)\(Int(abs(s).rounded())) pts"
    }
}
