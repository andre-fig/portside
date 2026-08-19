import { IsString, Length } from "class-validator";

export class ChallengeLicenseDto {
  @IsString()
  licenseId!: string;

  @IsString()
  @Length(1, 256)
  deviceId!: string;
}
