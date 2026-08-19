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
});
