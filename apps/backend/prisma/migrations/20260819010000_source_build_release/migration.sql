-- Source provenance, reproducible builds and explicit release promotion state.
CREATE TYPE "SourceSnapshotStatus" AS ENUM ('discovered', 'synced', 'verified', 'failed', 'archived');
CREATE TYPE "BuildStatus" AS ENUM ('queued', 'running', 'succeeded', 'failed', 'quarantined');
CREATE TYPE "ReleaseStatus" AS ENUM ('draft', 'staging', 'approved', 'production', 'rolled_back', 'rejected');

ALTER TABLE "Artifact"
  ADD COLUMN "sourceSnapshotId" TEXT,
  ADD COLUMN "buildId" TEXT,
  ADD COLUMN "provenance" JSONB,
  ADD COLUMN "sbom" JSONB;

ALTER TABLE "RuntimeManifest" ADD COLUMN "releaseId" TEXT;

ALTER TABLE "SyncExecution"
  ADD COLUMN "requestedCommit" TEXT,
  ADD COLUMN "sourceSnapshotChecksum" TEXT,
  ADD COLUMN "sourceSnapshotId" TEXT;

CREATE TABLE "SourceSnapshot" (
  "id" TEXT NOT NULL,
  "sourceId" TEXT NOT NULL,
  "commit" TEXT NOT NULL,
  "commitDate" TIMESTAMP(3),
  "snapshotChecksum" TEXT NOT NULL,
  "license" TEXT NOT NULL,
  "localPath" TEXT NOT NULL,
  "submodules" JSONB,
  "lfsUsed" BOOLEAN NOT NULL DEFAULT false,
  "status" "SourceSnapshotStatus" NOT NULL DEFAULT 'discovered',
  "syncedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SourceSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "RuntimeBuild" (
  "id" TEXT NOT NULL,
  "version" TEXT NOT NULL,
  "portsideCommit" TEXT NOT NULL,
  "status" "BuildStatus" NOT NULL DEFAULT 'queued',
  "environment" JSONB NOT NULL,
  "toolchain" JSONB,
  "provenance" JSONB,
  "sbom" JSONB,
  "startedAt" TIMESTAMP(3),
  "finishedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "RuntimeBuild_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "RuntimeRelease" (
  "id" TEXT NOT NULL,
  "version" TEXT NOT NULL,
  "channel" "Channel" NOT NULL,
  "status" "ReleaseStatus" NOT NULL DEFAULT 'draft',
  "buildId" TEXT NOT NULL,
  "manifestVersion" TEXT,
  "manifestURL" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "promotedAt" TIMESTAMP(3),
  "rolledBackAt" TIMESTAMP(3),
  CONSTRAINT "RuntimeRelease_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ReleasePromotion" (
  "id" TEXT NOT NULL,
  "releaseId" TEXT NOT NULL,
  "fromChannel" "Channel",
  "toChannel" "Channel" NOT NULL,
  "actor" TEXT NOT NULL,
  "metadata" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ReleasePromotion_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "ReleaseRollback" (
  "id" TEXT NOT NULL,
  "releaseId" TEXT NOT NULL,
  "targetReleaseId" TEXT NOT NULL,
  "reason" TEXT NOT NULL,
  "actor" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ReleaseRollback_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "_RuntimeBuildToSourceSnapshot" (
  "A" TEXT NOT NULL,
  "B" TEXT NOT NULL,
  CONSTRAINT "_RuntimeBuildToSourceSnapshot_AB_pkey" PRIMARY KEY ("A", "B")
);

CREATE TABLE "_ArtifactToRuntimeRelease" (
  "A" TEXT NOT NULL,
  "B" TEXT NOT NULL,
  CONSTRAINT "_ArtifactToRuntimeRelease_AB_pkey" PRIMARY KEY ("A", "B")
);

CREATE UNIQUE INDEX "SourceSnapshot_sourceId_commit_key" ON "SourceSnapshot"("sourceId", "commit");
CREATE INDEX "SourceSnapshot_sourceId_status_createdAt_idx" ON "SourceSnapshot"("sourceId", "status", "createdAt");
CREATE INDEX "SourceSnapshot_snapshotChecksum_idx" ON "SourceSnapshot"("snapshotChecksum");
CREATE INDEX "RuntimeBuild_status_createdAt_idx" ON "RuntimeBuild"("status", "createdAt");
CREATE INDEX "RuntimeBuild_portsideCommit_idx" ON "RuntimeBuild"("portsideCommit");
CREATE UNIQUE INDEX "RuntimeRelease_channel_version_key" ON "RuntimeRelease"("channel", "version");
CREATE INDEX "RuntimeRelease_channel_status_createdAt_idx" ON "RuntimeRelease"("channel", "status", "createdAt");
CREATE INDEX "ReleasePromotion_releaseId_createdAt_idx" ON "ReleasePromotion"("releaseId", "createdAt");
CREATE INDEX "ReleaseRollback_releaseId_createdAt_idx" ON "ReleaseRollback"("releaseId", "createdAt");
CREATE INDEX "ReleaseRollback_targetReleaseId_createdAt_idx" ON "ReleaseRollback"("targetReleaseId", "createdAt");
CREATE INDEX "_RuntimeBuildToSourceSnapshot_B_index" ON "_RuntimeBuildToSourceSnapshot"("B");
CREATE INDEX "_ArtifactToRuntimeRelease_B_index" ON "_ArtifactToRuntimeRelease"("B");

ALTER TABLE "SourceSnapshot" ADD CONSTRAINT "SourceSnapshot_sourceId_fkey"
  FOREIGN KEY ("sourceId") REFERENCES "UpstreamSource"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "Artifact" ADD CONSTRAINT "Artifact_sourceSnapshotId_fkey"
  FOREIGN KEY ("sourceSnapshotId") REFERENCES "SourceSnapshot"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "Artifact" ADD CONSTRAINT "Artifact_buildId_fkey"
  FOREIGN KEY ("buildId") REFERENCES "RuntimeBuild"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "RuntimeRelease" ADD CONSTRAINT "RuntimeRelease_buildId_fkey"
  FOREIGN KEY ("buildId") REFERENCES "RuntimeBuild"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "RuntimeManifest" ADD CONSTRAINT "RuntimeManifest_releaseId_fkey"
  FOREIGN KEY ("releaseId") REFERENCES "RuntimeRelease"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "ReleasePromotion" ADD CONSTRAINT "ReleasePromotion_releaseId_fkey"
  FOREIGN KEY ("releaseId") REFERENCES "RuntimeRelease"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ReleaseRollback" ADD CONSTRAINT "ReleaseRollback_releaseId_fkey"
  FOREIGN KEY ("releaseId") REFERENCES "RuntimeRelease"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "ReleaseRollback" ADD CONSTRAINT "ReleaseRollback_targetReleaseId_fkey"
  FOREIGN KEY ("targetReleaseId") REFERENCES "RuntimeRelease"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "SyncExecution" ADD CONSTRAINT "SyncExecution_sourceSnapshotId_fkey"
  FOREIGN KEY ("sourceSnapshotId") REFERENCES "SourceSnapshot"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "_RuntimeBuildToSourceSnapshot" ADD CONSTRAINT "_RuntimeBuildToSourceSnapshot_A_fkey"
  FOREIGN KEY ("A") REFERENCES "RuntimeBuild"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "_RuntimeBuildToSourceSnapshot" ADD CONSTRAINT "_RuntimeBuildToSourceSnapshot_B_fkey"
  FOREIGN KEY ("B") REFERENCES "SourceSnapshot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "_ArtifactToRuntimeRelease" ADD CONSTRAINT "_ArtifactToRuntimeRelease_A_fkey"
  FOREIGN KEY ("A") REFERENCES "Artifact"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "_ArtifactToRuntimeRelease" ADD CONSTRAINT "_ArtifactToRuntimeRelease_B_fkey"
  FOREIGN KEY ("B") REFERENCES "RuntimeRelease"("id") ON DELETE CASCADE ON UPDATE CASCADE;
