# DISTRIBUICAO.md — como o app sai desta máquina (e por que ainda não saiu)

Autor: agente de release. Máquina do Jair, 2026-07-13.

**Regra desta página** (a mesma do `FONTES.md`): toda afirmação vem com o comando que a
provou. O que não foi provado está marcado **NÃO PROVADO**, em voz alta — e aqui tem uma
seção inteira disso, porque metade deste caminho depende de uma conta que ainda não existe.
Um "não sei" honesto vale mais que um chute confiante.

---

## 0. TL;DR — o estado de hoje, em uma linha

**O MyTokens não sai desta máquina.** Falta uma coisa, e ela custa **US$ 99/ano**: a conta
do Apple Developer Program. Sem ela não há certificado "Developer ID Application"; sem
certificado não há notarização; sem notarização o Gatekeeper barra o app no Mac do outro.

Tudo o mais já está pronto e testado: `scripts/release.sh` compila, assina, notariza,
empacota e **prova** o resultado com `spctl`. Ele só se recusa a fingir.

| | Estado | Provado por |
|---|---|---|
| Conta Apple Developer (US$ 99/ano) | ✗ **falta — é isto que trava tudo** | `security find-identity` (abaixo) |
| Certificado Developer ID Application | ✗ falta (depende da conta) | idem |
| Credencial do `notarytool` | ✗ falta (depende da conta) | `release.sh --check` |
| Hardened runtime | ✓ já ligado | `ENABLE_HARDENED_RUNTIME = YES` no pbxproj |
| Sandbox desligada (decisão consciente) | ✓ | `App/MyTokens.entitlements` |
| Script de release | ✓ `scripts/release.sh` | rodado; falha certo, ver §4 |
| CI (build + teste) | ✓ `.github/workflows/ci.yml` | **NÃO PROVADO** — ver §7 |

---

## 1. O que existe hoje — provado

### 1.1 Não há identidade de assinatura nesta máquina

```bash
$ security find-identity -v -p codesigning
     0 valid identities found
```

Zero. Não é "tem uma vencida", não é "tem a errada": **não tem nenhuma**.

### 1.2 O app é assinado ad-hoc

`MyTokens.xcodeproj/project.pbxproj`, nas duas configurações (Debug e Release):

```
CODE_SIGN_IDENTITY = "-";      ← ad-hoc: assina com nada, vale só localmente
DEVELOPMENT_TEAM = "";         ← nenhum time
ENABLE_HARDENED_RUNTIME = YES; ← isto já está certo, e é requisito da notarização
```

E o binário construído confirma:

```bash
$ codesign -dvv /Volumes/MyTokens\ 0.1.0/MyTokens.app 2>&1 | grep -E "Signature|TeamIdentifier"
Signature=adhoc
TeamIdentifier=not set
```

### 1.3 O que o ad-hoc provoca na máquina do outro — a prova

Este é o fato que justifica a página inteira. Um DMG feito hoje, com o app tal como ele é:

```bash
$ ./scripts/release.sh --local
$ spctl -a -vvv /Volumes/MyTokens\ 0.1.0/MyTokens.app
/Volumes/MyTokens 0.1.0/MyTokens.app: rejected
```

**`rejected`.** É a palavra do próprio Gatekeeper. Na máquina de outra pessoa isso vira o
diálogo *"«MyTokens» está danificado e não pode ser aberto. Mova-o para o Lixo."* — uma
mensagem que **mente sobre a causa** (o app não está danificado; ele está sem notarização),
que o usuário acredita, e que mata o app ali.

Por isso `scripts/release.sh` **falha alto** em vez de gerar esse DMG por engano. Um
artefato que o Gatekeeper barra é pior que artefato nenhum: ele *parece* pronto.

### 1.4 Por que a sandbox está desligada (e por que isso decide a rota)

`App/MyTokens.entitlements` diz `com.apple.security.app-sandbox = false`, de propósito: o
app lê `~/.claude`, `~/.codex` e o SQLite do Cursor. Com sandbox, cada uma dessas pastas
exigiria file-picker do usuário + security-scoped bookmarks.

**Consequência, e é ela que fecha a rota:** a Mac App Store **exige** sandbox. Logo a App
Store está fora, e a única saída é **Developer ID + notarização**. Não é preferência de
estilo — é a única porta que sobrou.

---

## 2. O que falta comprar e criar

Em ordem. O item 1 custa dinheiro; o resto custa uns 15 minutos.

### 2.1 Conta no Apple Developer Program — US$ 99/ano

https://developer.apple.com/programs/enroll/

