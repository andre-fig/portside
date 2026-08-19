import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { DatabaseModule } from "../../database/database.module.js";
import { AdminGuard } from "../../common/guards/admin.guard.js";
import { AdminController } from "./admin.controller.js";
import { AdminService } from "./admin.service.js";
import { SynchronizationModule } from "../synchronization/synchronization.module.js";

@Module({
  imports: [CoreModule, DatabaseModule, SynchronizationModule],
  controllers: [AdminController],
  providers: [AdminGuard, AdminService],
})
export class AdminModule {}
