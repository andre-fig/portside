import {
  BadRequestException,
  Injectable,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from "@nestjs/common";
import {
  ArtifactStatus,
  BuildStatus,
  Channel,
  Prisma,
  ReleaseStatus,
  AppReleaseStatus,
  SourceSnapshotStatus,
} from "@prisma/client";
import { createPublicKey, verify } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { PrismaService } from "../../database/prisma.service.js";
import { RegisterBuildDto } from "./dtos/register-build.dto.js";
import { RegisterReleaseDto } from "./dtos/register-release.dto.js";
import { RegisterSourceSnapshotDto } from "./dtos/register-source-snapshot.dto.js";
import { PublishManifestDto } from "./dtos/publish-manifest.dto.js";
import { RegisterAppReleaseDto } from "./dtos/register-app-release.dto.js";

function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value as Record<string, unknown>)
      // Match the JavaScript default key ordering used by generate_manifest.sh.
      .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
      .map(([key, nested]) => `${JSON.stringify(key)}:${canonicalJSON(nested)}`)
      .join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

@Injectable()
export class RuntimeService {
  constructor(@Optional() private readonly prisma?: PrismaService) {}

  async appcast(): Promise<string> {
    if (this.prisma) {
      try {
        const releases = await this.prisma.appRelease.findMany({
          where: {
            channel: Channel.production,
            status: { in: [AppReleaseStatus.production, AppReleaseStatus.superseded] },
          },
          orderBy: { pubDate: "desc" },
          take: 3,
        });
        if (releases.length > 0) return this.renderAppcast(releases);
      } catch (error) {
        if (process.env.NODE_ENV === "production") throw error;
      }
    }
    if (process.env.NODE_ENV === "production") {
      throw new ServiceUnavailableException("production appcast is not published");
    }
    try {
      return await readFile(join(process.cwd(), "manifests", "appcast.xml"), "utf8");
    } catch {
      throw new ServiceUnavailableException("appcast is not published");
    }
  }

  async registerAppRelease(input: RegisterAppReleaseDto) {
    const prisma = this.requireDatabase();
    if (input.channel !== Channel.production)
      throw new BadRequestException("app releases must use the production channel");
    const url = new URL(input.url);
    const hosts = new Set((process.env.PORTSIDE_APP_HOSTS ?? process.env.PORTSIDE_ARTIFACT_HOSTS ?? "").split(",").map((host) => host.trim()).filter(Boolean));
    for (const value of [process.env.PUBLIC_BASE_URL, process.env.RAILWAY_PUBLIC_DOMAIN]) {
      if (!value) continue;
      try {
        hosts.add(new URL(value.startsWith("http") ? value : `https://${value}`).hostname);
      } catch {
        // Invalid optional host values are ignored; required production hosts are validated elsewhere.
      }
    }
    if (url.protocol !== "https:" || (hosts.size > 0 && !hosts.has(url.hostname)) || url.hostname.includes("example.invalid"))
      throw new BadRequestException("app release URL is not an approved Portside host");
    const pubDate = input.pubDate ? new Date(input.pubDate) : new Date();
    if (Number.isNaN(pubDate.getTime())) throw new BadRequestException("app release date is invalid");
    const existing = await prisma.appRelease.findUnique({
      where: { channel_version: { channel: Channel.production, version: input.version } },
    });
    if (existing) {
      if (existing.url !== input.url || existing.edSignature !== input.edSignature || existing.length !== BigInt(input.length))
        throw new BadRequestException("app release identity conflicts with the existing record");
      return this.appReleaseResponse(existing);
    }
    return prisma.$transaction(async (transaction) => {
      await transaction.appRelease.updateMany({
        where: { channel: Channel.production, status: AppReleaseStatus.production },
        data: { status: AppReleaseStatus.superseded },
      });
      const created = await transaction.appRelease.create({
        data: {
          version: input.version,
          build: input.build,
          channel: Channel.production,
          status: AppReleaseStatus.production,
          url: input.url,
          length: BigInt(input.length),
          edSignature: input.edSignature,
          minimumOSVersion: input.minimumOSVersion,
          releaseNotesURL: input.releaseNotesURL,
          releaseNotes: input.releaseNotes,
          pubDate,
          promotedAt: new Date(),
        },
      });
      return this.appReleaseResponse(created);
    });
  }

