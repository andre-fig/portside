import { Injectable } from '@nestjs/common';

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required configuration: ${name}`);
  return value;
}

@Injectable()
export class AppConfig {
  readonly nodeEnv = process.env.NODE_ENV ?? 'development';
  readonly port = Number(process.env.PORT ?? 3000);
  readonly publicBaseURL = process.env.PUBLIC_BASE_URL ?? '';
  readonly offlineGraceDays = Number(process.env.OFFLINE_GRACE_DAYS ?? 14);
  readonly maxDownloadBytes = Number(process.env.MAX_DOWNLOAD_BYTES ?? 2_147_483_648);
  readonly allowedSourceHosts = new Set((process.env.ALLOWED_SOURCE_HOSTS ?? '').split(',').map((v) => v.trim()).filter(Boolean));
  readonly artifactHosts = new Set((process.env.PORTSIDE_ARTIFACT_HOSTS ?? '').split(',').map((v) => v.trim()).filter(Boolean));
  readonly upstreamSigningKeys: Record<string, string> = (() => { try { return JSON.parse(process.env.UPSTREAM_SIGNING_KEYS_JSON ?? '{}') as Record<string, string>; } catch { return {}; } })();
  readonly s3 = {
    endpoint: process.env.S3_ENDPOINT,
    region: process.env.S3_REGION ?? 'auto',
    bucket: process.env.S3_BUCKET,
    accessKeyId: process.env.S3_ACCESS_KEY_ID,
    secretAccessKey: process.env.S3_SECRET_ACCESS_KEY,
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true'
  };
  readonly secondaryS3 = {
    endpoint: process.env.SECONDARY_S3_ENDPOINT,
    region: process.env.SECONDARY_S3_REGION ?? 'auto',
    bucket: process.env.SECONDARY_S3_BUCKET,
    accessKeyId: process.env.SECONDARY_S3_ACCESS_KEY_ID,
    secretAccessKey: process.env.SECONDARY_S3_SECRET_ACCESS_KEY,
    forcePathStyle: process.env.SECONDARY_S3_FORCE_PATH_STYLE === 'true'
  };

  adminToken(): string { return required('ADMIN_BEARER_TOKEN'); }
  licenseHMACSecret(): string { return required('LICENSE_HMAC_SECRET'); }
  licensePrivateKey(): string { return required('LICENSE_SIGNING_PRIVATE_KEY_PEM'); }
  licensePublicKey(): string { return required('LICENSE_SIGNING_PUBLIC_KEY_PEM'); }
  licenseKeyId(): string { return required('LICENSE_SIGNING_KEY_ID'); }
  manifestPublicKey(): string { return required('MANIFEST_SIGNING_PUBLIC_KEY'); }

  validateProduction(): void {
    if (this.nodeEnv !== 'production') return;
    if (!this.publicBaseURL.startsWith('https://')) throw new Error('PUBLIC_BASE_URL must use HTTPS in production');
    if (!this.allowedSourceHosts.size) throw new Error('ALLOWED_SOURCE_HOSTS must not be empty in production');
    if (!this.s3.endpoint || !this.s3.bucket || !this.s3.accessKeyId || !this.s3.secretAccessKey) throw new Error('private artifact storage is required in production');
    this.adminToken(); this.licenseHMACSecret(); this.licensePrivateKey(); this.licensePublicKey(); this.licenseKeyId(); this.manifestPublicKey();
  }
}
