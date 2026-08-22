import "reflect-metadata";
import {
  BuildStatus,
  PrismaClient,
  SourceSnapshotStatus,
  SyncStatus,
  type Prisma,
} from "@prisma/client";
import {
  workflowRunToBuildUpdate,
  type GitHubWorkflowRun,
} from "./workflow-run.js";

const prisma = new PrismaClient();
const pollIntervalMs = Number(process.env.SYNC_WORKER_POLL_MS ?? 60_000);
const timeoutMs = Number(process.env.SYNC_WORKER_TIMEOUT_MS ?? 30 * 60_000);
const repository =
  process.env.PORTSIDE_GITHUB_REPOSITORY ?? "andre-fig/portside";
const workflow = process.env.PORTSIDE_RUNTIME_WORKFLOW ?? "build-runtime.yml";

async function reconcileStaleWork(): Promise<void> {
  const cutoff = new Date(Date.now() - timeoutMs);
  const finishedAt = new Date();
  const [syncExecutions, builds, snapshots] = await prisma.$transaction([
    prisma.syncExecution.updateMany({
      where: { status: SyncStatus.running, startedAt: { lt: cutoff } },
      data: {
        status: SyncStatus.failed,
        errorCode: "sync_timeout",
        finishedAt,
      },
    }),
    prisma.runtimeBuild.updateMany({
      where: {
        status: { in: [BuildStatus.queued, BuildStatus.running] },
        createdAt: { lt: cutoff },
      },
      data: {
        status: BuildStatus.failed,
        promotionStatus: "failed",
        finishedAt,
        testResult: { source: "worker", result: "timeout" },
      },
    }),
    prisma.sourceSnapshot.updateMany({
      where: {
        status: SourceSnapshotStatus.discovered,
        createdAt: { lt: cutoff },
      },
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

function githubHeaders(): HeadersInit {
  const token = process.env.PORTSIDE_GITHUB_TOKEN?.trim();
  return {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

async function fetchWorkflowRuns(): Promise<GitHubWorkflowRun[]> {
  const token = process.env.PORTSIDE_GITHUB_TOKEN?.trim();
  if (!token) return [];
  const url = new URL(
    `https://api.github.com/repos/${repository}/actions/workflows/${workflow}/runs`,
  );
  url.searchParams.set("branch", "main");
  url.searchParams.set("per_page", "20");
  const response = await fetch(url, {
    headers: githubHeaders(),
    signal: AbortSignal.timeout(20_000),
  });
  if (!response.ok) throw new Error(`github_actions_${response.status}`);
  const payload = (await response.json()) as {
    workflow_runs?: GitHubWorkflowRun[];
  };
  return payload.workflow_runs ?? [];
}

async function reconcileWorkflowRuns(): Promise<void> {
  if (!process.env.PORTSIDE_GITHUB_TOKEN?.trim()) {
    console.log(
      JSON.stringify({
        level: "info",
        event: "workflow_sync_disabled",
        reason: "PORTSIDE_GITHUB_TOKEN_not_configured",
      }),
    );
    return;
  }
  const runs = await fetchWorkflowRuns();
  for (const run of runs) {
    const update = workflowRunToBuildUpdate(run);
    const existing = await prisma.runtimeBuild.findUnique({
      where: { workflowRunId: update.workflowRunId },
      select: { promotionStatus: true },
    });
    await prisma.runtimeBuild.upsert({
      where: { workflowRunId: update.workflowRunId },
      update: {
        version: update.version,
        portsideCommit: update.portsideCommit,
        workflowURL: update.workflowURL,
        status: update.status,
        environment: update.environment as Prisma.InputJsonValue,
        testResult: update.testResult as Prisma.InputJsonValue,
        startedAt: update.startedAt,
        finishedAt: update.finishedAt,
      },
      create: {
        version: update.version,
        portsideCommit: update.portsideCommit,
        workflowRunId: update.workflowRunId,
        workflowURL: update.workflowURL,
        status: update.status,
        promotionStatus: existing?.promotionStatus ?? "not_promoted",
        environment: update.environment as Prisma.InputJsonValue,
        testResult: update.testResult as Prisma.InputJsonValue,
        startedAt: update.startedAt,
        finishedAt: update.finishedAt,
      },
    });
  }
  console.log(
    JSON.stringify({
      level: "info",
      event: "workflow_runs_reconciled",
      repository,
      workflow,
      count: runs.length,
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
    await reconcileWorkflowRuns().catch((error: unknown) => {
      console.error(
        JSON.stringify({
          level: "error",
          event: "workflow_sync_failed",
          error: error instanceof Error ? error.name : "workflow_sync_failed",
        }),
      );
    });
    const poller = setInterval(() => {
      reconcileStaleWork().catch((error: unknown) => {
        console.error(
          JSON.stringify({
            level: "error",
            event: "sync_worker_reconcile_failed",
            error: error instanceof Error ? error.name : "reconcile_failed",
          }),
        );
      });
      reconcileWorkflowRuns().catch((error: unknown) => {
        console.error(
          JSON.stringify({
            level: "error",
            event: "workflow_sync_failed",
            error: error instanceof Error ? error.name : "workflow_sync_failed",
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

run().catch((error: unknown) => {
  console.error(
    JSON.stringify({
      level: "error",
      event: "sync_worker_failed",
      error: error instanceof Error ? error.name : "worker_failed",
    }),
  );
  process.exit(1);
});
