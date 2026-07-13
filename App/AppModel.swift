import Foundation
import Observation
import MyTokensCore
import MyTokensUI

/// O coordenador: FSEvents acorda → debounce → o core coleta → o ícone e a janela mudam.
///
/// O app inteiro é reativo a disco. NÃO existe timer em lugar nenhum — é essa ausência
/// que segura a CPU ociosa em ~0%. Parado, o processo não executa uma instrução.
///
/// O trabalho pesado (parsear 1,4 GB de JSONL) mora no `MyTokensEngine`, que é um actor:
/// roda fora da MainActor e nunca engasga a barra de menu.
@MainActor
@Observable
final class AppModel {

    /// Vive o app inteiro e precisa ligar no LAUNCH, não no primeiro clique do menu.
    static let shared = AppModel()

    private(set) var statuses: [ProviderStatus] = []
    /// O que a tela desenha. Nasce VAZIO — e vazio, aqui, é um estado honesto com nome
    /// e desenho próprios, não um dashboard de zeros esperando dado chegar.
    private(set) var dashboard = Dashboard(lanes: [])
    private(set) var lastRefresh: Date?
    private(set) var lastDuration: TimeInterval?
    private(set) var isPaused = false
    /// Quantas vezes o DISCO nos acordou. É a prova, em QA, de que isto é evento e não polling.
    private(set) var wakeCount = 0
    /// Se o motor nem subiu (ex.: pricing.json corrompido), a tela DIZ isso.
    /// Não finge que está tudo bem mostrando zero.
    private(set) var engineError: String?

    @ObservationIgnored private let engine: MyTokensEngine?
    @ObservationIgnored private var watcher: FSEventsWatcher?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    init() {
        do {
            engine = try MyTokensEngine()
        } catch {
            engine = nil
            engineError = String(describing: error)
        }
    }

    /// Os diretórios-fonte. READ-ONLY, sempre (regra 3 do `regras-repo`).
    /// O app JAMAIS escreve aqui — nem em ~/.claude/settings.json. Ver docs/STATUSLINE.md:
    /// o hook do statusLine é a única fonte do "restante" do Claude, e instalá-lo exige
    /// autorização explícita do usuário porque ESCREVE na casa dele.
    static var sourcePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.claude/projects",
            "\(home)/.codex/sessions",
        ]
    }

    var armedPaths: [String] { watcher?.armedPaths ?? [] }

    func start() {
        guard watcher == nil else { return }

        let watcher = FSEventsWatcher(paths: Self.sourcePaths)
        self.watcher = watcher

        pumpTask = Task { [weak self] in
            for await paths in watcher.changes {
                guard let self else { return }
                guard paths.contains(where: Self.isInteresting) else { continue }
                self.wakeCount += 1
                self.scheduleRefresh()
            }
        }

        // Uma leitura no boot, pra tela não nascer vazia. Depois disso, só o disco manda.
        scheduleRefresh(delay: .zero)
    }

    /// Armamos diretórios largos (às vezes o PAI, quando o alvo ainda não existe), então
    /// filtramos aqui. ~/.claude ferve de ruído (statsig, todos, shell-snapshots): acordar
    /// o motor por causa de um arquivo de telemetria seria queimar CPU do usuário à toa.
    private static func isInteresting(_ path: String) -> Bool {
        path.contains("/.claude/projects/") || path.contains("/.codex/sessions/")
    }

    /// Debounce: uma rajada de writes vira UMA coleta.
    /// O FSEvents já coalesce no kernel (latency 1s); isto é o segundo cinto, pro caso de
    /// os dois diretórios acordarem juntos.
    private func scheduleRefresh(delay: Duration = .milliseconds(400)) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard !isPaused, let engine else { return }

        // `engine` é um actor: o parsing acontece fora da MainActor, sozinho.
        let snapshot = await engine.refresh()

        statuses = snapshot.statuses
        dashboard = Dashboard(snapshot)
        lastRefresh = snapshot.generatedAt
        lastDuration = snapshot.duration
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused { scheduleRefresh(delay: .zero) }
    }

    // MARK: - o ícone

    /// Regra do Prisma (UI-SPEC §9): o ícone mostra UM provedor — o de MENOR FOLGA.
    /// E a textura do topo é a DESSE provedor: se o mais apertado for um Claude sem hook,
    /// o topo sai pontilhado. Três provetas em 22 px não é informação, é sujeira.
    var iconState: StatusIcon.State {
        let base = iconBase
        return isPaused ? .paused(base) : lift(base)
    }

    private var iconBase: StatusIcon.State.Base {
        // `Dashboard.tightest` é a de MENOR FOLGA (cota queimada vs. tempo decorrido) —
        // não a de maior %. Uma pista em 80% que zera em 10 min aperta MENOS que uma em
        // 60% que zera daqui a 4 dias, e é a que aperta que responde "posso continuar?".
        guard let lane = dashboard.tightest, let used = lane.used else {
            return .noData  // ninguém deu número. Vazio honesto — nunca um zero.
        }
        guard used < 100 else { return .overflow }

        let level = StatusIcon.quantize(percent: used)
        // Composta e derivada saem as DUAS reticuladas: a ponta das duas é palpite.
        // Só o medido puro ganha tinta sólida.
        if case .measured = lane.certainty {
            return .measured(level)
        }
        return .derived(level)
    }

    private func lift(_ base: StatusIcon.State.Base) -> StatusIcon.State {
        switch base {
        case .noData: .noData
        case .measured(let l): .measured(level: l)
        case .derived(let l): .derived(level: l)
        case .overflow: .overflow
        }
    }
}
