import { describe, expect, it } from "vitest";
import { BuildStatus } from "@prisma/client";
import { workflowRunToBuildUpdate } from "./workflow-run.js";

const run = {
  id: 123,
  status: "completed",
  conclusion: "success",
  head_sha: "a".repeat(40),
  run_number: 42,
  html_url: "https://github.com/andre-fig/portside/actions/runs/123",
  event: "workflow_dispatch",
  name: "Build Portside Runtime",
  display_title: "runtime version 1.2.3",
  created_at: "2026-08-19T00:00:00Z",
  updated_at: "2026-08-19T00:05:00Z",
  run_started_at: "2026-08-19T00:01:00Z",
} as const;

describe("workflowRunToBuildUpdate", () => {
  it("maps a successful workflow to auditable build metadata", () => {
    const update = workflowRunToBuildUpdate(run);
    expect(update.status).toBe(BuildStatus.succeeded);
    expect(update.version).toBe("1.2.3");
    expect(update.portsideCommit).toBe("a".repeat(40));
    expect(update.workflowRunId).toBe("123");
    expect(update.testResult).toMatchObject({ conclusion: "success" });
    expect(update.finishedAt?.toISOString()).toBe("2026-08-19T00:05:00.000Z");
  });

  it("keeps an in-progress workflow non-publishable", () => {
    const update = workflowRunToBuildUpdate({ ...run, status: "in_progress", conclusion: null });
    expect(update.status).toBe(BuildStatus.running);
    expect(update.finishedAt).toBeUndefined();
    expect(update.testResult).toMatchObject({ status: "in_progress", conclusion: null });
  });
});
