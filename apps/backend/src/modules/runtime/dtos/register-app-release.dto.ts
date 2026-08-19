import { Channel } from "@prisma/client";
import {
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUrl,
  Max,
  MaxLength,
  Min,
  MinLength,
} from "class-validator";

export class RegisterAppReleaseDto {
  @IsString()
  @MinLength(1)
  @MaxLength(64)
  version!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(64)
  build!: string;

  @IsEnum(Channel)
  channel!: Channel;

  @IsUrl({ protocols: ["https"], require_protocol: true })
  url!: string;

  @IsInt()
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  length!: number;

  @IsString()
  @MinLength(1)
  @MaxLength(256)
  edSignature!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(32)
  minimumOSVersion!: string;

  @IsOptional()
  @IsUrl({ protocols: ["https"], require_protocol: true })
  releaseNotesURL?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20_000)
  releaseNotes?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  pubDate?: string;
}
