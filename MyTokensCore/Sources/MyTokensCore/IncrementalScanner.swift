// Cache incremental por (arquivo, mtime, tamanho, offset).
//
// 970MB em 6.268 JSONL do Claude + 450MB do Codex, e crescendo. Reparsear tudo a
// cada refresh é inaceitável. JSONL é APPEND-ONLY: se o arquivo só cresceu, os bytes
// velhos são idênticos e já foram digeridos — só lemos de `offset` até o fim.
//
// Guardas:
//   - tamanho ENCOLHEU ou mtime mudou sem crescer  -> reparse total (rotação/reescrita).
//   - último byte não é \n                          -> linha parcial (escrita em voo):
//     consome só até o último \n e o offset para ali. A linha entra no próximo scan.

import Foundation

/// Quem sabe transformar bytes novos de UM arquivo em um resumo daquele arquivo.
/// Claude: o resumo é a lista de linhas assistant. Codex: é o último token_count.
public protocol IncrementalFileParser: Sendable {
    associatedtype Digest: Sendable
    /// `newBytes` = fatia nova do arquivo (do offset anterior até o último \n).
    /// `previous` = digest do scan anterior; nil no primeiro scan do arquivo.
    func digest(newBytes: Data, file: URL, previous: Digest?) -> Digest
}

public struct ScanStats: Sendable, Equatable {
    public var filesSeen = 0
    public var filesReparsed = 0
    public var filesAppended = 0
    public var filesUnchanged = 0
    public var bytesRead: Int64 = 0
    public var duration: TimeInterval = 0
}

public struct ScanResult<Digest: Sendable>: Sendable {
    /// caminho -> digest do arquivo.
    public var digests: [String: Digest]
    public var stats: ScanStats
    /// Algum arquivo nasceu, cresceu, foi reescrito ou sumiu?
    ///
    /// `false` = o disco está EXATAMENTE como no scan anterior, e quem chama pode reusar
    /// o que já calculou. Sem isto, o refresh reconstrói 45 mil eventos (dedup, Decimal,
    /// ordenação) pra chegar no mesmo array de antes — 314 ms de trabalho pra nada, a
    /// cada evento de FSEvents.
    public var changed: Bool { !changedPaths.isEmpty || !removedPaths.isEmpty }

    /// QUAIS arquivos foram parseados agora (nasceram, cresceram ou foram reescritos).
    /// Saber quais, e não só que houve algum, é o que permite refazer só a parte que
    /// mudou em vez do mundo inteiro.
    public var changedPaths: [String]
    /// Sumiram do disco.
    public var removedPaths: [String]
}

/// Um arquivo com tamanho e mtime JÁ LIDOS.
///
/// O enumerator do FileWalker passa por cada arquivo e o kernel já lhe entrega os
/// atributos. Jogar isso fora e depois chamar `attributesOfItem` em cada um custava
/// 6.597 syscalls e ~330 ms por refresh — o maior custo do scan incremental, num scan
/// que não lia UM byte.
public struct ScannedFile: Sendable, Hashable {
    public let url: URL
    public let size: Int64
    public let mtime: TimeInterval

    public init(url: URL, size: Int64, mtime: TimeInterval) {
        self.url = url
        self.size = size
        self.mtime = mtime
    }

    /// Quando você tem só a URL e precisa dos atributos. Custa um stat — o FileWalker
    /// NÃO usa isto (lá os atributos vêm de graça do enumerator). É pra teste e pra
    /// quem chega com uma URL solta na mão.
    ///
    /// ⚠️ `URL` CACHEIA resource values dentro do próprio objeto. Reusar a mesma URL
    /// depois de o arquivo crescer devolve o TAMANHO VELHO — e um scanner incremental
    /// que lê tamanho velho conclui "nada mudou" e perde o gasto. Por isso o cache é
    /// derrubado ANTES de cada leitura.
    public init?(stating url: URL) {
        var u = url
        u.removeAllCachedResourceValues()
        guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = v.fileSize,
              let mtime = v.contentModificationDate
        else { return nil }
        self.init(url: url, size: Int64(size), mtime: mtime.timeIntervalSince1970)
    }

    public var path: String { url.path }
}

