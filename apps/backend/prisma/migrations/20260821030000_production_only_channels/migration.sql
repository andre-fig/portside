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

  RAISE NOTICE 'production-only application policy enabled; preserving % legacy release rows for explicit audit/cleanup', legacy_count;
END $$;