> **A conta grátis NÃO serve.** Ela emite só o certificado "Apple Development", que assina
> para rodar *na sua própria máquina* — exatamente o que o ad-hoc já faz de graça. Ela
> **não** emite "Developer ID Application", e **não** dá acesso à notarização. Não há
> caminho gratuito para distribuir fora da App Store. Esse é o pedágio da Apple.

Pessoa física serve (não precisa de empresa nem de D-U-N-S). A aprovação costuma sair em
24-48 h.

### 2.2 O certificado "Developer ID Application"

Com a conta ativa:

```
Xcode → Settings → Accounts → (sua conta) → Manage Certificates
  → botão +  → "Developer ID Application"
```

Ele nasce direto no chaveiro. A prova de que funcionou é a mesma linha de comando de antes,
com a resposta trocada:

```bash
$ security find-identity -v -p codesigning
  1) A1B2C3...  "Developer ID Application: Jair Rebello (A1B2C3D4E5)"
     1 valid identities found
```

Os 10 caracteres dentro do parêntese são o **Team ID**. O `release.sh` extrai sozinho — não
é preciso digitar em lugar nenhum, e **nenhum Team ID está hardcodado neste repositório**.

> **Guarde o backup do certificado.** Chaveiro → exportar como `.p12`, com senha, num lugar
> seguro. Se a máquina morrer sem esse backup, a chave privada morre junto: dá para revogar
> e emitir outra, mas todo binário já assinado com a antiga fica órfão.
> (O `.gitignore` já bloqueia `*.p12`, `*.p8`, `*.pem`, `*.key` — o `.p12` **nunca** entra
> no git.)

### 2.3 A credencial de notarização (app-specific password)

A notarização é um segundo login — o certificado assina, mas quem envia o binário para a
Apple é o `notarytool`, e ele quer credencial própria.

1. Crie uma **app-specific password** (NÃO é a senha do seu Apple ID):
   https://account.apple.com → Sign-In and Security → App-Specific Passwords
   Sai no formato `xxxx-xxxx-xxxx-xxxx`.

2. Guarde no chaveiro, **uma vez só**:

```bash
$ xcrun notarytool store-credentials "mytokens" \
    --apple-id "voce@exemplo.com" \
    --team-id "A1B2C3D4E5" \
    --password "xxxx-xxxx-xxxx-xxxx"
```

O nome do perfil (`mytokens`) é o default que o `release.sh` procura. Prova de que colou:

```bash
$ xcrun notarytool history --keychain-profile "mytokens"
Successfully received submission history.
```

> A senha vai para o **chaveiro**, não para arquivo nenhum do repo. É a regra 4 do projeto.
> Se preferir não usar o chaveiro, o `release.sh` também aceita `APPLE_ID`, `APPLE_PASSWORD`
> e `TEAM_ID` no ambiente.

---

## 3. O dia em que a conta existir — o passo a passo inteiro

```bash
# 1. conferir que a máquina tem tudo (não compila nada; só diagnostica)
$ ./scripts/release.sh --check
  ✓ identidade de assinatura: Developer ID Application: Jair Rebello (A1B2C3D4E5)
  ✓ credencial de notarização: autentica (notarytool history respondeu)
  → dá pra distribuir. Rode: ./scripts/release.sh

# 2. a release inteira: compila, assina, notariza, empacota, PROVA
$ ./scripts/release.sh
```

E é isso. Não há passo manual escondido. O script:

1. **Confere a credencial ANTES de compilar** — descobrir que falta certificado depois de
   dois minutos de `xcodebuild` é desrespeito com quem está esperando.
2. Compila em Release passando `CODE_SIGN_IDENTITY`, `DEVELOPMENT_TEAM` e
   `--timestamp --options=runtime` **na linha de comando** (precedência mais alta do
   `xcodebuild`; ganha do `"-"` do pbxproj sem tocar num byte do projeto — ver §6).
3. **Aborta se o build falhar.** Óbvio, e mesmo assim foi bug: `xcodebuild | grep … || true`
   devolve o status do *grep*, e um `BUILD FAILED` passava batido — o script seguia,
   encontrava a casca de bundle que o xcodebuild deixa pra trás (`Contents/MacOS/` **vazio**)
   e empacotava um DMG com um app **sem binário dentro**, anunciando sucesso. Pego rodando o
   próprio script. Corrigido aqui e no `install.sh`, que tinha o mesmo furo — e lá era pior:
   ele **substituía** o app bom em `/Applications` por uma casca que não abre.
4. Notariza o **`.app`** (via `ditto` → zip → `notarytool submit --wait`) e o **grampeia**
   (`stapler staple`).
5. Monta o DMG (`hdiutil`, `MyTokens.app` + link para `/Applications`), assina o DMG,
   notariza o DMG, grampeia o DMG.
6. **Prova** — §4.

