CREATE TYPE "AppReleaseStatus" AS ENUM ('draft', 'staging', 'production', 'superseded', 'rolled_back', 'rejected');

CREATE TABLE "AppRelease" (
  "id" TEXT NOT NULL,
  "version" TEXT NOT NULL,
  "build" TEXT NOT NULL,
  "channel" "Channel" NOT NULL,
  "status" "AppReleaseStatus" NOT NULL DEFAULT 'draft',
  "url" TEXT NOT NULL,
  "length" BIGINT NOT NULL,
  "edSignature" TEXT NOT NULL,
  "minimumOSVersion" TEXT NOT NULL,
  "releaseNotesURL" TEXT,
  "releaseNotes" TEXT,
  "pubDate" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "promotedAt" TIMESTAMP(3),
  "rolledBackAt" TIMESTAMP(3),
  CONSTRAINT "AppRelease_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AppRelease_channel_version_key" ON "AppRelease"("channel", "version");
CREATE INDEX "AppRelease_channel_status_pubDate_idx" ON "AppRelease"("channel", "status", "pubDate");
