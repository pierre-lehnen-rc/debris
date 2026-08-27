import { loadConfig } from "./config.js";
import { buildApp } from "./server.js";

async function main(): Promise<void> {
  const config = loadConfig();
  const { app, cache, apps } = await buildApp(config);

  let shuttingDown = false;
  const shutdown = async (reason: string): Promise<void> => {
    if (shuttingDown) return;
    shuttingDown = true;
    app.log.info({ reason }, "shutting down");
    apps.stop();
    await app.close();
    await cache.closeAll();
    process.exit(0);
  };

  for (const signal of ["SIGINT", "SIGTERM"] as const) {
    process.on(signal, () => {
      void shutdown(signal);
    });
  }

  // A managed server (launched by the app) stops itself once the last connected
  // app disconnects, so runs don't leave an orphaned server behind. A server the
  // developer started by hand leaves onEmpty unset and keeps running.
  if (config.managed) {
    apps.onEmpty = () => {
      app.log.info("no apps connected; stopping managed server");
      void shutdown("no-apps");
    };
  }

  try {
    await app.listen({ port: config.port, host: config.host });
  } catch (err) {
    app.log.error({ err }, "failed to start server");
    await cache.closeAll();
    process.exit(1);
  }
}

void main();
