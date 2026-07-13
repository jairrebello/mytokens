//  Budget.swift
//
//  O TETO QUE VOCÊ MESMO PÔS — e a única pista deste app que não mede um provedor.
//
//  ═══════════════════════════════════════════════════════════════════════════
//  NENHUMA PEÇA NOVA. O orçamento é uma `Lane` igual às outras, e é de propósito:
//
//    eixo   = 0 → 100% do orçamento do mês
//    tinta  = quanto do orçamento já foi gasto
//    cursor = quanto do MÊS já passou
//    o VÃO entre os dois continua sendo a resposta — tinta atrás do cursor
//    significa que você fecha o mês dentro do teto.
//
//  A pista em DÓLAR com teto já existia (`unit: .usd` + `capUSD`): é o que o Cursor
//  faz. O orçamento não precisou de um widget; precisou de um denominador.
//  ═══════════════════════════════════════════════════════════════════════════
//
//  AS TRÊS COISAS QUE ESTA PISTA NÃO PODE FINGIR:
//
//  1. ELA É DERIVADA. O US$ sai do `pricing.json` — token do disco × preço público de
//     tabela da API. NÃO é fatura, ninguém aqui viu uma. Logo a tinta sai RETICULADA e a
//     procedência vai por escrito, permanente. Uma pista de orçamento com tinta sólida
//     seria a pior mentira que este app poderia contar, porque é a única que é sobre
//     DINHEIRO — e dinheiro é a única grandeza da tela que sai do bolso de alguém.
//
//  2. ELA É UM PISO, NUNCA UM TETO. O disco do Claude é MUTÁVEL: sessão antiga é
//     reescrita e compactada, e gasto SOME do passado. Um orçamento lê o mês inteiro do
//     disco a cada refresh — então o número pode ANDAR PRA TRÁS entre dois refreshes,
//     sem que um centavo tenha sido devolvido a ninguém. O erro dele é sempre no mesmo
//     sentido: ele subestima. A tela diz isso em palavra, porque uma barra que encolhe
//     sem explicação é um instrumento que perde a confiança de uma vez só.
//
//  3. SEM ORÇAMENTO, ELA NÃO EXISTE. `nil` não é `0`, e `0` não é um teto padrão.
//     Não há "US$ 0 de US$ 0" — há a ausência da pista inteira, e um convite discreto no
//     menu. Ausência é ausência, aqui como em todo o resto do app.
//
//  E O MÊS É O MÊS DO CALENDÁRIO. Não são 30 dias corridos. A `History` recém-nascida é
//  de 30 DIAS e não serve aqui: a fatura do usuário vira no dia 1, não "trinta dias
//  depois do dia em que você abriu o app". O gasto vem de `ProviderStatus.month`, que o
//  core já calcula com `Calendar.current` — o mesmo calendário local que a operadora dele
//  usa. Zero conta nova, zero passada nova sobre os eventos.

import Foundation
import MyTokensCore

// MARK: - A preferência

/// O teto mensal, persistido. Mesmo formato dos outros Stores (`ThemeStore`,
/// `MenuBarStyleStore`, `NotifyStore`): uma chave namespaced, um `static var`, e ponto.
///
/// Guardado em CENTAVOS INTEIROS, e não num `Double` de dólares. Este repo já decidiu que
/// dinheiro é `Decimal` e nunca ponto flutuante (`UsageEvent.costUSD`); o `plist` do
/// UserDefaults, porém, só sabe guardar número como `CFNumber` — um `Decimal` de 40,10
/// entraria como double e voltaria como 40,100000000000001. Centavo é inteiro, inteiro
/// atravessa o plist intacto, e a conta volta a ser exata na saída.
public struct BudgetStore {
    public static let key = "mytokens.budgetCents"

    /// `nil` = NÃO EXISTE orçamento. Não é zero — é a ausência do teto, e é ela que faz a
    /// pista não existir. Um `0` guardado aqui significaria "o usuário definiu um teto de
    /// zero dólares", que é uma afirmação que ninguém quis fazer.
    public static var current: Decimal? {
        get {
            guard let n = UserDefaults.standard.object(forKey: key) as? NSNumber else { return nil }
            let cents = n.intValue
            return cents > 0 ? Decimal(cents) / 100 : nil
        }
        set {
            guard let cents = newValue.map(Self.cents), cents > 0 else {
                // APAGAR é obrigatório. Um app que deixa definir e não deixa desfazer é uma
                // armadilha — e a chave some de verdade, não vira um zero dormindo no plist.
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            UserDefaults.standard.set(cents, forKey: key)
        }
    }

    static func cents(_ d: Decimal) -> Int {
        var arredondado = Decimal()
        var origem = d * 100
        NSDecimalRound(&arredondado, &origem, 0, .plain)
        return (arredondado as NSDecimalNumber).intValue
    }

    // MARK: - O que o usuário digitou

    /// O resultado de ler um campo de texto. Três respostas, e nenhuma delas é um chute:
    /// ou é um valor, ou é um pedido explícito de apagar, ou o app NÃO ENTENDEU e diz isso.
    /// Adivinhar o que "quarenta reais" queria dizer seria inventar o teto de outra pessoa.
    public enum Input: Equatable {
        case value(Decimal)
        /// Campo vazio ou zero. Apagar o orçamento é uma escolha legítima, não um erro.
        case erase
        case invalid
    }

    /// Aceita `40`, `40,50`, `40.50`, `US$ 40`, `1.234,56`. Recusa o resto — em voz alta.
    public static func parse(_ raw: String) -> Input {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for lixo in ["US$", "USD", "$", " ", "\u{00A0}"] {
            s = s.replacingOccurrences(of: lixo, with: "")
        }
        guard !s.isEmpty else { return .erase }

        // "1.234,56" é pt-BR: o ponto agrupa, a vírgula decide. "40.50" é o teclado de quem
        // digita como programador. A vírgula, quando existe, é quem manda.
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "")
            s = s.replacingOccurrences(of: ",", with: ".")
        }

