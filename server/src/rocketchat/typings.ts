import { existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { RcBridgeError } from "./bridge.js";

/**
 * Lists a model's public methods from the `@rocket.chat/model-typings` interfaces
 * (`I<Model>Model`), so Debris shows exactly the API those interfaces declare —
 * including methods inherited from IBaseModel — and none of the raw class's internal
 * helpers. Pure server-side: it reads and type-checks the shipped `.d.ts` files from
 * the workspace's meteor dir, needing neither the RC server running nor the bridge.
 *
 * TypeScript is loaded from the checkout (not bundled) via a require rooted at the
 * meteor dir, the same place `@rocket.chat/model-typings` resolves from.
 */
export class ModelTypings {
  // meteorDir -> the resolved typescript module + the typings' models directory.
  private readonly envs = new Map<string, { ts: any; modelsDir: string }>();
  // "meteorDir\nModel" -> sorted method names.
  private readonly cache = new Map<string, string[]>();

  /** The public method names of `<model>`'s interface, sorted; [] when it has none. */
  methods(meteorDir: string, model: string): string[] {
    if (!/^[A-Za-z][A-Za-z0-9]*$/.test(model)) {
      throw new RcBridgeError(`invalid model name: ${model}`, 400);
    }
    const cacheKey = `${meteorDir}\n${model}`;
    const hit = this.cache.get(cacheKey);
    if (hit) return hit;

    const env = this.env(meteorDir);
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
        `cannot load model typings from ${meteorDir}: ${(e as Error).message}`,
        400,
      );
    }
    const env = { ts, modelsDir };
    this.envs.set(meteorDir, env);
    return env;
  }

  /** Type-check one interface file and collect its method property names. */
  private extract(ts: any, file: string, ifaceName: string): string[] {
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
    const names = new Set<string>();
    for (const sym of checker.getPropertiesOfType(type)) {
      const decls = sym.getDeclarations() || [];
      const isMethod = decls.some(
        (d: any) =>
          ts.isMethodSignature(d) ||
          ts.isMethodDeclaration(d) ||
          (ts.isPropertySignature(d) && d.type && ts.isFunctionTypeNode(d.type)),
      );
      if (isMethod) names.add(sym.getName());
    }
    return Array.from(names).sort();
  }
}
