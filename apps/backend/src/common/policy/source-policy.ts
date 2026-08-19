export function validateHTTPSHost(
  rawURL: string,
  allowedHosts: Set<string>,
): URL {
  const url = new URL(rawURL);
  if (
    url.protocol !== "https:" ||
    !url.hostname ||
    !allowedHosts.has(url.hostname)
  ) {
    throw new Error("source host is not allowlisted for HTTPS download");
  }
  if (url.username || url.password)
    throw new Error("source URL may not contain credentials");
  return url;
}

export function validateStorageKey(key: string): string {
  if (
    !key ||
    key.startsWith("/") ||
    key.includes("..") ||
    key.includes("\\") ||
    // Control characters are invalid in object keys and must be rejected.
    // eslint-disable-next-line no-control-regex
    /[\u0000-\u001f]/.test(key)
  ) {
    throw new Error("unsafe storage key");
  }
  return key;
}
