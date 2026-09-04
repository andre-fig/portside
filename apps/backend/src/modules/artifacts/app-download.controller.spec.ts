import { describe, expect, it, vi } from "vitest";
import { AppDownloadController } from "./app-download.controller.js";
import type { ArtifactService } from "./artifact.service.js";

describe("AppDownloadController", () => {
  it("redirects the commercial app archive to a short-lived signed URL", async () => {
    const signedAppDownload = vi.fn().mockResolvedValue({
      url: "https://private-storage.example/app/production/Portside-0.1.11.zip?signature=redacted",
      expiresIn: 300,
    });
    const response = { setHeader: vi.fn(), redirect: vi.fn() };
    const controller = new AppDownloadController({ signedAppDownload } as unknown as ArtifactService);

    await controller.redirect("production", "Portside-0.1.11.zip", response as never);

    expect(signedAppDownload).toHaveBeenCalledWith("production", "Portside-0.1.11.zip");
    expect(response.setHeader).toHaveBeenCalledWith("Cache-Control", "no-store");
    expect(response.redirect).toHaveBeenCalledWith(302, expect.stringContaining("private-storage.example"));
  });

  it("redirects the latest production app to its signed URL", async () => {
    const signedLatestAppDownload = vi.fn().mockResolvedValue({
      url: "https://private-storage.example/app/production/Portside-0.1.22.dmg?signature=redacted",
      expiresIn: 300,
    });
    const response = { setHeader: vi.fn(), redirect: vi.fn() };
    const controller = new AppDownloadController({ signedLatestAppDownload } as unknown as ArtifactService);

    await controller.latest("production", response as never);

    expect(signedLatestAppDownload).toHaveBeenCalledWith("production");
    expect(response.setHeader).toHaveBeenCalledWith("Cache-Control", "no-store");
    expect(response.redirect).toHaveBeenCalledWith(302, expect.stringContaining("private-storage.example"));
  });
});
