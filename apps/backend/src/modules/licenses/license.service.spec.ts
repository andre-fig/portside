import { generateKeyPairSync } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import { LicenseService } from "./license.service.js";

function devicePublicKey(): string {
  const { publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const spki = publicKey.export({ format: "der", type: "spki" });
  return spki.subarray(-65).toString("base64");
}

function licenseService() {
  const license = {
    id: "lic-1",
    status: "active",
    plan: "standard",
    offlineGraceDays: 14,
  };
  const device = { id: "dev-1" };
  const transaction = {
    license: {
      findUnique: vi.fn().mockResolvedValue(license),
    },
    device: {
      upsert: vi.fn().mockResolvedValue(device),
    },
    activation: {
      findFirst: vi.fn().mockResolvedValue(null),
      upsert: vi.fn().mockResolvedValue({ deviceId: device.id }),
    },
  };
  const prisma = {
    $transaction: vi.fn(async (callback: (tx: typeof transaction) => unknown) => callback(transaction)),
  };
  const { privateKey } = generateKeyPairSync("ed25519");
  const config = {
    licenseHMACSecret: () => "test-hmac-secret",
    licensePrivateKey: () => privateKey.export({ format: "pem", type: "pkcs8" }).toString(),
    licenseKeyId: () => "license-test",
  };
  return { service: new LicenseService(prisma as never, config as never), prisma, transaction };
}

describe("LicenseService activation security", () => {
  it("rejects malformed device keys before touching the database", async () => {
    const { service, prisma } = licenseService();

    await expect(
      service.activate({
        licenseKey: "PORT-ABCDEFGH-ABCDEFGH-ABCDEFGH-ABCDEFGH",
        publicKey: "not-a-p256-key",
      }),
    ).rejects.toThrow("invalid device public key");
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("does not create a device for an unknown license", async () => {
    const { service, transaction } = licenseService();
    transaction.license.findUnique.mockResolvedValue(null);

    await expect(
      service.activate({
        licenseKey: "PORT-ABCDEFGH-ABCDEFGH-ABCDEFGH-ABCDEFGH",
        publicKey: devicePublicKey(),
      }),
    ).rejects.toThrow("license is not active");
    expect(transaction.device.upsert).not.toHaveBeenCalled();
  });

  it("binds activation to a valid P-256 device key", async () => {
    const { service, transaction } = licenseService();

    const result = await service.activate({
      licenseKey: "PORT-ABCDEFGH-ABCDEFGH-ABCDEFGH-ABCDEFGH",
      publicKey: devicePublicKey(),
    });

    expect(result.deviceId).toBe("dev-1");
    expect(transaction.device.upsert).toHaveBeenCalledOnce();
    expect(transaction.activation.upsert).toHaveBeenCalledOnce();
  });
});
