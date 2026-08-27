import type { FastifyPluginAsync } from "fastify";
import type { RcBridgeRegistry, RcTarget } from "./bridge.js";

export interface RcRoutesOptions {
  registry: RcBridgeRegistry;
}

/** JSON schema for the `target` object every request carries. */
const targetSchema = {
  type: "object",
  required: ["meteorDir"],
  additionalProperties: true,
  properties: {
    meteorDir: { type: "string", minLength: 1 },
    url: { type: "string" },
  },
} as const;

function withTarget(extra: Record<string, unknown> = {}, required: string[] = []): Record<string, unknown> {
  return {
    type: "object",
    required: ["target", ...required],
    additionalProperties: true,
    properties: { target: targetSchema, ...extra },
  };
}

const stringField = { type: "string", minLength: 1 } as const;

/**
 * Routes for calling Rocket.Chat model methods through an in-process bridge the
 * server installs into a running RC dev instance. Mounted under `/api`, so the
 * paths are `/api/rocketchat/*`. Every request names its `target` (the RC
 * checkout + URL); the server keeps one bridge per target.
 */
export const registerRocketChatRoutes: FastifyPluginAsync<RcRoutesOptions> = async (
  app,
  { registry },
) => {
  // Force a (re)install of the bridge handler into the running RC server.
  app.post<{ Body: { target: RcTarget } }>(
    "/rocketchat/install",
    { schema: { body: withTarget() } },
    async (req) => {
      const bridge = registry.acquire(req.body.target);
      await bridge.ensureInstalled(true);
      return { ok: true, installed: bridge.isInstalled, url: bridge.url };
    },
  );

  // Report whether this server has installed the bridge for a target yet.
  app.post<{ Body: { target: RcTarget } }>(
    "/rocketchat/status",
    { schema: { body: withTarget() } },
    async (req) => {
      const bridge = registry.acquire(req.body.target);
      return { ok: true, installed: bridge.isInstalled, url: bridge.url };
    },
  );

  // Run a model method: `{ target, model, method, args }`. `args` is the JSON
  // array the user supplies, spread into the call. The result comes back as
  // canonical Extended JSON, matching the MongoDB routes' response dialect.
  app.post<{
    Body: { target: RcTarget; model: string; method: string; args?: unknown[] };
  }>(
    "/rocketchat/call",
    {
      schema: {
        body: withTarget(
          { model: stringField, method: stringField, args: { type: "array" } },
          ["model", "method"],
        ),
      },
    },
    async (req) => {
      const { target, model, method, args } = req.body;
      const bridge = registry.acquire(target);
      const result = await bridge.call(model, method, args ?? []);
      return { result };
    },
  );
};
