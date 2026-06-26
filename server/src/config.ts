/** Runtime configuration, sourced from environment variables with sane defaults. */
export interface Config {
  /** Port the HTTP server listens on. */
  port: number;
  /** Host/interface the HTTP server binds to. */
  host: string;
  /** Idle time (ms) after which a cached MongoClient is closed and evicted. */
  clientIdleTtlMs: number;
  /** How often (ms) the cache sweeps for idle clients. */
  clientSweepIntervalMs: number;
  /** Default server selection / connection timeout (ms) applied to MongoClients. */
  serverSelectionTimeoutMs: number;
  /** Fastify log level. */
  logLevel: string;
}

function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === "") return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function loadConfig(): Config {
  return {
    port: intFromEnv("PORT", 4000),
    host: process.env.HOST ?? "127.0.0.1",
    clientIdleTtlMs: intFromEnv("MONGO_CLIENT_IDLE_TTL_MS", 5 * 60_000),
    clientSweepIntervalMs: intFromEnv("MONGO_CLIENT_SWEEP_INTERVAL_MS", 60_000),
    serverSelectionTimeoutMs: intFromEnv("MONGO_SERVER_SELECTION_TIMEOUT_MS", 10_000),
    logLevel: process.env.LOG_LEVEL ?? "info",
  };
}
