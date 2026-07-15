//  History.swift
//
//  O PASSADO — a única coisa que o app já sabia e jogava fora na fronteira.
//
//  O `Snapshot` do core sempre teve os últimos 30 dias, o gasto por projeto e o gasto por
//  modelo: eles saem de `byDay()`, `byProject()`, `byModel()` desde a Fase 1. O que não
//  existia era um TIPO que a tela pudesse desenhar. `Dashboard` traduzia só o AGORA (as
//  pistas), e o resto do snapshot morria no `init`. Isto é a segunda metade daquela ponte.
//
//  ═══════════════════════════════════════════════════════════════════════════
//  AS DUAS AUSÊNCIAS, QUE NÃO SÃO A MESMA COISA
//
//    dia com registro e gasto zero  → `costUSD == 0`. É um FATO: eu li o disco e não
//                                     havia nada. A coluna não sobe — e é honesto.
//    dia SEM registro               → `costUSD == nil`. Não é zero. Zero é uma
//                                     afirmação ("você não gastou"), e eu não posso
//                                     provar isso: o disco do Claude é MUTÁVEL. Sessão
//                                     antiga é reescrita, compactada, apagada — e o
//                                     gasto de um dia de junho pode simplesmente sumir.
//
//  Um dia sem registro NÃO é um dia sem gasto. É um dia sem prova. A tela desenha os
//  dois diferente (hachura x nada) e diz isso por escrito, porque a diferença entre
//  "não gastei" e "não sei" é o produto inteiro.
//  ═══════════════════════════════════════════════════════════════════════════
//
//  E o dinheiro: o US$ daqui é DERIVADO do `pricing.json` — tokens do disco x preço de
//  tabela da API. NÃO é fatura. Ninguém neste app viu uma. Por isso toda tinta de custo
//  sai RETICULADA (a textura de "inferido", a mesma das pistas) e a seção carrega a
//  procedência por escrito, permanente. O que ele NÃO ganha é o til `~`: o til promete
//  uma faixa (`41–68`), e aqui não existe faixa a prometer — os tokens são exatos, o
//  preço é o de tabela. A incerteza não é de MAGNITUDE, é de NATUREZA: isto é uma
//  estimativa a preço de API, não a conta que você vai pagar. Isso se diz com palavra.

import Foundation
import MyTokensCore

public struct History: Sendable, Equatable {

    /// Um dia do trilho. `costUSD == nil` é ausência de REGISTRO — nunca um zero.
    public struct Day: Identifiable, Sendable, Equatable {
        public var id: Date { start }
        public let start: Date
        public let costUSD: Decimal?
        /// O corte DESTE dia — por projeto e por modelo. `nil` quando a fonte não permite
        /// derivar por dia (`History.assembled`, que só recebe agregados prontos do
        /// período inteiro, sem os eventos crus). Nesse caso a coluna existe mas não é
        /// selecionável: clicar nela não pode fingir um corte que ninguém calculou.
        public let breakdown: Breakdown?

        public struct Breakdown: Sendable, Equatable {
            public let projects: [Cut]
            public let models: [Cut]
            /// Gasto do dia que o disco não sabe atribuir a projeto nenhum. Mesma regra
            /// do total do período: existe pra a coluna do dia FECHAR com o `costUSD` dele.
            public let unattributedUSD: Decimal

            public init(projects: [Cut], models: [Cut], unattributedUSD: Decimal) {
                self.projects = projects
                self.models = models
                self.unattributedUSD = unattributedUSD
            }
        }

        public init(start: Date, costUSD: Decimal?, breakdown: Breakdown? = nil) {
            self.start = start
            self.costUSD = costUSD
            self.breakdown = breakdown
        }

        public var hasRecord: Bool { costUSD != nil }
        /// Pode virar seleção fixa no trilho? Só quando o dia carrega seu próprio corte.
        public var isSelectable: Bool { breakdown != nil }
    }

    /// Uma fatia do bolo: um projeto ou um modelo. Só entra quem CUSTOU.
    /// Projeto sem evento não vira uma linha de `US$ 0,00` — não vira linha nenhuma.
    public struct Cut: Identifiable, Sendable, Equatable {
        public var id: String { key }
        /// A chave crua do core ("mytokens", "claude-opus-4-8").
        public let key: String
        /// O nome escrito pro humano. Igual à chave quando não conhecemos o formato.
        public let label: String
        public let costUSD: Decimal
        /// 0...1 do total do período. É a largura da tinta na pista da linha.
        public let share: Double

