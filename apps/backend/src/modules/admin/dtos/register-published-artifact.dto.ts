import {
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUrl,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from "class-validator";

export class RegisterPublishedArtifactDto {
  @IsString()
  @Matches(/^(wrapper|engine|winetricks)$/)
  component!: string;

  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  @MinLength(1)
  @MaxLength(120)
  version!: string;

  @IsUrl({ protocols: ["https"], require_protocol: true })
  sourceURL!: string;

  @IsString()
  @IsUrl({ protocols: ["https"], require_protocol: true })
  sourceRepository!: string;

  @IsString()
  @Matches(/^[a-f0-9]{40}$/i)
  sourceCommitOrTag!: string;

  @IsString()
  @MinLength(1)
  sourceSnapshotId!: string;

  @IsString()
  @MinLength(1)
  buildId!: string;

  @IsString()
  @MinLength(1)
  license!: string;

  @IsString()
  @Matches(/^[A-Za-z0-9][A-Za-z0-9._-]*\.tar\.xz$/)
  fileName!: string;

  @IsInt()
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  size!: number;

  @IsString()
  @Matches(/^[a-f0-9]{64}$/i)
  expectedSHA256!: string;

  @IsOptional()
  @IsObject()
  provenance?: Record<string, unknown>;

  @IsOptional()
  @IsObject()
  sbom?: Record<string, unknown>;
}
