//  BudgetTests.swift
//
//  O orçamento é a única pista deste app que fala de DINHEIRO QUE SAI DO BOLSO de alguém.
//  Toda mentira que ele possa contar é mais cara que as outras — então as regras dele são
//  testadas uma a uma, e não "por inspeção".

import Testing
import Foundation
import MyTokensCore
@testable import MyTokensUI

@Suite("Orçamento — o teto que o usuário pôs, e as três coisas que ele não pode fingir")
struct BudgetTests {

    /// 13/07/2026, 12:00 local. Data fixa: um teste de "mês do calendário" que dependesse do
    /// dia em que roda é um teste que passa em julho e some em fevereiro.
    private static func hoje() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 13; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    private static func status(_ p: Provider, month: Decimal) -> ProviderStatus {
        ProviderStatus(provider: p, connected: true, month: Spend(tokens: 1, costUSD: month))
    }

    // MARK: - Regra 1: sem orçamento, não existe pista

    @Test("sem teto definido, a pista de orçamento NÃO EXISTE — não é 'US$ 0 de US$ 0'")
    func semOrcamentoNaoHaPista() {
        let dash = Dashboard(lanes: [
            Lane(id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                 used: 40, certainty: .measured(at: nil), nowFraction: 0.5,
                 resetsAt: Self.hoje().addingTimeInterval(3600)),
        ])
        .withBudget(nil, monthSpentUSD: 68.40, now: Self.hoje())

        #expect(!dash.lanes.contains { $0.owner == .budget })
    }

    @Test("teto zero (ou negativo) não é um orçamento — é a ausência de um")
    func tetoZeroNaoEOrcamento() {
        #expect(Lane.budget(spentUSD: 10, capUSD: 0, now: Self.hoje()) == nil)
        #expect(Lane.budget(spentUSD: 10, capUSD: -5, now: Self.hoje()) == nil)
    }

    @Test("APAGAR devolve o app ao estado sem orçamento — definir e não poder desfazer é armadilha")
    func apagarRemoveAPista() {
        let comTeto = Dashboard(lanes: []).withBudget(200, monthSpentUSD: 68.40, now: Self.hoje())
        #expect(comTeto.lanes.count == 1)

        let semTeto = comTeto.withBudget(nil, monthSpentUSD: 68.40, now: Self.hoje())
        #expect(semTeto.lanes.isEmpty, "apagar REMOVE a pista; não a zera")
    }

    // MARK: - Regra 2: ela é DERIVADA, e diz isso

    @Test("a pista do orçamento NUNCA é medida — o US$ sai do pricing.json, não de uma fatura")
    func orcamentoEDerivado() throws {
        let lane = try #require(Lane.budget(spentUSD: 68.40, capUSD: 200, now: Self.hoje()))

        // Esta é A asserção deste arquivo. Uma pista de orçamento com `.measured` desenharia
        // tinta SÓLIDA (LaneView.ink) — a textura que este app reserva pro número que o
        // provedor DEU. Seria o app afirmando que viu uma cobrança que ele nunca viu.
        guard case .derived = lane.certainty else {
            Issue.record("orçamento com certeza \(lane.certainty) — tinta sólida em dinheiro derivado")
            return
        }
        #expect(lane.certainty.hasInk)
        #expect(lane.certainty.isApproximate)
        #expect(lane.provenanceNote == "estimado do disco")
    }

    @Test("sem faixa: derivado de dinheiro não promete lo–hi, porque não existe lo–hi a prometer")
    func semFaixaDeIncerteza() throws {
        let lane = try #require(Lane.budget(spentUSD: 68.40, capUSD: 200, now: Self.hoje()))
        #expect(lane.displayRange == nil, "faixa em dinheiro seria estatística inventada")
    }

    @Test("o número em US$ NÃO leva til — o ~ promete uma margem que não existe")
    func dinheiroNaoLevaTil() throws {
        let lane = try #require(Lane.budget(spentUSD: 68.40, capUSD: 200, now: Self.hoje()))
        #expect(lane.displayValue == "US$ 68,40")
        #expect(!lane.displayValue.contains("~"))
        #expect(lane.displayUnitSuffix == "/ 200")
    }

