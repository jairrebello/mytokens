#!/usr/bin/env bun
/**
 * scan-claude.ts — parser de referência para ~/.claude/projects/<slug>/<sessionId>.jsonl
 *
 * Prova, com número, o efeito do dedup por requestId, e levanta o schema real
 * (campos, tipos, variação entre versões do CLI).
 *
 * Uso:
 *   bun scripts/probe/scan-claude.ts            # JSON no stdout
 *   bun scripts/probe/scan-claude.ts --pretty
 *
 * Saída: JSON único no stdout. Diagnóstico vai pro stderr.
 */

import { readdirSync, statSync, createReadStream } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { createInterface } from "node:readline";

const ROOT = join(homedir(), ".claude", "projects");

/** Os 4 buckets de token. NUNCA somar num só: têm preços diferentes. */
export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens: number;
  cache_read_input_tokens: number;
}

export interface AssistantRow {
  requestId?: string;
  messageId?: string;
  sessionId: string;
  timestamp: string;
  model: string;
  version: string;
  usage: Usage;
  isSidechain: boolean;
  file: string;
}

const ZERO = (): Usage => ({
  input_tokens: 0,
  output_tokens: 0,
  cache_creation_input_tokens: 0,
  cache_read_input_tokens: 0,
});

const add = (a: Usage, b: Usage): Usage => ({
  input_tokens: a.input_tokens + b.input_tokens,
  output_tokens: a.output_tokens + b.output_tokens,
  cache_creation_input_tokens:
    a.cache_creation_input_tokens + b.cache_creation_input_tokens,
  cache_read_input_tokens: a.cache_read_input_tokens + b.cache_read_input_tokens,
});

const total = (u: Usage) =>
  u.input_tokens +
  u.output_tokens +
  u.cache_creation_input_tokens +
  u.cache_read_input_tokens;

/**
 * Lista todo *.jsonl sob ~/.claude/projects/ RECURSIVAMENTE.
 *
 * ATENÇÃO: recursão não é luxo, é obrigatória. O transcript de subagente (Task)
 * vive em <slug>/<parentSessionId>/subagents/<id>.jsonl — um nível ABAIXO da
 * sessão. Varrer só <slug>/*.jsonl perde 686 arquivos de gasto REAL nesta
 * máquina. E não adianta filtrar por isSidechain: esse campo é `false` em
 * 100% das linhas do histórico atual (é legado). Ver docs/FONTES.md.
 */
export function listSessionFiles(root = ROOT): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith(".jsonl")) out.push(p);
    }
  };
  walk(root);
  return out;
}

/** true se o arquivo é transcript de subagente (Task). Gasto real: SOMAR. */
export const isSubagentFile = (f: string) => f.includes("/subagents/");

/**
 * Lê o usage de UMA linha assistant.
 *
 * ARMADILHA: quando `usage.iterations` tem 2+ entradas (uma request que o servidor
 * executou em várias passadas), o `usage` de TOPO é igual à ÚLTIMA iteração — NÃO à
 * soma. Confiar no topo SUBCONTA o gasto. Provado: uma linha com iterations=[2] diz
 * cache_read=105.029 no topo, mas a soma das iterações é 203.371.
 * Regra: se iterations.length > 1, SOME as iterações. Senão, use o topo.
 * (Raro hoje — 4 em 18.821 linhas amostradas — mas é gasto real e é barato acertar.)
 */
export function readUsage(u: any): Usage {
  const pick = (x: any): Usage => ({
    input_tokens: x?.input_tokens ?? 0,
    output_tokens: x?.output_tokens ?? 0,
    cache_creation_input_tokens: x?.cache_creation_input_tokens ?? 0,
    cache_read_input_tokens: x?.cache_read_input_tokens ?? 0,
  });
  const it = u?.iterations;
  if (Array.isArray(it) && it.length > 1)
    return it.map(pick).reduce(add, ZERO());
  return pick(u);
}

/**
 * Extrai a linha assistant. Retorna null se a linha não for gasto de token.
 * Regra: só type=="assistant" com message.usage. Todo outro type é ruído.
 */
export function parseAssistantLine(
  line: string,
  file: string,
): AssistantRow | null {
  if (!line.includes('"type":"assistant"')) return null; // fast path
  let o: any;
  try {
    o = JSON.parse(line);
  } catch {
    return null;
  }
  if (o.type !== "assistant") return null;
  const u = o.message?.usage;
  if (!u) return null;
  return {
    requestId: o.requestId,
    messageId: o.message?.id,
    sessionId: o.sessionId,
    timestamp: o.timestamp,
    model: o.message?.model ?? "unknown",
    version: o.version ?? "unknown",
    isSidechain: !!o.isSidechain,
    file,
    usage: readUsage(u),
  };
}

