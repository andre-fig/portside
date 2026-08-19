import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { ArtifactStatus, Channel } from '@prisma/client';
import { AppConfig } from './config.js';
import { PrismaService } from './prisma.service.js';
import { validateStorageKey } from './source-policy.js';

@Injectable()
export class ArtifactService {
  private readonly s3?: S3Client;
  constructor(private readonly prisma: PrismaService, private readonly config: AppConfig) {
    const s3 = config.s3;
    if (s3.endpoint && s3.bucket && s3.accessKeyId && s3.secretAccessKey) {
      this.s3 = new S3Client({ endpoint: s3.endpoint, region: s3.region, forcePathStyle: s3.forcePathStyle, credentials: { accessKeyId: s3.accessKeyId, secretAccessKey: s3.secretAccessKey } });
    }
  }

  async signedDownload(id: string): Promise<{ url: string; expiresIn: number; sha256: string; size: string }> {
    if (!this.s3 || !this.config.s3.bucket) throw new ServiceUnavailableException('artifact storage is not configured');
    const artifact = await this.prisma.artifact.findUnique({ where: { id } });
    if (!artifact || (artifact.status !== ArtifactStatus.production && artifact.status !== ArtifactStatus.approved)) throw new ServiceUnavailableException('artifact is not available');
    const key = validateStorageKey(artifact.storageKey);
    const expiresIn = 300;
    const url = await getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.config.s3.bucket, Key: key }), { expiresIn });
    return { url, expiresIn, sha256: artifact.sha256, size: artifact.size.toString() };
  }

  async production(component: string, channel: Channel): Promise<unknown> {
    return this.prisma.artifact.findMany({ where: { component, channel, status: ArtifactStatus.production }, orderBy: { promotedAt: 'desc' }, take: 3, select: { id: true, component: true, version: true, sha256: true, size: true, status: true, sourceCommitOrTag: true } });
  }
}