        guard let d = Double(s), d.isFinite, d >= 0 else { return .invalid }
        let cents = Int((d * 100).rounded())
        return cents > 0 ? .value(Decimal(cents) / 100) : .erase
    }
}

// MARK: - A pista

extension Lane {

    /// O id é FIXO e não tem `@` dentro — e isso não é detalhe de estilo.
    ///
    /// O livro do "já avisei" (App/Notifier.swift) chaveia por `laneID@resetsAtEpoch` e
    /// desmonta a chave partindo no `@`. Um id de pista que carregasse um `@` quebraria o
    /// dedup em silêncio: o app avisaria de novo a cada refresh. Ele é fixo porque a pista
    /// tem que ser a MESMA entre dois snapshots pro Notifier reconhecer uma TRAVESSIA de
    /// 85% em vez de um mero estado.
    public static let budgetID = "budget-month"

    /// A pista do orçamento. `nil` quando não há teto — e "não há teto" é o caso comum:
    /// a maioria dos usuários nunca vai definir um, e pra eles esta pista simplesmente
    /// não existe. Não existe como `US$ 0 de US$ 0`, não existe como trilho vazio
    /// convidativo, não existe.
    ///
    /// `burnRatePerHour` fica `nil` DE PROPÓSITO, e é a decisão mais deliberada daqui.
    /// A projeção da `Lane` extrapola o ritmo dos últimos 20 minutos até o fim da janela.
    /// Numa janela de 5 h isso é uma leitura; num mês de 700 horas é uma alucinação — vinte
    /// minutos de Opus projetados sobre dezoito dias fecham o mês em 4.000%. O app não
    /// desenha essa projeção porque ela não é um palpite, é um erro de escala. O que
    /// responde a pergunta continua sendo o VÃO entre a tinta e o cursor, que não extrapola
    /// nada: ele compara duas frações do mesmo mês, e as duas são fatos.
    public static func budget(
        spentUSD: Decimal,
        capUSD: Decimal,
        now: Date = Date(),
        calendar: Calendar = .current,
        isLive: Bool = false
    ) -> Lane? {
        guard capUSD > 0 else { return nil }
        // O MÊS DO CALENDÁRIO LOCAL — não uma janela deslizante de 30 dias. É assim que a
        // fatura do usuário funciona, e é a única definição de "mês" que ele reconhece.
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }

        let cap = (capUSD as NSDecimalNumber).doubleValue
        let spent = (spentUSD as NSDecimalNumber).doubleValue
        // Pode passar de 100. E quando passa, passa: o teto era dele, e estourá-lo é um
        // fato, não um erro de leitura. `Heat.over` põe croma no número e a conversa acaba
        // aí — sem trilho rompido, porque o que rompe o trilho é PROJEÇÃO, e projeção é
        // palpite. Isto aqui é dinheiro que já saiu.
        let used = max(0, spent / cap * 100)

        let total = month.end.timeIntervalSince(month.start)
        let nowFraction: Double? = total > 0
            ? min(1, max(0, now.timeIntervalSince(month.start) / total))
            : nil

        return Lane(
            id: budgetID,
            owner: .budget,
            title: "Orçamento · mês",
            used: used,
            // DERIVADO, e sem faixa. Reticulado + topo pontilhado, como todo custo neste app.
            //
            // `lo`/`hi` ficam nil porque não existe faixa a prometer: o token é EXATO (saiu
            // do disco) e o preço é o de TABELA (saiu do pricing.json). A incerteza não é de
            // MAGNITUDE, é de NATUREZA — isto é preço público de API, não a conta que vai
            // ser cobrada. Isso não cabe num `~` nem num `41–68`; cabe numa frase, e a frase
            // está na tela. (o mesmo argumento que a `History` já fez pro custo de 30 dias)
            certainty: .derived(lo: nil, hi: nil),
            nowFraction: nowFraction,
            resetsAt: month.end,
            unit: .usd,
            capUSD: capUSD,
            burnRatePerHour: nil,
            isLive: isLive
        )
    }
}
