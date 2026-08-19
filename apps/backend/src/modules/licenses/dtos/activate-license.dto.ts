import { IsString, Length, Matches } from "class-validator";

export class ActivateLicenseDto {
  @IsString()
  @Matches(/^PORT-[A-Z0-9-]+$/)
  licenseKey!: string;

  @IsString()
  @Length(40, 512)
  publicKey!: string;
}
