import { Controller, Get, Param, Res } from "@nestjs/common";
import type { Response } from "express";
import { ArtifactService } from "./artifact.service.js";

@Controller("/app")
export class AppDownloadController {
  constructor(private readonly artifacts: ArtifactService) {}

  @Get(":channel/:fileName")
  async redirect(
    @Param("channel") channel: string,
    @Param("fileName") fileName: string,
    @Res() response: Response,
  ): Promise<void> {
    const signed = await this.artifacts.signedAppDownload(channel, fileName);
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("X-Content-Type-Options", "nosniff");
    response.redirect(302, signed.url);
  }
}