  async rollbackAppRelease(id: string, targetReleaseId: string) {
    const prisma = this.requireDatabase();
    const [current, target] = await Promise.all([
      prisma.appRelease.findUnique({ where: { id } }),
      prisma.appRelease.findUnique({ where: { id: targetReleaseId } }),
    ]);
    if (!current || !target) throw new NotFoundException("app release not found");
    if (current.channel !== Channel.production || current.status !== AppReleaseStatus.production || target.channel !== Channel.production || (target.status !== AppReleaseStatus.production && target.status !== AppReleaseStatus.superseded))
      throw new BadRequestException("rollback requires production app releases");
    return prisma.$transaction(async (transaction) => {
      await transaction.appRelease.update({ where: { id }, data: { status: AppReleaseStatus.rolled_back, rolledBackAt: new Date() } });
      await transaction.appRelease.updateMany({ where: { channel: Channel.production, status: AppReleaseStatus.production }, data: { status: AppReleaseStatus.superseded } });
      return transaction.appRelease.update({ where: { id: targetReleaseId }, data: { status: AppReleaseStatus.production, promotedAt: new Date() } });
    });
  }

  async manifest(): Promise<unknown> {
    if (this.prisma) {
      try {
        const published = await this.prisma.runtimeManifest.findFirst({
          where: { channel: Channel.production, status: "published" },
          orderBy: { publishedAt: "desc" },
        });
        if (published) {
          const payload = published.payload as Record<string, unknown>;
          this.validatePublishedManifest(payload, published.channel);
          return {
            ...payload,
            signature: published.signature,
            signatureKeyId: published.signatureKeyId,
          };
        }
      } catch (error) {
        if (process.env.NODE_ENV === "production") throw error;
      }
    }

    if (process.env.NODE_ENV === "production") {
      throw new ServiceUnavailableException(
        "production runtime manifest is not published",
      );
    }
    const path = join(process.cwd(), "manifests", "runtime-manifest.json");
    try {
      const payload = JSON.parse(await readFile(path, "utf8")) as Record<string, unknown>;
      this.validatePublishedManifest(payload, Channel.production);
      return payload;
    } catch {
      throw new ServiceUnavailableException(
        "production runtime manifest is not published",
      );
    }
  }

