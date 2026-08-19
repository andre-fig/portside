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
import { RegisterBuildDto } from "../runtime/dtos/register-build.dto.js";
import { RegisterReleaseDto } from "../runtime/dtos/register-release.dto.js";
import { RegisterSourceSnapshotDto } from "../runtime/dtos/register-source-snapshot.dto.js";
import { RollbackReleaseDto } from "../runtime/dtos/rollback-release.dto.js";
import { PublishManifestDto } from "../runtime/dtos/publish-manifest.dto.js";
import { RegisterAppReleaseDto } from "../runtime/dtos/register-app-release.dto.js";
import { RuntimeService } from "../runtime/runtime.service.js";

@Controller("/v1/admin")
@UseGuards(AdminGuard)
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly runtimeService: RuntimeService,
  ) {}

  @Post("source-snapshots/register")
  registerSourceSnapshot(@Body() body: RegisterSourceSnapshotDto) {
    return this.runtimeService.registerSourceSnapshot(body);
  }

  @Post("builds/register")
  registerBuild(@Body() body: RegisterBuildDto) {
    return this.runtimeService.registerBuild(body);
  }

  @Post("releases/register")
  registerRelease(@Body() body: RegisterReleaseDto) {
    return this.runtimeService.registerRelease(body);
  }

  @Post("app-releases/register")
  registerAppRelease(@Body() body: RegisterAppReleaseDto) {
    return this.runtimeService.registerAppRelease(body);
  }

  @Post("app-releases/:id/promote")
  promoteAppRelease(@Param("id") id: string) {
    return this.runtimeService.promoteAppRelease(id);
  }

  @Post("app-releases/:id/rollback")
  rollbackAppRelease(@Param("id") id: string, @Body() body: RollbackReleaseDto) {
    return this.runtimeService.rollbackAppRelease(id, body.targetReleaseId);
  }

  @Post("releases/:id/promote")
  promoteRelease(@Param("id") id: string) {
    return this.runtimeService.promoteRelease(id);
  }

  @Post("releases/:id/rollback")
  rollbackRelease(@Param("id") id: string, @Body() body: RollbackReleaseDto) {
    return this.runtimeService.rollbackRelease(id, body.targetReleaseId, body.reason);
  }

  @Post("manifests/publish")
  publishManifest(@Body() body: PublishManifestDto) {
    return this.runtimeService.publishManifest(body);
  }

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
