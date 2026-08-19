import { Body, Controller, Post } from '@nestjs/common';
import { IsBase64, IsString, Length, Matches } from 'class-validator';
import { LicenseService } from './license.service.js';

class ActivateDTO { @IsString() @Matches(/^PORT-[A-Z0-9-]+$/) licenseKey!: string; @IsString() @Length(40, 512) publicKey!: string; }
class ChallengeDTO { @IsString() licenseId!: string; @IsString() @Length(1, 256) deviceId!: string; }
class ValidateDTO { @IsString() token!: string; @IsString() challenge!: string; @IsBase64() signature!: string; }
class DeactivateDTO { @IsString() licenseKey!: string; @IsString() @Length(1, 128) deviceId!: string; }

@Controller('/v1/licenses')
export class LicenseController {
  constructor(private readonly licenses: LicenseService) {}
  @Post('activate') activate(@Body() body: ActivateDTO) { return this.licenses.activate(body); }
  @Post('challenge') challenge(@Body() body: ChallengeDTO) { return this.licenses.challenge(body); }
  @Post('validate') validate(@Body() body: ValidateDTO) { return this.licenses.validate(body); }
  @Post('deactivate') deactivate(@Body() body: DeactivateDTO) { return this.licenses.deactivate(body); }
}
