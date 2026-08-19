import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { RuntimeController } from "./runtime.controller.js";

@Module({
  imports: [CoreModule],
  controllers: [RuntimeController],
})
export class RuntimeModule {}