> **Por que duas idas à Apple (o app E o DMG), se uma parece bastar?**
> Grampear só o DMG deixa o `.app` sem ticket próprio. Enquanto o usuário abre direto do
> DMG, tudo bem. Mas ele **arrasta o app para `/Applications`** — e aí o app sozinho depende
> de consulta *online* ao ticket. Primeira abertura offline: falha. Grampear os dois custa
> alguns minutos a mais e elimina a classe inteira de "às vezes não abre".

Cada `notarytool submit --wait` costuma levar de 1 a 5 minutos. Se a Apple **rejeitar**, ela
diz por quê:

```bash
$ xcrun notarytool log <submission-id> --keychain-profile "mytokens"
```

Os dois motivos que respondem por quase toda rejeição já estão prevenidos no script:
hardened runtime desligado (aqui está `YES`) e assinatura sem secure timestamp (aqui vai
`--timestamp`).

---

## 4. Como verificar que funcionou — o teste de aceitação

O `release.sh` roda isto sozinho no fim, e o `set -e` mata o script se qualquer linha falhar:
**ou o DMG passa no Gatekeeper, ou ele não é anunciado como pronto.** Mas rode você mesmo:

```bash
# 1. o veredito do Gatekeeper. É ESTA linha que decide tudo.
$ spctl -a -vvv /Applications/MyTokens.app
/Applications/MyTokens.app: accepted
source=Notarized Developer ID          ← a frase que você quer ler
origin=Developer ID Application: Jair Rebello (A1B2C3D4E5)

# 2. o ticket está grampeado no bundle (é isto que faz funcionar OFFLINE)
$ xcrun stapler validate /Applications/MyTokens.app
The validate action worked!

# 3. a assinatura fecha, recursivamente
$ codesign --verify --deep --strict --verbose=2 /Applications/MyTokens.app
--prepared:/Applications/MyTokens.app
--validated:/Applications/MyTokens.app
/Applications/MyTokens.app: valid on disk
/Applications/MyTokens.app: satisfies its Designated Requirement

# 4. o DMG também
$ spctl -a -vvv -t open --context context:primary-signature dist/MyTokens-0.1.0.dmg
dist/MyTokens-0.1.0.dmg: accepted
```

`accepted` + `source=Notarized Developer ID` é a prova. Qualquer outra coisa — `rejected`,
`source=Unnotarized Developer ID`, `no usable signature` — significa que **não está pronto**.

### 4.1 O teste que vale mais que os quatro acima

Os comandos acima rodam na máquina que *assinou* o app — ela é cúmplice. O teste honesto é
simular o que o Mac do outro faz: carimbar o arquivo como "baixado da internet" (é esse
`xattr` que liga o Gatekeeper de verdade) e só então abrir.

```bash
$ xattr -w com.apple.quarantine "0081;00000000;Safari;" dist/MyTokens-0.1.0.dmg
$ xattr -l dist/MyTokens-0.1.0.dmg        # confirma que o carimbo está lá
$ open dist/MyTokens-0.1.0.dmg            # tem que abrir sem susto nenhum
```

Se abrir limpo, com o app quarentenado, acabou: **está distribuível**. Melhor ainda é pedir
para alguém baixar num Mac que nunca viu este projeto — mas o `xattr` acima pega 95% dos
erros sem depender de ninguém.

---

## 5. Enquanto a conta não existe

```bash
./scripts/install.sh          # instala em /Applications. É o caminho de hoje. Funciona.
./scripts/release.sh --local  # DMG ad-hoc — e ele GRITA que só serve nesta máquina
```

O `--local` existe para testar o empacotamento, não para distribuir. Ele imprime, sem
rodeios:

```
  ⚠  DMG LOCAL — NÃO DISTRIBUÍVEL:  dist/MyTokens-0.1.0.dmg
  Este DMG contém um app assinado AD-HOC. Ele funciona nesta máquina e SÓ nesta máquina.
  NÃO mande este arquivo pra ninguém. Ele parece um release e não é.
```

E o `spctl` confirma que o aviso não é exagero: `rejected` (§1.3).

**Não existe atalho.** Mandar o `.zip` e ensinar o outro a fazer botão-direito → Abrir, ou a
rodar `xattr -dr com.apple.quarantine`, *funciona* — e é péssimo: ensina o usuário a desarmar
a própria proteção do sistema para rodar um binário que ele não pode verificar. Um app que
lê o histórico inteiro do `~/.claude` da pessoa não tem o direito de pedir isso.

---

## 6. Por que o `project.pbxproj` NÃO foi tocado

A tentação era pôr um `.xcconfig` com `CODE_SIGN_IDENTITY` e `DEVELOPMENT_TEAM`. Não foi
feito, por dois motivos — e o primeiro é técnico, não estético:

