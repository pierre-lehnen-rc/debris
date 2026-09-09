import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { join } from "node:path";
import { meteorEnv, meteorSearchDirs, resolveMeteorBin } from "./meteor.js";

/**
 * Where a Rocket.Chat bridge lives. Supplied by the client on each request, the
 * same way {@link ConnectionSpec} carries MongoDB connection details. The server
 * never persists these; they only key a cached {@link RcBridge}.
 */
export interface RcTarget {
  /**
   * Absolute path to the Rocket.Chat repository (the checkout root, e.g.
   * /home/me/Documents/Rocket.Chat). The Meteor app directory the shell and the
   * typings are read from is derived with {@link meteorDirOf}, so the user
   * configures the repository they cloned rather than a path inside it.
   */
  repoPath: string;
  /** Base URL of the running Rocket.Chat server. Defaults to http://localhost:3000. */
  url?: string;
}

/** The Meteor app directory inside a Rocket.Chat checkout. */
export function meteorDirOf(repoPath: string): string {
  return join(repoPath, "apps", "meteor");
}

/**
 * A plain integer from a value that may be a number or an Extended JSON wrapper
 * ({ $numberInt } / { $numberLong }), since the bridge's canonical-EJSON responses
 * box integers. Anything unrecognized becomes 0.
 */
