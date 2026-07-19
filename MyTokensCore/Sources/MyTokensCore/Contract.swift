// Tipos do contrato `contrato-dados` (v1.3). Fronteira Core <-> Views.
// Mudou aqui? Atualiza a nota e avisa o Vitral ANTES.
//
// v1.3 (ADITIVO): LimitWindow ganhou modelScope. O Claude passou a publicar limite
// POR MODELO (ex: semanal do Fable) além do limite da conta; sem este campo a view
// não distingue "conta inteira" de "só este modelo" sem parsear o `id` — gambiarra.
// nil = conta inteira, comportamento antigo intacto.
//
// v1.2 (ADITIVO): LimitWindow absorveu os campos que a view pedia e que o mirror dela
// carregava em paralelo — startedAt, measuredAt, measuredPercent, lo/hi, burnRatePerHour,
// unit, capUSD. Todos Optional: quem não sabe, não preenche, e a view degrada com
// honestidade (sem faixa, sem projeção, sem costura) em vez de inventar.
// Com isso o ContractMirror MORREU: existe UM contrato, e ele mora aqui.
//
// v1.1 (ADITIVO — não quebra a view): TokenBuckets ganhou cacheWrite5m/cacheWrite1h.
// Motivo: o disco separa cache_creation em ephemeral_5m e ephemeral_1h, e o
// pricing.json cobra 1.25x input pro 5m e 2x input pro 1h. Colapsar os dois num
// `cacheWrite` só erra o custo em até 60% NESSE bucket. `cacheWrite` continua sendo
// o TOTAL (5m + 1h) — a view pode seguir lendo só ele e ignorar o detalhe.

import Foundation

public enum Provider: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case codex
    case cursor

    /// Copy do app é pt-BR; identificador de código é inglês (regras-repo #11).
    public var displayName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

public struct TokenBuckets: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    /// cache_creation — custa MAIS que input. Total de cacheWrite5m + cacheWrite1h.
    public var cacheWrite: Int
    /// cache_read — custa ~10x MENOS que input.
    public var cacheRead: Int
    /// só Codex. É SUBCONJUNTO de `output` — não somar de novo, é informativo.
    public var reasoning: Int?

    /// Detalhe do cacheWrite por TTL. Ausente = sem detalhe no disco; trate como 5m.
    public var cacheWrite5m: Int?
    public var cacheWrite1h: Int?

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheWrite: Int = 0,
        cacheRead: Int = 0,
        reasoning: Int? = nil,
        cacheWrite5m: Int? = nil,
        cacheWrite1h: Int? = nil
    ) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.reasoning = reasoning
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    /// Soma dos 4 buckets. `reasoning` NÃO entra: já está dentro de `output`.
    public var total: Int { input + output + cacheWrite + cacheRead }

    public static func + (a: TokenBuckets, b: TokenBuckets) -> TokenBuckets {
        TokenBuckets(
            input: a.input + b.input,
            output: a.output + b.output,
            cacheWrite: a.cacheWrite + b.cacheWrite,
            cacheRead: a.cacheRead + b.cacheRead,
            reasoning: sumOptional(a.reasoning, b.reasoning),
            cacheWrite5m: sumOptional(a.cacheWrite5m, b.cacheWrite5m),
            cacheWrite1h: sumOptional(a.cacheWrite1h, b.cacheWrite1h)
        )
    }

    public static func += (a: inout TokenBuckets, b: TokenBuckets) { a = a + b }

    private static func sumOptional(_ a: Int?, _ b: Int?) -> Int? {
        guard a != nil || b != nil else { return nil }
        return (a ?? 0) + (b ?? 0)
    }
}

public struct UsageEvent: Codable, Sendable, Identifiable, Equatable {
    /// = sourceId. CHAVE DE DEDUP.
    /// Claude: requestId (fallback message.id). Codex: rolloutFile + índice.
    /// Sem dedup por essa chave o total infla 2,12x. MEDIDO, não teórico.
    public var id: String
    public var provider: Provider
    public var ts: Date
    public var sessionId: String
    public var model: String
    /// slug do cwd, quando existir.
    public var project: String?
    public var tokens: TokenBuckets
    /// calculado no CORE. NUNCA na view. Decimal, não Double.
    public var costUSD: Decimal

