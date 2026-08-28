import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";

/**
 * Where a Rocket.Chat bridge lives. Supplied by the client on each request, the
 * same way {@link ConnectionSpec} carries MongoDB connection details. The server
 * never persists these; they only key a cached {@link RcBridge}.
 */
export interface RcTarget {
  /** Absolute path to the Rocket.Chat `apps/meteor` directory (the Meteor app root). */
  meteorDir: string;
  /** Base URL of the running Rocket.Chat server. Defaults to http://localhost:3000. */
  url?: string;
}

export interface RcBridgeOptions {
  /**
   * Executable used to open a Meteor shell. Comes from server config, never the
   * request body — it is spawned as a command, so client-supplied would be RCE.
   */
  meteorBin: string;
  /** Max time (ms) to wait for a `meteor shell` install to complete. */
  shellTimeoutMs: number;
}

const DEFAULT_URL = "http://localhost:3000";
const BRIDGE_PATH = "/debris/call";

/** An error carrying an HTTP status; {@link describeError} maps it to a response. */
export class RcBridgeError extends Error {
  constructor(
    message: string,
    readonly statusCode = 400,
  ) {
    super(message);
    this.name = "RcBridgeError";
  }
}

/**
 * The code injected into a running Rocket.Chat server via `meteor shell`. It
 * registers a single Connect handler at {@link BRIDGE_PATH} that runs a model
 * method and returns its result as canonical Extended JSON.
 *
 * Nothing is written to disk: the handler lives only in the server's memory,
 * guarded so re-running merely swaps the (token-checked) logic in place, and it
 * disappears entirely on the next server restart. The per-session `token` gates
 * every request so a stale handler is never an open door.
 */
function buildInstaller(token: string): string {
  const tokenLiteral = JSON.stringify(token);
  const pathLiteral = JSON.stringify(BRIDGE_PATH);
  return `(function () {
  const { WebApp } = require('meteor/webapp');
  const models = require('@rocket.chat/models');
  const { EJSON } = require('mongodb').BSON;
  const BLOCKED = new Set(['constructor','__proto__','prototype','__defineGetter__','__defineSetter__','__lookupGetter__','__lookupSetter__','hasOwnProperty','isPrototypeOf','propertyIsEnumerable','toString','valueOf']);
  // Many model methods return a live Mongo cursor (or a { cursor, totalCount }
  // paginated shape) rather than a resolved array. A cursor back-references the
  // client/session pool, so serializing it directly throws on the circular
  // structure — drain it to documents first.
  async function materialize(v) {
    if (v && typeof v.toArray === 'function') return await v.toArray();
    if (v && v.cursor && typeof v.cursor.toArray === 'function') {
      const documents = await v.cursor.toArray();
      const totalCount = (v.totalCount && typeof v.totalCount.then === 'function') ? await v.totalCount : v.totalCount;
      return { documents: documents, totalCount: totalCount };
    }
    return v;
  }
  const D = (globalThis.__debris = globalThis.__debris || {});
  D.token = ${tokenLiteral};
  D.handle = async function (body) {
    const model = body && body.model;
    const method = body && body.method;
    const args = body && body.args;
    if (typeof model !== 'string' || typeof method !== 'string') throw new Error('model and method must be strings');
    if (BLOCKED.has(method) || method.charAt(0) === '_') throw new Error('method not allowed: ' + method);
    const inst = models[model];
    if (!inst || typeof inst !== 'object') throw new Error('unknown model: ' + model);
    const fn = inst[method];
    if (typeof fn !== 'function') throw new Error('not a function: ' + model + '.' + method);
    return await materialize(await fn.apply(inst, Array.isArray(args) ? args : []));
  };
  if (D.installed) return 'handler-updated';
  D.installed = true;
  WebApp.connectHandlers.use(${pathLiteral}, function (req, res) {
    if (req.headers['x-debris-token'] !== D.token) {
      res.statusCode = 403;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ ok: false, error: 'forbidden' }));
      return;
    }
    let raw = '';
    req.on('data', function (c) { raw += c; });
    req.on('end', async function () {
      try {
        const parsed = raw ? EJSON.parse(raw) : {};
        const result = await D.handle(parsed);
        res.setHeader('content-type', 'application/json');
        res.end(EJSON.stringify({ ok: true, result: result }, { relaxed: false }));
      } catch (err) {
        res.statusCode = 400;
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify({ ok: false, error: String((err && err.message) || err) }));
      }
    });
  });
  return 'installed ${BRIDGE_PATH}';
})()`;
}

/** Feed a script to `meteor shell` and resolve with its trimmed output. */
function runMeteorShell(
  bin: string,
  cwd: string,
  script: string,
  timeoutMs: number,
): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, ["shell"], { cwd, stdio: ["pipe", "pipe", "pipe"] });
    let out = "";
    let err = "";
    let settled = false;

    const finish = (fn: () => void): void => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn();
    };

    const timer = setTimeout(() => {
      finish(() => {
        child.kill("SIGKILL");
        reject(
          new RcBridgeError(
            `meteor shell timed out after ${timeoutMs}ms (is the Rocket.Chat dev server running for ${cwd}?)`,
            504,
          ),
        );
      });
    }, timeoutMs);

    child.stdout.on("data", (d: Buffer) => {
      out += d.toString();
    });
    child.stderr.on("data", (d: Buffer) => {
      err += d.toString();
    });
    child.on("error", (e: Error) => {
      finish(() => reject(new RcBridgeError(`failed to spawn '${bin} shell': ${e.message}`, 500)));
    });
    child.on("close", () => {
      finish(() => resolve(out.trim() || err.trim()));
    });

    child.stdin.write(script);
    child.stdin.end();
  });
}