        public init(key: String, label: String, costUSD: Decimal, share: Double) {
            self.key = key
            self.label = label
            self.costUSD = costUSD
            self.share = share
        }
    }

    /// O que sobrou fora do top-N. Não é "outros" no sentido de resto de pizza — é a
    /// cauda, e ela tem tamanho e nome de gente: "+ 81 projetos".
    public struct Rest: Sendable, Equatable {
        public let count: Int
        public let costUSD: Decimal
    }

    /// Do mais VELHO ao mais NOVO. O último é HOJE — e hoje ainda está em curso.
    public let days: [Day]
    /// Ordenados por custo, desc. Todos — o corte do top-N é da view (`History.top`).
    public let projects: [Cut]
    public let models: [Cut]
    /// Gasto real que o disco não sabe atribuir a projeto nenhum (evento sem `cwd`).
    /// Existe pra que a soma da coluna BATA com o trilho. Um resto que não fecha a conta
    /// é a maneira mais silenciosa de um dashboard mentir.
    public let unattributedUSD: Decimal
    public let totalUSD: Decimal
    /// O evento mais antigo que o disco AINDA tem — de qualquer época, não só da janela.
    /// Se ele for de dentro dos 30 dias, os dias anteriores não são dias parados: são
    /// dias que o disco não guarda. A frase muda por causa disto.
    public let firstRecordAt: Date?
    /// Queimou nos últimos 5 min. É o que acende o ember na coluna de hoje —
    /// calor é ATIVIDADE, e hoje é o único dia que ainda pode estar quente.
    public let liveToday: Bool

    public init(
        days: [Day],
        projects: [Cut],
        models: [Cut],
        unattributedUSD: Decimal = 0,
        totalUSD: Decimal,
        firstRecordAt: Date? = nil,
        liveToday: Bool = false
    ) {
        self.days = days
        self.projects = projects
        self.models = models
        self.unattributedUSD = unattributedUSD
        self.totalUSD = totalUSD
        self.firstRecordAt = firstRecordAt
        self.liveToday = liveToday
    }

    /// Nada lido ainda. NÃO é "trinta dias zerados" — é a ausência do trilho inteiro,
    /// e a seção simplesmente não existe na tela. Um trilho de trinta colunas vazias
    /// antes do primeiro scan seria um instrumento afirmando o que ainda não mediu.
    public static let empty = History(days: [], projects: [], models: [], totalUSD: 0)

    // MARK: - Leituras

    public var hasAnyRecord: Bool { days.contains(where: \.hasRecord) }

    /// Dias da janela que o disco não prova. É o número que a ressalva cita.
    public var daysWithoutRecord: Int { days.filter { !$0.hasRecord }.count }

    /// O pior dia. É o que fixa a escala da graduação — e é a única leitura que o
    /// trilho entrega sem hover.
    public var peak: Day? {
        days.filter(\.hasRecord).max { ($0.costUSD ?? 0) < ($1.costUSD ?? 0) }
    }

    /// O corte do top-N + a cauda. Mora aqui, e não na view: a view não faz conta.
    public static func top(_ cuts: [Cut], _ n: Int) -> (shown: [Cut], rest: Rest?) {
        guard cuts.count > n else { return (cuts, nil) }
        let shown = Array(cuts.prefix(n))
        let tail = cuts.dropFirst(n)
        return (shown, Rest(count: tail.count, costUSD: tail.reduce(Decimal(0)) { $0 + $1.costUSD }))
    }
}

