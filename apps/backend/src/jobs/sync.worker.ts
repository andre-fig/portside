import "reflect-metadata";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

function waitForShutdown(): Promise<void> {
  return new Promise((resolve) => {
    const keepAlive = setInterval(() => undefined, 60_000);
    const shutdown = () => {
      clearInterval(keepAlive);
      resolve();
    };
    process.once("SIGTERM", shutdown);
    process.once("SIGINT", shutdown);
  });
}

async function run(): Promise<void> {
  try {
    console.log(
      JSON.stringify({
        level: "info",
        event: "sync_worker_idle",
        at: new Date().toISOString(),
      }),
    );
    await waitForShutdown();
  } finally {
    await prisma.$disconnect();
  }
}
run().catch((error) => {
  console.error(
    JSON.stringify({
      level: "error",
      event: "sync_worker_failed",
      error: String(error),
    }),
  );
  process.exit(1);
});
