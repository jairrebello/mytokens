import Foundation

/// O hook `statusLine` — a ÚNICA porta pelo "quanto RESTA" do Claude.
///
/// Este arquivo é a exceção à regra 3 (as fontes são READ-ONLY). Ele é o único lugar do app
/// que ESCREVE em `~/.claude`. A exceção não é uma brecha: é uma porta, e ela tem fechadura.
/// Nada aqui roda sozinho. `plan()` calcula os bytes e NÃO escreve; `install(_:)` só existe
/// para ser chamado depois de o usuário ter VISTO esses bytes e clicado. Consentimento
/// informado é o diff na tela — não a caixa de "ok" numa frase genérica.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// POR QUE O WRAPPER É GERADO EM SWIFT, E NÃO CARREGADO DO BUNDLE
///
/// O wrapper não é um asset: ele EMBUTE o comando anterior do usuário, escapado pro `sh`.
/// Um "template" no bundle seria um literal com um buraco — e o buraco é a única parte
/// interessante. Trazê-lo do bundle custaria um recurso a mais para sumir (cópia, codesign,
/// grupo sincronizado classificando `.sh` como sabe-se lá o quê) e o sintoma dessa perda
/// seria justamente "o conectar não conecta". Um literal em Swift não some.
///
/// E o bundle seria só transporte: depois de instalado, NADA aqui é lido do app de novo. O
/// wrapper mora em `~/.mytokens/statusline.sh` — casa do usuário, caminho estável, calculado
/// de `NSHomeDirectory()`. Nunca o DerivedData, nunca o repo: um caminho que aponta pra
/// pasta de build de alguém é uma statusline que morre no primeiro `xcodebuild clean`.
///
/// O `scripts/statusline-install.sh` continua existindo e gera os MESMOS bytes, pra quem
/// prefere o terminal. Os dois caminhos convergem no mesmo arquivo.
enum StatusLineHook {

    // MARK: - Onde as coisas moram

    private static var home: String { NSHomeDirectory() }

    /// A casa do usuário, não a nossa. `~/.claude/settings.json`.
    static var settingsPath: String { "\(home)/.claude/settings.json" }

    /// O wrapper. Fora do bundle DE PROPÓSITO: se o app for apagado, este arquivo continua
    /// de pé e a statusline do usuário continua desenhando. É a promessa inteira do desenho.
    static var wrapperPath: String { "\(home)/.mytokens/statusline.sh" }

    private static var myDir: String { "\(home)/.mytokens" }
    private static var backupsDir: String { "\(myDir)/backups" }
    /// O comando que era do usuário ANTES de nós. É o que a desinstalação devolve.
    private static var originalCommandPath: String { "\(myDir)/original-command.txt" }
    /// Se o usuário NÃO tinha statusLine, nós INSERIMOS um bloco inteiro. Guardar os bytes
    /// exatos que entraram é o que permite tirá-los depois sem sobrar vírgula nem linha em
    /// branco. Desfazer "mais ou menos" não é desfazer.
    private static var insertedBlockPath: String { "\(myDir)/inserted-block.txt" }
    /// Onde o wrapper despeja o stdin. É o que o `ClaudeRateLimitReader` lê.
    private static var snapshotPath: String {
        "\(home)/Library/Application Support/MyTokens/statusline.json"
    }

    // MARK: - O estado, dito em voz alta

    /// Um hook QUEBRADO é pior que hook nenhum: a statusline do usuário simplesmente para de
    /// aparecer, e ele não faz ideia do porquê. Por isso `.quebrado` é um estado de primeira
    /// classe aqui, e não um `else` de `.instalado`.
    enum State: Sendable {
        /// O `statusLine` não é nosso (ou não existe). Nada foi escrito na casa dele.
        case ausente
        /// Instalado e são. `original` é o comando que o wrapper chama depois de despejar
        /// (vazio = o usuário não tinha statusLine nenhum antes de nós).
        case instalado(original: String)
        /// O settings.json aponta pra nós, mas o caminho não resolve. A statusline dele está
        /// MORTA agora.
        case quebrado(motivo: String)
        /// Não dá pra opinar: o settings.json não existe, ou não é JSON que eu saiba ler.
        case indeciso(motivo: String)
    }

