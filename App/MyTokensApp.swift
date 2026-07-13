import AppKit
import SwiftUI
import MyTokensCore
import MyTokensUI

@main
struct MyTokensApp: App {
    // Singleton de propósito: o coordenador vive o app inteiro e precisa ligar no LAUNCH,
    // não no primeiro clique. O conteúdo do MenuBarExtra é LAZY — se o watcher dependesse
    // dele, o app só começaria a enxergar disco depois que o usuário abrisse a janela.
    @State private var model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverScene(model: model)
        } label: {
            // Template image: só o alfa importa, o macOS tinge sozinho.
            // Dark e light saem de graça — e a cor deixa de ser uma tentação de design.
            Image(nsImage: StatusIcon.image(for: model.iconState))
        }
        // .window, não .menu: SwiftUI de verdade lá dentro. É onde o Vitral trabalha.
        .menuBarExtraStyle(.window)

        // A janela expandida. NÃO é uma tela nova — é o mesmo sistema com mais ar
        // (UI-SPEC): a agulha do agora, a régua do eixo, o ritmo e o custo do dia.
        //
        // `Window` (singular), não `WindowGroup`: é UMA janela, e reabrir tem que trazer a
        // que já existe pra frente em vez de empilhar cópias do mesmo painel.
        Window("MyTokens", id: WindowScene.main) {
            MainScene(model: model)
        }
        // O conteúdo tem largura fixa (960) e altura própria. Deixar o usuário arrastar a
        // borda só produziria vão morto — o desenho não escala, ele respira.
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        // Sem barra de título: a MainWindowView é uma BANCADA, desenhada de borda a borda.
        // Uma titlebar padrão do sistema por cima dela cortaria o desenho ao meio pra
        // repetir um nome que o usuário já sabe.
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()   // app de barra de menu não tem menu de aplicação
    }
}

enum WindowScene {
    static let main = "main"
}

// MARK: - O popover

/// O que mora dentro do MenuBarExtra.
///
/// Existe como view (e não inline na cena) porque `openWindow` é do ambiente de VIEW —
/// e é dele que sai o "ABRIR" do rodapé.
private struct PopoverScene: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PopoverView(
            snapshot: model.dashboard,
            onOpenWindow: abrir,
            onConnect: model.connect,
            controls: model.controls
        )
        // O rodapé do popover ANUNCIA `⌘⏎`. Um atalho anunciado e não implementado é uma
        // mentira pequena, e este app não pode se dar ao luxo nem das pequenas.
        // Botão invisível, porque o atalho precisa de um responder — o desenho é do Vitral.
        .background {
            Button("", action: abrir)
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // Abriu o popover → força uma coleta. É o que atualiza o Cursor, que muda por
        // rede e não por disco (o FSEvents nunca acorda por causa dele).
        .task { model.refreshOnOpen() }
    }

    private func abrir() {
        openWindow(id: WindowScene.main)
        // Sem isto a janela nasce ATRÁS de quem estiver na frente: o app é `.accessory`
        // (não tem Dock, não tem Cmd+Tab), então ninguém o ativa por ele.
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - A janela

private struct MainScene: View {
    @Bindable var model: AppModel

    var body: some View {
        MainWindowView(snapshot: model.dashboard, onConnect: model.connect)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cinto e suspensório do LSUIElement: sem Dock, sem Cmd+Tab, sem menu de aplicação.
        // O app MORA na barra de menu.
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }

    /// Fechar a janela NÃO é sair. O app continua na barra, que é onde ele mora.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}
