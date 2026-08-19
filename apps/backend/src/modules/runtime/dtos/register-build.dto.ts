import {
  IsArray,
  IsEnum,
  IsObject,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from "class-validator";
import { BuildStatus } from "@prisma/client";

export class RegisterBuildDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  version!: string;

  @IsString()
  @Matches(/^[a-f0-9]{7,64}$/i)
  portsideCommit!: string;

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

  @IsArray()
  @IsString({ each: true })
  sourceSnapshotIds!: string[];
}
