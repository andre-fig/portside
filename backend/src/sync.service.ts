import { BadRequestException, ConflictException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ArtifactStatus, Channel, SyncStatus } from '@prisma/client';
import { createHash, verify } from 'node:crypto';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { AppConfig } from './config.js';
import { PrismaService } from './prisma.service.js';
import { validateHTTPSHost, validateStorageKey } from './source-policy.js';

export type SyncRequest = {
  component: string;
  version: string;
  channel: Channel;
  sourceURL: string;
  sourceRepository?: string;
  sourceCommitOrTag?: string;
  license: string;
  fileName: string;
  expectedSHA256: string;
  signature?: string;
  signatureKeyId?: string;
  idempotencyKey: string;
};

@Injectable()
export class SyncService {
  private readonly s3?: S3Client;
  private readonly secondaryS3?: S3Client;
  constructor(private readonly prisma: PrismaService, private readonly config: AppConfig) {
    const s3 = config.s3;
    if (s3.endpoint && s3.bucket && s3.accessKeyId && s3.secretAccessKey) this.s3 = new S3Client({ endpoint: s3.endpoint, region: s3.region, forcePathStyle: s3.forcePathStyle, credentials: { accessKeyId: s3.accessKeyId, secretAccessKey: s3.secretAccessKey } });
    const secondary = config.secondaryS3;
    if (secondary.endpoint && secondary.bucket && secondary.accessKeyId && secondary.secretAccessKey) this.secondaryS3 = new S3Client({ endpoint: secondary.endpoint, region: secondary.region, forcePathStyle: secondary.forcePathStyle, credentials: { accessKeyId: secondary.accessKeyId, secretAccessKey: secondary.secretAccessKey } });
  }

  async sync(request: SyncRequest): Promise<{ id: string; status: ArtifactStatus; sha256: string }> {
    if (!/^[a-f0-9]{64}$/i.test(request.expectedSHA256)) throw new BadRequestException('expectedSHA256 must be a SHA-256 digest');
    const existingRun = await this.prisma.syncExecution.findUnique({ where: { idempotencyKey: request.idempotencyKey } });
    if (existingRun?.status === SyncStatus.succeeded) {
      const existing = await this.prisma.artifact.findFirst({ where: { component: request.component, version: request.version, channel: request.channel } });
      if (existing) return { id: existing.id, status: existing.status, sha256: existing.sha256 };
      throw new ConflictException('idempotency record has no artifact');
    }
    const run = existingRun ?? await this.prisma.syncExecution.create({ data: { idempotencyKey: request.idempotencyKey, status: SyncStatus.running } });
    try {
      if (!this.s3 || !this.config.s3.bucket) throw new ServiceUnavailableException('private artifact storage is not configured');
      const source = validateHTTPSHost(request.sourceURL, this.config.allowedSourceHosts);
      const response = await fetch(source, { redirect: 'manual', signal: AbortSignal.timeout(120_000) });
      if (!response.ok || response.status >= 300 && response.status < 400) throw new BadRequestException('upstream response is not a direct successful download');
      const contentLength = Number(response.headers.get('content-length') ?? 0);
      if (contentLength > this.config.maxDownloadBytes) throw new BadRequestException('download exceeds configured size limit');
      const data = Buffer.from(await response.arrayBuffer());
      if (data.length > this.config.maxDownloadBytes) throw new BadRequestException('download exceeds configured size limit');
      const sha256 = createHash('sha256').update(data).digest('hex');
      if (sha256.toLowerCase() !== request.expectedSHA256.toLowerCase()) throw new BadRequestException('checksum mismatch');
      if (request.signature) {
        const key = request.signatureKeyId ? this.config.upstreamSigningKeys[request.signatureKeyId] : undefined;
        if (!key || !verify(null, data, key, Buffer.from(request.signature, 'base64'))) throw new BadRequestException('upstream signature verification failed');
      }
      const storageKey = validateStorageKey(`artifacts/${request.channel}/${request.component}/${request.version}/${request.fileName}`);
      await this.s3.send(new PutObjectCommand({ Bucket: this.config.s3.bucket, Key: storageKey, Body: data, ContentLength: data.length }));
      if (this.secondaryS3 && this.config.secondaryS3.bucket) {
        try { await this.secondaryS3.send(new PutObjectCommand({ Bucket: this.config.secondaryS3.bucket, Key: storageKey, Body: data, ContentLength: data.length })); }
        catch (error) { console.warn(JSON.stringify({ level: 'warn', event: 'secondary_backup_pending', storageKey, error: error instanceof Error ? error.name : 'backup_failed' })); }
      } else {
        console.warn(JSON.stringify({ level: 'warn', event: 'secondary_backup_pending', reason: 'secondary_storage_not_configured' }));
      }
      const artifact = await this.prisma.artifact.upsert({ where: { component_version_channel: { component: request.component, version: request.version, channel: request.channel } }, update: { sourceURL: source.toString(), sourceRepository: request.sourceRepository, sourceCommitOrTag: request.sourceCommitOrTag, license: request.license, fileName: request.fileName, size: BigInt(data.length), sha256, signature: request.signature, storageKey, status: ArtifactStatus.verified, verifiedAt: new Date() }, create: { component: request.component, version: request.version, channel: request.channel, sourceURL: source.toString(), sourceRepository: request.sourceRepository, sourceCommitOrTag: request.sourceCommitOrTag, license: request.license, fileName: request.fileName, size: BigInt(data.length), sha256, signature: request.signature, storageKey, status: ArtifactStatus.verified, verifiedAt: new Date() } });
      await this.prisma.syncExecution.update({ where: { id: run.id }, data: { status: SyncStatus.succeeded, discovered: 1, verified: 1, finishedAt: new Date() } });
      return { id: artifact.id, status: artifact.status, sha256 };
    } catch (error) {
      await this.prisma.syncExecution.update({ where: { id: run.id }, data: { status: SyncStatus.failed, errorCode: error instanceof Error ? error.name : 'sync_failed', finishedAt: new Date() } });
      throw error;
    }
  }
}
