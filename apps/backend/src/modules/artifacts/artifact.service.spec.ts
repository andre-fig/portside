import { describe, expect, it, vi } from "vitest";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { ArtifactService } from "./artifact.service.js";
import type { AppConfig } from "../../core/app-config.js";
import type { PrismaService } from "../../database/prisma.service.js";

vi.mock("@aws-sdk/s3-request-presigner", () => ({
  getSignedUrl: vi.fn(),
}));

describe("ArtifactService runtime downloads", () => {
  const config = {
    runtimeSignedURLTtlSeconds: 300,
    s3: {
      endpoint: "https://storage.example",
      region: "auto",
      bucket: "portside-artifacts",
      accessKeyId: "test-access",
      secretAccessKey: "test-secret",
      forcePathStyle: true,
    },
  } as AppConfig;

  it("signs only the expected private runtime object path", async () => {
    vi.mocked(getSignedUrl).mockResolvedValueOnce(
      "https://storage.example/runtime/production/PortsideWrapper-1.0.0.tar.xz?signature=redacted",
    );
    const service = new ArtifactService({} as PrismaService, config);

    await expect(
      service.signedRuntimeDownload("production", "PortsideWrapper-1.0.0.tar.xz"),
    ).resolves.toEqual({
      url: expect.stringContaining("storage.example"),
      expiresIn: 300,
    });

    const command = vi.mocked(getSignedUrl).mock.calls[0]?.[1] as { input: Record<string, string> };
    expect(command.input).toMatchObject({
      Bucket: "portside-artifacts",
      Key: "runtime/production/PortsideWrapper-1.0.0.tar.xz",
    });
  });

  it("rejects traversal and non-runtime archive names", async () => {
    const service = new ArtifactService({} as PrismaService, config);

    await expect(
      service.signedRuntimeDownload("production", "../../secrets.tar.xz"),
    ).rejects.toThrow("runtime artifact name is invalid");
    await expect(
      service.signedRuntimeDownload("production", "runtime-manifest.json"),
    ).rejects.toThrow("runtime artifact name is invalid");
  });
});
