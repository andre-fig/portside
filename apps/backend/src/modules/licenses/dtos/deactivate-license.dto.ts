import { IsString, Length } from "class-validator";

export class DeactivateLicenseDto {
  @IsString()
  licenseKey!: string;

  @IsString()
  @Length(1, 128)
  deviceId!: string;
}
