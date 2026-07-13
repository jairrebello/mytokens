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
                detail: "A janela de \(lane.windowLabel) do **\(lane.ownerName)** zerou. "
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

        let janela = t.owner.subject(window: t.windowLabel)

        // O ORÇAMENTO GANHOU O VEREDITO.
        //
        // Ele compete como qualquer pista (ver `Dashboard.tightest`), mas a frase NÃO pode ser
        // a mesma: as outras falam de uma porta que fecha ("só volta a andar quando a janela
        // virar"), e sobre orçamento isso seria mentira — ninguém é barrado por estourar o
        // próprio teto. O que muda é o preço, não a permissão.
        //
        // Então o ramo é próprio, e ele diz as duas coisas na mesma respiração: você passou, E
        // nada te impede de continuar. Sem susto, sem bloqueio inventado, sem "não abra frente
        // nova" — que é conselho sobre TRABALHO, e o problema aqui é de BOLSO.
        if !t.owner.stops {
            switch t.heat {
            case .over:
                return Verdict(
                    headline: "Você passou do seu orçamento.",
                    detail: "O mês está em **\(t.displayValue)** de um teto de "
                          + "**\(t.capUSD.map(Self.usd) ?? "—")**. Nada te impede de continuar "
                          + "— só fica mais caro.",
                    heat: .over,
                    tightestID: t.id
                )
            case .high:
                return Verdict(
                    headline: "O orçamento está no fim.",
                    detail: "Você já usou **\(t.displayValue)** do teto de "
                          + "**\(t.capUSD.map(Self.usd) ?? "—")** que você definiu, e o mês "
                          + "ainda não acabou. Passar dele não trava nada — só cobra.",
                    heat: .high,
                    tightestID: t.id
                )
            default:
                return Verdict(
                    headline: "Dá pra continuar.",
                    detail: "O teto que mais aperta é o **\(janela)**: "
                          + "**\(t.displayValue)** de **\(t.capUSD.map(Self.usd) ?? "—")**. "
                          + "Nenhuma janela de provedor está mais perto do limite que ele.",
                    heat: t.heat,
                    tightestID: t.id
                )
            }
        }

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

    /// O veredito dito em voz alta. O `**` é PESO — instrução pro olho. Pro ouvido
    /// ele é ruído (o VoiceOver soletraria os asteriscos), então some. Nenhuma
    /// palavra muda: a frase que o cego ouve é a MESMA que o vidente lê.
    public var spoken: String {
        "\(headline) \(detail.replacingOccurrences(of: "**", with: ""))"
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

// MARK: - A PISTA FALADA
//
// ═══════════════════════════════════════════════════════════════════════════
// A pista é a peça central do produto e, até aqui, ela era MUDA. Um usuário
// cego abria o app e ouvia... nada — nem quanto queimou, nem quanto sobra.
//
// A regra que rege este bloco é a mesma do `Certainty`: a certeza TEM que
// aparecer na leitura. Se a honestidade do app só existe pra quem enxerga o
// reticulado, ela não é honestidade — é decoração. "Medido pelo provedor",
// "estimado", "não sei" são os três canais visuais (textura, til, faixa)
// traduzidos pro único canal que o VoiceOver tem: a frase.
//
// E o zero mentiroso morre aqui também: uma pista sem tinta NUNCA é lida como
// "0%". Ela é lida como "não sei quanto da cota foi usada" — e vem com o
// porquê. Ausência é ausência, em qualquer canal.
//
// O número é montado dos valores CRUS, nunca de `displayValue`: aquele string
// carrega o `~` (que o VoiceOver soletraria como "til") e o `—` (que ele leria
// como travessão). Marcas tipográficas não sobrevivem à travessia pro som — o
// que sobrevive é a palavra.
// ═══════════════════════════════════════════════════════════════════════════

extension Lane {

    /// A leitura completa da pista, em UMA fala: provedor, janela, quanto queimou,
    /// com que certeza, quanto do TEMPO passou, e quando zera.
    ///
    /// É este texto — e só ele — que o VoiceOver diz ao parar sobre a pista. Os
    /// rótulos ao redor (título, número, procedência) ficam escondidos: eles são a
    /// mesma informação, e ouvi-la três vezes é pior que não ouvi-la.
    public func accessibilityReading(now: Date = Date()) -> String {
        // Quem abre a fala é o SUJEITO da pista. "Orçamento, janela de mês" seria a frase de
        // quem tratou o orçamento como um provedor a mais — que é exatamente o erro que o
        // `LaneOwner` existe pra tornar impossível.
        let abertura = switch owner {
        case .provider(let p): "\(p.displayName), janela de \(windowLabel)."
        case .budget: "Orçamento do mês, o teto que você definiu."
        }
        var parts: [String] = [abertura]

        parts.append(spokenQuota)

        // O relógio a gente SEMPRE sabe, mesmo sem a tinta — e por isso ele é dito
        // até na pista ausente. Falta a tinta, não a pista: meia leitura honesta
        // vale mais que um zero mentiroso.
        if let nowFraction {
            parts.append("Passaram \(Self.pct(nowFraction * 100)) do tempo da janela.")
        }

        if let reset = spokenReset(now: now) {
            parts.append(reset)
        }

        return parts.joined(separator: " ")
    }

    /// Quanto queimou — e com que certeza. As duas coisas na mesma frase, porque
    /// na tela elas também são a mesma coisa (a tinta e a textura dela).
    private var spokenQuota: String {
        guard let used, certainty.hasInk else {
            // AUSENTE. Não é "0%", não é "zero", não é silêncio: é "não sei", com
            // o motivo colado. Zero é um número, e número é uma afirmação.
            var s = "Não sei quanto da cota foi usada: \(certainty.provenanceLabel())."
            if let cap = capUSD {
                // O que a gente sabe do Cursor sem credencial é o TETO, não o gasto.
                // Dizer só o teto é honesto; deixá-lo implícito seria esconder metade.
                s += " O \(capNoun) da janela é de \(Lane.cap(cap)) dólares."
            }
            return s
        }

        let over = used > 100 ? " Passou do teto." : ""

        switch certainty {
        case .measured(let at):
            let when = at.map { " às \(Verdict.hm($0))" } ?? ""
            return "Queimou \(spokenAmount(used)), número medido pelo provedor\(when).\(over)"

        case .composite(let measuredUpTo, let at):
            // A BARRA COMPOSTA dita: o fato, a hora do fato, e onde ele acaba.
            // A costura é 1 px na tela; aqui ela é a palavra "até".
            return "Queimou cerca de \(spokenAmount(used)): medido até "
                 + "\(Self.pct(measuredUpTo)) às \(Verdict.hm(at)), o resto é estimado "
                 + "do que ficou no disco.\(over)"

        case .derived:
            // O orçamento diz de onde vem o palpite, porque em dinheiro o "de onde" É a
            // ressalva: não é uma margem de erro, é o fato de que isto é preço de tabela e
            // não a fatura. Quem lê por som não vê o reticulado nem lê o rodapé da tela —
            // se a frase não disser, ele nunca fica sabendo.
            if case .budget = owner {
                return "Já foram \(spokenAmount(used)). Estimado do disco a preço de tabela "
                     + "da API — não é a sua fatura, e é um piso: gasto que o Claude apagou "
                     + "do disco não é contado.\(over)"
            }
            var s = "Queimou cerca de \(spokenAmount(used)), número estimado"
            if case .derived(let lo, let hi) = certainty, let lo, let hi {
                // A faixa é o que separa palpite honesto de chute. Se o core não a
                // mandou, ela não é inventada — nem na tela, nem na fala.
                s += ", entre \(Self.pct(lo)) e \(Self.pct(hi))"
            }
            return s + ".\(over)"

        case .absent:
            return ""   // já tratado no guard — inalcançável
        }
    }

    /// "68% da cota" · "6,40 dólares dos 20 do crédito, 32% da cota".
    /// 32% de um crédito em dólar e 32% de uma cota opaca não são a mesma coisa —
    /// a fala carrega a mesma distinção que o número na tela carrega.
    private func spokenAmount(_ used: Double) -> String {
        switch unit {
        case .percent:
            return "\(Self.pct(used)) \(quotaNoun)"
        case .usd:
            guard let cap = capUSD else { return "\(Self.pct(used)) \(quotaNoun)" }
            let capValue = (cap as NSDecimalNumber).doubleValue
            let spent = used / 100 * capValue
            return "\(Self.money(spent)) dólares dos \(Lane.cap(cap)) do \(capNoun), "
                 + "\(Self.pct(used)) \(quotaNoun)"
        }
    }

    /// O nome do denominador em US$. O do Cursor é um CRÉDITO — dinheiro que o plano já
    /// incluiu e que ele te devolve em compute. O do orçamento é um TETO, e é seu: você o
    /// escreveu, ninguém te deu. Chamar os dois de "crédito" apagaria a única diferença que
    /// importa entre eles — um você recebeu, o outro você prometeu.
    private var capNoun: String {
        switch owner {
        case .budget: "orçamento"
        case .provider: "crédito"
        }
    }

    /// A fração, dita: "68% da cota" · "88% do orçamento". Uma COTA é o que o provedor te
    /// concede; um ORÇAMENTO é o que você concede a si mesmo. Dizer "88% da cota" sobre um
    /// teto que o usuário digitou faria o app soar como se a regra viesse de fora.
    private var quotaNoun: String {
        switch owner {
        case .budget: "do orçamento"
        case .provider: "da cota"
        }
    }

    /// "Zera às 16:50." · "Zera sexta-feira às 09:12."
    /// O `displayReset` da tela diz "zera 16:50" — cabe em 40 px, mas não é frase.
    /// Aqui sobra tempo pra dizer o dia por extenso, e o ouvido agradece.
    private func spokenReset(now: Date) -> String? {
        guard let resetsAt else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        let sameDay = Calendar.current.isDate(resetsAt, inSameDayAs: now)
        f.dateFormat = sameDay ? "'às' HH:mm" : "EEEE 'às' HH:mm"
        return "Zera \(f.string(from: resetsAt))."
    }

    /// "+14 pts" vira "14 pontos de folga". O sinal é tipografia; a palavra é fala.
    /// (O VoiceOver leria "−24" como "menos vinte e quatro" — correto e inútil:
    /// menos vinte e quatro do quê?)
    var spokenSlack: String? {
        guard let s = slackPoints else { return nil }
        let n = Int(abs(s).rounded())
        return s >= 0
            ? "\(n) pontos de folga: a cota anda mais devagar que o relógio"
            : "\(n) pontos de aperto: a cota anda mais rápido que o relógio"
    }

    /// "0,86× a janela" → "0,86 vezes a janela". O `×` não é uma palavra.
    var spokenPace: String? {
        paceLabel?.replacingOccurrences(of: "×", with: " vezes")
    }

    // MARK: - Números que viram som

    /// Percentual arredondado, do jeito que se fala: "68%".
    private static func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }

    /// "6,40" — vírgula decimal, que é como o pt-BR lê (e diz) dinheiro.
    private static func money(_ v: Double) -> String {
        String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }
}
