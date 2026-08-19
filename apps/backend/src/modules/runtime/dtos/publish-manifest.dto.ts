import { IsEnum, IsObject, IsString, MaxLength, MinLength } from "class-validator";
import { Channel } from "@prisma/client";

export class PublishManifestDto {
  @IsEnum(Channel)
  channel!: Channel;

  @IsObject()
  manifest!: Record<string, unknown>;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  releaseId!: string;
}
