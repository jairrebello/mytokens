//  Lane.swift
//
//  A PISTA — a peça central do sistema. Um eixo, DUAS leituras:
//
//    eixo x  = 0 → 100% DAQUELA janela (5 h, 7 d, ou o mês em US$)
//    tinta   = % da COTA queimada
//    cursor  = % do TEMPO decorrido nessa janela ("agora")
//
//    O VÃO ENTRE A TINTA E O CURSOR É A RESPOSTA DO APP.
//      tinta ATRÁS do cursor  → gasta mais devagar que o relógio. Folga.
//      tinta NA FRENTE        → acaba antes da janela fechar.
//
//  O eixo é NORMALIZADO, não temporal. Foi a única coisa que sobreviveu ao
//  Codex matar a janela de 5 h em 12/07: se o eixo fosse "5 horas de relógio",
//  o app estaria desenhando um dado que não existe mais. Fração de janela é a
//  única unidade em que 5 h, 7 d e US$ 20/mês são honestamente comparáveis.

import MyTokensCore
import Foundation

/// DE QUEM é a pista.
///
/// Durante muito tempo isto era um `Provider` cru, e funcionava porque toda pista era de um
/// provedor. O ORÇAMENTO quebrou essa suposição: ele é um teto medido contra os MESMOS dados,
/// mas não é um provedor — é uma regra que o usuário escreveu pra si mesmo.
///
/// A saída fácil seria um `case orcamento` no enum `Provider` do CORE. Seria errado: o
/// `Provider` é a lista de coisas que o app SABE LER DO DISCO, e é ele que decide qual
/// collector roda, o que é dedup, o que é preço. Enfiar um conceito que só existe na tela
/// dentro do contrato de dados contamina o core com uma ideia de UI — e o `Contract.swift`
/// pede, no topo, que mudanças ali sejam aditivas e justificadas. Esta não seria nem uma
/// coisa nem outra: seria um provedor que não coleta nada.
///
/// Então o dono da pista vira um tipo DA UI. O core não sabe que orçamento existe, e não
/// precisa saber. Zero linha mudou no `Contract.swift`.
public enum LaneOwner: Sendable, Equatable {
    case provider(Provider)
    case budget

    /// ESTA JANELA TE PARA?
    ///
    /// Um limite de provedor PARA: bateu, o prompt não passa. Um orçamento não para ninguém —
    /// ele só COBRA. São duas perguntas ("posso continuar?" e "posso gastar?"), e a diferença
    /// entre elas é real.
    ///
    /// MAS ELA NÃO DECIDE QUEM VIRA HERÓI. O orçamento COMPETE pelo veredito como qualquer
    /// outra pista (ver `Dashboard.tightest`) — porque um app que fica calado sobre o teto que
    /// o próprio usuário mandou vigiar não está sendo disciplinado, está sendo surdo. Quem
    /// definiu um orçamento e o estourou 14x não quer ler "Dá pra continuar" no topo.
    ///
    /// O que este `stops` decide é o que a frase pode PROMETER. Quando o herói para, o veredito
    /// fala de reset e de porta fechada. Quando ele só cobra, a frase diz a verdade inteira:
    /// "nada te impede de continuar — só fica mais caro". Confundir as duas seria vender um
    /// bloqueio que não existe, e este app não vende susto.
    public var stops: Bool {
        switch self {
        case .provider: true
        case .budget: false
        }
    }

    /// O SUJEITO da frase do veredito. "a janela de 5 horas do Claude" te para; "o seu
    /// orçamento do mês" te cobra. A frase inteira se apoia nisto, então ele mora aqui e não
    /// num `if` dentro da view.
    public func subject(window: String) -> String {
        switch self {
        case .provider(let p): "janela de \(window) do \(p.displayName)"
        case .budget: "seu orçamento do mês"
        }
    }
}

