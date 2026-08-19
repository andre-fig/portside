import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { PrismaService } from "../../database/prisma.service.js";
import { SyncService } from "../synchronization/sync.service.js";
import type { SyncRequest } from "../synchronization/dtos/sync-request.dto.js";

type SyncArtifactInput = Omit<SyncRequest, "idempotencyKey"> & {
  idempotencyKey?: string;
};

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly syncService: SyncService,
  ) {}

  sync(input: SyncArtifactInput) {
    return this.syncService.sync({
      ...input,
      idempotencyKey: input.idempotencyKey ?? randomUUID(),
    });
  }

  async promote(id: string) {
    const artifact = await this.prisma.artifact.findUnique({
      where: { id },
      include: { sourceSnapshot: true, build: true },
    });
    if (!artifact) throw new NotFoundException("artifact not found");
    if (artifact.status !== "approved" && artifact.status !== "verified")
      throw new BadRequestException(
        "artifact must pass approval before promotion",
      );
    if (
      !artifact.sourceSnapshot ||
      artifact.sourceSnapshot.status !== "verified" ||
      !artifact.build ||
      artifact.build.status !== "succeeded"
    )
      throw new BadRequestException(
        "artifact requires a verified source snapshot and successful Portside build",
      );
    return this.prisma.artifact.update({
      where: { id },
      data: { status: "production", promotedAt: new Date() },
    });
  }

  async rollback(id: string, rollbackVersion: string) {
    const current = await this.prisma.artifact.findUniqueOrThrow({
      where: { id },
      include: { sourceSnapshot: true, build: true },
    });
    const target = await this.prisma.artifact.findFirst({
      where: {
        component: current.component,
        version: rollbackVersion,
        channel: "production",
        status: { in: ["approved", "production"] },
      },
    });
    if (
      !target ||
      !target.sourceSnapshotId ||
      !target.buildId
    )
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

  revoke(id: string, reason?: string) {
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
            reason: reason ?? "administrative revocation",
            actor: "admin",
          },
        },
      },
    });
  }
}
