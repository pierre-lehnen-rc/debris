import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import { AppRegistry } from "./apps.js";
import type { Config } from "./config.js";
import { describeError } from "./errors.js";
import { ClientCache } from "./mongo/pool.js";
import { RcBridgeRegistry } from "./rocketchat/bridge.js";
import { registerRocketChatRoutes } from "./rocketchat/routes.js";
import { registerRoutes } from "./routes.js";

export interface AppContext {
  app: FastifyInstance;
  cache: ClientCache;
  apps: AppRegistry;
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

  const apps = new AppRegistry({
    timeoutMs: config.appTimeoutMs,
    sweepIntervalMs: config.appSweepIntervalMs,
  });

  const rcBridges = new RcBridgeRegistry({
    meteorBin: config.rocketchatMeteorBin,
    shellTimeoutMs: config.rocketchatShellTimeoutMs,
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

  app.get("/health", async () => ({
    status: "ok",
    clients: cache.size,
    apps: apps.size,
  }));

  // Connection tracking for the app instances using this server. These are the
  // app's own control-plane calls (not MongoDB proxying), so they live outside
  // the /api prefix. Both carry a clientId the app generates for its lifetime.
  const clientBody = {
    type: "object",
    required: ["clientId"],
    additionalProperties: true,
    properties: { clientId: { type: "string", minLength: 1 } },
  } as const;

  app.post<{ Body: { clientId: string } }>(
    "/clients/heartbeat",
    { schema: { body: clientBody } },
    async (req) => {
      apps.heartbeat(req.body.clientId);
      return { ok: true, apps: apps.size };
    },
  );

  app.post<{ Body: { clientId: string } }>(
    "/clients/disconnect",
    { schema: { body: clientBody } },
    async (req) => {
      apps.disconnect(req.body.clientId);
      return { ok: true, apps: apps.size };
    },
  );

  await app.register(registerRoutes, { cache, prefix: "/api" });
  await app.register(registerRocketChatRoutes, { registry: rcBridges, prefix: "/api" });

  return { app, cache, apps };
}
