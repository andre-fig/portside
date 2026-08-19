import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { HealthController } from "./health.controller.js";

@Module({
  imports: [CoreModule],
  controllers: [HealthController],
})
export class HealthModule {}
