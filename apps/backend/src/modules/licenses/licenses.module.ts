import { Module } from "@nestjs/common";
import { CoreModule } from "../../core/core.module.js";
import { DatabaseModule } from "../../database/database.module.js";
import { LicenseController } from "./license.controller.js";
import { LicenseService } from "./license.service.js";

@Module({
  imports: [CoreModule, DatabaseModule],
  controllers: [LicenseController],
  providers: [LicenseService],
  exports: [LicenseService],
})
export class LicensesModule {}