  async publishManifest(input: PublishManifestDto) {
    const prisma = this.requireDatabase();
    const manifest = { ...input.manifest };
    const signature = typeof manifest.signature === "string" ? manifest.signature : "";
    const signatureKeyId = typeof manifest.signatureKeyId === "string" ? manifest.signatureKeyId : "";
    const manifestVersion = typeof manifest.manifestVersion === "string" ? manifest.manifestVersion : "";
    const minimumPortsideVersion = typeof manifest.minimumPortsideVersion === "string" ? manifest.minimumPortsideVersion : "";
    if (!signature || !signatureKeyId || !manifestVersion || !minimumPortsideVersion)
      throw new BadRequestException("manifest identity and signature are required");
    const configuredKeyID = process.env.MANIFEST_SIGNING_KEY_ID?.trim();
    if (configuredKeyID && configuredKeyID !== signatureKeyId)
      throw new BadRequestException("manifest signing key ID is not configured");
    if (manifest.channel !== input.channel)
      throw new BadRequestException("manifest channel does not match the release channel");
    const components = Array.isArray(manifest.components) ? manifest.components : [];
    if (components.length !== 3)
      throw new BadRequestException("runtime manifest must contain wrapper, engine and winetricks artifacts");
    if (manifest.buildStatus !== input.channel || manifest.builtBy !== "Portside" || typeof manifest.buildId !== "string" || !manifest.buildId)
      throw new BadRequestException("runtime manifest must reference a successful Portside build");
    const artifactHosts = new Set(
      (process.env.PORTSIDE_ARTIFACT_HOSTS ?? "")
        .split(",")
        .map((host) => host.trim())
        .filter(Boolean),
    );
    for (const value of [process.env.PUBLIC_BASE_URL, process.env.RAILWAY_PUBLIC_DOMAIN]) {
      if (!value) continue;
      try {
        artifactHosts.add(new URL(value.startsWith("http") ? value : `https://${value}`).hostname);
      } catch {
        // Invalid optional host values are ignored; required production hosts are validated elsewhere.
      }
    }
    for (const component of components) {
      let downloadURL: URL | null = null;
      if (
        component &&
        typeof component === "object" &&
        typeof (component as Record<string, unknown>).downloadURL === "string"
      ) {
        try {
          downloadURL = new URL(
            (component as Record<string, string>).downloadURL,
          );
        } catch {
          downloadURL = null;
        }
      }
      const sha256 =
        component && typeof component === "object" &&
        typeof (component as Record<string, unknown>).sha256 === "string"
          ? (component as Record<string, string>).sha256
          : "";
      const size =
        component && typeof component === "object" &&
        typeof (component as Record<string, unknown>).size === "number"
          ? (component as Record<string, number>).size
          : 0;
      if (
        (!downloadURL ||
          downloadURL.protocol !== "https:" ||
          !downloadURL.hostname ||
          !artifactHosts.has(downloadURL.hostname) ||
          !/^[a-f0-9]{64}$/i.test(sha256) ||
          !Number.isSafeInteger(size) ||
          size <= 0 ||
          typeof component !== "object" ||
          (component as Record<string, unknown>).builtBy !== "Portside" ||
          typeof (component as Record<string, unknown>).sourcePath !== "string" ||
          typeof (component as Record<string, unknown>).sourceCommit !== "string" ||
          typeof (component as Record<string, unknown>).sourceSnapshotChecksum !== "string" ||
          typeof (component as Record<string, unknown>).license !== "string" ||
          !["wrapper", "engine", "winetricks"].includes(String((component as Record<string, unknown>).component)) ||
          /sikarugir|raw\.githubusercontent\.com|github\.com\/Sikarugir-App/i.test(String((component as Record<string, unknown>).downloadURL)))
      )
        throw new BadRequestException(
          "runtime manifest contains an invalid or non-Portside artifact",
        );
    }
    const unsigned = { ...manifest, signature: null };
    const publicKeyBase64 = process.env.MANIFEST_SIGNING_PUBLIC_KEY?.trim();
    if (!publicKeyBase64) throw new ServiceUnavailableException("manifest signing key is not configured");
    let publicKey: ReturnType<typeof createPublicKey>;
    try {
      const rawKey = Buffer.from(publicKeyBase64, "base64");
      if (rawKey.length !== 32) throw new Error("invalid Ed25519 public key length");
      publicKey = createPublicKey({
        key: Buffer.concat([Buffer.from("302a300506032b6570032100", "hex"), rawKey]),
        format: "der",
        type: "spki",
      });
    } catch {
      throw new BadRequestException("manifest signing key is invalid");
    }
    const valid = verify(
      null,
      Buffer.from(canonicalJSON(unsigned)),
      publicKey,
      Buffer.from(signature, "base64"),
    );
    if (!valid) throw new BadRequestException("manifest signature is invalid");
    if (!input.releaseId) throw new BadRequestException("manifest must reference a release");
    const release = await prisma.runtimeRelease.findUnique({
      where: { id: input.releaseId },
      include: {
        artifacts: {
          select: { component: true, version: true, sha256: true, size: true, fileName: true },
        },
      },
    });
    if (
      !release ||
      input.channel !== Channel.production ||
      release.channel !== Channel.production ||
      release.status !== ReleaseStatus.production
    )
      throw new BadRequestException("manifest release is not eligible for this channel");
    if (
      components.some(
        (component) => {
          if (!component || typeof component !== "object") return true;
          const candidate = component as Record<string, unknown>;
          const size = candidate.size;
          const artifact = release.artifacts.find(
            (registered) =>
              registered.component === candidate.component &&
              registered.version === candidate.version &&
              registered.sha256.toLowerCase() === String(candidate.sha256).toLowerCase() &&
              registered.fileName === String(candidate.downloadURL).split("/").pop() &&
              typeof size === "number" &&
              registered.size === BigInt(size),
          );
          return !artifact;
        },
      )
    )
      throw new BadRequestException("manifest references an artifact outside its release");
    return prisma.$transaction(async (transaction) => {
      await transaction.runtimeManifest.updateMany({
        where: { channel: input.channel, status: "published" },
        data: { status: "superseded" },
      });
      const data = {
        channel: input.channel,
        manifestVersion,
        minimumPortsideVersion,
        payload: unsigned as Prisma.InputJsonValue,
        signature,
        signatureKeyId,
        releaseId: input.releaseId,
        status: "published",
        publishedAt: new Date(),
      };
      const existing = await transaction.runtimeManifest.findUnique({
        where: { channel_manifestVersion: { channel: input.channel, manifestVersion } },
      });
      return existing
        ? transaction.runtimeManifest.update({ where: { id: existing.id }, data })
        : transaction.runtimeManifest.create({ data });
    });
  }

