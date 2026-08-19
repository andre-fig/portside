import "reflect-metadata";
import { BuildStatus, PrismaClient, SourceSnapshotStatus, SyncStatus } from "@prisma/client";

const prisma = new PrismaClient();
const pollIntervalMs = Number(process.env.SYNC_WORKER_POLL_MS ?? 60_000);
const timeoutMs = Number(process.env.SYNC_WORKER_TIMEOUT_MS ?? 30 * 60_000);

async function reconcileStaleWork(): Promise<void> {
  const cutoff = new Date(Date.now() - timeoutMs);
  const finishedAt = new Date();
  const [syncExecutions, builds, snapshots] = await prisma.$transaction([
    prisma.syncExecution.updateMany({
      where: { status: SyncStatus.running, startedAt: { lt: cutoff } },
      data: { status: SyncStatus.failed, errorCode: "sync_timeout", finishedAt },
    }),
    prisma.runtimeBuild.updateMany({
      where: {
        status: { in: [BuildStatus.queued, BuildStatus.running] },
        createdAt: { lt: cutoff },
      },
      data: { status: BuildStatus.failed, finishedAt },
    }),
    prisma.sourceSnapshot.updateMany({
      where: { status: SourceSnapshotStatus.discovered, createdAt: { lt: cutoff } },
      data: { status: SourceSnapshotStatus.failed },
    }),
  ]);
  console.log(
    JSON.stringify({
      level: "info",
      event: "sync_worker_reconciled",
      syncExecutionsFailed: syncExecutions.count,
      buildsFailed: builds.count,
      snapshotsFailed: snapshots.count,
      at: finishedAt.toISOString(),
    }),
  );
}

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
    await reconcileStaleWork();
    const poller = setInterval(() => {
      reconcileStaleWork().catch((error) => {
        console.error(
          JSON.stringify({
            level: "error",
            event: "sync_worker_reconcile_failed",
            error: error instanceof Error ? error.name : "reconcile_failed",
          }),
        );
      });
    }, pollIntervalMs);
    await waitForShutdown();
    clearInterval(poller);
  } finally {
    await prisma.$disconnect();
  }
}

run().catch((error) => {
  console.error(
    JSON.stringify({
      level: "error",
      event: "sync_worker_failed",
      error: error instanceof Error ? error.name : "worker_failed",
    }),
  );
  process.exit(1);
});
