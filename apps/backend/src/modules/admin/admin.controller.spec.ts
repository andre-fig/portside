import { describe, expect, it, vi } from "vitest";
import { AdminController } from "./admin.controller.js";
import type { AdminService } from "./admin.service.js";
import { SyncArtifactDto } from "./dtos/sync-artifact.dto.js";
import type { RuntimeService } from "../runtime/runtime.service.js";

describe("AdminController", () => {
  it("generates an idempotency key when syncing an artifact", async () => {
    const sync = vi.fn().mockResolvedValue({ status: "verified" });
    const controller = new AdminController(
      { sync } as unknown as AdminService,
      {} as RuntimeService,
    );
    const body = Object.assign(new SyncArtifactDto(), {
      component: "engine",
      version: "1.0.0",
      channel: "production",
      sourceURL: "https://github.com/example/engine.zip",
      license: "MIT",
      fileName: "engine.zip",
      expectedSHA256: "a".repeat(64),
    });

    await controller.sync(body);

    expect(sync).toHaveBeenCalledWith(body);
  });
});
