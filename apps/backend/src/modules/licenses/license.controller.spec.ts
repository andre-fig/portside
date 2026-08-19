import { describe, expect, it, vi } from "vitest";
import { LicenseController } from "./license.controller.js";
import type { LicenseService } from "./license.service.js";
import { ActivateLicenseDto } from "./dtos/activate-license.dto.js";

describe("LicenseController", () => {
  it("delegates activation to the license service", async () => {
    const activate = vi.fn().mockResolvedValue({ token: "token" });
    const controller = new LicenseController({ activate } as unknown as LicenseService);
    const body = Object.assign(new ActivateLicenseDto(), {
      licenseKey: "PORT-ABCDEFGH-ABCDEFGH-ABCDEFGH-ABCDEFGH",
      publicKey: "a".repeat(40),
    });

    await controller.activate(body);

    expect(activate).toHaveBeenCalledWith(body);
  });
});
