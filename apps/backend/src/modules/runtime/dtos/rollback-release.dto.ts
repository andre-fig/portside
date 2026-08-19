import { IsString, MaxLength, MinLength } from "class-validator";

export class RollbackReleaseDto {
  @IsString()
  @MinLength(1)
  targetReleaseId!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reason!: string;
}
