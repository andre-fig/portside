import { IsOptional, IsString, MaxLength } from "class-validator";

export class RevokeLicenseDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}
