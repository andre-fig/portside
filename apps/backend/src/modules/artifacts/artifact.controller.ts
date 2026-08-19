import { Controller, Get, Param } from "@nestjs/common";
import { ArtifactService } from "./artifact.service.js";

@Controller("/v1/artifacts")
export class ArtifactController {
  constructor(private readonly artifacts: ArtifactService) {}

  @Get(":id/download")
  download(
    @Param("id") id: string,
  ): Promise<{ url: string; expiresIn: number; sha256: string; size: string }> {
    return this.artifacts.signedDownload(id);
  }
}
