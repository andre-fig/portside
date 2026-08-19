import { Module } from "@nestjs/common";
import { DatabaseModule } from "../../database/database.module.js";
import { RuntimeController } from "./runtime.controller.js";
import { RuntimeService } from "./runtime.service.js";

@Module({
  imports: [DatabaseModule],
  controllers: [RuntimeController],
  providers: [RuntimeService],
  exports: [RuntimeService],
})
export class RuntimeModule {}