/// O que uma pista precisa saber pra se desenhar. Nada além disto.
/// A view NUNCA vê um LimitWindow cru — vê isto, que já resolveu a certeza.
public struct Lane: Identifiable, Sendable, Equatable {
    public let id: String
    public let owner: LaneOwner
    /// "Claude · 5 h"
    public let title: String
    /// 0...100+ da janela. `nil` quando ausente — NUNCA 0.
    public let used: Double?
    public let certainty: Certainty
    /// % do TEMPO decorrido na janela. O relógio a gente SEMPRE sabe, mesmo
    /// quando não sabemos a tinta: o Cursor desconectado também tem cursor.
    /// Falta a tinta, não a pista. Meia leitura honesta > zero mentiroso.
    public let nowFraction: Double?
    public let resetsAt: Date?
    public let unit: WindowUnit
    public let capUSD: Decimal?
    public let burnRatePerHour: Double?
    /// Modelo a que a janela se aplica (contrato v1.3). `nil` = conta inteira.
    /// A pista não o desenha (é o §11, do Vitral); quem já o lê é o picker da barra,
    /// que precisa distinguir "Semana" de "Semana · Fable" pra fixar a certa.
    public let modelScope: String?

    /// Está queimando AGORA (evento recente). É a única coisa que acende a
    /// matiz ember — e ela não significa perigo, significa CALOR = atividade.
    /// Provedor parado fica cinza (`emberCold`). Sem verde e sem amarelo no
    /// sistema, não existe semáforo nem se eu quisesse fazer um.
    public let isLive: Bool

    public init(
        id: String, owner: LaneOwner, title: String,
        used: Double?, certainty: Certainty, nowFraction: Double?,
        resetsAt: Date?, unit: WindowUnit = .percent,
        capUSD: Decimal? = nil, burnRatePerHour: Double? = nil,
        isLive: Bool = false, modelScope: String? = nil
    ) {
        self.isLive = isLive
        self.id = id
        self.owner = owner
        self.title = title
        self.used = used
        self.certainty = certainty
        self.nowFraction = nowFraction
        self.resetsAt = resetsAt
        self.unit = unit
        self.capUSD = capUSD
        self.burnRatePerHour = burnRatePerHour
        self.modelScope = modelScope
    }

    /// A pista de um provedor. É o caso esmagadoramente comum, então ele continua sendo o
    /// que se escreve sem cerimônia — nenhum mock, nenhum teste e nenhuma view precisou
    /// aprender a palavra `owner` por causa do orçamento.
    public init(
        id: String, provider: Provider, title: String,
        used: Double?, certainty: Certainty, nowFraction: Double?,
        resetsAt: Date?, unit: WindowUnit = .percent,
        capUSD: Decimal? = nil, burnRatePerHour: Double? = nil,
        isLive: Bool = false, modelScope: String? = nil
    ) {
        self.init(
            id: id, owner: .provider(provider), title: title,
            used: used, certainty: certainty, nowFraction: nowFraction,
            resetsAt: resetsAt, unit: unit, capUSD: capUSD,
            burnRatePerHour: burnRatePerHour, isLive: isLive, modelScope: modelScope
        )
    }

    /// `nil` no orçamento — e é por isso que ele é Optional. A alternativa era devolver um
    /// provedor inventado pra a view não precisar pensar, e o preço disso seria um botão
    /// "conectar o ..." num teto que não tem o que conectar.
    public var provider: Provider? {
        if case .provider(let p) = owner { return p }
        return nil
    }

    /// "Claude" · "Codex" · "Orçamento". A primeira linha da coluna da esquerda.
    public var ownerName: String {
        switch owner {
        case .provider(let p): p.displayName
        case .budget: "Orçamento"
        }
    }

    /// O nome desta pista dentro de uma FRASE (a notificação, um alerta).
    ///
    /// `title` é um cabeçalho de grade: "Claude · 5 h" cabe numa coluna e lê bem numa frase
    /// curta. "Orçamento · mês" também cabe na coluna, e numa frase soa como um erro de
    /// digitação. Dois lugares, duas gramáticas — o ponto médio é que a notificação diga
    /// exatamente o que a pista diz, só que em português.
    public var noticeTitle: String {
        switch owner {
        case .provider: title
        case .budget: "Orçamento do mês"
        }
    }

    public var heat: Heat { Heat(percent: used ?? 0) }

    /// O nome desta janela no picker "Mostrar na barra" (UI-SPEC §12).
    ///
    /// Janela primeiro, modelo como qualificador depois do middot (§11): "Claude · Semana ·
    /// Fable" — nunca "Fable" sozinho, que leria como provedor. O guard contra o título já
    /// conter o escopo existe porque o rótulo da janela é do provedor: se um dia a fonte
    /// passar a escrever "Semana · Fable" no `label`, duplicar aqui viraria gagueira.
    public var pickerLabel: String {
        guard let scope = modelScope, !scope.isEmpty,
              !title.localizedCaseInsensitiveContains(scope) else { return title }
        return "\(title) · \(scope.capitalized)"
    }

