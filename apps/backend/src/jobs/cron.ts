import "reflect-metadata";

console.log(
  JSON.stringify({
    level: "info",
    event: "upstream_sync_cron_started",
    at: new Date().toISOString(),
  }),
);
