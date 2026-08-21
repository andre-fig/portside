import {
  IsArray,
  IsEnum,
  IsObject,
  IsOptional,
  IsString,
  IsUrl,
  Matches,
  MaxLength,
  MinLength,
} from "class-validator";
import { BuildStatus } from "@prisma/client";

export class RegisterBuildDto {
  @IsOptional()
  @IsString()
  @Matches(/^[A-Za-z0-9_-]{1,120}$/)
  buildId?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  version!: string;

  @IsString()
  @Matches(/^[a-f0-9]{7,64}$/i)
  portsideCommit!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  workflowRunId?: string;

  @IsOptional()
  @IsUrl({ protocols: ["https"], require_protocol: true })
  workflowURL?: string;

  @IsEnum(BuildStatus)
  status!: BuildStatus;

  @IsObject()
  environment!: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  toolchain?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  provenance?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  sbom?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  testResult?: Record<string, unknown>;

  @IsArray()
  @IsString({ each: true })
  sourceSnapshotIds!: string[];
}
