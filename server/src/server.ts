import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import type { Config } from "./config.js";
import { describeError } from "./errors.js";
import { ClientCache } from "./mongo/pool.js";
import { registerRoutes } from "./routes.js";

export interface AppContext {
  app: FastifyInstance;
  cache: ClientCache;
}

/**
 * Build the Fastify application: a stateless proxy that runs MongoDB operations
 * using connection details supplied by the client on each request. The returned
 * {@link ClientCache} must be closed on shutdown.
 */
export async function buildApp(config: Config): Promise<AppContext> {
  const app = Fastify({ logger: { level: config.logLevel } });

  const cache = new ClientCache({
    idleTtlMs: config.clientIdleTtlMs,
    sweepIntervalMs: config.clientSweepIntervalMs,
    serverSelectionTimeoutMs: config.serverSelectionTimeoutMs,
  });

  // Map driver/validation errors to structured JSON responses.
  app.setErrorHandler((err: FastifyError, req, reply) => {
    // Fastify schema validation errors already carry a statusCode.
    if (err.validation) {
      reply.code(400).send({
        error: { message: err.message, name: "ValidationError" },
      });
      return;
    }
    const { status, payload } = describeError(err);
    if (status >= 500) req.log.error({ err }, "request failed");
    else req.log.warn({ err }, "request rejected");
    reply.code(status).send(payload);
  });

  app.get("/health", async () => ({ status: "ok", clients: cache.size }));

  await app.register(registerRoutes, { cache, prefix: "/api" });

  return { app, cache };
}
