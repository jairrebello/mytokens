import AppKit
import Foundation
import UserNotifications
import MyTokensCore
import MyTokensUI

/// Os DOIS avisos do UI-SPEC §7 — e nenhum a mais.
///
/// O app é olhado 30x por dia e não pede atenção: notificação aqui é a exceção, não o
/// hábito. Só duas coisas justificam interromper alguém que não estava olhando:
///
///   CRUZOU 85%  — "Aperta o passo." Informa, não apavora. O UI-SPEC é explícito: a tela
///                 não fica vermelha porque a barra é FATO MEDIDO e fato não muda de cor
///                 porque o futuro é feio. A notificação segue a mesma regra: ela diz o
///                 que é, e diz quanto tempo você tem. Não grita.
///   RESETOU     — o alívio. "Nada pisca, nada quica, nada faz confete": chega em
///                 `.passive`, sem som. Isto não é conquista, é o dia recomeçando.
///
/// SEM TIMER. Este arquivo não tem um. O cruzamento de 85% é descoberto comparando o
/// snapshot novo com o anterior, quando o FSEvents acorda o AppModel — que é o único
/// relógio que este app tem, e é o disco que dá corda nele.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    /// A linha. Fixa: um limiar configurável seria um botão a mais pra ninguém mexer.
    private static let threshold: Double = 85

    /// O macOS BARROU os avisos. O menu lê isto pra parar de fingir que o toggle vale
    /// alguma coisa — um ✓ que não avisa nada é pior que aviso nenhum.
    private(set) var isBlocked = false

    private let center = UNUserNotificationCenter.current()
    private let ledger = Ledger()

    override init() {
        super.init()
        // Só o delegate. NÃO pede permissão aqui: um app que pede autorização no launch
        // pede antes de ter feito qualquer coisa por você. Pedimos quando houver algo
        // real a dizer — ver `ensureAuthorized()`.
        center.delegate = self
    }

    /// Sem isto o macOS ENGOLE a notificação quando o app está ativo — e o app fica ativo
    /// exatamente no pior momento: abrir o popover dispara um refresh, e é nesse refresh
    /// que o cruzamento de 85% costuma ser descoberto.
    ///
    /// `nonisolated` porque o UserNotifications chama isto de fora da MainActor e nem
    /// `UNNotification` nem o `center` são Sendable. E não precisa ser: a resposta é uma
    /// constante — não lê um byte do estado deste objeto.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // MARK: - O gatilho

    /// Chamado a cada dashboard novo. Compara com o anterior e decide se há o que dizer.
    ///
    /// `enabled == false` é literal: o app não toca no UNUserNotificationCenter, não
    /// consulta status, não pede nada. Aviso desligado é aviso INEXISTENTE.
    func evaluate(previous: Dashboard, current: Dashboard, enabled: Bool, now: Date = Date()) async {
        guard enabled else { return }

        ledger.prune(now: now)
        await refreshBlocked()

        var pending: [Note] = []

        for lane in current.lanes {
            // TINTA OU NADA. Sem tinta o app não afirma um número na tela; muito menos vai
            // afirmar um alarme. Ausência de dado é ausência — nunca um zero, nunca um susto.
            guard lane.certainty.hasInk, let used = lane.used, let resetsAt = lane.resetsAt
            else { continue }

            // 1) A JANELA VIROU?
            //
            // Não dá pra ver isso comparando com o snapshot anterior: no instante do reset
            // a janela VENCIDA some do contrato (o core derruba janela morta), e a pista
            // pode passar um tempo ausente até o provedor publicar a nova. O que sobrevive
            // a esse vão é o livro: se eu avisei sobre uma janela cujo `resetsAt` já passou,
            // e agora essa mesma pista aparece com um `resetsAt` NOVO e com MENOS tinta,
            // então ela zerou — e isso é medida, não relógio de parede.
            if let old = ledger.expiredEntry(laneID: lane.id, before: resetsAt, now: now),
               used < old.usedPercent {
                pending.append(.reset(lane: lane, peak: old.usedPercent, forget: old.key))
            }

            // 2) CRUZOU A LINHA?
            //
            // Transição, não estado: exige um snapshot anterior ABAIXO de 85, na MESMA
            // instância de janela. Um app que grita no boot porque encontrou 90% no disco
            // está gritando sobre o passado — e sobre um passado que o usuário já viveu.
            let key = Ledger.key(laneID: lane.id, resetsAt: resetsAt)
            guard used >= Self.threshold, !ledger.contains(key) else { continue }
            guard let before = previous.lanes.first(where: { $0.id == lane.id }),
                  before.certainty.hasInk,
                  before.resetsAt == resetsAt,
                  let beforeUsed = before.used,
                  beforeUsed < Self.threshold
            else { continue }

            pending.append(.crossed(lane: lane, used: used, key: key))
        }

        guard !pending.isEmpty else { return }
        // A permissão é pedida AQUI, na primeira vez que existe um aviso de verdade pra dar.
        guard await ensureAuthorized() else { return }

        for note in pending {
            await post(note, now: now)
            // O livro só é escrito DEPOIS que o aviso saiu. Marcar antes seria dar por
            // avisado um usuário que não foi avisado de nada.
            switch note {
            case .crossed(_, let used, let key):     ledger.remember(key, usedPercent: used)
            case .reset(_, _, let forget):           ledger.forget(forget)
            }
        }
    }

    private enum Note {
        case crossed(lane: Lane, used: Double, key: String)
        case reset(lane: Lane, peak: Double, forget: String)
    }

    // MARK: - O que é dito

    private func post(_ note: Note, now: Date) async {
        let content = UNMutableNotificationContent()
        let id: String

        switch note {
        case .crossed(let lane, let used, let key):
            id = key
            // O til do reticulado sobrevive à travessia pra cá: se o número é estimado na
            // tela, ele é estimado na notificação. A honestidade não pode parar na janela.
            let mark = lane.certainty.isApproximate ? "~" : ""
            content.title = "\(lane.title) em \(mark)\(Int(used.rounded()))%"

            var corpo = "Aperta o passo — dá pra fechar o que está aberto, não pra abrir frente nova."
            if let falta = Self.remaining(until: lane.resetsAt, now: now) {
                corpo += " Zera em \(falta)."
            }
            content.body = corpo
            content.sound = .default   // é o aviso ACIONÁVEL: o único que merece um som.

        case .reset(let lane, let peak, _):
            id = "reset-\(lane.id)-\(Int(peak.rounded()))"
            content.title = "\(lane.title) zerou"
            content.body = "Cota inteira de novo. Você tinha chegado a \(Int(peak.rounded()))%."
            // Sem som e `.passive`: alívio não interrompe ninguém. Isto não é uma conquista,
            // é o dia recomeçando — e o dia recomeçando não toca sino.
            content.sound = nil
            content.interruptionLevel = .passive
        }

        // `trigger: nil` = agora. Agendar seria inventar um relógio, e o app não tem um.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// "1 h 20 min" · "45 min" · "3 dias". O tempo é a unidade do humano (UI-SPEC §3):
    /// "zera em 1 h 20 min" responde a pergunta que "resets_at: 1768312800" não responde.
    private static func remaining(until date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let s = Int(date.timeIntervalSince(now))
        guard s > 0 else { return nil }
        let min = s / 60, h = min / 60, d = h / 24
        if d >= 1 { return d == 1 ? "1 dia" : "\(d) dias" }
        if h >= 1 {
            let m = min % 60
            return m == 0 ? "\(h) h" : "\(h) h \(m) min"
        }
        return "\(max(min, 1)) min"
    }

    // MARK: - A permissão

    /// Pede na PRIMEIRA vez que há algo a notificar — nunca no launch.
    ///
    /// Um app que abre pedindo autorização está pedindo crédito antes de ter feito nada
    /// por você. Este pede depois de já ter algo a dizer, e o que ele tem a dizer é a
    /// justificativa do pedido.
    private func ensureAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            isBlocked = !ok
            return ok
        case .denied:
            isBlocked = true
            return false
        default:
            isBlocked = false
            return true
        }
    }

    /// Lê o status SEM pedir nada (`notificationSettings()` nunca abre diálogo). É o que
    /// mantém o menu honesto quando o usuário revoga a permissão em Ajustes depois de dar.
    func refreshBlocked() async {
        isBlocked = await center.notificationSettings().authorizationStatus == .denied
    }

    /// "diz o que quebrou e como consertar", inline — a mesma regra dos erros do UI-SPEC.
    /// Um menu que só constata o bloqueio deixa o usuário caçando o painel sozinho.
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - O livro do "já avisei"

