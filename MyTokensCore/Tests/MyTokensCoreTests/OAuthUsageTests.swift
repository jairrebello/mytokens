//  OAuthUsageTests.swift
//
//  A tradução do GET /api/oauth/usage — a ÚNICA fonte das janelas por-modelo do
//  Claude. Tudo aqui é a função pura `windows(fromResponse:now:)`: rede nenhuma.
//
//  As pegadinhas que valem teste: utilization é 0..1 mas limits[].percent JÁ é
//  0-100; resets_at é STRING ISO (no hook é epoch em segundos); Opus/Sonnet
//  podem vir DUAS vezes (campo fixo + limits[]); e o CLI às vezes embrulha o
//  miolo em {utilization: ...}, às vezes manda direto.

import Foundation
import Testing
@testable import MyTokensCore

@Suite("Claude OAuth /usage — as janelas que o hook não tem")
struct OAuthUsageTests {

    let agora = Date(timeIntervalSince1970: 1_784_500_000)  // jul/2026
    var amanha: String { ISO8601DateFormatter().string(from: agora.addingTimeInterval(86_400)) }

    func payload(_ miolo: String, embrulhado: Bool) -> Data {
        let s = embrulhado ? #"{"fetchedAtMs": 1, "accountUuid": "x", "utilization": \#(miolo)}"# : miolo
        return Data(s.utf8)
    }

    @Test("payload completo: conta + por-modelo, cada um na escala CERTA",
          arguments: [true, false])   // embrulhado no CLI ou miolo direto — tanto faz
    func fullPayload(embrulhado: Bool) {
        let miolo = """
        {
          "five_hour": {"utilization": 0.42, "resets_at": "\(amanha)"},
          "seven_day": {"utilization": 0.815, "resets_at": "\(amanha)"},
          "seven_day_opus": {"utilization": 0.10, "resets_at": "\(amanha)"},
          "limits": [
            {"kind": "weekly", "percent": 55, "resets_at": "\(amanha)",
             "scope": {"model": {"display_name": "Fable"}}}
          ]
        }
        """
        let w = ClaudeOAuthUsageSource.windows(fromResponse: payload(miolo, embrulhado: embrulhado), now: agora)

        #expect(w.map(\.id) == ["claude-5h", "claude-7d", "claude-7d-opus", "claude-7d-fable"])
        // utilization 0..1 vira % — 0.815 NÃO pode chegar na tela como 0,815%.
        #expect(w[1].usedPercent == 81.5)
        // limits[].percent JÁ é 0-100 — multiplicar de novo viraria 5500%.
        #expect(w[3].usedPercent == 55)
        #expect(w[3].label == "Semana · Fable")
        #expect(w[3].modelScope == "Fable")
        #expect(w[0].modelScope == nil, "a cota da conta não tem modelo")
        #expect(w.allSatisfy { $0.source == .measured })
    }

    @Test("Opus em dobro (campo fixo + limits[]) entra UMA vez — o fixo ganha")
    func opusNotDuplicated() {
        let miolo = """
        {
          "seven_day_opus": {"utilization": 0.10, "resets_at": "\(amanha)"},
          "limits": [
            {"percent": 99, "resets_at": "\(amanha)",
             "scope": {"model": {"display_name": "Opus"}}}
          ]
        }
        """
        let w = ClaudeOAuthUsageSource.windows(fromResponse: payload(miolo, embrulhado: true), now: agora)
        #expect(w.map(\.id) == ["claude-7d-opus"])
        #expect(w[0].usedPercent == 10, "o campo fixo entrou primeiro e fica")
    }

    @Test("janela morta não fala: utilization null, resets vencido ou ausente → fora")
    func deadWindowsDropped() {
        let ontem = ISO8601DateFormatter().string(from: agora.addingTimeInterval(-3600))
        let miolo = """
        {
          "five_hour": {"utilization": null, "resets_at": "\(amanha)"},
          "seven_day": {"utilization": 0.5, "resets_at": "\(ontem)"},
          "seven_day_opus": {"utilization": 0.5, "resets_at": null},
          "limits": [
            {"percent": 55, "resets_at": "\(ontem)",
             "scope": {"model": {"display_name": "Fable"}}}
          ]
        }
        """
        let w = ClaudeOAuthUsageSource.windows(fromResponse: payload(miolo, embrulhado: false), now: agora)
        #expect(w.isEmpty, "melhor lacuna honesta que número fabricado")
    }

    @Test("lixo não derruba: payload que não é JSON de objeto devolve []")
    func garbageDegrades() {
        #expect(ClaudeOAuthUsageSource.windows(fromResponse: Data("not json".utf8), now: agora).isEmpty)
        #expect(ClaudeOAuthUsageSource.windows(fromResponse: Data("[1,2]".utf8), now: agora).isEmpty)
    }

    @Test("merge: em id repetido o hook GANHA — ele é event-driven, o GET é esporádico")
    func hookWinsOnMerge() {
        func w(_ id: String, pct: Double) -> LimitWindow {
            LimitWindow(id: id, label: id, usedPercent: pct,
                        resetsAt: agora.addingTimeInterval(3600),
                        source: .measured, startedAt: agora,
                        measuredAt: agora, measuredPercent: pct)
        }
        let hook = [w("claude-7d", pct: 40)]
        let endpoint = [w("claude-7d", pct: 35), w("claude-7d-fable", pct: 70)]
        let merged = ClaudeOAuthUsageSource.merge(hook: hook, endpoint: endpoint)
        #expect(merged.map(\.id) == ["claude-7d", "claude-7d-fable"])
        #expect(merged[0].usedPercent == 40, "o número do hook, não o do GET")
    }
}