    @Test("o rodapé da tela declara a procedência do dinheiro, e ela é reticulada como todo custo")
    func aLegendaMostraOInferido() {
        let dash = Dashboard(lanes: []).withBudget(200, monthSpentUSD: 68.40, now: Self.hoje())
        #expect(dash.legendKinds.contains(.inferred),
                "a pista do orçamento põe hachura na tela; a legenda tem que explicá-la")
    }

    // MARK: - Regra 3: o mês é o do CALENDÁRIO, não 30 dias corridos

    @Test("o gasto vem de status.month — o mês do calendário local, que é o mês da fatura")
    func mesDoCalendario() {
        // `ProviderStatus.month` é, por contrato, o mês corrente (Aggregator.status usa
        // `dateInterval(of: .month)` com o Calendar local). A soma do orçamento é a soma
        // desses meses — e não uma janela de 30 dias, que em 3 de agosto ainda estaria
        // contando julho e faria o orçamento de agosto nascer estourado.
        let total = Dashboard.monthSpentUSD([
            Self.status(.claudeCode, month: 52.30),
            Self.status(.codex, month: 16.10),
            Self.status(.cursor, month: 0),   // o Cursor não emite evento: zero por construção
        ])
        #expect(total == 68.40)
    }

    @Test("o cursor do 'agora' é a fração do MÊS decorrida — no dia 13 de julho, ~40%")
    func cursorDoMes() throws {
        let lane = try #require(Lane.budget(spentUSD: 68.40, capUSD: 200, now: Self.hoje()))

        // 12,5 dias de 31 = 0,403.
        let now = try #require(lane.nowFraction)
        #expect(abs(now - 0.403) < 0.01, "cursor em \(now) — deveria ser a fração do mês")

        // E o reset é a VIRADA DO MÊS: 1º de agosto, 00:00 local.
        let reset = try #require(lane.resetsAt)
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour], from: reset)
        #expect(c.year == 2026 && c.month == 8 && c.day == 1 && c.hour == 0)
    }

    @Test("o VÃO é a resposta: tinta atrás do cursor = você fecha o mês dentro do teto")
    func oVaoEARresposta() throws {
        // 34% do teto queimado com 40% do mês passado → folga positiva.
        let folgado = try #require(Lane.budget(spentUSD: 68.40, capUSD: 200, now: Self.hoje()))
        #expect((folgado.slackPoints ?? 0) > 0)

        // 88% do teto com os mesmos 40% do mês → você fura antes do mês virar.
        let apertado = try #require(Lane.budget(spentUSD: 176, capUSD: 200, now: Self.hoje()))
        #expect((apertado.slackPoints ?? 0) < 0)
    }

    // MARK: - O orçamento VIRA herói — e a frase muda de natureza quando ele vira

    @Test("o orçamento estourado GANHA o veredito — mas a frase não inventa um bloqueio")
    func orcamentoViraHeroi() throws {
        // O orçamento está estourado (110%); o Claude está folgado. O orçamento é a menor
        // folga, então ele ganha — porque um app que fica calado sobre o teto que o próprio
        // usuário mandou vigiar não é disciplinado, é surdo.
        let dash = Dashboard(lanes: [
            Lane(id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                 used: 20, certainty: .measured(at: nil), nowFraction: 0.9,
                 resetsAt: Self.hoje().addingTimeInterval(3600)),
        ])
        .withBudget(200, monthSpentUSD: 220, now: Self.hoje())

        let heroi = try #require(dash.tightest)
        #expect(heroi.owner == .budget)

        let v = Verdict.of(dash)
        #expect(v.tightestID == "budget-month")   // o ícone da barra segue o herói
        #expect(v.headline == "Você passou do seu orçamento.")

        // ESTA é a linha que o teste existe pra proteger. O orçamento não te PARA (`stops` é
        // false), então a frase dele NÃO pode falar de porta fechada nem mandar você segurar
        // o trabalho — esse vocabulário pertence a quem de fato te barra. O que muda ao
        // estourar um teto que você mesmo escreveu é o PREÇO, não a permissão.
        #expect(v.detail.contains("Nada te impede de continuar"))
        #expect(!v.detail.contains("frente nova"))
        #expect(!v.detail.contains("Só volta a andar"))
    }

    @Test("quem PARA continua falando de porta fechada — o orçamento não contaminou a frase")
    func provedorEstouradoAindaFalaDeReset() throws {
        // O contrapeso do teste acima: com o Claude estourado e o orçamento folgado, o
        // vocabulário de bloqueio tem que continuar existindo. Uma coisa é não inventar
        // barreira onde não há; outra, bem diferente, é parar de avisar onde há.
        let dash = Dashboard(lanes: [
            Lane(id: "claude-5h", provider: .claudeCode, title: "Claude · 5 h",
                 used: 105, certainty: .measured(at: nil), nowFraction: 0.5,
                 resetsAt: Self.hoje().addingTimeInterval(3600)),
        ])
        .withBudget(200, monthSpentUSD: 10, now: Self.hoje())

        let heroi = try #require(dash.tightest)
        #expect(heroi.owner == .provider(.claudeCode))
        #expect(Verdict.of(dash).headline == "Passou do teto.")
    }

    @Test("estourar o teto é um FATO, e ele aparece: >100%, croma no número")
    func estourarOTeto() throws {
        let lane = try #require(Lane.budget(spentUSD: 220, capUSD: 200, now: Self.hoje()))
        #expect(lane.used ?? 0 > 100)
        #expect(lane.heat == .over)
        #expect(lane.displayValue == "US$ 220,00")
        // Sem projeção: o `burnRatePerHour` é nil de propósito. Extrapolar 20 min de queima
        // sobre 18 dias de mês não é um palpite, é um erro de escala.
        #expect(lane.projected == nil)
        #expect(lane.overrun == nil)
    }

    @Test("o orçamento não é um provedor — não há 'conectar', e o core não sabe que ele existe")
    func orcamentoNaoEProvider() throws {
        let lane = try #require(Lane.budget(spentUSD: 68.40, capUSD: 200, now: Self.hoje()))
        // `provider == nil` é o que impede, NO COMPILADOR, a view desenhar um botão
        // "conectar" num teto que o próprio usuário digitou.
        #expect(lane.provider == nil)
        #expect(lane.ownerName == "Orçamento")
        #expect(lane.noticeTitle == "Orçamento do mês")
        // E o enum `Provider` do CORE continua com três casos. Nenhum `case orcamento` entrou
        // no contrato de dados pra caber numa view.
        #expect(Provider.allCases.count == 3)
    }

    // MARK: - O aviso de 85% (App/Notifier.swift) — as pré-condições dele, checadas aqui
    //
    // O Notifier mora no target do app, que não tem suíte de teste. O que dá pra travar aqui é
    // o CONTRATO que ele exige da pista — e é justamente aí que o orçamento poderia ter
    // quebrado em silêncio, porque a chave de dedup dele é `laneID@resetsAt`.

    @Test("o orçamento satisfaz as 3 pré-condições do aviso de 85%: tinta, resetsAt e id estável")
    func avisoDe85HerdaDeGraca() throws {
        let lane = try #require(Lane.budget(spentUSD: 176, capUSD: 200, now: Self.hoje()))

        // 1. `guard lane.certainty.hasInk` — derivado tem tinta.
        #expect(lane.certainty.hasInk)
        // 2. `guard let resetsAt` — a virada do mês.
        #expect(lane.resetsAt != nil)
        // 3. o `Ledger` chaveia em "\(laneID)@\(epoch)" e desmonta partindo no "@".
        //    Um "@" dentro do id partiria a chave ao meio e o dedup morreria CALADO —
        //    o app avisaria de novo a cada refresh.
        #expect(!Lane.budgetID.contains("@"))
        #expect(lane.id == Lane.budgetID)

        // E o id é ESTÁVEL entre dois snapshots do mesmo mês: é isso que faz o Notifier
        // enxergar uma TRAVESSIA (85% cruzado) em vez de um mero estado.
        let outro = try #require(Lane.budget(spentUSD: 180, capUSD: 200, now: Self.hoje()))
        #expect(outro.id == lane.id)
        #expect(outro.resetsAt == lane.resetsAt, "mesmo mês, mesmo resetsAt, mesma chave")

        #expect((lane.used ?? 0) >= 85, "176 de 200 é 88% — cruza a linha")
    }

    // MARK: - O que o usuário digita

    @Test("o campo aceita o que gente escreve, e recusa o resto EM VOZ ALTA")
    func parseDoCampo() {
        #expect(BudgetStore.parse("40") == .value(40))
        #expect(BudgetStore.parse("US$ 40") == .value(40))
        #expect(BudgetStore.parse("37,50") == .value(37.5))
        #expect(BudgetStore.parse("37.50") == .value(37.5))

        // `Decimal(string:)`, e não o literal `1234.56` — e o motivo é o assunto deste arquivo.
        // Um literal de ponto flutuante em Swift vira `Decimal` PELO DOUBLE, e sai
        // 1234.5599999999997952. O parser não: ele lê centavos INTEIROS e monta o Decimal a
        // partir deles, então sai 1234,56 exato. Foi este teste que pegou a diferença — a
        // versão errada era a minha asserção, não o código.
        #expect(BudgetStore.parse("1.234,56") == .value(Decimal(string: "1234.56")!))

        // Vazio e zero são um pedido de APAGAR, não um erro. Zero dólares por mês não é um
        // orçamento — é a ausência de um.
        #expect(BudgetStore.parse("") == .erase)
        #expect(BudgetStore.parse("0") == .erase)

        // E o que ele não entende ele não ADIVINHA. O teto do mês de alguém é a última coisa
        // sobre a qual este app deveria dar um palpite.
        #expect(BudgetStore.parse("quarenta") == .invalid)
        #expect(BudgetStore.parse("-10") == .invalid)
    }

    @Test("o denominador não trunca: quem digitou 37,50 não lê '/ 37'")
    func tetoComCentavosNaoTrunca() throws {
        let lane = try #require(Lane.budget(spentUSD: 18.75, capUSD: 37.50, now: Self.hoje()))
        #expect(lane.displayUnitSuffix == "/ 37,50")
        #expect(lane.displayValue == "US$ 18,75")
        #expect(abs((lane.used ?? 0) - 50) < 0.001)

        // E o teto redondo continua redondo: o Cursor lê "/ 20", não "/ 20,00".
        #expect(Lane.cap(20) == "20")
        #expect(Lane.cap(1234.5) == "1.234,50")
    }

    // MARK: - O disco é mutável

    @Test("o número pode DIMINUIR entre dois refreshes — e a pista aguenta, sem inventar nada")
    func oDiscoEncolhe() throws {
        // O Claude reescreveu uma sessão de julho e US$ 12 sumiram do passado. Não houve
        // estorno nenhum: o disco é que não prova mais aquele gasto.
        let antes = try #require(Lane.budget(spentUSD: 68.40, capUSD: 200, now: Self.hoje()))
        let depois = try #require(Lane.budget(spentUSD: 56.40, capUSD: 200, now: Self.hoje()))

        #expect((depois.used ?? 0) < (antes.used ?? 0))
        // O que ela NÃO faz: virar `nil`, virar zero, ou congelar no valor velho pra "não
        // assustar". Ela anda pra trás e a tela diz por quê (MainWindowView.budgetNote).
        #expect(abs((depois.used ?? 0) - 28.2) < 0.001)
        #expect(depois.certainty.hasInk)
    }
}