function toPlainInt(value: unknown): number {
  if (typeof value === "number") return Math.trunc(value);
  if (value && typeof value === "object") {
    const boxed = (value as { $numberInt?: unknown; $numberLong?: unknown });
    const raw = boxed.$numberInt ?? boxed.$numberLong;
    if (raw !== undefined) return Math.trunc(Number(raw)) || 0;
  }
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

export interface RcBridgeOptions {
  /**
   * Executable used to open a Meteor shell — a bare command name to look up, or a
   * path to a specific binary. Comes from server config, never the request body:
   * it is spawned as a command, so client-supplied would be RCE.
   */
  meteorBin: string;
  /** Max time (ms) to wait for a `meteor shell` install to complete. */
  shellTimeoutMs: number;
}

const DEFAULT_URL = "http://localhost:3000";
const BRIDGE_PATH = "/debris/call";

/** One model exposed by @rocket.chat/models, and the collection it reads. */
/** What {@link RcBridge.probe} found when it asked the server. */
export interface RcBridgeStatus {
  /** Whether Rocket.Chat itself answered at all. */
  reachable: boolean;
  /** Whether the endpoint answered as our injected handler. */
  injected: boolean;
  /** Models the bridge reported, when it answered. */
  models: number;
  /** Why it didn't, when something went wrong. */
  error: string;
}

export interface RcModelInfo {
  name: string;
  collection: string;
}

/** One captured log line: its sequence number and the raw text as the tap saw it. */
export interface RcLogEntry {
  seq: number;
  line: string;
}

/** A poll of the log tap: the new lines, the high-water `seq`, and any tap error. */
export interface RcLogsResult {
  seq: number;
  error: string;
  entries: RcLogEntry[];
}

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
    // Meta-op: list the models available in @rocket.chat/models (PascalCase object
    // exports) for the Server Models sidebar, each with the Mongo collection it
    // reads. The collection comes from the model's own getCollectionName(), which is
    // authoritative — it already accounts for the rocketchat_ prefix and for the
    // models that opt out of it via a collectionNameResolver (users, instances, …).
    if (body && body.op === 'listModels') {
      return Object.keys(models).filter(function (k) {
        if (!/^[A-Z]/.test(k)) return false;
        try { return models[k] && typeof models[k] === 'object'; } catch (e) { return false; }
      }).sort().map(function (name) {
        var collection = '';
        try {
          var c = models[name].getCollectionName();
          if (typeof c === 'string') collection = c;
        } catch (e) { /* a model without a resolvable collection stays untyped */ }
        return { name: name, collection: collection };
      });
    }
    // Read log lines the tap has captured since sequence \`since\` (0 for the whole
    // retained buffer). \`seq\` is the current high-water mark to poll from next;
    // \`error\` reports a tap that couldn't attach. Lines are returned raw — never
    // parsed here — so the client owns formatting and a future file source fits.
    if (body && body.op === 'logs') {
      var LR = D.logRing || { buf: [], seq: 0, error: 'log tap not installed' };
      var since = (body && body.since) | 0;
      return {
        seq: LR.seq,
        error: LR.error || '',
        entries: LR.buf.filter(function (e) { return e.seq > since; })
      };
    }
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
  // Tap the shared @rocket.chat/logger pino stream so the log view can read the
  // server's log output. Every RC logger is a child of one pino instance and shares
  // a single destination stream; teeing its write() captures every logger's line as
  // raw NDJSON — before pino-pretty formats it — and still forwards, so the meteor
  // terminal is unaffected. Best-effort and idempotent: a failure here never fails
  // the injection (the log view surfaces the reason), and re-running only re-attaches
  // if a restart dropped the tap. Runs before the installed-guard below so a re-inject
  // retries a tap that didn't take the first time.
  //
  // Finding the stream: pino keys it under Symbol('pino.stream'), which is UNIQUE per
  // pino module copy — and Rocket.Chat resolves more than one pino (apps/meteor's vs
  // the repo root's). Requiring our own pino would get a symbol that never matches the
  // logger the app actually built. So find the symbol ON the logger by its description,
  // walking the prototype chain (a child logger inherits the stream from its parent).
  var LR = (D.logRing = D.logRing || { buf: [], seq: 0, max: 2000, error: '' });
  try {
    var logger = require('@rocket.chat/logger').getPino('debris-log-tap');
    var streamSym = null;
    for (var obj = logger; obj && !streamSym; obj = Object.getPrototypeOf(obj)) {
      var syms = Object.getOwnPropertySymbols(obj);
      for (var i = 0; i < syms.length; i++) {
        if (syms[i].description === 'pino.stream') { streamSym = syms[i]; break; }
      }
    }
    var stream = streamSym ? logger[streamSym] : null;
    if (!stream || typeof stream.write !== 'function') {
      LR.error = 'log stream not reachable (no pino stream symbol on the logger)';
    } else if (!stream.__debrisTapped) {
      stream.__debrisTapped = true;
      LR.error = '';
      var origWrite = stream.write.bind(stream);
      stream.write = function (chunk) {
        try {
          var line = typeof chunk === 'string' ? chunk : String(chunk);
          LR.buf.push({ seq: ++LR.seq, line: line });
          if (LR.buf.length > LR.max) LR.buf.splice(0, LR.buf.length - LR.max);
        } catch (e) { /* never let logging break logging */ }
        return origWrite(chunk);
      };
    }
  } catch (e) {
    LR.error = 'log tap failed: ' + String((e && e.message) || e);
  }
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
    const child = spawn(bin, ["shell"], {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
      env: meteorEnv(),
    });
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
   * keyed by its repository path — one per server — so the URL is just where to
   * POST; the latest one wins without disturbing the injected handler or its token.
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
      await this.meteorBin(),
      meteorDirOf(this.target.repoPath),
      buildInstaller(this.token),
      this.options.shellTimeoutMs,
    );
    if (!/installed \/debris\/call|handler-updated/.test(output)) {
      throw new RcBridgeError(
        `bridge injection did not confirm; meteor shell said: ${output.slice(0, 500) || "(no output)"}`,
        502,
      );
    }
  }

  /**
   * The `meteor` executable to spawn, resolved against PATH and the usual install
   * locations. Resolving here rather than trusting PATH matters because the server
   * is normally started by the app, which — launched from a desktop rather than a
   * shell — passes on a PATH that often has none of the directories Meteor lives in.
   */
  private async meteorBin(): Promise<string> {
    const configured = this.options.meteorBin;
    const resolved = await resolveMeteorBin(configured);
    if (resolved) return resolved;
    throw new RcBridgeError(
      `could not find the '${configured}' executable. Looked in PATH and in `
        + `${meteorSearchDirs().join(", ")}. Set DEBRIS_RC_METEOR_BIN to its full `
        + `path (\`which meteor\` shows it) and restart the server.`,
      500,
    );
  }

  /**
   * Run a model method inside RC by posting to the already-installed endpoint.
   * Does NOT install — injection is a separate, explicit step (see the /install
   * route). If the endpoint isn't there (never installed this session, server
   * restarted, or the token was superseded) this reports that so the caller can
   * refresh, rather than silently reinstalling.
   */
  async call(model: string, method: string, args: unknown[]): Promise<unknown> {
    return this.unwrap(await this.post({ model, method, args }));
  }

  /**
   * List the models available in @rocket.chat/models on this server, each as
   * `{ name, collection }` where `collection` is the Mongo collection the model
   * reads (used to type its query results against the database schema).
   */
  async listModels(): Promise<RcModelInfo[]> {
    const result = this.unwrap(await this.post({ op: "listModels" }));
    return Array.isArray(result) ? (result as RcModelInfo[]) : [];
  }

  /**
   * Read log lines the injected tap has captured since sequence `since` (0 for the
   * whole retained buffer). Returns the high-water `seq` to poll from next, any
   * tap-side `error` (e.g. the pino stream wasn't reachable), and the new lines as
   * raw strings — never parsed here, so a future file-tail source of pretty-printed
   * text flows through the same shape. Installs nothing; `unwrap` throws the 503
   * "not injected" when the bridge isn't there, exactly like `call`/`listModels`.
   */
  async readLogs(since: number): Promise<RcLogsResult> {
    const result = this.unwrap(await this.post({ op: "logs", since }));
    const r = (result ?? {}) as { seq?: unknown; error?: unknown; entries?: unknown };
    // The RC handler serializes its result as canonical Extended JSON (relaxed:
    // false, to round-trip model data faithfully), which wraps a plain integer as
    // { $numberInt: "1" }. Log sequences are just counters, and the client contract
    // for logs is plain JSON — so unwrap them back to numbers here rather than leak
    // EJSON shapes the log view would have to know about.
    const entries = Array.isArray(r.entries)
      ? (r.entries as Array<Record<string, unknown>>).map((e) => ({
          seq: toPlainInt(e?.seq),
          line: typeof e?.line === "string" ? e.line : String(e?.line ?? ""),
        }))
      : [];
    return {
      seq: toPlainInt(r.seq),
      error: typeof r.error === "string" ? r.error : "",
      entries,
    };
  }

  /**
   * Report whether the injected endpoint is answering right now, installing
   * nothing. Distinct from {@link isInstalled}, which is only this process's
   * memory of having injected once: Rocket.Chat drops the in-memory handler when
   * it restarts, and another Debris server can supersede the token, so a status
   * panel has to ask the server rather than trust a flag.
   *
   * Never throws — every way this can go wrong is a state worth showing.
   */
  async probe(): Promise<RcBridgeStatus> {
    let attempt: PostResult;
    try {
      attempt = await this.post({ op: "listModels" });
    } catch (e) {
      // post() throws only when Rocket.Chat itself couldn't be reached.
      return {
        reachable: false,
        injected: false,
        models: 0,
        error: (e as Error).message,
      };
    }
    switch (attempt.kind) {
      case "ok":
        return {
          reachable: true,
          injected: true,
          models: Array.isArray(attempt.result) ? attempt.result.length : 0,
          error: "",
        };
      // The server answered, but not as our handler: never injected, dropped on
      // restart, or another bridge's token now holds the path.
      case "reinstall":
        return { reachable: true, injected: false, models: 0, error: "" };
      case "error":
        return { reachable: true, injected: false, models: 0, error: attempt.message };
    }
  }

  /** Map a post outcome to a value or a thrown error (the "not installed" 503). */
  private unwrap(attempt: PostResult): unknown {
    switch (attempt.kind) {
      case "ok":
        return attempt.result;
      case "error":
        throw new RcBridgeError(attempt.message, attempt.status);
      case "reinstall":
        throw new RcBridgeError(
          `Server Models endpoint isn't injected on ${this.target.url}. `
            + `Use Inject in the Server Models footer to inject it.`,
          503,
        );
    }
  }

  private async post(payload: Record<string, unknown>): Promise<PostResult> {
    let resp: Response;
    try {
      resp = await fetch(`${this.target.url}${BRIDGE_PATH}`, {
        method: "POST",
        headers: { "content-type": "application/json", "x-debris-token": this.token },
        // Forwarded as plain JSON; the bridge EJSON-parses it so args may carry
        // $oid/$date/etc. Values round-trip through the same dialect as ejson.ts.
        body: JSON.stringify(payload),
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
 * Caches one {@link RcBridge} per RC server (keyed by repository path) so its token
 * and injection state persist across requests. Keying by the repository rather than
 * the URL is deliberate: the repository identifies the server the handler is
 * injected into and owns the single server-side token, so a changed URL just
 * re-points the same bridge instead of spawning a rival with a clashing token.
 * Bridges hold no open resources (the shell child is short-lived), so there is
 * nothing to close.
 */
export class RcBridgeRegistry {
  private readonly bridges = new Map<string, RcBridge>();

  constructor(private readonly options: RcBridgeOptions) {}

  acquire(target: RcTarget): RcBridge {
    const repoPath = target.repoPath;
    const url = (target.url ?? DEFAULT_URL).replace(/\/+$/, "");

    let bridge = this.bridges.get(repoPath);
    if (!bridge) {
      bridge = new RcBridge({ repoPath, url }, this.options);
      this.bridges.set(repoPath, bridge);
    } else {
      bridge.setUrl(url);
    }
    return bridge;
  }
}
