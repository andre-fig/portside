import { describe, expect, it, vi } from "vitest";
import { RuntimeArtifactController } from "./runtime-artifact.controller.js";
import type { ArtifactService } from "./artifact.service.js";

describe("RuntimeArtifactController", () => {
  it("redirects to the short-lived signed storage URL", async () => {
    const signedRuntimeDownload = vi.fn().mockResolvedValue({
      url: "https://private-storage.example/runtime/staging/PortsideWrapper-1.0.0.tar.xz?signature=redacted",
      expiresIn: 300,
    });
    const response = {
      setHeader: vi.fn(),
      redirect: vi.fn(),
    };
    const controller = new RuntimeArtifactController({ signedRuntimeDownload } as unknown as ArtifactService);

    await controller.redirect(
      "staging",
      "PortsideWrapper-1.0.0.tar.xz",
      response as never,
    );

    expect(signedRuntimeDownload).toHaveBeenCalledWith(
      "staging",
      "PortsideWrapper-1.0.0.tar.xz",
    );
    expect(response.setHeader).toHaveBeenCalledWith("Cache-Control", "no-store");
    expect(response.redirect).toHaveBeenCalledWith(
      302,
      expect.stringContaining("private-storage.example"),
    );
  });
});
