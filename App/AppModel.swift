import AppKit
import Foundation
import Observation
import ServiceManagement
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
    /// O tema escolhido. Muda a tela na hora e sobrevive ao relaunch (persistido).
    private(set) var theme: Theme = ThemeStore.current
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
            // O despejo do hook statusLine. É a ÚNICA fonte do "quanto resta" do Claude,
            // e ela chega por EVENTO — o hook dispara a cada redesenho da statusline.
            // Sem vigiar esta pasta, o número novo só apareceria na próxima vez que um
            // JSONL mexesse, e a tela mostraria um "medido" velho sem motivo.
            "\(home)/Library/Application Support/MyTokens",
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
        path.contains("/.claude/projects/")
            || path.contains("/.codex/sessions/")
            || path.hasSuffix("/MyTokens/statusline.json")
    }

    /// O usuário abriu o popover ou a janela. Força uma coleta.
    ///
    /// É o que mantém o Cursor honesto: ele muda por REDE, não por disco, então o FSEvents
    /// nunca acorda por causa dele. Se o usuário só usa o Cursor (Claude e Codex parados),
    /// nada dispararia o refresh — e o número ficaria velho. Abrir a tela é o gatilho.
    /// O TTL do CursorCollector (5 min) segura a rede: abrir e fechar dez vezes bate uma vez.
    func refreshOnOpen() {
        scheduleRefresh(delay: .zero)
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

    // MARK: - "conectar"
    //
    // O botão aparece em toda pista sem tinta. Ele NÃO pode ser um enfeite: se anuncia
    // que dá pra conectar, tem que entregar alguma coisa. E hoje ele não pode entregar o
    // número — o Jair escolheu a opção D do docs/STATUSLINE.md, e o app não escreve um
    // byte em ~/.claude sem autorização por escrito.
    //
    // Então ele entrega o que é POSSÍVEL entregar sem escrever nada: a VERDADE sobre por
    // que aquele número não existe. Cada provedor não sabe pelo seu próprio motivo, e
    // esconder isso atrás de um "não disponível" genérico seria trocar uma mentira por
    // uma preguiça.
    func connect(_ provider: Provider) {
        let alerta = NSAlert()
        alerta.alertStyle = .informational
        alerta.messageText = motivo(provider).titulo
        alerta.informativeText = motivo(provider).corpo
        alerta.addButton(withTitle: "Entendi")

        // App `.accessory` não é ativado por ninguém — sem isto o painel nasce atrás.
        NSApp.activate(ignoringOtherApps: true)
        alerta.runModal()
    }

    private func motivo(_ provider: Provider) -> (titulo: String, corpo: String) {
        switch provider {
        case .claudeCode:
            (
                "O hook do statusLine não está instalado.",
                """
                O quanto você JÁ GASTOU eu leio do disco. O quanto RESTA não está em arquivo \
                nenhum: o Claude Code recebe esse número nos headers HTTP e guarda só em \
                memória. Ele passa por UM lugar — o stdin do hook `statusLine` — e some.

                Para capturá-lo, rode:

                    ./scripts/statusline-install.sh

                Ele instala um wrapper de 5 linhas que guarda o número e chama o SEU \
                statusLine atual, intacto. Não é um binário nosso no caminho: se você \
                desinstalar o MyTokens, sua statusline continua funcionando igual.
                Desfaz com ./scripts/statusline-uninstall.sh — e o settings.json volta byte \
                a byte.

                Até lá, o app prefere dizer "não sei" a inventar uma porcentagem.
                """
            )
        case .codex:
            (
                "O Codex está sem janela válida.",
                """
                Este eu leio de graça: o Codex grava os limites no próprio rollout, e nada \
                precisa ser conectado.

                Só que a janela de 5 h foi REMOVIDA pela OpenAI em 12/07/2026, e a semanal \
                que está no disco já venceu. Mostrar a porcentagem de um bloco morto seria \
                um número velho fingindo ser o de agora.

                Assim que você usar o Codex de novo, o limite aparece aqui sozinho.
                """
            )
        case .cursor:
            (
                "Não encontrei sua sessão do Cursor.",
                """
                O Cursor não guarda uso no disco — o número vive no servidor dele. Para \
                lê-lo, o app reusa a sessão que o próprio Cursor já mantém na sua máquina \
                (o accessToken em state.vscdb) e pergunta ao cursor.com quanto você já usou.

                Se esta pista está vazia, é porque essa sessão não foi encontrada, expirou, \
                ou o computador está sem rede. Abra o Cursor e faça login uma vez — no \
                próximo refresh o número aparece.

                A sua credencial nunca é registrada, salva nem enviada a lugar nenhum além \
                do próprio cursor.com.
                """
            )
        }
    }

    func togglePause() {
        isPaused.toggle()
        if !isPaused { scheduleRefresh(delay: .zero) }
    }

    // MARK: - Os controles do app

    /// O que a `PopoverView` precisa pra desenhar o menu do rodapé.
    var controls: AppControls {
        AppControls(
            isPaused: isPaused,
            launchesAtLogin: launchesAtLogin,
            theme: theme,
            togglePause: { [weak self] in self?.togglePause() },
            toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            setTheme: { [weak self] in self?.setTheme($0) },
            quit: { NSApplication.shared.terminate(nil) }
        )
    }

    func setTheme(_ t: Theme) {
        guard t != theme else { return }
        theme = t
        ThemeStore.current = t   // sobrevive ao relaunch
    }

    /// `nil` = o sistema não sabe dizer, e aí a opção SOME do menu em vez de mentir.
    ///
    /// `.notFound` acontece de verdade: um app rodando de dentro do DerivedData não é um
    /// app instalado, e o macOS se recusa a registrá-lo pro login. Mostrar um toggle que
    /// falha em silêncio seria pior que não mostrar nada.
    private var launchesAtLogin: Bool? {
        switch SMAppService.mainApp.status {
        case .enabled: true
        case .notRegistered: false
        case .requiresApproval: true   // registrado; o usuário é que barrou em Ajustes
        case .notFound: nil
        @unknown default: nil
        }
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchesAtLogin == true {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Falhou de verdade (app fora de /Applications, permissão negada). Diz o que
            // houve — engolir o erro deixaria um toggle que não toggla e ninguém explica.
            let a = NSAlert()
            a.messageText = "Não consegui mexer no início automático."
            a.informativeText = """
                \(error.localizedDescription)

                O macOS só registra apps INSTALADOS. Se o MyTokens está rodando direto da \
                pasta de build do Xcode, mova-o para /Applications primeiro.
                """
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
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
