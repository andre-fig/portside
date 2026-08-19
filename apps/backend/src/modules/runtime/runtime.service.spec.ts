import { describe, expect, it, vi } from "vitest";
import { RuntimeService } from "./runtime.service.js";

describe("RuntimeService", () => {
  it("loads the checked-in appcast", async () => {
    const service = new RuntimeService();

    await expect(service.appcast()).resolves.toContain("<rss");
  });

  it("reports when the production manifest is not published", async () => {
    const previous = process.env.NODE_ENV;
    process.env.NODE_ENV = "production";
    const service = new RuntimeService();

    try {
      await expect(service.manifest()).rejects.toMatchObject({
        response: { statusCode: 503 },
      });
    } finally {
      if (previous === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = previous;
    }
  });

  it("renders only promoted app releases and keeps the current plus two previous versions", async () => {
    const previous = process.env.NODE_ENV;
    process.env.NODE_ENV = "production";
    const appRelease = {
      findMany: vi.fn().mockResolvedValue([
        { version: "1.2.0", build: "120", url: "https://downloads.portside.test/app/1.2.0.zip", length: 120n, edSignature: "sig-120", minimumOSVersion: "13.0", releaseNotesURL: "https://portside.test/releases/1.2.0", releaseNotes: null, pubDate: new Date("2026-08-19T00:00:00Z") },
        { version: "1.1.0", build: "110", url: "https://downloads.portside.test/app/1.1.0.zip", length: 110n, edSignature: "sig-110", minimumOSVersion: "13.0", releaseNotesURL: null, releaseNotes: "Maintenance", pubDate: new Date("2026-08-18T00:00:00Z") },
        { version: "1.0.0", build: "100", url: "https://downloads.portside.test/app/1.0.0.zip", length: 100n, edSignature: "sig-100", minimumOSVersion: "13.0", releaseNotesURL: null, releaseNotes: null, pubDate: new Date("2026-08-17T00:00:00Z") },
      ]),
    };
    const service = new RuntimeService({ appRelease } as never);

    try {
      const feed = await service.appcast();
      expect(appRelease.findMany).toHaveBeenCalledWith(expect.objectContaining({ take: 3 }));
      expect(feed).toContain("sparkle:edSignature=\"sig-120\"");
      expect(feed).toContain("sparkle:edSignature=\"sig-110\"");
      expect(feed).toContain("sparkle:edSignature=\"sig-100\"");
      expect(feed).not.toContain("example.invalid");
    } finally {
      if (previous === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = previous;
    }
  });
});