1. **Um `.xcconfig` de projeto não ganharia.** As configurações de assinatura estão no
   **alvo** (`CODE_SIGN_IDENTITY = "-"` nas duas `XCBuildConfiguration` do target), e alvo
   vence xcconfig de projeto. Para o xcconfig valer, seria preciso *editar o pbxproj* de
   qualquer jeito — ou seja, o risco não seria evitado, só adiado.

2. **A linha de comando já ganha de todo mundo, e não deixa rastro.** Foi verificado:

```bash
$ xcodebuild -project MyTokens.xcodeproj -scheme MyTokens -configuration Release \
    -showBuildSettings CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="ABCDE12345" \
  | grep -E "CODE_SIGN_IDENTITY|DEVELOPMENT_TEAM|ENABLE_HARDENED_RUNTIME"
    CODE_SIGN_IDENTITY = Developer ID Application     ← sobrescreveu o "-"
    DEVELOPMENT_TEAM = ABCDE12345                     ← sobrescreveu o ""
    ENABLE_HARDENED_RUNTIME = YES                     ← já estava certo
```

O override na linha de comando é a precedência mais alta do `xcodebuild`. Então o
`release.sh` passa os valores lá, o build ad-hoc do dia a dia continua **byte a byte o que
era**, e o pbxproj segue sem Team ID nenhum dentro dele — que é exatamente onde um Team ID
não deve estar.

---

## 7. NÃO PROVADO — a parte honesta

Isto aqui não foi verificado, e não dá para verificar sem a conta paga. Está listado para
que ninguém leia esta página como "está tudo testado":

- **A notarização nunca rodou.** `notarytool submit`, `stapler staple` e o `spctl` dando
  `accepted` são o comportamento **documentado pela Apple**, escrito no script conforme a
  documentação — mas nesta máquina, hoje, nada disso executou uma vez sequer, porque não há
  credencial. O caminho feliz do `release.sh` (tudo depois de `notarytool submit`) é
  **código não executado**. Espere um ou outro ajuste pequeno na primeira release de verdade;
  o que *está* provado é que ele não produz lixo enquanto isso: ele para, e explica.

- **As saídas de exemplo das §3 e §4** (`accepted`, `source=Notarized Developer ID`, `The
  validate action worked!`) são o formato documentado desses comandos, **não** capturas
  desta máquina. As saídas reais que aparecem nesta página — `0 valid identities found`,
  `Signature=adhoc`, `rejected` — essas sim foram capturadas aqui, hoje.

- **O CI nunca rodou.** O `.github/workflows/ci.yml` foi criado agora; não há remote com
  Actions ligado. O YAML foi validado (`yaml.safe_load`, sem exceção) e cada comando dele
  foi rodado à mão nesta máquina, mas o workflow em si é **NÃO PROVADO** até o primeiro push.

- **Os testes de disco real não rodam no CI, e o verde do CI não os cobre.**
  `RealDiskTests.swift` lê o `~/.claude` e o `~/.codex` de quem roda. No runner do GitHub
  eles não existem, e as suítes se desativam sozinhas — `.enabled(if: hasClaudeDisk)`, que
  já estava no código antes do CI existir. **Nenhum teste foi desligado para caber no CI.**
  Provado simulando a condição do runner (home vazio, que é o que o macOS de fato honra via
  `CFFIXED_USER_HOME` — `HOME` sozinho **não** muda o `NSHomeDirectory()`):

  ```bash
  $ CFFIXED_USER_HOME=/tmp/vazio swift test        # em MyTokensCore/
  ✔ Test run with 53 tests in 8 suites passed after 2.104 seconds.
  ```

  Contra o disco real, o mesmo comando leva 91 s — a diferença é exatamente o trabalho que o
  CI **não** faz. Quem roda esses testes é o dono do disco, com `swift test` local.

---

## 8. Resumo para o Jair

**Compre uma coisa:** a conta do Apple Developer Program, US$ 99/ano
(https://developer.apple.com/programs/enroll/). É o único item pago, e é o que trava tudo.

**Depois, 15 minutos:**
1. Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application
2. `xcrun notarytool store-credentials "mytokens" --apple-id … --team-id … --password …`
   (a senha é uma *app-specific password* de account.apple.com, não a do Apple ID)
3. `./scripts/release.sh --check` → tem que dar dois ✓
4. `./scripts/release.sh` → sai `dist/MyTokens-<versão>.dmg`, assinado, notarizado e grampeado
5. `spctl -a -vvv /Applications/MyTokens.app` → tem que dizer **`accepted`**

Até o passo 1 acontecer, o app roda aqui e só aqui — e todo script deste repo diz isso na
cara, em vez de deixar você descobrir pelo amigo que não conseguiu abrir o DMG.
