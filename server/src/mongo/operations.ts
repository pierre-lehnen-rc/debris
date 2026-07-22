import type { Document, FindOptions, MongoClient } from "mongodb";
import { fromExtendedJson, toExtendedJson } from "./ejson.js";

/** Parameters shared by collection-scoped operations. */
export interface CollectionTarget {
  database: string;
  collection: string;
}

export interface FindParams extends CollectionTarget {
  filter?: unknown;
  /**
   * Any find options the driver accepts (projection, sort, collation, hint,
   * comment, max/min, …), passed straight through as the driver's options
   * argument. skip/limit are handled separately so the pager stays in control.
   */
  options?: unknown;
  skip?: number;
  limit?: number;
}

export interface CountParams extends CollectionTarget {
  filter?: unknown;
}

export interface AggregateParams extends CollectionTarget {
  pipeline?: unknown[];
}

export interface InsertParams extends CollectionTarget {
  documents: unknown[];
}

export interface UpdateParams extends CollectionTarget {
  filter: unknown;
  update: unknown;
  many?: boolean;
  upsert?: boolean;
}

export interface DeleteParams extends CollectionTarget {
  filter: unknown;
  many?: boolean;
}

export interface CommandParams {
  database: string;
  command: unknown;
}

const DEFAULT_FIND_LIMIT = 50;

export async function ping(client: MongoClient): Promise<unknown> {
  const result = await client.db("admin").command({ ping: 1 });
  return toExtendedJson(result);
}

export async function listDatabases(client: MongoClient): Promise<unknown> {
  const result = await client.db("admin").admin().listDatabases();
  return toExtendedJson(result);
}

export async function listCollections(client: MongoClient, database: string): Promise<unknown> {
  const collections = await client.db(database).listCollections().toArray();
  return toExtendedJson(collections);
}

export async function find(client: MongoClient, params: FindParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const options = fromExtendedJson<FindOptions>(params.options ?? {});
  const cursor = coll.find(fromExtendedJson<Document>(params.filter ?? {}), options);

  // The pager owns skip/limit, so apply them last (overriding any in options).
  if (params.skip !== undefined) cursor.skip(params.skip);
  cursor.limit(params.limit ?? DEFAULT_FIND_LIMIT);

  const documents = await cursor.toArray();
  return toExtendedJson(documents);
}

export async function findOne(client: MongoClient, params: FindParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const options = fromExtendedJson<FindOptions>(params.options ?? {});
  const document = await coll.findOne(fromExtendedJson<Document>(params.filter ?? {}), options);
  return toExtendedJson(document);
}

export async function count(client: MongoClient, params: CountParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const total = await coll.countDocuments(fromExtendedJson<Document>(params.filter ?? {}));
  return { count: total };
}

export async function explain(client: MongoClient, params: FindParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const options = fromExtendedJson<FindOptions>(params.options ?? {});
  const cursor = coll.find(fromExtendedJson<Document>(params.filter ?? {}), options);
  const result = await cursor.explain();
  return toExtendedJson(result);
}

export async function listIndexes(client: MongoClient, params: CollectionTarget): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const indexes = await coll.listIndexes().toArray();
  return toExtendedJson(indexes);
}

export async function aggregate(client: MongoClient, params: AggregateParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const pipeline = fromExtendedJson<Document[]>(params.pipeline ?? []);
  const documents = await coll.aggregate(pipeline).toArray();
  return toExtendedJson(documents);
}

export async function insert(client: MongoClient, params: InsertParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const docs = fromExtendedJson<Document[]>(params.documents);
  const result = await coll.insertMany(docs);
  return toExtendedJson({
    acknowledged: result.acknowledged,
    insertedCount: result.insertedCount,
    insertedIds: result.insertedIds,
  });
}

export async function update(client: MongoClient, params: UpdateParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const filter = fromExtendedJson<Document>(params.filter);
  const mod = fromExtendedJson<Document>(params.update);
  const options = { upsert: params.upsert ?? false };

  const result = params.many
    ? await coll.updateMany(filter, mod, options)
    : await coll.updateOne(filter, mod, options);

  return toExtendedJson({
    acknowledged: result.acknowledged,
    matchedCount: result.matchedCount,
    modifiedCount: result.modifiedCount,
    upsertedCount: result.upsertedCount,
    upsertedId: result.upsertedId,
  });
}

export async function remove(client: MongoClient, params: DeleteParams): Promise<unknown> {
  const coll = client.db(params.database).collection(params.collection);
  const filter = fromExtendedJson<Document>(params.filter);
  const result = params.many ? await coll.deleteMany(filter) : await coll.deleteOne(filter);
  return toExtendedJson({
    acknowledged: result.acknowledged,
    deletedCount: result.deletedCount,
  });
}

export async function runCommand(client: MongoClient, params: CommandParams): Promise<unknown> {
  const command = fromExtendedJson<Document>(params.command);
  const result = await client.db(params.database).command(command);
  return toExtendedJson(result);
}
