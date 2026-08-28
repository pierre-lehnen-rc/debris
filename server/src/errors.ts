import { MongoError, MongoServerSelectionError } from "mongodb";

export interface ErrorPayload {
  error: {
    message: string;
    name: string;
    code?: number | string;
  };
}

/**
 * Map an arbitrary thrown value to an HTTP status code and a structured payload.
 * MongoDB driver errors carry useful codes; connection failures map to 502
 * (the upstream DB is unreachable), other Mongo errors to 400 (bad operation),
 * and anything unexpected to 500.
 */
export function describeError(err: unknown): { status: number; payload: ErrorPayload } {
  if (err instanceof MongoServerSelectionError) {
    return {
      status: 502,
      payload: { error: { message: err.message, name: err.name } },
    };
  }

  if (err instanceof MongoError) {
    const code = typeof err.code === "number" || typeof err.code === "string" ? err.code : undefined;
    return {
      status: 400,
      payload: { error: { message: err.message, name: err.name, ...(code !== undefined ? { code } : {}) } },
    };
  }

  // Errors that carry their own HTTP status (e.g. the Rocket.Chat bridge).
  if (err instanceof Error && typeof (err as { statusCode?: unknown }).statusCode === "number") {
    const status = (err as unknown as { statusCode: number }).statusCode;
    return { status, payload: { error: { message: err.message, name: err.name } } };
  }

  if (err instanceof Error) {
    return {
      status: 500,
      payload: { error: { message: err.message, name: err.name } },
    };
  }

  return {
    status: 500,
    payload: { error: { message: String(err), name: "UnknownError" } },
  };
}
