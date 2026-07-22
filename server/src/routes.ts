import type { FastifyInstance, FastifyPluginAsync } from "fastify";
import type { ConnectionSpec } from "./mongo/connection.js";
import type { ClientCache } from "./mongo/pool.js";
import * as ops from "./mongo/operations.js";

export interface RoutesOptions {
  cache: ClientCache;
}

/** Every request body carries the connection details plus operation params. */
interface WithConnection {
  connection: ConnectionSpec;
}

// --- JSON schema fragments for request validation -------------------------

const connectionSchema = {
  type: "object",
  additionalProperties: true,
} as const;

/** Build a body schema requiring `connection` plus the given extra properties. */
function bodySchema(
  properties: Record<string, unknown> = {},
  required: string[] = [],
): Record<string, unknown> {
  return {
    type: "object",
    required: ["connection", ...required],
    additionalProperties: true,
    properties: {
      connection: connectionSchema,
      ...properties,
    },
  };
}

const stringField = { type: "string", minLength: 1 } as const;

// --- Route registration ---------------------------------------------------

export const registerRoutes: FastifyPluginAsync<RoutesOptions> = async (
  app: FastifyInstance,
  { cache },
) => {
  // Connectivity check.
  app.post<{ Body: WithConnection }>(
    "/ping",
    { schema: { body: bodySchema() } },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.ping(client);
    },
  );

  // List all databases on the server.
  app.post<{ Body: WithConnection }>(
    "/databases",
    { schema: { body: bodySchema() } },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.listDatabases(client);
    },
  );

  // List collections within a database.
  app.post<{ Body: WithConnection & { database: string } }>(
    "/collections",
    { schema: { body: bodySchema({ database: stringField }, ["database"]) } },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.listCollections(client, req.body.database);
    },
  );

  // Find documents.
  app.post<{ Body: WithConnection & ops.FindParams }>(
    "/find",
    {
      schema: {
        body: bodySchema(
          { database: stringField, collection: stringField },
          ["database", "collection"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.find(client, req.body);
    },
  );

  // Find a single document.
  app.post<{ Body: WithConnection & ops.FindParams }>(
    "/findOne",
    {
      schema: {
        body: bodySchema(
          { database: stringField, collection: stringField },
          ["database", "collection"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.findOne(client, req.body);
    },
  );

  // Count documents matching a filter.
  app.post<{ Body: WithConnection & ops.CountParams }>(
    "/count",
    {
      schema: {
        body: bodySchema(
          { database: stringField, collection: stringField },
          ["database", "collection"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.count(client, req.body);
    },
  );

  // Explain a query's execution plan.
  app.post<{ Body: WithConnection & ops.FindParams }>(
    "/explain",
    {
      schema: {
        body: bodySchema(
          { database: stringField, collection: stringField },
          ["database", "collection"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.explain(client, req.body);
    },
  );

  // List a collection's indexes.
  app.post<{ Body: WithConnection & ops.CollectionTarget }>(
    "/listIndexes",
    {
      schema: {
        body: bodySchema(
          { database: stringField, collection: stringField },
          ["database", "collection"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.listIndexes(client, req.body);
    },
  );

  // Run an aggregation pipeline.
  app.post<{ Body: WithConnection & ops.AggregateParams }>(
    "/aggregate",
    {
      schema: {
        body: bodySchema(
          { database: stringField, collection: stringField },
          ["database", "collection"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.aggregate(client, req.body);
    },
  );

  // Insert one or more documents.
  app.post<{ Body: WithConnection & ops.InsertParams }>(
    "/insert",
    {
      schema: {
        body: bodySchema(
          {
            database: stringField,
            collection: stringField,
            documents: { type: "array", items: { type: "object" }, minItems: 1 },
          },
          ["database", "collection", "documents"],
        ),
      },
    },
    async (req, reply) => {
      const client = await cache.acquire(req.body.connection);
      reply.code(201);
      return ops.insert(client, req.body);
    },
  );

  // Update one or many documents.
  app.post<{ Body: WithConnection & ops.UpdateParams }>(
    "/update",
    {
      schema: {
        body: bodySchema(
          {
            database: stringField,
            collection: stringField,
            filter: { type: "object" },
            update: { type: "object" },
          },
          ["database", "collection", "filter", "update"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.update(client, req.body);
    },
  );

  // Delete one or many documents.
  app.post<{ Body: WithConnection & ops.DeleteParams }>(
    "/delete",
    {
      schema: {
        body: bodySchema(
          {
            database: stringField,
            collection: stringField,
            filter: { type: "object" },
          },
          ["database", "collection", "filter"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.remove(client, req.body);
    },
  );

  // Generic escape hatch: run any database command.
  app.post<{ Body: WithConnection & ops.CommandParams }>(
    "/command",
    {
      schema: {
        body: bodySchema(
          { database: stringField, command: { type: "object" } },
          ["database", "command"],
        ),
      },
    },
    async (req) => {
      const client = await cache.acquire(req.body.connection);
      return ops.runCommand(client, req.body);
    },
  );
};
