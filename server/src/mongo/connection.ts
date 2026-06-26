import { createHash } from "node:crypto";
import type { MongoClientOptions } from "mongodb";

/**
 * Connection details supplied by the client on every request. Either a full
 * `uri` is provided, or discrete fields are used to build one. Credentials are
 * never persisted server-side; they only live for the lifetime of the cached
 * client (see {@link ClientCache}).
 */
export interface ConnectionSpec {
  /** Full MongoDB connection string. Takes precedence over discrete fields. */
  uri?: string;
  /** Host name or IP. Defaults to "127.0.0.1" when no uri is given. */
  host?: string;
  /** Port. Defaults to 27017. */
  port?: number;
  /** Username for authentication. */
  username?: string;
  /** Password for authentication. */
  password?: string;
  /** Authentication database (authSource). */
  authSource?: string;
  /** SCRAM/other auth mechanism, e.g. "SCRAM-SHA-256". */
  authMechanism?: string;
  /** Replica set name. */
  replicaSet?: string;
  /** Force a direct (non-discovering) connection to a single host. */
  directConnection?: boolean;
  /** Enable TLS/SSL. */
  tls?: boolean;
  /** Skip TLS certificate validation (insecure; for self-signed certs). */
  tlsAllowInvalidCertificates?: boolean;
}

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 27017;

/** Build a `mongodb://` URI from discrete connection fields. */
function buildUriFromFields(spec: ConnectionSpec): string {
  const host = spec.host ?? DEFAULT_HOST;
  const port = spec.port ?? DEFAULT_PORT;
  const auth =
    spec.username !== undefined && spec.username !== ""
      ? `${encodeURIComponent(spec.username)}:${encodeURIComponent(spec.password ?? "")}@`
      : "";

  const params = new URLSearchParams();
  if (spec.authSource) params.set("authSource", spec.authSource);
  if (spec.authMechanism) params.set("authMechanism", spec.authMechanism);
  if (spec.replicaSet) params.set("replicaSet", spec.replicaSet);
  if (spec.directConnection) params.set("directConnection", "true");
  if (spec.tls) params.set("tls", "true");
  if (spec.tlsAllowInvalidCertificates) params.set("tlsAllowInvalidCertificates", "true");

  const query = params.toString();
  return `mongodb://${auth}${host}:${port}/${query ? `?${query}` : ""}`;
}

/** Resolve a {@link ConnectionSpec} to a final connection URI. */
export function resolveUri(spec: ConnectionSpec): string {
  if (spec.uri && spec.uri.trim() !== "") return spec.uri.trim();
  return buildUriFromFields(spec);
}

/** Driver options applied on top of whatever the URI encodes. */
export function buildClientOptions(serverSelectionTimeoutMs: number): MongoClientOptions {
  return { serverSelectionTimeoutMS: serverSelectionTimeoutMs };
}

/**
 * Derive a stable cache key from a connection spec. Distinct credentials or
 * options must yield distinct keys so clients are never shared across identities.
 * The key is hashed so raw credentials never appear in logs or maps as plain text.
 */
export function connectionKey(spec: ConnectionSpec): string {
  const normalized = JSON.stringify({
    uri: spec.uri ?? null,
    host: spec.host ?? null,
    port: spec.port ?? null,
    username: spec.username ?? null,
    password: spec.password ?? null,
    authSource: spec.authSource ?? null,
    authMechanism: spec.authMechanism ?? null,
    replicaSet: spec.replicaSet ?? null,
    directConnection: spec.directConnection ?? null,
    tls: spec.tls ?? null,
    tlsAllowInvalidCertificates: spec.tlsAllowInvalidCertificates ?? null,
  });
  return createHash("sha256").update(normalized).digest("hex");
}
