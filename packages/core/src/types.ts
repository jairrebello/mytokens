/**
 * Contrato de dados MyTokens — fronteira entre core e UI.
 * Fonte da verdade: nota "contrato-dados" no canvas Maestri.
 * STATUS: v0 RASCUNHO. Mudou aqui? Avise Vitral e o Maestro antes de codar.
 */

export type Provider = 'claude-code' | 'codex' | 'cursor';

/** Unidade mínima: um turno de LLM já normalizado. */
export type UsageEvent = {
  provider: Provider;
  ts: string; // ISO
  sessionId: string;
  model: string;
  project?: string; // cwd/slug quando existir
  tokens: {
    input: number;
    output: number;
    cacheWrite: number;
    cacheRead: number;
    reasoning?: number;
  };
  costUsd: number; // calculado no core. NUNCA na UI.
  sourceId: string; // requestId (claude) | rolloutFile+idx (codex) — CHAVE DE DEDUP
};

export type Spend = {
  tokens: number;
  costUsd: number;
  byModel: Record<string, number>;
};

export type LimitWindow = {
  label: string; // "5 horas" | "Semana"
  usedPercent: number; // 0..100
  resetsAt: string; // ISO
  /**
   * 'measured' = o provedor DEU o número (Codex faz isso).
   * 'derived'  = nós CALCULAMOS (Claude).
   * A UI é obrigada a distinguir os dois visualmente.
   */
  source: 'measured' | 'derived';
};

/** O que a UI realmente pinta. */
export type ProviderStatus = {
  provider: Provider;
  connected: boolean;
  windows: LimitWindow[]; // vazio = não sabemos (caso do Claude hoje). UI mostra estado honesto, não zero.
  spend: { today: Spend; week: Spend; month: Spend };
  lastEventAt: string | null;
};