public actor IncrementalScanner<P: IncrementalFileParser> {
    private struct Entry: Sendable {
        var size: Int64
        var mtime: TimeInterval
        /// bytes já digeridos (sempre termina logo depois de um \n).
        var offset: Int64
        var digest: P.Digest
    }

    private enum Plan: Sendable {
        case unchanged
        case read(from: Int64, size: Int64, mtime: TimeInterval, reuse: Bool)
        case drop
    }

    private struct Parsed: Sendable {
        let path: String
        let entry: Entry
        let bytesRead: Int64
    }

    private let parser: P
    private var entries: [String: Entry] = [:]

    public init(parser: P) { self.parser = parser }

    public var cachedFileCount: Int { entries.count }

    public func reset() { entries.removeAll() }

    /// Varre `files` em paralelo. Devolve o digest de cada arquivo — dos que mudaram
    /// (reparse/append) e dos que não mudaram (vem do cache, custo zero).
    public func scan(files: [ScannedFile]) async -> ScanResult<P.Digest> {
        let start = DispatchTime.now()
        var stats = ScanStats()
        stats.filesSeen = files.count

        // 1) Decide o que fazer com cada arquivo. Tamanho e mtime já vieram do walker —
        //    não custam syscall nenhum aqui. O parse é que é caro.
        var plans: [(URL, Plan)] = []
        plans.reserveCapacity(files.count)

        for f in files {
            let (url, size, mtime) = (f.url, f.size, f.mtime)

            if let e = entries[url.path] {
                if e.size == size && e.mtime == mtime {
                    plans.append((url, .unchanged))
                } else if size > e.size && e.offset <= size {
                    // cresceu: só o rabo é novo.
                    plans.append((url, .read(from: e.offset, size: size, mtime: mtime, reuse: true)))
                } else {
                    // encolheu ou foi reescrito: não dá pra confiar no offset.
                    plans.append((url, .read(from: 0, size: size, mtime: mtime, reuse: false)))
                }
            } else {
                plans.append((url, .read(from: 0, size: size, mtime: mtime, reuse: false)))
            }
        }

        // 2) Parseia em paralelo só o que mudou.
        let parser = self.parser
        var work: [(URL, Int64, Int64, TimeInterval, P.Digest?)] = []
        for (url, plan) in plans {
            switch plan {
            case .unchanged:
                stats.filesUnchanged += 1
            case .drop:
                entries.removeValue(forKey: url.path)
            case let .read(from, size, mtime, reuse):
                if reuse { stats.filesAppended += 1 } else { stats.filesReparsed += 1 }
                work.append((url, from, size, mtime, reuse ? entries[url.path]?.digest : nil))
            }
        }

        let parsedList: [Parsed] = await withTaskGroup(of: Parsed?.self) { group in
            for (url, from, size, mtime, previous) in work {
                group.addTask {
                    guard let (bytes, consumed) = Self.readTail(url: url, from: from, size: size)
                    else { return nil }
                    let digest = parser.digest(newBytes: bytes, file: url, previous: previous)
                    return Parsed(
                        path: url.path,
                        entry: Entry(size: size, mtime: mtime, offset: from + consumed, digest: digest),
                        bytesRead: consumed
                    )
                }
            }
            var acc: [Parsed] = []
            acc.reserveCapacity(work.count)
            for await p in group { if let p { acc.append(p) } }
            return acc
        }

        for p in parsedList {
            entries[p.path] = p.entry
            stats.bytesRead += p.bytesRead
        }

        // 3) Poda arquivos que sumiram do disco.
        let alive = Set(files.map(\.path))
        let removed = entries.keys.filter { !alive.contains($0) }
        for p in removed { entries.removeValue(forKey: p) }

        var digests: [String: P.Digest] = [:]
        digests.reserveCapacity(entries.count)
        for (path, e) in entries { digests[path] = e.digest }

        stats.duration = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        return ScanResult(
            digests: digests,
            stats: stats,
            changedPaths: parsedList.map(\.path),
            removedPaths: removed
        )
    }

    /// Lê [from, size) e corta no ÚLTIMO \n — nunca entrega linha pela metade.
    /// Devolve (bytes, quantos bytes foram realmente consumidos).
    private static func readTail(url: URL, from: Int64, size: Int64) -> (Data, Int64)? {
        guard size > from else { return (Data(), 0) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(from))
            guard var data = try handle.read(upToCount: Int(size - from)) else { return (Data(), 0) }
            guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
                // nenhuma linha completa nova ainda.
                return (Data(), 0)
            }
            let consumed = Int64(lastNewline - data.startIndex + 1)
            data = data[data.startIndex...lastNewline]
            return (data, consumed)
        } catch {
            return nil
        }
    }
}

// MARK: - Varredura de diretório

public enum FileWalker {
    /// Lista arquivos RECURSIVAMENTE, JÁ COM tamanho e mtime. Recursão não é luxo: o
    /// transcript de subagente (Task) vive em <slug>/<sessionId>/subagents/*.jsonl, um
    /// nível abaixo. Varrer só o topo perde 686 arquivos de gasto REAL. (docs/FONTES.md §1)
    ///
    /// Os atributos vêm PRÉ-BUSCADOS pelo enumerator (`includingPropertiesForKeys`): o
    /// kernel já os tem em mãos ao listar o diretório. Pedi-los aqui é de graça; pedi-los
    /// depois, arquivo por arquivo, custava 330 ms por refresh.
    public static func jsonl(under root: URL, namePrefix: String? = nil) -> [ScannedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [ScannedFile] = []
        for case let url as URL in e {
            guard url.pathExtension == "jsonl" else { continue }
            if let namePrefix, !url.lastPathComponent.hasPrefix(namePrefix) { continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let size = v.fileSize,
                  let mtime = v.contentModificationDate
            else { continue }
            out.append(ScannedFile(
                url: url,
                size: Int64(size),
                mtime: mtime.timeIntervalSince1970
            ))
        }
        return out
    }
}