  async registerSourceSnapshot(input: RegisterSourceSnapshotDto) {
    const prisma = this.requireDatabase();
    const source = await prisma.upstreamSource.upsert({
      where: { name: input.sourceName },
      update: {
        repository: input.repository,
        license: input.license,
        allowlisted: true,
      },
      create: {
        name: input.sourceName,
        repository: input.repository,
        license: input.license,
      },
    });
    return prisma.sourceSnapshot.upsert({
      where: { sourceId_commit: { sourceId: source.id, commit: input.commit } },
      update: {
        commitDate: input.commitDate ? new Date(input.commitDate) : undefined,
        snapshotChecksum: input.snapshotChecksum,
        license: input.license,
        localPath: input.localPath,
        submodules: input.submodules as Prisma.InputJsonValue | undefined,
        lfsUsed: input.lfsUsed,
        status: SourceSnapshotStatus.verified,
        syncedAt: new Date(),
      },
      create: {
        sourceId: source.id,
        commit: input.commit,
        commitDate: input.commitDate ? new Date(input.commitDate) : undefined,
        snapshotChecksum: input.snapshotChecksum,
        license: input.license,
        localPath: input.localPath,
        submodules: input.submodules as Prisma.InputJsonValue | undefined,
        lfsUsed: input.lfsUsed,
        status: SourceSnapshotStatus.verified,
        syncedAt: new Date(),
      },
    });
  }

