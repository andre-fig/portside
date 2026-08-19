import { Body, Controller, Post } from "@nestjs/common";
import { LicenseService } from "./license.service.js";
import { ActivateLicenseDto } from "./dtos/activate-license.dto.js";
import { ChallengeLicenseDto } from "./dtos/challenge-license.dto.js";
import { DeactivateLicenseDto } from "./dtos/deactivate-license.dto.js";
import { ValidateLicenseDto } from "./dtos/validate-license.dto.js";

@Controller("/v1/licenses")
export class LicenseController {
  constructor(private readonly licenses: LicenseService) {}
  @Post("activate") activate(@Body() body: ActivateLicenseDto) {
    return this.licenses.activate(body);
  }
  @Post("challenge") challenge(@Body() body: ChallengeLicenseDto) {
    return this.licenses.challenge(body);
  }
  @Post("validate") validate(@Body() body: ValidateLicenseDto) {
    return this.licenses.validate(body);
  }
  @Post("deactivate") deactivate(@Body() body: DeactivateLicenseDto) {
    return this.licenses.deactivate(body);
  }
}