    static func state() -> State {
        guard let raw = try? String(contentsOfFile: settingsPath, encoding: .utf8) else {
            return .indeciso(motivo: "Não encontrei \(tilde(settingsPath)).")
        }
        guard let root = parse(raw) else {
            return .indeciso(motivo: "O \(tilde(settingsPath)) não é um JSON que eu saiba ler. "
                + "Não encosto num arquivo que não entendo.")
        }

        let atual = command(in: root) ?? ""
        let fm = FileManager.default

        guard atual == wrapperPath else {
            // Aponta pra um MyTokens que NÃO é este caminho: instalação antiga, app movido,
            // wrapper de um repo que sumiu. Dizer "não instalado" aqui seria mentir — tem
            // coisa nossa (ou parecida com a nossa) no caminho, e ela pode estar morta.
            if atual.localizedCaseInsensitiveContains("mytokens") {
                return .quebrado(motivo: """
                    O seu statusLine aponta pra um MyTokens que não é este:

                        \(atual)

                    Este app instala o wrapper em \(tilde(wrapperPath)). \
                    Se aquele caminho não existir mais, sua statusline não está sendo \
                    desenhada — e é por isso, não por culpa do Claude.
                    """)
            }
            return .ausente
        }

        guard fm.fileExists(atPath: wrapperPath) else {
            return .quebrado(motivo: """
                O seu settings.json chama \(tilde(wrapperPath)) — e esse arquivo NÃO EXISTE.

                Isso significa que a sua statusline não está sendo desenhada AGORA. Reinstalar \
                recria o wrapper; desinstalar devolve o settings.json ao que era.
                """)
        }
        guard fm.isExecutableFile(atPath: wrapperPath) else {
            return .quebrado(motivo: """
                O wrapper \(tilde(wrapperPath)) existe mas não tem permissão de execução. \
                O Claude Code não consegue rodá-lo, e sua statusline não aparece.
                """)
        }

        let original = originalCommand()
        // O wrapper chama o comando ANTERIOR do usuário. Se o programa daquele comando sumiu
        // (o GSD desinstalou o hook dele, por exemplo), o wrapper roda, despeja o número — e
        // a statusline dele imprime um erro. O app é quem tem como perceber isso.
        if let sumiu = missingFile(in: original) {
            return .quebrado(motivo: """
                O wrapper está instalado e chama o SEU statusLine anterior:

                    \(original)

                Só que `\(sumiu)` não existe mais. O despejo continua funcionando, mas a sua \
                statusline está chamando um arquivo que sumiu.
                """)
        }

        return .instalado(original: original)
    }

