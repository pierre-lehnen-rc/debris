import { EJSON } from "bson";

/**
 * Convert client-supplied Extended JSON into native BSON values. This lets the
 * client express types the GUI needs, e.g. `{ "_id": { "$oid": "..." } }` or
 * `{ "$date": "..." }`, and have them become real ObjectId / Date instances
 * before reaching the driver.
 */
export function fromExtendedJson<T = unknown>(value: unknown): T {
  if (value === undefined || value === null) return value as T;
  // EJSON.deserialize operates on plain objects/arrays produced by JSON parsing.
  return EJSON.deserialize(value as Record<string, unknown>, { relaxed: false }) as T;
}

/**
 * Convert BSON values returned by the driver into Extended JSON suitable for a
 * JSON response. Canonical (relaxed: false) form preserves type information so
 * the client can distinguish ObjectIds, longs, dates, etc.
 */
export function toExtendedJson(value: unknown): unknown {
  return EJSON.serialize(value as Record<string, unknown>, { relaxed: false });
}
