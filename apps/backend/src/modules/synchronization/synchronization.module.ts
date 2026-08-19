import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { DatabaseModule } from "../../database/database.module.js";
import { SyncService } from "./sync.service.js";

@Module({
  imports: [CoreModule, DatabaseModule],
  providers: [SyncService],
  exports: [SyncService],
})
export class SynchronizationModule {}
