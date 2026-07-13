//  ReduceMotion.swift
//
//  UI-SPEC §6, última subseção: "reduce motion corta a ANIMAÇÃO, nunca a
//  INFORMAÇÃO." Este arquivo é o único lugar do pacote que sabe disso.
//
//  A curva não é escolhida na view — a view declara a INTENÇÃO (`.data`,
//  `.chrome`, `.pulse`) e a intenção resolve a curva, já filtrada pelo
//  Reduce Motion do sistema. É a mesma disciplina do `Certainty`: a regra vira
//  TIPO, não um `if` repetido em cinco arquivos. Uma view não consegue esquecer
//  de checar o Reduce Motion porque não existe caminho de código que anime sem
//  passar por aqui.
//
//  O que o Reduce Motion NÃO faz: sumir com estado. A tinta continua indo até o
//  valor certo, o número continua trocando, o pulso do vazio continua ACESO —
//  só param de se mexer no caminho. Quem tem enjoo de movimento não perde dado.

import SwiftUI

extension Motion {

    /// A intenção do movimento. A curva é consequência dela, e do Reduce Motion.
    public enum Cue: Sendable {
        /// Tinta avançando, número trocando de valor. Dado MEDIDO em movimento —
        /// e é por isso que a mola aqui tem `dampingFraction: 1.0`: overshoot
        /// exibiria, por ~80 ms, um número que é mentira (UI-SPEC §6).
        case data
        /// O dreno do reset. Mais LENTO que o avanço, de propósito: encher é
        /// rotina, esvaziar é acontecimento.
        case drain
        /// Hover, revelar, o card de convite. É o ÚNICO lugar onde bounce é
        /// permitido — chrome pode quicar, dado não.
        case chrome
        /// Micro-troca de estado (tick de 140 ms).
        case tick
        /// O pulso do estado vazio. Puro sinal de vida — nenhum bit de dado mora
        /// nele, e é o único movimento que o Reduce Motion pode matar INTEIRO.
        case pulse

        /// A resolução. Pura, e por isso testável sem subir uma tela.
        ///
        /// `nil` = "não anime" (o SwiftUI aplica a mudança na hora). Repare que
        /// só o `pulse` vira `nil`: os outros ainda animam, num ease-out curto —
        /// o movimento encolhe pra 200 ms, mas o valor final é sempre o mesmo.
        public func animation(reduceMotion: Bool) -> Animation? {
            guard reduceMotion else {
                switch self {
                case .data:   return Motion.state
                case .drain:  return Motion.drain
                case .chrome: return Motion.ui
                case .tick:   return Motion.tick
                case .pulse:  return Motion.pulse
                }
            }
            switch self {
            case .pulse:
                // O ponto para de piscar e FICA ACESO. O instrumento continua
                // ligado — a informação é a luz, não a oscilação dela.
                return nil
            case .data, .drain, .chrome, .tick:
                // O ease-out curto do §6. Sem mola, sem overshoot, sem 900 ms de
                // dreno: a distância entre o valor velho e o novo continua sendo
                // percorrida — só que rápido e reto.
                return Motion.calm
            }
        }
    }

    /// O pulso do vazio: 1,2 s indo e voltando — o ritmo de uma respiração calma.
    /// Não é spinner. Spinner diz "estou travado"; isto diz "estou ligado".
    public static let pulse = Animation.easeInOut(duration: 1.2)
        .repeatForever(autoreverses: true)

    /// A curva do Reduce Motion. Uma só, pra todo mundo: o §6 escreve
    /// `.easeOut(duration: 0.2)` e não há razão de inventar cinco variantes de
    /// "quase parado".
    public static let calm = Animation.easeOut(duration: 0.20)
}

// MARK: - O ponto central

/// Lê o Reduce Motion do sistema e resolve a curva. É o único `@Environment(\.
/// accessibilityReduceMotion)` do pacote — se aparecer um segundo, alguém está
/// reimplementando esta regra em vez de usá-la.
struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cue: Motion.Cue
    let value: V

    func body(content: Content) -> some View {
        content.animation(cue.animation(reduceMotion: reduceMotion), value: value)
    }
}

/// O mesmo, pro texto que TROCA de valor. `numericText()` rola os dígitos como
/// um odômetro — que é movimento, e movimento é o que o Reduce Motion pede pra
/// não ter. A troca vira uma dissolvência: o número novo continua chegando.
struct NumericTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : .numericText())
    }
}

extension View {
    /// Anima `value` com a intenção `cue`, respeitando o Reduce Motion do sistema.
    /// Toda animação do pacote passa por aqui. Não existe `.animation(...)` solto.
    public func motion<V: Equatable>(_ cue: Motion.Cue, value: V) -> some View {
        modifier(MotionModifier(cue: cue, value: value))
    }

    /// O odômetro do número — ou a dissolvência, sob Reduce Motion.
    public func numericValueTransition() -> some View {
        modifier(NumericTransitionModifier())
    }
}
