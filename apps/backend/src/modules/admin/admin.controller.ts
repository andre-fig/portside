import {
  Body,
  Controller,
  Param,
  Post,
  UseGuards,
} from "@nestjs/common";
import { AdminGuard } from "../../common/guards/admin.guard.js";
import { AdminService } from "./admin.service.js";
import { RevokeLicenseDto } from "./dtos/revoke-license.dto.js";
import { RollbackArtifactDto } from "./dtos/rollback-artifact.dto.js";
import { SyncArtifactDto } from "./dtos/sync-artifact.dto.js";

@Controller("/v1/admin")
@UseGuards(AdminGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Post("artifacts/sync")
  sync(@Body() body: SyncArtifactDto) {
    return this.adminService.sync(body);
  }

  @Post("artifacts/:id/promote")
  promote(@Param("id") id: string) {
    return this.adminService.promote(id);
  }

  @Post("artifacts/:id/rollback")
  rollback(@Param("id") id: string, @Body() body: RollbackArtifactDto) {
    return this.adminService.rollback(id, body.rollbackVersion);
  }

  @Post("licenses/:id/revoke")
  revoke(@Param("id") id: string, @Body() body: RevokeLicenseDto) {
    return this.adminService.revoke(id, body.reason);
  }
}