/// Chaveado por PROVEDOR + JANELA + `resetsAt`, e persistido.
///
/// Sem persistir, o app avisa de novo a cada relaunch — e um aviso repetido é um aviso
/// que ninguém lê. E `resetsAt` na chave não é enfeite: é ele que faz a chave morrer junto
/// com a janela. A janela seguinte tem outro `resetsAt`, logo outra chave, logo ela pode
/// (e deve) avisar de novo.
///
/// O valor guardado é a TINTA no momento do aviso. Ela paga por duas coisas: prova que a
/// janela seguinte "caiu" (reset é medida, não palpite) e dá o pico que o aviso de alívio
/// devolve pro usuário.
private struct Ledger {
    static let key = "mytokens.notify.warned"

    struct Entry {
        let key: String
        let resetsAt: Date
        let usedPercent: Double
    }

    static func key(laneID: String, resetsAt: Date) -> String {
        "\(laneID)@\(Int(resetsAt.timeIntervalSince1970))"
    }

    private var raw: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Double] ?? [:] }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.key) }
    }

    func contains(_ k: String) -> Bool { raw[k] != nil }

    func remember(_ k: String, usedPercent: Double) {
        var d = raw
        d[k] = usedPercent
        raw = d
    }

    func forget(_ k: String) {
        var d = raw
        d.removeValue(forKey: k)
        raw = d
    }

    /// A janela ANTERIOR desta pista, já vencida, sobre a qual eu avisei.
    func expiredEntry(laneID: String, before: Date, now: Date) -> Entry? {
        raw.compactMap { Self.parse($0.key, usedPercent: $0.value) }
            .filter { $0.key.hasPrefix("\(laneID)@") && $0.resetsAt <= now && $0.resetsAt < before }
            .max { $0.resetsAt < $1.resetsAt }
    }

    /// Chave de janela vencida há mais de um dia é lixo: ou o alívio já foi dado, ou o
    /// app estava fechado na virada e ninguém mais vai reclamar dela. Varrer aqui é o que
    /// impede o UserDefaults de virar um cemitério que cresce pra sempre.
    func prune(now: Date) {
        let limite = now.addingTimeInterval(-24 * 60 * 60)
        let vivas = raw.filter { k, _ in
            guard let e = Self.parse(k, usedPercent: 0) else { return false }  // chave ilegível: fora
            return e.resetsAt > limite
        }
        if vivas.count != raw.count { raw = vivas }
    }

    private static func parse(_ k: String, usedPercent: Double) -> Entry? {
        guard let at = k.split(separator: "@").last, let epoch = TimeInterval(at) else { return nil }
        return Entry(key: k, resetsAt: Date(timeIntervalSince1970: epoch), usedPercent: usedPercent)
    }
}

// MARK: - O toggle

/// "Avisar em 85%". Persistido, no mesmo formato de `ThemeStore`/`MenuBarStyleStore`.
struct NotifyStore {
    static let key = "mytokens.notifyAt85"

    static var current: Bool {
        get {
            // `UserDefaults.bool` devolve `false` pra chave que nunca existiu — e isso
            // entregaria o app com o aviso DESLIGADO, que é o oposto do default. Ausência
            // de dado é ausência, e aqui a ausência significa "o usuário nunca escolheu".
            UserDefaults.standard.object(forKey: key) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