async function* readLines(file: string) {
  const rl = createInterface({
    input: createReadStream(file, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });
  for await (const line of rl) if (line.length > 2) yield line;
}

async function main() {
  const files = listSessionFiles();
  process.stderr.write(`scan-claude: ${files.length} arquivos\n`);

  // acumuladores
  const raw = ZERO(); // soma burra: toda linha assistant
  const dedupReq = ZERO(); // dedup por requestId
  const dedupMsg = ZERO(); // dedup por message.id
  const dedupReqMsg = ZERO(); // dedup por requestId + message.id
  const noReqId = ZERO(); // linhas assistant SEM requestId
  const sidechain = ZERO(); // subagentes (isSidechain)

  let rowCount = 0;
  let noReqIdCount = 0;
  let noMsgIdCount = 0;
  let sidechainCount = 0;

  const seenReq = new Set<string>();
  const seenMsg = new Set<string>();
  const seenReqMsg = new Set<string>();

  // requestId -> quantos arquivos distintos o contêm (prova do resume/branch)
  const reqFiles = new Map<string, Set<string>>();

  const byVersion = new Map<string, number>();
  const byModelDedup = new Map<string, Usage>();
  const byModelRaw = new Map<string, Usage>();
  // por dia (UTC) — dedup E raw, pra poder recortar a MESMA janela do stats-cache
  const byDayDedup = new Map<string, Map<string, Usage>>();
  const byDayRaw = new Map<string, Map<string, Usage>>();

  const bump = (
    m: Map<string, Map<string, Usage>>,
    day: string,
    model: string,
    u: Usage,
  ) => {
    let dm = m.get(day);
    if (!dm) m.set(day, (dm = new Map()));
    dm.set(model, add(dm.get(model) ?? ZERO(), u));
  };

  let fi = 0;
  for (const file of files) {
    if (++fi % 500 === 0)
      process.stderr.write(`  ...${fi}/${files.length}\n`);
    try {
      for await (const line of readLines(file)) {
        const r = parseAssistantLine(line, file);
        if (!r) continue;
        rowCount++;

        const day = r.timestamp?.slice(0, 10) ?? "unknown";

        Object.assign(raw, add(raw, r.usage));
        byModelRaw.set(r.model, add(byModelRaw.get(r.model) ?? ZERO(), r.usage));
        bump(byDayRaw, day, r.model, r.usage);
        byVersion.set(r.version, (byVersion.get(r.version) ?? 0) + 1);
        if (r.isSidechain) {
          sidechainCount++;
          Object.assign(sidechain, add(sidechain, r.usage));
        }

        if (!r.requestId) {
          noReqIdCount++;
          Object.assign(noReqId, add(noReqId, r.usage));
        }
        if (!r.messageId) noMsgIdCount++;

        if (r.requestId) {
          let s = reqFiles.get(r.requestId);
          if (!s) reqFiles.set(r.requestId, (s = new Set()));
          s.add(r.file);
        }

        // --- dedup por requestId ---
        // linha sem requestId NÃO pode ser descartada: é gasto real (ver FONTES.md).
        // Fallback: chave = message.id; se nem isso, chave sintética única.
        const kReq =
          r.requestId ?? (r.messageId ? `msg:${r.messageId}` : `row:${rowCount}`);
        if (!seenReq.has(kReq)) {
          seenReq.add(kReq);
          Object.assign(dedupReq, add(dedupReq, r.usage));

          byModelDedup.set(
            r.model,
            add(byModelDedup.get(r.model) ?? ZERO(), r.usage),
          );
          bump(byDayDedup, day, r.model, r.usage);
        }

        // --- dedup por message.id ---
        const kMsg =
          r.messageId ?? (r.requestId ? `req:${r.requestId}` : `row:${rowCount}`);
        if (!seenMsg.has(kMsg)) {
          seenMsg.add(kMsg);
          Object.assign(dedupMsg, add(dedupMsg, r.usage));
        }

        // --- dedup por par ---
        const kBoth = `${r.requestId ?? "-"}|${r.messageId ?? "-"}`;
        if (!seenReqMsg.has(kBoth)) {
          seenReqMsg.add(kBoth);
          Object.assign(dedupReqMsg, add(dedupReqMsg, r.usage));
        }
      }
    } catch (e) {
      process.stderr.write(`  ERRO ${file}: ${e}\n`);
    }
  }

  // Quantos requestIds aparecem em mais de um arquivo? Isso É o resume/branch.
  let reqInMultipleFiles = 0;
  for (const s of reqFiles.values()) if (s.size > 1) reqInMultipleFiles++;

  const rawT = total(raw);
  const dedupT = total(dedupReq);

  const out = {
    files: files.length,
    assistantRows: rawT > 0 ? rowCount : 0,
    uniqueRequestIds: seenReq.size,
    uniqueMessageIds: seenMsg.size,
    uniqueRequestIdPlusMessageId: seenReqMsg.size,
    rowsWithoutRequestId: noReqIdCount,
    rowsWithoutMessageId: noMsgIdCount,
    requestIdsAppearingInMultipleFiles: reqInMultipleFiles,
    sidechainRows: sidechainCount,

    totals: {
      raw,
      dedupByRequestId: dedupReq,
      dedupByMessageId: dedupMsg,
      dedupByRequestIdAndMessageId: dedupReqMsg,
      usageOfRowsWithoutRequestId: noReqId,
      usageOfSidechainRows: sidechain,
    },

    inflation: {
      rawTotalTokens: rawT,
      dedupTotalTokens: dedupT,
      duplicatedTokens: rawT - dedupT,
      inflationPercent: dedupT ? ((rawT - dedupT) / dedupT) * 100 : 0,
      rawOverDedupRatio: dedupT ? rawT / dedupT : 0,
    },

    byVersion: Object.fromEntries(
      [...byVersion.entries()].sort((a, b) => b[1] - a[1]),
    ),
    byModelDedup: Object.fromEntries(byModelDedup),
    byModelRaw: Object.fromEntries(byModelRaw),
    byDayDedup: Object.fromEntries(
      [...byDayDedup.entries()]
        .sort()
        .map(([d, m]) => [d, Object.fromEntries(m)]),
    ),
    byDayRaw: Object.fromEntries(
      [...byDayRaw.entries()].sort().map(([d, m]) => [d, Object.fromEntries(m)]),
    ),
  };

  const pretty = process.argv.includes("--pretty");
  process.stdout.write(JSON.stringify(out, null, pretty ? 2 : 0) + "\n");
}

if (import.meta.main) await main();
