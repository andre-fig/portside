import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { DatabaseModule } from "../../database/database.module.js";
import { ArtifactController } from "./artifact.controller.js";
import { ArtifactService } from "./artifact.service.js";
import { RuntimeArtifactController } from "./runtime-artifact.controller.js";
import { AppDownloadController } from "./app-download.controller.js";

@Module({
  imports: [CoreModule, DatabaseModule],
  controllers: [ArtifactController, RuntimeArtifactController, AppDownloadController],
  providers: [ArtifactService],
  exports: [ArtifactService],
})
export class ArtifactsModule {}
