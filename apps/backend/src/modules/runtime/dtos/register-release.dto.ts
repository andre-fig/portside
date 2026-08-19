import {
  IsArray,
  IsEnum,
  IsOptional,
  IsString,
  IsUrl,
  MaxLength,
  MinLength,
} from "class-validator";
import { Channel } from "@prisma/client";

export class RegisterReleaseDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  version!: string;

  @IsEnum(Channel)
  channel!: Channel;

  @IsString()
  @MinLength(1)
  buildId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  manifestVersion?: string;

  @IsOptional()
  @IsUrl({ protocols: ["https"], require_protocol: true })
  manifestURL?: string;

  @IsArray()
  @IsString({ each: true })
  artifactIds!: string[];
}
