import { describe, expect, it } from 'vitest';
import type { UsageEvent } from './types.js';

describe('contrato-dados stub', () => {
  it('aceita um UsageEvent bem formado', () => {
    const event: UsageEvent = {
      provider: 'claude-code',
      ts: new Date().toISOString(),
      sessionId: 'sess-1',
      model: 'claude-sonnet-5',
      tokens: { input: 100, output: 50, cacheWrite: 0, cacheRead: 0 },
      costUsd: 0.01,
      sourceId: 'req-1',
    };

    expect(event.provider).toBe('claude-code');
  });
});
