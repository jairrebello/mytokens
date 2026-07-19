import Foundation
import Security
import MyTokensCore

/// O consentimento pras janelas por-modelo do Claude. Nasce DESLIGADO.
///
/// Ligar significa duas coisas que o painel diz com todas as letras: o app passa a LER o
/// token OAuth que o Claude Code guarda no Keychain, e passa a mandá-lo — num header, pra
/// UM host da Anthropic — pra perguntar o uso por modelo. Nenhuma das duas acontece sem
/// este bool, e este bool não liga sem um clique.
enum ClaudeOAuthConsent {
    static let key = "mytokens.claudeOAuthPerModel"

    static var granted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Lê o token OAuth do Claude Code do Keychain — e é o ÚNICO lugar do app que o toca.
///
/// O item é "Claude Code-credentials", criado pelo Claude Code. Regras da casa
/// (`regras-repo`): leitura SÓ, o token não é copiado pra lugar nenhum (nem UserDefaults,
/// nem arquivo, nem log — vazar token em log é bug CRÍTICO), e ele sai daqui direto pro
/// header do request no core. Os erros abaixo carregam MOTIVO, nunca o valor.
///
/// O macOS soma o prompt dele por cima do nosso consentimento: o item é de outro app,
/// então na primeira leitura o sistema pergunta ao usuário se o MyTokens pode. Dois
/// portões, os dois do usuário.
struct KeychainClaudeOAuth: ClaudeOAuthTokenProvider {

    enum Failure: LocalizedError {
        case semConsentimento
        case naoEncontrado(OSStatus)
        case ilegivel
        case vencido

        var errorDescription: String? {
            switch self {
            case .semConsentimento: "As janelas por modelo estão desligadas."
            case .naoEncontrado(let s): "Keychain não entregou o item (OSStatus \(s))."
            case .ilegivel: "O item do Keychain não tem o formato que o Claude Code grava."
            case .vencido: "O token OAuth do Claude Code está vencido."
            }
        }
    }

    func accessToken() async throws -> String {
        guard ClaudeOAuthConsent.granted else { throw Failure.semConsentimento }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw Failure.naoEncontrado(status)
        }

        // {"claudeAiOauth":{"accessToken":"…","expiresAt":<epoch em MILISSEGUNDOS>,…}}
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw Failure.ilegivel }

        // Vencido não vai pra rede: um 401 garantido só queimaria um request. O Claude
        // Code renova o token quando roda; enquanto ele não rodar, a lacuna é honesta.
        if let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: ms / 1000) <= Date() {
            throw Failure.vencido
        }
        return token
    }
}
