import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { SyncService } from "./sync.service.js";

@Module({
  imports: [CoreModule],
  providers: [SyncService],
  exports: [SyncService],
})
export class SynchronizationModule {}
