const secretPattern =
  /(password|passwd|token|cookie|sessionid|steamid|authorization|secret)\s*[=:]\s*[^\s,;]+/gi;

export function sanitize(value: unknown): string {
  return String(value ?? "")
    .replace(/\/Users\/[^\s/]+/g, "$USER_HOME")
    .replace(secretPattern, "$1=<redacted>")
    .slice(0, 8_000);
}

export function auditMetadata(
  metadata: Record<string, unknown>,
): Record<string, unknown> {
  const allowed = new Set([
    "component",
    "version",
    "channel",
    "status",
    "reason",
    "count",
    "source",
  ]);
  return Object.fromEntries(
    Object.entries(metadata)
      .filter(([key]) => allowed.has(key))
      .map(([key, value]) => [key, sanitize(value)]),
  );
}
