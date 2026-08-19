import {
  IsBoolean,
  IsISO8601,
  IsObject,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from "class-validator";

export class RegisterSourceSnapshotDto {
  @IsString()
  @Matches(/^[A-Za-z0-9._-]+$/)
  @MinLength(1)
  @MaxLength(120)
  sourceName!: string;

  @IsString()
  @Matches(/^https:\/\//)
  repository!: string;

  @IsString()
  @Matches(/^[a-f0-9]{40}$/i)
  commit!: string;

  @IsOptional()
  @IsISO8601()
  commitDate?: string;

  @IsString()
  @Matches(/^[a-f0-9]{64}$/i)
  snapshotChecksum!: string;

  @IsString()
  @MinLength(1)
  license!: string;

  @IsString()
  @Matches(/^vendor\/[A-Za-z0-9._/-]+$/)
  localPath!: string;

  @IsOptional()
  @IsObject()
  submodules?: Record<string, unknown>;

  @IsBoolean()
  lfsUsed!: boolean;
}
