import "reflect-metadata";
import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();
async function run(): Promise<void> {
  try {
    console.log(
      JSON.stringify({
        level: "info",
        event: "sync_worker_idle",
        at: new Date().toISOString(),
      }),
    );
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
