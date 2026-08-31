/**
 * Tracks which app instances ("clients", in the user's terms) are currently
 * connected. Each app posts a heartbeat every ~30s and a disconnect when it
 * closes. An app that goes silent for longer than `timeoutMs` is presumed gone.
 *
 * When the last known app goes away — either by disconnecting or by timing out —
 * {@link onEmpty} fires once. A managed server uses this to stop itself; a server
 * started by hand ignores it and keeps running.
 */
export interface AppRegistryOptions {
  /** Time (ms) without a heartbeat after which an app is presumed disconnected. */
  timeoutMs: number;
  /** How often (ms) to sweep for timed-out apps. */
  sweepIntervalMs: number;
}

export class AppRegistry {
  /** app id -> last-seen timestamp (ms). */
  private readonly apps = new Map<string, number>();
  private readonly sweepTimer: NodeJS.Timeout;
  /**
   * Whether any app has ever connected. Guards against firing {@link onEmpty}
   * during the startup gap before the launching app sends its first heartbeat.
   */
  private hasHadApps = false;

  /** Invoked once when the last connected app goes away. */
  onEmpty: (() => void) | null = null;

  constructor(private readonly options: AppRegistryOptions) {
    this.sweepTimer = setInterval(() => this.sweep(), options.sweepIntervalMs);
    // Don't keep the process alive solely for this timer.
    this.sweepTimer.unref();
  }

  /** Register or refresh an app's presence. */
  heartbeat(id: string): void {
    this.apps.set(id, Date.now());
    this.hasHadApps = true;
  }

  /** Remove an app that has cleanly signalled it is closing. */
  disconnect(id: string): void {
    if (this.apps.delete(id)) this.maybeEmpty();
  }

  /** Whether the app with this id is currently registered. */
  has(id: string): boolean {
    return this.apps.has(id);
  }

  /**
   * Whether this server will stop itself once the last app goes away — true for a
   * managed server (one whose owner wired up {@link onEmpty}), false for one
   * started by hand.
   */
  get stopsWhenEmpty(): boolean {
    return this.onEmpty !== null;
  }

  /** Drop apps whose last heartbeat is older than the timeout. */
  private sweep(): void {
    const now = Date.now();
    let removed = false;
    for (const [id, lastSeen] of this.apps) {
      if (now - lastSeen > this.options.timeoutMs) {
        this.apps.delete(id);
        removed = true;
      }
    }
    if (removed) this.maybeEmpty();
  }

  /** Fire onEmpty exactly once when the registry empties out after having apps. */
  private maybeEmpty(): void {
    if (this.hasHadApps && this.apps.size === 0) {
      this.hasHadApps = false;
      this.onEmpty?.();
    }
  }

  /** Number of currently connected apps. */
  get size(): number {
    return this.apps.size;
  }

  /** Stop the sweep timer. Call on shutdown. */
  stop(): void {
    clearInterval(this.sweepTimer);
  }
}
