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
    /// O que a barra mostra ao lado da proveta. Persistido.
    private(set) var menuBarStyle: MenuBarStyle = MenuBarStyleStore.current
    /// Avisar quando uma janela cruza 85%. Persistido; nasce LIGADO.
    private(set) var notifyAt85: Bool = NotifyStore.current
    /// O teto de gasto mensal. Persistido, e nasce `nil`: NINGUÉM tem orçamento até dizer que
    /// tem. Um teto padrão seria o app inventando o bolso do usuário.
    private(set) var budgetUSD: Decimal? = BudgetStore.current
    /// O macOS barrou os avisos. O menu precisa saber pra não mostrar um ✓ que não avisa nada.
    private(set) var notificationsBlocked = false
    /// Quantas vezes o DISCO nos acordou. É a prova, em QA, de que isto é evento e não polling.
    private(set) var wakeCount = 0
    /// Se o motor nem subiu (ex.: pricing.json corrompido), a tela DIZ isso.
    /// Não finge que está tudo bem mostrando zero.
    private(set) var engineError: String?

    @ObservationIgnored private let engine: MyTokensEngine?
    /// Os dois avisos do UI-SPEC §7. Ele instala o delegate no init (barato, e sem diálogo
    /// nenhum) — a permissão só é pedida quando houver algo de verdade a dizer.
    @ObservationIgnored private let notifier = Notifier()
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

        // O PASSADO também é calculado fora da MainActor. Ele é a única coisa da tela que
        // varre TODOS os eventos do disco (68 mil, no disco do Jair) — ~45 ms de passada
        // única. É pouco, e continua sendo pouco justamente porque não roda aqui: 45 ms na
        // MainActor a cada FSEvent seriam 45 ms de barra de menu engasgada, e o app é olhado
        // 30x por dia. Ver Model/History.swift pro porquê de não ser `snapshot.byDay()`.
        let history = await Self.digest(snapshot)

        // O ANTERIOR, guardado antes de ser sobrescrito. É a única memória que o app tem do
        // que já era verdade — e é comparando as duas que se descobre uma TRAVESSIA (cruzar
        // 85%) em vez de um mero estado. Sem isso, "está em 90%" e "acabou de passar de 85%"
        // viram a mesma coisa, e o app avisaria a cada refresh.
        let anterior = dashboard

        statuses = snapshot.statuses
        dashboard = Dashboard(snapshot, history: history, budgetUSD: budgetUSD)
        lastRefresh = snapshot.generatedAt
        lastDuration = snapshot.duration

        // Nenhum timer entra aqui: o disco acorda o app, o app compara, e só então fala.
        await notifier.evaluate(previous: anterior, current: dashboard, enabled: notifyAt85)
        notificationsBlocked = notifier.isBlocked
    }

    /// Os 30 dias, o gasto por projeto e o gasto por modelo — num thread que não é o da
    /// interface. `Snapshot` e `History` são `Sendable`: a travessia é de graça e o
    /// compilador é quem garante, não um comentário.
    ///
    /// É `detached` de propósito: uma `Task {}` comum HERDA a MainActor e o cálculo
    /// aconteceria exatamente onde ele não pode acontecer.
    private static func digest(_ snapshot: Snapshot) async -> History {
        await Task.detached(priority: .userInitiated) { History(snapshot) }.value
    }

    // MARK: - "conectar"
    //
    // O botão aparece em toda pista sem tinta. Ele NÃO pode ser um enfeite: se anuncia que
    // dá pra conectar, tem que CONECTAR.
    //
    // Por muito tempo ele não conectava, e o motivo era bom: o "quanto resta" do Claude só
    // existe no stdin do hook `statusLine`, e instalar o hook ESCREVE em ~/.claude — a casa
    // do usuário, que este app trata como read-only. Então o botão fazia a única coisa
    // honesta que sabia fazer: explicava, e mandava o cara abrir um terminal.
    //
    // Isso era honesto e era um beco. O app SABE exatamente quais bytes precisam entrar. O
    // que faltava não era permissão técnica — era CONSENTIMENTO, e consentimento se pede
    // mostrando o que vai ser feito. Então o painel do Claude agora mostra o DIFF: o antes e
    // o depois, literais, do settings.json dele. Ele lê os bytes e clica. Ou não clica, e
    // nada acontece — nem um `mkdir`.
    //
    // Codex e Cursor continuam só explicando, e continuam certos em só explicar: o motivo
    // deles não tem conserto por hook nenhum, e um botão que fingisse que tem seria pior que
    // o beco.
    func connect(_ provider: Provider) {
        guard provider == .claudeCode else { return explicar(provider) }

        switch StatusLineHook.state() {
        case .ausente:
            oferecerInstalacao()

        case .instalado(let original):
            painelInstalado(original: original)

        case .quebrado(let motivo):
            // Um hook quebrado é PIOR que hook nenhum: a statusline do usuário some e ele não
            // sabe por quê. Este é o único painel do app que abre com um aviso, não com uma
            // explicação — porque aqui tem coisa quebrada AGORA, na casa dele, e é nossa.
            painelQuebrado(motivo: motivo)

        case .indeciso(let motivo):
            avisar(titulo: "Não consigo opinar sobre o seu ~/.claude/settings.json.",
                   corpo: motivo)
        }
    }

    /// O caminho sem ação: o app diz a verdade e não promete o que não pode cumprir.
    private func explicar(_ provider: Provider) {
        let m = motivo(provider)
        avisar(titulo: m.titulo, corpo: m.corpo)
    }

    private func avisar(titulo: String, corpo: String) {
        let alerta = NSAlert()
        alerta.alertStyle = .informational
        alerta.messageText = titulo
        alerta.informativeText = corpo
        alerta.addButton(withTitle: "Entendi")

        // App `.accessory` não é ativado por ninguém — sem isto o painel nasce atrás.
        NSApp.activate(ignoringOtherApps: true)
        alerta.runModal()
    }

    // MARK: - conectar o Claude: o diff, e só então a escrita

    /// O painel do consentimento informado. Ele mostra os BYTES — não uma promessa sobre os
    /// bytes. O usuário lê o diff do próprio settings.json e o conteúdo do wrapper que vai
    /// nascer, e só então existe um botão que escreve.
    ///
    /// Se o plano nem puder ser calculado (JSON que eu não sei ler, comando que aparece duas
    /// vezes no texto), o painel diz isso e NÃO oferece botão nenhum. Falhar fechado.
    private func oferecerInstalacao() {
        let plano: StatusLineHook.Plan
        do {
            plano = try StatusLineHook.plan()
        } catch {
            avisar(titulo: "Não consigo instalar o hook com segurança.",
                   corpo: error.localizedDescription)
            return
        }

        let alerta = NSAlert()
        alerta.alertStyle = .informational
        alerta.messageText = "Instalar o hook do statusLine?"
        alerta.informativeText = """
            O quanto você JÁ GASTOU eu leio do disco. O quanto RESTA não está em arquivo \
            nenhum: o Claude Code recebe esse número nos headers HTTP e guarda só em memória. \
            Ele passa por UM lugar — o stdin do hook `statusLine` — e some.

            Para capturá-lo eu preciso escrever em DOIS arquivos seus. Estão abaixo, byte a \
            byte, e nada acontece até você clicar.
            """
        alerta.accessoryView = Self.painelDeBytes(plano)
        alerta.addButton(withTitle: "Instalar o hook")
        alerta.addButton(withTitle: "Cancelar")

        NSApp.activate(ignoringOtherApps: true)
        guard alerta.runModal() == .alertFirstButtonReturn else { return }
        escrever(plano)
    }

    /// O único ponto do app que escreve em ~/.claude — e ele só é alcançado por um clique.
    private func escrever(_ plano: StatusLineHook.Plan) {
        do {
            let backup = try StatusLineHook.install(plano)
            avisar(titulo: "Pronto. O hook está de pé.", corpo: """
                Backup do seu settings.json anterior:
                \(StatusLineHook.tilde(backup))

                O número aparece aqui no PRÓXIMO turno do Claude Code — o hook só dispara \
                quando a statusline é redesenhada. Até lá a pista continua dizendo "não sei", \
                que continua sendo verdade.

                Pra desfazer: clique em "conectar" de novo (ou rode \
                ./scripts/statusline-uninstall.sh). O settings.json volta byte a byte.
                """)
            scheduleRefresh(delay: .zero)
        } catch {
            avisar(titulo: "Não consegui instalar o hook.", corpo: error.localizedDescription)
        }
    }

    /// Instalado — mas a pista está sem tinta, senão este painel nem teria sido aberto.
    /// Então ele explica POR QUE um hook instalado ainda não tem número, e oferece a porta de
    /// saída. Desinstalar não é nota de rodapé: é um botão, aqui, do mesmo tamanho.
    private func painelInstalado(original: String) {
        let quando: String
        if let d = StatusLineHook.lastCapture() {
            let f = DateFormatter()
            f.dateFormat = "dd/MM 'às' HH:mm"
            quando = "A última captura foi em \(f.string(from: d))."
        } else {
            quando = "Ainda não houve captura nenhuma — nenhum turno do Claude Code rodou "
                + "desde a instalação."
        }

        let alerta = NSAlert()
        alerta.alertStyle = .informational
        alerta.messageText = "O hook JÁ está instalado."
        alerta.informativeText = """
            \(quando)

            O hook só dispara enquanto o Claude Code está rodando: ele nasce no redesenho da \
            statusline e some. Com o Claude fechado, o número congela — e quando a janela dele \
            vence, o app prefere apagar a tinta a mostrar uma porcentagem de um bloco morto.

            \(original.isEmpty
                ? "O wrapper não chama statusLine nenhum: você não tinha um."
                : "O wrapper continua chamando o SEU statusLine, intacto:\n\(original)")
            """
        alerta.addButton(withTitle: "Fechar")
        alerta.addButton(withTitle: "Desinstalar o hook")

        NSApp.activate(ignoringOtherApps: true)
        guard alerta.runModal() == .alertSecondButtonReturn else { return }
        desinstalar()
    }

    private func painelQuebrado(motivo: String) {
        let alerta = NSAlert()
        alerta.alertStyle = .warning
        alerta.messageText = "O hook está QUEBRADO."
        alerta.informativeText = motivo
        alerta.addButton(withTitle: "Consertar (reinstalar)")
        alerta.addButton(withTitle: "Desinstalar o hook")
        alerta.addButton(withTitle: "Cancelar")

        NSApp.activate(ignoringOtherApps: true)
        switch alerta.runModal() {
        case .alertFirstButtonReturn: oferecerInstalacao()
        case .alertSecondButtonReturn: desinstalar()
        default: return
        }
    }

    private func desinstalar() {
        do {
            let backup = try StatusLineHook.uninstall()
            avisar(titulo: "Desinstalado. O settings.json voltou ao que era.", corpo: """
                O wrapper foi removido e o seu statusLine anterior está de volta, byte a byte.

                Backup de antes de desfazer: \(StatusLineHook.tilde(backup))

                O despejo em ~/Library/Application Support/MyTokens/ ficou — é DADO SEU, não \
                lixo nosso. O app volta a dizer "não sei quanto sobra", que continua sendo \
                verdade.
                """)
            scheduleRefresh(delay: .zero)
        } catch {
            avisar(titulo: "Não consegui desinstalar.", corpo: error.localizedDescription)
        }
    }

    /// O diff e o wrapper, em fonte monoespaçada, roláveis e SELECIONÁVEIS — o usuário tem
    /// que poder copiar os bytes e conferir por conta própria. Um "confie em mim" formatado
    /// em caixinha continua sendo um "confie em mim".
    private static func painelDeBytes(_ plano: StatusLineHook.Plan) -> NSView {
        var texto = """
            ── ~/.claude/settings.json ─ o que muda ──────────────────────────────

            \(plano.diff)

            ── ~/.mytokens/statusline.sh ─ arquivo NOVO ──────────────────────────

            \(plano.wrapperBody)
            ── e mais nada ───────────────────────────────────────────────────────

            Um backup do settings.json vai pra ~/.mytokens/backups/ ANTES da troca.
            O wrapper é testado com um payload falso ANTES de o settings.json mudar:
            se ele falhar, nada é alterado.
            """
        if plano.originalCommand.isEmpty {
            texto += "\n\nVocê não tem statusLine hoje: o wrapper só vai despejar o dado, "
                + "sem imprimir nada."
        }

        let campo = NSTextView(frame: .zero)
        campo.string = texto
        campo.isEditable = false
        campo.isSelectable = true
        campo.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        campo.textContainerInset = NSSize(width: 8, height: 8)
        // Sem quebra de linha: uma linha do diff quebrada no meio deixa de ser a linha que
        // vai pro arquivo. Quem tem que rolar é a caixa, não a verdade.
        campo.isHorizontallyResizable = true
        campo.textContainer?.widthTracksTextView = false
        campo.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 340))
        scroll.documentView = campo
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = false
        scroll.borderType = .bezelBorder
        return scroll
    }

    private func motivo(_ provider: Provider) -> (titulo: String, corpo: String) {
        switch provider {
        case .claudeCode:
            // Não é mais alcançável pelo `connect(_:)` — o Claude tem ação própria agora.
            // Fica porque o `motivo` é o inventário dos POR QUÊS do app, e o do Claude
            // continua sendo esse.
            (
                "O hook do statusLine não está instalado.",
                """
                O quanto você JÁ GASTOU eu leio do disco. O quanto RESTA não está em arquivo \
                nenhum: o Claude Code recebe esse número nos headers HTTP e guarda só em \
                memória. Ele passa por UM lugar — o stdin do hook `statusLine` — e some.
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

    // MARK: - O orçamento
    //
    // O único número da tela que não vem do disco: vem do usuário. E como ele é a régua com
    // que o app vai medir o dinheiro dele, o painel que o coleta tem UMA obrigação antes de
    // ter um campo de texto — dizer contra o quê ele vai ser medido.
    //
    // O app não pode prometer uma fatura. Ele lê tokens do disco e multiplica por um preço de
    // TABELA. É uma boa estimativa e não é a sua conta, e a diferença entre as duas coisas é
    // o produto inteiro. Um painel que só perguntasse "quanto você quer gastar?" e sumisse
    // estaria deixando o usuário assumir a coisa errada em silêncio.

    private func abrirPainelDoOrcamento() {
        let atual = budgetUSD

        let alerta = NSAlert()
        alerta.alertStyle = .informational
        alerta.messageText = atual == nil ? "Definir um orçamento mensal" : "Orçamento mensal"
        alerta.informativeText = """
            Um teto em US$ pro MÊS DO CALENDÁRIO — o mesmo mês da sua fatura, virando no dia \
            1º. A pista mede quanto do teto já foi; o cursor mede quanto do mês já passou. \
            Tinta atrás do cursor significa que você fecha o mês dentro do orçamento.

            O QUE ESTE NÚMERO NÃO É: a sua fatura. Ele é o token que ficou gravado no disco \
            multiplicado pelo preço PÚBLICO de tabela da API (pricing.json). Ninguém aqui viu \
            uma cobrança — por isso a tinta dessa pista sai reticulada, como todo custo neste app.

            E ele é um PISO, não um teto: o Claude reescreve e compacta sessões antigas, e \
            gasto some do passado. Um orçamento relê o mês inteiro a cada leitura, então este \
            número pode DIMINUIR entre dois refreshes sem que ninguém tenha devolvido um \
            centavo. O erro dele é sempre pro mesmo lado — ele subestima, nunca exagera.

            O Cursor fica de fora: ele não grava uso no disco, e o que publica é a fração de \
            um crédito já incluído no plano, no ciclo de cobrança dele — que não é o mês do \
            calendário.
            """

        let campo = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        campo.placeholderString = "dólares por mês — ex.: 40"
        campo.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        if let atual { campo.stringValue = Lane.cap(atual) }
        alerta.accessoryView = campo

        alerta.addButton(withTitle: "Salvar")
        // APAGAR mora AQUI, do mesmo tamanho do salvar — e só existe quando há o que apagar.
        // Um app que deixa definir e não deixa desfazer é uma armadilha; um que esconde o
        // desfazer atrás de um "edite o plist" é a mesma armadilha com uma nota de rodapé.
        if atual != nil { alerta.addButton(withTitle: "Apagar o orçamento") }
        alerta.addButton(withTitle: "Cancelar")

        NSApp.activate(ignoringOtherApps: true)
        // Depois do `layout()` o campo existe na janela e pode receber o foco. Sem isto, o
        // usuário abre um painel com um campo de texto e tem que clicar nele pra digitar.
        alerta.layout()
        alerta.window.makeFirstResponder(campo)

        switch alerta.runModal() {
        case .alertFirstButtonReturn:
            switch BudgetStore.parse(campo.stringValue) {
            case .value(let v):
                setBudget(v)
            case .erase:
                // Campo vazio (ou zero) no botão "Salvar" é um pedido legítimo de apagar, e
                // não um erro a esfregar na cara de ninguém. Zero dólares por mês não é um
                // orçamento — é a ausência de um.
                setBudget(nil)
            case .invalid:
                avisar(titulo: "Não entendi esse valor.", corpo: """
                    Escreva só o número, em dólares: "40" ou "37,50".

                    Eu podia tentar adivinhar o que você quis dizer, mas o teto do seu mês é a \
                    última coisa deste app sobre a qual eu deveria dar um palpite.
                    """)
            }

        case .alertSecondButtonReturn where atual != nil:
            setBudget(nil)

        default:
            return
        }
    }

    /// Definir, mudar ou apagar o teto. A pista nasce (ou some) NA HORA.
    ///
    /// Não passa por `scheduleRefresh`: o gasto do mês já está no `statuses` da última coleta
    /// — não há um byte novo a ler no disco, e esperar o próximo FSEvent pra desenhar uma
    /// coisa que o usuário ACABOU de pedir seria um app que não responde. Pior: com a leitura
    /// PAUSADA o `refresh()` volta na porta, e definir um orçamento com o app pausado é uma
    /// coisa perfeitamente razoável de se fazer.
    func setBudget(_ v: Decimal?) {
        guard v != budgetUSD else { return }
        budgetUSD = v
        BudgetStore.current = v   // sobrevive ao relaunch. `nil` APAGA a chave.
        dashboard = dashboard.withBudget(v, monthSpentUSD: Dashboard.monthSpentUSD(statuses))
    }

    // MARK: - Os controles do app

    /// O que a `PopoverView` precisa pra desenhar o menu do rodapé.
    /// O estado do hook, traduzido pro vocabulário da UI. O motivo do "quebrado" NÃO vem
    /// junto: o menu só precisa saber que está quebrado pra dizer isso alto; o porquê, com
    /// todo o detalhe, é assunto do painel — que é onde o usuário vai clicar em seguida.
    private var hookState: AppControls.HookState {
        switch StatusLineHook.state() {
        case .ausente: .ausente
        case .instalado: .instalado
        case .quebrado: .quebrado
        case .indeciso: .indeciso
        }
    }

    var controls: AppControls {
        AppControls(
            isPaused: isPaused,
            launchesAtLogin: launchesAtLogin,
            theme: theme,
            menuBarStyle: menuBarStyle,
            hook: hookState,
            openHookPanel: { [weak self] in self?.connect(.claudeCode) },
            budgetUSD: budgetUSD,
            openBudgetPanel: { [weak self] in self?.abrirPainelDoOrcamento() },
            notifyAt85: notifyAt85,
            notificationsBlocked: notificationsBlocked,
            togglePause: { [weak self] in self?.togglePause() },
            toggleLaunchAtLogin: { [weak self] in self?.toggleLaunchAtLogin() },
            setTheme: { [weak self] in self?.setTheme($0) },
            setMenuBarStyle: { [weak self] in self?.setMenuBarStyle($0) },
            toggleNotifyAt85: { [weak self] in self?.toggleNotifyAt85() },
            openNotificationSettings: { [weak self] in self?.notifier.openSystemSettings() },
            quit: { NSApplication.shared.terminate(nil) }
        )
    }

    /// Ligar NÃO abre o diálogo de permissão — o app não cobra autorização por um aviso que
    /// talvez nunca aconteça. Só relê o status (isso não abre diálogo nenhum), pra que o
    /// menu já diga a verdade se o macOS estiver barrando desde antes.
    func toggleNotifyAt85() {
        notifyAt85.toggle()
        NotifyStore.current = notifyAt85   // sobrevive ao relaunch
        guard notifyAt85 else {
            notificationsBlocked = false   // desligado por ESCOLHA não é "bloqueado"
            return
        }
        Task { [notifier] in
            await notifier.refreshBlocked()
            notificationsBlocked = notifier.isBlocked
        }
    }

    func setTheme(_ t: Theme) {
        guard t != theme else { return }
        theme = t
        ThemeStore.current = t   // sobrevive ao relaunch
    }

    func setMenuBarStyle(_ s: MenuBarStyle) {
        guard s != menuBarStyle else { return }
        menuBarStyle = s
        MenuBarStyleStore.current = s
    }

    /// O texto que a barra mostra ao lado da proveta, pro estilo escolhido. Vazio = só ícone.
    var menuBarText: String {
        dashboard.menuBarText(style: menuBarStyle)
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
