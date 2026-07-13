//  Gallery.swift
//
//  Bancada de prova. Roda os estados lado a lado, em dark e light, numa janela
//  de verdade — porque `ImageRenderer` NÃO rasteriza material nativo, e material
//  nativo é metade da promessa do popover. Screenshot de material fake provaria
//  a coisa errada.
//
//  Uso:
//    swift run MyTokensGallery <estado> <dark|light>
//    swift run MyTokensGallery reset dark      # dispara a animação do dreno

import MyTokensCore
import SwiftUI
import AppKit
import MyTokensUI

// O bootstrap está em main.swift: o ciclo de vida `App` do SwiftUI com uma cena
// `Settings` vazia nunca completa o launch, e o delegate não dispara. NSApplication
// direto é o caminho curto — e aqui é uma bancada de prova, não o app de verdade
// (esse é território do Chassi).

// MARK: - Estados

enum Shot: String, CaseIterable {
    case popover          // o dia comum: barra composta, Cursor ausente
    case empty            // primeiro boot
    case almost           // 85%: a projeção rompe o trilho
    case noHook           // Claude 100% derivado
    case reset            // a janela virou — o dreno
    case overrun          // estourou
    case window           // a janela expandida
    case windowAlmost     // a janela expandida, apertando
    case lanes            // as quatro texturas, isoladas, lado a lado
    case real             // o DISCO DESTA MÁQUINA. Sem mock. É o teste que não mente.
    case realWindow       // idem, na janela expandida

    /// O mock é desenho; `real` é o app. A galeria roda os dois na MESMA view — se a
    /// pista só ficar bonita com dado inventado, o problema é a pista.
    var snapshot: Dashboard {
        switch self {
        case .popover, .window: Mock.normal
        case .empty: Mock.empty
        case .almost, .windowAlmost: Mock.almostThere
        case .noHook: Mock.noHook
        case .reset: Mock.justReset
        case .overrun: Mock.overrun
        case .lanes: Mock.normal
        case .real, .realWindow: Dashboard(lanes: [])   // substituído no launch pela leitura de verdade
        }
    }

    var isWindow: Bool {
        self == .window || self == .windowAlmost || self == .realWindow
    }

    var size: CGSize {
        switch self {
        case .lanes: CGSize(width: 700, height: 420)
        case .window, .windowAlmost, .realWindow: CGSize(width: 960, height: 560)
        default: CGSize(width: 380, height: 560)   // popover + folga pro desktop
        }
    }
}

// MARK: - Janela

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ n: Notification) {
        note("DELEGATE FIRED")
        let args = CommandLine.arguments
        let shot = Shot(rawValue: args.count > 1 ? args[1] : "popover") ?? .popover
        let dark = !(args.count > 2 && args[2] == "light")

        let root = GalleryRoot(shot: shot)
            .preferredColorScheme(dark ? .dark : .light)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: shot.size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: root)
        window.level = .floating
        // Origem fixa: o script de screenshot recorta exatamente esta região.
        window.setFrameOrigin(NSPoint(x: 80, y: 200))
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // O `screencapture -l<id>` recorta exatamente esta janela — sem depender
        // de coordenada de tela nem de quem está na frente.
        note("WINDOW_ID \(window.windowNumber)")
    }
}

// MARK: - Raiz

struct GalleryRoot: View {
    let shot: Shot

    var body: some View {
        switch shot {
        case .lanes:
            LaneShowcase()
        case .window, .windowAlmost:
            MainWindowView(snapshot: shot.snapshot)
        case .reset:
            ResetStage()          // o dreno anima ao abrir
        case .real:
            DesktopBacking { RealStage(window: false) }
        case .realWindow:
            RealStage(window: true)
        default:
            DesktopBacking {
                PopoverView(snapshot: shot.snapshot)
            }
        }
    }
}

/// A mesma PopoverView, alimentada pelo DISCO DESTA MÁQUINA.
///
/// É o único estado da galeria que pode falhar de verdade — e é por isso que ele existe.
/// Mock prova desenho; isto prova o app. Enquanto o motor lê (o primeiro scan varre 1,4 GB),
/// a tela mostra o estado VAZIO, que é a verdade naquele instante: ainda não sabemos.
struct RealStage: View {
    let window: Bool
    @State private var snapshot = Dashboard(lanes: [])

