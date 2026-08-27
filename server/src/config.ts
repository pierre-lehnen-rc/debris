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
  /**
   * True when this process was launched by the app (which sets DEBRIS_MANAGED).
   * A managed server stops itself once the last connected app disconnects; a
   * server the developer started by hand stays up regardless.
   */
  managed: boolean;
  /**
   * How long (ms) without a heartbeat before a connected app is presumed gone.
   * Apps heartbeat every 30s, so a minute tolerates one missed beat.
   */
  appTimeoutMs: number;
  /** How often (ms) the app registry sweeps for timed-out apps. */
  appSweepIntervalMs: number;
}

function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === "") return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function loadConfig(): Config {
  return {
    port: intFromEnv("PORT", 4020),
    host: process.env.HOST ?? "127.0.0.1",
    clientIdleTtlMs: intFromEnv("MONGO_CLIENT_IDLE_TTL_MS", 5 * 60_000),
    clientSweepIntervalMs: intFromEnv("MONGO_CLIENT_SWEEP_INTERVAL_MS", 60_000),
    serverSelectionTimeoutMs: intFromEnv("MONGO_SERVER_SELECTION_TIMEOUT_MS", 10_000),
    logLevel: process.env.LOG_LEVEL ?? "info",
    managed: process.env.DEBRIS_MANAGED === "1",
    appTimeoutMs: intFromEnv("DEBRIS_CLIENT_TIMEOUT_MS", 60_000),
    appSweepIntervalMs: intFromEnv("DEBRIS_CLIENT_SWEEP_INTERVAL_MS", 15_000),
  };
}
