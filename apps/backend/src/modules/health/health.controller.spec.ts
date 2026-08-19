import { describe, expect, it, vi } from "vitest";
import { HealthController } from "./health.controller.js";
import type { HealthService } from "./health.service.js";

describe("HealthController", () => {
  it("returns a liveness response without touching the database", () => {
    const health = vi.fn().mockReturnValue({ status: "ok" });
    const ready = vi.fn();
    const controller = new HealthController({ health, ready } as unknown as HealthService);

    expect(controller.health()).toEqual({ status: "ok" });
    expect(health).toHaveBeenCalledOnce();
    expect(ready).not.toHaveBeenCalled();
  });

  it("delegates readiness to the health service", async () => {
    const health = vi.fn();
    const ready = vi.fn().mockResolvedValue({ status: "ready" });
    const controller = new HealthController({ health, ready } as unknown as HealthService);

    await expect(controller.ready()).resolves.toEqual({ status: "ready" });
    expect(ready).toHaveBeenCalledOnce();
  });
});