  async registerBuild(input: RegisterBuildDto) {
    const prisma = this.requireDatabase();
    if (input.sourceSnapshotIds.length === 0)
      throw new BadRequestException("a build must reference source snapshots");
    const snapshots = await prisma.sourceSnapshot.findMany({
      where: { id: { in: input.sourceSnapshotIds } },
      select: { id: true, status: true },
    });
    if (snapshots.length !== new Set(input.sourceSnapshotIds).size)
      throw new BadRequestException("one or more source snapshots do not exist");
    if (snapshots.some(({ status }) => status !== SourceSnapshotStatus.verified))
      throw new BadRequestException("all source snapshots must be verified");
    const existingBuild = input.buildId
      ? await prisma.runtimeBuild.findUnique({ where: { id: input.buildId } })
      : input.workflowRunId
        ? await prisma.runtimeBuild.findUnique({ where: { workflowRunId: input.workflowRunId } })
        : null;
    if (existingBuild) {
      if (
        existingBuild.version !== input.version ||
        existingBuild.portsideCommit !== input.portsideCommit ||
        existingBuild.status !== input.status
      )
        throw new BadRequestException("build identity conflicts with the existing record");
      return existingBuild;
    }
    return prisma.runtimeBuild.create({
      data: {
        ...(input.buildId ? { id: input.buildId } : {}),
        version: input.version,
        portsideCommit: input.portsideCommit,
        workflowRunId: input.workflowRunId,
        workflowURL: input.workflowURL,
        status: input.status,
        promotionStatus: "not_promoted",
        environment: input.environment as Prisma.InputJsonValue,
        toolchain: input.toolchain as Prisma.InputJsonValue | undefined,
        provenance: input.provenance as Prisma.InputJsonValue | undefined,
        sbom: input.sbom as Prisma.InputJsonValue | undefined,
        testResult: input.testResult as Prisma.InputJsonValue | undefined,
        startedAt: input.status === BuildStatus.queued ? undefined : new Date(),
        finishedAt:
          input.status === BuildStatus.succeeded || input.status === BuildStatus.failed
            ? new Date()
            : undefined,
        sourceSnapshots: {
          connect: snapshots.map(({ id }) => ({ id })),
        },
      },
    });
  }

  async registerRelease(input: RegisterReleaseDto) {
    const prisma = this.requireDatabase();
    if (input.channel !== Channel.production)
      throw new BadRequestException("runtime releases must use the production channel");
    const build = await prisma.runtimeBuild.findUnique({
      where: { id: input.buildId },
    });
    if (!build) throw new NotFoundException("runtime build not found");
    if (build.status !== BuildStatus.succeeded)
      throw new BadRequestException("only successful builds can create releases");
    const existingRelease = await prisma.runtimeRelease.findUnique({
      where: { channel_version: { channel: Channel.production, version: input.version } },
    });
    if (existingRelease) {
      if (existingRelease.buildId !== input.buildId || existingRelease.status !== ReleaseStatus.production)
        throw new BadRequestException("release identity conflicts with the existing record");
      return existingRelease;
    }
    const artifacts = await prisma.artifact.findMany({
      where: { id: { in: input.artifactIds } },
    });
    if (artifacts.length !== new Set(input.artifactIds).size)
      throw new BadRequestException("one or more release artifacts do not exist");
    if (
      artifacts.some(
        (artifact) =>
          (artifact.status !== ArtifactStatus.verified &&
            artifact.status !== ArtifactStatus.approved) ||
          (artifact.buildId !== null && artifact.buildId !== input.buildId),
      )
    )
      throw new BadRequestException(
        "release artifacts must be verified or approved and belong to the build",
      );
    return prisma.$transaction(async (transaction) => {
      await transaction.artifact.updateMany({
        where: { id: { in: input.artifactIds } },
        data: { buildId: input.buildId },
      });
      await transaction.artifact.updateMany({
        where: { id: { in: input.artifactIds } },
        data: { status: ArtifactStatus.production, promotedAt: new Date() },
      });
      await transaction.runtimeBuild.update({
        where: { id: input.buildId },
        data: { promotionStatus: "production" },
      });
      return transaction.runtimeRelease.create({
        data: {
          version: input.version,
          channel: Channel.production,
          status: ReleaseStatus.production,
          buildId: input.buildId,
          manifestVersion: input.manifestVersion,
          manifestURL: input.manifestURL,
          promotedAt: new Date(),
          artifacts: { connect: input.artifactIds.map((id) => ({ id })) },
        },
      });
    });
  }

