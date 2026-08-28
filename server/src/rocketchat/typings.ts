import { existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { meteorDirOf, RcBridgeError } from "./bridge.js";

/** One method of a model's interface: its name and a readable signature. */
export interface RcModelMethod {
  name: string;
  /** e.g. `(username: string, options?: O) => Promise<IUser | null>`; "" if unknown. */
  signature: string;
}

/**
 * Lists a model's public methods from the `@rocket.chat/model-typings` interfaces
 * (`I<Model>Model`), so Debris shows exactly the API those interfaces declare —
 * including methods inherited from IBaseModel — and none of the raw class's internal
 * helpers. Pure server-side: it reads and type-checks the shipped `.d.ts` files from
 * the workspace's repository, needing neither the RC server running nor the bridge.
 *
 * TypeScript is loaded from the checkout (not bundled) via a require rooted at the
 * repository's Meteor app dir, where `@rocket.chat/model-typings` resolves from.
 */
export class ModelTypings {
  // meteorDir -> the resolved typescript module + the typings' models directory.
  private readonly envs = new Map<string, { ts: any; modelsDir: string }>();
  // "repoPath\nModel" -> sorted methods.
  private readonly cache = new Map<string, RcModelMethod[]>();

  /** The public methods of `<model>`'s interface, sorted by name; [] when none. */
  methods(repoPath: string, model: string): RcModelMethod[] {
    if (!/^[A-Za-z][A-Za-z0-9]*$/.test(model)) {
      throw new RcBridgeError(`invalid model name: ${model}`, 400);
    }
    const cacheKey = `${repoPath}\n${model}`;
    const hit = this.cache.get(cacheKey);
    if (hit) return hit;

    const env = this.env(meteorDirOf(repoPath));
    const file = join(env.modelsDir, `I${model}Model.d.ts`);
    const names = existsSync(file) ? this.extract(env.ts, file, `I${model}Model`) : [];
    this.cache.set(cacheKey, names);
    return names;
  }

  /** Resolve (and cache) typescript + the model-typings models dir for a meteor dir. */
  private env(meteorDir: string): { ts: any; modelsDir: string } {
    const hit = this.envs.get(meteorDir);
    if (hit) return hit;

    let ts: any;
    let modelsDir: string;
    try {
      const req = createRequire(meteorDir.replace(/\/*$/, "/"));
      ts = req("typescript");
      modelsDir = join(dirname(req.resolve("@rocket.chat/model-typings")), "models");
    } catch (e) {
      throw new RcBridgeError(
        `cannot load model typings from ${meteorDir} `
          + `(is the Rocket.Chat repository path correct, with dependencies installed?): `
          + `${(e as Error).message}`,
        400,
      );
    }
    const env = { ts, modelsDir };
    this.envs.set(meteorDir, env);
    return env;
  }

  /** Type-check one interface file and collect its methods with their signatures. */
  private extract(ts: any, file: string, ifaceName: string): RcModelMethod[] {
    const program = ts.createProgram([file], {
      target: ts.ScriptTarget.Latest,
      skipLibCheck: true,
      moduleResolution: ts.ModuleResolutionKind.NodeNext,
      noEmit: true,
    });
    const checker = program.getTypeChecker();
    const src = program.getSourceFile(file);
    if (!src) return [];

    let iface: any = null;
    ts.forEachChild(src, (n: any) => {
      if (ts.isInterfaceDeclaration(n) && n.name.text === ifaceName) iface = n;
    });
    if (!iface) return [];

    // The type includes inherited members (IBaseModel), which is what we want.
    const type = checker.getTypeAtLocation(iface.name);
    const out: RcModelMethod[] = [];
    const seen = new Set<string>();
    for (const sym of checker.getPropertiesOfType(type)) {
      const decls = sym.getDeclarations() || [];
      // A method signature, or a property typed as a function. Overloads declare the
      // name more than once; the first declaration stands for the method.
      const method = decls.find((d: any) => ts.isMethodSignature(d) || ts.isMethodDeclaration(d));
      const fnProp = decls.find(
        (d: any) => ts.isPropertySignature(d) && d.type && ts.isFunctionTypeNode(d.type),
      );
      const node = method ?? (fnProp ? (fnProp as any).type : null);
      if (node === null || seen.has(sym.getName())) continue;
      seen.add(sym.getName());
      out.push({ name: sym.getName(), signature: this.signatureOf(node) });
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out;
  }

  /**
   * A readable one-line signature for a method declaration: its parameters (names,
   * optionality, rest, and the types as written) and return type. Generic type
   * parameters are left off — they add noise without helping someone write the
   * argument list. The types are taken verbatim from the declaration rather than
   * resolved, so aliases the author chose (IUser['_id'], UserStatus) survive.
   */
  private signatureOf(decl: any): string {
    const flat = (s: string): string => s.replace(/\s+/g, " ").trim();
    const params: string[] = (decl.parameters ?? []).map((p: any) => {
      const rest = p.dotDotDotToken ? "..." : "";
      const optional = p.questionToken || p.initializer ? "?" : "";
      const type = p.type ? `: ${flat(p.type.getText())}` : "";
      return `${rest}${flat(p.name.getText())}${optional}${type}`;
    });
    const returns = decl.type ? ` => ${flat(decl.type.getText())}` : "";
    return `(${params.join(", ")})${returns}`;
  }
}
