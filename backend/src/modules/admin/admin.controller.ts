import {
  BadRequestException,
  Body,
  Controller,
  NotFoundException,
  Param,
  Post,
  UseGuards,
} from "@nestjs/common";
import {
  IsEnum,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from "class-validator";
import { randomUUID } from "node:crypto";
import { Channel } from "@prisma/client";
import { AdminGuard } from "../../common/guards/admin.guard.js";
import { PrismaService } from "../../database/prisma.service.js";
import {
  SyncRequest,
  SyncService,
} from "../synchronization/sync.service.js";

class SyncDTO implements Omit<SyncRequest, "idempotencyKey"> {
  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  @MinLength(1)
  @MaxLength(120)
  component!: string;
  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  @MinLength(1)
  @MaxLength(120)
  version!: string;
  @IsEnum(Channel) channel!: Channel;
  @IsString() @Matches(/^https:\/\//) sourceURL!: string;
  @IsOptional() @IsString() sourceRepository?: string;
  @IsOptional() @IsString() sourceCommitOrTag?: string;
  @IsString() @MinLength(1) license!: string;
  @IsString() @Matches(/^[A-Za-z0-9._-]+$/) fileName!: string;
  @IsString() @Matches(/^[a-fA-F0-9]{64}$/) expectedSHA256!: string;
  @IsOptional() @IsString() @Matches(/^[A-Za-z0-9+/=]+$/) signature?: string;
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  signatureKeyId?: string;
  @IsOptional() @IsString() @MinLength(16) idempotencyKey?: string;
}

@Controller("/v1/admin")
@UseGuards(AdminGuard)
export class AdminController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly syncService: SyncService,
  ) {}
  @Post("artifacts/sync") async sync(@Body() body: SyncDTO) {
    return this.syncService.sync({
      ...body,
      idempotencyKey: body.idempotencyKey ?? randomUUID(),
    });
  }
  @Post("artifacts/:id/promote") async promote(@Param("id") id: string) {
    const artifact = await this.prisma.artifact.findUnique({ where: { id } });
    if (!artifact) throw new NotFoundException("artifact not found");
    if (artifact.status !== "approved" && artifact.status !== "verified")
      throw new BadRequestException(
        "artifact must pass approval before promotion",
      );
    return this.prisma.artifact.update({
      where: { id },
      data: { status: "production", promotedAt: new Date() },
    });
  }
  @Post("artifacts/:id/rollback") async rollback(
    @Param("id") id: string,
    @Body() body: { rollbackVersion?: string },
  ) {
    if (!body.rollbackVersion)
      throw new BadRequestException("rollbackVersion is required");
    const target = await this.prisma.artifact.findFirst({
      where: {
        component: (
          await this.prisma.artifact.findUniqueOrThrow({ where: { id } })
        ).component,
        version: body.rollbackVersion,
        channel: "production",
        status: { in: ["approved", "production"] },
      },
    });
    if (!target)
      throw new BadRequestException("rollback target is not approved");
    await this.prisma.artifact.update({
      where: { id },
      data: { status: "deprecated" },
    });
    return this.prisma.artifact.update({
      where: { id: target.id },
      data: { status: "production", promotedAt: new Date() },
    });
  }
  @Post("licenses/:id/revoke") async revoke(
    @Param("id") id: string,
    @Body() body: { reason?: string },
  ) {
    return this.prisma.license.update({
      where: { id },
      data: {
        status: "revoked",
        revokedAt: new Date(),
        activations: {
          updateMany: {
            where: { status: "active" },
            data: { status: "revoked" },
          },
        },
        revocations: {
          create: {
            reason: body.reason ?? "administrative revocation",
            actor: "admin",
          },
        },
      },
    });
  }
}