// MARK: - Do snapshot pro trilho
//
// UMA passada sobre os eventos. Não é preciosismo: é orçamento.
//
// O caminho óbvio — `snapshot.byDay()` + `byProject()` + `byModel()` — custa 150 ms sobre
// o disco real do Jair (68 mil eventos, 39 mil deles nos últimos 30 dias). MEDIDO, não
// teórico. Ele varre os eventos TRÊS vezes, chama o `Calendar` uma vez por evento e monta
// um dicionário `byModel` dentro de cada balde do dia. O refresh incremental inteiro tem
// orçamento de 200 ms e hoje gasta 202 — somar 150 seria dobrar o custo de cada FSEvent.
//
// Esta passada única faz o mesmo em ~45 ms: acha o dia por busca binária num vetor de 30
// fronteiras pré-calculadas (30 chamadas de `Calendar`, não 39 mil) e soma projeto e modelo
// no mesmo laço. Os números são IDÊNTICOS aos do `Aggregator` — e existe um teste que
// prova isso a cada CI, porque duplicar agregação sem uma prova de equivalência é assinar
// um cheque em branco pro dia em que os dois divergirem em silêncio.
//
// A busca binária não assume ordem: o engine entrega os eventos ordenados, mas um trilho
// que depende disso quebraria caladinho no dia em que alguém mexer no `sort`.

extension History {

    public init(
        _ snapshot: MyTokensCore.Snapshot,
        span: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        // O trilho não precisa de mais nada do snapshot além dos eventos. Ele nasce da mesma
        // lista crua que o `Aggregator` do core lê — e é isso que faz os dois serem
        // comparáveis num teste, em vez de "confia em mim".
        self.init(events: snapshot.events, span: span, now: now, calendar: calendar)
    }

    init(
        events: [UsageEvent],
        span: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        // As fronteiras dos dias. `startOfDay` respeita fuso e horário de verão — por isso
        // são datas de verdade, e não `now - 86400*k`: dia não tem 24 h em toda parte.
        let today = calendar.startOfDay(for: now)
        let starts: [Date] = (0..<span).compactMap {
            calendar.date(byAdding: .day, value: -(span - 1 - $0), to: today)
        }
        guard let cutoff = starts.first, starts.count == span else {
            self = .empty
            return
        }

        var cost = [Decimal](repeating: 0, count: span)
        var seen = [Bool](repeating: false, count: span)
        var byProject: [String: Decimal] = [:]
        var byModel: [String: Decimal] = [:]
        byProject.reserveCapacity(128)
        byModel.reserveCapacity(16)

        // O MESMO corte, por dia. Vive ao lado do agregado do período inteiro — a
        // passada continua sendo UMA só, e é por isso que o corte por dia não custa
        // uma segunda varredura do disco.
        var byProjectPerDay = [[String: Decimal]](repeating: [:], count: span)
        var byModelPerDay = [[String: Decimal]](repeating: [:], count: span)
        var attributedPerDay = [Decimal](repeating: 0, count: span)

        var oldest: Date?
        var newest: Date?
        var total = Decimal(0)
        var attributed = Decimal(0)

        for e in events {
            if oldest == nil || e.ts < oldest! { oldest = e.ts }
            if newest == nil || e.ts > newest! { newest = e.ts }
            guard e.ts >= cutoff else { continue }

            // Qual dia contém este evento. log2(30) ≈ 5 comparações de Date.
            var lo = 0, hi = span - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if e.ts >= starts[mid] { lo = mid } else { hi = mid - 1 }
            }

            // O REGISTRO existe mesmo quando o custo é zero: um modelo sem preço na tabela
            // (o `<synthetic>` do Claude) gera evento e não gera dinheiro. O dia foi lido —
            // ele só não custou. Isso é um fato, e fato não é ausência.
            seen[lo] = true
            cost[lo] += e.costUSD
            total += e.costUSD
            byModel[e.model, default: 0] += e.costUSD
            byModelPerDay[lo][e.model, default: 0] += e.costUSD
            if let p = e.project {
                byProject[p, default: 0] += e.costUSD
                attributed += e.costUSD
                byProjectPerDay[lo][p, default: 0] += e.costUSD
                attributedPerDay[lo] += e.costUSD
            }
        }

        let live = newest.map { now.timeIntervalSince($0) < Dashboard.liveWindow } ?? false

