ALTER TABLE "RuntimeBuild"
  ADD COLUMN "workflowRunId" TEXT,
  ADD COLUMN "workflowURL" TEXT,
  ADD COLUMN "promotionStatus" TEXT NOT NULL DEFAULT 'not_promoted',
  ADD COLUMN "testResult" JSONB;

CREATE UNIQUE INDEX "RuntimeBuild_workflowRunId_key"
  ON "RuntimeBuild"("workflowRunId");
