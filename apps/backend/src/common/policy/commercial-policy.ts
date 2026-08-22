import { createHash, randomBytes } from "node:crypto";

export type ChallengeState = {
  nonce: string;
  expiresAt: number;
  used: boolean;
};

export function newChallenge(
  now = Date.now(),
  lifetimeMs = 120_000,
): ChallengeState {
  return {
    nonce: randomBytes(32).toString("base64url"),
    expiresAt: now + lifetimeMs,
    used: false,
  };
}

export function consumeChallenge(
  challenge: ChallengeState,
  now = Date.now(),
): ChallengeState {
  if (challenge.used || challenge.expiresAt <= now) {
    throw new Error("challenge expired or already used");
  }
  return { ...challenge, used: true };
}

export function canActivate(
  activeDeviceId: string | null,
  requestedDeviceId: string,
): boolean {
  return activeDeviceId === null || activeDeviceId === requestedDeviceId;
}

export function offlineUntil(now = Date.now(), graceDays = 14): number {
  return now + graceDays * 86_400_000;
}

export function verifyDigest(
  bytes: Uint8Array,
  expectedSHA256: string,
): boolean {
  return (
    createHash("sha256").update(bytes).digest("hex").toLowerCase() ===
    expectedSHA256.toLowerCase()
  );
}

export function isPromotable(status: string): boolean {
  return status === "approved" || status === "verified";
}