  async rollbackRelease(
    id: string,
    targetReleaseId: string,
    reason: string,
    actor = "admin",
  ) {
    const prisma = this.requireDatabase();
    const [release, target] = await Promise.all([
      prisma.runtimeRelease.findUnique({ where: { id }, include: { build: true } }),
      prisma.runtimeRelease.findUnique({
        where: { id: targetReleaseId },
        include: {
          build: true,
          manifests: {
            where: { channel: Channel.production, status: "published" },
            take: 1,
          },
        },
      }),
    ]);
    if (!release || !target) throw new NotFoundException("runtime release not found");
    if (
      release.channel !== Channel.production ||
      release.status !== ReleaseStatus.production ||
      target.channel !== Channel.production ||
      target.status !== ReleaseStatus.production ||
      target.manifests.length === 0
    )
      throw new BadRequestException("rollback requires two production releases");
    return prisma.$transaction(async (transaction) => {
      const rolledBack = await transaction.runtimeRelease.update({
        where: { id },
        data: { status: ReleaseStatus.rolled_back, rolledBackAt: new Date() },
      });
      await transaction.runtimeBuild.update({
        where: { id: release.buildId },
        data: { promotionStatus: "rolled_back" },
      });
      await transaction.runtimeBuild.update({
        where: { id: target.buildId },
        data: { promotionStatus: "production" },
      });
      await transaction.releaseRollback.create({
        data: { releaseId: id, targetReleaseId, reason, actor },
      });
      await transaction.runtimeManifest.updateMany({
        where: { channel: Channel.production, status: "published" },
        data: { status: "superseded" },
      });
      await transaction.runtimeManifest.updateMany({
        where: {
          releaseId: targetReleaseId,
          channel: Channel.production,
          status: "superseded",
        },
        data: { status: "published", publishedAt: new Date() },
      });
      return rolledBack;
    });
  }

  private validatePublishedManifest(payload: Record<string, unknown>, channel: Channel): void {
    const components = Array.isArray(payload.components) ? payload.components : [];
    if (payload.buildStatus !== channel || payload.builtBy !== "Portside" || components.length !== 3)
      throw new ServiceUnavailableException("runtime manifest is not a complete Portside build");
    const names = components.map((component) => component && typeof component === "object" ? String((component as Record<string, unknown>).component) : "").sort();
    if (names.join(",") !== "engine,winetricks,wrapper")
      throw new ServiceUnavailableException("runtime manifest components are incomplete");
  }

  private appReleaseResponse(release: {
    id: string;
    version: string;
    channel: Channel;
    status: AppReleaseStatus;
    length: bigint;
  }) {
    return {
      id: release.id,
      version: release.version,
      channel: release.channel,
      status: release.status,
      length: release.length.toString(),
    };
  }

  private requireDatabase(): PrismaService {
    if (!this.prisma)
      throw new ServiceUnavailableException("database is not configured");
    return this.prisma;
  }

  private renderAppcast(releases: Array<{
    version: string;
    build: string;
    url: string;
    length: bigint;
    edSignature: string;
    minimumOSVersion: string;
    releaseNotesURL: string | null;
    releaseNotes: string | null;
    pubDate: Date;
  }>): string {
    const escape = (value: string) => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
    const items = releases.map((release) => {
      const notes = release.releaseNotesURL ? `<sparkle:releaseNotesLink>${escape(release.releaseNotesURL)}</sparkle:releaseNotesLink>` : release.releaseNotes ? `<description><![CDATA[${release.releaseNotes.replace(/]]>/g, "]]]]><![CDATA[>")}]]></description>` : "";
      return `<item><title>Portside ${escape(release.version)}</title><pubDate>${release.pubDate.toUTCString()}</pubDate>${notes}<enclosure url="${escape(release.url)}" sparkle:version="${escape(release.build)}" sparkle:shortVersionString="${escape(release.version)}" sparkle:minimumSystemVersion="${escape(release.minimumOSVersion)}" sparkle:edSignature="${escape(release.edSignature)}" length="${release.length.toString()}" type="application/octet-stream" /></item>`;
    }).join("");
    const link = process.env.PORTSIDE_APPCAST_URL ?? "https://api-production-6d06.up.railway.app/v1/appcast.xml";
    return `<?xml version="1.0" encoding="utf-8"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Portside</title><link>${escape(link)}</link><description>Portside updates</description><language>en</language>${items}</channel></rss>`;
  }
}