    /// Onde a tinta chega no fim da janela, no ritmo dos últimos 20 min.
    /// Só existe acima de 70% — abaixo disso é ruído: a resposta já é "pode ir".
    public var projected: Double? {
        guard let used, used >= 70,
              let burn = burnRatePerHour,
              let resetsAt, certainty.hasInk else { return nil }
        let hoursLeft = resetsAt.timeIntervalSinceNow / 3600
        guard hoursLeft > 0 else { return nil }
        return used + burn * hoursLeft
    }

    /// O quanto a projeção passa de 100. É isto que vaza PRA FORA do trilho.
    /// O trilho é o limite. O que sai dele é o que você não tem.
    public var overrun: Double? {
        guard let p = projected, p > 100 else { return nil }
        return p - 100
    }

    /// Folga em pontos: quanto do relógio você tem a mais que da cota.
    /// Positivo = folga. Negativo = você fura antes da janela virar.
    public var slackPoints: Double? {
        guard let used, let nowFraction, certainty.hasInk else { return nil }
        return nowFraction * 100 - used
    }

    // MARK: - Como o número é escrito
    //
    // Segundo canal da honestidade. A textura fala com o olho de raspão;
    // isto fala com o olho que para.

    /// `50%` (medido) · `~53%` (derivado/composta) · `—` (ausente. NUNCA `0`)
    public var displayValue: String {
        guard let used, certainty.hasInk else { return "—" }
        switch unit {
        case .percent:
            let n = "\(Int(used.rounded()))%"
            return certainty.isApproximate ? "~\(n)" : n
        case .usd:
            // 32% de um crédito em dólar e 32% de uma cota opaca não são a
            // mesma coisa. Fingir que são é a mentira que o UI-SPEC §12.2 mata.
            guard let cap = capUSD else { return "—" }
            //
            // DINHEIRO NÃO LEVA TIL. Nem quando é derivado — e o orçamento SEMPRE é.
            //
            // O `~` promete uma FAIXA (`41–68`): ele diz "o valor está por aqui, com esta
            // margem". Em dinheiro não existe faixa a prometer. O token é EXATO (saiu do
            // disco) e o preço é o de TABELA (saiu do pricing.json): a incerteza não é de
            // MAGNITUDE, é de NATUREZA — isto é preço público de API, não a conta que vai
            // ser cobrada, e não existe margem de erro que exprima essa diferença. Um
            // `~US$ 34,80` convidaria a ler "34,80 mais ou menos", que é a única coisa que
            // este número NÃO é: ele é 34,80 exatos de uma tabela que não é a sua fatura.
            //
            // O que diz a verdade aqui são os canais que sobraram: a tinta RETICULADA (o
            // olho de raspão) e a frase de procedência, permanente na tela (o olho que
            // para). É o mesmo argumento que a `History` já tinha feito pro custo de 30
            // dias — nenhum sinal de pontuação fingindo ser estatística.
            //
            // E o formatter é o do app (`Verdict.usd`): vírgula decimal e ponto de milhar,
            // que é como o pt-BR lê dinheiro. O `String(format:)` que morava aqui não
            // agrupava milhar — "US$ 4608,00" na coluna do Jair.
            return Verdict.usd(Decimal(used) / 100 * cap)
        }
    }

    /// O denominador, quando ele existe de verdade: o crédito do Cursor, o teto do orçamento.
    public var displayUnitSuffix: String? {
        guard case .usd = unit, let cap = capUSD, certainty.hasInk else { return nil }
        return "/ \(Self.cap(cap))"
    }

    /// O teto escrito curto: `20` · `37,50`.
    ///
    /// Cota de crédito é redonda e dispensa centavo. Orçamento é um número que o usuário
    /// DIGITOU — e imprimir "/ 37" onde ele escreveu 37,50 seria mentir sobre o denominador
    /// dele, que é justamente a metade da fração que ele controla.
    public static func cap(_ d: Decimal) -> String {
        let n = d as NSDecimalNumber
        let redondo = n.doubleValue == n.doubleValue.rounded()
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = redondo ? 0 : 2
        f.maximumFractionDigits = redondo ? 0 : 2
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        return f.string(from: n) ?? "\(d)"
    }

