#!/usr/bin/env bun
/**
 * scan-codex.ts — parser de referência para ~/.codex/sessions|archived_sessions
 *
 * O Codex é o caso FÁCIL: ele entrega o "restante" de bandeja (rate_limits).
 * Mas tem duas armadilhas que invertem o sinal do número se erradas:
 *
 *   ARMADILHA A (ACUMULADO): info.total_token_usage é o acumulado DA SESSÃO INTEIRA,
 *     reescrito a cada turno. Somar todos os token_count conta o mesmo token N vezes.
 *     -> Pegue só o ÚLTIMO token_count de cada sessão. (Ver `sessionTotals`.)
 *
 *   ARMADILHA B (SNAPSHOT): rate_limits.used_percent é um SNAPSHOT do momento.
 *     O valor "agora" NÃO é o do arquivo mais recente por nome/mtime — é o do evento
 *     com maior TIMESTAMP entre TODAS as sessões. (Ver `currentRateLimits`.)
 *
 * Uso:
 *   bun scripts/probe/scan-codex.ts --pretty
 */

import { readdirSync, statSync, createReadStream } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { createInterface } from "node:readline";

const CODEX = join(homedir(), ".codex");

export interface CodexTokenUsage {
  input_tokens: number;
  cached_input_tokens: number;
  output_tokens: number;
  reasoning_output_tokens: number;
  total_tokens: number;
}

/** Uma janela de rate limit. `resets_at` é unix epoch em SEGUNDOS. */
export interface RateWindow {
  used_percent: number;
  window_minutes: number; // 300 = 5h (primary) | 10080 = 7d (secondary)
  resets_at: number;
}

export interface CodexEvent {
  timestamp: string;
  file: string;
  totalUsage?: CodexTokenUsage; // ACUMULADO da sessão até aqui
  lastUsage?: CodexTokenUsage; // só do último turno
  primary?: RateWindow; // 5h
  secondary?: RateWindow; // 7d
  planType?: string;
  contextWindow?: number;
}

function walk(dir: string, out: string[] = []): string[] {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith(".jsonl") && e.name.startsWith("rollout-"))
      out.push(p);
  }
  return out;
}

export function listRollouts(root = CODEX): string[] {
  const out: string[] = [];
  for (const sub of ["sessions", "archived_sessions"]) {
    const d = join(root, sub);
    try {
      if (statSync(d).isDirectory()) walk(d, out);
    } catch {
      /* dir pode não existir */
    }
  }
  return out;
}

/** Extrai um evento token_count. Retorna null pra qualquer outra linha. */
export function parseTokenCountLine(
  line: string,
  file: string,
): CodexEvent | null {
  if (!line.includes('"token_count"')) return null; // fast path
  let o: any;
  try {
    o = JSON.parse(line);
  } catch {
    return null;
  }
  const p = o.payload;
  if (o.type !== "event_msg" || p?.type !== "token_count") return null;

  const rl = p.rate_limits;
  const info = p.info;
  const win = (w: any): RateWindow | undefined =>
    w && typeof w === "object"
      ? {
          used_percent: w.used_percent ?? 0,
          window_minutes: w.window_minutes ?? 0,
          resets_at: w.resets_at ?? 0,
        }
      : undefined;

  return {
    timestamp: o.timestamp,
    file,
    totalUsage: info?.total_token_usage,
    lastUsage: info?.last_token_usage,
    contextWindow: info?.model_context_window,
    primary: win(rl?.primary),
    secondary: win(rl?.secondary),
    planType: rl?.plan_type,
  };
}

async function* readLines(file: string) {
  const rl = createInterface({
    input: createReadStream(file, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });
  for await (const l of rl) if (l.length > 2) yield l;
}

async function main() {
  const files = listRollouts();
  process.stderr.write(`scan-codex: ${files.length} rollouts\n`);

  // ARMADILHA A: guardar só o ÚLTIMO evento de cada sessão (arquivo)
  const lastPerSession = new Map<string, CodexEvent>();
  // ARMADILHA B: o evento de maior timestamp GLOBAL, com rate_limits
  let newestWithLimits: CodexEvent | null = null;

  // blocos de 5h observados: resets_at -> sessões distintas que o reportaram
  const blocks = new Map<number, Set<string>>();
  let events = 0;

  for (const file of files) {
    for await (const line of readLines(file)) {
      const e = parseTokenCountLine(line, file);
      if (!e) continue;
      events++;

      const prev = lastPerSession.get(file);
      if (!prev || (e.timestamp ?? "") >= (prev.timestamp ?? ""))
        lastPerSession.set(file, e);

      if (e.primary) {
        if (
          !newestWithLimits ||
          (e.timestamp ?? "") > (newestWithLimits.timestamp ?? "")
        )
          newestWithLimits = e;
        if (e.primary.resets_at) {
          let s = blocks.get(e.primary.resets_at);
          if (!s) blocks.set(e.primary.resets_at, (s = new Set()));
          s.add(file);
        }
      }
    }
  }

  // Soma correta: último acumulado de cada sessão.
  const sum: CodexTokenUsage = {
    input_tokens: 0,
    cached_input_tokens: 0,
    output_tokens: 0,
    reasoning_output_tokens: 0,
    total_tokens: 0,
  };
  // Soma ERRADA (todo evento) — só pra medir o tamanho da armadilha.
  let naiveTotal = 0;
  for (const file of files) {
    const e = lastPerSession.get(file);
    if (!e?.totalUsage) continue;
    for (const k of Object.keys(sum) as (keyof CodexTokenUsage)[])
      sum[k] += e.totalUsage[k] ?? 0;
  }
  for (const file of files) {
    for await (const line of readLines(file)) {
      const e = parseTokenCountLine(line, file);
      if (e?.totalUsage) naiveTotal += e.totalUsage.total_tokens ?? 0;
    }
  }

  const sharedBlocks = [...blocks.values()].filter((s) => s.size > 1).length;

  const out = {
    rollouts: files.length,
    tokenCountEvents: events,
    sessionsWithUsage: [...lastPerSession.values()].filter((e) => e.totalUsage)
      .length,

    // O NÚMERO CERTO: último acumulado de cada sessão, somado.
    totalTokensCorrect: sum,
    // O NÚMERO ERRADO: somar todo token_count (conta o acumulado N vezes).
    totalTokensNaive: naiveTotal,
    naiveOverCorrectRatio: sum.total_tokens
      ? naiveTotal / sum.total_tokens
      : 0,

    // O "AGORA": snapshot mais recente por timestamp GLOBAL, não por arquivo.
    currentRateLimits: newestWithLimits
      ? {
          asOf: newestWithLimits.timestamp,
          planType: newestWithLimits.planType,
          fiveHour: newestWithLimits.primary,
          sevenDay: newestWithLimits.secondary,
        }
      : null,

    // Prova de que a janela de 5h é por CONTA, não por sessão.
    fiveHourBlocksObserved: blocks.size,
    blocksSharedByMultipleSessions: sharedBlocks,
  };

  process.stdout.write(
    JSON.stringify(out, null, process.argv.includes("--pretty") ? 2 : 0) + "\n",
  );
}

if (import.meta.main) await main();
