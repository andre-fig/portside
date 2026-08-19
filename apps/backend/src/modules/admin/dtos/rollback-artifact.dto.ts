import { IsString, MaxLength, MinLength } from "class-validator";

export class RollbackArtifactDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  rollbackVersion!: string;
}
