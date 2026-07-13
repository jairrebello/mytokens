# MyTokens

Monitor de tokens gastos/restantes: **Claude Code**, **Codex** e **Cursor**. Local-first, sem backend próprio.

Responde numa olhada: *posso continuar trabalhando ou vou bater no limite?*

## Estrutura

```
packages/core/   lib pura de parsing + agregação (sem Electron, sem React)
apps/desktop/    shell desktop (em definição — Electron vs Tauri)
```

## Scripts

```
pnpm install
pnpm typecheck
pnpm test
pnpm lint
```

## Status

Projeto em construção multi-agente. Ver notas do canvas Maestri (`projeto-mytokens`,
`regras-repo`, `contrato-dados`) para contexto e regras.
