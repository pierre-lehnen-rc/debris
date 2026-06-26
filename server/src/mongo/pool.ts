import { MongoClient } from "mongodb";
import {
  buildClientOptions,
  connectionKey,
  resolveUri,
  type ConnectionSpec,
} from "./connection.js";

interface CacheEntry {
  client: MongoClient;
  lastUsed: number;
}

export interface ClientCacheOptions {
  idleTtlMs: number;
  sweepIntervalMs: number;
  serverSelectionTimeoutMs: number;
}

/**
 * Caches connected {@link MongoClient} instances keyed by connection identity so
 * repeated requests reuse the same connection pool. Idle clients are closed and
 * evicted after `idleTtlMs`. Because connections are established lazily and the
 * same key may be requested concurrently, in-flight connects are de-duplicated.
 */
export class ClientCache {
  private readonly entries = new Map<string, CacheEntry>();
  private readonly pending = new Map<string, Promise<MongoClient>>();
  private readonly sweepTimer: NodeJS.Timeout;

  constructor(private readonly options: ClientCacheOptions) {
    this.sweepTimer = setInterval(() => {
      void this.sweep();
    }, options.sweepIntervalMs);
    // Don't keep the process alive solely for the sweep timer.
    this.sweepTimer.unref();
  }

  /** Get a connected client for the given connection spec, creating one if needed. */
  async acquire(spec: ConnectionSpec): Promise<MongoClient> {
    const key = connectionKey(spec);

    const existing = this.entries.get(key);
    if (existing) {
      existing.lastUsed = Date.now();
      return existing.client;
    }

    const inFlight = this.pending.get(key);
    if (inFlight) return inFlight;

    const connectPromise = this.connect(spec)
      .then((client) => {
        this.entries.set(key, { client, lastUsed: Date.now() });
        this.pending.delete(key);
        return client;
      })
      .catch((err: unknown) => {
        this.pending.delete(key);
        throw err;
      });

    this.pending.set(key, connectPromise);
    return connectPromise;
  }

  private async connect(spec: ConnectionSpec): Promise<MongoClient> {
    const uri = resolveUri(spec);
    const client = new MongoClient(uri, buildClientOptions(this.options.serverSelectionTimeoutMs));
    await client.connect();
    return client;
  }

  /** Close clients idle longer than the configured TTL. */
  private async sweep(): Promise<void> {
    const now = Date.now();
    const expired: string[] = [];
    for (const [key, entry] of this.entries) {
      if (now - entry.lastUsed > this.options.idleTtlMs) expired.push(key);
    }
    for (const key of expired) {
      const entry = this.entries.get(key);
      this.entries.delete(key);
      if (entry) await entry.client.close().catch(() => undefined);
    }
  }

  /** Close every cached client and stop the sweep timer. Call on shutdown. */
  async closeAll(): Promise<void> {
    clearInterval(this.sweepTimer);
    const clients = [...this.entries.values()].map((e) => e.client);
    this.entries.clear();
    await Promise.all(clients.map((c) => c.close().catch(() => undefined)));
  }

  /** Number of currently cached clients (useful for diagnostics/tests). */
  get size(): number {
    return this.entries.size;
  }
}
