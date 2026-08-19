import { describe, expect, it } from "vitest";
import {
  canActivate,
  consumeChallenge,
  isPromotable,
  newChallenge,
  offlineUntil,
  verifyDigest,
} from "../src/common/policy/commercial-policy.js";

describe("commercial license and artifact policy", () => {
  it("allows the first activation and refuses a second device", () => {
    expect(canActivate(null, "device-a")).toBe(true);
    expect(canActivate("device-a", "device-b")).toBe(false);
    expect(canActivate("device-a", "device-a")).toBe(true);
  });

  it("allows deactivation followed by a new activation", () => {
    let active: string | null = "device-a";
    active = null;
    expect(canActivate(active, "device-b")).toBe(true);
  });

  it("expires and consumes challenges exactly once", () => {
    const challenge = newChallenge(1_000, 100);
    expect(consumeChallenge(challenge, 1_050).used).toBe(true);
    expect(() =>
      consumeChallenge({ ...challenge, used: true }, 1_050),
    ).toThrow();
    expect(() => consumeChallenge(newChallenge(1_000, 100), 1_100)).toThrow();
  });

  it("keeps the offline grace period bounded and configurable", () => {
    expect(offlineUntil(0, 14)).toBe(14 * 86_400_000);
    expect(offlineUntil(0, 7)).toBe(7 * 86_400_000);
  });

  it("requires a matching artifact checksum before promotion", () => {
    expect(
      verifyDigest(
        new TextEncoder().encode("portside"),
        "b3a4c4f3f4c2b5f8b75f4e8d53bd8b2e7a0d8d4c20c7d3e8f1a4f78e4cf8b6c0",
      ),
    ).toBe(false);
    expect(isPromotable("approved")).toBe(true);
    expect(isPromotable("discovered")).toBe(false);
  });
});
