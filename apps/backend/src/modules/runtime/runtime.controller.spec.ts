import { describe, expect, it, vi } from "vitest";
import { RuntimeController } from "./runtime.controller.js";
import type { RuntimeService } from "./runtime.service.js";

describe("RuntimeController", () => {
  it("delegates appcast requests to the runtime service", async () => {
    const appcast = vi.fn().mockResolvedValue("<rss />");
    const manifest = vi.fn();
    const controller = new RuntimeController({ appcast, manifest } as unknown as RuntimeService);

    await expect(controller.appcast()).resolves.toBe("<rss />");
    expect(appcast).toHaveBeenCalledOnce();
  });

  it("delegates manifest requests to the runtime service", async () => {
    const appcast = vi.fn();
    const manifest = vi.fn().mockResolvedValue({ version: "1.0.0" });
    const controller = new RuntimeController({ appcast, manifest } as unknown as RuntimeService);

    await expect(controller.manifest()).resolves.toEqual({ version: "1.0.0" });
    expect(manifest).toHaveBeenCalledOnce();
  });
});
