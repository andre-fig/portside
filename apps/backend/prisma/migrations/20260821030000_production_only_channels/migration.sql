BEGIN;

DO $$
DECLARE
  legacy_count bigint;
BEGIN
  SELECT
    (SELECT count(*) FROM "Artifact" WHERE "channel"::text = 'staging') +
    (SELECT count(*) FROM "UpdateChannel" WHERE "channel"::text = 'staging') +
    (SELECT count(*) FROM "RuntimeManifest" WHERE "channel"::text = 'staging') +
    (SELECT count(*) FROM "RuntimeRelease" WHERE "channel"::text = 'staging') +
    (SELECT count(*) FROM "AppRelease" WHERE "channel"::text = 'staging') +
    (SELECT count(*) FROM "ReleasePromotion" WHERE "fromChannel"::text = 'staging' OR "toChannel"::text = 'staging') +
    (SELECT count(*) FROM "RuntimeRelease" WHERE "status"::text = 'staging') +
    (SELECT count(*) FROM "AppRelease" WHERE "status"::text = 'staging')
  INTO legacy_count;

  IF legacy_count > 0 THEN
    RAISE EXCEPTION 'production-only migration blocked: % legacy staging rows require explicit cleanup', legacy_count;
  END IF;
END $$;

ALTER TYPE "Channel" RENAME TO "Channel_legacy";
CREATE TYPE "Channel" AS ENUM ('production');
ALTER TABLE "Artifact" ALTER COLUMN "channel" TYPE "Channel" USING "channel"::text::"Channel";
ALTER TABLE "UpdateChannel" ALTER COLUMN "channel" TYPE "Channel" USING "channel"::text::"Channel";
ALTER TABLE "RuntimeManifest" ALTER COLUMN "channel" TYPE "Channel" USING "channel"::text::"Channel";
ALTER TABLE "RuntimeRelease" ALTER COLUMN "channel" TYPE "Channel" USING "channel"::text::"Channel";
ALTER TABLE "AppRelease" ALTER COLUMN "channel" TYPE "Channel" USING "channel"::text::"Channel";
ALTER TABLE "ReleasePromotion" ALTER COLUMN "fromChannel" TYPE "Channel" USING "fromChannel"::text::"Channel";
ALTER TABLE "ReleasePromotion" ALTER COLUMN "toChannel" TYPE "Channel" USING "toChannel"::text::"Channel";
DROP TYPE "Channel_legacy";

ALTER TYPE "ReleaseStatus" RENAME TO "ReleaseStatus_legacy";
CREATE TYPE "ReleaseStatus" AS ENUM ('draft', 'approved', 'production', 'rolled_back', 'rejected');
ALTER TABLE "RuntimeRelease" ALTER COLUMN "status" TYPE "ReleaseStatus" USING "status"::text::"ReleaseStatus";
DROP TYPE "ReleaseStatus_legacy";

ALTER TYPE "AppReleaseStatus" RENAME TO "AppReleaseStatus_legacy";
CREATE TYPE "AppReleaseStatus" AS ENUM ('draft', 'production', 'superseded', 'rolled_back', 'rejected');
ALTER TABLE "AppRelease" ALTER COLUMN "status" TYPE "AppReleaseStatus" USING "status"::text::"AppReleaseStatus";
DROP TYPE "AppReleaseStatus_legacy";

COMMIT;
