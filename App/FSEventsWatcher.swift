import CoreServices
import Foundation

/// Watcher de disco ORIENTADO A EVENTO. Nunca polling.
///
/// É o kernel que nos acorda, não um timer. É isso que segura a CPU ociosa em ~0%:
/// parado, o app não executa uma instrução sequer — não existe loop, não existe timer,
/// não existe "checa a cada N segundos". O FSEvents dorme no kernel e cutuca a gente.
///
/// `latency` faz a coalescência acontecer DENTRO do kernel: uma sessão do Claude Code
/// escrevendo JSONL gera dezenas de writes por segundo, e nós acordamos uma vez.
final class FSEventsWatcher {

    /// Lotes de caminhos mudados. Consumir com `for await`.
    let changes: AsyncStream<[String]>

    private let continuation: AsyncStream<[String]>.Continuation
    private var stream: FSEventStreamRef?
    private var boxPointer: UnsafeMutableRawPointer?
    private let queue = DispatchQueue(label: "com.jairrebello.mytokens.fsevents", qos: .utility)

    /// Caminhos que o watcher REALMENTE armou (pode diferir do pedido: se
    /// ~/.codex/sessions ainda não existe, armamos o pai e filtramos).
    private(set) var armedPaths: [String] = []

    /// - Parameters:
    ///   - paths: diretórios de interesse. Se um não existir, arma o PAI dele —
    ///            assim o app enxerga a criação do diretório sem precisar de polling.
    ///   - latency: janela de coalescência do kernel. 1s é folgado de propósito:
    ///             o custo de acordar tarde é 1 segundo de atraso na UI; o custo de
    ///             acordar sempre é a bateria do usuário.
    init(paths: [String], latency: CFTimeInterval = 1.0) {
        (changes, continuation) = AsyncStream.makeStream(of: [String].self)

        let fm = FileManager.default
        var armed: [String] = []
        for path in paths {
            if fm.fileExists(atPath: path) {
                armed.append(path)
            } else {
                let parent = (path as NSString).deletingLastPathComponent
                if fm.fileExists(atPath: parent) { armed.append(parent) }
            }
        }
        armedPaths = Array(Set(armed)).sorted()
        guard !armedPaths.isEmpty else { return }

        // A caixa é Sendable DE VERDADE: guarda só um closure @Sendable imutável.
        // Nada de @unchecked pra calar o compilador (regra 8).
        let cont = continuation  // AsyncStream.Continuation é Sendable
        let box = CallbackBox { paths in cont.yield(paths) }
        let boxPtr = Unmanaged.passRetained(box).toOpaque()
        boxPointer = boxPtr

        var context = FSEventStreamContext(
            version: 0,
            info: boxPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer  // primeiro evento chega NA HORA; a rajada é que espera
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &context,
            armedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(boxPtr).release()
            boxPointer = nil
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        if let boxPointer {
            Unmanaged<CallbackBox>.fromOpaque(boxPointer).release()
        }
        continuation.finish()
    }
}

/// Sendable legítimo: um único campo imutável, que é um closure @Sendable.
private final class CallbackBox: Sendable {
    let onChange: @Sendable ([String]) -> Void
    init(onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
    }
}

/// Callback do C. Não captura nada — recebe a caixa pelo ponteiro `info`.
private func fsEventsCallback(
    stream: ConstFSEventStreamRef,
    info: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info, numEvents > 0 else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
    // kFSEventStreamCreateFlagUseCFTypes garante um CFArray de CFString aqui.
    guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
    box.onChange(paths)
}