        self.init(
            days: (0..<span).map { i in
                Day(
                    start: starts[i],
                    costUSD: seen[i] ? cost[i] : nil,
                    breakdown: Day.Breakdown(
                        projects: Self.cuts(byProjectPerDay[i], total: cost[i]) { $0 },
                        models: Self.cuts(byModelPerDay[i], total: cost[i], label: Self.modelLabel),
                        unattributedUSD: max(0, cost[i] - attributedPerDay[i])
                    )
                )
            },
            projects: Self.cuts(byProject, total: total) { $0 },
            models: Self.cuts(byModel, total: total, label: Self.modelLabel),
            unattributedUSD: max(0, total - attributed),
            totalUSD: total,
            firstRecordAt: oldest,
            liveToday: live
        )
    }

    /// Vira fatia quem custou. `> 0`, e não `>= 0`: um projeto que não custou nada não
    /// aparece como `US$ 0,00` — ele não aparece. Zero é uma afirmação e ocupa uma linha
    /// que pertence a quem tem o que dizer.
    private static func cuts(
        _ raw: [String: Decimal],
        total: Decimal,
        label: (String) -> String = { $0 }
    ) -> [Cut] {
        let denom = (total as NSDecimalNumber).doubleValue
        return raw
            .filter { $0.value > 0 }
            .map { key, value in
                Cut(
                    key: key,
                    label: label(key),
                    costUSD: value,
                    share: denom > 0 ? (value as NSDecimalNumber).doubleValue / denom : 0
                )
            }
            .sorted {
                // Empate no custo (dois projetos com o mesmo centavo) desempata pelo nome —
                // senão a ordem vem do hash do dicionário e as linhas DANÇAM a cada refresh.
                $0.costUSD == $1.costUSD ? $0.key < $1.key : $0.costUSD > $1.costUSD
            }
    }

    /// `claude-opus-4-8` → `Opus 4.8`. Um id de modelo não é um nome — mas também não é
    /// um enigma, e escrever o id cru numa tela que fala português é preguiça.
    ///
    /// O que este método NÃO faz: adivinhar. Se o formato não é o conhecido, ele devolve
    /// o id LITERAL (`gpt-5.6-terra`, `<synthetic>`). Batizar de "GPT 5.6 Terra" um modelo
    /// cujo esquema de nome eu não conheço é a mesma família de mentira do zero: afirmar
    /// mais do que se sabe, por estética.
    static func modelLabel(_ id: String) -> String {
        let parts = id.split(separator: "-").map(String.init)
        guard parts.count >= 2, parts[0] == "claude" else { return id }

        let family = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        // O sufixo de data (`-20251001`) é carimbo de release, não versão. Ele some.
        let version = parts.dropFirst(2).filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        return version.isEmpty ? family : "\(family) \(version.joined(separator: "."))"
    }
}

// MARK: - Montagem à mão (mock e teste)

extension History {
    /// Monta um trilho a partir de valores literais. O total sai da SOMA DOS DIAS, e as
    /// fatias tiram sua fração dele — do mesmo jeito que sai do disco. Um mock cujos
    /// pedaços não fecham com o todo é um mock que valida uma tela que não existe.
    public static func assembled(
        dailyUSD: [Decimal?],
        projects: [(String, Decimal)],
        models: [(String, Decimal)],
        now: Date = Date(),
        calendar: Calendar = .current,
        liveToday: Bool = false
    ) -> History {
        let today = calendar.startOfDay(for: now)
        let n = dailyUSD.count
        let days: [Day] = dailyUSD.enumerated().compactMap { i, v in
            calendar.date(byAdding: .day, value: -(n - 1 - i), to: today).map { Day(start: $0, costUSD: v) }
        }
        let total = dailyUSD.compactMap { $0 }.reduce(Decimal(0), +)
        let denom = (total as NSDecimalNumber).doubleValue
        func cut(_ pairs: [(String, Decimal)], _ label: (String) -> String) -> [Cut] {
            pairs.filter { $0.1 > 0 }
                .map { Cut(key: $0.0, label: label($0.0), costUSD: $0.1,
                           share: denom > 0 ? ($0.1 as NSDecimalNumber).doubleValue / denom : 0) }
                .sorted { $0.costUSD > $1.costUSD }
        }
        let attributed = projects.reduce(Decimal(0)) { $0 + $1.1 }
        return History(
            days: days,
            projects: cut(projects, { $0 }),
            models: cut(models, modelLabel),
            unattributedUSD: max(0, total - attributed),
            totalUSD: total,
            firstRecordAt: days.first(where: \.hasRecord)?.start,
            liveToday: liveToday
        )
    }
}