    /// A procedência em PALAVRA — o segundo canal, ao lado da textura.
    ///
    /// O orçamento diz mais que "estimado": ele diz DE ONDE. E o "de onde" não é curiosidade,
    /// é a única coisa que explica por que este número pode ANDAR PRA TRÁS entre dois
    /// refreshes — o disco do Claude é mutável, sessão antiga é reescrita, e gasto some do
    /// passado. Uma barra que encolhe sem explicação queima a confiança de uma vez só.
    public var provenanceNote: String {
        switch owner {
        case .budget: "estimado do disco"
        case .provider: certainty.provenanceLabel()
        }
    }

    /// A faixa `41–68` que acompanha o til. Só no derivado, e só se o core
    /// mandou piso e teto. Sem faixa, sem número inventado.
    public var displayRange: String? {
        guard case .derived(let lo, let hi) = certainty, let lo, let hi else { return nil }
        return "\(Int(lo.rounded()))–\(Int(hi.rounded()))"
    }

    /// "zera 16:50" · "zera sex 09:12" · "zera 1 de ago"
    public var displayReset: String? {
        guard let resetsAt else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        let sameDay = Calendar.current.isDate(resetsAt, inSameDayAs: Date())
        // A mais de uma semana daqui, o dia da SEMANA deixa de localizar: "zera sáb" pode ser
        // este sábado ou o de daqui a três semanas, e o leitor não tem como saber qual. Aí
        // quem localiza é a DATA. Isto nasceu pro orçamento (que vira no dia 1) mas conserta
        // também a pista do Cursor, cujo ciclo de cobrança costuma estar a semanas de
        // distância — ela vinha dizendo "zera qua 00:00" há meses.
        let longe = resetsAt.timeIntervalSinceNow > 7 * 86_400
        f.dateFormat = sameDay ? "HH:mm" : (longe ? "d 'de' MMM" : "EEE HH:mm")
        return "zera \(f.string(from: resetsAt))"
    }
}

// MARK: - Do contrato pra pista

extension Lane {
    /// Uma janela do core vira uma pista. A certeza é resolvida uma vez, aqui.
    ///
    /// `startedAt` vem NA janela (contrato v1.2). O parâmetro só existe pra teste poder
    /// forçar um começo — em produção ninguém passa, e o dado é o do core.
    public init(
        window w: LimitWindow,
        provider: Provider,
        startedAt: Date? = nil,
        isLive: Bool = false
    ) {
        let certainty = Certainty.of(w)
        let startedAt = startedAt ?? w.startedAt
        let now: Double? = {
            guard let startedAt else { return nil }
            let total = w.resetsAt.timeIntervalSince(startedAt)
            guard total > 0 else { return nil }
            return min(1, max(0, Date().timeIntervalSince(startedAt) / total))
        }()

        self.init(
            id: "\(provider.rawValue)-\(w.id)",
            provider: provider,
            title: "\(provider.displayName) · \(w.label)",
            used: w.usedPercent,
            certainty: certainty,
            nowFraction: now,
            resetsAt: w.resetsAt,
            unit: w.unit,
            capUSD: w.capUSD,
            burnRatePerHour: w.burnRatePerHour,
            isLive: isLive,
            modelScope: w.modelScope
        )
    }

    /// A pista de um provedor que não tem NENHUMA janela.
    /// `windows` vazio no contrato = "não sabemos". Isto é o estado honesto
    /// que ocupa o lugar do zero mentiroso.
    public static func absent(
        provider: Provider,
        label: String,
        nowFraction: Double? = nil,
        capUSD: Decimal? = nil,
        unit: WindowUnit = .percent
    ) -> Lane {
        Lane(
            id: "\(provider.rawValue)-absent",
            provider: provider,
            title: "\(provider.displayName) · \(label)",
            used: nil,
            certainty: .absent,
            nowFraction: nowFraction,
            resetsAt: nil,
            unit: unit,
            capUSD: capUSD
        )
    }
}

// MARK: - O app inteiro, numa struct