type PostResult =
  | { kind: "ok"; result: unknown }
  | { kind: "error"; message: string; status: number }
  // The endpoint didn't answer as our handler — RC likely restarted and dropped
  // the in-memory middleware. The caller reinstalls and retries once.
  | { kind: "reinstall" };

interface BridgeReply {
  ok: boolean;
  error?: string;
  result?: unknown;
}

function isBridgeReply(v: unknown): v is BridgeReply {
  return typeof v === "object" && v !== null && typeof (v as { ok?: unknown }).ok === "boolean";
}

/**
 * A handle to the model-eval bridge inside one Rocket.Chat server. Installs the
 * in-memory endpoint on demand, then proxies `{ model, method, args }` calls to
 * it over HTTP. Reinstalls automatically if the server was restarted.
 */
export class RcBridge {
  private readonly token = randomBytes(24).toString("hex");
  private installed = false;
  private installing: Promise<void> | null = null;

  constructor(
    private target: Required<RcTarget>,
    private readonly options: RcBridgeOptions,
  ) {}

  get isInstalled(): boolean {
    return this.installed;
  }

  get url(): string {
    return this.target.url;
  }

  /**
   * Point this bridge at a (possibly new) URL for the same RC server. The bridge is
   * keyed by its meteor dir — one per server — so the URL is just where to POST; the
   * latest one wins without disturbing the installed handler or its token.
   */
  setUrl(url: string): void {
    this.target.url = url;
  }

  /** Ensure the bridge handler is installed, running the shell install if not. */
  async ensureInstalled(force = false): Promise<void> {
    if (this.installed && !force) return;
    if (force) {
      this.installed = false;
      this.installing = null;
    }
    if (!this.installing) {
      this.installing = this.install().then(
        () => {
          this.installed = true;
          this.installing = null;
        },
        (e: unknown) => {
          this.installing = null;
          throw e;
        },
      );
    }
    return this.installing;
  }

  private async install(): Promise<void> {
    const output = await runMeteorShell(
      this.options.meteorBin,
      this.target.meteorDir,
      buildInstaller(this.token),
      this.options.shellTimeoutMs,
    );
    if (!/installed \/debris\/call|handler-updated/.test(output)) {
      throw new RcBridgeError(
        `bridge install did not confirm; meteor shell said: ${output.slice(0, 500) || "(no output)"}`,
        502,
      );
    }
  }

  /**
   * Run a model method inside RC by posting to the already-installed endpoint.
   * Does NOT install — injection is a separate, explicit step (see the /install
   * route). If the endpoint isn't there (never installed this session, server
   * restarted, or the token was superseded) this reports that so the caller can
   * refresh, rather than silently reinstalling.
   */
  async call(model: string, method: string, args: unknown[]): Promise<unknown> {
    const attempt = await this.post(model, method, args);
    switch (attempt.kind) {
      case "ok":
        return attempt.result;
      case "error":
        throw new RcBridgeError(attempt.message, attempt.status);
      case "reinstall":
        throw new RcBridgeError(
          `Server Models endpoint isn't installed on ${this.target.url}. `
            + `Use Refresh in the Server Models panel to install it.`,
          503,
        );
    }
  }

  private async post(model: string, method: string, args: unknown[]): Promise<PostResult> {
    let resp: Response;
    try {
      resp = await fetch(`${this.target.url}${BRIDGE_PATH}`, {
        method: "POST",
        headers: { "content-type": "application/json", "x-debris-token": this.token },
        // Forwarded as plain JSON; the bridge EJSON-parses it so args may carry
        // $oid/$date/etc. Values round-trip through the same dialect as ejson.ts.
        body: JSON.stringify({ model, method, args }),
      });
    } catch (e) {
      throw new RcBridgeError(
        `cannot reach Rocket.Chat at ${this.target.url}: ${(e as Error).message}`,
        502,
      );
    }

    const text = await resp.text();
    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      json = undefined;
    }

    if (!isBridgeReply(json)) return { kind: "reinstall" };
    // 403 means the server-side token no longer matches ours — the handler was
    // reinstalled by someone else. Reinstall to re-assert this bridge's token and
    // retry, rather than surfacing a spurious "forbidden".
    if (resp.status === 403) return { kind: "reinstall" };
    if (!json.ok) {
      return { kind: "error", message: json.error ?? "bridge error", status: 400 };
    }
    return { kind: "ok", result: json.result };
  }
}

/**
 * Caches one {@link RcBridge} per RC server (keyed by meteor dir) so its token and
 * install state persist across requests. Keying by the meteor dir rather than the
 * URL is deliberate: the meteor dir identifies the server the handler is installed
 * into and owns the single server-side token, so a changed URL just re-points the
 * same bridge instead of spawning a rival with a clashing token. Bridges hold no
 * open resources (the shell child is short-lived), so there is nothing to close.
 */
export class RcBridgeRegistry {
  private readonly bridges = new Map<string, RcBridge>();

  constructor(private readonly options: RcBridgeOptions) {}

  acquire(target: RcTarget): RcBridge {
    const meteorDir = target.meteorDir;
    const url = (target.url ?? DEFAULT_URL).replace(/\/+$/, "");

    let bridge = this.bridges.get(meteorDir);
    if (!bridge) {
      bridge = new RcBridge({ meteorDir, url }, this.options);
      this.bridges.set(meteorDir, bridge);
    } else {
      bridge.setUrl(url);
    }
    return bridge;
  }
}