    var body: some View {
        Group {
            if window {
                MainWindowView(snapshot: snapshot)
            } else {
                PopoverView(snapshot: snapshot)
            }
        }
            .task {
                do {
                    let engine = try MyTokensEngine()
                    snapshot = Dashboard(await engine.refresh())
                    // O script de screenshot espera esta linha antes de disparar —
                    // capturar antes seria fotografar o estado vazio e chamar de real.
                    note("REAL_READY \(snapshot.lanes.count) pistas")
                } catch {
                    note("REAL_FAILED \(error)")
                }
            }
    }
}

/// Um pedaço de desktop atrás do popover — sem isso, o material nativo não tem
/// o que atravessar e o screenshot mentiria sobre a translucidez.
struct DesktopBacking<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.24, green: 0.20, blue: 0.30),
                    Color(.sRGB, red: 0.10, green: 0.09, blue: 0.14),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .clipShape(RoundedRectangle(cornerRadius: R.r3, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 12)
                .padding(.top, 18)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - O RESET, animado
//
// A sequência inteira do UI-SPEC §8, em 1.500 ms. Encher é rotina; esvaziar é
// acontecimento — então o dreno (900 ms) é MAIS LENTO que o avanço (420 ms).
// As outras pistas NÃO se mexem: as janelas são independentes, e animar tudo
// junto ensinaria errado a mecânica dos limites.

struct ResetStage: View {
    @State private var drained = false

    private var before: Dashboard { Mock.almostThere }
    private var after: Dashboard { Mock.justReset }

    var body: some View {
        DesktopBacking {
            PopoverView(snapshot: drained ? after : before)
                .animation(Motion.drain, value: drained)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            drained = true
        }
    }
}

// MARK: - As quatro texturas, isoladas
//
// A prova do sistema. Se estas quatro não forem distinguíveis de raspão,
// o app mente — e nada mais na tela importa.

struct LaneShowcase: View {
    @Environment(\.palette) private var p

    private let cases: [(String, String, Lane)] = [
        ("MEDIDO", "o provedor nos deu o número. sólido, corte reto, sem selo.",
         Lane(id: "m", provider: .claudeCode, title: "Claude · 7 d", used: 38,
              certainty: .measured(at: Date()), nowFraction: 0.46,
              resetsAt: Date().addingTimeInterval(86400 * 2))),

        ("COMPOSTA", "medido até a costura; o disco inferiu o resto.",
         Lane(id: "c", provider: .claudeCode, title: "Claude · 5 h", used: 50,
              certainty: .composite(measuredUpTo: 32, at: Date()), nowFraction: 0.59,
              resetsAt: Date().addingTimeInterval(3600), isLive: true)),

        ("DERIVADO", "nós calculamos. reticulado, faixa piso–teto, til no número.",
         Lane(id: "d", provider: .claudeCode, title: "Claude · 5 h", used: 54,
              certainty: .derived(lo: 41, hi: 68), nowFraction: 0.59,
              resetsAt: Date().addingTimeInterval(3600))),

        ("AUSENTE", "não sabemos. a pista existe, vazia. o relógio continua.",
         Lane.absent(provider: .cursor, label: "mês", nowFraction: 0.41,
                     capUSD: 20, unit: .usd)),

        ("ESTOURO", "a projeção rompe o trilho. o alarme é geometria, não cor.",
         Lane(id: "o", provider: .claudeCode, title: "Claude · 5 h", used: 85,
              certainty: .measured(at: Date()), nowFraction: 0.61,
              resetsAt: Date().addingTimeInterval(3600),
              burnRatePerHour: 26, isLive: true)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: S.s5) {
            ForEach(cases, id: \.0) { name, why, lane in
                HStack(alignment: .center, spacing: S.s5) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.ui(T.micro, .semibold))
                            .tracking(0.09 * T.micro)
                            .foregroundStyle(p.ink2)
                        Text(why)
                            .font(.ui(T.xs))
                            .foregroundStyle(p.ink4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 230, alignment: .leading)

                    LaneView(lane: lane, height: 14, showNeedle: true)
                        .frame(maxWidth: .infinity)

                    ValueText(lane: lane, size: T.xl)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            Divider().overlay(p.lineSoft)
            ProvenanceLegend()
        }
        .padding(S.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(p.canvas)
        .bancada()
    }
}
