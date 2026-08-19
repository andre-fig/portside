import { IsEnum, IsObject, IsOptional, IsString, Matches, MaxLength, MinLength } from "class-validator";
import { Channel } from "@prisma/client";
import type { SyncRequest } from "../../synchronization/dtos/sync-request.dto.js";

export class SyncArtifactDto implements Omit<SyncRequest, "idempotencyKey"> {
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

  @IsEnum(Channel)
  channel!: Channel;

  @IsString()
  @Matches(/^https:\/\//)
  sourceURL!: string;

  @IsOptional()
  @IsString()
  sourceRepository?: string;

  @IsOptional()
  @IsString()
  sourceCommitOrTag?: string;

  @IsOptional()
  @IsString()
  sourceSnapshotId?: string;

  @IsOptional()
  @IsString()
  buildId?: string;

  @IsString()
  @MinLength(1)
  license!: string;

  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  fileName!: string;

  @IsString()
  @Matches(/^[a-fA-F0-9]{64}$/)
  expectedSHA256!: string;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9+/=]+$/)
  signature?: string;

  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  signatureKeyId?: string;

  @IsOptional()
  @IsObject()
  provenance?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  sbom?: Record<string, unknown>;

  @IsOptional()
  @IsString()
  @MinLength(16)
  idempotencyKey?: string;
}
