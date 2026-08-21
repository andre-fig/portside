import { describe, expect, it, vi } from "vitest";
import { AdminService } from "./admin.service.js";
import type { PrismaService } from "../../database/prisma.service.js";
import type { SyncService } from "../synchronization/sync.service.js";

describe("AdminService", () => {
  it("adds an idempotency key before dispatching an artifact sync", async () => {
    const sync = vi.fn().mockResolvedValue({ status: "verified" });
    const service = new AdminService(
      {} as PrismaService,
      { sync } as unknown as SyncService,
    );

    await service.sync({
      component: "engine",
      version: "1.0.0",
      channel: "production",
      sourceURL: "https://github.com/example/engine.zip",
      license: "MIT",
      fileName: "engine.zip",
      expectedSHA256: "a".repeat(64),
    });

    expect(sync).toHaveBeenCalledWith(
      expect.objectContaining({ idempotencyKey: expect.any(String) }),
    );
  });

  it("registers a published production artifact without downloading it again", async () => {
    const previousBaseURL = process.env.PUBLIC_BASE_URL;
    const previousArtifactHosts = process.env.PORTSIDE_ARTIFACT_HOSTS;
    process.env.PUBLIC_BASE_URL = "https://api.portside.test";
    delete process.env.PORTSIDE_ARTIFACT_HOSTS;
    const create = vi.fn().mockResolvedValue({ id: "artifact-1" });
    const prisma = {
      sourceSnapshot: {
        findUnique: vi.fn().mockResolvedValue({
          id: "snapshot-1",
          commit: "a".repeat(40),
          status: "verified",
          source: { repository: "https://github.com/andre-fig/portside" },
        }),
      },
      runtimeBuild: {
        findUnique: vi.fn().mockResolvedValue({
          id: "build-1",
          status: "succeeded",
          sourceSnapshots: [{ id: "snapshot-1" }],
        }),
      },
      artifact: {
        findUnique: vi.fn().mockResolvedValue(null),
        create,
      },
    };

    try {
      const service = new AdminService(
        prisma as unknown as PrismaService,
        {} as SyncService,
      );
      await service.registerPublishedArtifact({
        component: "wrapper",
        version: "0.1.11",
        sourceURL: "https://api.portside.test/v1/runtime/artifacts/production/PortsideWrapper-0.1.11.tar.xz",
        sourceRepository: "https://github.com/andre-fig/portside",
        sourceCommitOrTag: "a".repeat(40),
        sourceSnapshotId: "snapshot-1",
        buildId: "build-1",
        license: "Portside runtime host and template",
        fileName: "PortsideWrapper-0.1.11.tar.xz",
        size: 123,
        expectedSHA256: "b".repeat(64),
      });

      expect(create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            component: "wrapper",
            channel: "production",
            storageKey: "runtime/production/PortsideWrapper-0.1.11.tar.xz",
            buildId: "build-1",
            sourceSnapshotId: "snapshot-1",
          }),
        }),
      );
    } finally {
      if (previousBaseURL === undefined) delete process.env.PUBLIC_BASE_URL;
      else process.env.PUBLIC_BASE_URL = previousBaseURL;
      if (previousArtifactHosts === undefined) delete process.env.PORTSIDE_ARTIFACT_HOSTS;
      else process.env.PORTSIDE_ARTIFACT_HOSTS = previousArtifactHosts;
    }
  });
});
