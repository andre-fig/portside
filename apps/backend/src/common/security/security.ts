import {
  createHash,
  createHmac,
  randomBytes,
  sign,
  timingSafeEqual,
} from "node:crypto";

export function hmacHex(secret: string, value: string): string {
  return createHmac("sha256", secret).update(value, "utf8").digest("hex");
}

export function randomToken(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

export function sha256Hex(value: string | Buffer): string {
  return createHash("sha256").update(value).digest("hex");
}

export function safeEqualText(expected: string, actual: string): boolean {
  const a = Buffer.from(expected);
  const b = Buffer.from(actual);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function signLicenseToken(
  payload: Record<string, string | number>,
  privateKey: string,
): string {
  const header = Buffer.from(
    JSON.stringify({ alg: "EdDSA", typ: "PORTSIDE-LICENSE" }),
  ).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const input = `${header}.${body}`;
  const signature = sign(null, Buffer.from(input), privateKey).toString(
    "base64url",
  );
  return `${input}.${signature}`;
}

export function signedTokenInput(token: string): Buffer {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("invalid license token");
  return Buffer.from(`${parts[0]}.${parts[1]}`);
}
