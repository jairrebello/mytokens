export type { Provider, UsageEvent, Spend, LimitWindow, ProviderStatus } from './types.js';

/**
 * Contrato de um módulo de provider. Novo provider = novo módulo que
 * implementa isto. Nada além disso — ver nota "contrato-dados".
 */
export type ProviderModule = {
  provider: import('./types.js').Provider;
  readEvents(): Promise<import('./types.js').UsageEvent[]>;
  getStatus(): Promise<import('./types.js').ProviderStatus>;
};
