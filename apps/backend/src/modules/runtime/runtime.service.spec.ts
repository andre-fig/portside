import { describe, expect, it } from "vitest";
import { RuntimeService } from "./runtime.service.js";

describe("RuntimeService", () => {
  it("loads the checked-in appcast", async () => {
    const service = new RuntimeService();

    await expect(service.appcast()).resolves.toContain("<rss");
  });

  it("reports when the production manifest is not published", async () => {
    const service = new RuntimeService();

    await expect(service.manifest()).rejects.toMatchObject({
      response: { statusCode: 503 },
    });
  });
});
