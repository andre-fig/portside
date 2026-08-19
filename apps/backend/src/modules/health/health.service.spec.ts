import { describe, expect, it, vi } from "vitest";
import { HealthService } from "./health.service.js";
import type { PrismaService } from "../../database/prisma.service.js";

describe("HealthService", () => {
  it("returns a liveness response without touching the database", () => {
    const queryRaw = vi.fn();
    const service = new HealthService({ $queryRaw: queryRaw } as unknown as PrismaService);

    expect(service.health()).toEqual({ status: "ok" });
    expect(queryRaw).not.toHaveBeenCalled();
  });

  it("checks the database for readiness", async () => {
    const queryRaw = vi.fn().mockResolvedValue([{ ok: 1 }]);
    const service = new HealthService({ $queryRaw: queryRaw } as unknown as PrismaService);

    await expect(service.ready()).resolves.toEqual({ status: "ready" });
    expect(queryRaw).toHaveBeenCalledOnce();
  });
});
