import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import {
  ArtifactStatus,
  BuildStatus,
  Channel,
  Prisma,
  SourceSnapshotStatus,
} from "@prisma/client";
import { PrismaService } from "../../database/prisma.service.js";
import { SyncService } from "../synchronization/sync.service.js";
import type { SyncRequest } from "../synchronization/dtos/sync-request.dto.js";
import type { RegisterPublishedArtifactDto } from "./dtos/register-published-artifact.dto.js";

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

  async registerPublishedArtifact(input: RegisterPublishedArtifactDto) {
    const artifactPrefix = {
      wrapper: "PortsideWrapper",
      engine: "PortsideWineEngine",
      winetricks: "PortsideWinetricks",
    }[input.component];
    if (!artifactPrefix) {
      throw new BadRequestException("runtime component is not supported");
    }

    const sourceURL = new URL(input.sourceURL);
    const approvedHosts = new Set([
      ...(process.env.PORTSIDE_ARTIFACT_HOSTS ?? "")
        .split(",")
        .map((host) => host.trim())
        .filter(Boolean),
      ...this.portsideServiceHosts(),
    ]);
    if (
      sourceURL.protocol !== "https:" ||
      sourceURL.username ||
      sourceURL.password ||
      !approvedHosts.has(sourceURL.hostname) ||
      sourceURL.pathname !==
        `/v1/runtime/artifacts/production/${input.fileName}` ||
      sourceURL.search ||
      sourceURL.hash
    ) {
      throw new BadRequestException(
        "runtime artifact URL is not an approved Portside route",
      );
    }

    const expectedFileName = `${artifactPrefix}-${input.version}.tar.xz`;
    if (input.fileName !== expectedFileName) {
      throw new BadRequestException(
        "runtime artifact filename does not match its component and version",
      );
    }

    const prisma = this.prisma;
    const [snapshot, build] = await Promise.all([
      prisma.sourceSnapshot.findUnique({
        where: { id: input.sourceSnapshotId },
        include: { source: true },
      }),
      prisma.runtimeBuild.findUnique({
        where: { id: input.buildId },
        include: { sourceSnapshots: { select: { id: true } } },
      }),
    ]);
    if (!snapshot || snapshot.status !== SourceSnapshotStatus.verified) {
      throw new BadRequestException(
        "artifact requires a verified source snapshot",
      );
    }
    if (!build || build.status !== BuildStatus.succeeded) {
      throw new BadRequestException(
        "artifact requires a successful Portside build",
      );
    }
    if (!build.sourceSnapshots.some(({ id }) => id === snapshot.id)) {
      throw new BadRequestException(
        "artifact source snapshot is not attached to its build",
      );
    }
    if (
      snapshot.commit !== input.sourceCommitOrTag ||
      snapshot.source.repository !== input.sourceRepository
    ) {
      throw new BadRequestException(
        "artifact source provenance does not match the registered snapshot",
      );
    }

    const storageKey = `runtime/production/${input.fileName}`;
    const unique = {
      component_version_channel: {
        component: input.component,
        version: input.version,
        channel: Channel.production,
      },
    } as const;
    const existing = await prisma.artifact.findUnique({ where: unique });
    if (existing) {
      if (
        existing.sha256.toLowerCase() !== input.expectedSHA256.toLowerCase() ||
        existing.size !== BigInt(input.size) ||
        (existing.buildId && existing.buildId !== input.buildId) ||
        (existing.sourceSnapshotId &&
          existing.sourceSnapshotId !== input.sourceSnapshotId)
      ) {
        throw new BadRequestException(
          "published artifact identity conflicts with the existing record",
        );
      }
      const updated = await prisma.artifact.update({
        where: { id: existing.id },
        data: {
          sourceURL: input.sourceURL,
          sourceRepository: input.sourceRepository,
          sourceCommitOrTag: input.sourceCommitOrTag,
          license: input.license,
          fileName: input.fileName,
          storageKey,
          sourceSnapshotId: input.sourceSnapshotId,
          buildId: input.buildId,
          provenance: input.provenance as Prisma.InputJsonValue | undefined,
          sbom: input.sbom as Prisma.InputJsonValue | undefined,
          status:
            existing.status === ArtifactStatus.production
              ? ArtifactStatus.production
              : ArtifactStatus.verified,
          verifiedAt: existing.verifiedAt ?? new Date(),
        },
      });
      return { id: updated.id };
    }

    const created = await prisma.artifact.create({
      data: {
        component: input.component,
        version: input.version,
        channel: Channel.production,
        sourceURL: input.sourceURL,
        sourceRepository: input.sourceRepository,
        sourceCommitOrTag: input.sourceCommitOrTag,
        license: input.license,
        fileName: input.fileName,
        size: BigInt(input.size),
        sha256: input.expectedSHA256.toLowerCase(),
        storageKey,
        sourceSnapshotId: input.sourceSnapshotId,
        buildId: input.buildId,
        provenance: input.provenance as Prisma.InputJsonValue | undefined,
        sbom: input.sbom as Prisma.InputJsonValue | undefined,
        status: ArtifactStatus.verified,
        verifiedAt: new Date(),
      },
    });
    return { id: created.id };
  }

  private portsideServiceHosts(): string[] {
    return [process.env.PUBLIC_BASE_URL, process.env.RAILWAY_PUBLIC_DOMAIN]
      .filter((value): value is string => Boolean(value))
      .flatMap((value) => {
        try {
          return [
            new URL(value.startsWith("http") ? value : `https://${value}`)
              .hostname,
          ];
        } catch {
          return [];
        }
      });
  }

  async promote(id: string) {
    const artifact = await this.prisma.artifact.findUnique({
      where: { id },
      include: { sourceSnapshot: true, build: true },
    });
    if (!artifact) throw new NotFoundException("artifact not found");
    if (artifact.status !== "approved" && artifact.status !== "verified") {
      throw new BadRequestException(
        "artifact must pass approval before promotion",
      );
    }
    if (
      !artifact.sourceSnapshot ||
      artifact.sourceSnapshot.status !== "verified" ||
      !artifact.build ||
      artifact.build.status !== "succeeded"
    ) {
      throw new BadRequestException(
        "artifact requires a verified source snapshot and successful Portside build",
      );
    }
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
    if (!target || !target.sourceSnapshotId || !target.buildId) {
      throw new BadRequestException("rollback target is not approved");
    }
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
