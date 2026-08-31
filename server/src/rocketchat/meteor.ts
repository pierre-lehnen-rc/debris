import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

/**
 * Locating the `meteor` executable used to install the model bridge.
 *
 * The server is normally spawned by the app, so it inherits the app's
 * environment — and a GUI-launched app gets a minimal PATH (on macOS, launchd
 * hands it `/usr/bin:/bin:/usr/sbin:/sbin`, with none of the directories a
 * shell's profile would have added). `spawn("meteor")` then fails with ENOENT
 * even though the user's terminal finds `meteor` perfectly well. So resolve the
 * binary ourselves against the usual install locations before spawning it — the
 * same approach ServerManager takes for `node` on the client side.
 */

/**
 * Directories to look in beyond PATH, in order of preference. These are where
 * Meteor's installer and the common package managers put the launcher; missing
 * ones are simply skipped.
 */
export function meteorSearchDirs(): string[] {
  const home = homedir();
  const dirs = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/opt/local/bin"];
  if (home) {
    // The official installer's own copy: `~/.meteor/meteor` is a working launcher
    // even when the /usr/local/bin symlink to it was never created.
    dirs.push(join(home, ".meteor"), join(home, ".local", "bin"));
  }
  return dirs;
}

async function isExecutable(path: string): Promise<boolean> {
  try {
    await access(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Resolve `configured` to an executable path, or null if nothing matched.
 *
 * A value naming a path (anything containing a separator) is taken at its word
 * and only checked; a bare command name is looked up in PATH first, then in
 * {@link meteorSearchDirs}. On Windows the name is passed straight through, so
 * `spawn` keeps doing the PATHEXT lookup that finds `meteor.bat`.
 */
export async function resolveMeteorBin(configured: string): Promise<string | null> {
  if (process.platform === "win32") return configured;
  if (configured.includes("/")) return (await isExecutable(configured)) ? configured : null;

  const fromPath = (process.env.PATH ?? "").split(delimiter).filter((d) => d !== "");
  for (const dir of [...fromPath, ...meteorSearchDirs()]) {
    const candidate = join(dir, configured);
    if (await isExecutable(candidate)) return candidate;
  }
  return null;
}

/**
 * The environment for the `meteor` child. Meteor's launcher shells out to its own
 * dev bundle and to tools like `git`, so a PATH missing the usual directories
 * breaks it further down even once the launcher itself is found. Append the search
 * directories to the inherited PATH — appended, so a PATH the user did set wins.
 */
export function meteorEnv(): NodeJS.ProcessEnv {
  if (process.platform === "win32") return process.env;
  const existing = (process.env.PATH ?? "").split(delimiter).filter((d) => d !== "");
  const merged = [...existing, ...meteorSearchDirs().filter((d) => !existing.includes(d))];
  return { ...process.env, PATH: merged.join(delimiter) };
}
