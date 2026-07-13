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
            // A view do Vitral, com o dado do Chassi. `onConnect` ainda não faz nada:
            // conectar o Claude significa ESCREVER em ~/.claude/settings.json (o hook do
            // statusLine), e isso exige consentimento explícito do usuário — é o próximo
            // bloco, com sheet de autorização e backup. Ver docs/STATUSLINE.md.
            PopoverView(snapshot: model.dashboard)
        } label: {
            // Template image: só o alfa importa, o macOS tinge sozinho.
            // Dark e light saem de graça — e a cor deixa de ser uma tentação de design.
            Image(nsImage: StatusIcon.image(for: model.iconState))
        }
        // .window, não .menu: SwiftUI de verdade lá dentro. É onde o Vitral trabalha.
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cinto e suspensório do LSUIElement: sem Dock, sem Cmd+Tab, sem menu de aplicação.
        // O app MORA na barra de menu.
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
}