/// O que a view recebe. Não existe caminho daqui pro disco.
public struct Dashboard: Sendable, Equatable {
    public var lanes: [Lane]
    /// Provedores que o app ENCONTROU no disco mas que ainda não queimaram nada.
    /// Serve ao estado vazio: "achei o Codex e o Claude Code" compra confiança
    /// no segundo 1, e é diferente de "não sei onde eles estão".
    public var discovered: [Provider]
    public var todayCostUSD: Decimal
    /// Marca a última janela que resetou — o app dá o respiro visual e limpa.
    public var justReset: String?
    /// O PASSADO — 30 dias, projeto, modelo. Já estava no `Snapshot` desde a Fase 1 e a
    /// fronteira jogava fora. Nasce `.empty` (e aí a bancada não desenha história nenhuma):
    /// trinta colunas vazias antes do primeiro scan seriam um instrumento afirmando o que
    /// ainda não mediu. Ver Model/History.swift.
    public var history: History

    public init(
        lanes: [Lane],
        discovered: [Provider] = [],
        todayCostUSD: Decimal = 0,
        justReset: String? = nil,
        history: History = .empty
    ) {
        self.lanes = lanes
        self.discovered = discovered
        self.todayCostUSD = todayCostUSD
        self.justReset = justReset
        self.history = history
    }

    /// A pista que APERTA: a de menor folga entre as que têm tinta. É ela que responde a
    /// pergunta do topo, e é ela que vai pro ícone da barra — três provetas em 22 px não é
    /// informação, é sujeira.
    ///
    /// O ORÇAMENTO COMPETE AQUI, e essa foi uma decisão tomada duas vezes.
    ///
    /// Na primeira, ele ficou de fora: o eixo do app é "tempo até te PARAR", e orçamento não
    /// para ninguém — só cobra. O raciocínio era limpo e o resultado, surdo: com o teto
    /// estourado em 14x, a tela estampava "Dá pra continuar" e ia falar de outra coisa. O app
    /// dando de ombros justamente pro número que o usuário mandou vigiar.
    ///
    /// Um teto que a pessoa escreveu com a própria mão é um limite REAL — só que o custo de
    /// cruzá-lo é dinheiro, não uma porta fechada. Então ele briga pelo veredito como qualquer
    /// outra pista, e é a FRASE que muda de natureza conforme quem ganha (`LaneOwner.stops`):
    /// quem para fala de reset; quem cobra diz, com todas as letras, que nada te impede de
    /// continuar — só fica mais caro. O app não vende um bloqueio que não existe.
    public var tightest: Lane? {
        lanes
            .filter { $0.certainty.hasInk && $0.used != nil }
            .min { a, b in (a.slackPoints ?? .infinity) < (b.slackPoints ?? .infinity) }
    }

    public var isEmpty: Bool {
        lanes.allSatisfy { !$0.certainty.hasInk || ($0.used ?? 0) == 0 }
    }

    /// Troca — ou APAGA — a pista do orçamento, sem tocar em mais nada.
    ///
    /// Existe porque o orçamento é a única coisa da tela que muda por vontade do usuário, e
    /// não por evento de disco. Quando ele digita um teto, a pista tem que nascer AGORA: o
    /// gasto do mês já está no `statuses` da última coleta, não há um byte novo a ler. E um
    /// `refresh()` completo nem serviria — ele é barrado quando a leitura está PAUSADA, e
    /// definir um orçamento com o app pausado é uma coisa perfeitamente razoável de se fazer.
    ///
    /// `capUSD == nil` remove a pista. Não a zera: REMOVE. Sem teto não existe pista de
    /// orçamento — não existe como "US$ 0 de US$ 0", não existe como trilho vazio esperando
    /// um número. Ausência é ausência, aqui como em todo o resto do app.
    public func withBudget(
        _ capUSD: Decimal?,
        monthSpentUSD: Decimal,
        now: Date = Date()
    ) -> Dashboard {
        var out = self
        out.lanes.removeAll { $0.owner == .budget }
        if let capUSD,
           let lane = Lane.budget(
               spentUSD: monthSpentUSD,
               capUSD: capUSD,
               now: now,
               // O calor é ATIVIDADE: se algum provedor queimou nos últimos 5 min, o
               // orçamento também está queimando — é o mesmo dinheiro.
               isLive: out.lanes.contains(where: \.isLive)
           ) {
            out.lanes.append(lane)
        }
        return out
    }
}
