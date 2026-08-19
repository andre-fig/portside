import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../database/prisma.service.js";

@Injectable()
export class HealthService {
  constructor(private readonly prisma: PrismaService) {}

  health(): { status: string } {
    return { status: "ok" };
  }

  async ready(): Promise<{ status: string }> {
    await this.prisma.$queryRaw`SELECT 1`;
    return { status: "ready" };
  }
}
