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

  it("returns a cache validator and handles a matching conditional request", async () => {
    const appcast = vi.fn().mockResolvedValue("<rss><channel /></rss>");
    const controller = new RuntimeController({ appcast } as unknown as RuntimeService);
    const firstResponse = {
      setHeader: vi.fn(),
      status: vi.fn(),
    };

    const body = await controller.appcast(undefined, firstResponse as never);
    expect(body).toContain("<rss");
    const etag = firstResponse.setHeader.mock.calls.find(([key]) => key === "ETag")?.[1];
    expect(etag).toEqual(expect.any(String));

    const secondResponse = {
      setHeader: vi.fn(),
      status: vi.fn(),
    };
    await expect(
      controller.appcast(
        { headers: { "if-none-match": etag } } as never,
        secondResponse as never,
      ),
    ).resolves.toBe("");
    expect(secondResponse.status).toHaveBeenCalledWith(304);
  });
});
