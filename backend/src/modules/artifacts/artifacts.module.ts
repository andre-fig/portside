import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { ArtifactController } from "./artifact.controller.js";
import { ArtifactService } from "./artifact.service.js";

@Module({
  imports: [CoreModule],
  controllers: [ArtifactController],
  providers: [ArtifactService],
  exports: [ArtifactService],
})
export class ArtifactsModule {}
