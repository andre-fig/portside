import { IsBase64, IsString } from "class-validator";

export class ValidateLicenseDto {
  @IsString()
  token!: string;

  @IsString()
  challenge!: string;

  @IsBase64()
  signature!: string;
}