    /// Quando o hook capturou o número pela última vez. `nil` = nunca capturou (ou o despejo
    /// foi apagado). Serve pra dizer "instalado, mas ainda não passou turno nenhum".
    static func lastCapture() -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: snapshotPath)[.modificationDate] as? Date
    }

    // MARK: - O plano: os bytes, antes de qualquer byte

    /// Tudo que a instalação VAI fazer, calculado sem escrever nada. É o que o painel mostra.
    struct Plan: Sendable {
        /// O texto CRU do settings.json de hoje.
        let before: String
        /// O texto CRU do settings.json depois. Já validado como JSON.
        let after: String
        /// O `before` e o `after` lado a lado, só as linhas que mudam, com contexto.
        let diff: String
        /// Os bytes do wrapper que vão nascer em `~/.mytokens/statusline.sh`.
        let wrapperBody: String
        /// O statusLine que o usuário tem hoje, e que o wrapper vai continuar chamando.
        let originalCommand: String
        /// Não-nil quando o usuário NÃO tinha statusLine e nós inserimos o bloco inteiro.
        let insertedBlock: String?
        /// `true` quando o settings.json já aponta pro wrapper (é conserto, não instalação).
        var isRepair: Bool { before == after }
    }

    enum Erro: LocalizedError {
        case semSettings
        case jsonIlegivel
        case ocorrencias(Int)
        case naoSeiFazer(String)
        case wrapperFalhou(String)

        var errorDescription: String? {
            switch self {
            case .semSettings:
                "Não encontrei ~/.claude/settings.json. Rode o Claude Code uma vez primeiro."
            case .jsonIlegivel:
                "O ~/.claude/settings.json não é um JSON que eu saiba ler. Não encosto num "
                    + "arquivo que não entendo — o risco de destruir a configuração é real."
            case .ocorrencias(let n):
                "Eu esperava achar o comando atual UMA vez no texto do settings.json, e achei "
                    + "\(n). Não vou adivinhar qual trocar. Edite à mão ou use "
                    + "./scripts/statusline-install.sh."
            case .naoSeiFazer(let m):
                m
            case .wrapperFalhou(let m):
                "O wrapper falhou no teste, então NADA foi alterado no seu settings.json.\n\n\(m)"
            }
        }
    }

    static func plan() throws -> Plan {
        guard let raw = try? String(contentsOfFile: settingsPath, encoding: .utf8) else {
            throw Erro.semSettings
        }
        guard let root = parse(raw) else { throw Erro.jsonIlegivel }

        let statusLine = root["statusLine"] as? [String: Any]
        let atual = (statusLine?["command"] as? String) ?? ""

        // Reinstalação: o settings já aponta pra nós, então o comando "atual" é o NOSSO
        // wrapper. Embutir isso dentro do próprio wrapper faria uma recursão infinita — e o
        // Claude Code chamando o wrapper que chama o wrapper é um fork bomb na statusline.
        let original = (atual == wrapperPath) ? originalCommand() : atual

        let wrapperBody = wrapperSource(calling: original)
        var after = raw
        var inserted: String?

        if atual == wrapperPath {
            // Conserto: o settings.json já está certo. Só o wrapper precisa nascer de novo.
            after = raw
        } else if !atual.isEmpty {
            // A troca CIRÚRGICA: só o literal do comando muda, no texto cru. Indentação,
            // ordem das chaves e todo campo que eu não conheço ficam byte a byte iguais.
            // Reserializar o JSON seria jogar fora o que eu não entendo — e o que eu não
            // entendo é justamente o que não é meu.
            let alvo = jsonLiteral(atual)
            let novo = jsonLiteral(wrapperPath)
            let n = ocorrencias(of: alvo, in: raw)
            guard n == 1 else { throw Erro.ocorrencias(n) }
            after = raw.replacingOccurrences(of: alvo, with: novo)
        } else if statusLine == nil {
            // Ele não tem statusLine nenhum. Aqui a gente INSERE — e guarda os bytes exatos
            // que entraram, pra saber tirar exatamente eles depois.
            let (novoRaw, bloco) = try insertBlock(into: raw, isEmptyObject: root.isEmpty)
            after = novoRaw
            inserted = bloco
        } else {
            // Tem um bloco `statusLine` sem `command`. Config já estranha, e eu não sei
            // consertar sem chutar. Prefiro dizer isso a mexer.
            throw Erro.naoSeiFazer("""
                Você tem um bloco `statusLine` no settings.json, mas sem a chave `command`. \
                Eu não sei mexer nisso sem adivinhar, e adivinhar na configuração dos outros \
                não é coisa que eu faça. Ajuste à mão e tente de novo.
                """)
        }

        // Nunca, em hipótese nenhuma, escrevo um JSON quebrado na casa de alguém.
        guard parse(after) != nil else {
            throw Erro.naoSeiFazer("O resultado da minha própria mudança não é JSON válido. "
                + "Isso é um bug MEU — e por isso não escrevi nada.")
        }

        return Plan(
            before: raw,
            after: after,
            diff: unifiedDiff(before: raw, after: after, label: tilde(settingsPath)),
            wrapperBody: wrapperBody,
            originalCommand: original,
            insertedBlock: inserted
        )
    }

    // MARK: - Escrever (e só aqui)

    /// Escreve. Retorna o caminho do backup do settings.json de ANTES.
    ///
    /// A ordem importa e é esta de propósito:
    ///   1. o wrapper nasce;
    ///   2. o wrapper é TESTADO com um payload falso;
    ///   3. só então o settings.json muda.
    /// Trocar a config e SÓ ENTÃO descobrir que o wrapper está quebrado é deixar o usuário
    /// sem statusline. O teste é a diferença entre uma instalação e uma aposta.
    @discardableResult
    static func install(_ plan: Plan) throws -> String {
        let fm = FileManager.default
        for dir in [myDir, backupsDir, (snapshotPath as NSString).deletingLastPathComponent] {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // 1. o wrapper
        try atomicWrite(plan.wrapperBody, to: wrapperPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath)

        // 2. a memória do que era dele. Sem isto, desinstalar vira chute.
        try atomicWrite(plan.originalCommand, to: originalCommandPath)
        if let bloco = plan.insertedBlock {
            try atomicWrite(bloco, to: insertedBlockPath)
        } else {
            try? fm.removeItem(atPath: insertedBlockPath)   // marcador velho mente; some
        }

        // 3. o teste do wrapper, com o despejo indo pra um arquivo DESCARTÁVEL. O payload é
        //    INVENTADO: se ele caísse no arquivo de verdade, o app leria 42,5% e diria
        //    "medido" sobre um número que EU criei. Seria a mentira exata que este app
        //    existe pra não contar.
        try smokeTest()

        // 4. backup, e só então o settings.json
        let backup = "\(backupsDir)/settings-\(stamp()).json"
        if !plan.isRepair {
            try fm.copyItem(atPath: settingsPath, toPath: backup)
            try atomicWrite(plan.after, to: settingsPath)
        }
        return plan.isRepair ? "(nada a copiar — o settings.json não mudou)" : backup
    }

    /// Devolve o settings.json ao que era. Byte a byte — não "quase".
    /// Retorna o caminho do backup feito ANTES de desfazer (sim: desfazer também é mexer).
    @discardableResult
    static func uninstall() throws -> String {
        guard let raw = try? String(contentsOfFile: settingsPath, encoding: .utf8) else {
            throw Erro.semSettings
        }
        guard let root = parse(raw) else { throw Erro.jsonIlegivel }
        let atual = command(in: root) ?? ""

        let fm = FileManager.default
        let backup = "\(backupsDir)/settings-\(stamp())-pre-uninstall.json"

        guard atual == wrapperPath else {
            // Nada nosso no caminho. Só limpa o que é nosso e sai — mexer no settings.json
            // aqui seria escrever sem motivo, que é exatamente o que a gente não faz.
            try? fm.removeItem(atPath: wrapperPath)
            try? fm.removeItem(atPath: insertedBlockPath)
            return "(o statusLine não apontava pro MyTokens — o settings.json não foi tocado)"
        }

        let original = originalCommand()
        let inserted = try? String(contentsOfFile: insertedBlockPath, encoding: .utf8)
        let novo: String

        if original.isEmpty {
            // Ele não tinha statusLine. A gente inseriu um bloco; agora tira EXATAMENTE os
            // bytes que entraram. É por isso que eles foram guardados.
            guard let bloco = inserted, ocorrencias(of: bloco, in: raw) == 1 else {
                throw Erro.naoSeiFazer("""
                    Você não tinha statusLine antes do MyTokens, e eu não consigo mais achar, \
                    no seu settings.json, o bloco exato que eu inseri (você editou o arquivo \
                    desde então?). Não vou remover "mais ou menos" — restaure à mão de \
                    \(tilde(backupsDir))/, os backups estão todos lá.
                    """)
            }
            novo = raw.replacingOccurrences(of: bloco, with: "")
        } else {
            let alvo = jsonLiteral(atual)
            let volta = jsonLiteral(original)
            let n = ocorrencias(of: alvo, in: raw)
            guard n == 1 else { throw Erro.ocorrencias(n) }
            novo = raw.replacingOccurrences(of: alvo, with: volta)
        }

        guard parse(novo) != nil else {
            throw Erro.naoSeiFazer("A minha própria reversão produziu um JSON inválido. "
                + "Bug MEU — e por isso não escrevi nada. Restaure de \(tilde(backupsDir))/.")
        }

        try fm.createDirectory(atPath: backupsDir, withIntermediateDirectories: true)
        try fm.copyItem(atPath: settingsPath, toPath: backup)
        try atomicWrite(novo, to: settingsPath)

        // O wrapper sai. O DESPEJO fica: é dado do usuário, não lixo nosso.
        try? fm.removeItem(atPath: wrapperPath)
        try? fm.removeItem(atPath: insertedBlockPath)
        return backup
    }

    // MARK: - O wrapper

    /// Os bytes exatos do wrapper. O `scripts/statusline-install.sh` gera ESTES MESMOS bytes —
    /// os dois caminhos (app e terminal) instalam o mesmo arquivo, e um `diff` prova isso.
    ///
    /// Cinco linhas de `sh`, e nenhuma delas é o MyTokens. A objeção honesta contra este
    /// caminho (docs/STATUSLINE.md, opção A) era "viramos ponto único de falha da statusline
    /// dele". A resposta não foi aceitar o risco — foi TIRAR O BINÁRIO DO CAMINHO.
    static func wrapperSource(calling original: String) -> String {
        """
        #!/bin/sh
        # GERADO PELO MyTokens. Não edite à mão — reinstalar sobrescreve.
        #
        # O Claude Code entrega o JSON da statusline no stdin. Dentro dele vem `rate_limits`,
        # que é o ÚNICO lugar do mundo onde existe o "quanto resta" do Claude — ele não é
        # gravado em disco nenhum. Este script guarda esse JSON e passa a bola adiante, intacta.
        #
        # Ele NÃO chama o MyTokens.app. Apague o app, mova o app, jogue o Mac pela janela: a
        # sua statusline continua desenhando exatamente como antes.

        # MYTOKENS_SNAP existe pro INSTALADOR poder testar este script sem contaminar o arquivo
        # de verdade. Um teste que grava um número inventado no lugar onde o app lê a verdade
        # não é um teste — é o bug que ele deveria pegar.
        SNAP="${MYTOKENS_SNAP:-$HOME/Library/Application Support/MyTokens/statusline.json}"
        input=$(cat)

        # Despejo. Falha aqui NUNCA derruba a statusline: se der errado, segue o baile.
        {
          mkdir -p "$(dirname "$SNAP")" && \\
          printf '%s' "$input" > "$SNAP.tmp" && mv -f "$SNAP.tmp" "$SNAP"
        } 2>/dev/null || true

        # O SEU comando, com o MESMO stdin, stdout e código de saída.
        ORIGINAL=\(shQuoted(original))
        [ -n "$ORIGINAL" ] || exit 0
        printf '%s' "$input" | eval "$ORIGINAL"

        """
    }

    /// Prova que o wrapper presta ANTES de o settings.json mudar. Em dois atos, e o que ele
    /// NÃO faz é a parte importante do desenho:
    ///
    /// O WRAPPER DO USUÁRIO NUNCA É EXECUTADO COM DADO INVENTADO.
    ///
    /// A versão anterior deste teste rodava o wrapper de verdade — que chama o statusLine do
    /// usuário — com um payload sintético (42,5%, sessão "teste"). O despejo do MyTokens estava
    /// protegido (ia pra um temp), mas o que corre RIO ABAIXO não estava: o statusLine de uma
    /// pessoa é um programa qualquer, e programas escrevem. O do Jair, por exemplo, grava um
    /// arquivo-ponte a cada turno (`gsd-statusline.js:342`). Nele o estrago foi nulo por sorte
    /// — o caminho é chaveado pelo session_id, e "teste" não colide com UUID nenhum. Se aquele
    /// script gravasse num caminho FIXO (um cache, um log, um arquivo de estado), instalar o
    /// MyTokens teria enfiado um 42,5% inventado lá dentro.
    ///
    /// Escrever um número que ninguém mediu, num lugar onde outra coisa lê a verdade, é a
    /// mentira exata que este app existe pra não contar. O instalador não vai ser o primeiro
    /// a contá-la.
    ///
    ///   ATO 1 — `sh -n` no wrapper. Não executa NADA; só valida a sintaxe. É o que pega o
    ///           modo de falha real (o comando do usuário com aspa simples no meio, que
    ///           estoura a citação e mata a statusline dele).
    ///   ATO 2 — roda uma CÓPIA do wrapper com o comando de baixo VAZIO, num temp. Prova o
    ///           despejo, o `mkdir -p`, a escrita atômica e o código de saída — todo o cano
    ///           que é NOSSO — sem tocar em uma linha do programa dele.
    ///
    /// O que fica sem prova: que o statusLine dele roda por baixo do wrapper. Isso só um turno
    /// real do Claude Code mostra, e é por isso que o painel diz "ainda não passou turno
    /// nenhum" até o primeiro despejo chegar. Um "não sei ainda" honesto vale mais que um
    /// teste que suja o disco de quem confiou no botão.
    private static func smokeTest() throws {
        // ATO 1 — a sintaxe, sem executar.
        let n = Process()
        n.executableURL = URL(fileURLWithPath: "/bin/sh")
        n.arguments = ["-n", wrapperPath]
        let nErro = Pipe()
        n.standardError = nErro
        n.standardOutput = Pipe()
        try n.run()
        let queixa = String(decoding: (try? nErro.fileHandleForReading.readToEnd()) ?? Data(),
                            as: UTF8.self)
        n.waitUntilExit()
        guard n.terminationStatus == 0 else {
            throw Erro.wrapperFalhou("""
                O wrapper não é um script de shell válido — provavelmente o SEU comando de \
                statusLine tem uma citação que eu não soube embutir:

                \(queixa.trimmingCharacters(in: .whitespacesAndNewlines))

                Nada foi alterado. Reporte isto: é bug meu, não seu.
                """)
        }

        // ATO 2 — o nosso cano, sozinho. Cópia do wrapper SEM o comando de baixo.
        let dir = NSTemporaryDirectory()
        let copia = dir + "mytokens-smoke-\(UUID().uuidString).sh"
        let alvo = dir + "mytokens-smoke-\(UUID().uuidString).json"
        defer {
            try? FileManager.default.removeItem(atPath: copia)
            try? FileManager.default.removeItem(atPath: alvo)
        }
        try atomicWrite(wrapperSource(calling: ""), to: copia)

        let prova = #"{"hook_event_name":"Status","session_id":"smoke","rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":9999999999}}}"#

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [copia]
        p.environment = ProcessInfo.processInfo.environment.merging(
            ["MYTOKENS_SNAP": alvo], uniquingKeysWith: { _, novo in novo })

        let entrada = Pipe(), saida = Pipe(), erro = Pipe()
        p.standardInput = entrada
        p.standardOutput = saida
        p.standardError = erro

        try p.run()
        entrada.fileHandleForWriting.write(Data(prova.utf8))
        try? entrada.fileHandleForWriting.close()
        // Drenar ANTES do wait: senão o filho trava escrevendo num pipe cheio e a gente trava
        // esperando o filho. Deadlock de manual.
        _ = try? saida.fileHandleForReading.readToEnd()
        _ = try? erro.fileHandleForReading.readToEnd()
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            throw Erro.wrapperFalhou("Ele saiu com código \(p.terminationStatus).")
        }
        guard let d = FileManager.default.contents(atPath: alvo),
              String(decoding: d, as: UTF8.self).contains("rate_limits")
        else {
            throw Erro.wrapperFalhou("Ele rodou, mas não gravou o despejo.")
        }
    }

    // MARK: - Texto: ler sem reserializar, escrever sem truncar

    private static func parse(_ raw: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    }

    private static func command(in root: [String: Any]) -> String? {
        (root["statusLine"] as? [String: Any])?["command"] as? String
    }

    static func originalCommand() -> String {
        if let s = try? String(contentsOfFile: originalCommandPath, encoding: .utf8) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // O bilhete sumiu, mas o wrapper CARREGA o comando dentro dele. Ler de lá é a
        // diferença entre uma desinstalação e um "não sei mais o que era seu".
        guard let w = try? String(contentsOfFile: wrapperPath, encoding: .utf8) else { return "" }
        for linha in w.split(separator: "\n", omittingEmptySubsequences: false)
        where linha.hasPrefix("ORIGINAL='") && linha.hasSuffix("'") {
            let corpo = linha.dropFirst("ORIGINAL='".count).dropLast()
            return corpo.replacingOccurrences(of: #"'\''"#, with: "'")
        }
        return ""
    }

    /// O literal JSON de uma string, do jeito que ele aparece NO ARQUIVO: UTF-8 cru, sem
    /// escapar `/`, escapando só o que o JSON obriga. Se o arquivo do usuário usasse `\uXXXX`
    /// para acentos, este literal não casaria — e a busca acharia 0 ocorrências, e a gente
    /// recusaria a mexer. Falhar fechado é o comportamento certo aqui.
    private static func jsonLiteral(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }

    /// `'...'` pro `sh`, com o truque do `'\''` pra aspa simples de dentro. Sem isto, um
    /// statusLine com uma aspa simples no meio (um `awk '{...}'`, por exemplo) explodiria o
    /// wrapper — e a statusline do usuário sumiria por causa da NOSSA citação preguiçosa.
    private static func shQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private static func ocorrencias(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }

    /// Insere o bloco `statusLine` inteiro, logo depois da chave que abre o objeto. Textual,
    /// não reserializado: as outras chaves — inclusive as que eu não conheço — não são tocadas.
    private static func insertBlock(into raw: String, isEmptyObject: Bool) throws
        -> (String, String) {
        guard let abre = raw.firstIndex(of: "{") else { throw Erro.jsonIlegivel }
        // Objeto vazio (`{}`) não leva vírgula: ela sobraria e o JSON quebraria.
        let virgula = isEmptyObject ? "" : ","
        // Dois espaços de indentação — é o que o settings.json do Claude Code usa.
        let bloco = """

          "statusLine": {
            "type": "command",
            "command": \(jsonLiteral(wrapperPath))
          }\(virgula)
        """

        var novo = raw
        novo.insert(contentsOf: bloco, at: novo.index(after: abre))
        return (novo, bloco)
    }

    /// Escrita atômica: temp + rename, no MESMO diretório. Nunca `truncate`. Se a máquina cair
    /// no meio, o usuário fica com o arquivo velho inteiro — não com meio arquivo.
    private static func atomicWrite(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    static func tilde(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Dos caminhos ABSOLUTOS que aparecem num comando de shell, o primeiro que não existe.
    /// É como o app descobre que o statusLine anterior do usuário apontava pra um arquivo que
    /// o mundo apagou embaixo dele.
    private static func missingFile(in command: String) -> String? {
        guard !command.isEmpty else { return nil }
        let fm = FileManager.default
        for token in shellTokens(command) where token.hasPrefix("/") {
            if !fm.fileExists(atPath: token) { return token }
        }
        return nil
    }

    /// Tokenizador de pobre: só o suficiente pra separar `"a b" 'c' d` em três pedaços.
    /// Não é um shell — é uma lupa.
    private static func shellTokens(_ s: String) -> [String] {
        var out: [String] = []
        var atual = ""
        var aspas: Character?
        for c in s {
            if let a = aspas {
                if c == a { aspas = nil } else { atual.append(c) }
            } else if c == "\"" || c == "'" {
                aspas = c
            } else if c == " " || c == "\t" {
                if !atual.isEmpty { out.append(atual); atual = "" }
            } else {
                atual.append(c)
            }
        }
        if !atual.isEmpty { out.append(atual) }
        return out
    }

    // MARK: - O diff

    /// O antes e o depois, LITERAIS, só nas linhas que mudam. É o que o painel mostra antes de
    /// pedir o clique — porque "autorizo você a escrever em ~/.claude" só é consentimento se
    /// o usuário viu O QUE vai ser escrito. O resto é consentimento presumido, que é outra
    /// coisa e tem outro nome.
    ///
    /// A nossa edição é sempre UMA substituição contígua, então prefixo comum + sufixo comum
    /// isolam exatamente o miolo que muda. Não precisa de Myers pra isso.
    static func unifiedDiff(before: String, after: String, label: String, context: Int = 3)
        -> String {
        guard before != after else {
            return "(o \(label) não muda — ele já aponta pro wrapper)"
        }
        let a = before.components(separatedBy: "\n")
        let b = after.components(separatedBy: "\n")

        var pre = 0
        while pre < a.count, pre < b.count, a[pre] == b[pre] { pre += 1 }
        var suf = 0
        while suf < a.count - pre, suf < b.count - pre, a[a.count - 1 - suf] == b[b.count - 1 - suf] {
            suf += 1
        }

        var linhas: [String] = ["--- \(label)   (agora)", "+++ \(label)   (depois)"]
        let ctxIni = max(0, pre - context)
        if ctxIni > 0 { linhas.append("  ⋮") }
        for i in ctxIni..<pre { linhas.append("  " + a[i]) }
        for i in pre..<(a.count - suf) { linhas.append("- " + a[i]) }
        for i in pre..<(b.count - suf) { linhas.append("+ " + b[i]) }
        let fim = min(a.count, a.count - suf + context)
        for i in (a.count - suf)..<fim { linhas.append("  " + a[i]) }
        if fim < a.count { linhas.append("  ⋮") }
        return linhas.joined(separator: "\n")
    }
}
