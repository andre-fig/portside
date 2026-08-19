import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { AdminGuard } from "../../common/guards/admin.guard.js";
import { AdminController } from "./admin.controller.js";
import { SynchronizationModule } from "../synchronization/synchronization.module.js";

@Module({
  imports: [CoreModule, SynchronizationModule],
  controllers: [AdminController],
  providers: [AdminGuard],
})
export class AdminModule {}