    public init(
        id: String,
        provider: Provider,
        ts: Date,
        sessionId: String,
        model: String,
        project: String? = nil,
        tokens: TokenBuckets,
        costUSD: Decimal
    ) {
        self.id = id
        self.provider = provider
        self.ts = ts
        self.sessionId = sessionId
        self.model = model
        self.project = project
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public enum WindowSource: String, Codable, Sendable {
    /// o provedor NOS DEU o número.
    ///   Claude → statusLine hook: rate_limits.five_hour/seven_day.used_percentage
    ///   Codex  → rollout: rate_limits.secondary (a primary/5h morreu em 2026-07-12)
    case measured
    /// NÓS calculamos. Fallback aproximado — o denominador não é publicado.
    case derived
}

/// A unidade do limite. Quase tudo é fração de cota (%); o Cursor é crédito em dólar.
/// Rotular "32%" onde a verdade é "US$ 6,40 de 20" é a mentira que o UI-SPEC §12.2 mata.
public enum WindowUnit: String, Codable, Sendable {
    case percent
    case usd
}

public struct LimitWindow: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var label: String        // "5 horas" | "Semana"
    /// A melhor estimativa AGORA. 0...100 — fração DA JANELA, sempre.
    public var usedPercent: Double
    public var resetsAt: Date
    public var source: WindowSource

    /// Quando a janela ABRIU. É o que permite desenhar o cursor do "agora" na pista:
    /// o vão entre a tinta (cota queimada) e o cursor (tempo decorrido) É a resposta do
    /// app. Sem isto, a pista mostra meia leitura.
    public var startedAt: Date?

    /// Quando o valor medido chegou. Obrigatório quando `source == .measured`:
    /// o hook `statusLine` só dispara ENQUANTO o Claude Code roda, logo todo medido
    /// TEM IDADE. Fingir que é de agora é a mentira mais fácil de cometer aqui.
    public var measuredAt: Date?

    /// O valor que foi de fato MEDIDO em `measuredAt` — não o de agora.
    /// A diferença pro `usedPercent` é, literalmente, o pedaço que a gente inferiu do
    /// disco depois: é onde a barra composta costura fato e palpite.
    ///   measuredPercent == usedPercent → sólido puro
    ///   measuredPercent <  usedPercent → composta (fato + palpite)
    public var measuredPercent: Double?

    /// Piso e teto plausíveis. Só fazem sentido quando `source == .derived`.
    /// Sem faixa, o reticulado é um borrão bonito; com faixa, é estatística.
    public var lo: Double?
    public var hi: Double?

    /// Pontos de % por hora nos últimos 20 min. Alimenta a projeção da view, que só
    /// aparece acima de 70% — abaixo disso é ruído. `nil` = sem projeção, e tudo bem.
    public var burnRatePerHour: Double?

    public var unit: WindowUnit
    /// Teto em US$ quando `unit == .usd`. `nil` em %.
    public var capUSD: Decimal?

    /// Modelo a que o limite se aplica. `nil` = conta inteira (todos os modelos).
    /// Ex: "fable" para o limite semanal do Fable. String livre de propósito:
    /// modelo novo no provedor não pode exigir mudança de contrato.
    public var modelScope: String?

    public init(
        id: String,
        label: String,
        usedPercent: Double,
        resetsAt: Date,
        source: WindowSource,
        startedAt: Date? = nil,
        measuredAt: Date? = nil,
        measuredPercent: Double? = nil,
        lo: Double? = nil,
        hi: Double? = nil,
        burnRatePerHour: Double? = nil,
        unit: WindowUnit = .percent,
        capUSD: Decimal? = nil,
        modelScope: String? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.source = source
        self.startedAt = startedAt
        self.measuredAt = measuredAt
        self.measuredPercent = measuredPercent
        self.lo = lo
        self.hi = hi
        self.burnRatePerHour = burnRatePerHour
        self.unit = unit
        self.capUSD = capUSD
        self.modelScope = modelScope
    }
}

public struct Spend: Codable, Sendable, Equatable {
    public var tokens: Int
    public var costUSD: Decimal
    public var byModel: [String: Int]

    public init(tokens: Int = 0, costUSD: Decimal = 0, byModel: [String: Int] = [:]) {
        self.tokens = tokens
        self.costUSD = costUSD
        self.byModel = byModel
    }
}

public struct ProviderStatus: Codable, Sendable {
    public var id: Provider { provider }
    public var provider: Provider
    public var connected: Bool
    /// VAZIO = não sabemos. A view mostra estado honesto, nunca zero.
    public var windows: [LimitWindow]
    public var today: Spend
    public var week: Spend
    public var month: Spend
    public var lastEventAt: Date?

    public init(
        provider: Provider,
        connected: Bool = false,
        windows: [LimitWindow] = [],
        today: Spend = Spend(),
        week: Spend = Spend(),
        month: Spend = Spend(),
        lastEventAt: Date? = nil
    ) {
        self.provider = provider
        self.connected = connected
        self.windows = windows
        self.today = today
        self.week = week
        self.month = month
        self.lastEventAt = lastEventAt
    }
}

extension ProviderStatus: Identifiable {}

/// O único jeito de plugar um provider novo: um tipo novo conformando isso.
/// Zero mudança no resto.
public protocol UsageCollector: Sendable {
    var provider: Provider { get }
    func collect() async throws -> (events: [UsageEvent], status: ProviderStatus)
}
