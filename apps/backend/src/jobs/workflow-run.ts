import { BuildStatus } from "@prisma/client";

export type GitHubWorkflowRun = {
  id: number;
  status: string;
  conclusion: string | null;
  head_sha: string;
  run_number: number;
  html_url: string;
  event: string;
  name: string;
  display_title: string;
  created_at: string;
  updated_at: string;
  run_started_at: string | null;
};

export type WorkflowBuildUpdate = {
  workflowRunId: string;
  workflowURL: string;
  version: string;
  portsideCommit: string;
  status: BuildStatus;
  environment: Record<string, unknown>;
  testResult: Record<string, unknown>;
  startedAt: Date;
  finishedAt?: Date;
};

function versionFor(run: GitHubWorkflowRun): string {
  const match = `${run.display_title} ${run.name}`.match(
    /(?:runtime|version)[^0-9]*([0-9][A-Za-z0-9._-]*)/i,
  );
  return match?.[1] ?? `workflow-${run.run_number}`;
}

function statusFor(run: GitHubWorkflowRun): BuildStatus {
  if (run.status === "completed")
    return run.conclusion === "success" ? BuildStatus.succeeded : BuildStatus.failed;
  if (run.status === "in_progress") return BuildStatus.running;
  return BuildStatus.queued;
}

export function workflowRunToBuildUpdate(run: GitHubWorkflowRun): WorkflowBuildUpdate {
  const finished = run.status === "completed" ? new Date(run.updated_at) : undefined;
  return {
    workflowRunId: String(run.id),
    workflowURL: run.html_url,
    version: versionFor(run),
    portsideCommit: run.head_sha,
    status: statusFor(run),
    environment: {
      provider: "github-actions",
      workflow: run.name,
      event: run.event,
      runNumber: run.run_number,
      runId: run.id,
      workflowURL: run.html_url,
    },
    testResult: {
      provider: "github-actions",
      status: run.status,
      conclusion: run.conclusion,
      updatedAt: run.updated_at,
    },
    startedAt: new Date(run.run_started_at ?? run.created_at),
    finishedAt: finished,
  };
}
