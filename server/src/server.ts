import Fastify, { type FastifyError, type FastifyInstance } from "fastify";
import { AppRegistry } from "./apps.js";
import type { Config } from "./config.js";
import { describeError } from "./errors.js";
import { ClientCache } from "./mongo/pool.js";
import { RcBridgeRegistry } from "./rocketchat/bridge.js";
import { registerRocketChatRoutes } from "./rocketchat/routes.js";
import { ModelTypings } from "./rocketchat/typings.js";
import { registerRoutes } from "./routes.js";

export interface AppContext {
  app: FastifyInstance;
  cache: ClientCache;
  apps: AppRegistry;
  /**
   * Invoked when a client asks the server to shut down (POST /server/stop). The
   * owner of the process wires this to its graceful-shutdown routine; while it is
   * null the route reports that this server can't be stopped remotely.
   */
  onStop: ((reason: string) => void) | null;
}

/**
 * Build the Fastify application: a stateless proxy that runs MongoDB operations
 * using connection details supplied by the client on each request. The returned
 * {@link ClientCache} must be closed on shutdown.
 */
export async function buildApp(config: Config): Promise<AppContext> {
  const app = Fastify({ logger: { level: config.logLevel } });
  const startedAt = Date.now();

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
  const rcTypings = new ModelTypings();

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

  const context: AppContext = { app, cache, apps, onStop: null };

  // Read-only view of the server for the app's server panel: what this process
  // is, who is attached, and whether it stops itself when they leave. Deliberately
  // a GET with no side effects — an app can poll it to show the server's state
  // without registering itself as connected. Passing the app's own clientId (which
  // the registry only ever reads here) reports whether that app is still attached,
  // so a heartbeat lost to a restart or a timeout shows up as disconnected.
  app.get<{ Querystring: { clientId?: string } }>(
    "/server/state",
    {
      schema: {
        querystring: {
          type: "object",
          additionalProperties: false,
          properties: { clientId: { type: "string" } },
        },
      },
    },
    async (req) => ({
      status: "ok",
      pid: process.pid,
      uptimeMs: Date.now() - startedAt,
      managed: apps.stopsWhenEmpty,
      apps: apps.size,
      connections: cache.size,
      connected: req.query.clientId ? apps.has(req.query.clientId) : false,
      stoppable: context.onStop !== null,
    }),
  );

  // Shut the server down on request (the app's "Stop server" action). Answering
  // before shutting down matters: the reply travels on a socket this very call is
  // about to close, so it is sent first and the shutdown runs once it has landed.
  app.post("/server/stop", async (_req, reply) => {
    const stop = context.onStop;
    if (stop === null) {
      reply.code(501);
      return {
        error: {
          message: "This server cannot be stopped remotely",
          name: "NotSupportedError",
        },
      };
    }
    reply.raw.on("finish", () => stop("stop-requested"));
    return { ok: true, stopping: true };
  });

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

  // Reached both when the app closes and when the user disconnects from its
  // server panel — the server can't tell them apart and shouldn't: either way an
  // app is gone, and a managed server left with none stops itself.
  app.post<{ Body: { clientId: string } }>(
    "/clients/disconnect",
    { schema: { body: clientBody } },
    async (req) => {
      apps.disconnect(req.body.clientId);
      return { ok: true, apps: apps.size, managed: apps.stopsWhenEmpty };
    },
  );

  await app.register(registerRoutes, { cache, prefix: "/api" });
  await app.register(registerRocketChatRoutes, {
    registry: rcBridges,
    typings: rcTypings,
    prefix: "/api",
  });

  return context;
}
