import { Controller, Get } from "@nestjs/common";
import { HealthService } from "./health.service.js";

@Controller()
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get("/health")
  health(): { status: string } {
    return this.healthService.health();
  }

  @Get("/ready")
  ready(): Promise<{ status: string }> {
    return this.healthService.ready();
  }
}
